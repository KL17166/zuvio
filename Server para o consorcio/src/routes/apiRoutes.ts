import { Router, Request, Response, NextFunction } from 'express';
import { prisma } from '../config/database';
import { authenticate, AuthPayload } from '../middlewares/authMiddleware';
import { PixGoService } from '../services/gateways/pixGoService';
import { SigiloPayService } from '../services/gateways/sigiloPayService';
import { checkOwnership } from '../middlewares/idorMiddleware';
import { logger } from '../config/logger';
import { generatePaymentToken, verifyPaymentToken } from '../security/paymentToken';

const router = Router();

// ========================================
// MIDDLEWARE - Ownership Validation
// ========================================

// ========================================
// SUBSCRIPTIONS (Contratos do Usuário)
// ========================================

// Helper para cálculo de valor da parcela (Amortização)
const calculateInstallmentValue = (baseAmount: number, installmentIndex: number, nextInstallmentIndex: number): number => {
    if (installmentIndex <= nextInstallmentIndex) {
        return baseAmount;
    }
    // Distância em meses para a antecipação
    const monthsInAdvance = installmentIndex - nextInstallmentIndex;
    // Taxa de desconto mensal (0.5%)
    const discountRate = 0.005;

    // Fórmula de Valor Presente: VP = VF / (1 + i)^n
    return baseAmount / (1 + (discountRate * monthsInAdvance));
};

// Helper para tratar imageUrls que podem vir como string malformada do banco
const safeParseImageUrls = (imageUrls: any): string[] => {
    if (!imageUrls) return [];
    if (Array.isArray(imageUrls)) return imageUrls;
    if (typeof imageUrls !== 'string') return [];

    try {
        // Tenta parse normal (JSON)
        return JSON.parse(imageUrls);
    } catch (e) {
        try {
            // Tenta tratar aspas simples se vierem do seed ou input manual
            const normalized = imageUrls.replace(/'/g, '"').replace(/,\s*]/g, ']');
            return JSON.parse(normalized);
        } catch (e2) {
            // Se tudo falhar, retorna como item único se parecer URL
            if (imageUrls.startsWith('http')) return [imageUrls];
            return [];
        }
    }
};

// GET /api/subscriptions/:userId - Listar contratos do usuário
router.get('/subscriptions/:userId', authenticate, checkOwnership('user', 'userId'), async (req: Request, res: Response) => {
    try {
        const userId = req.params.userId as string;

        // Auto-cancel pending subscriptions older than 3 days
        const threeDaysAgo = new Date();
        threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);

        await prisma.subscription.updateMany({
            where: {
                userId,
                status: 'PENDING',
                createdAt: { lt: threeDaysAgo }
            },
            data: { status: 'CANCELLED', balanceDue: 0 }
        });

        const subscriptions = await prisma.subscription.findMany({
            where: {
                userId,
                status: { not: 'CANCELLED' } // Hide cancelled from main list
            },
            include: {
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
            },
            orderBy: { createdAt: 'desc' }
        });

        // Format response for app — skip subscriptions whose product was deleted
        const orphanIds: string[] = [];
        const formattedSubscriptions = subscriptions
            .filter((sub: any) => {
                if (!sub.plan?.product) {
                    orphanIds.push(sub.id);
                    return false;
                }
                return true;
            })
            .map((sub: any) => {
            // Determine next installment index (0-based, includes adesão)
            const paidIndices = new Set(sub.installments.filter((i: any) => i.status === 'PAID').map((i: any) => i.number));
            let nextIndex = sub.totalInstallments + 1;
            for (let i = 1; i <= sub.totalInstallments; i++) {
                if (!paidIndices.has(i)) {
                    nextIndex = i;
                    break;
                }
            }

            return {
                id: sub.id,
                groupNumber: sub.groupNumber,
                quotaNumber: sub.quotaNumber,
                creditValue: Number(sub.creditValue),
                balanceDue: Number(sub.balanceDue),
                status: sub.status,
                contemplated: sub.contemplated,
                contemplationDate: sub.contemplationDate,
                contemplationType: sub.contemplationType,
                paidInstallments: sub.paidInstallments,
                totalInstallments: sub.totalInstallments,
                createdAt: sub.createdAt,
                plan: {
                    id: sub.plan.id,
                    name: sub.plan.name,
                    durationMonths: sub.plan.durationMonths,
                    adminFeeRate: Number(sub.plan.adminFeeRate),
                    fundRate: Number(sub.plan.fundRate),
                    monthlyInstallment: Number(sub.creditValue) / sub.plan.durationMonths
                },
                product: {
                    id: sub.plan.product.id,
                    name: sub.plan.product.name,
                    imageUrl: sub.plan.product.imageUrl,
                    imageUrls: safeParseImageUrls(sub.plan.product.imageUrls),
                    price: Number(sub.plan.product.price),
                    category: sub.plan.product.category
                },
                installments: sub.installments.map((inst: any) => ({
                    id: inst.id,
                    idTokenPay: inst.idTokenPay,
                    number: inst.number,
                    amount: Number(inst.amount),
                    valueToPay: calculateInstallmentValue(Number(inst.amount), inst.number, nextIndex), // Server-side calculation
                    dueDate: inst.dueDate,
                    status: inst.status,
                    paymentDate: inst.paymentDate,
                    paymentMethod: inst.paymentMethod
                })),
                bids: sub.bids.map((bid: any) => ({
                    id: bid.id,
                    type: bid.type,
                    percentage: Number(bid.percentage),
                    amount: Number(bid.amount),
                    status: bid.status,
                    isWinner: bid.isWinner,
                    createdAt: bid.createdAt
                }))
            };
        });

        // Auto-cancel orphan subscriptions (product deleted) so they never appear again
        if (orphanIds.length > 0) {
            logger.warn(`Auto-cancelling ${orphanIds.length} orphan subscription(s) with deleted products: ${orphanIds.join(', ')}`);
            await prisma.subscription.updateMany({
                where: { id: { in: orphanIds } },
                data: { status: 'CANCELLED', balanceDue: 0 }
            });
        }

        res.json(formattedSubscriptions);
    } catch (error) {
        logger.error('Error fetching subscriptions:', error);
        res.status(500).json({ error: 'Erro ao buscar contratos' });
    }
});

