import axios from 'axios';
import crypto from 'crypto';
import { logger } from '../config/logger';
import { env } from '../config/env';

// ── Types ──────────────────────────────────────────────────────────────────────
export interface KycStoragePayload {
    userId: string;
    /** Full unmasked CPF — stored only on the secure VPS, never sent to client */
    cpf: string;
    fileType: 'selfie' | 'document';
    imageBuffer: Buffer;
    imageFilename: string;
    datavalidResult: Record<string, unknown> | null;
    kycStep: 'facial_check' | 'biographical_check';
}

// ── Helpers ────────────────────────────────────────────────────────────────────

/** Returns "123.***.***-45" — first 3 and last 2 digits visible */
export function maskCpf(cpf: string): string {
    const d = cpf.replace(/\D/g, '');
    if (d.length !== 11) return cpf;
    return `${d.slice(0, 3)}.***.***-${d.slice(9, 11)}`;
}

function hmacSign(secret: string, data: string): string {
    return crypto.createHmac('sha256', secret).update(data).digest('hex');
}

// ── Fire-and-forget VPS push ───────────────────────────────────────────────────

/**
 * Sends KYC data (image + Datavalid result) to the VPS storage endpoint.
 *
 * Rules:
 * - Fire-and-forget: never awaited, never throws to caller
 * - 10 s timeout; failure is logged as a warning (not an error)
 * - Silently skipped when KYC_STORAGE_URL is not configured
 * - Every request is signed with HMAC-SHA256(KYC_STORAGE_SECRET) in X-KYC-Signature
 */
export function pushToKycStorage(payload: KycStoragePayload): void {
    // Capture the URL before entering the async IIFE so TypeScript narrows the type
    const storageUrl = env.KYC_STORAGE_URL;
    if (!storageUrl) return;

    void (async () => {
        try {
            const timestamp = new Date().toISOString();
            const secret = env.KYC_STORAGE_SECRET ?? '';

            // Sign deterministic string over non-file fields so VPS can verify authenticity
            const sigBase = `${payload.userId}:${payload.cpf}:${payload.fileType}:${payload.kycStep}:${timestamp}`;
            const signature = hmacSign(secret, sigBase);

            // Convert Buffer → Uint8Array to get a clean ArrayBuffer-backed view for Blob
            const imageUint8 = new Uint8Array(payload.imageBuffer);

            // Native FormData (Node 18+ / @types/node 25+) — axios 1.x handles it natively
            const form = new FormData();
            form.append('userId', payload.userId);
            form.append('cpf', payload.cpf);
            form.append('fileType', payload.fileType);
            form.append('kycStep', payload.kycStep);
            form.append('timestamp', timestamp);
            form.append('datavalidResult', JSON.stringify(payload.datavalidResult ?? {}));
            form.append(
                'image',
                new Blob([imageUint8], { type: 'application/octet-stream' }),
                payload.imageFilename,
            );

            await axios.post(storageUrl, form, {
                headers: { 'X-KYC-Signature': signature },
                timeout: 10_000,
            });
        } catch (err: any) {
            // Log as warning — VPS failure must never affect the main KYC flow
            logger.warn('KYC storage VPS upload failed', {
                userId: payload.userId,
                cpf: maskCpf(payload.cpf),
                kycStep: payload.kycStep,
                message: err.message,
                status: err?.response?.status,
            });
        }
    })();
}
