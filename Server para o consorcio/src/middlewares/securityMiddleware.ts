import { Request, Response, NextFunction } from 'express';
import { prisma } from '../config/database';
import { logger } from '../config/logger';
import { isAuthenticatedAdmin } from '../security/adminAuth';

// ========================================
// THREAT SCORE CONFIGURATION
// ========================================
const THREAT_SCORES = {
    HONEYPOT: 100,      // Bloqueio imediato
    INJECTION: 50,
    IDOR: 30,
    INVALID_TOKEN: 10,
    RATE_LIMIT: 20,
    BRUTE_FORCE: 40,
    SUSPICIOUS_PATTERN: 25,
    SCANNER: 60,        // Automated vulnerability scanners
};

const BLOCK_THRESHOLD = 100;

// ========================================
// HONEYPOT ROUTES - Rotas falsas para pegar atacantes
// ========================================
export const HONEYPOT_ROUTES = [
    // API endpoints
    '/api/admin/users',
    '/api/admin/all',
    '/api/backup/database',
    '/api/backup/db',
    '/api/debug/sql',
    '/api/debug/query',
    '/api/.env',
    '/api/config/secrets',
    '/api/config/keys',
    '/api/internal/admin',
    '/api/v1/admin/users',
    '/api/users/all',
    '/api/dump',
    '/api/export/users',
    '/api/db/export',
    // Common scanner targets
    '/wp-admin',
    '/wp-login.php',
    '/wp-content',
    '/phpmyadmin',
    '/phpMyAdmin',
    '/administrator',
    '/.git/config',
    '/.git/HEAD',
    '/.env',
    '/.env.local',
    '/.env.production',
    '/actuator',
    '/actuator/health',
    '/debug/pprof',
    '/server-status',
    '/server-info',
    '/elmah.axd',
    '/telescope',
    '/graphql',
];

// ========================================
// HELPER FUNCTIONS
// ========================================

function getClientIP(req: Request): string {
    const forwarded = req.headers['x-forwarded-for'];
    if (forwarded) {
        return (typeof forwarded === 'string' ? forwarded : forwarded[0]).split(',')[0].trim();
    }
    return req.socket.remoteAddress || req.ip || 'unknown';
}

function getDeviceInfo(req: Request) {
    return {
        deviceId: req.headers['x-device-id'] as string || null,
        deviceModel: req.headers['x-device-model'] as string || null,
        userAgent: req.headers['user-agent'] || null
    };
}

// detectInjectionPatterns removida — o WAF (wafMiddleware.ts) já cobre
// XSS, SQLi, path traversal, command injection, SSRF, SSTI de forma mais completa.

function sanitizeForLog(body: any): string {
    if (!body) return '';
    const sanitized = { ...body };
    // Remove senhas do log
    if (sanitized.password) sanitized.password = '[REDACTED]';
    if (sanitized.passwordHash) sanitized.passwordHash = '[REDACTED]';
    return JSON.stringify(sanitized).substring(0, 500);
}

// ========================================
// CHECK IF DEVICE/IP IS BLOCKED
// ========================================
async function isBlocked(ip: string, deviceId: string | null): Promise<boolean> {
    const blocked = await prisma.blockedDevice.findFirst({
        where: {
            active: true,
            OR: [
                { ipAddress: ip },
                ...(deviceId ? [{ deviceId }] : [])
            ]
        }
    });
    return !!blocked;
}

// ========================================
// LOG THREAT AND CHECK FOR BLOCK
// ========================================
async function logThreat(
    req: Request,
    threatType: string,
    threatScore: number,
    details?: string
): Promise<boolean> {
    const ip = getClientIP(req);
    const { deviceId, deviceModel, userAgent } = getDeviceInfo(req);

    // Log threat
    await prisma.securityThreat.create({
        data: {
            ipAddress: ip,
            deviceId,
            deviceModel,
            userId: (req as any).user?.userId || null,
            threatType,
            threatScore,
            requestPath: req.path,
            requestMethod: req.method,
            userAgent,
            details,
            blocked: threatScore >= BLOCK_THRESHOLD
        }
    });

    logger.warn(`[SEC-BLOCK] EVENT=THREAT_DETECTED IP=${ip} TYPE=${threatType} SCORE=${threatScore} PATH=${req.path}`);

    // Calculate cumulative score
    const recentThreats = await prisma.securityThreat.findMany({
        where: {
            OR: [
                { ipAddress: ip },
                ...(deviceId ? [{ deviceId }] : [])
            ],
            createdAt: {
                gte: new Date(Date.now() - 24 * 60 * 60 * 1000) // Last 24 hours
            }
        }
    });

    const totalScore = recentThreats.reduce((sum: number, t: any) => sum + t.threatScore, 0);

    // Block if threshold exceeded
    if (totalScore >= BLOCK_THRESHOLD) {
        // Check if already blocked
        const existingBlock = await prisma.blockedDevice.findFirst({
            where: {
                OR: [
                    { ipAddress: ip },
                    ...(deviceId ? [{ deviceId }] : [])
                ]
            }
        });

        if (!existingBlock) {
            await prisma.blockedDevice.create({
                data: {
                    deviceId,
                    ipAddress: ip,
                    reason: `Threat score ${totalScore} exceeded threshold. Last threat: ${threatType}`,
                    threatScore: totalScore,
                    permanent: true,
                    active: true
                }
            });

            logger.error(`[SEC-BLOCK] EVENT=DEVICE_BANNED IP=${ip} DEVICE=${deviceId} SCORE=${totalScore}`);
        }

        return true; // Was blocked
    }

    return false;
}

