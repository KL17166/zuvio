import { createClient, type RedisClientType } from 'redis';
import { logger } from './logger';
import { env } from './env';

/**
 * Shared Redis client used by:
 *   - express-session store (app.ts)
 *   - JWT JTI blacklist (authMiddleware)
 *   - Per-session signing secrets (requestSignatureMiddleware, authController)
 *
 * Graceful degradation: when Redis is unavailable the client is null.
 * Each consumer checks `if (redisClient)` before use and logs a warning.
 * In that state:
 *   - Sessions fall back to in-memory (express-session behaviour)
 *   - Revoked tokens remain valid until their natural expiry (15 min)
 *   - Request signing falls back to the static global secret
 */
let _redisClient: RedisClientType | null = null;

try {
    _redisClient = createClient({
        url: env.REDIS_URL,
        socket: {
            reconnectStrategy: (retries) => {
                if (retries > 3) {
                    logger.warn('Redis: max retries reached — JWT blacklist and session signing degraded');
                    return false;
                }
                return Math.min(retries * 200, 2000);
            },
        },
    }) as RedisClientType;

    _redisClient.on('connect', () => logger.info('Redis connected'));
    _redisClient.on('error', (err: Error) => logger.warn(`Redis error: ${err.message}`));

    _redisClient.connect().catch(() => {
        logger.warn('Redis unavailable — JWT blacklist and session signing will degrade gracefully');
        _redisClient = null;
    });
} catch (err) {
    logger.warn('Redis init failed — JWT blacklist and session signing degraded');
    _redisClient = null;
}

export const redisClient = _redisClient;
