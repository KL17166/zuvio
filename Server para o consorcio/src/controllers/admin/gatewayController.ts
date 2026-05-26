import { Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { SigiloPayService } from '../../services/gateways/sigiloPayService';

// Default gateway configurations to seed on first load
const DEFAULT_GATEWAYS = [
    {
        name: 'pixgo',
        displayName: 'PixGo',
        baseUrl: 'https://pixgo.org/api/v1',
        supportsPix: true,
        supportsBoleto: false,
        supportsCard: false,
    },
    {
        name: 'sigilopay',
        displayName: 'SigiloPay',
        baseUrl: 'https://app.sigilopay.com.br/api/v1',
        supportsPix: true,
        supportsBoleto: true,
        supportsCard: false,
    }
];

// GET /admin/gateways
export const listGateways = async (req: Request, res: Response) => {
    try {
        // Auto-seed default gateways if they don't exist
        for (const gw of DEFAULT_GATEWAYS) {
            const exists = await prisma.gatewayConfig.findFirst({ where: { name: gw.name } });
            if (!exists) {
                await prisma.gatewayConfig.create({ data: gw });
            }
        }

        const gatewaysData = await prisma.gatewayConfig.findMany({
            orderBy: { createdAt: 'asc' }
        });

        // Map gateways to include env status
        const gateways = gatewaysData.map(gw => {
            const gwObj = gw as any;
            
            if (gw.name === 'pixgo') {
                gwObj.envApiKey = !!process.env.PIXGO_API_KEY;
                gwObj.envWebhookSecret = !!process.env.PIXGO_WEBHOOK_SECRET; 
                
                // If config in DB is empty but env exists, treat as configured (for UI display)
                if (!gw.apiKey && gwObj.envApiKey) {
                    gwObj.apiKey = 'Presente no .env';
                }
            } else if (gw.name === 'sigilopay') {
                gwObj.envApiKey = !!process.env.SIGILOPAY_API_KEY;
                gwObj.envApiSecret = !!process.env.SIGILOPAY_API_SECRET;

                if (!gw.apiKey && gwObj.envApiKey) {
                    gwObj.apiKey = 'Presente no .env';
                }
            }
            return gwObj;
        });

        res.render('pages/gateways/index', {
            path: '/gateways',
            gateways,
            // @ts-ignore
            csrfToken: req.csrfToken ? req.csrfToken() : ''
        });
    } catch (error) {
        logger.error('Gateways page error:', error);
        res.status(500).send('Erro ao carregar gateways');
    }
};

// POST /admin/gateways/:id/update
export const updateGateway = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;
        const {
            apiKey, apiSecret, webhookSecret, baseUrl,
            environment, platformId,
            isDefaultPix, isDefaultBoleto, isDefaultCard
        } = req.body;

        // If setting as default for a method, unset all others first
        if (isDefaultPix === 'true') {
            await prisma.gatewayConfig.updateMany({
                where: { id: { not: id } },
                data: { isDefaultPix: false }
            });
        }
        if (isDefaultBoleto === 'true') {
            await prisma.gatewayConfig.updateMany({
                where: { id: { not: id } },
                data: { isDefaultBoleto: false }
            });
        }
        if (isDefaultCard === 'true') {
            await prisma.gatewayConfig.updateMany({
                where: { id: { not: id } },
                data: { isDefaultCard: false }
            });
        }

        await prisma.gatewayConfig.update({
            where: { id },
            data: {
                apiKey: apiKey || null,
                apiSecret: apiSecret || null,
                webhookSecret: webhookSecret || null,
                baseUrl: baseUrl || null,
                environment: environment || 'sandbox',
                platformId: platformId || null,
                isDefaultPix: isDefaultPix === 'true',
                isDefaultBoleto: isDefaultBoleto === 'true',
                isDefaultCard: isDefaultCard === 'true',
            }
        });

        req.flash('success_msg', 'Configuração do gateway atualizada com sucesso!');
        res.redirect('/admin/gateways');
    } catch (error) {
        logger.error('Update gateway error:', error);
        req.flash('error_msg', 'Erro ao atualizar configuração do gateway.');
        res.redirect('/admin/gateways');
    }
};

// POST /admin/gateways/:id/toggle
export const toggleGateway = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;
        const gateway = await prisma.gatewayConfig.findUnique({ where: { id } });

        if (!gateway) {
            req.flash('error_msg', 'Gateway não encontrado.');
            return res.redirect('/admin/gateways');
        }

        const newEnabled = !gateway.enabled;

        // Validate: cannot enable without API key (unless present in env)
        const hasEnvKey = (gateway.name === 'pixgo' && process.env.PIXGO_API_KEY) || 
                          (gateway.name === 'sigilopay' && process.env.SIGILOPAY_API_KEY);

        if (newEnabled && !gateway.apiKey && !hasEnvKey) {
            req.flash('error_msg', 'Configure a API Key antes de ativar o gateway.');
            return res.redirect('/admin/gateways');
        }

        await prisma.gatewayConfig.update({
            where: { id },
            data: { enabled: newEnabled }
        });

        // If disabling and it was default, clear defaults
        if (!newEnabled) {
            await prisma.gatewayConfig.update({
                where: { id },
                data: {
                    isDefaultPix: false,
                    isDefaultBoleto: false,
                    isDefaultCard: false
                }
            });
        }

        req.flash('success_msg', `Gateway ${gateway.displayName} ${newEnabled ? 'ativado' : 'desativado'} com sucesso!`);
        res.redirect('/admin/gateways');
    } catch (error) {
        logger.error('Toggle gateway error:', error);
        req.flash('error_msg', 'Erro ao alternar status do gateway.');
        res.redirect('/admin/gateways');
    }
};

// GET /admin/gateways/sigilopay/balance — Proxy to SigiloPay Balance API
export const getSigiloPayBalance = async (req: Request, res: Response) => {
    try {
        const balance = await SigiloPayService.getBalance();
        res.json(balance);
    } catch (error: any) {
        logger.error('SigiloPay balance error:', error.message);
        res.status(500).json({ 
            error: 'Erro ao consultar saldo',
            details: error.message 
        });
    }
};

// POST /admin/gateways/sigilopay/withdraw — Request withdrawal from SigiloPay
export const requestSigiloPayWithdraw = async (req: Request, res: Response) => {
    try {
        const { amount, pixKey, pixKeyType, description } = req.body;

        if (!amount || !pixKey || !pixKeyType) {
            return res.status(400).json({
                error: 'Campos obrigatórios: amount, pixKey, pixKeyType'
            });
        }

        const numAmount = parseFloat(amount);
        if (isNaN(numAmount) || numAmount <= 0) {
            return res.status(400).json({ error: 'Valor de saque inválido' });
        }

        const validTypes = ['cpf', 'cnpj', 'email', 'phone', 'random'];
        if (!validTypes.includes(pixKeyType)) {
            return res.status(400).json({ error: 'Tipo de chave PIX inválido' });
        }

        const result = await SigiloPayService.requestWithdraw({
            amount: numAmount,
            pixKey,
            pixKeyType,
            description: description || undefined
        });

        logger.info(`[Admin] Withdrawal requested: R$ ${numAmount} by ${(req as any).session?.user?.email}`);

        res.json({
            success: true,
            message: 'Saque solicitado com sucesso',
            data: result
        });
    } catch (error: any) {
        logger.error('SigiloPay withdraw error:', error.message);
        res.status(500).json({
            error: 'Erro ao solicitar saque',
            details: error.message
        });
    }
};
