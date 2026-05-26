import axios from 'axios';
import { logger } from '../config/logger';
import { env } from '../config/env';

// ── Correct V4 gateway (docs: gateway.apiserpro.serpro.gov.br) ────────────────
const TOKEN_URL = 'https://gateway.apiserpro.serpro.gov.br/token';
const BASE_V4   = 'https://gateway.apiserpro.serpro.gov.br/datavalid/v4';

// DV-codes for integration being down → 503 to client
const DV_UNAVAILABLE_CODES = ['DV150', 'DV151', 'DV152'];

// ── Token cache ────────────────────────────────────────────────────────────────
let _token: string | null = null;
let _tokenExpiresAt = 0;

async function getAccessToken(): Promise<string> {
    if (_token && Date.now() < _tokenExpiresAt) {
        return _token;
    }

    const credentials = Buffer.from(
        `${env.DATAVALID_CONSUMER_KEY}:${env.DATAVALID_CONSUMER_SECRET}`
    ).toString('base64');

    const response = await axios.post(
        TOKEN_URL,
        'grant_type=client_credentials',
        {
            headers: {
                Authorization: `Basic ${credentials}`,
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            timeout: 10_000,
        }
    );

    // Token expires_in is 3600 s per docs; subtract 60 s buffer
    const expiresIn: number = response.data.expires_in ?? 3600;
    _token = response.data.access_token as string;
    _tokenExpiresAt = Date.now() + (expiresIn - 60) * 1000;

    return _token;
}

// ── Public types ───────────────────────────────────────────────────────────────
export type DatavalidError =
    | { type: 'unavailable' }
    | { type: 'validation_failed'; reason: string };

/**
 * Result returned by every public check function.
 * `error` is null when validation passed.
 * `rawResponse` is the full JSON body from the Datavalid API (or error body on failure).
 */
export interface DatavalidCheckOutcome {
    error: DatavalidError | null;
    rawResponse: Record<string, unknown> | null;
}

// ── Helpers ────────────────────────────────────────────────────────────────────
function toBase64(buffer: Buffer): string {
    return buffer.toString('base64');
}

function classify422(body: any): 'unavailable' | 'validation_failed' {
    const code: string = body?.codigo ?? body?.code ?? '';
    if (DV_UNAVAILABLE_CODES.includes(code)) return 'unavailable';
    return 'validation_failed';
}

function handleDatavalidError(err: any, context: string): DatavalidError {
    const status: number | undefined = err?.response?.status;
    const body = err?.response?.data;

    if (status === 422) {
        const kind = classify422(body);
        logger.warn(`Datavalid ${context} — 422`, { code: body?.codigo, kind });
        return { type: kind, reason: body?.codigo ?? '422' };
    }

    if (status && status >= 400 && status < 500) {
        logger.warn(`Datavalid ${context} — ${status}`, { body });
        return { type: 'validation_failed', reason: `http_${status}` };
    }

    logger.error(`Datavalid ${context} — unavailable`, { message: err.message, status });
    return { type: 'unavailable' };
}

// ── pf-facial ─────────────────────────────────────────────────────────────────
/**
 * Validates a face photo against the government biometric database (SENATRAN/RENACH)
 * and runs liveness detection (vivacidade).
 *
 * Docs endpoint: POST /datavalid/v4/pf-facial
 */
export async function runFacialCheck(
    cpf: string,
    imageBuffer: Buffer
): Promise<DatavalidCheckOutcome> {
    try {
        const token = await getAccessToken();

        const response = await axios.post(
            `${BASE_V4}/pf-facial`,
            {
                cpf: cpf.replace(/\D/g, ''),
                validacao: {
                    biometria_face: toBase64(imageBuffer),
                    vivacidade: 'true',
                },
            },
            {
                headers: {
                    Authorization: `Bearer ${token}`,
                    'Content-Type': 'application/json',
                    Accept: 'application/json',
                },
                timeout: 30_000,
            }
        );

        const data: Record<string, unknown> = response.data;

        // Liveness: fake attack or image too low quality for liveness
        const vivacidade = data.vivacidade as string | undefined;
        if (vivacidade === 'fake') {
            logger.warn('Datavalid facial — liveness attack detected');
            return { error: { type: 'validation_failed', reason: 'liveness_fake' }, rawResponse: data };
        }
        if (vivacidade === 'bad_quality') {
            logger.warn('Datavalid facial — image quality too low for liveness');
            return { error: { type: 'validation_failed', reason: 'liveness_bad_quality' }, rawResponse: data };
        }

        // No government photo on record — not a fraud signal, allow through
        if (data.biometria_face_disponivel === false) {
            logger.warn('Datavalid facial — no government photo on record for CPF');
            return { error: null, rawResponse: data };
        }

        // Face similarity threshold 0.70 ("Baixa" band floor covers initial onboarding)
        const similarity = (data.biometria_face_similaridade as number) ?? 0;
        if (similarity < 0.70) {
            logger.warn('Datavalid facial — low similarity', { similarity });
            return { error: { type: 'validation_failed', reason: 'face_similarity_too_low' }, rawResponse: data };
        }

        return { error: null, rawResponse: data };
    } catch (err: any) {
        const rawResponse: Record<string, unknown> | null = err?.response?.data ?? null;
        return { error: handleDatavalidError(err, 'facial'), rawResponse };
    }
}

// ── pf-basica ─────────────────────────────────────────────────────────────────
/**
 * Validates CPF + name against the Receita Federal (RFB) database.
 *
 * Docs endpoint: POST /datavalid/v4/pf-basica
 */
export async function runBiographicalCheck(
    cpf: string,
    name: string
): Promise<DatavalidCheckOutcome> {
    try {
        const token = await getAccessToken();

        const response = await axios.post(
            `${BASE_V4}/pf-basica`,
            {
                cpf: cpf.replace(/\D/g, ''),
                validacao: { nome: name },
            },
            {
                headers: {
                    Authorization: `Bearer ${token}`,
                    'Content-Type': 'application/json',
                    Accept: 'application/json',
                },
                timeout: 15_000,
            }
        );

        const data: Record<string, unknown> = response.data;

        if (!data.rfb_existe) {
            logger.warn('Datavalid biographical — CPF not found in RFB');
            return { error: { type: 'validation_failed', reason: 'cpf_not_found' }, rawResponse: data };
        }

        const rfb = (data.rfb as Record<string, unknown>) ?? {};
        const nameSimilarity = (rfb.nome_similaridade as number) ?? (rfb.nome ? 1 : 0);
        if (nameSimilarity < 0.80) {
            logger.warn('Datavalid biographical — name mismatch', { nameSimilarity });
            return { error: { type: 'validation_failed', reason: 'name_mismatch' }, rawResponse: data };
        }

        return { error: null, rawResponse: data };
    } catch (err: any) {
        const rawResponse: Record<string, unknown> | null = err?.response?.data ?? null;
        return { error: handleDatavalidError(err, 'biographical'), rawResponse };
    }
}
