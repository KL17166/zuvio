import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import session from 'express-session';
const { RedisStore } = require('connect-redis');
import flash from 'connect-flash';
import path from 'path';
import ejs from 'ejs';
import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import compression from 'compression';
import hpp from 'hpp'; // HTTP Parameter Pollution protection
import routes from './routes';
import adminRoutes from './routes/adminRoutes';
import { logger } from './config/logger';
import { errorHandler } from './middlewares/errorHandler';
import { securityMiddleware, honeypotHandler, HONEYPOT_ROUTES } from './middlewares/securityMiddleware';
import { env } from './config/env';
import { prisma } from './config/database';
import { redisClient } from './config/redis';

export { redisClient };

const app = express();

// ========================================
// SESSION STORE (Redis-backed, in-memory fallback)
// ========================================
const sessionStore = redisClient
    ? new RedisStore({ client: redisClient, prefix: 'consorcio:sess:', ttl: 86400 })
    : undefined;

// ========================================
// SECURITY MIDDLEWARES
// ========================================

// Helmet for security headers with strict CSP
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'", "'unsafe-inline'", "https://cdn.jsdelivr.net", "https://code.jquery.com", "https://cdnjs.cloudflare.com", "https://cdn.datatables.net", "https://www.gstatic.com"],
            scriptSrcAttr: ["'unsafe-inline'"], // Allow inline event handlers (onclick, onsubmit)
            styleSrc: ["'self'", "'unsafe-inline'", "https://cdn.jsdelivr.net", "https://cdn.datatables.net", "https://fonts.googleapis.com"],
            fontSrc: ["'self'", "https://fonts.gstatic.com", "data:", "https://fonts.googleapis.com", "https://cdn.jsdelivr.net"],
            imgSrc: ["'self'", "data:", "https:", "https://images.unsplash.com"],
            connectSrc: ["'self'", "https://fonts.googleapis.com", "https://fonts.gstatic.com", "https://www.gstatic.com", "https://cdn.jsdelivr.net", "https://cdn.datatables.net"],
            frameSrc: ["'none'"],
            objectSrc: ["'none'"],
            upgradeInsecureRequests: [],
        },
    },
    crossOriginEmbedderPolicy: false, // Sometimes needed for CDNs
    hsts: {
        maxAge: 31536000,
        includeSubDomains: true,
        preload: true
    },
    hidePoweredBy: true, // Hide X-Powered-By
    noSniff: true,
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    xFrameOptions: { action: 'deny' },   // Prevent clickjacking
}));

// Permissions-Policy: restrict browser features this app never uses
app.use((req, res, next) => {
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=()');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    next();
});

// HARDENING: Disable Express Signature
app.disable('x-powered-by');

// HARDENING: Block access to hidden files (.env, .git, etc.)
app.use((req, res, next) => {
    if (req.path.includes('/.') || req.path.includes('\\.')) {
        logger.warn(`Blocked attempt to access hidden file: ${req.path} from ${req.ip}`);
        return res.status(403).send('Forbidden');
    }
    next();
});

// HTTP Parameter Pollution Protection
app.use(hpp());

// Gzip/Brotli Compression — reduces response sizes 60-80%
app.use(compression({
    level: 6, // Good balance between speed and compression ratio
    threshold: 1024, // Only compress responses > 1KB
    filter: (req, res) => {
        if (req.headers['x-no-compression']) return false;
        return compression.filter(req, res);
    }
}));

// Local WAF Middleware
import { wafMiddleware } from './middlewares/wafMiddleware';
app.use(wafMiddleware);

// Anti-Scraping / Anti-Dump Protection (HTTrack, wget, site copiers)
import { antiScrapingMiddleware } from './middlewares/antiScrapingMiddleware';
app.use(antiScrapingMiddleware);

// Trust proxy (required for rate-limit behind load balancers/tunnels)
app.set('trust proxy', 1);

