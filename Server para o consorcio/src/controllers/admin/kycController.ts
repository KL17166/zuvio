import { Request, Response } from 'express';
import fs from 'fs';
import path from 'path';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { AdminRoles } from '../../config/roles';
import { runFacialCheck, runBiographicalCheck } from '../../services/datavalidService';
import { pushToKycStorage, maskCpf } from '../../services/kycStorageService';

/**
 * KYC Controller — Admin verification of client identity
 * Flow: Client submits docs → Admin reviews → Approve or Reject
 */

// ── Helpers ────────────────────────────────────────────────────────────────────

/** Express 5 types params as string | string[] — always take the scalar value */
function param(v: string | string[]): string {
    return Array.isArray(v) ? v[0] : v;
}

function readSidecar(userId: string, filename: string): Record<string, unknown> | null {
    try {
        const p = path.join(process.cwd(), 'public', 'uploads', 'documents', userId, filename);
        if (!fs.existsSync(p)) return null;
        return JSON.parse(fs.readFileSync(p, 'utf-8')) as Record<string, unknown>;
    } catch {
        return null;
    }
}

function adminRole(req: Request): string {
    return (req as any).session?.user?.role ?? '';
}

function canViewFullData(role: string): boolean {
    return role === AdminRoles.MASTER || role === AdminRoles.MANAGER;
}

// ── GET /admin/kyc — Queue ─────────────────────────────────────────────────────

export const getKycQueue = async (req: Request, res: Response) => {
    try {
        const pendingUsers = await prisma.user.findMany({
            where: {
                role: 'CLIENT',
                kycStatus: 'SUBMITTED',
            },
            include: {
                subscriptions: {
                    where: { status: 'PENDING_KYC' },
                    include: {
                        plan: { include: { product: true } },
                        installments: { where: { number: 1 }, take: 1 },
                    },
                },
            },
            orderBy: { updatedAt: 'desc' },
        });

        const recentlyReviewed = await prisma.user.findMany({
            where: {
                role: 'CLIENT',
                kycStatus: { in: ['APPROVED', 'REJECTED'] },
                kycReviewedAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
            },
            orderBy: { kycReviewedAt: 'desc' },
            take: 20,
        });

        res.render('pages/kyc/index', {
            path: '/kyc',
            pendingUsers,
            recentlyReviewed,
        });
    } catch (error) {
        logger.error('KYC queue error:', error);
        res.status(500).send('Erro ao carregar fila de KYC');
    }
};

// ── GET /admin/kyc/:userId — Detail (role-gated) ───────────────────────────────
/**
 * Access rules:
 *   MASTER / MANAGER — full unmasked CPF, image URLs, full raw Datavalid JSON
 *   SUPPORT          — masked CPF, kycStatus only, no images, no Datavalid result
 */
export const getKycDetail = async (req: Request, res: Response) => {
    try {
        const userId = param(req.params.userId);
        const role = adminRole(req);

        const user = await prisma.user.findUnique({
            where: { id: userId },
            select: {
                id: true,
                name: true,
                email: true,
                cpf: true,
                kycStatus: true,
                kycReviewedAt: true,
                kycReviewedBy: true,
                kycRejectReason: true,
                selfieUrl: true,
                documentFrontUrl: true,
                documentBackUrl: true,
                createdAt: true,
            },
        });

        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }

        const full = canViewFullData(role);

        // Datavalid sidecar results — only exposed to MASTER/MANAGER
        const facialResult   = full ? readSidecar(userId, 'kyc-facial-result.json')       : null;
        const bioResult      = full ? readSidecar(userId, 'kyc-biographical-result.json') : null;

        const payload = {
            id: user.id,
            name: user.name,
            email: user.email,
            cpf: full ? user.cpf : maskCpf(user.cpf),
            kycStatus: user.kycStatus,
            kycReviewedAt: user.kycReviewedAt,
            kycReviewedBy: user.kycReviewedBy,
            kycRejectReason: user.kycRejectReason,
            createdAt: user.createdAt,
            // Images — only MASTER/MANAGER
            selfieUrl:         full ? user.selfieUrl         : undefined,
            documentFrontUrl:  full ? user.documentFrontUrl  : undefined,
            documentBackUrl:   full ? user.documentBackUrl   : undefined,
            // Datavalid raw results — only MASTER/MANAGER
            datavalid: full ? { facial: facialResult, biographical: bioResult } : undefined,
            // Caller's role so the frontend can adapt its UI
            viewerRole: role,
        };

        res.json(payload);
    } catch (error) {
        logger.error('KYC detail error:', error);
        res.status(500).json({ error: 'Erro ao carregar detalhes do KYC' });
    }
};

