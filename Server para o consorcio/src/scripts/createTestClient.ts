
import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../security/password';

const prisma = new PrismaClient();

async function main() {
    console.log('👤 Creating Test Client...');

    const email = 'clienteteste@example.com';
    const cpf = '12312312312'; // Valid format 11 digits
    const password = 'clientepass';

    // Check if exists
    const existing = await prisma.user.findFirst({
        where: {
            OR: [{ email }, { cpf }]
        }
    });

    if (existing) {
        console.log(`⚠️ Client with email ${email} or CPF ${cpf} already exists.`);
        return;
    }

    const hashedPassword = await hashPassword(password);

    const client = await prisma.user.create({
        data: {
            name: 'Cliente Teste Script',
            email,
            cpf,
            phone: '11999999999',
            passwordHash: hashedPassword,
            role: 'CLIENT',
            birthDate: new Date('1990-01-01'),
            address: 'Rua Teste Script, 123, Cidade - UF'
        }
    });

    console.log(`✅ Client created successfully!`);
    console.log(`- ID: ${client.id}`);
    console.log(`- Name: ${client.name}`);
    console.log(`- Email: ${client.email}`);
    console.log(`- Password: ${password}`);
    console.log(`- Role: ${client.role}`);
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
