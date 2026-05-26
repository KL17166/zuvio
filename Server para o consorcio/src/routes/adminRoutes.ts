import { Router } from 'express';
import crypto from 'crypto';
import { hashPassword, verifyPassword } from '../security/password';
import { requireRoles } from '../security/adminAuth';
import jwt from 'jsonwebtoken';
import { prisma } from '../config/database';
import { logger } from '../config/logger';
import * as csrfMiddleware from '../middlewares/csrfMiddleware';
const { authenticator } = require('otplib');

// Controllers
import * as clientsController from '../controllers/admin/clientsController';
import * as contractsController from '../controllers/admin/contractsController';
import * as paymentsController from '../controllers/admin/paymentsController';
import * as bidsController from '../controllers/admin/bidsController';
import * as dashboardController from '../controllers/admin/dashboardController';
import * as adminProductController from '../controllers/admin/adminProductController';
import * as adminUserController from '../controllers/admin/adminUserController';
import * as securityController from '../controllers/admin/securityController';
import * as gatewayController from '../controllers/admin/gatewayController';
import * as reportsController from '../controllers/admin/reportsController';
import * as kycController from '../controllers/admin/kycController';
import * as profileController from '../controllers/admin/profileController';

// Services
import { markInstallmentAsPaid } from '../services/installmentService';

const router = Router();

// ========================================
// GLOBAL CSRF MIDDLEWARE
// ========================================

router.use((req, res, next) => {
    if (req.path === '/login' || req.path === '/logout' || req.path === '/') {
        return next();
    }
    csrfMiddleware.generateToken(req, res, next);
});

router.use((req, res, next) => {
    if (['POST', 'PUT', 'DELETE'].includes(req.method)) {
        if (req.path === '/login') {
            return next();
        }
        return csrfMiddleware.validateToken(req, res, next);
    }
    next();
});

// ========================================
// MIDDLEWARE - Authentication
// ========================================
const isAdmin = async (req: any, res: any, next: any) => {
    if (req.session && req.session.user && ['MASTER', 'MANAGER', 'SUPPORT'].includes(req.session.user.role)) {
        // ── Silent JWT refresh ─────────────────────────────────────────────────
        // Admin JWT expiry is 2 hours. When < 15 minutes remain on the embedded
        // token, silently reissue a fresh 2h JWT and persist it to the session.
        // This is completely transparent to the admin — their session never expires
        // mid-task as long as they are actively making requests.
        const currentToken: string | undefined = req.session.adminToken;
        if (currentToken) {
            try {
                const payload = jwt.verify(currentToken, process.env.JWT_SECRET as string, {
                    algorithms: ['HS256'],
                }) as any;
                const secondsLeft = payload.exp - Math.floor(Date.now() / 1000);
                if (secondsLeft < 15 * 60) {
                    const freshToken = jwt.sign(
                        { userId: req.session.user.id, role: req.session.user.role, type: 'admin_panel' },
                        process.env.JWT_SECRET as string,
                        { algorithm: 'HS256', expiresIn: '2h' } as any
                    );
                    req.session.adminToken = freshToken;
                    await new Promise<void>((resolve) => req.session.save(resolve));
                }
            } catch {
                // Token already expired but session is valid — issue a fresh one
                const freshToken = jwt.sign(
                    { userId: req.session.user.id, role: req.session.user.role, type: 'admin_panel' },
                    process.env.JWT_SECRET as string,
                    { algorithm: 'HS256', expiresIn: '2h' } as any
                );
                req.session.adminToken = freshToken;
                await new Promise<void>((resolve) => req.session.save(resolve));
            }
        }
        return next();
    }

    if (req.xhr || req.headers.accept?.includes('application/json') || !req.headers.accept?.includes('text/html')) {
        return res.status(403).json({
            error: 'Acesso negado',
            message: 'Apenas administradores autorizados podem acessar esta rota. Faca login como admin.'
        });
    }

    req.flash('error', 'Por favor, faca login como administrador.');
    res.redirect('/admin/login');
};

// ========================================
// AUTHENTICATION ROUTES
// ========================================
router.get('/', (req, res) => {
    res.redirect('/admin/login');
});

router.get('/login', (req, res) => {
    res.render('pages/auth/login');
});