// ── POST /admin/kyc/:userId/approve ───────────────────────────────────────────

export const approveKyc = async (req: Request, res: Response) => {
    try {
        const userId = param(req.params.userId);
        const adminId = (req as any).session?.user?.id || 'unknown';

        await prisma.user.update({
            where: { id: userId },
            data: {
                kycStatus: 'APPROVED',
                kycReviewedAt: new Date(),
                kycReviewedBy: adminId,
                kycRejectReason: null,
            },
        });

        const pendingSubscriptions = await prisma.subscription.findMany({
            where: { userId, status: 'PENDING_KYC' },
        });

        for (const sub of pendingSubscriptions) {
            await prisma.subscription.update({
                where: { id: sub.id },
                data: { status: 'ACTIVE' },
            });
        }

        logger.info(`KYC APPROVED: user ${userId} by admin ${adminId}. Activated ${pendingSubscriptions.length} subscriptions.`);

        (req as any).flash?.('success', `KYC aprovado! ${pendingSubscriptions.length} contrato(s) ativado(s).`);
        res.redirect('/admin/kyc');
    } catch (error) {
        logger.error('KYC approve error:', error);
        (req as any).flash?.('error', 'Erro ao aprovar KYC');
        res.redirect('/admin/kyc');
    }
};

// ── POST /admin/kyc/:userId/reject ────────────────────────────────────────────

export const rejectKyc = async (req: Request, res: Response) => {
    try {
        const userId = param(req.params.userId);
        const adminId = (req as any).session?.user?.id || 'unknown';
        const { reason } = req.body;

        await prisma.user.update({
            where: { id: userId },
            data: {
                kycStatus: 'REJECTED',
                kycReviewedAt: new Date(),
                kycReviewedBy: adminId,
                kycRejectReason: reason || 'Documentos inválidos ou ilegíveis',
            },
        });

        const pendingSubscriptions = await prisma.subscription.findMany({
            where: { userId, status: 'PENDING_KYC' },
            include: { installments: { where: { status: 'PAID' } } },
        });

        let refundTotal = 0;
        for (const sub of pendingSubscriptions) {
            await prisma.subscription.update({
                where: { id: sub.id },
                data: { status: 'CANCELLED' },
            });

            for (const inst of sub.installments) {
                await prisma.installment.update({
                    where: { id: inst.id },
                    data: {
                        status: 'REFUNDED',
                        paymentMethod: `REFUND_${inst.paymentMethod || 'MANUAL'}`,
                    },
                });
                refundTotal += Number(inst.amount);
            }
        }

        logger.info(`KYC REJECTED: user ${userId} by admin ${adminId}. Reason: ${reason}. Cancelled ${pendingSubscriptions.length} subscriptions. Refund total: R$${refundTotal.toFixed(2)}`);

        (req as any).flash?.('success', `KYC rejeitado. ${pendingSubscriptions.length} contrato(s) cancelado(s). Reembolso total: R$${refundTotal.toFixed(2)}`);
        res.redirect('/admin/kyc');
    } catch (error) {
        logger.error('KYC reject error:', error);
        (req as any).flash?.('error', 'Erro ao rejeitar KYC');
        res.redirect('/admin/kyc');
    }
};

// ── POST /admin/kyc/:userId/override — Manual override (MASTER/MANAGER only) ──
/**
 * Manually approve or reject KYC regardless of the Datavalid result.
 * Body: { action: 'approve' | 'reject', reason?: string }
 *
 * A failed Datavalid check never permanently blocks a user — MASTER/MANAGER
 * can always call this endpoint to override it.
 */
