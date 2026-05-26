import { Router, Request, Response } from 'express';
import { prisma } from '../config/database';
import crypto from 'crypto';
import { env } from '../config/env';
import { markInstallmentAsPaid } from '../services/installmentService';

const router = Router();

// POST /webhooks/pixgo - Tratamento de webhook do PixGo
router.post('/pixgo', async (req: Request, res: Response) => {
    try {
        const signature = req.headers['x-pixgo-signature'] as string;

        // Dynamic secret loading
        const config = await prisma.gatewayConfig.findUnique({ where: { name: 'pixgo' } });
        const webhookSecret = config?.webhookSecret || env.PIXGO_WEBHOOK_SECRET;

        // Only skip verification if NO secret is configured anywhere
        if (webhookSecret) {
            if (!signature) {
                return res.status(401).json({
                    error: 'Assinatura ausente',
                    message: 'O header x-pixgo-signature e obrigatorio para autenticar webhooks.'
                });
            }

            const payload = (req as any).rawBody ? (req as any).rawBody.toString('utf8') : JSON.stringify(req.body);
            const expectedSignature = crypto
                .createHmac('sha256', webhookSecret)
                .update(payload)
                .digest('hex');

            // Use timing-safe comparison to prevent timing attacks
            const sigBuffer = Buffer.from(signature, 'hex');
            const expectedBuffer = Buffer.from(expectedSignature, 'hex');
            
            // Basic length check first to prevent error in timingSafeEqual
            if (sigBuffer.length !== expectedBuffer.length || 
                !crypto.timingSafeEqual(sigBuffer, expectedBuffer)) {
                return res.status(401).json({
                    error: 'Assinatura invalida', 
                    message: 'A assinatura do webhook nao corresponde. Verifique o secret configurado.'
                });
            }

            // TIMESTAMP VALIDATION (Replay Protection against delayed attacks)
            const timestampHeader = req.headers['x-pixgo-timestamp'] as string;
            if (timestampHeader) {
                const requestTime = parseInt(timestampHeader, 10);
                const currentTime = Math.floor(Date.now() / 1000);
                const tolerance = 300; // 5 minutes tolerance

                if (isNaN(requestTime) || Math.abs(currentTime - requestTime) > tolerance) {
                    return res.status(401).json({
                        error: 'Timestamp invalido ou expirado',
                        message: 'A requisicao e muito antiga ou esta no futuro.'
                    });
                }
            }
        }

        // REPLAY ATTACK PREVENTION / IDEMPOTENCY
        // Guard: if no signature header is present and no webhookSecret is configured,
        // we cannot use a stable replay key — reject to prevent processing unauthenticated requests.
        if (!signature) {
            console.warn('[Webhook] No signature header and no secret configured — rejecting');
            return res.status(401).json({ error: 'Assinatura ausente' });
        }

        // Check if this signature has already been processed
        const existingLog = await prisma.webhookLog.findUnique({
            where: { signature }
        });

        if (existingLog) {
            console.warn(`[Webhook] Replay detected for signature ${signature}. Ignoring.`);
            return res.status(200).send('Already processed');
        }

        // Store signature to prevent future replays
        try {
            await prisma.webhookLog.create({
                data: {
                    signature,
                    provider: 'pixgo',
                    payload: JSON.stringify(req.body).substring(0, 1000)
                }
            });
        } catch (dbError) {
             console.warn(`[Webhook] Signature collision/race condition: ${signature}`);
             return res.status(200).send('Already processed');
        }

        const { event, data } = req.body;
        console.log(`[Webhook] PixGo event: ${event}, ID: ${data?.external_id || 'unknown'}`);

        // Process completed payment via installmentService (respects KYC, TOCTOU, etc.)
        if (event === 'payment.completed') {
            const installmentId = data.external_id;

            if (!installmentId) {
                console.warn('[Webhook] Missing external_id in payload');
                res.status(400).json({
                    error: 'Dados incompletos',
                    message: 'Campo external_id ausente no payload do webhook.'
                });
                return;
            }

            const result = await markInstallmentAsPaid(installmentId, {
                paymentMethod: 'PIX-PIXGO',
                paymentDate: new Date()
            });

            if (!result.success) {
                console.warn(`[Webhook] markInstallmentAsPaid failed: ${result.message}`);
                // Return 200 anyway to prevent webhook retries for already-paid, etc.
                res.status(200).send(result.message);
                return;
            }

            console.log(`[Webhook] Payment confirmed for installment ${installmentId}${result.pendingKyc ? ' (PENDING_KYC)' : ''}`);
        }

        res.status(200).send('OK');
    } catch (error: any) {
        console.error('[Webhook] Error processing webhook:', error.message);
        res.status(500).json({
            error: 'Erro interno',
            message: 'Erro ao processar webhook. Tente novamente.'
        });
    }
});

