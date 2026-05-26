import axios from 'axios';
import { logger } from '../../config/logger';
import { prisma } from '../../config/database';

// =============================================
// SigiloPay API — Production Integration
// Docs: https://app.sigilopay.com.br
// Base: https://app.sigilopay.com.br/api/v1
// Auth: API Key (public) + API Secret headers
// =============================================

interface CreatePixDepositParams {
    amount: number;        // Value in BRL (e.g. 100.50)
    external_id: string;   // Used as reference for tracking
    description?: string;
    payer: {
        name: string;
        email?: string;
        document: string;  // CPF (11 digits) or CNPJ (14 digits)
        phone?: string;
        address?: {
            zipCode: string;
            street: string;
            number: string;
            complement?: string;
            neighborhood: string;
            city: string;
            state: string; // UF (e.g. SP)
        };
    };
}

interface SigiloPayTransactionResponse {
    responseType?: string;
    fee?: number;
    pix?: {
        code: string;
        base64: string;
    };
    boleto?: {
        digitableLine: string;
        dueDate: string;
        url?: string;
    };
    transactionId?: string;
    id?: string;
    status: string;
    order?: {
        id: string;
        url: string;
        receiptUrl: string;
    };
    amount?: number;
    reference?: string;
    copy_paste?: string;
}

interface SigiloPayBalanceResponse {
    available: number;
    pending: number;
    fundLock: number;
}

export class SigiloPayService {
    private static readonly DEFAULT_BASE_URL = 'https://app.sigilopay.com.br/api/v1';

    /**
     * Load config from DB first, then fall back to .env
     */
    private static async getConfig() {
        try {
            const config = await prisma.gatewayConfig.findUnique({
                where: { name: 'sigilopay' }
            });

            if (config && config.enabled && config.apiKey && config.apiSecret) {
                return {
                    apiKey: config.apiKey,
                    apiSecret: config.apiSecret,
                    baseUrl: config.baseUrl || this.DEFAULT_BASE_URL,
                    isConfigured: true
                };
            }
        } catch (error) {
            logger.warn('[SigiloPay] Error loading config from DB, using fallback:', error);
        }

        // Fallback to Environment Variables
        const envApiKey = process.env.SIGILOPAY_API_KEY;
        const envApiSecret = process.env.SIGILOPAY_API_SECRET;

        return {
            apiKey: envApiKey || null,
            apiSecret: envApiSecret || null,
            baseUrl: this.DEFAULT_BASE_URL,
            isConfigured: !!(envApiKey && envApiSecret)
        };
    }

    /**
     * Build auth headers for SigiloPay API
     */
    private static buildHeaders(apiKey: string, apiSecret: string) {
        return {
            'x-public-key': apiKey,
            'x-secret-key': apiSecret,
            'Content-Type': 'application/json'
        };
    }

    /**
     * Create a PIX deposit transaction
     */
    static async createPixDeposit(params: CreatePixDepositParams): Promise<SigiloPayTransactionResponse> {
        const config = await this.getConfig();

        if (!config.isConfigured || !config.apiKey || !config.apiSecret) {
            throw new Error('SigiloPay credentials not configured. Set SIGILOPAY_API_KEY/SECRET in .env or Admin Panel > Gateways.');
        }

        logger.info(`[SigiloPay] Creating PIX deposit: ${params.external_id} - R$ ${params.amount}`);

        const cleanDoc = params.payer.document.replace(/\D/g, '');
        const webhookUrl = process.env.PIXGO_WEBHOOK_URL ? `${process.env.PIXGO_WEBHOOK_URL}/api/webhooks/sigilopay` : undefined;

        const payload = {
            identifier: params.external_id,
            amount: Math.round(params.amount * 100) / 100, // Ensure valid decimal
            client: {
                name: params.payer.name,
                email: params.payer.email || 'naoinformado@exemplo.com',
                phone: params.payer.phone ? params.payer.phone.replace(/\D/g, '') : '11999999999',
                document: cleanDoc,
            },
            ...(webhookUrl && { callbackUrl: webhookUrl })
        };

        try {
            const response = await axios.post<SigiloPayTransactionResponse>(
                `${config.baseUrl}/gateway/pix/receive`,
                payload,
                { headers: this.buildHeaders(config.apiKey, config.apiSecret) }
            );

            logger.info(`[SigiloPay] PIX transaction created: ${response.data.transactionId || 'OK'} - Status: ${response.data.status}`);
            return response.data;
        } catch (error: any) {
            const errData = error.response?.data;
            logger.error('[SigiloPay] Error creating PIX deposit:', errData ? JSON.stringify(errData) : error.message);
            if (!errData) { console.error("FULL ERROR:", error.response || error); }
            throw new Error(errData?.message || errData?.error || 'Failed to create SigiloPay PIX deposit');
        }
    }

