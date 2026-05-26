import { Request, Response, NextFunction } from 'express';
import { prisma } from '../config/database';

/**
 * Middleware to check if the authenticated user owns the resource they are trying to access.
 * Usage: checkOwnership('user', 'id') or checkOwnership('contract', 'id')
 */
export const checkOwnership = (modelName: 'user' | 'contract', paramId: string = 'id') => {
    return async (req: Request, res: Response, next: NextFunction) => {
        try {
            const userId = (req as any).user?.userId;
            const resourceId = req.params[paramId] as string;

            if (!userId) {
                return res.status(401).json({
                    error: 'Nao autenticado',
                    message: 'Voce precisa estar logado para acessar este recurso.'
                });
            }

            if (!resourceId) {
                return res.status(400).json({
                    error: 'ID do recurso ausente',
                    message: 'O ID do recurso nao foi informado na requisicao.'
                });
            }

            // check ownership logic based on model
            if (modelName === 'user') {
                // For User model, the ID in URL must match the authenticated user ID
                if (resourceId !== userId) {
                    return res.status(403).json({
                        error: 'Acesso negado',
                        message: 'Voce so pode acessar seus proprios dados. Nao e permitido visualizar dados de outros usuarios.'
                    });
                }
            } else if (modelName === 'contract') {
                // For Contract (Subscription), we need to check if the subscription belongs to the user
                const subscription = await prisma.subscription.findUnique({
                    where: { id: resourceId },
                    select: { userId: true }
                });

                if (!subscription) {
                    return res.status(404).json({
                        error: 'Contrato nao encontrado',
                        message: 'O contrato solicitado nao existe ou foi removido.'
                    });
                }

                if (subscription.userId !== userId) {
                    return res.status(403).json({
                        error: 'Acesso negado',
                        message: 'Este contrato pertence a outro usuario. Voce so pode acessar seus proprios contratos.'
                    });
                }
            }

            next();
        } catch (error) {
            next(error);
        }
    };
};
