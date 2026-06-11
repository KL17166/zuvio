import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { redisClient } from '../config/redis';
import { logger } from '../config/logger';
import { deviceBindingMiddleware } from './deviceBindingMiddleware';

export interface AuthPayload {
    userId: string;
    role: string;
    jti?: string;
}

declare global {
    namespace Express {
        interface Request {
            user?: AuthPayload;
        }
    }
}

export const authenticate = async (req: Request, res: Response, next: NextFunction) => {
    const authHeader = req.headers.authorization;

    if (!authHeader) {
        return res.status(401).json({
            error: 'Token nao fornecido',
            message: 'Envie o token JWT no header Authorization: Bearer <token>. Faca login primeiro para obter seu token.'
        });
    }

    const parts = authHeader.split(' ');
    if (parts.length !== 2 || parts[0] !== 'Bearer') {
        return res.status(401).json({
            error: 'Token mal formatado',
            message: 'O header Authorization deve seguir o formato: Bearer <token>'
        });
    }

    const token = parts[1];
    if (!token) {
        return res.status(401).json({
            error: 'Token vazio',
            message: 'O token JWT esta vazio. Faca login novamente para obter um token valido.'
        });
    }

    try {
        const payload = jwt.verify(token, process.env.JWT_SECRET as string, {
            algorithms: ['HS256'],
        }) as AuthPayload;

        // ── JWT Blacklist check ────────────────────────────────────────────────
        // On logout the server stores the JTI in Redis with a TTL equal to
        // the token's remaining lifetime. Any request carrying a revoked JTI
        // is rejected immediately, even within the token's natural expiry window.
        if (payload.jti && redisClient) {
            try {
                const isBlacklisted = await redisClient.get(`jti:blacklist:${payload.jti}`);
                if (isBlacklisted) {
                    return res.status(401).json({
                        error: 'Token revogado',
                        message: 'Você fez logout. Faça login novamente para continuar.'
                    });
                }
            } catch (redisErr) {
                // Redis unavailable — fail open (log warning, allow the request)
                // This preserves availability at the cost of blacklist enforcement
                // for the Redis outage window only.
                logger.warn('JWT blacklist check failed (Redis unavailable) — allowing request', { jti: payload.jti });
            }
        }

        req.user = payload;
        
        // Pass control to the Device Binding Middleware to verify hardware tokens
        return deviceBindingMiddleware(req, res, next);
    } catch (error) {
        return res.status(401).json({
            error: 'Token invalido ou expirado',
            message: 'Seu token de acesso e invalido ou expirou. Faca login novamente.'
        });
    }
};

export const authorize = (roles: string[]) => {
    return (req: Request, res: Response, next: NextFunction) => {
        if (!req.user) {
            return res.status(401).json({
                error: 'Nao autenticado',
                message: 'Voce precisa estar logado para acessar esta rota.'
            });
        }

        if (!roles.includes(req.user.role)) {
            return res.status(403).json({
                error: 'Acesso negado',
                message: `Esta rota requer permissao de: ${roles.join(', ')}. Seu perfil (${req.user.role}) nao tem acesso.`
            });
        }

        next();
    };
};