// CORS Configuration
const allowedOrigins = (env.ALLOWED_ORIGINS?.split(',') || [
    'http://localhost:3000',
    'http://localhost:8080',
    'http://127.0.0.1:3000',
    'http://127.0.0.1:8080',
    'http://10.0.2.2:3000', // Android emulator
]).map(origin => origin.trim());

// Matches any localhost / 127.0.0.1 origin regardless of port (Flutter web uses dynamic ports)
const localhostOriginRe = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

app.use(cors({
    origin: (origin, callback) => {
        // Strict blocking of no-origin requests in production
        if (!origin) {
            if (env.NODE_ENV === 'development') {
                return callback(null, true);
            } else {
                return callback(new Error('Not allowed by CORS'));
            }
        }

        if (origin === 'null') {
            if (env.NODE_ENV === 'development') {
                return callback(null, true);
            } else {
                return callback(new Error('Not allowed by CORS'));
            }
        }

        // Allow Cloudflare Tunnel URLs (dynamic, change each session)
        if (origin.endsWith('.trycloudflare.com')) {
            return callback(null, true);
        }

        // Allow any localhost / 127.0.0.1 origin in development (Flutter web uses dynamic ports)
        if (env.NODE_ENV === 'development' && localhostOriginRe.test(origin)) {
            return callback(null, true);
        }

        if (allowedOrigins.includes(origin)) {
            callback(null, true);
        } else {
            logger.warn(`CORS blocked request from: ${origin}`);
            callback(new Error('Not allowed by CORS'));
        }
    },
    credentials: true,
}));

// Rate Limiting - Geral (IP + Token se possível - aqui simplificado por IP)
const generalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutos
    max: 300, // 300 requests por IP em 15 min (Flutter faz várias chamadas legítimas)
    message: { error: 'Muitas requisições. Tente novamente em 15 minutos.' },
    standardHeaders: true,
    legacyHeaders: false,
});

// Rate Limiting - Auth Admin (Muito Estrito)
const adminAuthLimiter = rateLimit({
    windowMs: 10 * 60 * 1000, // 10 minutos
    max: 5, // Apenas 5 tentativas
    message: { error: 'Muitas tentativas de login admin. Bloqueado por 10 minutos.' },
    standardHeaders: true,
    legacyHeaders: false,
    skipSuccessfulRequests: true, // Não contar logins bem sucedidos para não bloquear admin legítimo
});

// Rate Limiting - Auth API
const apiAuthLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10,
    message: { error: 'Muitas tentativas de login. Tente novamente em 15 minutos.' },
    standardHeaders: true,
    legacyHeaders: false,
});

// Rate Limiting - Register (Prevent account spam)
const apiRegisterLimiter = rateLimit({
    windowMs: 60 * 60 * 1000,  // 1 hour
    max: 5,                     // 5 registrations per hour per IP
    message: { error: 'Muitos registros. Tente novamente em 1 hora.' },
    standardHeaders: true,
    legacyHeaders: false,
});

// Rate Limiting - Admin Panel (Geral)
const adminGeneralLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutos
    max: 300, // Aumentado para 300 para não bloquear admin legíto trabalhando
    message: 'Muitas requisições ao painel admin. Tente novamente em 15 minutos.',
    standardHeaders: true,
    legacyHeaders: false,
});

// Helper: extract userId from JWT for per-user rate limiting without full auth middleware
const userIdFromBearer = (req: any): string => {
    const auth = req.headers.authorization?.split(' ')[1];
    if (auth) {
        try {
            const payload = JSON.parse(Buffer.from(auth.split('.')[1], 'base64url').toString());
            if (payload?.userId) return `u:${payload.userId}`;
        } catch { /* fall through to IP */ }
    }
    return ipKeyGenerator(req);
};

