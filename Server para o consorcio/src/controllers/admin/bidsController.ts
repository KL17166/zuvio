import { Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { paginate, paginationMeta, buildPageUrl } from '../../utils/pagination';

// GET /admin/bids
export const getBids = async (req: Request, res: Response) => {
    try {
        const status = (req.query.status as string) || '';
        const type   = (req.query.type   as string) || '';
        const search = (req.query.search as string) || '';
        const { page, limit, skip } = paginate(req);

        const where: any = {};
        if (status) where.status = status;
        if (type)   where.type   = type;
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

        const [bids, total] = await Promise.all([
            prisma.bid.findMany({
                where,
                include: {
                    subscription: {
                        include: {
                            user: true,
                            plan: { include: { product: true } }
                        }
                    }
                },
                orderBy: { createdAt: 'desc' },
                skip,
                take: limit
            }),
            prisma.bid.count({ where })
        ]);

        // Global summary (ignores filters)
        const allBids = await prisma.bid.findMany({ select: { status: true, amount: true } });
        const totalPending      = allBids.filter(b => b.status === 'PENDING').length;
        const totalApproved     = allBids.filter(b => b.status === 'APPROVED').length;
        const totalContemplated = allBids.filter(b => b.status === 'CONTEMPLATED').length;
        const totalRejected     = allBids.filter(b => b.status === 'REJECTED').length;
        const totalAmount       = allBids.reduce((s, b) => s + Number(b.amount), 0);

        const pagination = paginationMeta(total, page, limit);

        res.render('pages/bids/index', {
            path: '/bids',
            bids,
            summary: {
                totalPending,
                totalApproved,
                totalContemplated,
                totalRejected,
                totalAmount,
                total: allBids.length
            },
            status,
            type,
            search,
            pagination,
            buildPageUrl: (p: number) => buildPageUrl('/admin/bids', req.query as Record<string, any>, p)
        });
    } catch (error) {
        logger.error(error);
        res.status(500).send('Erro ao carregar lances');
    }
};

// GET /admin/bids/pending
export const getPendingBids = async (req: Request, res: Response) => {
    try {
        const pendingBids = await prisma.bid.findMany({
            where: { status: 'PENDING' },
            include: {
                subscription: {
                    include: {
                        user: true,
                        plan: { include: { product: true } }
                    }
                }
            },
            orderBy: [{ amount: 'desc' }, { createdAt: 'asc' }]
        });

        const totalAmount = pendingBids.reduce((s, b) => s + Number(b.amount), 0);

        res.render('pages/bids/pending', {
            path: '/bids',
            bids: pendingBids,
            totalAmount
        });
    } catch (error) {
        logger.error(error);
        res.status(500).send('Erro ao carregar lances pendentes');
    }
};

// GET /admin/bids/:id
export const getBidDetails = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;

        const bid = await prisma.bid.findUnique({
            where: { id },
            include: {
                subscription: {
                    include: {
                        user: true,
                        plan: { include: { product: true } },
                        installments: { orderBy: { number: 'asc' } }
                    }
                }
            }
        });

        if (!bid) {
            req.flash('error_msg', 'Lance não encontrado');
            return res.redirect('/admin/bids');
        }

        const installments       = bid.subscription.installments;
        const monthlyInstallment = installments[0]?.amount || 0;
        const installmentsFromBid = Number(monthlyInstallment) > 0
            ? Math.round(Number(bid.amount) / Number(monthlyInstallment))
            : 0;

        const creditValue    = Number(bid.subscription.creditValue);
        const bidPercentage  = creditValue > 0
            ? ((Number(bid.amount) / creditValue) * 100).toFixed(2)
            : '0.00';

        const paidInstallments    = installments.filter(i => i.status === 'PAID').length;
        const totalInstallments   = installments.length;
        const totalPaid           = installments
            .filter(i => i.status === 'PAID')
            .reduce((s, i) => s + Number(i.amount), 0);

        res.render('pages/bids/details', {
            path: '/bids',
            bid,
            installmentsFromBid,
            bidPercentage,
            paidInstallments,
            totalInstallments,
            totalPaid
        });
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao carregar detalhes do lance');
        res.redirect('/admin/bids');
    }
};