// GET /api/subscription/:subscriptionId - Detalhes de um único contrato
router.get('/subscription/:subscriptionId', authenticate, async (req: Request, res: Response) => {
    const user = req.user as AuthPayload;
    try {
        const subscriptionId = req.params.subscriptionId as string;

        const sub = await prisma.subscription.findUnique({
            where: { id: subscriptionId },
            include: {
                plan: { include: { product: true } },
                installments: { orderBy: { number: 'asc' } },
                bids: { orderBy: { createdAt: 'desc' } }
            }
        });

        if (!sub) {
            res.status(404).json({ error: 'Contrato não encontrado' });
            return;
        }

        // Ownership check
        if (sub.userId !== user.userId) {
            res.status(403).json({ error: 'Acesso negado' });
            return;
        }

        const paidIndices = new Set(sub.installments.filter((i: any) => i.status === 'PAID').map((i: any) => i.number));
        let nextIndex = sub.totalInstallments + 1;
        for (let i = 1; i <= sub.totalInstallments; i++) {
            if (!paidIndices.has(i)) { nextIndex = i; break; }
        }

        res.json({
            id: sub.id,
            groupNumber: sub.groupNumber,
            quotaNumber: sub.quotaNumber,
            creditValue: Number(sub.creditValue),
            balanceDue: Number(sub.balanceDue),
            status: sub.status,
            contemplated: sub.contemplated,
            contemplationDate: sub.contemplationDate,
            contemplationType: sub.contemplationType,
            paidInstallments: sub.paidInstallments,
            totalInstallments: sub.totalInstallments,
            createdAt: sub.createdAt,
            plan: {
                id: sub.plan.id,
                name: sub.plan.name,
                durationMonths: sub.plan.durationMonths,
                adminFeeRate: Number(sub.plan.adminFeeRate),
                fundRate: Number(sub.plan.fundRate),
                monthlyInstallment: Number(sub.creditValue) / sub.plan.durationMonths
            },
            product: {
                id: sub.plan.product.id,
                name: sub.plan.product.name,
                imageUrl: sub.plan.product.imageUrl,
                imageUrls: safeParseImageUrls(sub.plan.product.imageUrls),
                price: Number(sub.plan.product.price),
                category: sub.plan.product.category
            },
            installments: sub.installments.map((inst: any) => ({
                id: inst.id,
                idTokenPay: inst.idTokenPay,
                number: inst.number,
                amount: Number(inst.amount),
                valueToPay: calculateInstallmentValue(Number(inst.amount), inst.number, nextIndex),
                dueDate: inst.dueDate,
                status: inst.status,
                paymentDate: inst.paymentDate,
                paymentMethod: inst.paymentMethod
            })),
            bids: sub.bids.map((bid: any) => ({
                id: bid.id,
                type: bid.type,
                percentage: Number(bid.percentage),
                amount: Number(bid.amount),
                status: bid.status,
                isWinner: bid.isWinner,
                createdAt: bid.createdAt
            }))
        });
    } catch (error) {
        logger.error('Error fetching subscription detail:', error);
        res.status(500).json({ error: 'Erro ao buscar contrato' });
    }
});

// POST /api/subscriptions/:subscriptionId/cancel - Cancelar contrato (cliente)
// Only PENDING subscriptions can be self-cancelled (no payment made yet).
// ACTIVE/CONTEMPLATED subscriptions require admin intervention.
router.post('/subscriptions/:subscriptionId/cancel', authenticate, async (req: Request, res: Response) => {
    const user = req.user as AuthPayload;
    try {
        const subscriptionId = req.params.subscriptionId as string;

        const sub = await prisma.subscription.findUnique({
            where: { id: subscriptionId }
        });

        if (!sub) {
            res.status(404).json({ error: 'Contrato não encontrado' });
            return;
        }

        if (sub.userId !== user.userId) {
            res.status(403).json({ error: 'Acesso negado' });
            return;
        }

        if (sub.status !== 'PENDING') {
            res.status(400).json({
                error: 'Apenas contratos pendentes podem ser cancelados pelo cliente. Para cancelar um contrato ativo, entre em contato com o suporte.'
            });
            return;
        }

        await prisma.$transaction(async (tx) => {
            await tx.subscription.update({
                where: { id: subscriptionId },
                data: { status: 'CANCELLED', balanceDue: 0 }
            });
            await tx.installment.updateMany({
                where: { subscriptionId, status: { in: ['PENDING', 'OVERDUE'] } },
                data: { status: 'CANCELLED' }
            });
        });

        logger.info(`Subscription ${subscriptionId} cancelled by client ${user.userId}`);
        res.json({ success: true, message: 'Contrato cancelado com sucesso.' });
    } catch (error) {
        logger.error('Error cancelling subscription:', error);
        res.status(500).json({ error: 'Erro ao cancelar contrato' });
    }
});

