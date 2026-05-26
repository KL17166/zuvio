import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
    console.log('Starting migration: ADMIN to MASTER...');
    
    // Find all users with role 'ADMIN'
    const adminUsers = await prisma.user.findMany({
        where: { role: 'ADMIN' }
    });
    
    console.log(`Found ${adminUsers.length} users with role ADMIN.`);
    
    if (adminUsers.length > 0) {
        // Update all to MASTER
        const updateResult = await prisma.user.updateMany({
            where: { role: 'ADMIN' },
            data: { role: 'MASTER' }
        });
        
        console.log(`Successfully migrated ${updateResult.count} users to MASTER.`);
    } else {
        console.log('No users found to migrate.');
    }
    
    console.log('Migration complete.');
}

main()
    .catch((e) => {
        console.error('Migration failed:', e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
