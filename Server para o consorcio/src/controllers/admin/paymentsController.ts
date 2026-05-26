import { Request, Response, NextFunction } from 'express';
import { prisma } from '../../config/database';
import { z } from 'zod';
import { paginate, paginationMeta, buildPageUrl } from '../../utils/pagination';

// GET /admin/payments
export const getPayments = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const status  = (req.query.status  as string) || 'ALL';
        const month   = (req.query.month   as string) || '';
        const search  = (req.query.search  as string) || '';
        const method  = (req.query.method  as string) || '';
        const { page, limit, skip } = paginate(req);

        const where: any = {};

        if (status && status !== 'ALL') {
            where.status = status;
        }

        if (method) {
            where.paymentMethod = method;
        }

        if (month) {
            const [year, monthNum] = month.split('-');
            where.dueDate = {
                gte: new Date(parseInt(year), parseInt(monthNum) - 1, 1),
                lte: new Date(parseInt(year), parseInt(monthNum), 0)
            };
        }

        if (search) {
            where.subscription = {
                user: {
                    OR: [
                        { name:  { contains: search } },
                        { email: { contains: search } },
                        { cpf:   { contains: search } }
                    ]
                }
            };
        }

        const [installments, total] = await Promise.all([
            prisma.installment.findMany({
                where,
                include: {
                    subscription: {
                        include: {
                            user: true,
                            plan: { include: { product: true } }
                        }
                    }
                },
                orderBy: { dueDate: 'asc' },
                skip,
                take: limit
            }),
            prisma.installment.count({ where })
        ]);

        // ── All-installments summary (ignores filters for totals) ────────
        const [summaryResult] = await prisma.$queryRawUnsafe<any[]>(`
            SELECT
                COALESCE(SUM(CASE WHEN status = 'PENDING' THEN amount ELSE 0 END), 0) AS "totalPending",
                COALESCE(SUM(CASE WHEN status = 'OVERDUE'  THEN amount ELSE 0 END), 0) AS "totalOverdue",
                COALESCE(SUM(CASE WHEN status = 'PAID'     THEN amount ELSE 0 END), 0) AS "totalPaid",
                COALESCE(SUM(CASE WHEN status = 'REFUNDED' THEN amount ELSE 0 END), 0) AS "totalRefunded",
                COUNT(*)                                                                AS "totalCount",
                COUNT(CASE WHEN status = 'PAID'     THEN 1 END)                        AS "paidCount",
                COUNT(CASE WHEN status = 'PENDING'  THEN 1 END)                        AS "pendingCount",
                COUNT(CASE WHEN status = 'OVERDUE'  THEN 1 END)                        AS "overdueCount",
                COUNT(CASE WHEN status = 'REFUNDED' THEN 1 END)                        AS "refundedCount"
            FROM installments
        `);

        // ── This month received ──────────────────────────────────────────
        const now = new Date();
        const firstOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const [monthResult] = await prisma.$queryRawUnsafe<any[]>(`
            SELECT COALESCE(SUM(amount), 0) AS "receivedThisMonth"
            FROM installments
            WHERE status = 'PAID'
              AND "paymentDate" >= '${firstOfMonth.toISOString()}'
        `);

        // ── Near-due (next 7 days, still PENDING) ────────────────────────
        const in7Days = new Date(now);
        in7Days.setDate(now.getDate() + 7);
        const nearDueCount = await prisma.installment.count({
            where: {
                status: 'PENDING',
                dueDate: { gte: now, lte: in7Days }
            }
        });

        // ── Payment method list for filter dropdown ───────────────────────
        const methodsRaw = await prisma.installment.findMany({
            where: { status: 'PAID', paymentMethod: { not: null } },
            select: { paymentMethod: true },
            distinct: ['paymentMethod']
        });
        const paymentMethodOptions = methodsRaw
            .map(m => m.paymentMethod)
            .filter(Boolean) as string[];

        const pagination = paginationMeta(total, page, limit);

        res.render('pages/payments/index', {
            path: '/payments',
            installments,
            summary: {
                totalPending:   Number(summaryResult?.totalPending   || 0),
                totalOverdue:   Number(summaryResult?.totalOverdue   || 0),
                totalPaid:      Number(summaryResult?.totalPaid      || 0),
                totalRefunded:  Number(summaryResult?.totalRefunded  || 0),
                paidCount:      Number(summaryResult?.paidCount      || 0),
                pendingCount:   Number(summaryResult?.pendingCount   || 0),
                overdueCount:   Number(summaryResult?.overdueCount   || 0),
                refundedCount:  Number(summaryResult?.refundedCount  || 0),
                count:          total,
                receivedThisMonth: Number(monthResult?.receivedThisMonth || 0),
                nearDueCount
            },
            status,
            month,
            search,
            method,
            paymentMethodOptions,
            pagination,
            buildPageUrl: (p: number) => buildPageUrl('/admin/payments', req.query as Record<string, any>, p)
        });
    } catch (error) {
        next(error);
    }
};

