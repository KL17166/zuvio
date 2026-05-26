import { Request, Response, NextFunction } from 'express';
import { hashPassword, verifyPassword } from '../../security/password';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { z } from 'zod';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { env } from '../../config/env';
import { redisClient } from '../../config/redis';
import fs from 'fs';
import path from 'path';
import {
    runFacialCheck,
    runBiographicalCheck,
} from '../../services/datavalidService';
import { pushToKycStorage } from '../../services/kycStorageService';

// Fix 12: CPF mod-11 algorithm validation
function isValidCpf(cpf: string): boolean {
    if (cpf.length !== 11) return false;
    // Reject sequences of identical digits (000.000.000-00, 111.111.111-11, etc.)
    if (/^(\d)\1{10}$/.test(cpf)) return false;

    let sum = 0;
    for (let i = 0; i < 9; i++) sum += parseInt(cpf[i]) * (10 - i);
    let remainder = (sum * 10) % 11;
    if (remainder === 10 || remainder === 11) remainder = 0;
    if (remainder !== parseInt(cpf[9])) return false;

    sum = 0;
    for (let i = 0; i < 10; i++) sum += parseInt(cpf[i]) * (11 - i);
    remainder = (sum * 10) % 11;
    if (remainder === 10 || remainder === 11) remainder = 0;
    if (remainder !== parseInt(cpf[10])) return false;

    return true;
}

const registerSchema = z.object({
    name: z.string().min(3),
    email: z.string().email(),
    cpf: z.string().transform(cpf => cpf.replace(/\D/g, '')).refine(isValidCpf, "CPF inválido"),
    password: z.string().min(8, "Password must be at least 8 characters"),
    phone: z.string().nullable().optional(),
    birthDate: z.string().transform((str) => new Date(str)), // Expecting ISO string or YYYY-MM-DD
});

const loginSchema = z.object({
    cpf: z.string().transform(cpf => cpf.replace(/\D/g, '')).refine(cpf => cpf.length === 11, "CPF must be 11 digits"),
    password: z.string(),
});

export const register = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const data = registerSchema.parse(req.body);

        const existingUser = await prisma.user.findFirst({
            where: { OR: [{ email: data.email }, { cpf: data.cpf }] },
        });

        if (existingUser) {
            return res.status(409).json({ message: 'User already exists (Email or CPF)' });
        }

        const passwordHash = await hashPassword(data.password);

        const user = await prisma.user.create({
            data: {
                name: data.name,
                email: data.email,
                cpf: data.cpf,
                passwordHash,
                phone: data.phone,
                role: 'CLIENT', // Default
                birthDate: data.birthDate as any,
            },
            select: { id: true, name: true, email: true, cpf: true, role: true, createdAt: true },
        });

        // Log for audit
        await prisma.auditLog.create({
            data: {
                userId: user.id,
                action: 'REGISTER',
                resource: 'user',
                details: JSON.stringify({ email: user.email, cpf: user.cpf }),
                ipAddress: req.ip,
            }
        });

        logger.info(`User registered: ${user.email} (${user.cpf})`);

        res.status(201).json({ message: 'User registered successfully', user });
    } catch (error) {
        next(error);
    }
};

