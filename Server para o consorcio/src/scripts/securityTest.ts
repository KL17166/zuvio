import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../security/password';
import jwt from 'jsonwebtoken';

const prisma = new PrismaClient();

async function createTestUsers() {
    console.log('=== SECURITY TEST SCRIPT ===\n');

    // Create two test users
    const password1 = await hashPassword('User1Pass123');
    const password2 = await hashPassword('User2Pass123');

    let user1, user2;

    try {
        user1 = await prisma.user.upsert({
            where: { cpf: '11111111111' },
            update: {},
            create: {
                name: 'Victim User',
                email: 'victim@test.com',
                cpf: '11111111111',
                passwordHash: password1,
                role: 'CLIENT',
                birthDate: new Date('1990-01-01'),
            }
        });
        console.log('✅ User 1 (Victim) created:', user1.id);
    } catch (e) {
        console.log('User 1 already exists');
        user1 = await prisma.user.findUnique({ where: { cpf: '11111111111' } });
    }

    try {
        user2 = await prisma.user.upsert({
            where: { cpf: '22222222222' },
            update: {},
            create: {
                name: 'Attacker User',
                email: 'attacker@test.com',
                cpf: '22222222222',
                passwordHash: password2,
                role: 'CLIENT',
                birthDate: new Date('1995-05-05'),
            }
        });
        console.log('✅ User 2 (Attacker) created:', user2.id);
    } catch (e) {
        console.log('User 2 already exists');
        user2 = await prisma.user.findUnique({ where: { cpf: '22222222222' } });
    }

    // Generate tokens
    const victimToken = jwt.sign(
        { userId: user1!.id, role: 'CLIENT' },
        process.env.JWT_SECRET as string,
        { expiresIn: '1h' }
    );

    const attackerToken = jwt.sign(
        { userId: user2!.id, role: 'CLIENT' },
        process.env.JWT_SECRET as string,
        { expiresIn: '1h' }
    );

    console.log('\n=== TOKENS FOR TESTING ===');
    console.log('\nVICTIM_USER_ID=' + user1!.id);
    console.log('VICTIM_TOKEN=' + victimToken);
    console.log('\nATTACKER_USER_ID=' + user2!.id);
    console.log('ATTACKER_TOKEN=' + attackerToken);

    await prisma.$disconnect();
}

createTestUsers().catch(console.error);
