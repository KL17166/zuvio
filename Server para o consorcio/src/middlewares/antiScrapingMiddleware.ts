import { Request, Response, NextFunction } from 'express';
import { logger } from '../config/logger';

// =============================================
// ANTI-SCRAPING / ANTI-DUMP MIDDLEWARE
// Protects against HTTrack, wget, curl mass-download,
// offline browsers, and automated site copiers.
// =============================================

// ── Blocked User-Agent keywords ────────────────
// Covers every major site-ripper, offline browser,
// and mass-download tool known as of 2026.
const SCRAPER_UA_KEYWORDS = [
    // Site copiers / mirrors
    'httrack', 'website copier', 'webcopier', 'webcopy',
    'teleport', 'teleport pro', 'offline explorer',
    'webzip', 'webripper', 'sitesucker', 'pavuk',
    'blackwidow', 'widowmaker', 'websnatcher',
    'surfoffline', 'siphon', 'getright', 'flashget',
    'go-ahead-got-it', 'grab', 'miner', 'crescent',
    'copier', 'stripper', 'sucker', 'webwhacker',
    'webstripper', 'sitesnagger', 'collector',
    'webbandit', 'webfetch',
    // Download managers / mass-fetchers
    'wget', 'aria2', 'axel', 'linkwalker',
    'indy library', 'libwww-perl', 'lwp-trivial',
    // Generic bots / crawlers that can be abused
    'python-urllib', 'python-requests', 'python-httpx',
    'scrapy', 'go-http-client', 'java/', 'jakarta',
    'node-fetch', 'node-superagent', 'axios/',
    'httpie', 'mechanize', 'phantom', 'headless',
    'curl/', 'aiohttp', 'okhttp',
    // AI / LLM crawlers
    'gptbot', 'chatgpt', 'claudebot', 'ccbot', 'bytespider',
    'petalbot', 'barkrowler', 'amazonbot', 'anthropic',
];

// ── Suspicious request headers ─────────────────
// HTTrack and many scrapers set telltale headers.
const SCRAPER_HEADER_SIGNATURES = [
    { header: 'x-httrack', value: null },       // HTTrack fingerprint
    { header: 'x-offline-browse', value: null },
];

// ── In-memory sliding window per IP ────────────
// Tracks request timestamps to detect burst crawling.
interface RequestWindow {
    timestamps: number[];
    distinctPaths: Set<string>;
    warned: boolean;
    blocked: boolean;
}

const ipWindows: Map<string, RequestWindow> = new Map();

// Config
const WINDOW_MS       = 15_000;   // 15-second window
const MAX_REQUESTS    = 40;       // Max requests per window before flag
const MAX_DISTINCT    = 25;       // Max distinct paths per window (crawl detection)
const BLOCK_DURATION  = 30 * 60_000; // 30 min soft-block after detection

// Cleanup stale entries every 5 min
setInterval(() => {
    const now = Date.now();
    for (const [ip, w] of ipWindows.entries()) {
        if (w.timestamps.length === 0 || now - w.timestamps[w.timestamps.length - 1] > BLOCK_DURATION) {
            ipWindows.delete(ip);
        }
    }
}, 5 * 60_000);

// ── Helper: get client IP ──────────────────────
function clientIP(req: Request): string {
    const fwd = req.headers['x-forwarded-for'];
    if (fwd) return (typeof fwd === 'string' ? fwd : fwd[0]).split(',')[0].trim();
    return req.socket.remoteAddress || req.ip || 'unknown';
}

// ── The Middleware ──────────────────────────────
export const antiScrapingMiddleware = (req: Request, res: Response, next: NextFunction) => {
    const ip = clientIP(req);
    const ua = (req.headers['user-agent'] || '').toLowerCase();

    // ─── 1. User-Agent blacklist ───────────────
    const matchedUA = SCRAPER_UA_KEYWORDS.find(kw => ua.includes(kw));
    if (matchedUA) {
        logger.warn(`🕷️  SCRAPER BLOCKED (UA): "${matchedUA}" | IP: ${ip} | Path: ${req.path}`);
        return res.status(403).json({
            error: 'Acesso negado',
            message: 'Ferramentas automatizadas de download não são permitidas.'
        });
    }

    // ─── 2. No User-Agent at all ───────────────
    // Real browsers always send one. Most dump tools don't.
    if (!req.headers['user-agent']) {
        logger.warn(`🕷️  SCRAPER BLOCKED (No UA) | IP: ${ip} | Path: ${req.path}`);
        return res.status(403).json({
            error: 'Acesso negado',
            message: 'User-Agent obrigatório.'
        });
    }

    // ─── 3. Suspicious header fingerprints ─────
    for (const sig of SCRAPER_HEADER_SIGNATURES) {
        if (req.headers[sig.header] !== undefined) {
            logger.warn(`🕷️  SCRAPER BLOCKED (Header): ${sig.header} | IP: ${ip}`);
            return res.status(403).json({
                error: 'Acesso negado',
                message: 'Ferramentas automatizadas de download não são permitidas.'
            });
        }
    }

    // ─── 4. Crawl-speed detection ──────────────
    // Tracks distinct pages per IP in a sliding window.
    const now = Date.now();
    let window = ipWindows.get(ip);

    if (!window) {
        window = { timestamps: [], distinctPaths: new Set(), warned: false, blocked: false };
        ipWindows.set(ip, window);
    }

    // If IP is already soft-blocked, reject immediately
    if (window.blocked) {
        const lastTs = window.timestamps[window.timestamps.length - 1] || 0;
        if (now - lastTs < BLOCK_DURATION) {
            return res.status(429).json({
                error: 'Muitas requisições',
                message: 'Muitas requisições detectadas. Aguarde alguns minutos antes de tentar novamente.'
            });
        }
        // Block has expired, reset
        window.blocked = false;
        window.warned = false;
        window.timestamps = [];
        window.distinctPaths.clear();
    }

    // Slide window: remove timestamps older than WINDOW_MS
    window.timestamps = window.timestamps.filter(t => now - t < WINDOW_MS);
    
    // Add the current request
    window.timestamps.push(now);
    window.distinctPaths.add(req.path);

    // Check thresholds
    if (window.timestamps.length > MAX_REQUESTS || window.distinctPaths.size > MAX_DISTINCT) {
        if (!window.blocked) {
            logger.warn(`🕷️  CRAWL DETECTED & BLOCKED: IP ${ip} | ${window.timestamps.length} reqs | ${window.distinctPaths.size} distinct paths in ${WINDOW_MS / 1000}s`);
            window.blocked = true;
        }
        return res.status(429).json({
            error: 'Muitas requisições',
            message: 'Atividade de scraping detectada. Seu IP foi temporariamente bloqueado.'
        });
    }

    // ─── 5. Anti-mirror response headers ───────
    // Tell caches and offline tools NOT to cache or archive.
    res.setHeader('X-Robots-Tag', 'noindex, nofollow, noarchive, nosnippet, noimageindex');
    res.setHeader('Cache-Control', 'private, no-store, no-cache, must-revalidate, max-age=0');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');

    next();
};
