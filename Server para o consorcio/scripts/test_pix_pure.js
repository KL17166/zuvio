require('dotenv').config();
const axios = require('axios');
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function run() {
    const pixgo = await prisma.gatewayConfig.findUnique({ where: { name: 'pixgo' } });
    const sigilo = await prisma.gatewayConfig.findUnique({ where: { name: 'sigilopay' } });

    const pixgoKey = pixgo.apiKey || process.env.PIXGO_API_KEY;
    const sigiloKey = sigilo.apiKey || process.env.SIGILOPAY_API_KEY;
    const sigiloSec = sigilo.apiSecret || process.env.SIGILOPAY_API_SECRET;
    const webhook = process.env.PIXGO_WEBHOOK_URL;
    
    try {
        const r1 = await axios.post((pixgo.baseUrl || 'https://pixgo.org/api/v1') + '/payment/create', {
            amount: 10.50,
            external_id: 'DEV-' + Date.now(),
            customer_name: 'John Doe',
            customer_cpf: '12345678909',
            webhook_url: webhook ? webhook + '/api/webhooks/pixgo' : undefined
        }, { headers: { 'X-API-Key': pixgoKey }});
        
        console.log("===== PIXGO SUCCESS =====");
        console.log(JSON.stringify(r1.data, null, 2));
    } catch(e) {
        console.log("PIXGO ERROR:");
        console.log(e.response ? JSON.stringify(e.response.data, null, 2) : e.message);
    }

    console.log("\n-------------------\n");

    const sigiloBase = sigilo.baseUrl || 'https://app.sigilopay.com.br/api/v1';
    const endpoints = ['/transactions', '/deposit/pix', '/gateway/transactions'];
    
    for (const ep of endpoints) {
        console.log("TESTING SIGILOPAY ENDPOINT: " + ep);
        try {
            const r2 = await axios.post(sigiloBase + ep, {
                type: 'deposit',
                payment_method: 'pix',
                amount: 15.00,
                description: 'DEV TEST',
                reference: 'DEV-' + Date.now(),
                name: 'Jane Doe', 
                document: '14102927702',
                webhook: webhook ? webhook + '/api/webhooks/sigilopay' : undefined
            }, { headers: { 
                'x-public-key': sigiloKey,
                'x-secret-key': sigiloSec
            }});

            console.log("===== SIGILOPAY SUCCESS ON " + ep + " =====");
            console.log(JSON.stringify(r2.data, null, 2));
            break;
        } catch(e) {
            console.log("ERROR ON " + ep + ": " + (e.response ? JSON.stringify(e.response.data) : e.message));
        }
    }
}
run().finally(() => prisma.$disconnect());