// ========================================
// BIDS (Lances)
// ========================================

// POST /api/subscriptions - Criar novo contrato (Requer token no body)
router.post('/subscriptions', authenticate, async (req: Request, res: Response) => {
    try {
        const user = req.user as AuthPayload;
        const { userId, planId, productId, token, termsAccepted, documentFrontUrl, documentBackUrl, selfieUrl } = req.body;

        // 1. Validar Token no Body (Requisito de Segurança Adicional)
        const authHeader = req.headers.authorization;
        const headerToken = authHeader?.split(' ')[1]; // Remove 'Bearer '

        if (!token || token !== headerToken) {
            console.warn(`[Security] Token mismatch or missing in body. User: ${user.userId}`);
            res.status(401).json({ error: 'Token de autenticação inválido ou ausente no corpo da requisição' });
            return;
        }

        // 2. Validar Campos Obrigatórios
        if (!userId || !planId || !productId) {
            logger.warn(`Missing fields: userId=${userId}, planId=${planId}, productId=${productId}`);
            res.status(400).json({ error: 'Dados incompletos: userId, planId e productId são obrigatórios' });
            return;
        }

        // termsAccepted is legally required — cannot create a consortium contract without consent
        if (termsAccepted !== true) {
            logger.warn(`Terms not accepted for user: ${userId}`);
            res.status(400).json({ error: 'Você deve aceitar os termos e condições para criar um contrato.' });
            return;
        }

        // 3. Validar Ownership
        if (userId !== user.userId) {
            logger.warn(`Ownership mismatch: requested=${userId}, actual=${user.userId}`);
            res.status(403).json({ error: 'Acesso negado: você só pode criar contratos para si mesmo' });
            return;
        }

        // Fix 6: Fast-fail if KYC is already REJECTED (re-checked atomically before creation below)
        const userRecord = await prisma.user.findUnique({
            where: { id: userId },
            select: { kycStatus: true }
        });
        if (userRecord?.kycStatus === 'REJECTED') {
            logger.warn(`KYC is REJECTED for user: ${userId}`);
            res.status(403).json({ error: 'Seu cadastro foi reprovado. Entre em contato com o suporte para regularizar sua situação.' });
            return;
        }

        // Fix 9: Cap active subscriptions per user.
        // Only counts statuses that represent real, committed contracts — not stale PENDING ones
        // that auto-cancel after 3 days. This avoids the cap being exhausted by uncommitted entries.
        const MAX_ACTIVE_SUBSCRIPTIONS = 5;
        const activeCount = await prisma.subscription.count({
            where: {
                userId,
                status: { in: ['ACTIVE', 'PENDING_KYC', 'CONTEMPLATED'] }
            }
        });
        if (activeCount >= MAX_ACTIVE_SUBSCRIPTIONS) {
            logger.warn(`Max subscriptions reached for user: ${userId} (${activeCount})`);
            res.status(400).json({ error: `Limite de contratos ativos atingido (máximo: ${MAX_ACTIVE_SUBSCRIPTIONS})` });
            return;
        }

        // 4. Buscar Plano e Validar
        const plan = await prisma.consortiumPlan.findUnique({
            where: { id: planId },
            include: { product: true }
        });

        if (!plan) {
            logger.warn(`Plan not found: ${planId}`);
            res.status(404).json({ error: 'Plano de consórcio não encontrado' });
            return;
        }

        // Fix 10: Ensure plan is active
        if (!plan.active) {
            logger.warn(`Plan is inactive: ${planId}`);
            res.status(400).json({ error: 'O plano selecionado não está mais disponível.' });
            return;
        }

        // Fix 10: Validate plan duration is within product limits.
        // Use schema defaults as fallbacks in case the fields are 0 or not yet set.
        // Guard: durationMonths must be a positive integer to prevent division-by-zero
        if (!plan.durationMonths || plan.durationMonths <= 0) {
            logger.warn(`Invalid plan duration: ${plan.durationMonths}`);
            res.status(400).json({ error: 'Configuração do plano inválida: duração deve ser maior que zero.' });
            return;
        }

        const minDuration = plan.product.minDuration || 12;
        const maxDuration = plan.product.maxDuration || 60;
        if (plan.durationMonths < minDuration || plan.durationMonths > maxDuration) {
            logger.warn(`Duration out of bounds: ${plan.durationMonths} (min: ${minDuration}, max: ${maxDuration})`);
            res.status(400).json({
                error: `Duração do plano (${plan.durationMonths} meses) está fora dos limites permitidos para este produto (${minDuration}–${maxDuration} meses)`
            });
            return;
        }

        // Verificar se o plano corresponde ao produto informado
        if (plan.productId !== productId) {
            logger.warn(`Product ID mismatch: plan.productId=${plan.productId}, productId=${productId}`);
            res.status(400).json({ error: 'O plano selecionado não corresponde ao produto informado' });
            return;
        }

        // 5. Calcular Valores (Adesão e Parcelas)
        const productPrice = Number(plan.product.price);
        const totalRate = Number(plan.adminFeeRate) + Number(plan.fundRate);
        const creditValue = productPrice * (1 + totalRate / 100);
        const monthlyInstallment = creditValue / plan.durationMonths;

        logger.info('--- SUBSCRIPTION CALCULATION ---');
        logger.info(`Plan: ${plan.id}, Price: ${productPrice}, Total Rate: ${totalRate}`);
        logger.info(`Credit Value: ${creditValue}, Monthly: ${monthlyInstallment}`);

        // 6. Criar Subscrição (Contrato)
        // Como é via App, definimos grupo/cota como 'PENDING' ou geramos provisório
        // Em produção, isso viria de uma lógica de distribuição de grupos
        const tempGroup = 'APP-' + Math.floor(Math.random() * 1000);
        const tempQuota = Math.floor(Math.random() * 1000).toString();

        // Total installments = durationMonths (adesão é a 1ª parcela)
        const totalInstallments = plan.durationMonths;

        // Fix 4: Wrap subscription + installment creation in a Serializable transaction and
        // re-validate KYC status inside it, eliminating the TOCTOU window between the outer
        // fast-fail check above and the actual DB write.
        const { subscription, createdInstallments } = await prisma.$transaction(async (tx) => {
            // Re-validate KYC inside the transaction to close the TOCTOU race
            const latestUser = await tx.user.findUnique({
                where: { id: userId },
                select: { kycStatus: true }
            });
            if (latestUser?.kycStatus === 'REJECTED') {
                throw Object.assign(new Error('KYC_REJECTED'), { statusCode: 403 });
            }

            const sub = await tx.subscription.create({
                data: {
                    userId,
                    planId,
                    groupNumber: tempGroup,
                    quotaNumber: tempQuota,
                    creditValue,
                    balanceDue: creditValue,
                    totalInstallments,
                    status: 'PENDING',
                    paidInstallments: 0,
                    contemplated: false,
                    termsAccepted: termsAccepted === true,
                    termsAcceptedAt: termsAccepted ? new Date() : null,
                    termsIpAddress: req.ip,
                }
            });

            // 6b. Auto-submit KYC if document photos were provided with the contract
            if (documentFrontUrl && documentBackUrl && selfieUrl) {
                await tx.user.update({
                    where: { id: userId },
                    data: {
                        documentFrontUrl,
                        documentBackUrl,
                        selfieUrl,
                        kycStatus: 'SUBMITTED'
                    }
                });
                logger.info(`KYC auto-submitted with contract creation: user ${userId}`);
            }

            // 7. Gerar Parcelas
            const today = new Date();
            const installmentsData = [];

            installmentsData.push({
                subscriptionId: sub.id,
                idTokenPay: generatePaymentToken(sub.id, 1, userId),
                number: 1,
                amount: monthlyInstallment,
                dueDate: today,
                status: 'PENDING'
            });

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

            const instList = await tx.installment.findMany({
                where: { subscriptionId: sub.id },
                orderBy: { number: 'asc' }
            });

            return { subscription: sub, createdInstallments: instList };
        }, { isolationLevel: 'Serializable', timeout: 15000 });

        const formattedInstallments = createdInstallments.map((inst: any) => ({
            ...inst,
            amount: Number(inst.amount)
        }));

        logger.info(`Sending ${formattedInstallments.length} installments. First amount: ${formattedInstallments[0].amount}`);

        res.status(201).json({
            success: true,
            v: 2,
            message: 'Contrato solicitado com sucesso!',
            subscriptionId: subscription.id,
            status: 'PENDING',
            plan: {
                id: plan.id,
                monthlyInstallment: monthlyInstallment
            },
            installments: formattedInstallments
        });

    } catch (error: any) {
        if (error?.message === 'KYC_REJECTED') {
            res.status(403).json({ error: 'Seu cadastro foi reprovado. Entre em contato com o suporte para regularizar sua situação.' });
            return;
        }
        logger.error('Error creating subscription:', error);
        res.status(500).json({ error: 'Erro interno ao processar solicitação de contrato' });
    }
});

