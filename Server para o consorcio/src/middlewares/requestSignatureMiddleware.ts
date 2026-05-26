import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { logger } from '../config/logger';
import { env } from '../config/env';
import { redisClient } from '../config/redis';

// =============================================
// HMAC REQUEST SIGNATURE MIDDLEWARE
// =============================================
// Validates that API requests originate from the official
// Flutter app by verifying an HMAC-SHA256 signature.
//
// Headers required:
//   X-Request-Signature:  HMAC of "timestamp|method|path|bodyHash"
//   X-Request-Timestamp:  Unix epoch milliseconds
//
// This blocks replayed requests (>30s window) and requests
// crafted by someone who intercepted traffic but doesn't
// know the signing secret.
// =============================================

// Fail fast in production if the signing secret is not configured.
// The Flutter app hardcodes the same secret in request_signer.dart.
// Without this, any script that knows the fallback secret can forge requests.
if (env.NODE_ENV === 'production' && !env.REQUEST_SIGNING_SECRET) {
    throw new Error('❌ FATAL: REQUEST_SIGNING_SECRET must be set in production. Server cannot start without it.');
}
const SIGNING_SECRET = env.REQUEST_SIGNING_SECRET ?? 'katari-hmac-secret-change-in-prod';

const MAX_AGE_MS = 30_000; // 30 seconds — reject stale requests

export const requestSignatureMiddleware = async (req: Request, res: Response, next: NextFunction) => {
    // Only enforce on /api/* routes (not admin panel, webhooks, or static files)
    if (!req.path.startsWith('/api/')) return next();

    // Skip public endpoints that don't need signing
    const publicPaths = ['/api/products', '/api/health'];
    if (publicPaths.some(p => req.path.startsWith(p)) && req.method === 'GET') {
        return next();
    }

    const signature = req.headers['x-request-signature'] as string;
    const timestamp = req.headers['x-request-timestamp'] as string;

    // Reject requests without HMAC signature headers
    if (!signature || !timestamp) {
        logger.warn(`🔒 MISSING SIGNATURE: ${req.path} | IP: ${req.ip}`);
        return res.status(403).json({ error: 'Assinatura de requisição obrigatória' });
    }

    const ts = parseInt(timestamp, 10);
    if (isNaN(ts)) {
        return res.status(400).json({ error: 'Invalid request timestamp' });
    }

    // Anti-replay: reject requests older than 30 seconds
    const age = Math.abs(Date.now() - ts);
    if (age > MAX_AGE_MS) {
        logger.warn(`🔒 REPLAY REJECTED: ${req.path} | Age: ${age}ms | IP: ${req.ip}`);
        return res.status(403).json({ error: 'Request expired', retryable: true });
    }

    // ── Per-session signing secret ─────────────────────────────────────────────
    // On login the server generates a unique signing secret tied to the JWT's JTI
    // and stores it in Redis. Authenticated requests use that per-session secret
    // instead of the global static fallback, so extracting the APK secret only
    // helps forge unauthenticated requests (login/register) — not authenticated ones.
    //
    // For unauthenticated routes (login, register) or when Redis is unavailable,
    // we fall back to the global static secret transparently.
    let effectiveSecret = SIGNING_SECRET;
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ') && redisClient) {
        try {
            const token = authHeader.substring(7);
            const parts = token.split('.');
            if (parts.length === 3) {
                // Decode payload without verification — we only need the JTI to look
                // up the session secret. The token is fully verified by authMiddleware.
                const rawPayload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
                if (rawPayload?.jti) {
                    const sessionSecret = await redisClient.get(`signing:session:${rawPayload.jti}`);
                    if (sessionSecret) {
                        effectiveSecret = sessionSecret;
                    }
                }
            }
        } catch {
            // Decode/Redis failure — fall back to global secret silently
        }
    }

    // Compute expected signature using raw bytes if available
    let bodyString = '';
    if ((req as any).rawBody) {
        bodyString = (req as any).rawBody.toString('utf8');
    }

    const bodyHash = crypto.createHash('sha256')
        .update(bodyString)
        .digest('hex');

    const payload = `${timestamp}|${req.method}|${req.path}|${bodyHash}`;
    const expected = crypto.createHmac('sha256', effectiveSecret)
        .update(payload)
        .digest('hex');

    // timingSafeEqual requires equal-length buffers — different length = definitely invalid
    const sigBuf = Buffer.from(signature, 'utf8');
    const expBuf = Buffer.from(expected, 'utf8');
    const valid = sigBuf.length === expBuf.length && crypto.timingSafeEqual(sigBuf, expBuf);

    if (!valid) {
        logger.warn(`🔒 INVALID SIGNATURE: ${req.path} | IP: ${req.ip}`);
        return res.status(403).json({ error: 'Invalid request signature' });
    }

    next();
};
