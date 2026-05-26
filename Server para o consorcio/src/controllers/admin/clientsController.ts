import { Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { paginate, paginationMeta, buildPageUrl } from '../../utils/pagination';
import { hashPassword } from '../../security/password';

// GET /admin/clients/new - Formulário de criação
export const getNewClient = (req: Request, res: Response) => {
    res.render('pages/clients/form', {
        path: '/clients',
        editing: false,
        client: {}
    });
};

// POST /admin/clients/new - Criar cliente
export const createClient = async (req: Request, res: Response) => {
    try {
        const { name, email, cpf, phone, password, address_cep, address_street, address_number, address_complement, address_neighborhood, address_city, address_state } = req.body;

        // Check if email or cpf already exists
        const existingUser = await prisma.user.findFirst({
            where: { OR: [{ email }, { cpf: cpf.replace(/\D/g, '') }] }
        });

        if (existingUser) {
            req.flash('error_msg', 'Email ou CPF já cadastrado.');
            return res.redirect('/admin/clients/new');
        }

        const hashedPassword = await hashPassword(password);

        let formattedAddress = null;
        if (address_street) {
             formattedAddress = JSON.stringify({
                 cep: address_cep || '',
                 street: address_street,
                 number: address_number || '',
                 complement: address_complement || '',
                 neighborhood: address_neighborhood || '',
                 city: address_city || '',
                 state: address_state || ''
             });
        }

        await prisma.user.create({
            data: {
                name,
                email,
                cpf: cpf.replace(/\D/g, ''),
                phone: phone || null,
                passwordHash: hashedPassword,
                role: 'CLIENT',
                address: formattedAddress
            }
        });

        req.flash('success_msg', 'Cliente cadastrado com sucesso!');
        res.redirect('/admin/clients');
    } catch (error) {
        logger.error('Create client error:', error);
        req.flash('error_msg', 'Erro ao criar cliente.');
        res.redirect('/admin/clients/new');
    }
};

// GET /admin/clients - Lista todos os clientes
export const getClients = async (req: Request, res: Response) => {
    try {
        const search = (req.query.search as string) || '';
        const status = (req.query.status as string) || '';
        const { page, limit, skip } = paginate(req);

        const where: any = {
            role: 'CLIENT'
        };

        if (status) {
            where.kycStatus = status;
        }

        if (search) {
            where.OR = [
                { name: { contains: search } },
                { cpf: { contains: search } },
                { email: { contains: search } }
            ];
        }

        const [clients, total] = await Promise.all([
            prisma.user.findMany({
                where,
                include: {
                    subscriptions: {
                        include: {
                            plan: {
                                include: {
                                    product: true
                                }
                            }
                        }
                    }
                },
                orderBy: { createdAt: 'desc' },
                skip,
                take: limit
            }),
            prisma.user.count({ where })
        ]);

        // Calculate stats for each client
        const clientsWithStats = clients.map(client => {
            const activeContracts = client.subscriptions.filter((s: any) => s.status === 'ACTIVE').length;
            const totalContracts = client.subscriptions.length;

            return {
                ...client,
                activeContracts,
                totalContracts
            };
        });

        const pagination = paginationMeta(total, page, limit);

        res.render('pages/clients/index', {
            path: '/clients',
            clients: clientsWithStats,
            search,
            status,
            pagination,
            buildPageUrl: (p: number) => buildPageUrl('/admin/clients', req.query as Record<string, any>, p)
        });
    } catch (error) {
        logger.error(error);
        res.status(500).send('Erro ao carregar clientes');
    }
};

// GET /admin/clients/:id - Detalhes do cliente
export const getClientDetails = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;

        const client = await prisma.user.findUnique({
            where: { id },
            include: {
                subscriptions: {
                    include: {
                        plan: {
                            include: {
                                product: true
                            }
                        },
                        installments: {
                            orderBy: { number: 'asc' }
                        },
                        bids: true
                    }
                }
            }
        });

        if (!client) {
            req.flash('error_msg', 'Cliente não encontrado');
            return res.redirect('/admin/clients');
        }

        // Calculate payment stats
        const allInstallments = client.subscriptions.flatMap((s: any) =>
            s.installments.map((i: any) => ({
                ...i,
                subscriptionId: s.id,
                productName: s.plan.product.name,
                planName: s.plan.name
            }))
        );

        // Sort installments: overdue first, then pending, then paid
        const statusOrder: Record<string, number> = { 'OVERDUE': 0, 'PENDING': 1, 'PAID': 2, 'CANCELLED': 3, 'REFUNDED': 4 };
        allInstallments.sort((a: any, b: any) => {
            const orderDiff = statusOrder[a.status] - statusOrder[b.status];
            if (orderDiff !== 0) return orderDiff;
            return new Date(a.dueDate).getTime() - new Date(b.dueDate).getTime();
        });

        const paidInstallments = allInstallments.filter((i: any) => i.status === 'PAID').length;
        const overdueInstallments = allInstallments.filter((i: any) => i.status === 'OVERDUE').length;
        const pendingInstallments = allInstallments.filter((i: any) => i.status === 'PENDING').length;

        // Get all bids
        const allBids = client.subscriptions.flatMap((s: any) =>
            s.bids.map((b: any) => ({
                ...b,
                productName: s.plan.product.name,
                planName: s.plan.name
            }))
        );
        allBids.sort((a: any, b: any) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

        // Add paidInstallments and totalInstallments to each subscription
        const subscriptionsWithStats = client.subscriptions.map((sub: any) => ({
            ...sub,
            paidInstallments: sub.installments.filter((i: any) => i.status === 'PAID').length,
            totalInstallments: sub.installments.length
        }));

        res.render('pages/clients/details', {
            path: '/clients',
            client: {
                ...client,
                subscriptions: subscriptionsWithStats
            },
            stats: {
                paidInstallments,
                overdueInstallments,
                pendingInstallments,
                totalInstallments: allInstallments.length
            },
            allInstallments,
            allBids
        });
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao carregar detalhes do cliente');
        res.redirect('/admin/clients');
    }
};

