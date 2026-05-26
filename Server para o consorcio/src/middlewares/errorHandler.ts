import { Request, Response, NextFunction } from 'express';
import { logger } from '../config/logger';
import { ZodError } from 'zod';

export const errorHandler = (
    err: Error,
    req: Request,
    res: Response,
    next: NextFunction
) => {
    logger.error(`Error: ${err.message}`, { stack: err.stack, path: req.path, method: req.method });

    // Prevent "Cannot set headers after they are sent" crashes
    if (res.headersSent) {
        return next(err);
    }

    if (err instanceof ZodError) {
        return res.status(400).json({
            error: 'Validacao falhou',
            message: 'Os dados enviados nao sao validos. Verifique os campos e tente novamente.',
            ...(process.env.NODE_ENV === 'development' ? { details: err.issues } : {}),
        });
    }

    // Handle specific known errors here (e.g., AppError class if created)

    // Handle Admin UI errors
    if (req.path.startsWith('/admin') && req.accepts('html')) {
        return res.status(500).render('pages/error/index', {
            message: 'Erro interno do servidor',
            error: process.env.NODE_ENV === 'development' ? err : {}
        });
    }

    res.status(500).json({
        error: 'Erro interno do servidor',
        message: 'Ocorreu um erro inesperado. Tente novamente mais tarde ou entre em contato com o suporte.',
    });
};