function setupAdminSession(req: any, res: any, user: any, rememberMe: boolean) {
    req.session.regenerate((err: any) => {
        if (err) {
            logger.error('Session regeneration error:', err);
            req.flash('error', 'Erro interno ao processar login.');
            return res.redirect('/admin/login');
        }

        req.session.user = {
            id: user.id,
            name: user.name,
            email: user.email,
            role: user.role
        };

        // Gerar JWT admin token para assinar requests e bypassar security middleware.
        // 2-hour expiry: the isAdmin middleware silently refreshes it when < 15 min remain,
        // so an active session never sees the token expire mid-work.
        const adminToken = jwt.sign(
            { userId: user.id, role: user.role, type: 'admin_panel' },
            process.env.JWT_SECRET as string,
            { algorithm: 'HS256', expiresIn: '2h' } as any
        );
        req.session.adminToken = adminToken;

        if (rememberMe) {
            req.session.cookie.maxAge = 30 * 24 * 60 * 60 * 1000; // 30 days
        } else {
            req.session.cookie.maxAge = 24 * 60 * 60 * 1000; // 24 hours
        }

        req.session.save((saveErr: any) => {
            if (saveErr) {
                logger.error('Session save error:', saveErr);
                req.flash('error', 'Erro interno ao processar login.');
                return res.redirect('/admin/login');
            }
            res.redirect('/admin/dashboard');
        });
    });
}

router.post('/login', async (req, res) => {
    const { email, password } = req.body;

    try {
        const user = await prisma.user.findFirst({ where: { email } });

        if (!user || !['MASTER', 'MANAGER', 'SUPPORT'].includes(user.role)) {
            req.flash('error', 'Credenciais inválidas ou sem permissão.');
            return res.redirect('/admin/login');
        }

        const validPassword = await verifyPassword(password, user.passwordHash);
        if (!validPassword) {
            req.flash('error', 'Credenciais inválidas.');
            return res.redirect('/admin/login');
        }

        if (user.twoFactorEnabled && user.twoFactorSecret) {
            (req.session as any).pending2FAUserId = user.id;
            (req.session as any).rememberMe = req.body.remember === 'on';
            return res.redirect('/admin/login/2fa');
        }

        setupAdminSession(req, res, user, req.body.remember === 'on');
    } catch (error) {
        logger.error('Admin login error:', error);
        req.flash('error', 'Erro interno ao processar login.');
        res.redirect('/admin/login');
    }
});

router.get('/login/2fa', (req, res) => {
    if (!(req.session as any).pending2FAUserId) return res.redirect('/admin/login');
    res.render('pages/auth/login-2fa');
});

router.post('/login/2fa', async (req, res) => {
    const userId = (req.session as any).pending2FAUserId;
    if (!userId) return res.redirect('/admin/login');

    const { token } = req.body;
    try {
        const user = await prisma.user.findUnique({ where: { id: userId } });
        if (!user || !user.twoFactorSecret) return res.redirect('/admin/login');

        const isValid = authenticator.verify({ token, secret: user.twoFactorSecret });
        if (!isValid) {
            req.flash('error', 'Código 2FA inválido.');
            return res.redirect('/admin/login/2fa');
        }

        delete (req.session as any).pending2FAUserId;
        setupAdminSession(req, res, user, (req.session as any).rememberMe);
    } catch (err) {
        logger.error('2FA verification error:', err);
        req.flash('error', 'Erro interno ao validar 2FA.');
        res.redirect('/admin/login');
    }
});

router.get('/logout', (req, res) => {
    req.session.destroy(() => {
        res.redirect('/admin/login');
    });
});

// Admin Token endpoint — retorna o JWT do admin autenticado para o frontend
router.get('/token', isAdmin, (req, res) => {
    const token = (req.session as any).adminToken;
    if (!token) {
        return res.status(401).json({ error: 'Token não disponível. Faça login novamente.' });
    }
    res.json({ token });
});

// ========================================
// DASHBOARD
// ========================================
router.get('/dashboard', isAdmin, dashboardController.getDashboard);

// ========================================
// PROFILE / 2FA
// ========================================
router.get('/profile/2fa', isAdmin, profileController.get2FASetup);
router.post('/profile/2fa/enable', isAdmin, profileController.enable2FA);
router.post('/profile/2fa/disable', isAdmin, profileController.disable2FA);

// ========================================
// CLIENTS
// ========================================
router.get('/clients', isAdmin, clientsController.getClients);
router.get('/clients/new', isAdmin, requireRoles(['MASTER', 'MANAGER']), clientsController.getNewClient);
router.post('/clients/new', isAdmin, requireRoles(['MASTER', 'MANAGER']), clientsController.createClient);
router.get('/clients/:id', isAdmin, clientsController.getClientDetails);
router.get('/clients/:id/edit', isAdmin, requireRoles(['MASTER', 'MANAGER']), clientsController.getEditClient);
router.post('/clients/:id/edit', isAdmin, requireRoles(['MASTER', 'MANAGER']), clientsController.updateClient);
router.post('/clients/:id/delete', isAdmin, requireRoles(['MASTER', 'MANAGER']), clientsController.deleteClient);

