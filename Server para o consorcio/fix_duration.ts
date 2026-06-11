import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
async function main() {
  const products = await prisma.product.findMany({ include: { plans: true }});
  let fixed = 0;
  for (const product of products) {
    const maxPlan = Math.max(...product.plans.map(p => p.durationMonths));
    if (product.maxDuration < maxPlan) {
      console.log(`Fixing product ${product.name} maxDuration from ${product.maxDuration} to ${maxPlan}`);
      await prisma.product.update({
        where: { id: product.id },
        data: { maxDuration: maxPlan }
      });
      fixed++;
    }
  }
  console.log(`Fixed ${fixed} products.`);
}
main().finally(() => prisma.$disconnect());
