import { Request, Response, NextFunction } from 'express';
import { redisClient } from '../config/redis';
import { logger } from '../config/logger';

// =============================================
// REDIS-BACKED RATE LIMIT MIDDLEWARE
// =============================================
// Provides distributed rate limiting across server instances
// for critical endpoints (login, checkout, etc.)
// =============================================

export const createRateLimiter = (options: {
    prefix: string;
    maxRequests: number;
    windowSeconds: number;
    keyGenerator: (req: Request) => string;
    errorMessage: string;
}) => {
    return async (req: Request, res: Response, next: NextFunction) => {
        if (!redisClient) {
            // Fail open if Redis is down
            return next();
        }

        const keySuffix = options.keyGenerator(req);
        if (!keySuffix) return next();

        const key = `ratelimit:${options.prefix}:${keySuffix}`;

        try {
            const current = await redisClient.incr(key);
            
            if (current === 1) {
                await redisClient.expire(key, options.windowSeconds);
            }

            if (current > options.maxRequests) {
                logger.warn(`🛑 RATE LIMIT EXCEEDED: ${req.path} | Key: ${key} | Current: ${current}/${options.maxRequests}`);
                return res.status(429).json({
                    error: 'Muitas requisições',
                    message: options.errorMessage
                });
            }

            next();
        } catch (error) {
            logger.error(`Rate limiter Redis error: ${error}`);
            next();
        }
    };
};

export const authRateLimiter = createRateLimiter({
    prefix: 'auth',
    maxRequests: 5,
    windowSeconds: 15 * 60, // 15 minutes
    keyGenerator: (req) => {
        // Limit by CPF if provided in body, else by IP
        let cpf = req.body?.cpf as string;
        if (cpf) {
            cpf = cpf.replace(/\D/g, '');
            return `cpf:${cpf}`;
        }
        return `ip:${req.ip}`;
    },
    errorMessage: 'Muitas tentativas de login. Aguarde 15 minutos e tente novamente.'
});

export const transactionRateLimiter = createRateLimiter({
    prefix: 'transaction',
    maxRequests: 3,
    windowSeconds: 60, // 1 minute
    keyGenerator: (req) => {
        if (req.user?.userId) {
            return `user:${req.user.userId}`;
        }
        return `ip:${req.ip}`;
    },
    errorMessage: 'Muitas transações seguidas. Aguarde 1 minuto e tente novamente.'
});
