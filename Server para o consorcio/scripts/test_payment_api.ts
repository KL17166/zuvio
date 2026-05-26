import axios from 'axios';
import { PrismaClient } from '@prisma/client';
import * as jwt from 'jsonwebtoken';
import * as crypto from 'crypto';
import app from '../src/app'; // Make sure to export app from src/app.ts if not already
import { generatePaymentToken } from '../src/security/paymentToken';

const prisma = new PrismaClient();
const PORT = 3005;
const BASE_URL = `http://localhost:${PORT}/api`;
const JWT_SECRET = process.env.JWT_SECRET || 'fallback_secret_for_dev';
const REQUEST_SIGNING_SECRET = process.env.REQUEST_SIGNING_SECRET || 'katari-hmac-secret-change-in-prod';

/**
 * Helper to generate the Request Signature headers
 */
function getSignatureHeaders(method: string, path: string, bodyObj: any) {
    const timestamp = Date.now().toString();
    // Use empty string to match backend behavior where req.body is undefined before express.json()
    const bodyString = '';
    const bodyHash = crypto.createHash('sha256').update(bodyString).digest('hex');
    const payload = `${timestamp}|${method}|${path}|${bodyHash}`;
    const signature = crypto.createHmac('sha256', REQUEST_SIGNING_SECRET).update(payload).digest('hex');
    
    return {
        'x-request-timestamp': timestamp,
        'x-request-signature': signature
    };
}

/**
 * Valid random CPF generator for testing
 */
function generateValidCPF() {
    const randomDigit = () => Math.floor(Math.random() * 9);
    const mod11 = (sum: number) => sum % 11 < 2 ? 0 : 11 - (sum % 11);

    const n = Array.from({ length: 9 }, randomDigit);
    n.push(mod11(n.reduce((acc, val, i) => acc + val * (10 - i), 0)));
    n.push(mod11(n.reduce((acc, val, i) => acc + val * (11 - i), 0)));

    return n.join('');
}

async function runTests() {
    // Start isolated server for tests
    const server = app.listen(PORT, () => {
        console.log(`\n--- 🚀 Test Server running on port ${PORT} ---`);
    });

    try {
        console.log('--- 🟢 Starting E2E Payment API Tests ---');

        // 1. Try to find a valid user with an active pending installment
        let installment = await prisma.installment.findFirst({
            where: {
                status: 'PENDING',
                subscription: {
                    user: {
                        role: 'USER'
                    }
                }
            },
            include: {
                subscription: {
                    include: {
                        user: true
                    }
                }
            }
        });

        let isMockData = false;

        if (!installment) {
            console.log('⚠️ No PENDING installment found. Creating mock data for the test...');
            isMockData = true;

            const mockUser = await prisma.user.create({
                data: {
                    email: `test_api_${Date.now()}@example.com`,
                    name: 'API Test User',
                    cpf: generateValidCPF(),
                    phone: '11999999999',
                    passwordHash: 'hashed_password_mock',
                    address: JSON.stringify({
                        zipCode: '01001000',
                        street: 'Praça da Sé',
                        number: '1',
                        complement: 'Lado ímpar',
                        neighborhood: 'Sé',
                        city: 'São Paulo',
                        state: 'SP'
                    })
                }
            });

            const plan = await prisma.consortiumPlan.findFirst() || await prisma.consortiumPlan.create({
                data: {
                    name: 'Mock Plan',
                    durationMonths: 60,
                    adminFeeRate: 15.0,
                    fundRate: 2.0,
                    product: {
                        create: {
                            name: 'Mock Product',
                            description: 'A mock product for testing',
                            type: 'CARRO',
                            category: 'sedan',
                            imageUrl: 'mock.jpg',
                            imageUrls: '[]',
                            price: 50000
                        }
                    }
                }
            });

            const mockSubscription = await prisma.subscription.create({
                data: {
                    userId: mockUser.id,
                    planId: plan.id,
                    groupNumber: '001',
                    quotaNumber: '001',
                    creditValue: 50000,
                    balanceDue: 50000,
                    totalInstallments: 60,
                    status: 'ACTIVE'
                }
            });

            installment = await prisma.installment.create({
                data: {
                    subscriptionId: mockSubscription.id,
                    number: 1,
                    amount: 10,
                    dueDate: new Date(Date.now() + 24 * 60 * 60 * 1000),
                    status: 'PENDING'
                },
                include: {
                    subscription: {
                        include: {
                            user: true
                        }
                    }
                }
            });
        }

        const user = installment.subscription.user;

        // Ensure SigiloPay is active in the database for the test
        await prisma.gatewayConfig.upsert({
            where: { name: 'sigilopay' },
            create: {
                name: 'sigilopay',
                displayName: 'SigiloPay',
                enabled: true,
                environment: 'sandbox',
                supportsPix: true,
                supportsBoleto: true,
                isDefaultPix: true,
                isDefaultBoleto: true
            },
            update: {
                enabled: true,
                supportsPix: true,
                supportsBoleto: true,
                isDefaultPix: true,
                isDefaultBoleto: true
            }
        });
        console.log(`✅ Selected Test User: ${user.name} (ID: ${user.id})`);
        console.log(`✅ Selected Installment: #${installment.number} (ID: ${installment.id}) - Sub: ${installment.subscriptionId}`);

        // 2. Generate Auth Token
        const token = jwt.sign({ userId: user.id, role: user.role }, JWT_SECRET, { expiresIn: '1h' });
        
        // 3. Generate idTokenPay payload
        const idTokenPay = generatePaymentToken(installment.subscriptionId, installment.number, user.id);
        
        console.log(`\n--- 🔵 Test 1: POST /payments/${installment.id}/pix ---`);
        try {
            const pixPath = `/api/payments/${installment.id}/pix`;
            const pixBody = { idTokenPay };
            
            const pixRawResponse = await axios.post(
                `${BASE_URL}/payments/${installment.id}/pix`,
                pixBody,
                {
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'Content-Type': 'application/json',
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                        ...getSignatureHeaders('POST', pixPath, pixBody)
                    }
                }
            );
            
            console.log('✅ PIX API Success - Payload retornado para o App:');
            console.log(JSON.stringify(pixRawResponse.data, null, 2));
            
        } catch (error: any) {
            console.log('❌ PIX API Failed:');
            console.log(error.response?.data || error.message);
        }

        // Add small delay to prevent rate limits
        await new Promise(res => setTimeout(res, 1000));

        console.log(`\n--- 🔵 Test 2: POST /payments/${installment.id}/boleto ---`);
        try {
            const boletoPath = `/api/payments/${installment.id}/boleto`;
            const boletoBody = { idTokenPay };

            const boletoRawResponse = await axios.post(
                `${BASE_URL}/payments/${installment.id}/boleto`,
                boletoBody,
                {
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'Content-Type': 'application/json',
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                        ...getSignatureHeaders('POST', boletoPath, boletoBody)
                    }
                }
            );
            
            console.log('✅ BOLETO API Success - Payload retornado para o App:');
            console.log(JSON.stringify(boletoRawResponse.data, null, 2));

        } catch (error: any) {
            console.log('❌ BOLETO API Failed:');
            console.log(error.response?.data || error.message);
        }

    } finally {
        await prisma.$disconnect();
        server.close();
        console.log('\n--- 🏁 Tests Finished ---');
    }
}

runTests();
