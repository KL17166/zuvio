import { Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';

// GET /admin/reports
export const getReports = async (req: Request, res: Response) => {
    try {
        const now = new Date();

        // ── Period filter (default: current month) ──────────────────────────
        const periodParam = (req.query.period as string) || 'month';
        const customStart = req.query.start as string | undefined;
        const customEnd   = req.query.end   as string | undefined;

        let periodStart: Date;
        let periodEnd: Date = new Date(now);
        periodEnd.setHours(23, 59, 59, 999);

        switch (periodParam) {
            case 'today':
                periodStart = new Date(now);
                periodStart.setHours(0, 0, 0, 0);
                break;
            case 'week':
                periodStart = new Date(now);
                periodStart.setDate(now.getDate() - 6);
                periodStart.setHours(0, 0, 0, 0);
                break;
            case 'month':
                periodStart = new Date(now.getFullYear(), now.getMonth(), 1);
                break;
            case '3months':
                periodStart = new Date(now.getFullYear(), now.getMonth() - 2, 1);
                break;
            case 'year':
                periodStart = new Date(now.getFullYear(), 0, 1);
                break;
            case 'custom':
                periodStart = customStart ? new Date(customStart) : new Date(now.getFullYear(), now.getMonth(), 1);
                if (customEnd) { periodEnd = new Date(customEnd); periodEnd.setHours(23, 59, 59, 999); }
                break;
            default:
                periodStart = new Date(now.getFullYear(), now.getMonth(), 1);
        }

        // ── Previous period (for % change comparison) ───────────────────────
        const periodLengthMs = periodEnd.getTime() - periodStart.getTime();
        const prevPeriodEnd   = new Date(periodStart.getTime() - 1);
        const prevPeriodStart = new Date(prevPeriodEnd.getTime() - periodLengthMs);

        // ── Fetch all installments once — group in JS ────────────────────────
        const allInstallments = await prisma.installment.findMany({
            select: {
                id: true,
                amount: true,
                status: true,
                paymentDate: true,
                paymentMethod: true,
                dueDate: true,
                number: true,
                subscriptionId: true,
                subscription: {
                    select: {
                        user: { select: { id: true, name: true, email: true } },
                        plan: { select: { product: { select: { id: true, name: true, type: true } } } }
                    }
                }
            }
        });

        const paidAll      = allInstallments.filter(i => i.status === 'PAID');
        const overdueAll   = allInstallments.filter(i => i.status === 'OVERDUE');
        const pendingAll   = allInstallments.filter(i => i.status === 'PENDING');
        const refundedAll  = allInstallments.filter(i => i.status === 'REFUNDED');

        // ── All-time totals ──────────────────────────────────────────────────
        const totalReceived = paidAll.reduce((s, i) => s + Number(i.amount), 0);
        const totalOverdue  = overdueAll.reduce((s, i) => s + Number(i.amount), 0);
        const totalPending  = pendingAll.reduce((s, i) => s + Number(i.amount), 0);
        const totalRefunded = refundedAll.reduce((s, i) => s + Number(i.amount), 0);

        // ── Period totals ────────────────────────────────────────────────────
        const paidInPeriod = paidAll.filter(i =>
            i.paymentDate && i.paymentDate >= periodStart && i.paymentDate <= periodEnd
        );
        const paidInPrevPeriod = paidAll.filter(i =>
            i.paymentDate && i.paymentDate >= prevPeriodStart && i.paymentDate <= prevPeriodEnd
        );

        const periodReceived     = paidInPeriod.reduce((s, i) => s + Number(i.amount), 0);
        const prevPeriodReceived = paidInPrevPeriod.reduce((s, i) => s + Number(i.amount), 0);
        const receivedChange     = prevPeriodReceived > 0
            ? ((periodReceived - prevPeriodReceived) / prevPeriodReceived) * 100
            : null;

        const overdueInPeriod = overdueAll.filter(i =>
            i.dueDate && i.dueDate >= periodStart && i.dueDate <= periodEnd
        );

        const avgTicket = paidInPeriod.length > 0
            ? periodReceived / paidInPeriod.length
            : 0;

        const defaultRate = (paidInPeriod.length + overdueInPeriod.length) > 0
            ? (overdueInPeriod.length / (paidInPeriod.length + overdueInPeriod.length)) * 100
            : 0;

        // ── Projection: next 30/60/90 days ──────────────────────────────────
        const proj30  = new Date(now); proj30.setDate(now.getDate() + 30);
        const proj60  = new Date(now); proj60.setDate(now.getDate() + 60);
        const proj90  = new Date(now); proj90.setDate(now.getDate() + 90);

        const projection30 = pendingAll
            .filter(i => i.dueDate && i.dueDate >= now && i.dueDate <= proj30)
            .reduce((s, i) => s + Number(i.amount), 0);
        const projection60 = pendingAll
            .filter(i => i.dueDate && i.dueDate >= now && i.dueDate <= proj60)
            .reduce((s, i) => s + Number(i.amount), 0);
        const projection90 = pendingAll
            .filter(i => i.dueDate && i.dueDate >= now && i.dueDate <= proj90)
            .reduce((s, i) => s + Number(i.amount), 0);

        // ── Monthly revenue — last 12 months ────────────────────────────────
        const monthlyRevenue: { month: string; amount: number }[] = [];
        for (let i = 11; i >= 0; i--) {
            const mStart = new Date(now.getFullYear(), now.getMonth() - i, 1);
            const mEnd   = new Date(now.getFullYear(), now.getMonth() - i + 1, 1);
            const total  = paidAll
                .filter(inst => inst.paymentDate && inst.paymentDate >= mStart && inst.paymentDate < mEnd)
                .reduce((s, inst) => s + Number(inst.amount), 0);
            monthlyRevenue.push({
                month: mStart.toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' }),
                amount: total
            });
        }

        // ── Payment method distribution ──────────────────────────────────────
        const methodMap: Record<string, number> = {};
        paidInPeriod.forEach(i => {
            const m = i.paymentMethod || 'N/A';
            methodMap[m] = (methodMap[m] || 0) + Number(i.amount);
        });
        const paymentMethods = Object.entries(methodMap)
            .map(([method, total]) => ({ method, total }))
            .sort((a, b) => b.total - a.total);

        // ── Status distribution (pie chart data) ────────────────────────────
        const statusDistribution = [
            { label: 'Pago',         value: paidAll.length,    color: '#10b981' },
            { label: 'Pendente',     value: pendingAll.length,  color: '#f59e0b' },
            { label: 'Atrasado',     value: overdueAll.length,  color: '#ef4444' },
            { label: 'Reembolsado',  value: refundedAll.length, color: '#3b82f6' }
        ];

        // ── Transaction feed (paid in period, most recent first) ─────────────
        const transactionFeed = paidInPeriod
            .sort((a, b) => (b.paymentDate?.getTime() || 0) - (a.paymentDate?.getTime() || 0))
            .slice(0, 50)
            .map(i => ({
                id:            i.id,
                clientName:    i.subscription.user.name,
                clientEmail:   i.subscription.user.email,
                productName:   i.subscription.plan.product.name,
                amount:        Number(i.amount),
                paymentMethod: i.paymentMethod || 'N/A',
                paymentDate:   i.paymentDate,
                installment:   i.number
            }));

        // ── Refund/exit feed ─────────────────────────────────────────────────
        const refundFeed = refundedAll
            .sort((a, b) => (b.dueDate?.getTime() || 0) - (a.dueDate?.getTime() || 0))
            .slice(0, 20)
            .map(i => ({
                id:          i.id,
                clientName:  i.subscription.user.name,
                productName: i.subscription.plan.product.name,
                amount:      Number(i.amount),
                dueDate:     i.dueDate
            }));

        // ── Top 10 clients by amount paid ────────────────────────────────────
        const clientTotals: Record<string, { name: string; email: string; total: number; count: number }> = {};
        paidInPeriod.forEach(i => {
            const uid = i.subscription.user.id;
            if (!clientTotals[uid]) {
                clientTotals[uid] = { name: i.subscription.user.name, email: i.subscription.user.email, total: 0, count: 0 };
            }
            clientTotals[uid].total += Number(i.amount);
            clientTotals[uid].count += 1;
        });
        const topClients = Object.values(clientTotals)
            .sort((a, b) => b.total - a.total)
            .slice(0, 10);

        // ── Clients with overdue installments (30+ days) ─────────────────────
        const thirtyDaysAgo = new Date(now);
        thirtyDaysAgo.setDate(now.getDate() - 30);
        const longOverdue = overdueAll.filter(i => i.dueDate && i.dueDate <= thirtyDaysAgo);
        const longOverdueByClient: Record<string, { name: string; total: number; count: number }> = {};
        longOverdue.forEach(i => {
            const uid = i.subscription.user.id;
            if (!longOverdueByClient[uid]) {
                longOverdueByClient[uid] = { name: i.subscription.user.name, total: 0, count: 0 };
            }
            longOverdueByClient[uid].total += Number(i.amount);
            longOverdueByClient[uid].count += 1;
        });
        const overdueClients = Object.values(longOverdueByClient)
            .sort((a, b) => b.total - a.total)
            .slice(0, 10);

        // ── New clients per month (last 6 months) ────────────────────────────
        const newClientsRaw = await prisma.user.findMany({
            where: {
                role: 'CLIENT',
                createdAt: { gte: new Date(now.getFullYear(), now.getMonth() - 5, 1) }
            },
            select: { createdAt: true }
        });
        const newClientsPerMonth: { month: string; count: number }[] = [];
        for (let i = 5; i >= 0; i--) {
            const mStart = new Date(now.getFullYear(), now.getMonth() - i, 1);
            const mEnd   = new Date(now.getFullYear(), now.getMonth() - i + 1, 1);
            const count  = newClientsRaw.filter(u => u.createdAt >= mStart && u.createdAt < mEnd).length;
            newClientsPerMonth.push({
                month: mStart.toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' }),
                count
            });
        }

        // ── Revenue by product type ──────────────────────────────────────────
        const typeRevenue: Record<string, number> = {};
        paidInPeriod.forEach(i => {
            const t = i.subscription.plan.product.type || 'OUTROS';
            typeRevenue[t] = (typeRevenue[t] || 0) + Number(i.amount);
        });
        const revenueByType = Object.entries(typeRevenue)
            .map(([type, total]) => ({ type, total }))
            .sort((a, b) => b.total - a.total);

        // ── Top products by number of contracts ──────────────────────────────
        const productContractMap: Record<string, { name: string; count: number; revenue: number }> = {};
        paidInPeriod.forEach(i => {
            const pid = i.subscription.plan.product.id;
            if (!productContractMap[pid]) {
                productContractMap[pid] = { name: i.subscription.plan.product.name, count: 0, revenue: 0 };
            }
            productContractMap[pid].count   += 1;
            productContractMap[pid].revenue += Number(i.amount);
        });
        const topProducts = Object.values(productContractMap)
            .sort((a, b) => b.revenue - a.revenue)
            .slice(0, 5);

        // ── Contract & client global stats ───────────────────────────────────
        const [
            totalClients,
            totalContracts,
            activeContracts,
            contemplatedContracts,
            totalProducts,
            totalBids,
            pendingBids
        ] = await Promise.all([
            prisma.user.count({ where: { role: 'CLIENT' } }),
            prisma.subscription.count(),
            prisma.subscription.count({ where: { status: 'ACTIVE' } }),
            prisma.subscription.count({ where: { contemplated: true } }),
            prisma.product.count({ where: { active: true } }),
            prisma.bid.count(),
            prisma.bid.count({ where: { status: 'PENDING' } })
        ]);

        res.render('pages/reports/index', {
            path: '/reports',

            // Period
            period:      periodParam,
            periodStart,
            periodEnd,
            customStart: customStart || '',
            customEnd:   customEnd   || '',

            // All-time totals
            stats: {
                totalClients,
                totalContracts,
                activeContracts,
                contemplatedContracts,
                totalReceived,
                totalOverdue,
                totalPending,
                totalRefunded,
                totalProducts,
                totalBids,
                pendingBids,
                paidCount:    paidAll.length,
                overdueCount: overdueAll.length
            },

            // Period metrics
            period_stats: {
                periodReceived,
                prevPeriodReceived,
                receivedChange,
                avgTicket,
                defaultRate,
                paidCount:    paidInPeriod.length,
                overdueCount: overdueInPeriod.length
            },

            // Projections
            projections: { proj30: projection30, proj60: projection60, proj90: projection90 },

            // Charts
            monthlyRevenue,
            statusDistribution,
            paymentMethods,
            revenueByType,
            newClientsPerMonth,

            // Feeds
            transactionFeed,
            refundFeed,

            // Rankings
            topClients,
            overdueClients,
            topProducts
        });
    } catch (error) {
        logger.error('Reports error:', error);
        res.status(500).send('Erro ao carregar relatórios');
    }
};