// POST /api/bids - Criar lance (valida ownership via subscriptionId no body)
router.post('/bids', authenticate, async (req: Request, res: Response) => {
    // Validação de ownership explícita para bids
    const user = req.user as AuthPayload;
    const { subscriptionId } = req.body;

    if (subscriptionId) {
        const subscription = await prisma.subscription.findUnique({
            where: { id: subscriptionId }
        });
        if (subscription && subscription.userId !== user.userId) {
            res.status(403).json({ error: 'Acesso negado: você só pode criar lances para seus próprios contratos' });
            return;
        }
    }
    try {
        const { subscriptionId, type, percentage, amount } = req.body;

        if (!subscriptionId || !type || !percentage || !amount) {
            res.status(400).json({ error: 'Dados incompletos' });
            return;
        }

        // Validar tipo de lance
        const validTypes = ['FREE', 'FIXED'];
        if (!validTypes.includes(type)) {
            res.status(400).json({ error: `Tipo inválido. Deve ser: ${validTypes.join(' ou ')}` });
            return;
        }

        // Validar porcentagem (0 a 100%)
        const parsedPercentage = parseFloat(percentage);
        if (isNaN(parsedPercentage) || parsedPercentage < 0 || parsedPercentage > 100) {
            res.status(400).json({ error: 'Porcentagem deve estar entre 0 e 100' });
            return;
        }

        // Validar valor positivo
        const parsedAmount = parseFloat(amount);
        if (isNaN(parsedAmount) || parsedAmount <= 0) {
            res.status(400).json({ error: 'Valor deve ser maior que zero' });
            return;
        }

        // Check subscription exists
        const subscription = await prisma.subscription.findUnique({
            where: { id: subscriptionId }
        });

        if (!subscription) {
            res.status(404).json({ error: 'Contrato não encontrado' });
            return;
        }

        // Fix 8: Bids are only allowed on ACTIVE subscriptions
        if (subscription.status !== 'ACTIVE') {
            res.status(400).json({ error: 'Lances só podem ser realizados em contratos ativos.' });
            return;
        }

        // Fix 2: Validate client-supplied amount matches expected value (creditValue × percentage / 100).
        // Tolerance of R$0.05 accommodates floating-point rounding on the client side.
        const expectedAmount = Number(subscription.creditValue) * parsedPercentage / 100;
        if (Math.abs(parsedAmount - expectedAmount) > 0.05) {
            res.status(400).json({
                error: `Valor do lance inválido. Para ${parsedPercentage}% o valor esperado é R$${expectedAmount.toFixed(2)}`
            });
            return;
        }

        // Previne Race Conditions (TOCTOU) usando transação atômica do banco de dados
        // Serializable isolation ensures two concurrent bid requests cannot both pass
        // the "existing pending bid" check and create duplicate bids.
        const bid = await prisma.$transaction(async (tx) => {
            const existing = await tx.bid.findFirst({
                where: {
                    subscriptionId,
                    status: 'PENDING'
                }
            });

            if (existing) {
                throw new Error('Já existe um lance pendente para este contrato');
            }

            return tx.bid.create({
                data: {
                    subscriptionId,
                    type,
                    percentage: parsedPercentage,
                    amount: parsedAmount,
                    status: 'PENDING'
                }
            });
        }, { isolationLevel: 'Serializable' });

        res.status(201).json({
            success: true,
            message: 'Lance registrado com sucesso!',
            bid: {
                id: bid.id,
                type: bid.type,
                percentage: Number(bid.percentage),
                amount: Number(bid.amount),
                status: bid.status,
                createdAt: bid.createdAt
            }
        });
    } catch (error) {
        logger.error('Error creating bid:', error);
        res.status(500).json({ error: 'Erro ao registrar lance' });
    }
});

