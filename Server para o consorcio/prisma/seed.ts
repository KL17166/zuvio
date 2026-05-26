import { PrismaClient } from '@prisma/client';
import fs from 'fs';
import path from 'path';
import { hashPassword } from '../src/security/password';

const prisma = new PrismaClient();

// Moto specs (kept from original seed, now stored as JSON)
const motoSpecsMap: Record<string, any> = {
    "1": {
        displacement: "249cc", power: "22,4 cv @ 7.500 rpm", torque: "2,24 kgf.m @ 6.000 rpm",
        transmission: "6 marchas", engineType: "Monocilíndrico 4 tempos",
        frontBrake: "Disco", rearBrake: "Disco", weight: "137 kg",
        fuelCapacity: "16,5 litros", consumption: "30 km/l"
    },
    "2": {
        displacement: "249cc", power: "21,3 cv @ 8.000 rpm", torque: "2,1 kgf.m @ 6.500 rpm",
        transmission: "5 marchas", engineType: "Blue Core 4 tempos",
        frontBrake: "Disco", rearBrake: "Disco", weight: "149 kg",
        fuelCapacity: "14 litros", consumption: "32 km/l"
    },
    "3": {
        displacement: "291cc", power: "25,4 cv @ 7.500 rpm", torque: "2,76 kgf.m @ 6.000 rpm",
        transmission: "5 marchas", engineType: "DOHC Monocilíndrico",
        frontBrake: "Disco/ABS", rearBrake: "Disco/ABS", weight: "148 kg",
        fuelCapacity: "13,8 litros", consumption: "25 km/l"
    },
    "4": {
        displacement: "249cc", power: "20,7 cv @ 8.000 rpm", torque: "2,1 kgf.m @ 6.500 rpm",
        transmission: "5 marchas", engineType: "SOHC 2 válvulas",
        frontBrake: "Disco/ABS", rearBrake: "Disco", weight: "153 kg",
        fuelCapacity: "13,6 litros", consumption: "30 km/l"
    },
    "5": {
        displacement: "745cc", power: "45,5 cv @ 5.500 rpm", torque: "6,5 kgf.m @ 3.500 rpm",
        transmission: "5 marchas", engineType: "V-Twin OHC",
        frontBrake: "Disco", rearBrake: "Tambor", weight: "250 kg",
        fuelCapacity: "14,6 litros", consumption: "20 km/l"
    },
    "6": {
        displacement: "749cc", power: "53 cv @ 8.000 rpm", torque: "6,0 kgf.m @ 4.000 rpm",
        transmission: "6 marchas", engineType: "Revolution X V-Twin",
        frontBrake: "Disco", rearBrake: "Disco", weight: "223 kg",
        fuelCapacity: "13,1 litros", consumption: "18 km/l"
    },
    "7": {
        displacement: "156.9cc", power: "16 cv @ 8.500 rpm", torque: "1,5 kgf.m @ 6.500 rpm",
        transmission: "CVT", engineType: "OHC Monocilíndrico",
        frontBrake: "Disco/ABS", rearBrake: "Disco", weight: "124 kg",
        fuelCapacity: "8 litros", consumption: "40 km/l"
    },
    "8": {
        displacement: "155cc", power: "15,4 cv @ 8.000 rpm", torque: "1,4 kgf.m @ 6.500 rpm",
        transmission: "CVT", engineType: "SOHC 4 válvulas",
        frontBrake: "Disco/ABS", rearBrake: "Disco", weight: "131 kg",
        fuelCapacity: "7,1 litros", consumption: "38 km/l"
    }
};