// POST /admin/bids/:id/approve
export const approveBid = async (req: Request, res: Response) => {
    const id = req.params.id as string;
    try {
        const bid = await prisma.bid.findUnique({ where: { id } });
        if (!bid || bid.status !== 'PENDING') {
            req.flash('error_msg', 'Lance não encontrado ou já processado');
            return res.redirect('/admin/bids');
        }
        await prisma.bid.update({ where: { id }, data: { status: 'APPROVED' } });
        req.flash('success_msg', 'Lance aprovado com sucesso!');
        res.redirect(`/admin/bids/${id}`);
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao aprovar lance');
        res.redirect(`/admin/bids/${id}`);
    }
};

// POST /admin/bids/:id/reject
export const rejectBid = async (req: Request, res: Response) => {
    const id = req.params.id as string;
    try {
        const bid = await prisma.bid.findUnique({ where: { id } });
        if (!bid || bid.status !== 'PENDING') {
            req.flash('error_msg', 'Lance não encontrado ou já processado');
            return res.redirect('/admin/bids');
        }
        await prisma.bid.update({ where: { id }, data: { status: 'REJECTED' } });
        req.flash('success_msg', 'Lance rejeitado');
        res.redirect('/admin/bids');
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao rejeitar lance');
        res.redirect(`/admin/bids/${id}`);
    }
};

// GET /admin/bids/draw
export const getDrawPage = async (req: Request, res: Response) => {
    try {
        const approvedBids = await prisma.bid.findMany({
            where: { status: 'APPROVED', isWinner: false },
            include: {
                subscription: {
                    include: {
                        user: true,
                        plan: { include: { product: true } }
                    }
                }
            },
            orderBy: { amount: 'desc' }
        });

        const groupedBids: Record<string, any> = {};
        approvedBids.forEach(bid => {
            const key = `${bid.subscription.plan.productId}-${bid.subscription.planId}`;
            if (!groupedBids[key]) {
                groupedBids[key] = {
                    product:     bid.subscription.plan.product,
                    plan:        bid.subscription.plan,
                    bids:        [],
                    totalAmount: 0
                };
            }
            groupedBids[key].bids.push(bid);
            groupedBids[key].totalAmount += Number(bid.amount);
        });

        res.render('pages/bids/draw', {
            path: '/bids',
            groupedBids,
            totalGroups: Object.keys(groupedBids).length,
            totalApproved: approvedBids.length
        });
    } catch (error) {
        logger.error(error);
        res.status(500).send('Erro ao carregar página de sorteio');
    }
};

// POST /admin/bids/draw
export const performDraw = async (req: Request, res: Response) => {
    try {
        const { productId, planId, numberOfWinners } = req.body;

        const eligibleBids = await prisma.bid.findMany({
            where: {
                status: 'APPROVED',
                isWinner: false,
                subscription: { planId, plan: { productId } }
            },
            include: { subscription: true },
            orderBy: { amount: 'desc' }
        });

        if (eligibleBids.length === 0) {
            req.flash('error_msg', 'Não há lances elegíveis para sorteio');
            return res.redirect('/admin/bids/draw');
        }

        const winners  = eligibleBids.slice(0, parseInt(numberOfWinners) || 1);
        const drawDate = new Date();

        const ops = winners.flatMap(winner => [
            prisma.bid.update({
                where: { id: winner.id },
                data: { status: 'CONTEMPLATED', isWinner: true, drawDate, contemplatedDate: drawDate }
            }),
            prisma.subscription.update({
                where: { id: winner.subscriptionId },
                data: { contemplated: true, contemplationDate: drawDate, contemplationType: 'BID', status: 'CONTEMPLATED' }
            })
        ]);

        await prisma.$transaction(ops);

        req.flash('success_msg', `${winners.length} lance(s) contemplado(s) com sucesso!`);
        res.redirect('/admin/bids');
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao realizar sorteio');
        res.redirect('/admin/bids/draw');
    }
};