// ========================================
// MAIN SECURITY MIDDLEWARE
// ========================================
export const securityMiddleware = async (req: Request, res: Response, next: NextFunction) => {
    // Admin bypass: admins autenticados com token válido pulam TODAS as checagens
    if (isAuthenticatedAdmin(req)) {
        return next();
    }

    const ip = getClientIP(req);
    const { deviceId } = getDeviceInfo(req);

    // Check if already blocked
    if (await isBlocked(ip, deviceId)) {
        logger.warn(`[SEC-BLOCK] EVENT=REJECTED_BANNED_DEVICE IP=${ip} DEVICE=${deviceId}`);
        res.status(403).json({
            error: 'Acesso bloqueado',
            message: 'Seu dispositivo foi bloqueado permanentemente por atividades suspeitas. Apenas um administrador pode remover o bloqueio. Entre em contato com o suporte.'
        });
        return;
    }

    // Check for honeypot access
    if (HONEYPOT_ROUTES.some(route => req.path.toLowerCase().includes(route.toLowerCase()))) {
        await logThreat(req, 'HONEYPOT', THREAT_SCORES.HONEYPOT, `Honeypot accessed: ${req.path}`);

        // Delay response to waste attacker time
        await new Promise(resolve => setTimeout(resolve, 3000));

        res.status(403).json({
            error: 'Acesso proibido',
            message: 'Rota restrita detectada. Esta tentativa de acesso foi registrada e seu dispositivo pode ser bloqueado.'
        });
        return;
    }

    // Detect automated vulnerability scanners
    const userAgent = (req.headers['user-agent'] || '').toLowerCase();
    const scannerSignatures = [
        'nmap', 'nikto', 'sqlmap', 'dirbuster', 'gobuster', 'wfuzz',
        'masscan', 'nuclei', 'burpsuite', 'zaproxy', 'acunetix',
        'nessus', 'openvas', 'arachni', 'skipfish', 'w3af',
        'havij', 'commix', 'hydra', 'medusa', 'metasploit'
    ];
    if (scannerSignatures.some(sig => userAgent.includes(sig))) {
        const blocked = await logThreat(req, 'SCANNER', THREAT_SCORES.SCANNER, `Scanner detected: ${userAgent.substring(0, 100)}`);
        if (blocked) {
            res.status(403).json({ error: 'Acesso bloqueado' });
            return;
        }
    }

    // Block suspicious request methods (TRACE, TRACK can be used for XST attacks)
    if (['TRACE', 'TRACK', 'CONNECT'].includes(req.method)) {
        await logThreat(req, 'SUSPICIOUS_PATTERN', THREAT_SCORES.SUSPICIOUS_PATTERN, `Blocked method: ${req.method}`);
        res.status(405).json({ error: 'Método não permitido' });
        return;
    }

    // Injection patterns são verificados pelo WAF (wafMiddleware.ts) de forma mais completa.
    // Não duplicar checagem aqui para evitar falsos positivos.

    next();
};

// ========================================
// HONEYPOT ROUTES HANDLER
// ========================================
export const honeypotHandler = async (req: Request, res: Response) => {
    await logThreat(req, 'HONEYPOT', THREAT_SCORES.HONEYPOT, `Direct honeypot access: ${req.path}`);

    // Delay to waste attacker time
    await new Promise(resolve => setTimeout(resolve, 5000));

    res.status(403).json({
        error: 'Acesso proibido',
        message: 'Seu dispositivo foi bloqueado permanentemente.'
    });
};

// ========================================
// LOG SPECIFIC THREATS (for use in other middlewares)
// ========================================
export const logIDORAttempt = (req: Request) => logThreat(req, 'IDOR', THREAT_SCORES.IDOR, 'IDOR attempt');
export const logInvalidToken = (req: Request) => logThreat(req, 'INVALID_TOKEN', THREAT_SCORES.INVALID_TOKEN, 'Invalid token used');
export const logRateLimitHit = (req: Request) => logThreat(req, 'RATE_LIMIT', THREAT_SCORES.RATE_LIMIT, 'Rate limit exceeded');
export const logBruteForce = (req: Request) => logThreat(req, 'BRUTE_FORCE', THREAT_SCORES.BRUTE_FORCE, 'Brute force attempt');
