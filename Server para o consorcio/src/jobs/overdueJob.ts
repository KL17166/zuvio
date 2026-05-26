import { prisma } from '../config/database';
import { logger } from '../config/logger';

/**
 * Overdue Payment Detection Job
 *
 * Marks PENDING installments with past due dates as OVERDUE.
 * Should run once daily via cron (e.g., 6:00 AM).
 *
 * Only affects installments from ACTIVE or CONTEMPLATED subscriptions
 * to avoid modifying cancelled/completed contracts.
 *
 * Usage:
 *   npx ts-node src/jobs/overdueJob.ts
 *   OR in production: node dist/src/jobs/overdueJob.js
 */
async function markOverdueInstallments(): Promise<void> {
    const startTime = Date.now();

    try {
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        const result = await prisma.installment.updateMany({
            where: {
                status: 'PENDING',
                dueDate: { lt: today },
                subscription: {
                    status: { in: ['ACTIVE', 'CONTEMPLATED'] }
                }
            },
            data: {
                status: 'OVERDUE'
            }
        });

        const elapsed = Date.now() - startTime;
        logger.info(`[OVERDUE JOB] Marked ${result.count} installments as OVERDUE in ${elapsed}ms`);
    } catch (error) {
        logger.error('[OVERDUE JOB] Failed:', error);
        throw error;
    } finally {
        await prisma.$disconnect();
    }
}

// Run if called directly
markOverdueInstallments()
    .then(() => process.exit(0))
    .catch(() => process.exit(1));

export { markOverdueInstallments };