// Mark client installment as paid (via installmentService)
router.post('/clients/:clientId/installments/:installmentId/mark-paid', isAdmin, requireRoles(['MASTER', 'MANAGER']), async (req, res) => {
    const { clientId, installmentId } = req.params;
    try {
        const result = await markInstallmentAsPaid(installmentId);
        if (result.success) {
            req.flash('success_msg', result.message);
        } else {
            req.flash('error_msg', result.message);
        }
        res.redirect(`/admin/clients/${clientId}`);
    } catch (error) {
        logger.error('Mark client installment paid error:', error);
        req.flash('error_msg', 'Erro ao marcar parcela como paga.');
        res.redirect(`/admin/clients/${clientId}`);
    }
});

// Reset client password
router.post('/clients/:id/reset-password', isAdmin, requireRoles(['MASTER', 'MANAGER']), async (req, res) => {
    const { id } = req.params;
    try {
        const newPassword = crypto.randomBytes(12).toString('base64url').slice(0, 12);
        const hashedPassword = await hashPassword(newPassword);

        await prisma.user.update({
            where: { id },
            data: { passwordHash: hashedPassword }
        });

        req.flash('success_msg', `Senha resetada! Nova senha: ${newPassword}`);
        res.redirect(`/admin/clients/${id}`);
    } catch (error) {
        logger.error('Password reset error:', error);
        req.flash('error_msg', 'Erro ao resetar senha.');
        res.redirect(`/admin/clients/${id}`);
    }
});

// ========================================
// CONTRACTS
// ========================================
router.get('/contracts', isAdmin, contractsController.getContracts);
router.get('/contracts/new', isAdmin, requireRoles(['MASTER', 'MANAGER']), contractsController.getNewContract);
router.post('/contracts/new', isAdmin, requireRoles(['MASTER', 'MANAGER']), contractsController.createContract);
router.get('/contracts/:id', isAdmin, contractsController.getContractDetails);
router.post('/contracts/:id/contemplate', isAdmin, requireRoles(['MASTER', 'MANAGER']), contractsController.contemplateContract);
router.post('/contracts/:id/cancel', isAdmin, requireRoles(['MASTER', 'MANAGER']), contractsController.cancelContract);

// ========================================
// PAYMENTS
// ========================================
router.get('/payments', isAdmin, requireRoles(['MASTER', 'MANAGER']), paymentsController.getPayments);
router.get('/payments/calendar', isAdmin, requireRoles(['MASTER', 'MANAGER']), paymentsController.getPaymentsCalendar);
router.get('/payments/overdue', isAdmin, requireRoles(['MASTER', 'MANAGER']), paymentsController.getOverduePayments);
router.post('/payments/:id/update', isAdmin, requireRoles(['MASTER', 'MANAGER']), paymentsController.updatePayment);

// Mark payment as paid (via installmentService)
router.post('/payments/:id/mark-paid', isAdmin, requireRoles(['MASTER', 'MANAGER']), async (req, res) => {
    const { id } = req.params;
    const { paymentMethod, paymentDate } = req.body;

    try {
        const result = await markInstallmentAsPaid(id, {
            paymentMethod: paymentMethod || undefined,
            paymentDate: paymentDate ? new Date(paymentDate) : undefined
        });

        if (result.success) {
            req.flash('success_msg', result.message);
        } else {
            req.flash('error_msg', result.message);
        }

        // Try to redirect back to the contract details page
        const installment = await prisma.installment.findUnique({ where: { id } });
        if (installment) {
            res.redirect(`/admin/contracts/${installment.subscriptionId}`);
        } else {
            res.redirect('/admin/contracts');
        }
    } catch (error) {
        logger.error('Mark contract installment paid error:', error);
        req.flash('error_msg', 'Erro ao marcar parcela como paga.');
        res.redirect('/admin/contracts');
    }
});