export const login = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { cpf, password } = loginSchema.parse(req.body);

        const user = await prisma.user.findUnique({ where: { cpf } });

        if (!user) {
            return res.status(401).json({ message: 'Invalid credentials' });
        }

        const validPassword = await verifyPassword(password, user.passwordHash);

        if (!validPassword) {
            return res.status(401).json({ message: 'Invalid credentials' });
        }

        // Include a unique JTI (JWT ID) so the token can be individually revoked on logout.
        const jti = crypto.randomUUID();

        const token = jwt.sign(
            { userId: user.id, role: user.role, jti },
            env.JWT_SECRET,
            { algorithm: 'HS256', expiresIn: process.env.JWT_EXPIRES_IN || '1h' } as any
        );

        // ── Per-session signing secret ─────────────────────────────────────────
        // A unique 32-byte secret tied to this login session replaces the static
        // APK-embedded secret for all authenticated requests. Even if an attacker
        // extracts the static secret from the APK, they cannot forge requests on
        // behalf of a logged-in user without also stealing this per-session secret.
        const signingSecret = crypto.randomBytes(32).toString('hex');

        // Store in Redis with the same TTL as the JWT so it expires automatically
        if (redisClient) {
            try {
                const decoded = jwt.decode(token) as any;
                const ttlSeconds = Math.max((decoded?.exp ?? 0) - Math.floor(Date.now() / 1000), 60);
                await redisClient.setEx(`signing:session:${jti}`, ttlSeconds, signingSecret);
            } catch (redisErr) {
                logger.warn('Failed to store session signing secret in Redis — falling back to static secret', { userId: user.id });
            }
        }

        await prisma.auditLog.create({
            data: {
                userId: user.id,
                action: 'LOGIN',
                resource: 'auth',
                ipAddress: req.ip,
            }
        });

        logger.info(`User logged in: ${user.cpf}`);

        // Parse address if exists
        let address = {};
        if (user.address) {
            try {
                address = JSON.parse(user.address);
            } catch (e) {
                logger.error('Failed to parse user address JSON', e);
            }
        }

        res.json({
            token,
            // Per-session signing secret — Flutter stores this securely and uses it
            // instead of the static APK-embedded secret for all subsequent requests.
            signingSecret,
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                role: user.role,
                cpf: user.cpf,
                birthDate: user.birthDate,
                phone: user.phone,
                kycStatus: user.kycStatus,
                kycRejectReason: user.kycRejectReason,
                ...address // Spread address fields (cep, street, etc) into user object
            }
        });
    } catch (error) {
        next(error);
    }
};

// Start of Document Upload & Profile Update Implementation

export const uploadDocument = async (req: Request, res: Response, next: NextFunction) => {
    try {
        if (!req.file) {
            return res.status(400).json({ message: 'No file uploaded' });
        }

        const userId = req.user?.userId || 'unknown';
        const fileUrl = `/public/uploads/documents/${userId}/${req.file.filename}`;

        // ── Serpro Datavalid KYC validation (V4) ──────────────────────────────
        // Datavalid is a government-database validation service, NOT an OCR API.
        // It validates data you already have (CPF, name, face) against RFB/SENATRAN records.
        if (env.DATAVALID_ENABLED) {
            const uploadType = (req.query.type as string) === 'selfie' ? 'selfie' : 'document';

            const user = await prisma.user.findUnique({
                where: { id: userId },
                select: { cpf: true, name: true },
            });
            const userCpf = user?.cpf ?? '';
            const userName = user?.name ?? '';
            const imageBuffer = fs.readFileSync(req.file.path);

            // Sidecar directory: same folder multer wrote the image to
            const kycDir = path.dirname(req.file.path);

            if (uploadType === 'selfie') {
                // ── 1. Facial biometric + liveness check ─────────────────────
                // Submits the selfie + CPF to Datavalid, which compares the face
                // against the government SENATRAN/RENACH biometric photo and runs
                // liveness detection (vivacidade). Endpoint: POST /pf-facial
                const { error: facialErr, rawResponse: facialRaw } =
                    await runFacialCheck(userCpf, imageBuffer);

                // Write sidecar JSON for admin review regardless of pass/fail
                const sidecar = {
                    kycStep: 'facial_check',
                    timestamp: new Date().toISOString(),
                    passed: facialErr === null,
                    errorReason: facialErr?.type === 'validation_failed' ? facialErr.reason : null,
                    rawResponse: facialRaw,
                };
                try {
                    fs.writeFileSync(
                        path.join(kycDir, 'kyc-facial-result.json'),
                        JSON.stringify(sidecar, null, 2),
                    );
                } catch { /* ignore — sidecar is best-effort */ }

                // Fire-and-forget VPS push
                pushToKycStorage({
                    userId,
                    cpf: userCpf,
                    fileType: 'selfie',
                    imageBuffer,
                    imageFilename: req.file.filename,
                    datavalidResult: facialRaw,
                    kycStep: 'facial_check',
                });

                if (facialErr) {
                    // Keep the file — admin may override a failed Datavalid check
                    if (facialErr.type === 'unavailable') {
                        return res.status(503).json({ error: 'Identity verification service unavailable. Try again later.' });
                    }
                    return res.status(403).json({ error: 'Liveness check failed. Possible fraud attempt.' });
                }
            } else {
                // ── 2. Biographical validation against RFB ────────────────────
                // Validates that the CPF + name stored in the user's account match
                // the Receita Federal database. The document image is stored for
                // compliance/audit but Datavalid validates against gov records.
                // Endpoint: POST /pf-basica
                const { error: bioErr, rawResponse: bioRaw } =
                    await runBiographicalCheck(userCpf, userName);

                // Write sidecar JSON for admin review regardless of pass/fail
                const sidecar = {
                    kycStep: 'biographical_check',
                    timestamp: new Date().toISOString(),
                    passed: bioErr === null,
                    errorReason: bioErr?.type === 'validation_failed' ? bioErr.reason : null,
                    rawResponse: bioRaw,
                };
                try {
                    fs.writeFileSync(
                        path.join(kycDir, 'kyc-biographical-result.json'),
                        JSON.stringify(sidecar, null, 2),
                    );
                } catch { /* ignore — sidecar is best-effort */ }

                // Fire-and-forget VPS push
                pushToKycStorage({
                    userId,
                    cpf: userCpf,
                    fileType: 'document',
                    imageBuffer,
                    imageFilename: req.file.filename,
                    datavalidResult: bioRaw,
                    kycStep: 'biographical_check',
                });

                if (bioErr) {
                    // Keep the file — admin may override a failed Datavalid check
                    if (bioErr.type === 'unavailable') {
                        return res.status(503).json({ error: 'Identity verification service unavailable. Try again later.' });
                    }
                    return res.status(403).json({ error: 'Document data does not match account. Possible fraud.' });
                }
            }
        }
        // ─────────────────────────────────────────────────────────────────────

        // Persist the URL to the user record so the admin KYC panel can access it.
        // The upload type determines which field to update.
        // `type=selfie` → selfieUrl, `type=document_back` → documentBackUrl, else → documentFrontUrl
        const queryType = (req.query.type as string) || '';
        const urlField: 'selfieUrl' | 'documentFrontUrl' | 'documentBackUrl' =
            queryType === 'selfie' ? 'selfieUrl'
            : queryType === 'document_back' ? 'documentBackUrl'
            : 'documentFrontUrl';

        const updatedUser = await prisma.user.update({
            where: { id: userId },
            data: { [urlField]: fileUrl },
            select: { selfieUrl: true, documentFrontUrl: true, documentBackUrl: true, kycStatus: true },
        });

        // Auto-advance to SUBMITTED when all three documents are present and KYC is still PENDING
        if (
            updatedUser.selfieUrl &&
            updatedUser.documentFrontUrl &&
            updatedUser.documentBackUrl &&
            updatedUser.kycStatus === 'PENDING'
        ) {
            await prisma.user.update({
                where: { id: userId },
                data: { kycStatus: 'SUBMITTED' },
            });
        }

        res.json({
            message: 'File uploaded successfully',
            url: fileUrl
        });
    } catch (error) {
        next(error);
    }
};