// Sample products for NEW categories
const extraProducts = [
    {
        name: "Toyota Corolla Cross 2025",
        description: "SUV compacto com design moderno, motor híbrido e tecnologia de ponta. Ideal para a cidade e estrada.",
        type: "CARRO",
        category: "suv",
        price: 195990,
        brand: "Toyota",
        model: "Corolla Cross",
        year: 2025,
        imageUrl: "https://placehold.co/600x400/1a73e8/white?text=Corolla+Cross",
        specs: {
            motor: "1.8L Híbrido", potencia: "122 cv combinados", cambio: "CVT",
            combustivel: "Flex + Elétrico", portas: 5, lugares: 5,
            portaMalas: "440L", tracao: "Dianteira"
        }
    },
    {
        name: "Hyundai HB20 2025",
        description: "Hatch compacto mais vendido do Brasil. Econômico, moderno e com ótimo custo-benefício.",
        type: "CARRO",
        category: "hatch",
        price: 89990,
        brand: "Hyundai",
        model: "HB20",
        year: 2025,
        imageUrl: "https://placehold.co/600x400/0d47a1/white?text=HB20",
        specs: {
            motor: "1.0 Turbo", potencia: "120 cv", cambio: "Automático 6 marchas",
            combustivel: "Flex", portas: 5, lugares: 5,
            portaMalas: "300L", tracao: "Dianteira"
        }
    },
    {
        name: "Chevrolet Tracker 2025",
        description: "SUV connect com Wi-Fi nativo, motor turbo e design arrojado.",
        type: "CARRO",
        category: "suv",
        price: 149990,
        brand: "Chevrolet",
        model: "Tracker",
        year: 2025,
        imageUrl: "https://placehold.co/600x400/e65100/white?text=Tracker",
        specs: {
            motor: "1.0 Turbo", potencia: "116 cv", cambio: "Automático 6 marchas",
            combustivel: "Flex", portas: 5, lugares: 5,
            portaMalas: "393L", tracao: "Dianteira"
        }
    },
    {
        name: "Carta de Crédito R$ 50.000",
        description: "Carta de crédito para aquisição de bens, serviços ou início de negócio. Use como quiser!",
        type: "CARTA_CREDITO",
        category: "geral",
        price: 50000,
        brand: null,
        model: null,
        year: null,
        imageUrl: "https://placehold.co/600x400/2e7d32/white?text=Carta+50k",
        specs: { finalidade: "Livre", restricoes: "Nenhuma" }
    },
    {
        name: "Carta de Crédito R$ 150.000",
        description: "Carta de crédito para compra de veículo, reforma ou investimento. Versatilidade total.",
        type: "CARTA_CREDITO",
        category: "veiculo",
        price: 150000,
        brand: null,
        model: null,
        year: null,
        imageUrl: "https://placehold.co/600x400/1b5e20/white?text=Carta+150k",
        specs: { finalidade: "Veículos e Reforma", restricoes: "Nenhuma" }
    },
    {
        name: "Carta de Crédito R$ 500.000",
        description: "Carta de crédito de alto valor para imóvel, empreendimento ou veículo de luxo.",
        type: "CARTA_CREDITO",
        category: "imovel",
        price: 500000,
        brand: null,
        model: null,
        year: null,
        imageUrl: "https://placehold.co/600x400/004d40/white?text=Carta+500k",
        specs: { finalidade: "Imóvel e Investimento", restricoes: "Nenhuma" }
    },
    {
        name: "Carta de Crédito R$ 1.250.000",
        description: "Carta de crédito premium para os maiores projetos. Casa própria, terreno, ou o empreendimento dos seus sonhos.",
        type: "CARTA_CREDITO",
        category: "premium",
        price: 1250000,
        brand: null,
        model: null,
        year: null,
        imageUrl: "https://placehold.co/600x400/311b92/white?text=Carta+1.25M",
        specs: { finalidade: "Livre - Alto Valor", restricoes: "Nenhuma" }
    },
    {
        name: "PC Gamer RTX 4070 Super",
        description: "Setup gamer completo: RTX 4070 Super, Ryzen 7 7800X3D, 32GB DDR5, SSD 1TB NVMe. Roda tudo no ultra!",
        type: "ELETRONICO",
        category: "gaming",
        price: 12500,
        brand: "Custom Build",
        model: "RTX 4070 Super Edition",
        year: 2025,
        imageUrl: "https://placehold.co/600x400/6a1b9a/white?text=PC+Gamer",
        specs: {
            processador: "AMD Ryzen 7 7800X3D", gpu: "NVIDIA RTX 4070 Super 12GB",
            ram: "32GB DDR5 6000MHz", armazenamento: "1TB NVMe Gen4",
            fonte: "750W 80+ Gold", gabinete: "Mid-Tower RGB"
        }
    },
    {
        name: "MacBook Pro M4 Pro",
        description: "Notebook profissional Apple com chip M4 Pro, 18GB RAM, tela Liquid Retina XDR 14 polegadas.",
        type: "ELETRONICO",
        category: "notebook",
        price: 18999,
        brand: "Apple",
        model: "MacBook Pro 14\"",
        year: 2025,
        imageUrl: "https://placehold.co/600x400/37474f/white?text=MacBook+Pro",
        specs: {
            processador: "Apple M4 Pro 12-core", gpu: "GPU 18-core integrada",
            ram: "18GB Unified Memory", armazenamento: "512GB SSD",
            tela: "14\" Liquid Retina XDR", bateria: "Até 17h"
        }
    }
];

const PLAN_TEMPLATES = [
    { months: 36, taxRate: 5.99 },
    { months: 48, taxRate: 6.99 },
    { months: 60, taxRate: 7.99 },
    { months: 70, taxRate: 8.99 },
    { months: 80, taxRate: 9.99 },
    { months: 90, taxRate: 10.99 },
];