// ========================================
// BIDS
// ========================================
router.get('/bids', isAdmin, requireRoles(['MASTER', 'MANAGER']), bidsController.getBids);
router.get('/bids/pending', isAdmin, requireRoles(['MASTER', 'MANAGER']), bidsController.getPendingBids);
router.get('/bids/draw', isAdmin, requireRoles(['MASTER', 'MANAGER']), bidsController.getDrawPage);
router.post('/bids/draw', isAdmin, requireRoles(['MASTER', 'MANAGER']), bidsController.performDraw);
router.get('/bids/:id', isAdmin, requireRoles(['MASTER', 'MANAGER']), bidsController.getBidDetails);
router.post('/bids/:id/approve', isAdmin, requireRoles(['MASTER', 'MANAGER']), bidsController.approveBid);
router.post('/bids/:id/reject', isAdmin, requireRoles(['MASTER', 'MANAGER']), bidsController.rejectBid);

// ========================================
// PRODUCTS
// ========================================
router.get('/products', isAdmin, requireRoles(['MASTER', 'MANAGER']), adminProductController.listProducts);
router.get('/products/new', isAdmin, requireRoles(['MASTER', 'MANAGER']), adminProductController.newProductForm);
router.post('/products/new', isAdmin, requireRoles(['MASTER', 'MANAGER']), adminProductController.createProduct);
router.get('/products/:id/edit', isAdmin, requireRoles(['MASTER', 'MANAGER']), adminProductController.editProductForm);
router.post('/products/:id/edit', isAdmin, requireRoles(['MASTER', 'MANAGER']), adminProductController.updateProduct);
router.post('/products/:id/delete', isAdmin, requireRoles(['MASTER', 'MANAGER']), adminProductController.deleteProduct);

// ========================================
// USERS (Admin Users Management)
// ========================================
router.get('/users', isAdmin, requireRoles(['MASTER']), adminUserController.listUsers);
router.get('/users/new', isAdmin, requireRoles(['MASTER']), adminUserController.newUserForm);
router.post('/users/new', isAdmin, requireRoles(['MASTER']), adminUserController.createUser);
router.get('/users/:id/edit', isAdmin, requireRoles(['MASTER']), adminUserController.editUserForm);
router.post('/users/:id/edit', isAdmin, requireRoles(['MASTER']), adminUserController.updateUser);
router.post('/users/:id/delete', isAdmin, requireRoles(['MASTER']), adminUserController.deleteUser);
router.post('/users/:id/reset-password', isAdmin, requireRoles(['MASTER']), adminUserController.resetPassword);

// ========================================
// REPORTS
// ========================================
router.get('/reports', isAdmin, requireRoles(['MASTER', 'MANAGER']), reportsController.getReports);

// ========================================
// SECURITY
// ========================================
router.get('/security', isAdmin, requireRoles(['MASTER']), securityController.getSecurityDashboard);
router.post('/security/unblock/:id', isAdmin, requireRoles(['MASTER']), securityController.unblockDevice);

// ========================================
// GATEWAYS
// ========================================
router.get('/gateways', isAdmin, requireRoles(['MASTER']), gatewayController.listGateways);
router.get('/gateways/sigilopay/balance', isAdmin, requireRoles(['MASTER']), gatewayController.getSigiloPayBalance);
router.post('/gateways/sigilopay/withdraw', isAdmin, requireRoles(['MASTER']), gatewayController.requestSigiloPayWithdraw);
router.post('/gateways/:id/update', isAdmin, requireRoles(['MASTER']), gatewayController.updateGateway);
router.post('/gateways/:id/toggle', isAdmin, requireRoles(['MASTER']), gatewayController.toggleGateway);
// ========================================
// KYC VERIFICATION
// ========================================
router.get('/kyc', isAdmin, requireRoles(['MASTER', 'MANAGER', 'SUPPORT']), kycController.getKycQueue);

// Detail — all roles can call but SUPPORT receives masked/redacted payload (enforced in controller)
router.get('/kyc/:userId', isAdmin, requireRoles(['MASTER', 'MANAGER', 'SUPPORT']), kycController.getKycDetail);

router.post('/kyc/:userId/approve', isAdmin, requireRoles(['MASTER', 'MANAGER']), kycController.approveKyc);
router.post('/kyc/:userId/reject', isAdmin, requireRoles(['MASTER', 'MANAGER']), kycController.rejectKyc);

// Manual override — bypasses Datavalid result; body: { action: 'approve'|'reject', reason? }
router.post('/kyc/:userId/override', isAdmin, requireRoles(['MASTER', 'MANAGER']), kycController.overrideKyc);

// Re-trigger Datavalid for a user; body: { step: 'facial'|'biographical' }
router.post('/kyc/:userId/retrigger', isAdmin, requireRoles(['MASTER', 'MANAGER']), kycController.retriggerKyc);

export default router;
