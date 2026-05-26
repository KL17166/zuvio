import dotenv from 'dotenv';
dotenv.config();

import app from './app';
import { redisClient } from './app';
import { logger } from './config/logger';
import { disconnectPrisma } from './config/database';
import { startWebhookCleanupTask } from './services/cronService';

const PORT = process.env.PORT || 3000;

const server = app.listen(PORT, () => {
    logger.info(`Server running on port ${PORT} in ${process.env.NODE_ENV} mode`);
    startWebhookCleanupTask(); // Start background jobs
});

// Slowloris DoS protection: limit how long a client can take to send headers/body
server.headersTimeout = 10_000;   // 10s to send all headers
server.requestTimeout = 30_000;   // 30s total request time

// ========================================
// GRACEFUL SHUTDOWN
// ========================================
let isShuttingDown = false;

async function gracefulShutdown(signal: string) {
    if (isShuttingDown) return;
    isShuttingDown = true;

    logger.info(`${signal} received. Starting graceful shutdown...`);

    // 1. Stop accepting new connections
    server.close(async () => {
        logger.info('HTTP server closed — no new connections accepted');

        // 2. Disconnect Redis
        if (redisClient) {
            try {
                await redisClient.disconnect();
                logger.info('Redis disconnected');
            } catch (e) { logger.warn('Redis disconnect error:', e); }
        }

        // 3. Disconnect database
        await disconnectPrisma();

        // 4. Exit
        logger.info('Graceful shutdown complete');
        process.exit(0);
    });

    // Force exit after 10s if graceful shutdown hangs
    setTimeout(() => {
        logger.error('Graceful shutdown timed out after 10s — forcing exit');
        process.exit(1);
    }, 10_000);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Catch unhandled errors to prevent silent crashes
process.on('uncaughtException', (err) => {
    logger.error('UNCAUGHT EXCEPTION — shutting down', { error: err.message, stack: err.stack });
    gracefulShutdown('uncaughtException');
});

process.on('unhandledRejection', (reason: any) => {
    logger.error('UNHANDLED REJECTION — shutting down', { reason: reason?.message || reason });
    gracefulShutdown('unhandledRejection');
});
