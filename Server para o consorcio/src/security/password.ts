import argon2 from 'argon2';

/**
 * Centralized password hashing with Argon2id + Pepper.
 *
 * - Argon2id: resistant to both side-channel and GPU attacks.
 * - Pepper: secret appended to password before hashing, stored in env (not in DB).
 *   Even if the DB leaks, hashes can't be cracked without the pepper.
 */

if (!process.env.PASSWORD_PEPPER) {
    throw new Error('❌ FATAL: PASSWORD_PEPPER não está definido no .env. O servidor NÃO pode rodar sem pepper.');
}
const PEPPER = process.env.PASSWORD_PEPPER;

const ARGON2_OPTIONS: argon2.Options = {
    type: argon2.argon2id,
    memoryCost: 65536,   // 64 MB
    timeCost: 12,        // 12 iterações/passagens
    parallelism: 4,      // 4 threads
};

/**
 * Hash a password using Argon2id + pepper.
 */
export async function hashPassword(plainPassword: string): Promise<string> {
    const peppered = plainPassword + PEPPER;
    return argon2.hash(peppered, ARGON2_OPTIONS);
}

/**
 * Verify a password against an Argon2id hash.
 */
export async function verifyPassword(plainPassword: string, hash: string): Promise<boolean> {
    const peppered = plainPassword + PEPPER;
    return argon2.verify(hash, peppered);
}
