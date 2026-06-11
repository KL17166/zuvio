import { Request, Response, NextFunction } from 'express';
import { env } from '../config/env';
import { encryptPayload, decryptPayload } from '../utils/cryptoUtils';
import { logger } from '../config/logger';
import { redisClient } from '../config/redis';
import jwt from 'jsonwebtoken';

/**
 * Resolves the per-session AES payload key from Redis using the JWT JTI.
 * Falls back to the static PAYLOAD_ENCRYPTION_SECRET when Redis is unavailable
 * or no authenticated session exists (e.g. login / register requests).
 */
async function resolvePayloadKey(req: Request): Promise<string | undefined> {
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ') && redisClient) {
        try {
            const token = authHeader.substring(7);
            const parts = token.split('.');
            if (parts.length === 3) {
                const rawPayload = JSON.parse(
                    Buffer.from(parts[1], 'base64url').toString('utf8'),
                );
                if (rawPayload?.jti) {
                    const sessionKey = await redisClient.get(
                        `payload:session:${rawPayload.jti}`,
                    );
                    if (sessionKey) return sessionKey;
                }
            }
        } catch {
            // Fall through to static key
        }
    }
    // No session key → use static env key (for login/register bootstrap)
    return undefined;
}

export const payloadObfuscationMiddleware = async (req: Request, res: Response, next: NextFunction) => {
    const bypassHeader = req.headers['x-bypass-obfuscation'];
    const isBypassed = bypassHeader === env.ENCRYPTION_BYPASS_SECRET;

    // 1. Decrypt incoming request body if it is encrypted
    if (req.method === 'POST' || req.method === 'PUT' || req.method === 'PATCH') {
        if (req.body && typeof req.body === 'object' && req.body.p && req.body.iv && req.body.t) {
            try {
                const sessionKey = await resolvePayloadKey(req);
                const decryptedJson = decryptPayload(req.body.p, req.body.iv, req.body.t, sessionKey);
                req.body = JSON.parse(decryptedJson);
            } catch (err) {
                logger.error('Failed to decrypt incoming request payload', { error: err });
                return res.status(400).json({ error: 'Invalid encrypted payload' });
            }
        }
    }

    // 2. Encrypt outgoing response
    if (!isBypassed) {
        const originalJson = res.json.bind(res);
        res.json = (body: any) => {
            // Avoid double encryption if the response is already encrypted
            if (body && typeof body === 'object' && body.p && body.iv && body.t) {
                return originalJson(body);
            }

            // Resolve key asynchronously — we must call the async function here
            resolvePayloadKey(req).then((sessionKey) => {
                try {
                    const jsonString = JSON.stringify(body);
                    const encrypted = encryptPayload(jsonString, sessionKey);
                    originalJson(encrypted);
                } catch (err) {
                    logger.error('Failed to encrypt outgoing response payload', { error: err });
                    res.status(500).send('Encryption error');
                }
            }).catch((err) => {
                logger.error('Failed to resolve payload key for response', { error: err });
                res.status(500).send('Encryption error');
            });

            // res.json must return res — actual send happens in the promise
            return res;
        };
    }

    next();
};
