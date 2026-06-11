import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../security/password';

const prisma = new PrismaClient();

async function main() {
    console.log('👤 Creating User Gabriella...');

    const email = 'gabriella@teste.com';
    const cpf = '44201483819';
    const password = 'cliente123';
    const name = 'GABRIELLA STEFANIE BISPO E SILVA';

    // Delete existing if any to allow fresh creation
    await prisma.user.deleteMany({
        where: {
            OR: [{ email }, { cpf }]
        }
    });

    const hashedPassword = await hashPassword(password);

    const addressObj = {
        cep: '04855-090',
        state: 'SP',
        city: 'SAO PAULO',
        street: 'R MANUEL VERGUEIRO',
        neighborhood: 'JD BELCITO',
        number: '6',
        complement: 'C 2 R'
    };

    const user = await prisma.user.create({
        data: {
            name,
            email,
            cpf,
            phone: '11999999999',
            passwordHash: hashedPassword,
            role: 'CLIENT',
            birthDate: new Date('1994-05-19T00:00:00Z'),
            address: JSON.stringify(addressObj)
        }
    });

    console.log(`✅ User Gabriella created successfully!`);
    console.log(`- ID: ${user.id}`);
    console.log(`- Name: ${user.name}`);
    console.log(`- Email: ${user.email}`);
    console.log(`- Password: ${password}`);
    console.log(`- CPF: ${user.cpf}`);
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
