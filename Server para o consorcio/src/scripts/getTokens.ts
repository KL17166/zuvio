import { PrismaClient } from '@prisma/client';
import jwt from 'jsonwebtoken';
import * as fs from 'fs';

const prisma = new PrismaClient();

async function main() {
    const users = await prisma.user.findMany({
        where: { cpf: { in: ['11111111111', '22222222222'] } }
    });

    const tokens: Record<string, string> = {};

    users.forEach(u => {
        const token = jwt.sign(
            { userId: u.id, role: u.role },
            process.env.JWT_SECRET as string,
            { expiresIn: '1h' }
        );
        tokens[u.cpf] = token;
        console.log(`${u.cpf}_ID=${u.id}`);
        console.log(`${u.cpf}_TOKEN=${token}`);
    });

    // Save to file for use in tests
    fs.writeFileSync('test_tokens.json', JSON.stringify({
        victimId: users.find(u => u.cpf === '11111111111')?.id,
        victimToken: tokens['11111111111'],
        attackerId: users.find(u => u.cpf === '22222222222')?.id,
        attackerToken: tokens['22222222222']
    }, null, 2));

    console.log('\n✅ Tokens saved to test_tokens.json');
    await prisma.$disconnect();
}

main();