// POST /webhooks/sigilopay - Webhook for SigiloPay
router.post('/sigilopay', async (req: Request, res: Response) => {
    try {
        const authHeader = req.headers.authorization;
        
        // 1. Verify Authentication (Bearer Token)
        const config = await prisma.gatewayConfig.findUnique({ where: { name: 'sigilopay' } });
        
        if (!config) {
             console.error('[SigiloPay Webhook] Configuration not found');
             return res.status(500).send('Configuration Error');
        }

        // Use webhookSecret if defined, otherwise fallback to apiSecret
        const validSecret = config.webhookSecret || config.apiSecret;

        if (!validSecret) {
             console.error('[SigiloPay Webhook] No secret configured for validation');
             return res.status(500).send('Configuration Error');
        }

        const expectedAuth = `Bearer ${validSecret}`;
        let isValidAuth = false;
        
        if (authHeader && authHeader.length === expectedAuth.length) {
            isValidAuth = crypto.timingSafeEqual(
                Buffer.from(authHeader, 'utf8'),
                Buffer.from(expectedAuth, 'utf8')
            );
        }

        if (!isValidAuth) {
            console.warn('[SigiloPay Webhook] Invalid Authorization token');
            return res.status(401).json({ error: 'Unauthorized' });
        }

        // 2. Extract Data
        const { status, reference, amount } = req.body;
        console.log(`[SigiloPay Webhook] Received: Status=${status}, Ref=${reference}`);

        // Fix 4: REPLAY ATTACK PREVENTION for SigiloPay (matching PixGo pattern)
        // Validate required fields before hashing — prevents null/undefined collisions
        // where multiple malformed requests would share the same replay key.
        if (!reference || !status || typeof reference !== 'string' || typeof status !== 'string') {
            console.warn('[SigiloPay Webhook] Missing or invalid reference/status fields');
            return res.status(400).json({ error: 'Campos obrigatórios ausentes: reference, status' });
        }

        // Use a deterministic key derived from provider + reference + status
        const sigiloReplayKey = crypto
            .createHash('sha256')
            .update(`sigilopay:${reference}:${status}`)
            .digest('hex');

        const existingSigiloLog = await prisma.webhookLog.findUnique({
            where: { signature: sigiloReplayKey }
        });
        if (existingSigiloLog) {
            console.warn(`[SigiloPay Webhook] Replay detected for reference ${reference}. Ignoring.`);
            return res.status(200).send('Already processed');
        }
        try {
            await prisma.webhookLog.create({
                data: {
                    signature: sigiloReplayKey,
                    provider: 'sigilopay',
                    payload: JSON.stringify(req.body).substring(0, 1000)
                }
            });
        } catch (dbError) {
            console.warn(`[SigiloPay Webhook] Replay key collision for reference ${reference}`);
            return res.status(200).send('Already processed');
        }

        // 3. Process Payment via installmentService (respects KYC, TOCTOU, etc.)
        if (status === 'completed' || status === 'paid' || status === 'approved') {
            const installmentId = reference;

             if (!installmentId) {
                console.warn('[SigiloPay Webhook] Missing reference');
                return res.status(400).send('Missing reference');
            }

            const result = await markInstallmentAsPaid(installmentId, {
                paymentMethod: 'PIX-SIGILOPAY',
                paymentDate: new Date()
            });

            if (!result.success) {
                console.warn(`[SigiloPay Webhook] markInstallmentAsPaid failed: ${result.message}`);
                return res.status(200).send(result.message);
            }
            
            console.log(`[SigiloPay Webhook] Payment confirmed for installment ${installmentId}${result.pendingKyc ? ' (PENDING_KYC)' : ''}`);
        }

        res.status(200).send('OK');
    } catch (error: any) {
        console.error('[SigiloPay Webhook] Error:', error);
        res.status(500).send('Internal Server Error');
    }
});

export default router;