const updateProfileSchema = z.object({
    name: z.string().min(3).optional(),
    phone: z.string().optional(),
    birthDate: z.string().transform((str) => new Date(str)).optional(),
    // Address fields
    cep: z.string().optional(),
    street: z.string().optional(),
    number: z.string().optional(),
    neighborhood: z.string().optional(),
    city: z.string().optional(),
    state: z.string().optional(),
    // Document URLs are intentionally excluded — they may only be set via
    // POST /auth/upload which runs Datavalid KYC validation before storing.
});

export const updateProfile = async (req: Request, res: Response, next: NextFunction) => {
    try {
        if (!req.user) {
            return res.status(401).json({ message: 'Not authenticated' });
        }

        const data = updateProfileSchema.parse(req.body);
        const { name, phone, birthDate, ...addressData } = data as any;

        // Build address JSON object
        let addressJson = null;
        if (Object.keys(addressData).length > 0) {
            addressJson = JSON.stringify(addressData);
        }

        const updateData: any = {};
        if (name) updateData.name = name;
        if (phone) updateData.phone = phone;
        if (birthDate) updateData.birthDate = birthDate;
        if (addressJson) updateData.address = addressJson;

        const user = await prisma.user.update({
            where: { id: req.user.userId },
            data: updateData,
        });

        await prisma.auditLog.create({
            data: {
                userId: user.id,
                action: 'UPDATE_PROFILE',
                resource: 'user',
                details: JSON.stringify(updateData),
                ipAddress: req.ip,
            }
        });

        logger.info(`User profile updated: ${user.cpf}`);

        res.json({
            message: 'Profile updated successfully',
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                role: user.role,
                cpf: user.cpf,
                birthDate: user.birthDate,
                phone: user.phone,
                documentFrontUrl: user.documentFrontUrl,
                documentBackUrl: user.documentBackUrl,
                selfieUrl: user.selfieUrl,
                ...addressData  // address fields (cep, street, etc.)
            }
        });

    } catch (error) {
        next(error);
    }
};

