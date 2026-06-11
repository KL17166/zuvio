import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
async function main() {
  await prisma.product.updateMany({
    data: { maxDuration: 60 }
  });
  console.log('Reverted maxDuration to 60 for all products.');
}
main().finally(() => prisma.$disconnect());
