
import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../security/password';

const prisma = new PrismaClient();

async function main() {
    console.log('Listando usuários:');
    const users = await prisma.user.findMany();

    for (const user of users) {
        console.log(`- [${user.role}] ${user.name} | CPF: "${user.cpf}" | Email: ${user.email}`);
    }

    // Tentar resetar senha do CPF do print
    const targetCpf = '21275117783';
    const targetUser = users.find(u => u.cpf.replace(/\D/g, '') === targetCpf);

    if (targetUser) {
        console.log(`\nFound target user: ${targetUser.name}`);
        const newPass = '12345678';
        const hash = await hashPassword(newPass);

        await prisma.user.update({
            where: { id: targetUser.id },
            data: { passwordHash: hash }
        });
        console.log(`Senha resetada para: ${newPass}`);
    } else {
        console.log(`\nUsuário com CPF ${targetCpf} não encontrado (limpo).`);
        // Tentar achar formatado
        const targetUserFormatted = users.find(u => u.cpf.includes('212.751'));
        if (targetUserFormatted) {
            console.log(`ACHEI FORMATADO! ${targetUserFormatted.name} -> ${targetUserFormatted.cpf}`);
        }
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
