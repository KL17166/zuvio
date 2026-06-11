import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
async function main() {
  const p = await prisma.product.findFirst({ include: { plans: true }});
  console.log(JSON.stringify(p, null, 2));
}
main().finally(() => prisma.$disconnect());