// Rate Limiting - Payment generation (PIX / Boleto): 3 per 5 minutes per user
const paymentGenerationLimiter = rateLimit({
    windowMs: 5 * 60 * 1000,
    max: 3,
    keyGenerator: userIdFromBearer,
    message: { error: 'Muitas solicitações de pagamento. Aguarde 5 minutos.' },
    standardHeaders: true,
    legacyHeaders: false,
});

// Rate Limiting - Bid creation: 5 per 10 minutes per user
const bidLimiter = rateLimit({
    windowMs: 10 * 60 * 1000,
    max: 5,
    keyGenerator: userIdFromBearer,
    message: { error: 'Muitos lances registrados. Aguarde 10 minutos.' },
    standardHeaders: true,
    legacyHeaders: false,
});

// Rate Limiting - Subscription READ (listing): 120 per 15 min per user — lenient for normal usage
const subscriptionReadLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 120,
    keyGenerator: userIdFromBearer,
    message: { error: 'Muitas consultas de contratos. Aguarde alguns minutos.' },
    standardHeaders: true,
    legacyHeaders: false,
});

// Rate Limiting - Subscription CREATE: 3 per hour per user (prevents spam)
const subscriptionCreateLimiter = rateLimit({
    windowMs: 60 * 60 * 1000,
    max: 3,
    keyGenerator: userIdFromBearer,
    message: { error: 'Muitos contratos criados. Aguarde 1 hora.' },
    standardHeaders: true,
    legacyHeaders: false,
});

// Rate Limiting - KYC submission: 5 per hour per user
const kycSubmitLimiter = rateLimit({
    windowMs: 60 * 60 * 1000,
    max: 5,
    keyGenerator: userIdFromBearer,
    message: { error: 'Muitas submissões de KYC. Aguarde 1 hora.' },
    standardHeaders: true,
    legacyHeaders: false,
});

app.use('/api', generalLimiter);
app.use('/api/auth/login', apiAuthLimiter);
app.use('/api/auth/register', apiRegisterLimiter);
app.use('/api/payments', paymentGenerationLimiter);
app.use('/api/bids', bidLimiter);
// Method-aware Rate Limiting for Subscriptions (Avoids path-to-regexp wildcard errors)
app.use('/api/subscriptions', (req, res, next) => {
    if (req.method === 'POST' && (req.path === '/' || req.path === '')) {
        return subscriptionCreateLimiter(req, res, next);
    }
    return subscriptionReadLimiter(req, res, next);
});
app.use('/api/kyc/submit', kycSubmitLimiter);
app.use('/admin', adminGeneralLimiter); // Rate limit geral no admin
app.use('/admin/login', adminAuthLimiter); // Rate limit estrito no login admin

// Session-based Rate Limiter — catches proxy-rotating scrapers
// (same session across different IPs still gets limited)
const sessionLimiter = rateLimit({
    windowMs: 1 * 60 * 1000, // 1 minute
    max: 120,                 // 120 requests per minute per session
    keyGenerator: (req) => (req.session as any)?.id || req.socket.remoteAddress || 'anon',
    message: { error: 'Muitas requisições por sessão. Aguarde um momento.' },
    standardHeaders: true,
    legacyHeaders: false,
});
app.use(sessionLimiter);

app.use(express.json({ 
    limit: '1mb',
    reviver: (key, value) => {
        // ZER0-DAY PROTECTION: Neutralize prototype pollution during JSON parsing
        if (key === '__proto__' || key === 'constructor' || key === 'prototype') {
            return undefined;
        }
        return value;
    },
    verify: (req: any, res, buf) => {
        req.rawBody = buf;
    }
})); // Limit body size to prevent DoS
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// JS Challenge for admin panel pages (blocks bots with fake User-Agents)
import { jsChallengeMiddleware } from './middlewares/jsChallengeMiddleware';
app.use('/admin', jsChallengeMiddleware);

// HMAC Request Signature Validation (anti-replay / anti-tampering)
import { requestSignatureMiddleware } from './middlewares/requestSignatureMiddleware';
app.use(requestSignatureMiddleware);

