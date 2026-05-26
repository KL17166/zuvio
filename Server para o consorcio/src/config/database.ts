import { PrismaClient } from '@prisma/client';
import { logger } from './logger';

// Singleton pattern — prevent multiple instances in dev (hot reload)
const globalForPrisma = globalThis as unknown as { prisma: PrismaClient | undefined };

export const prisma = globalForPrisma.prisma ?? new PrismaClient({
    log: process.env.NODE_ENV === 'development'
        ? [
            { emit: 'event', level: 'query' },
            { emit: 'event', level: 'warn' },
            { emit: 'event', level: 'error' },
        ]
        : [
            { emit: 'event', level: 'warn' },
            { emit: 'event', level: 'error' },
        ],
});

// Log slow queries in development
if (process.env.NODE_ENV === 'development') {
    (prisma as any).$on('query', (e: any) => {
        if (e.duration > 100) { // Log queries taking > 100ms
            logger.warn(`Slow query (${e.duration}ms): ${e.query}`);
        }
    });
}

(prisma as any).$on('warn', (e: any) => logger.warn(`Prisma warning: ${e.message}`));
(prisma as any).$on('error', (e: any) => logger.error(`Prisma error: ${e.message}`));

// Prevent multiple instances in development
if (process.env.NODE_ENV !== 'production') {
    globalForPrisma.prisma = prisma;
}

// Graceful disconnect helper
export async function disconnectPrisma() {
    try {
        await prisma.$disconnect();
        logger.info('Prisma disconnected gracefully');
    } catch (e) {
        logger.error('Error disconnecting Prisma:', e);
    }
}