// POST /auth/logout - Client logout
// Blacklists the JWT JTI in Redis so the token is immediately invalid server-side,
// even within its natural expiry window. Also deletes the per-session signing secret
// so any request signed with the old secret is rejected going forward.
export const logout = async (req: Request, res: Response, next: NextFunction) => {
    try {
        // Extract and blacklist the JTI from the current Bearer token
        const authHeader = req.headers.authorization;
        const token = authHeader?.split(' ')[1];

        if (token && redisClient) {
            try {
                const decoded = jwt.decode(token) as any;
                if (decoded?.jti && decoded?.exp) {
                    const ttlSeconds = Math.max(decoded.exp - Math.floor(Date.now() / 1000), 1);
                    // Blacklist: reject any future request carrying this JTI
                    await redisClient.setEx(`jti:blacklist:${decoded.jti}`, ttlSeconds, '1');
                    // Delete the per-session signing secret immediately
                    await redisClient.del(`signing:session:${decoded.jti}`);
                }
            } catch (redisErr) {
                // Log but do not fail the logout — client will discard the token regardless
                logger.warn('Failed to blacklist JTI on logout (Redis unavailable)', { userId: req.user?.userId });
            }
        }

        // Destroy server-side session if present (admin panel fallback)
        if (req.session) {
            req.session.destroy(() => {});
        }

        res.json({ success: true, message: 'Logout realizado com sucesso.' });
    } catch (error) {
        next(error);
    }
};

const changePasswordSchema = z.object({
    currentPassword: z.string().min(1, 'Senha atual é obrigatória'),
    newPassword: z.string().min(8, 'Nova senha deve ter pelo menos 8 caracteres'),
});

// PUT /auth/password - Change password
export const changePassword = async (req: Request, res: Response, next: NextFunction) => {
    try {
        if (!req.user) {
            return res.status(401).json({ message: 'Not authenticated' });
        }

        const data = changePasswordSchema.parse(req.body);

        const user = await prisma.user.findUnique({ where: { id: req.user.userId } });
        if (!user) {
            return res.status(404).json({ message: 'Usuário não encontrado' });
        }

        const validPassword = await verifyPassword(data.currentPassword, user.passwordHash);
        if (!validPassword) {
            return res.status(401).json({ message: 'Senha atual incorreta' });
        }

        const newHash = await hashPassword(data.newPassword);
        await prisma.user.update({
            where: { id: req.user.userId },
            data: { passwordHash: newHash }
        });

        await prisma.auditLog.create({
            data: {
                userId: req.user.userId,
                action: 'CHANGE_PASSWORD',
                resource: 'user',
                ipAddress: req.ip
            }
        });

        logger.info(`Password changed: user ${req.user.userId}`);
        res.json({ success: true, message: 'Senha alterada com sucesso.' });
    } catch (error) {
        next(error);
    }
};

// GET /auth/profile - Token validation & profile fetch (used by Flutter AuthGuard)
export const getProfile = async (req: Request, res: Response, next: NextFunction) => {
    try {
        if (!req.user) {
            return res.status(401).json({ message: 'Not authenticated' });
        }

        const user = await prisma.user.findUnique({
            where: { id: req.user.userId },
            select: {
                id: true,
                name: true,
                email: true,
                cpf: true,
                role: true,
                phone: true,
                birthDate: true,
                documentFrontUrl: true,
                documentBackUrl: true,
                selfieUrl: true,
                kycStatus: true,
                kycRejectReason: true,
                address: true,
                createdAt: true,
            },
        });

        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        let address = {};
        if (user.address) {
            try {
                address = JSON.parse(user.address);
            } catch (e) {
                logger.error('Failed to parse user address JSON', e);
            }
        }

        res.json({
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                role: user.role,
                cpf: user.cpf,
                birthDate: user.birthDate,
                phone: user.phone,
                documentFrontUrl: user.documentFrontUrl,
                documentBackUrl: user.documentBackUrl,
                selfieUrl: user.selfieUrl,
                kycStatus: user.kycStatus,
                kycRejectReason: user.kycRejectReason,
                ...address
            }
        });
    } catch (error) {
        next(error);
    }
};
