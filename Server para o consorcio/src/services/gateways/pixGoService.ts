import axios from 'axios';
import { logger } from '../../config/logger';
import { prisma } from '../../config/database';

// =============================================
// PixGo API v1 — Production Integration
// Docs: https://pixgo.org/api/v1/docs
// Base: https://pixgo.org/api/v1
// Auth: X-API-Key header
// =============================================

interface CreatePixParams {
    amount: number;          // Min R$ 10.00, max varies by level
    external_id: string;     // Max 50 chars
    description?: string;    // Max 200 chars
    customer_name?: string;  // Max 100 chars
    customer_email?: string; // Max 255 chars
    customer_cpf?: string;   // 11 digits (CPF) or 14 digits (CNPJ)
    customer_phone?: string; // Phone with area code, max 20 chars
    customer_address?: string; // Max 500 chars
    webhook_url?: string;
}

interface PixGoPaymentResponse {
    id: string;
    status: 'pending' | 'completed' | 'expired' | 'cancelled';
    amount: number;
    qr_code: string;           // PIX copia e cola
    qr_code_base64: string;    // QR code image base64
    external_id: string;
    description: string;
    expiration_date: string;
    created_at: string;
}

interface PixGoStatusResponse {
    id: string;
    status: 'pending' | 'completed' | 'expired' | 'cancelled';
}

export class PixGoService {
    private static readonly DEFAULT_BASE_URL = 'https://pixgo.org/api/v1';

    /**
     * Load config from DB first, then fall back to .env
     */
    private static async getConfig() {
        try {
            const config = await prisma.gatewayConfig.findUnique({
                where: { name: 'pixgo' }
            });

            if (config && config.enabled && config.apiKey) {
                return {
                    apiKey: config.apiKey,
                    baseUrl: config.baseUrl || this.DEFAULT_BASE_URL,
                    isConfigured: true
                };
            }
        } catch (error) {
            logger.warn('[PixGo] Error loading config from DB, using fallback:', error);
        }

        // Fallback to Environment Variables
        const envApiKey = process.env.PIXGO_API_KEY;
        return {
            apiKey: envApiKey,
            baseUrl: this.DEFAULT_BASE_URL,
            isConfigured: !!envApiKey
        };
    }

    /**
     * Build auth headers for PixGo API
     */
    private static buildHeaders(apiKey: string) {
        return {
            'X-API-Key': apiKey,
            'Content-Type': 'application/json'
        };
    }

    /**
     * Create a new PIX payment
     * POST /payment/create
     * Payments expire after 20 minutes
     */
    static async createPayment(params: CreatePixParams): Promise<PixGoPaymentResponse> {
        const config = await this.getConfig();

        if (!config.isConfigured || !config.apiKey) {
            throw new Error('PIXGO_API_KEY not configured (Check Admin Panel > Gateways)');
        }

        logger.info(`[PixGo] Creating payment: ${params.external_id} - R$ ${params.amount}`);

        // Validate minimum amount per docs
        if (params.amount < 10) {
            throw new Error('PixGo minimum payment amount is R$ 10.00');
        }

        try {
            const response = await axios.post<PixGoPaymentResponse>(
                `${config.baseUrl}/payment/create`,
                {
                    amount: params.amount,
                    external_id: params.external_id,
                    description: params.description || 'Pagamento Consórcio',
                    customer_name: params.customer_name,
                    customer_email: params.customer_email,
                    customer_cpf: params.customer_cpf?.replace(/\D/g, ''),
                    customer_phone: params.customer_phone?.replace(/\D/g, ''),
                    customer_address: params.customer_address,
                    webhook_url: params.webhook_url
                },
                { headers: this.buildHeaders(config.apiKey) }
            );

            logger.info(`[PixGo] Payment created: ${response.data.id} - Status: ${response.data.status}`);
            return response.data;
        } catch (error: any) {
            const errData = error.response?.data;
            logger.error('[PixGo] Error creating payment:', errData || error.message);
            throw new Error(errData?.message || 'Failed to create Pix payment');
        }
    }

    /**
     * Check payment status (lightweight)
     * GET /payment/{id}/status
     * Recommended polling interval: every 30 seconds
     */
    static async getPaymentStatus(id: string): Promise<PixGoStatusResponse> {
        const config = await this.getConfig();

        if (!config.isConfigured || !config.apiKey) {
            throw new Error('PIXGO_API_KEY not configured');
        }

        try {
            const response = await axios.get<PixGoStatusResponse>(
                `${config.baseUrl}/payment/${id}/status`,
                { headers: this.buildHeaders(config.apiKey) }
            );

            return response.data;
        } catch (error: any) {
            logger.error('[PixGo] Error checking payment status:', error.response?.data || error.message);
            throw error;
        }
    }

    /**
     * Get complete payment details
     * GET /payment/{id}
     */
    static async getPayment(id: string): Promise<PixGoPaymentResponse> {
        const config = await this.getConfig();

        if (!config.isConfigured || !config.apiKey) {
            throw new Error('PIXGO_API_KEY not configured');
        }

        try {
            const response = await axios.get<PixGoPaymentResponse>(
                `${config.baseUrl}/payment/${id}`,
                { headers: this.buildHeaders(config.apiKey) }
            );

            return response.data;
        } catch (error: any) {
            logger.error('[PixGo] Error fetching payment:', error.response?.data || error.message);
            throw error;
        }
    }
}