// GET /api/bids/:userId - Listar lances do usuário
router.get('/bids/:userId', authenticate, checkOwnership('user', 'userId'), async (req: Request, res: Response) => {
    try {
        const userId = req.params.userId as string;

        const bids = await prisma.bid.findMany({
            where: {
                subscription: {
                    userId
                }
            },
            include: {
                subscription: {
                    include: {
                        plan: {
                            include: {
                                product: true
                            }
                        }
                    }
                }
            },
            orderBy: { createdAt: 'desc' }
        });

        const formattedBids = bids.map((bid: any) => ({
            id: bid.id,
            type: bid.type,
            percentage: Number(bid.percentage),
            amount: Number(bid.amount),
            status: bid.status,
            isWinner: bid.isWinner,
            createdAt: bid.createdAt,
            product: {
                id: bid.subscription.plan.product.id,
                name: bid.subscription.plan.product.name,
                imageUrl: bid.subscription.plan.product.imageUrl
            },
            groupNumber: bid.subscription.groupNumber,
            quotaNumber: bid.subscription.quotaNumber
        }));

        res.json(formattedBids);
    } catch (error) {
        logger.error('Error fetching bids:', error);
        res.status(500).json({ error: 'Erro ao buscar lances' });
    }
});

// ========================================
// PAYMENTS (Pagamentos)
// ========================================

// POST /api/payments/:installmentId/pay - Registrar pagamento
// Direct payment marking is disabled — use the PIX/Boleto gateway routes instead.
router.post('/payments/:installmentId/pay', authenticate, (_req: Request, res: Response) => {
    res.status(403).json({ error: 'Funcionalidade desativada para usuários. Pagamentos devem ser processados via gateway.' });
});