// GET /admin/payments/calendar
export const getPaymentsCalendar = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const year  = parseInt(req.query.year  as string) || new Date().getFullYear();
        const month = parseInt(req.query.month as string) || new Date().getMonth() + 1;

        const startDate = new Date(year, month - 1, 1);
        const endDate   = new Date(year, month, 0);

        const installments = await prisma.installment.findMany({
            where: { dueDate: { gte: startDate, lte: endDate } },
            include: {
                subscription: {
                    include: {
                        user: true,
                        plan: { include: { product: true } }
                    }
                }
            },
            orderBy: { dueDate: 'asc' }
        });

        const calendar: Record<number, any[]> = {};
        installments.forEach(inst => {
            const day = inst.dueDate.getDate();
            if (!calendar[day]) calendar[day] = [];
            calendar[day].push(inst);
        });

        res.render('pages/payments/calendar', {
            path: '/payments',
            calendar,
            year,
            month
        });
    } catch (error) {
        next(error);
    }
};

const updatePaymentSchema = z.object({
    status:        z.enum(['PAID', 'PENDING', 'OVERDUE']),
    paymentDate:   z.string().optional().nullable(),
    paymentMethod: z.string().optional().nullable(),
    _csrf:         z.string().optional()
});

// POST /admin/payments/:id/update
export const updatePayment = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const id = req.params.id as string;

        const validation = updatePaymentSchema.safeParse(req.body);
        if (!validation.success) {
            req.flash('error_msg', 'Dados inválidos: ' + validation.error.issues.map(i => i.message).join(', '));
            return res.redirect('/admin/payments');
        }

        const { status, paymentDate, paymentMethod } = validation.data;
        const adminUser = (req as any).session?.user;

        await prisma.$transaction(async (tx) => {
            const inst = await tx.installment.findUnique({
                where: { id },
                include: { subscription: { include: { installments: true } } }
            });
            if (!inst) throw new Error('Parcela não encontrada');

            const currentOldStatus = inst.status;

            await tx.installment.update({
                where: { id },
                data: {
                    status: status,
                    paymentMethod: status === 'PAID' ? (paymentMethod || null) : null,
                    paymentDate:   status === 'PAID' ? (paymentDate ? new Date(paymentDate) : new Date()) : null
                }
            });

            await tx.auditLog.create({
                data: {
                    userId:   adminUser?.id || null,
                    action:   'UPDATE_PAYMENT',
                    resource: 'installment',
                    details:  JSON.stringify({
                        installmentId: id,
                        oldStatus: currentOldStatus,
                        newStatus: status,
                        adminName: adminUser?.name || 'Unknown'
                    }),
                    ipAddress: req.ip || req.socket.remoteAddress || 'unknown'
                }
            });

            if (currentOldStatus !== 'PAID' && status === 'PAID') {
                const subUpdate: any = {
                    paidInstallments: { increment: 1 },
                    balanceDue:       { decrement: Number(inst.amount) }
                };
                if (inst.number === 1 && inst.subscription.status === 'PENDING') {
                    subUpdate.status = 'ACTIVE';
                }
                await tx.subscription.update({ where: { id: inst.subscriptionId }, data: subUpdate });

                const allPaid = inst.subscription.installments.every(
                    i => i.id === id ? true : (i.status === 'PAID' || i.status === 'CANCELLED')
                );
                if (allPaid) {
                    await tx.subscription.update({ where: { id: inst.subscriptionId }, data: { status: 'COMPLETED' } });
                }
            } else if (currentOldStatus === 'PAID' && status !== 'PAID') {
                await tx.subscription.update({
                    where: { id: inst.subscriptionId },
                    data: {
                        paidInstallments: { decrement: 1 },
                        balanceDue:       { increment: Number(inst.amount) }
                    }
                });

                const hasPending = inst.subscription.installments.some(
                    i => i.id === id ? true : ['PENDING', 'OVERDUE', 'REFUNDED'].includes(i.status)
                );
                if (hasPending && inst.subscription.status === 'COMPLETED') {
                    await tx.subscription.update({ where: { id: inst.subscriptionId }, data: { status: 'ACTIVE' } });
                }
            }
        }, { isolationLevel: 'Serializable', timeout: 10000 });

        req.flash('success_msg', 'Pagamento atualizado com sucesso!');
        res.redirect('/admin/payments');
    } catch (error) {
        next(error);
    }
};

// GET /admin/payments/overdue
export const getOverduePayments = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        await prisma.installment.updateMany({
            where: {
                status: 'PENDING',
                dueDate: { lt: today },
                subscription: { status: { in: ['ACTIVE', 'CONTEMPLATED'] } }
            },
            data: { status: 'OVERDUE' }
        });

        const overdueInstallments = await prisma.installment.findMany({
            where: { status: 'OVERDUE' },
            include: {
                subscription: {
                    include: {
                        user: true,
                        plan: { include: { product: true } }
                    }
                }
            },
            orderBy: { dueDate: 'asc' }
        });

        const groupedByUser: Record<string, any> = {};
        overdueInstallments.forEach(inst => {
            const uid = inst.subscription.userId;
            if (!groupedByUser[uid]) {
                groupedByUser[uid] = {
                    user:         inst.subscription.user,
                    installments: [],
                    totalOverdue: 0
                };
            }
            groupedByUser[uid].installments.push(inst);
            groupedByUser[uid].totalOverdue += Number(inst.amount);
        });

        res.render('pages/payments/overdue', {
            path: '/payments',
            groupedByUser,
            totalOverdue: overdueInstallments.reduce((s, i) => s + Number(i.amount), 0)
        });
    } catch (error) {
        next(error);
    }
};
