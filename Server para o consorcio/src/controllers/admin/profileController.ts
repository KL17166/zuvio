import { Request, Response } from 'express';
const { authenticator } = require('otplib');
import QRCode from 'qrcode';
import { prisma } from '../../config/database';

export const get2FASetup = async (req: Request, res: Response) => {
    const userId = (req.session as any).user.id;
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) return res.redirect('/admin/login');

    if (user.twoFactorEnabled) {
        return res.render('pages/2fa/index', { 
            enabled: true, 
            path: '/profile/2fa',
            breadcrumbs: [{ name: 'Início', url: '/admin/dashboard' }, { name: 'Segurança da Conta', url: '#' }] 
        });
    }

    // Generate secret
    const secret = authenticator.generateSecret();
    const otpauth = authenticator.keyuri(user.email, 'Katari Admin', secret);
    const qrCodeImage = await QRCode.toDataURL(otpauth);

    // Save temporary secret to session
    (req.session as any).temp2FASecret = secret;

    res.render('pages/2fa/index', { 
        enabled: false, 
        qrCodeImage, 
        secret, 
        path: '/profile/2fa',
        breadcrumbs: [{ name: 'Início', url: '/admin/dashboard' }, { name: 'Segurança da Conta', url: '#' }] 
    });
};

export const enable2FA = async (req: Request, res: Response) => {
    const userId = (req.session as any).user.id;
    const { token } = req.body;
    const secret = (req.session as any).temp2FASecret;

    if (!secret || !token) {
        req.flash('error_msg', 'Sessão expirada. Tente novamente.');
        return res.redirect('/admin/profile/2fa');
    }

    const isValid = authenticator.verify({ token, secret });
    if (!isValid) {
        req.flash('error_msg', 'Código inválido. Tente novamente.');
        return res.redirect('/admin/profile/2fa');
    }

    await prisma.user.update({
        where: { id: userId },
        data: { twoFactorEnabled: true, twoFactorSecret: secret }
    });

    delete (req.session as any).temp2FASecret;
    req.flash('success_msg', 'Autenticação em 2 etapas habilitada com sucesso! Na próxima vez que tentar logar, esse código será exigido.');
    res.redirect('/admin/profile/2fa');
};

export const disable2FA = async (req: Request, res: Response) => {
    const userId = (req.session as any).user.id;
    const { token } = req.body;
    
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user || !user.twoFactorSecret) return res.redirect('/admin/profile/2fa');

    const isValid = authenticator.verify({ token, secret: user.twoFactorSecret });
    if (!isValid) {
        req.flash('error_msg', 'Código inválido. Verifique o app Autenticador.');
        return res.redirect('/admin/profile/2fa');
    }

    await prisma.user.update({
        where: { id: userId },
        data: { twoFactorEnabled: false, twoFactorSecret: null }
    });

    req.flash('success_msg', 'Autenticação em 2 etapas foi desabilitada. Sua conta agora está menos segura.');
    res.redirect('/admin/profile/2fa');
};