// Payload Obfuscation Middleware (Encryption/Decryption)
import { payloadObfuscationMiddleware } from './middlewares/payloadObfuscationMiddleware';
app.use(payloadObfuscationMiddleware);

// View Engine Setup
const viewsPath = path.join(__dirname, 'views');
app.set('views', viewsPath);
app.set('view engine', 'ejs');

// Configure EJS to support includes in v4.x
app.engine('ejs', (filePath: string, options: any, callback: any) => {
    ejs.renderFile(filePath, options, {
        views: [viewsPath, path.join(viewsPath, 'pages')],
        async: false
    }, callback);
});

// Session & Flash
app.use(session({
    store: sessionStore, // Redis store (undefined = in-memory fallback)
    secret: env.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    name: env.NODE_ENV === 'production' ? '__Host-sessionId' : 'sessionId', // ZER0-DAY: Secure cookie prefix (only works over HTTPS / strict domain)
    cookie: {
        secure: env.NODE_ENV === 'production', // Force HTTPS in production
        httpOnly: true, // Prevent JS access
        maxAge: 24 * 60 * 60 * 1000, // 24 horas
        sameSite: 'strict', // ZER0-DAY: CSRF estrito para blindagem de Cross-Site
        path: '/'
    }
}));
app.use(flash());

// Make flash messages and user available to all views
app.use((req, res, next) => {
    res.locals.success_msg = req.flash('success_msg');
    res.locals.error_msg = req.flash('error_msg');
    res.locals.error = req.flash('error');
    // Mock user for now or from session later
    res.locals.user = (req as any).session?.user || null;
    next();
});

// Request Logger
app.use((req, res, next) => {
    logger.info(`${req.method} ${req.url}`);
    next();
});

// ========================================
// HONEYPOT ROUTES (must be before real routes)
// ========================================
// Register honeypot handlers using shared HONEYPOT_ROUTES (only /api paths need explicit handlers)
const apiHoneypots = HONEYPOT_ROUTES.filter(p => p.startsWith('/api'));
apiHoneypots.forEach(path => {
    app.all(path, honeypotHandler);
});

// Webhook routes BEFORE security middleware (payment providers must not be blocked)
import webhookRoutes from './routes/webhookRoutes';
app.use('/api/webhooks', webhookRoutes);

// Security Middleware (applies to all /api routes EXCEPT webhooks)
app.use('/api', securityMiddleware);

// Security Middleware on admin routes too (IP/threat protection)
app.use('/admin', securityMiddleware);

// Routes
app.use('/api', routes);
app.use('/admin', adminRoutes);

// Explicit redirect for /admin to /admin/login to be safe
app.get('/admin', (req, res) => res.redirect('/admin/login'));

// Serve static files (Public assets + Flutter Web App)
app.use(express.static(path.join(__dirname, '../public')));
app.use('/public', express.static(path.join(__dirname, '../public')));

// Health Check — detailed
app.get('/health', async (req, res) => {
    const memUsage = process.memoryUsage();
    let dbStatus = 'ok';
    try {
        await prisma.$queryRawUnsafe('SELECT 1');
    } catch {
        dbStatus = 'error';
    }
    res.status(dbStatus === 'ok' ? 200 : 503).json({
        status: dbStatus === 'ok' ? 'OK' : 'DEGRADED',
        uptime: Math.floor(process.uptime()) + 's',
        memory: {
            rss: Math.round(memUsage.rss / 1024 / 1024) + 'MB',
            heap: Math.round(memUsage.heapUsed / 1024 / 1024) + 'MB',
            heapTotal: Math.round(memUsage.heapTotal / 1024 / 1024) + 'MB',
        },
        database: dbStatus,
        timestamp: new Date().toISOString(),
    });
});

// Global Error Handler
app.use(errorHandler);

export default app;
