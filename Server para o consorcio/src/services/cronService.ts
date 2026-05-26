import { prisma } from '../config/database';
import { logger } from '../config/logger';

const CLEANUP_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours
const LOG_RETENTION_HOURS = 24;

export const startWebhookCleanupTask = () => {
    logger.info('Starting WebhookLog cleanup task...');

    const runCleanup = async () => {
        try {
            const retentionDate = new Date();
            retentionDate.setHours(retentionDate.getHours() - LOG_RETENTION_HOURS);

            const result = await prisma.webhookLog.deleteMany({
                where: {
                    processedAt: {
                        lt: retentionDate
                    }
                }
            });

            if (result.count > 0) {
                logger.info(`[Cleanup] Deleted ${result.count} old webhook logs.`);
            }
        } catch (error) {
            logger.error('[Cleanup] Error deleting old webhook logs:', error);
        }
    };

    // Run immediately on start
    runCleanup();

    // Schedule periodic run
    setInterval(runCleanup, CLEANUP_INTERVAL_MS);
};
