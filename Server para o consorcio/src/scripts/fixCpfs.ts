
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
    console.log('Starting CPF fix...');

    const users = await prisma.user.findMany();
    let fixedCount = 0;

    for (const user of users) {
        const cleanCpf = user.cpf.replace(/\D/g, '');

        if (user.cpf !== cleanCpf) {
            console.log(`Fixing CPF for user ${user.name}: ${user.cpf} -> ${cleanCpf}`);

            try {
                await prisma.user.update({
                    where: { id: user.id },
                    data: { cpf: cleanCpf }
                });
                fixedCount++;
            } catch (e) {
                console.error(`Error fixing user ${user.name}:`, e);
            }
        }
    }

    console.log(`Finished! Fixed ${fixedCount} users.`);
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