export const overrideKyc = async (req: Request, res: Response) => {
    try {
        const userId = param(req.params.userId);
        const adminId = (req as any).session?.user?.id || 'unknown';
        const { action, reason } = req.body as { action: string; reason?: string };

        if (action !== 'approve' && action !== 'reject') {
            return res.status(400).json({ error: 'action must be "approve" or "reject"' });
        }

        const overrideNote = `Manual override by ${adminId}${reason ? `: ${reason}` : ''}`;

        if (action === 'approve') {
            await prisma.user.update({
                where: { id: userId },
                data: {
                    kycStatus: 'APPROVED',
                    kycReviewedAt: new Date(),
                    kycReviewedBy: adminId,
                    kycRejectReason: null,
                },
            });

            const pendingSubscriptions = await prisma.subscription.findMany({
                where: { userId, status: 'PENDING_KYC' },
            });

            for (const sub of pendingSubscriptions) {
                await prisma.subscription.update({
                    where: { id: sub.id },
                    data: { status: 'ACTIVE' },
                });
            }

            logger.info(`KYC OVERRIDE APPROVED: user ${userId}. ${overrideNote}. Activated ${pendingSubscriptions.length} subscriptions.`);
            return res.json({ ok: true, kycStatus: 'APPROVED', activatedSubscriptions: pendingSubscriptions.length });
        }

        // action === 'reject'
        await prisma.user.update({
            where: { id: userId },
            data: {
                kycStatus: 'REJECTED',
                kycReviewedAt: new Date(),
                kycReviewedBy: adminId,
                kycRejectReason: overrideNote,
            },
        });

        logger.info(`KYC OVERRIDE REJECTED: user ${userId}. ${overrideNote}.`);
        return res.json({ ok: true, kycStatus: 'REJECTED' });
    } catch (error) {
        logger.error('KYC override error:', error);
        res.status(500).json({ error: 'Erro ao processar override de KYC' });
    }
};

// ── POST /admin/kyc/:userId/retrigger — Re-run Datavalid (MASTER/MANAGER only) ─
/**
 * Re-triggers Datavalid validation using the user's currently stored files.
 * Updates the JSON sidecar and pushes a new copy to VPS.
 * Body: { step: 'facial' | 'biographical' }
 */
export const retriggerKyc = async (req: Request, res: Response) => {
    try {
        const userId = param(req.params.userId);
        const { step } = req.body as { step: string };

        if (step !== 'facial' && step !== 'biographical') {
            return res.status(400).json({ error: 'step must be "facial" or "biographical"' });
        }

        const user = await prisma.user.findUnique({
            where: { id: userId },
            select: { cpf: true, name: true, selfieUrl: true, documentFrontUrl: true },
        });

        if (!user) return res.status(404).json({ error: 'User not found' });

        const kycDir = path.join(process.cwd(), 'public', 'uploads', 'documents', userId);

        if (step === 'facial') {
            if (!user.selfieUrl) {
                return res.status(422).json({ error: 'No selfie on record for this user' });
            }
            const selfieDiskPath = path.join(process.cwd(), user.selfieUrl.replace(/^\//, ''));
            if (!fs.existsSync(selfieDiskPath)) {
                return res.status(422).json({ error: 'Selfie file not found on disk' });
            }

            const imageBuffer = fs.readFileSync(selfieDiskPath);
            const { error, rawResponse } = await runFacialCheck(user.cpf, imageBuffer);

            const sidecar = {
                kycStep: 'facial_check',
                timestamp: new Date().toISOString(),
                retriggeredBy: (req as any).session?.user?.id,
                passed: error === null,
                errorReason: error?.type === 'validation_failed' ? error.reason : null,
                rawResponse,
            };

            fs.writeFileSync(
                path.join(kycDir, 'kyc-facial-result.json'),
                JSON.stringify(sidecar, null, 2),
            );

            pushToKycStorage({
                userId,
                cpf: user.cpf,
                fileType: 'selfie',
                imageBuffer,
                imageFilename: path.basename(selfieDiskPath),
                datavalidResult: rawResponse,
                kycStep: 'facial_check',
            });

            logger.info(`KYC retrigger facial: user ${userId}, passed=${error === null}`);
            return res.json({ passed: error === null, errorReason: sidecar.errorReason, rawResponse });
        }

        // step === 'biographical'
        const { error, rawResponse } = await runBiographicalCheck(user.cpf, user.name ?? '');

        const sidecar = {
            kycStep: 'biographical_check',
            timestamp: new Date().toISOString(),
            retriggeredBy: (req as any).session?.user?.id,
            passed: error === null,
            errorReason: error?.type === 'validation_failed' ? error.reason : null,
            rawResponse,
        };

        fs.writeFileSync(
            path.join(kycDir, 'kyc-biographical-result.json'),
            JSON.stringify(sidecar, null, 2),
        );

        // No image file for biographical (it's a pure DB-data check) — skip VPS image push
        logger.info(`KYC retrigger biographical: user ${userId}, passed=${error === null}`);
        return res.json({ passed: error === null, errorReason: sidecar.errorReason, rawResponse });
    } catch (error) {
        logger.error('KYC retrigger error:', error);
        res.status(500).json({ error: 'Erro ao re-executar validação Datavalid' });
    }
};