    /**
     * Create a Boleto deposit transaction
     * Uses the same /gateway/transactions endpoint with payment_method = 'boleto'
     */
    static async createBoletoDeposit(params: CreatePixDepositParams): Promise<SigiloPayTransactionResponse> {
        const config = await this.getConfig();

        if (!config.isConfigured || !config.apiKey || !config.apiSecret) {
            throw new Error('SigiloPay credentials not configured. Set SIGILOPAY_API_KEY/SECRET in .env or Admin Panel > Gateways.');
        }

        logger.info(`[SigiloPay] Creating Boleto deposit: ${params.external_id} - R$ ${params.amount}`);

        const cleanDoc = params.payer.document.replace(/\D/g, '');

        const payload: any = {
            type: 'deposit',
            payment_method: 'boleto',
            amount: params.amount,
            description: params.description || `Pgto #${params.external_id}`,
            reference: params.external_id,
            name: params.payer.name,
            document: cleanDoc,
            email: params.payer.email || undefined,
            phone: params.payer.phone?.replace(/\D/g, '') || undefined,
        };

        if (params.payer.address) {
            payload.address = {
                zipCode: params.payer.address.zipCode.replace(/\D/g, ''),
                street: params.payer.address.street,
                number: params.payer.address.number,
                complement: params.payer.address.complement,
                neighborhood: params.payer.address.neighborhood,
                city: params.payer.address.city,
                state: params.payer.address.state,
            };
        }

        try {
            const response = await axios.post<SigiloPayTransactionResponse>(
                `${config.baseUrl}/gateway/transactions`,
                payload,
                { headers: this.buildHeaders(config.apiKey, config.apiSecret) }
            );

            logger.info(`[SigiloPay] Boleto transaction created: ${response.data.id} - Status: ${response.data.status}`);
            return response.data;
        } catch (error: any) {
            const errData = error.response?.data;
            logger.error('[SigiloPay] Error creating Boleto deposit:', errData || error.message);
            throw new Error(errData?.message || 'Failed to create SigiloPay Boleto deposit');
        }
    }

    /**
     * Get a transaction by ID
     */
    static async getTransaction(id: string): Promise<SigiloPayTransactionResponse> {
        const config = await this.getConfig();

        if (!config.isConfigured || !config.apiKey || !config.apiSecret) {
            throw new Error('SigiloPay credentials not configured');
        }

        try {
            const response = await axios.get<SigiloPayTransactionResponse>(
                `${config.baseUrl}/gateway/transactions/${id}`,
                { headers: this.buildHeaders(config.apiKey, config.apiSecret) }
            );

            return response.data;
        } catch (error: any) {
            logger.error('[SigiloPay] Error fetching transaction:', error.response?.data || error.message);
            throw error;
        }
    }

    /**
     * Get producer balance
     * GET /api/v1/gateway/producer/balance
     * Returns: { available, pending, fundLock }
     */
    static async getBalance(): Promise<SigiloPayBalanceResponse> {
        const config = await this.getConfig();

        if (!config.isConfigured || !config.apiKey || !config.apiSecret) {
            throw new Error('SigiloPay credentials not configured');
        }

        try {
            const response = await axios.get<SigiloPayBalanceResponse>(
                `${config.baseUrl}/gateway/producer/balance`,
                { headers: this.buildHeaders(config.apiKey, config.apiSecret) }
            );

            logger.info(`[SigiloPay] Balance fetched: available=${response.data.available}, pending=${response.data.pending}`);
            return response.data;
        } catch (error: any) {
            logger.error('[SigiloPay] Error fetching balance:', error.response?.data || error.message);
            throw new Error(error.response?.data?.message || 'Failed to fetch SigiloPay balance');
        }
    }

    /**
     * Request a withdrawal / payout
     * POST /api/v1/gateway/producer/withdraw
     */
    static async requestWithdraw(params: {
        amount: number;
        pixKey: string;
        pixKeyType: 'cpf' | 'cnpj' | 'email' | 'phone' | 'random';
        description?: string;
    }): Promise<any> {
        const config = await this.getConfig();

        if (!config.isConfigured || !config.apiKey || !config.apiSecret) {
            throw new Error('SigiloPay credentials not configured');
        }

        if (params.amount <= 0) {
            throw new Error('Withdrawal amount must be greater than zero');
        }

        logger.info(`[SigiloPay] Requesting withdrawal: R$ ${params.amount} to ${params.pixKeyType}:${params.pixKey}`);

        try {
            const response = await axios.post(
                `${config.baseUrl}/gateway/producer/withdraw`,
                {
                    amount: params.amount,
                    pix_key: params.pixKey,
                    pix_key_type: params.pixKeyType,
                    description: params.description || 'Saque via painel admin'
                },
                { headers: this.buildHeaders(config.apiKey, config.apiSecret) }
            );

            logger.info(`[SigiloPay] Withdrawal requested successfully`);
            return response.data;
        } catch (error: any) {
            const errData = error.response?.data;
            logger.error('[SigiloPay] Error requesting withdrawal:', errData || error.message);
            throw new Error(errData?.message || 'Failed to request SigiloPay withdrawal');
        }
    }

    /**
     * Legacy alias — used by apiRoutes.ts
     */
    static async createPixPayment(params: CreatePixDepositParams): Promise<SigiloPayTransactionResponse> {
        return this.createPixDeposit(params);
    }
}
