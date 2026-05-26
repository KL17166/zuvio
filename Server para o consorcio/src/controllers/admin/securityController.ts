import { Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';

// GET /admin/security
export const getSecurityDashboard = async (req: Request, res: Response) => {
    try {
        const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);

        // Get blocked devices
        const blockedDevices = await prisma.blockedDevice.findMany({
            orderBy: { blockedAt: 'desc' },
            take: 50
        });

        // Get recent threats
        const recentThreats = await prisma.securityThreat.findMany({
            where: {
                createdAt: { gte: yesterday }
            },
            orderBy: { createdAt: 'desc' },
            take: 100
        });

        // Stats
        const blockedCount = await prisma.blockedDevice.count({ where: { active: true } });
        const threatsToday = recentThreats.length;
        const honeypotHits = recentThreats.filter((t: any) => t.threatType === 'HONEYPOT').length;

        const totalScoreResult = await prisma.blockedDevice.aggregate({
            _sum: { threatScore: true },
            where: { active: true }
        });
        const totalBlockedScore = totalScoreResult._sum.threatScore || 0;

        res.render('pages/security/index', {
            path: '/security',
            blockedDevices,
            recentThreats,
            blockedCount,
            threatsToday,
            honeypotHits,
            totalBlockedScore
        });
    } catch (error) {
        logger.error('Security dashboard error:', error);
        res.status(500).send('Erro ao carregar página de segurança');
    }
};

// POST /admin/security/unblock/:id
export const unblockDevice = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;
        const adminUser = (req as any).session?.user;

        await prisma.blockedDevice.update({
            where: { id },
            data: {
                active: false,
                unblockedAt: new Date(),
                unblockedBy: adminUser?.name || 'Admin'
            }
        });

        req.flash('success_msg', 'Dispositivo desbloqueado com sucesso!');
        res.redirect('/admin/security');
    } catch (error) {
        logger.error('Unblock device error:', error);
        req.flash('error_msg', 'Erro ao desbloquear dispositivo');
        res.redirect('/admin/security');
    }
};
