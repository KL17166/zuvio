import { markInstallmentAsPaid } from '../services/installmentService';

// Mock Prisma with transaction support
const mockInstallmentFindUnique = jest.fn();
const mockInstallmentUpdate = jest.fn();
const mockInstallmentCount = jest.fn();
const mockSubscriptionUpdate = jest.fn();

const createTxMock = () => ({
    installment: {
        findUnique: (...args: any[]) => mockInstallmentFindUnique(...args),
        update: (...args: any[]) => mockInstallmentUpdate(...args),
        count: (...args: any[]) => mockInstallmentCount(...args),
    },
    subscription: {
        update: (...args: any[]) => mockSubscriptionUpdate(...args),
    }
});

jest.mock('../config/database', () => ({
    prisma: {
        installment: {
            findUnique: (...args: any[]) => mockInstallmentFindUnique(...args),
        },
        // $transaction receives a callback — we call it with a tx mock
        $transaction: (fn: (tx: any) => Promise<any>, _opts?: any) => fn(createTxMock()),
    }
}));

jest.mock('../config/logger', () => ({
    logger: {
        error: jest.fn(),
        info: jest.fn(),
        warn: jest.fn(),
    }
}));

describe('markInstallmentAsPaid', () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('should return error if installment not found', async () => {
        mockInstallmentFindUnique.mockResolvedValue(null);

        const result = await markInstallmentAsPaid('invalid-id');

        expect(result.success).toBe(false);
        expect(result.message).toContain('não encontrada');
    });

    it('should return error if installment already paid', async () => {
        mockInstallmentFindUnique.mockResolvedValue({
            id: '1',
            status: 'PAID',
            subscription: { id: 'sub-1' }
        });

        const result = await markInstallmentAsPaid('1');

        expect(result.success).toBe(false);
        expect(result.message).toContain('já está paga');
    });

    it('should mark installment as paid and update subscription atomically', async () => {
        // Pre-validation read
        mockInstallmentFindUnique
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 3, amount: 500,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'ACTIVE' }
            })
            // Transaction re-read
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 3, amount: 500,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'ACTIVE' }
            });
        mockInstallmentUpdate.mockResolvedValue({});
        mockSubscriptionUpdate.mockResolvedValue({});
        mockInstallmentCount.mockResolvedValue(2); // 2 unpaid remaining

        const result = await markInstallmentAsPaid('1');

        expect(result.success).toBe(true);
        expect(result.message).toContain('#3');
        expect(mockInstallmentUpdate).toHaveBeenCalledWith(
            expect.objectContaining({
                where: { id: '1' },
                data: expect.objectContaining({ status: 'PAID' })
            })
        );
        expect(mockSubscriptionUpdate).toHaveBeenCalledWith(
            expect.objectContaining({
                where: { id: 'sub-1' },
                data: expect.objectContaining({
                    paidInstallments: { increment: 1 },
                    balanceDue: { decrement: 500 }
                })
            })
        );
    });

    it('should activate subscription when paying adesão with KYC APPROVED', async () => {
        mockInstallmentFindUnique
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 1, amount: 200,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'PENDING' }
            })
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 1, amount: 200,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'PENDING', user: { kycStatus: 'APPROVED' } }
            });
        mockInstallmentUpdate.mockResolvedValue({});
        mockSubscriptionUpdate.mockResolvedValue({});
        mockInstallmentCount.mockResolvedValue(5);

        const result = await markInstallmentAsPaid('1');

        expect(result.success).toBe(true);
        expect(result.activated).toBe(true);
        expect(result.pendingKyc).toBeFalsy();
        expect(mockSubscriptionUpdate).toHaveBeenCalledWith(
            expect.objectContaining({
                data: expect.objectContaining({ status: 'ACTIVE' })
            })
        );
    });

    it('should set PENDING_KYC when paying adesão without KYC approval', async () => {
        mockInstallmentFindUnique
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 1, amount: 200,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'PENDING' }
            })
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 1, amount: 200,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'PENDING', user: { kycStatus: 'PENDING' } }
            });
        mockInstallmentUpdate.mockResolvedValue({});
        mockSubscriptionUpdate.mockResolvedValue({});
        mockInstallmentCount.mockResolvedValue(5);

        const result = await markInstallmentAsPaid('1');

        expect(result.success).toBe(true);
        expect(result.pendingKyc).toBe(true);
        expect(result.activated).toBeFalsy();
        expect(result.message).toContain('KYC');
        expect(mockSubscriptionUpdate).toHaveBeenCalledWith(
            expect.objectContaining({
                data: expect.objectContaining({ status: 'PENDING_KYC' })
            })
        );
    });

    it('should complete subscription when all installments are paid', async () => {
        mockInstallmentFindUnique
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 5, amount: 100,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'ACTIVE' }
            })
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 5, amount: 100,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'ACTIVE' }
            });
        mockInstallmentUpdate.mockResolvedValue({});
        mockSubscriptionUpdate.mockResolvedValue({});
        mockInstallmentCount.mockResolvedValue(0); // 0 unpaid = all paid!

        const result = await markInstallmentAsPaid('1');

        expect(result.success).toBe(true);
        expect(result.completed).toBe(true);
        // Called twice: once for balance, once for COMPLETED
        expect(mockSubscriptionUpdate).toHaveBeenCalledTimes(2);
    });

    it('should handle TOCTOU — already paid in transaction re-read', async () => {
        // Pre-validation: shows PENDING
        mockInstallmentFindUnique
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 2, amount: 300,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'ACTIVE' }
            })
            // Transaction re-read: already PAID (concurrent process beat us)
            .mockResolvedValueOnce({
                id: '1', status: 'PAID', number: 2, amount: 300,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'ACTIVE' }
            });

        const result = await markInstallmentAsPaid('1');

        // Should detect the race and return gracefully
        expect(result.success).toBe(false);
        expect(result.message).toContain('já está paga');
        expect(mockInstallmentUpdate).not.toHaveBeenCalled();
    });

    it('should use custom payment method and date', async () => {
        const customDate = new Date('2025-06-15');
        mockInstallmentFindUnique
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 2, amount: 300,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'ACTIVE' }
            })
            .mockResolvedValueOnce({
                id: '1', status: 'PENDING', number: 2, amount: 300,
                subscriptionId: 'sub-1', subscription: { id: 'sub-1', status: 'ACTIVE' }
            });
        mockInstallmentUpdate.mockResolvedValue({});
        mockSubscriptionUpdate.mockResolvedValue({});
        mockInstallmentCount.mockResolvedValue(3);

        await markInstallmentAsPaid('1', {
            paymentMethod: 'PIX',
            paymentDate: customDate
        });

        expect(mockInstallmentUpdate).toHaveBeenCalledWith(
            expect.objectContaining({
                data: expect.objectContaining({
                    paymentMethod: 'PIX',
                    paymentDate: customDate
                })
            })
        );
    });
});
