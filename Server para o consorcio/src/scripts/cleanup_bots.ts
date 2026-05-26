// Script to delete bot accounts created by exploit_test.ps1
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function cleanup() {
    // Delete accounts where email matches bot pattern
    const result = await prisma.user.deleteMany({
        where: {
            email: { startsWith: 'bot' },
            name: { startsWith: 'Bot' }
        }
    });
    console.log(`Deleted ${result.count} bot accounts`);
    await prisma.$disconnect();
}

cleanup().catch(console.error);
