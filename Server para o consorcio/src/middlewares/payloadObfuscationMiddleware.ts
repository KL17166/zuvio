import { Request, Response, NextFunction } from 'express';
import { env } from '../config/env';
import { encryptPayload, decryptPayload } from '../utils/cryptoUtils';
import { logger } from '../config/logger';

export const payloadObfuscationMiddleware = (req: Request, res: Response, next: NextFunction) => {
    const bypassHeader = req.headers['x-bypass-obfuscation'];
    const isBypassed = bypassHeader === env.ENCRYPTION_BYPASS_SECRET;

    // 1. Decrypt incoming request body if it is encrypted
    if (req.method === 'POST' || req.method === 'PUT' || req.method === 'PATCH') {
        if (req.body && typeof req.body === 'object' && req.body.p && req.body.iv && req.body.t) {
            try {
                const decryptedJson = decryptPayload(req.body.p, req.body.iv, req.body.t);
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

            try {
                const jsonString = JSON.stringify(body);
                const encrypted = encryptPayload(jsonString);
                return originalJson(encrypted);
            } catch (err) {
                logger.error('Failed to encrypt outgoing response payload', { error: err });
                return res.status(500).send('Encryption error');
            }
        };
    }

    next();
};
