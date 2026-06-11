import { Request, Response, NextFunction } from 'express';
import { redisClient } from '../config/redis';
import { logger } from '../config/logger';

// =============================================
// DEVICE BINDING MIDDLEWARE
// =============================================
// Validates that the request comes from the same physical device
// that performed the login, using a hardware-backed cryptographically 
// secure token stored in the Flutter app's Secure Storage (Keystore/Keychain).
//
// This mitigates the risk of an attacker extracting the JWT 
// and Session Secrets from memory and using them on another device.
// =============================================

export const deviceBindingMiddleware = async (req: Request, res: Response, next: NextFunction) => {
    // Only enforce on authenticated routes that have req.user populated by authMiddleware
    if (!req.user || !req.user.jti) {
        return next(); 
    }

    // Skip public endpoints and static file requests
    if (req.path.startsWith('/public/') || req.method === 'OPTIONS') {
        return next();
    }

    const providedToken = req.headers['x-device-binding'] as string;

    if (!providedToken) {
        logger.warn(`📱 MISSING DEVICE TOKEN: ${req.path} | User: ${req.user.userId} | IP: ${req.ip}`);
        return res.status(403).json({ 
            error: 'Dispositivo não reconhecido',
            message: 'Token de hardware ausente. Faça login novamente no aplicativo oficial.'
        });
    }

    if (redisClient) {
        try {
            const expectedToken = await redisClient.get(`device:binding:${req.user.jti}`);
            
            if (expectedToken && expectedToken !== providedToken) {
                // The session keys were used on a different device! 
                // This is a strong indicator of a stolen session.
                logger.error(`🚨 DEVICE BINDING MISMATCH (STOLEN SESSION?): ${req.path} | User: ${req.user.userId} | IP: ${req.ip}`);
                
                // Immediately kill the session to limit damage
                await redisClient.setEx(`jti:blacklist:${req.user.jti}`, 3600, '1');
                await redisClient.del(`signing:session:${req.user.jti}`);
                await redisClient.del(`payload:session:${req.user.jti}`);
                
                return res.status(403).json({ 
                    error: 'Sessão Comprometida',
                    message: 'Sua sessão foi revogada por segurança porque foi acessada a partir de um dispositivo não autorizado. Faça login novamente.' 
                });
            }
        } catch (e) {
            logger.warn(`Redis failure checking device binding for user ${req.user.userId}: ${e}`);
            // Fail open if Redis is down to preserve availability
        }
    }

    next();
};