// GET /api/payments/:subscriptionId - Listar parcelas de um contrato
router.get('/payments/:subscriptionId', authenticate, async (req: Request, res: Response) => {
    const user = req.user as AuthPayload;

    // Validar ownership via subscription
    const subscriptionId = req.params.subscriptionId as string;
    const subscription = await prisma.subscription.findUnique({
        where: { id: subscriptionId }
    });

    if (!subscription) {
        res.status(404).json({ error: 'Contrato não encontrado' });
        return;
    }

    if (subscription.userId !== user.userId) {
        res.status(403).json({ error: 'Acesso negado' });
        return;
    }
    try {

        const installments = await prisma.installment.findMany({
            where: { subscriptionId },
            orderBy: { number: 'asc' }
        });

        // Determine next installment index for all calculations in this list
        const paidIndices = new Set(installments.filter((i: any) => i.status === 'PAID').map((i: any) => i.number));
        let nextIndex = subscription.totalInstallments + 1;
        for (let i = 1; i <= subscription.totalInstallments; i++) {
            if (!paidIndices.has(i)) {
                nextIndex = i;
                break;
            }
        }

        const formattedInstallments = installments.map((inst: any) => ({
            id: inst.id,
            idTokenPay: inst.idTokenPay,
            number: inst.number,
            amount: Number(inst.amount),
            valueToPay: calculateInstallmentValue(Number(inst.amount), inst.number, nextIndex),
            dueDate: inst.dueDate,
            status: inst.status,
            paymentDate: inst.paymentDate,
            paymentMethod: inst.paymentMethod
        }));

        res.json(formattedInstallments);
    } catch (error) {
        logger.error('Error fetching installments:', error);
        res.status(500).json({ error: 'Erro ao buscar parcelas' });
    }
});

// POST /api/payments/:installmentId/pix - Gerar Pix
router.post('/payments/:installmentId/pix', authenticate, async (req: Request, res: Response) => {
    const user = req.user as AuthPayload;
    try {
        const installmentId = req.params.installmentId as string;
        const { idTokenPay } = req.body;

        // Validate payment token is present
        if (!idTokenPay) {
            res.status(400).json({ error: 'Token de pagamento ausente (idTokenPay)' });
            return;
        }

        const installment = await prisma.installment.findUnique({
            where: { id: installmentId },
            include: {
                subscription: {
                    include: {
                        user: true,
                        installments: true
                    }
                }
            }
        });

        if (!installment) {
            res.status(404).json({ error: 'Parcela não encontrada' });
            return;
        }

        // Validar ownership
        if (installment.subscription.userId !== user.userId) {
            res.status(403).json({ error: 'Acesso negado' });
            return;
        }

        // Verify payment token HMAC signature (prevents token forgery)
        const tokenValid = verifyPaymentToken(
            idTokenPay,
            installment.subscriptionId,
            installment.number,
            user.userId
        );
        if (!tokenValid) {
            logger.warn(`Invalid payment token attempt: user ${user.userId}, installment ${installmentId}`);
            res.status(403).json({ error: 'Token de pagamento inválido' });
            return;
        }

        if (installment.status === 'PAID') {
            res.status(400).json({ error: 'Parcela já está paga' });
            return;
        }

        // Determine next installment index for calculation
        const paidIndices = new Set(installment.subscription.installments.filter((i: any) => i.status === 'PAID').map((i: any) => i.number));
        let nextIndex = installment.subscription.totalInstallments + 1;
        for (let i = 1; i <= installment.subscription.totalInstallments; i++) {
            if (!paidIndices.has(i)) {
                nextIndex = i;
                break;
            }
        }

        const valueToPay = calculateInstallmentValue(Number(installment.amount), installment.number, nextIndex);

        // Check active default gateway
        const gateway = await prisma.gatewayConfig.findFirst({
            where: { isDefaultPix: true, enabled: true, supportsPix: true }
        });

        let paymentData: any = {};
        let provider = 'pixgo';

        try {
            if (gateway?.environment === 'sandbox') {
                // SANDBOX MANUAL APPROVAL FLOW
                provider = 'sandbox';
                
                // Update installment to waiting approval
                await prisma.installment.update({
                    where: { id: installmentId },
                    data: {
                        paymentMethod: 'SANDBOX_WAITING_APPROVAL',
                        // paymentDate is NOT set yet. It will be set when admin approves.
                    }
                });
                
                // Return dummy PIX data for testing
                paymentData = {
                    id: `sandbox-${Date.now()}`,
                    qr_code_base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', // 1x1 pixel transparent png base64
                    qr_code: '00020126360014BR.GOV.BCB.PIX0114+551199999999520400005303986540510.005802BR5913Cicrano de Tal6008BRASILIA62070503***63041D3D',
                    expirationDate: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
                };

                res.json({
                    success: true,
                    provider,
                    paymentId: paymentData.id,
                    qrCode: paymentData.qr_code_base64,
                    copyPaste: paymentData.qr_code,
                    amount: valueToPay,
                    expirationDate: paymentData.expirationDate,
                    message: 'Ambiente de Testes: Pagamento enviado para aprovação manual do administrador.'
                });
                return;
            }

            // Se nenhuma gateway estiver ativa, avisa o Flutter para tentar depois
            if (!gateway || !gateway.enabled) {
                return res.status(503).json({
                    success: false,
                    error: 'GATEWAY_UNAVAILABLE',
                    message: 'Nenhum gateway de pagamento ativo no momento. Tente novamente mais tarde.',
                    retryable: true
                });
            }

            if (gateway?.name === 'sigilopay') {
                provider = 'sigilopay';
                // SigiloPay Integration
                const result = await SigiloPayService.createPixDeposit({
                    amount: valueToPay,
                    external_id: installment.id,
                    description: `Pgto Parc. ${installment.number}`,
                    payer: {
                        name: installment.subscription.user.name,
                        email: installment.subscription.user.email,
                        document: installment.subscription.user.cpf,
                        phone: installment.subscription.user.phone || undefined
                    }
                });
                
                // Normalize SigiloPay response
                paymentData = {
                    id: result.transactionId,
                    qr_code_base64: result.pix?.base64 || null,
                    qr_code: result.pix?.code || '',
                    expirationDate: null
                };
            } else {
                // Default fallback: PixGo
                provider = 'pixgo';
                const webhookUrl = process.env.PIXGO_WEBHOOK_URL ? `${process.env.PIXGO_WEBHOOK_URL}/webhooks/pixgo` : undefined;
                
                const result = await PixGoService.createPayment({
                    amount: valueToPay,
                    external_id: installment.id, // Use installment ID as external reference
                    description: `Pagamento Consórcio - Parcela ${installment.number}`,
                    customer_name: installment.subscription.user.name,
                    customer_email: installment.subscription.user.email,
                    customer_cpf: installment.subscription.user.cpf,
                    webhook_url: webhookUrl
                });
                
                paymentData = {
                    id: result.id,
                    qr_code_base64: result.qr_code_base64,
                    qr_code: result.qr_code,
                    expirationDate: result.expiration_date
                };
            }

            res.json({
                success: true,
                provider,
                paymentId: paymentData.id,
                qrCode: paymentData.qr_code_base64,
                copyPaste: paymentData.qr_code,
                amount: valueToPay,
                expirationDate: paymentData.expirationDate || new Date(Date.now() + 30 * 60 * 1000).toISOString()
            });

        } catch (gwError: any) {
            logger.error(`Error generating PIX with ${provider}:`, gwError.message);
            res.status(500).json({ 
                error: 'Erro ao gerar Pix',
                details: gwError.message 
            });
        }

    } catch (error: any) {
        logger.error('Error generating PIX:', error.message);
        res.status(500).json({ error: 'Erro ao gerar Pix' });
    }
});

