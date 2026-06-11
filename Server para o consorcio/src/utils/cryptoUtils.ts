import crypto from 'crypto';
import { env } from '../config/env';

const ALGORITHM = 'aes-256-gcm';

/**
 * Derives a 32-byte AES key from a hex string or the static env secret.
 *
 * @param keyHex - Optional per-session key (64 hex chars = 32 bytes).
 *                 When provided (authenticated requests), this overrides the
 *                 static PAYLOAD_ENCRYPTION_SECRET from the environment.
 *                 When omitted, the static env secret is used (bootstrap/pre-auth).
 */
function resolveKey(keyHex?: string): Buffer {
    const secret = keyHex ?? env.PAYLOAD_ENCRYPTION_SECRET;
    // SHA-256 guarantees exactly 32 bytes regardless of input length
    return crypto.createHash('sha256').update(secret).digest();
}

/**
 * Encrypts a plaintext string using AES-256-GCM.
 *
 * @param data    - Plaintext JSON string to encrypt.
 * @param keyHex  - Optional per-session 64-char hex key. Falls back to env secret.
 * @returns Object with base64-encoded { p (ciphertext), iv, t (auth tag) }.
 */
export const encryptPayload = (
    data: string,
    keyHex?: string,
): { p: string; iv: string; t: string } => {
    const KEY = resolveKey(keyHex);
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv(ALGORITHM, KEY, iv);

    let encrypted = cipher.update(data, 'utf8', 'base64');
    encrypted += cipher.final('base64');

    const authTag = cipher.getAuthTag().toString('base64');

    return {
        p: encrypted,
        iv: iv.toString('base64'),
        t: authTag,
    };
};

/**
 * Decrypts an AES-256-GCM encrypted payload.
 *
 * @param encrypted    - Base64 ciphertext.
 * @param ivBase64     - Base64 IV.
 * @param authTagBase64 - Base64 auth tag.
 * @param keyHex       - Optional per-session 64-char hex key. Falls back to env secret.
 * @returns Decrypted plaintext string.
 * @throws If authentication tag verification fails (tampered data).
 */
export const decryptPayload = (
    encrypted: string,
    ivBase64: string,
    authTagBase64: string,
    keyHex?: string,
): string => {
    const KEY = resolveKey(keyHex);
    const iv = Buffer.from(ivBase64, 'base64');
    const authTag = Buffer.from(authTagBase64, 'base64');
    const decipher = crypto.createDecipheriv(ALGORITHM, KEY, iv);

    decipher.setAuthTag(authTag);

    let decrypted = decipher.update(encrypted, 'base64', 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
};
