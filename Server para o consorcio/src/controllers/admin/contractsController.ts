import { Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { paginate, paginationMeta, buildPageUrl } from '../../utils/pagination';
import { generatePaymentToken } from '../../security/paymentToken';

// GET /admin/contracts - Lista todos os contratos
export const getContracts = async (req: Request, res: Response) => {
    try {
        const status = (req.query.status as string) || '';
        const search = (req.query.search as string) || '';
        const { page, limit, skip } = paginate(req);

        const where: any = {};

        if (status) {
            where.status = status;
        }

        if (search) {
            where.OR = [
                { user: { name: { contains: search } } },
                { user: { cpf: { contains: search } } },
                { groupNumber: { contains: search } },
                { quotaNumber: { contains: search } }
            ];
        }

        const [contracts, total, totalActive, totalContemplated, totalPending] = await Promise.all([
            prisma.subscription.findMany({
                where,
                include: {
                    user: true,
                    plan: {
                        include: {
                            product: true
                        }
                    },
                    installments: {
                        orderBy: { number: 'asc' }
                    },
                    bids: true
                },
                orderBy: { createdAt: 'desc' },
                skip,
                take: limit
            }),
            prisma.subscription.count({ where }),
            prisma.subscription.count({ where: { ...where, status: 'ACTIVE' } }),
            prisma.subscription.count({ where: { ...where, contemplated: true } }),
            prisma.subscription.count({ where: { ...where, status: 'PENDING' } })
        ]);

        const pagination = paginationMeta(total, page, limit);

        res.render('pages/contracts/index', {
            path: '/contracts',
            contracts,
            summary: {
                totalActive,
                totalContemplated,
                totalPending,
                total
            },
            status,
            search,
            pagination,
            buildPageUrl: (p: number) => buildPageUrl('/admin/contracts', req.query as Record<string, any>, p)
        });
    } catch (error) {
        logger.error(error);
        res.status(500).send('Erro ao carregar contratos');
    }
};

// GET /admin/contracts/:id - Detalhes do contrato
export const getContractDetails = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;

        const contract = await prisma.subscription.findUnique({
            where: { id },
            include: {
                user: true,
                plan: {
                    include: {
                        product: true
                    }
                },
                installments: {
                    orderBy: { number: 'asc' }
                },
                bids: {
                    orderBy: { createdAt: 'desc' }
                }
            }
        });

        if (!contract) {
            req.flash('error_msg', 'Contrato não encontrado');
            return res.redirect('/admin/contracts');
        }

        // Calculate progress from actual installment records
        const paidInstallments = contract.installments.filter((i: any) => i.status === 'PAID').length;

        const totalPaid = contract.installments
            .filter((i: any) => i.status === 'PAID')
            .reduce((sum: number, i: any) => sum + Number(i.amount), 0);

        const progress = contract.totalInstallments > 0
            ? (paidInstallments / contract.totalInstallments) * 100
            : 0;

        res.render('pages/contracts/details', {
            path: '/contracts',
            contract,
            stats: {
                paidInstallments,
                totalPaid,
                progress: progress.toFixed(1)
            }
        });
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao carregar contrato');
        res.redirect('/admin/contracts');
    }
};

// GET /admin/contracts/new - Formulário de novo contrato
export const getNewContract = async (req: Request, res: Response) => {
    try {
        const clientId = (req.query.clientId as string)?.trim() || '';
        logger.info('Pre-selecting client via URL:', clientId);

        const clients = await prisma.user.findMany({
            where: { role: 'CLIENT' },
            orderBy: { name: 'asc' }
        });

        const plans = await prisma.consortiumPlan.findMany({
            where: { active: true },
            include: {
                product: true
            },
            orderBy: { name: 'asc' }
        });

        res.render('pages/contracts/form', {
            path: '/contracts',
            editing: false,
            clients,
            clientId, // Pass it to view
            plans
        });
    } catch (error) {
        logger.error(error);
        res.status(500).send('Erro ao carregar formulário');
    }
};