// POST /api/payments/:installmentId/boleto - Gerar Boleto
router.post('/payments/:installmentId/boleto', authenticate, async (req: Request, res: Response) => {
    const user = req.user as AuthPayload;
    try {
        const installmentId = req.params.installmentId as string;
        const { idTokenPay } = req.body;

        if (!idTokenPay) {
            res.status(400).json({ error: 'Token de pagamento ausente (idTokenPay)' });
            return;
        }

        const installment = await prisma.installment.findUnique({
            where: { id: installmentId },
            include: {
                subscription: {
                    include: {
                        user: true,
                        installments: true
                    }
                }
            }
        });

        if (!installment) {
            res.status(404).json({ error: 'Parcela não encontrada' });
            return;
        }

        if (installment.subscription.userId !== user.userId) {
            res.status(403).json({ error: 'Acesso negado' });
            return;
        }

        const tokenValid = verifyPaymentToken(
            idTokenPay,
            installment.subscriptionId,
            installment.number,
            user.userId
        );
        if (!tokenValid) {
            logger.warn(`Invalid boleto token attempt: user ${user.userId}, installment ${installmentId}`);
            res.status(403).json({ error: 'Token de pagamento inválido' });
            return;
        }

        if (installment.status === 'PAID') {
            res.status(400).json({ error: 'Parcela já está paga' });
            return;
        }

        const paidIndices = new Set(installment.subscription.installments.filter((i: any) => i.status === 'PAID').map((i: any) => i.number));
        let nextIndex = installment.subscription.totalInstallments + 1;
        for (let i = 1; i <= installment.subscription.totalInstallments; i++) {
            if (!paidIndices.has(i)) {
                nextIndex = i;
                break;
            }
        }

        const valueToPay = calculateInstallmentValue(Number(installment.amount), installment.number, nextIndex);

        const gateway = await prisma.gatewayConfig.findFirst({
            where: { isDefaultBoleto: true, enabled: true, supportsBoleto: true }
        });

        let paymentData: any = {};
        let provider = 'pixgo';

        try {
            if (gateway?.environment === 'sandbox') {
                provider = 'sandbox';
                
                await prisma.installment.update({
                    where: { id: installmentId },
                    data: {
                        paymentMethod: 'SANDBOX_WAITING_APPROVAL',
                    }
                });
                
                paymentData = {
                    id: `sandbox-boleto-${Date.now()}`,
                    qr_code_base64: null,
                    qr_code: '34191.09008 61713.957308 71444.640008 2 92900000000000',
                    expirationDate: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
                };

                res.json({
                    success: true,
                    provider,
                    paymentId: paymentData.id,
                    qrCode: null,
                    copyPaste: paymentData.qr_code,
                    amount: valueToPay,
                    expirationDate: paymentData.expirationDate,
                    message: 'Ambiente de Testes: Boleto enviado para aprovação manual.'
                });
                return;
            }

            if (!gateway || !gateway.enabled) {
                return res.status(503).json({
                    success: false,
                    error: 'GATEWAY_UNAVAILABLE',
                    message: 'Nenhum gateway de pagamento ativo no momento.',
                    retryable: true
                });
            }

            if (gateway?.name === 'sigilopay') {
                provider = 'sigilopay';
                let addressObj: any = undefined;
                if (installment.subscription.user.address) {
                    try {
                        addressObj = JSON.parse(installment.subscription.user.address);
                    } catch (e) {
                        logger.warn(`Could not parse address for user ${installment.subscription.user.id}`);
                    }
                }

                if (!addressObj || !addressObj.cep || !addressObj.street || !addressObj.number || !addressObj.neighborhood || !addressObj.city || !addressObj.state) {
                    res.status(400).json({ error: 'Endereço completo é obrigatório para gerar boleto. Por favor, atualize seu cadastro.' });
                    return;
                }

                const result = await SigiloPayService.createBoletoDeposit({
                    amount: valueToPay,
                    external_id: installment.id,
                    description: `Boleto Parc. ${installment.number}`,
                    payer: {
                        name: installment.subscription.user.name,
                        email: installment.subscription.user.email,
                        document: installment.subscription.user.cpf,
                        phone: installment.subscription.user.phone || undefined,
                        address: addressObj
                    }
                });
                
                paymentData = {
                    id: result.id,
                    qr_code_base64: null,
                    qr_code: result.boleto?.digitableLine || result.pix?.code || '',
                    expirationDate: result.boleto?.dueDate || new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString()
                };
            } else {
                throw new Error('O gateway ativo não suporta geração de boletos.');
            }

            res.json({
                success: true,
                provider,
                paymentId: paymentData.id,
                qrCode: null,
                copyPaste: paymentData.qr_code,
                amount: valueToPay,
                expirationDate: paymentData.expirationDate
            });

        } catch (gwError: any) {
            logger.error(`Error generating Boleto with ${provider}:`, gwError.message);
            res.status(500).json({ 
                error: 'Erro ao gerar Boleto',
                details: gwError.message 
            });
        }

    } catch (error: any) {
        logger.error('Error generating Boleto:', error.message);
        res.status(500).json({ error: 'Erro ao gerar Boleto' });
    }
});
// ========================================
// KYC VERIFICATION (Client-side)
// ========================================