async function main() {
    console.log('🌱 Starting seed...');

    // ============ Admin User ============
    const adminEmail = process.env.ADMIN_EMAIL;
    const adminPasswordPlain = process.env.ADMIN_PASSWORD;
    const adminCpf = process.env.ADMIN_CPF;

    if (!adminEmail || !adminPasswordPlain || !adminCpf) {
        throw new Error('❌ Missing Admin credentials in .env (ADMIN_EMAIL, ADMIN_PASSWORD, ADMIN_CPF)');
    }

    const adminPassword = await hashPassword(adminPasswordPlain);

    await prisma.user.upsert({
        where: { email: adminEmail },
        update: { passwordHash: adminPassword, role: 'MASTER' },
        create: {
            name: 'Administrador',
            email: adminEmail,
            cpf: adminCpf,
            passwordHash: adminPassword,
            role: 'MASTER',
            birthDate: new Date('2000-01-01'),
        }
    });
    console.log(`👨‍💼 Admin user ready: ${adminEmail} (MASTER)`);

    // ============ Test Client User ============
    const testClientEmail = 'cliente@teste.com';
    const testClientPassword = await hashPassword('cliente123');
    await prisma.user.upsert({
        where: { email: testClientEmail },
        update: { passwordHash: testClientPassword },
        create: {
            name: 'Cliente Teste',
            email: testClientEmail,
            cpf: '11111111111',
            phone: '11999999999',
            passwordHash: testClientPassword,
            role: 'CLIENT',
            birthDate: new Date('1995-05-15'),
        }
    });
    console.log(`👤 Test client user ready: ${testClientEmail}`);

    // ============ Motorcycles from data.json ============
    const jsonPath = path.resolve('..', 'App-android-web', 'assets', 'motorcycles', 'data.json');

    if (fs.existsSync(jsonPath)) {
        let rawData = fs.readFileSync(jsonPath, 'utf8');
        if (rawData.charCodeAt(0) === 0xFEFF) rawData = rawData.slice(1);
        const motorcyclesData = JSON.parse(rawData);

        for (const moto of motorcyclesData) {
            const specs = motoSpecsMap[moto.id] || {};

            const created = await prisma.product.create({
                data: {
                    name: moto.name,
                    description: moto.description,
                    type: 'MOTO',
                    category: moto.category || 'urbana',
                    imageUrl: moto.imageUrls?.[0]?.startsWith('http')
                        ? moto.imageUrls[0]
                        : `https://placehold.co/600x400/png?text=${encodeURIComponent(moto.name)}`,
                    imageUrls: JSON.stringify(moto.imageUrls?.[0]?.startsWith('http')
                        ? moto.imageUrls
                        : [`https://placehold.co/600x400/png?text=${encodeURIComponent(moto.name)}`]),
                    price: moto.price,
                    active: true,
                    isFeatured: moto.isFeatured || false,
                    isPopular: moto.isPopular || false,
                    brand: moto.name.split(' ')[0], // First word = brand (Honda, Yamaha, Harley)
                    model: moto.name,
                    year: specs.year || 2024,
                    specs: JSON.stringify(specs)
                }
            });

            console.log(`🏍️  Created MOTO: ${created.name}`);

            for (const template of PLAN_TEMPLATES) {
                await prisma.consortiumPlan.create({
                    data: {
                        name: `${template.months} Meses`,
                        durationMonths: template.months,
                        adminFeeRate: template.taxRate,
                        fundRate: 2.0,
                        productId: created.id,
                        active: true
                    }
                });
            }
            console.log(`   ✅ Created ${PLAN_TEMPLATES.length} plans`);
        }
    } else {
        console.warn(`⚠️ Moto data.json not found at ${jsonPath}, skipping motorcycle seeds`);
    }

    // ============ Extra Products (Carros, Cartas, Eletrônicos) ============
    for (const product of extraProducts) {
        const created = await prisma.product.create({
            data: {
                name: product.name,
                description: product.description,
                type: product.type,
                category: product.category,
                imageUrl: product.imageUrl,
                imageUrls: JSON.stringify([product.imageUrl]),
                price: product.price,
                active: true,
                isFeatured: false,
                isPopular: false,
                brand: product.brand,
                model: product.model,
                year: product.year,
                specs: JSON.stringify(product.specs)
            }
        });

        const emoji = { CARRO: '🚗', CARTA_CREDITO: '💳', ELETRONICO: '💻', IMOVEL: '🏠', SERVICO: '✈️' }[product.type] || '📦';
        console.log(`${emoji} Created ${product.type}: ${created.name}`);

        for (const template of PLAN_TEMPLATES) {
            await prisma.consortiumPlan.create({
                data: {
                    name: `${template.months} Meses`,
                    durationMonths: template.months,
                    adminFeeRate: template.taxRate,
                    fundRate: 2.0,
                    productId: created.id,
                    active: true
                }
            });
        }
        console.log(`   ✅ Created ${PLAN_TEMPLATES.length} plans`);
    }

    console.log('✅ Seed completed successfully.');
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
