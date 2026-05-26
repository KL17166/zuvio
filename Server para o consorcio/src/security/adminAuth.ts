import jwt from 'jsonwebtoken';
import { Request, Response, NextFunction } from 'express';

/**
 * Verifica se a request possui um token JWT de admin válido.
 * Checa o header X-Admin-Token e fallback no body._adminToken (para form submissions).
 */
export function isAuthenticatedAdmin(req: Request): boolean {
    const token = (req.headers['x-admin-token'] as string) || req.body?._adminToken;
    if (!token) return false;

    try {
        const payload = jwt.verify(token, process.env.JWT_SECRET as string, {
            algorithms: ['HS256'],
        }) as any;
        return ['MASTER', 'MANAGER', 'SUPPORT'].includes(payload.role) && payload.type === 'admin_panel';
    } catch {
        return false;
    }
}

/**
 * Middleware para gerar verificações de papéis baseados em session (Express Admin Panel)
 */
export const requireRoles = (roles: string[]) => {
    return (req: any, res: any, next: any) => {
        if (!req.session || !req.session.user || !roles.includes(req.session.user.role)) {
            if (req.xhr || req.headers.accept?.includes('application/json') || !req.headers.accept?.includes('text/html')) {
                return res.status(403).json({
                    error: 'Acesso negado',
                    message: `Esta rota requer um dos perfis: ${roles.join(', ')}. Seu perfil atual não tem acesso.`
                });
            }
            req.flash('error', 'Acesso negado. Nível de permissão insuficiente.');
            return res.redirect('back');
        }
        next();
    };
};
