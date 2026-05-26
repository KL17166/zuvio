import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';

declare module 'express-session' {
    interface SessionData {
        csrfToken: string;
    }
}

export const generateToken = (req: Request, res: Response, next: NextFunction) => {
    if (!req.session.csrfToken) {
        req.session.csrfToken = crypto.randomBytes(32).toString('hex');
    }
    res.locals.csrfToken = req.session.csrfToken;
    next();
};

export const validateToken = (req: Request, res: Response, next: NextFunction) => {
    const token = req.body._csrf || req.query._csrf || req.headers['csrf-token'];

    if (!token || token !== req.session.csrfToken) {
        // For API/programmatic requests: return 403 JSON
        if (req.xhr || req.headers.accept?.includes('application/json') || !req.headers.accept?.includes('text/html')) {
            return res.status(403).json({
                error: 'Token CSRF invalido',
                message: 'Token de seguranca invalido ou expirado. Recarregue a pagina e tente novamente.'
            });
        }
        // For browser requests: redirect
        req.flash('error_msg', 'Token de seguranca invalido ou expirado. Tente novamente.');
        return res.redirect('back');
    }
    next();
};
