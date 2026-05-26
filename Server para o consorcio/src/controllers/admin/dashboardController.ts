import { Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';

// GET /admin/dashboard
export const getDashboard = async (req: Request, res: Response) => {
    try {
        const today = new Date();
        const firstDayOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);

        // === BATCH 1: All count/stat queries in parallel ===
        const [
            totalUsers,
            totalContracts,
            activeContracts,
            contemplatedContracts,
            pendingPayments,
            overduePayments,
            paidPayments,
            recentContracts,
            recentPayments
        ] = await Promise.all([
            prisma.user.count({ where: { role: 'CLIENT' } }),
            prisma.subscription.count(),
            prisma.subscription.count({ where: { status: 'ACTIVE' } }),
            prisma.subscription.count({ where: { contemplated: true } }),
            prisma.installment.count({ where: { status: 'PENDING' } }),
            prisma.installment.count({ where: { status: 'OVERDUE' } }),
            prisma.installment.count({ where: { status: 'PAID' } }),
            prisma.subscription.findMany({
                take: 5,
                orderBy: { createdAt: 'desc' },
                include: {
                    user: true,
                    plan: { include: { product: true } }
                }
            }),
            prisma.installment.findMany({
                take: 5,
                where: { status: 'PAID' },
                orderBy: { paymentDate: 'desc' },
                include: {
                    subscription: { include: { user: true } }
                }
            })
        ]);

        // === BATCH 2: Single query for all paid installments in the last 12 months ===
        const twelveMonthsAgo = new Date(today.getFullYear(), today.getMonth() - 11, 1);

        const allPaidInstallments = await prisma.installment.findMany({
            where: {
                status: 'PAID',
                paymentDate: { gte: twelveMonthsAgo }
            },
            select: {
                amount: true,
                paymentDate: true
            }
        });

        // Total received this month (from the fetched data)
        const totalReceivedThisMonth = allPaidInstallments
            .filter(inst => inst.paymentDate && inst.paymentDate >= firstDayOfMonth)
            .reduce((sum, inst) => sum + Number(inst.amount), 0);

        // === Build cash flow data by grouping in JS ===
        const cashFlowData: Record<string, Array<{label: string, total: number}>> = {
            weekly: [],
            monthly: [],
            yearly: []
        };

        // Weekly: last 8 weeks
        for (let i = 7; i >= 0; i--) {
            const endDate = new Date();
            endDate.setDate(endDate.getDate() - (i * 7));
            endDate.setHours(23, 59, 59, 999);
            const startDate = new Date(endDate);
            startDate.setDate(startDate.getDate() - 6);
            startDate.setHours(0, 0, 0, 0);

            const total = allPaidInstallments
                .filter(inst => inst.paymentDate && inst.paymentDate >= startDate && inst.paymentDate <= endDate)
                .reduce((sum, inst) => sum + Number(inst.amount), 0);

            const label = `${startDate.getDate().toString().padStart(2,'0')}/${(startDate.getMonth()+1).toString().padStart(2,'0')}`;
            cashFlowData.weekly.push({ label, total });
        }

        // Monthly: last 6 months
        for (let i = 5; i >= 0; i--) {
            const date = new Date();
            date.setMonth(date.getMonth() - i);
            const startOfMonth = new Date(date.getFullYear(), date.getMonth(), 1);
            const endOfMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0, 23, 59, 59, 999);

            const total = allPaidInstallments
                .filter(inst => inst.paymentDate && inst.paymentDate >= startOfMonth && inst.paymentDate <= endOfMonth)
                .reduce((sum, inst) => sum + Number(inst.amount), 0);

            cashFlowData.monthly.push({
                label: date.toLocaleDateString('pt-BR', { month: 'short' }),
                total
            });
        }

        // Yearly: last 12 months
        for (let i = 11; i >= 0; i--) {
            const date = new Date();
            date.setMonth(date.getMonth() - i);
            const startOfMonth = new Date(date.getFullYear(), date.getMonth(), 1);
            const endOfMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0, 23, 59, 59, 999);

            const total = allPaidInstallments
                .filter(inst => inst.paymentDate && inst.paymentDate >= startOfMonth && inst.paymentDate <= endOfMonth)
                .reduce((sum, inst) => sum + Number(inst.amount), 0);

            cashFlowData.yearly.push({
                label: date.toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' }),
                total
            });
        }

        res.render('pages/dashboard/index', {
            path: '/dashboard',
            stats: {
                totalUsers,
                totalContracts,
                activeContracts,
                contemplatedContracts,
                totalReceivedThisMonth,
                pendingPayments,
                overduePayments,
                paidPayments
            },
            recentContracts,
            recentPayments,
            cashFlowData
        });
    } catch (error) {
        logger.error('Dashboard error:', error);
        res.status(500).send('Erro ao carregar dashboard');
    }
};
