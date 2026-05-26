import { prisma } from '../config/database';
import { PixGoService } from '../services/gateways/pixGoService';

const installmentId = '08793e8a-c5a8-4748-a1d4-afff92a407a9';

async function debugPix() {
    try {
        console.log('--- DEBUGGING PIX GENERATION ---');
        const installment = await prisma.installment.findUnique({
            where: { id: installmentId },
            include: {
                subscription: {
                    include: {
                        user: true,
                        installments: true
                    }
                }
            }
        });

        if (!installment) {
            console.error('Installment not found');
            return;
        }

        console.log('Installment found:', {
            id: installment.id,
            number: installment.number,
            amount: installment.amount,
            status: installment.status
        });

        const paidIndices = new Set(installment.subscription.installments.filter((i: any) => i.status === 'PAID').map((i: any) => i.number));
        let nextIndex = installment.subscription.totalInstallments + 1;
        for (let i = 1; i <= installment.subscription.totalInstallments; i++) {
            if (!paidIndices.has(i)) {
                nextIndex = i;
                break;
            }
        }

        console.log('Next Index:', nextIndex);

        const calculateInstallmentValue = (baseAmount: number, installmentIndex: number, nextInstallmentIndex: number): number => {
            if (installmentIndex <= nextInstallmentIndex) {
                return baseAmount;
            }
            const monthsInAdvance = installmentIndex - nextInstallmentIndex;
            const discountRate = 0.005;
            return baseAmount / (1 + (discountRate * monthsInAdvance));
        };

        const valueToPay = calculateInstallmentValue(Number(installment.amount), installment.number, nextIndex);
        console.log('Value to Pay:', valueToPay);

        if (valueToPay <= 0) {
            console.error('CRITICAL: Value to pay is 0 or negative. PixGo will likely reject this.');
        }

        console.log('Checking PixGo API Key:', process.env.PIXGO_API_KEY ? 'CONFIGURED' : 'NOT CONFIGURED');

    } catch (error: any) {
        console.error('Debug script error:', error.message);
    } finally {
        await prisma.$disconnect();
    }
}

debugPix();
