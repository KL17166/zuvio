// Check products in the database
import { prisma } from '../config/database';

async function checkProducts() {
    try {
        const products = await prisma.product.findMany({
            where: {
                name: { contains: 'PCX' }
            },
            include: { plans: true }
        });

        console.log('=== PRODUCT SEARCH: PCX ===');
        console.log(`Found: ${products.length}`);

        products.forEach((product, i) => {
            console.log(`\n--- Result ${i + 1} ---`);
            console.log(`ID: ${product.id}`);
            console.log(`Name: ${product.name}`);
            console.log(`Type: ${product.type}`);
            console.log(`Price: ${product.price}`);
            console.log(`Active: ${product.active}`);
            console.log(`Plans: ${product.plans.length}`);
        });

        // Also check all products with price 0
        const zeroPrice = await prisma.product.findMany({
            where: { price: 0 }
        });

        console.log(`\n=== PRODUCTS WITH PRICE 0 ===`);
        console.log(`Found: ${zeroPrice.length}`);
        zeroPrice.forEach(p => console.log(`- ${p.name}: ${p.price}`));

    } catch (error) {
        console.error('Error:', error);
    } finally {
        await prisma.$disconnect();
    }
}

checkProducts();