// GET /admin/clients/:id/edit - Formulário de edição
export const getEditClient = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;

        const client = await prisma.user.findUnique({
            where: { id }
        });

        if (!client) {
            req.flash('error_msg', 'Cliente não encontrado');
            return res.redirect('/admin/clients');
        }

        res.render('pages/clients/form', {
            path: '/clients',
            editing: true,
            client
        });
    } catch (error) {
        logger.error(error);
        res.redirect('/admin/clients');
    }
};

// POST /admin/clients/:id/edit - Atualizar cliente
export const updateClient = async (req: Request, res: Response) => {
    const id = req.params.id as string;
    try {
        const { name, email, phone, address_cep, address_street, address_number, address_complement, address_neighborhood, address_city, address_state } = req.body;

        // Construct structured address object
        const addressData = {
            cep: address_cep,
            street: address_street,
            number: address_number,
            complement: address_complement,
            neighborhood: address_neighborhood,
            city: address_city,
            state: address_state
        };

        await prisma.user.update({
            where: { id },
            data: {
                name,
                email,
                phone,
                address: JSON.stringify(addressData)
            }
        });

        req.flash('success_msg', 'Cliente atualizado com sucesso!');
        res.redirect(`/admin/clients/${id}`);
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao atualizar cliente');
        res.redirect(`/admin/clients/${id}/edit`);
    }
};

// GET /admin/clients/:id/delete - Deletar cliente
export const deleteClient = async (req: Request, res: Response) => {
    const id = req.params.id as string;
    try {
        // Check if has active contracts
        const activeContracts = await prisma.subscription.count({
            where: {
                userId: id,
                status: { in: ['ACTIVE', 'PENDING'] }
            }
        });

        if (activeContracts > 0) {
            req.flash('error_msg', 'Não é possível excluir cliente com contratos ativos');
            return res.redirect('/admin/clients');
        }

        await prisma.user.delete({
            where: { id }
        });

        req.flash('success_msg', 'Cliente removido com sucesso!');
        res.redirect('/admin/clients');
    } catch (error) {
        logger.error(error);
        req.flash('error_msg', 'Erro ao excluir cliente');
        res.redirect('/admin/clients');
    }
};
