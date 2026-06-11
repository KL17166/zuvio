import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const envSchema = z.object({
    NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
    PORT: z.string().default('3000').transform(Number),
    DATABASE_URL: z.string().url(),
    JWT_SECRET: z.string().min(32, "JWT_SECRET must be at least 32 characters"),
    SESSION_SECRET: z.string().min(32, "SESSION_SECRET must be at least 32 characters"),
    ALLOWED_ORIGINS: z.string().optional(),
    REDIS_URL: z.string().default('redis://localhost:6379'),
    PIXGO_WEBHOOK_SECRET: z.string().min(16, "PIXGO_WEBHOOK_SECRET deve ter pelo menos 16 caracteres em producao").optional()
        .refine(
            (val) => process.env.NODE_ENV !== 'production' || (val && val.length >= 16),
            { message: "PIXGO_WEBHOOK_SECRET e OBRIGATORIO em producao. Sem ele, qualquer pessoa pode simular webhooks e marcar parcelas como pagas." }
        ),

    // SigiloPay Credentials (fallback if not in DB)
    SIGILOPAY_API_KEY: z.string().optional(),
    SIGILOPAY_API_SECRET: z.string().optional(),

    // Admin Credentials for Seeding
    ADMIN_EMAIL: z.string().email().optional(),
    ADMIN_PASSWORD: z.string().min(8).optional(),
    ADMIN_CPF: z.string().length(11).optional(),

    // Serpro Datavalid KYC
    DATAVALID_CONSUMER_KEY: z.string().optional(),
    DATAVALID_CONSUMER_SECRET: z.string().optional(),
    DATAVALID_ENABLED: z.string().default('false').transform((v) => v === 'true'),

    // KYC VPS Storage — audit copy of every KYC submission
    KYC_STORAGE_URL: z.string().url().optional(),
    KYC_STORAGE_SECRET: z.string().optional(),

    // HMAC Request Signing — must match Flutter request_signer.dart
    REQUEST_SIGNING_SECRET: z.string().min(32, 'REQUEST_SIGNING_SECRET must be at least 32 characters')
        .refine(
            (val) => process.env.NODE_ENV !== 'production' || (val && val.length >= 32),
            { message: 'REQUEST_SIGNING_SECRET is REQUIRED in production. Without it all API requests use a well-known fallback secret.' }
        )
        .optional(),

    // Payload Encryption (AES-256)
    PAYLOAD_ENCRYPTION_SECRET: z.string().min(32, 'PAYLOAD_ENCRYPTION_SECRET must be at least 32 characters').default('super-secret-payload-encryption-key!'),
    ENCRYPTION_BYPASS_SECRET: z.string().default('admin-bypass-123'),
});

const _env = envSchema.safeParse(process.env);

if (!_env.success) {
    console.error("❌ Invalid environment variables:", _env.error.format());
    process.exit(1);
}

export const env = _env.data;
