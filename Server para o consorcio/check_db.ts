import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
async function main() {
  const u = await prisma.user.findFirst({
    where: { cpf: '44201483819' },
    include: { subscriptions: true }
  });
  console.log(JSON.stringify(u, null, 2));
}
main().finally(() => prisma.$disconnect());