// POST /admin/contracts/new - Criar contrato
export const createContract = async (req: Request, res: Response) => {
    try {
        const { userId, planId, groupNumber, quotaNumber } = req.body;

        const plan = await prisma.consortiumPlan.findUnique({
            where: { id: planId },
            include: { product: true }
        });

        if (!plan) {
            req.flash('error_msg', 'Plano não encontrado');
            return res.redirect('/admin/contracts/new');
        }

        // Calculate credit value with fees
        const productPrice = Number(plan.product.price);
        const totalRate = Number(plan.adminFeeRate) + Number(plan.fundRate);
        const creditValue = productPrice * (1 + totalRate / 100);
        const monthlyInstallment = creditValue / plan.durationMonths;

        // Total installments = durationMonths (adesão é a 1ª parcela)
        const totalInstallments = plan.durationMonths;

        // Create subscription + all installments atomically so a partial failure
        // never leaves a subscription record with no installments.
        const subscription = await prisma.$transaction(async (tx) => {
            const sub = await tx.subscription.create({
                data: {
                    userId,
                    planId,
                    groupNumber,
                    quotaNumber,
                    creditValue,
                    balanceDue: creditValue,
                    totalInstallments,
                    status: 'PENDING'
                }
            });

            const today = new Date();
            const installmentsData: any[] = [];

            // Adesão (installment #1) — due today
            installmentsData.push({
                subscriptionId: sub.id,
                idTokenPay: generatePaymentToken(sub.id, 1, userId),
                number: 1,
                amount: monthlyInstallment,
                dueDate: today,
                status: 'PENDING'
            });

            // Regular installments (2 to N)
            for (let i = 2; i <= plan.durationMonths; i++) {
                const dueDate = new Date(today);
                dueDate.setMonth(dueDate.getMonth() + (i - 1));
                dueDate.setDate(10);
                installmentsData.push({
                    subscriptionId: sub.id,
                    idTokenPay: generatePaymentToken(sub.id, i, userId),
                    number: i,
                    amount: monthlyInstallment,
                    dueDate,
                    status: 'PENDING'
                });
            }

            await tx.installment.createMany({ data: installmentsData });
            return sub;
        });

        req.flash('success_msg', 'Contrato criado com sucesso!');
        res.redirect(`/admin/contracts/${subscription.id}`);
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao criar contrato');
        res.redirect('/admin/contracts/new');
    }
};

// POST /admin/contracts/:id/contemplate - Contemplar contrato
export const contemplateContract = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;
        const { contemplationType } = req.body;

        // Validate contract is ACTIVE before contemplating
        const contract = await prisma.subscription.findUnique({ where: { id } });
        if (!contract || contract.status !== 'ACTIVE') {
            req.flash('error_msg', 'Contrato deve estar ativo para ser contemplado');
            return res.redirect(`/admin/contracts/${id}`);
        }

        // Fix 11: Block re-contemplation.
        // The status guard above already rejects CONTEMPLATED status; this catches the edge
        // case where status is ACTIVE but the contemplated flag is true due to a data inconsistency.
        if (contract.contemplated) {
            req.flash('error_msg', 'Este contrato já foi contemplado anteriormente e não pode ser contemplado novamente');
            return res.redirect(`/admin/contracts/${id}`);
        }

        await prisma.subscription.update({
            where: { id },
            data: {
                contemplated: true,
                contemplationDate: new Date(),
                contemplationType: contemplationType || 'DIRECT',
                status: 'CONTEMPLATED'
            }
        });

        req.flash('success_msg', 'Contrato contemplado com sucesso!');
        res.redirect(`/admin/contracts/${id}`);
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao contemplar contrato');
        res.redirect(`/admin/contracts/${req.params.id}`);
    }
};

// POST /admin/contracts/:id/cancel - Cancelar contrato
export const cancelContract = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;

        // Cancel subscription and zero out balance
        await prisma.subscription.update({
            where: { id },
            data: {
                status: 'CANCELLED',
                balanceDue: 0
            }
        });

        // Cancel pending and overdue installments
        await prisma.installment.updateMany({
            where: {
                subscriptionId: id,
                status: { in: ['PENDING', 'OVERDUE'] }
            },
            data: {
                status: 'CANCELLED'
            }
        });

        req.flash('success_msg', 'Contrato cancelado');
        res.redirect(`/admin/contracts/${id}`);
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao cancelar contrato');
        res.redirect(`/admin/contracts/${req.params.id}`);
    }
};
