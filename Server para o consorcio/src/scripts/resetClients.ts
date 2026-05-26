
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
    console.log('🗑️  Starting FULL CLIENT RESET...');

    // 1. Delete all Bids
    const deletedBids = await prisma.bid.deleteMany({});
    console.log(`- Deleted ${deletedBids.count} bids.`);

    // 2. Delete all Installments
    const deletedInstallments = await prisma.installment.deleteMany({});
    console.log(`- Deleted ${deletedInstallments.count} installments.`);

    // 3. Delete all Subscriptions
    const deletedSubs = await prisma.subscription.deleteMany({});
    console.log(`- Deleted ${deletedSubs.count} subscriptions.`);

    // 4. Delete all Users with role CLIENT
    const deletedClients = await prisma.user.deleteMany({
        where: { role: 'CLIENT' }
    });
    console.log(`- Deleted ${deletedClients.count} clients.`);

    console.log('✅ Limit reset complete! Only ADMINs remain.');
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
