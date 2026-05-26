import { PixGoService } from '../src/services/gateways/pixGoService';
import { SigiloPayService } from '../src/services/gateways/sigiloPayService';
import { prisma } from '../src/config/database';
import { env } from '../src/config/env';

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

async function testGateways() {
    try {
        const validCpf = generateValidCPF();
        console.log(`Using valid test CPF for this run: ${validCpf}\n`);

        console.log('--- 🟢 Testing PixGo PIX Generation ---');
        try {
            const pixgoRes = await PixGoService.createPayment({
                amount: 10.50,
                external_id: 'TEST-PIXGO-' + Date.now(),
                description: 'Test PixGo Integration',
                customer_name: 'Marcos Aurelio',
                customer_cpf: validCpf
            });
            console.log('✅ PixGo SUCESSO:');
            console.log('   ID da Transação:', pixgoRes.id);
            console.log('   Copia e Cola:', pixgoRes.qr_code.substring(0, 50) + '...');
        } catch (e: any) {
            console.log('❌ PixGo FALHA:', e.message || e);
        }

        console.log('\n----------------------------------------\n');

        console.log('--- 🟢 Testing SigiloPay PIX Generation ---');
        try {
            const sigiloRes = await SigiloPayService.createPixDeposit({
                amount: 15.00,
                external_id: 'TEST-SIGILO-' + Date.now(),
                description: 'Test SigiloPay Integration',
                payer: {
                    name: 'Maria Antonieta',
                    document: validCpf,
                    email: 'maria.test@example.com',
                    phone: '11999999999'
                }
            });
            console.log('✅ SigiloPay SUCESSO:');
            console.log('   ID da Transação:', sigiloRes.transactionId);
            console.log('   Pix Copia e Cola:', sigiloRes.pix?.code?.substring(0, 50) + '...');
        } catch (e: any) {
            console.log('❌ SigiloPay FALHA:', e.message || e);
        }
        
    } finally {
        await prisma.$disconnect();
    }
}

testGateways();
