import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
    console.log('Unlock device script started...');

    // Find blocked devices
    const blocked = await prisma.blockedDevice.findMany({
        where: { active: true }
    });

    console.log(`Found ${blocked.length} blocked devices.`);

    for (const device of blocked) {
        console.log(`Unblocking device: ${device.ipAddress} (Score: ${device.threatScore})`);
        await prisma.blockedDevice.update({
            where: { id: device.id },
            data: {
                active: false,
                unblockedAt: new Date(),
                unblockedBy: 'Script'
            }
        });
    }

    console.log('All devices unblocked.');
}

main()
    .catch(e => console.error(e))
    .finally(async () => {
        await prisma.$disconnect();
    });
