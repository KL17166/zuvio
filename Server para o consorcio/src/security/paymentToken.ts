import crypto from 'crypto';

/**
 * Secret key for signing payment tokens.
 * Uses APP_SECRET from env or falls back to a random key (dev only).
 */
const SIGNING_KEY = process.env.APP_SECRET || process.env.JWT_SECRET || crypto.randomBytes(32).toString('hex');

/**
 * Generates a signed payment token that binds:
 * - The specific subscription (contract)
 * - The installment number
 * - The owner (userId)
 *
 * Format: PAY-{subscriptionPrefix}-{number}-{signature}
 * Example: PAY-a3f8c1-003-7f2b9e4d1a6c
 *
 * The signature is an HMAC of (subscriptionId + number + userId),
 * so it's impossible for another client to forge a valid token.
 */
export function generatePaymentToken(subscriptionId: string, installmentNumber: number, userId: string): string {
    const subPrefix = subscriptionId.replace(/-/g, '').substring(0, 6);
    const num = installmentNumber.toString().padStart(3, '0');

    // HMAC signature: ties the token to the specific client + contract + installment
    const payload = `${subscriptionId}:${installmentNumber}:${userId}`;
    const signature = crypto
        .createHmac('sha256', SIGNING_KEY)
        .update(payload)
        .digest('hex')
        .substring(0, 12); // 12 hex chars = 48 bits of entropy

    return `PAY-${subPrefix}-${num}-${signature}`;
}

/**
 * Verifies that a payment token was legitimately generated for
 * the given subscription, installment, and user.
 *
 * Returns true if the token signature matches.
 * This prevents Client B from using Client A's payment token.
 */
export function verifyPaymentToken(
    token: string,
    subscriptionId: string,
    installmentNumber: number,
    userId: string
): boolean {
    const expected = generatePaymentToken(subscriptionId, installmentNumber, userId);
    // Timing-safe comparison to prevent timing attacks
    try {
        return crypto.timingSafeEqual(
            Buffer.from(token, 'utf-8'),
            Buffer.from(expected, 'utf-8')
        );
    } catch {
        return false; // Different lengths = invalid
    }
}
