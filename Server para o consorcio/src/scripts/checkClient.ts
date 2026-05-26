
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
    const targetId = '8f7acaf8-41f6-4941-ab1d-a30a94220059';
    console.log(`🔍 Checking for client with ID: ${targetId}`);

    const client = await prisma.user.findUnique({
        where: { id: targetId }
    });

    if (client) {
        console.log('✅ Client found!');
        console.log(`- Name: ${client.name}`);
        console.log(`- Role: ${client.role}`);
    } else {
        console.log('❌ Client NOT found.');

        // List some valid clients to compare
        console.log('\n📋 Valid clients:');
        const clients = await prisma.user.findMany({
            take: 5,
            where: { role: 'CLIENT' },
            select: { id: true, name: true }
        });
        clients.forEach(c => console.log(`- ${c.name}: ${c.id}`));
    }
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