// POST /api/kyc/submit — Client submits KYC documents
router.post('/kyc/submit', authenticate, async (req: Request, res: Response) => {
    try {
        const user = req.user as AuthPayload;
        const { documentFrontUrl, documentBackUrl, selfieUrl } = req.body;

        if (!documentFrontUrl || !documentBackUrl || !selfieUrl) {
            res.status(400).json({
                error: 'Documentos incompletos. Envie: foto frente do documento, foto verso, e selfie.'
            });
            return;
        }

        // Block resubmission if KYC is already APPROVED — prevents overwriting a valid approval
        const currentUser = await prisma.user.findUnique({
            where: { id: user.userId },
            select: { kycStatus: true }
        });
        if (currentUser?.kycStatus === 'APPROVED') {
            res.status(409).json({ error: 'Seu KYC já foi aprovado e não pode ser resubmetido.' });
            return;
        }

        // Allow (re)submission for PENDING, SUBMITTED (update docs), and REJECTED (retry)
        await prisma.user.update({
            where: { id: user.userId },
            data: {
                documentFrontUrl,
                documentBackUrl,
                selfieUrl,
                kycStatus: 'SUBMITTED',
                kycRejectReason: null // Clear previous rejection reason on resubmission
            }
        });

        logger.info(`KYC submitted: user ${user.userId}`);

        res.json({
            success: true,
            message: 'Documentos enviados com sucesso! Aguarde a verificação do administrador.',
            kycStatus: 'SUBMITTED'
        });
    } catch (error) {
        logger.error('KYC submit error:', error);
        res.status(500).json({ error: 'Erro ao enviar documentos' });
    }
});

// GET /api/kyc/status — Check KYC status
router.get('/kyc/status', authenticate, async (req: Request, res: Response) => {
    try {
        const user = req.user as AuthPayload;

        const userData = await prisma.user.findUnique({
            where: { id: user.userId },
            select: {
                kycStatus: true,
                kycRejectReason: true,
                documentFrontUrl: true,
                documentBackUrl: true,
                selfieUrl: true
            }
        });

        if (!userData) {
            res.status(404).json({ error: 'Usuário não encontrado' });
            return;
        }

        res.json({
            kycStatus: userData.kycStatus,
            rejectReason: userData.kycRejectReason,
            documentsUploaded: !!(userData.documentFrontUrl && userData.documentBackUrl && userData.selfieUrl)
        });
    } catch (error) {
        logger.error('KYC status error:', error);
        res.status(500).json({ error: 'Erro ao consultar status do KYC' });
    }
});

export default router;
