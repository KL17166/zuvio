import crypto from 'crypto';
import { env } from '../config/env';

const ALGORITHM = 'aes-256-gcm';
// Guarantee a 32-byte key by hashing the secret
const KEY = crypto.createHash('sha256').update(env.PAYLOAD_ENCRYPTION_SECRET).digest();

export const encryptPayload = (data: string): { p: string; iv: string; t: string } => {
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

export const decryptPayload = (encrypted: string, ivBase64: string, authTagBase64: string): string => {
    const iv = Buffer.from(ivBase64, 'base64');
    const authTag = Buffer.from(authTagBase64, 'base64');
    const decipher = crypto.createDecipheriv(ALGORITHM, KEY, iv);
    
    decipher.setAuthTag(authTag);
    
    let decrypted = decipher.update(encrypted, 'base64', 'utf8');
    decrypted += decipher.final('utf8');
    
    return decrypted;
};
