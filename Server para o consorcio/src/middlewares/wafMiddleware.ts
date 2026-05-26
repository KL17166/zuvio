import { Request, Response, NextFunction } from 'express';
import { logger } from '../config/logger';
import { isAuthenticatedAdmin } from '../security/adminAuth';

/**
 * Local Web Application Firewall (WAF) Middleware
 * Inspects request body, query, and params for common attack patterns.
 * Updated Feb 2026 — covers OWASP Top 10 + recent CVE vectors.
 * Admins autenticados com X-Admin-Token válido são isentos.
 */
export const wafMiddleware = (req: Request, res: Response, next: NextFunction) => {
    // Admin bypass: admins autenticados com token válido pulam o WAF
    if (isAuthenticatedAdmin(req)) {
        return next();
    }

    // ========================================
    // 1. XSS PATTERNS
    // ========================================
    const xssPatterns = [
        /<script\b[^>]*>([\s\S]*?)<\/script>/gmi,
        /javascript\s*:/i,
        /on(load|error|click|mouse|focus|blur|submit|change|input|key)\s*=/i,
        /\%3Cscript/i,
        /\beval\s*\(/i,
        /\bexpression\s*\(/i,
        /vbscript\s*:/i,
        /data\s*:\s*text\/html/i,
        /<\s*(iframe|object|embed|applet|form|input|img\s+[^>]*\bonerror)\b/i,
        /\bString\s*\.\s*fromCharCode\s*\(/i,
        /\bdocument\s*\.\s*(cookie|domain|write|location)/i,
        /\bwindow\s*\.\s*(location|open|eval)/i,
    ];

    // ========================================
    // 2. SQL INJECTION PATTERNS (Prisma protects, but block obvious scanners)
    // ========================================
    const sqliPatterns = [
        /union\s+(all\s+)?select/i,
        /drop\s+(table|database|index)/i,
        /select\s+\*\s+from/i,
        /insert\s+into\s+.*values/i,
        /update\s+\w+\s+set\s+/i,
        /delete\s+from\s+\w+/i,
        /;\s*(drop|alter|create|truncate|exec|execute|xp_)\s/i,
        /\bwaitfor\s+delay\b/i,           // Time-based blind SQLi
        /\bbenchmark\s*\(\s*\d+/i,         // MySQL benchmark injection
        /\bsleep\s*\(\s*\d+\s*\)/i,        // Sleep-based blind SQLi
        /\bload_file\s*\(/i,               // File read via SQL
        /\binto\s+(out|dump)file\s/i,       // File write via SQL
    ];

    // ========================================
    // 3. PATH TRAVERSAL PATTERNS
    // ========================================
    const pathTraversalPatterns = [
        /\.\.\//,
        /\.\.\\/,
        /%2e%2e(%2f|%5c)/i,
        /%252e%252e/i,                     // Double-encoded
        /\.\.%c0%af/i,                     // Overlong UTF-8 encoding
        /\.\.%c1%9c/i,                     // Alternative overlong encoding
        /\.\.\xc0\xaf/,                    // Raw overlong bytes
    ];

    // ========================================
    // 4. COMMAND INJECTION PATTERNS
    // ========================================
    const commandInjectionPatterns = [
        /;\s*(ls|cat|rm|wget|curl|bash|sh|nc|nmap|python|perl|ruby|php|powershell)\b/i,
        /\|\s*(ls|cat|rm|wget|curl|bash|sh|nc)\b/i,
        /`[^`]*`/,                          // Backtick execution
        /\$\([^)]+\)/,                      // $() subshell
        /\b(&&|\|\|)\s*(rm|cat|wget|curl)\b/i,
    ];

    // ========================================
    // 5. SSRF PATTERNS (Server-Side Request Forgery)
    // ========================================
    const ssrfPatterns = [
        /https?:\/\/(127\.|10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|0\.0\.0\.0|localhost)/i,
        /https?:\/\/\[::1?\]/i,            // IPv6 loopback
        /https?:\/\/169\.254\.\d+\.\d+/i,  // AWS metadata
        /https?:\/\/metadata\.google/i,     // GCP metadata
        /file:\/\//i,                       // File protocol
        /gopher:\/\//i,                     // Gopher protocol
        /dict:\/\//i,                       // Dict protocol
    ];

    // ========================================
    // 6. SSTI PATTERNS (Server-Side Template Injection)
    // ========================================
    const sstiPatterns = [
        /\{\{.*\}\}/,                       // Mustache/Handlebars
        /\$\{.*\}/,                         // Template literals
        /<%.*%>/,                           // EJS/ERB
        /#\{.*\}/,                          // Ruby interpolation
        /\{%.*%\}/,                         // Jinja
    ];

    // ========================================
    // 7. LOG INJECTION PATTERNS
    // ========================================
    const logInjectionPatterns = [
        /\r\n|\n|\r/,                       // CRLF injection (in URL/header values)
        /%0[ad]/i,                          // URL encoded newlines
        /%0D%0A/i,                          // Encoded CRLF
    ];

    // Dangerous keys that indicate prototype pollution
    const DANGEROUS_KEYS = ['__proto__', 'constructor', 'prototype'];

    // ========================================
    // CHECK FUNCTIONS
    // ========================================
    const checkString = (str: string, location: string): string | null => {
        if (!str || str.length > 10000) return null; // Skip very long strings (binary data)

        // XSS
        for (const p of xssPatterns) {
            p.lastIndex = 0; // Reset global regex
            if (p.test(str)) {
                logger.warn(`[SEC-BLOCK] EVENT=WAF_XSS IP=${req.ip} LOCATION=${location} PAYLOAD=${str.substring(0, 100)}`);
                return 'XSS';
            }
        }

        // SQL Injection
        for (const p of sqliPatterns) {
            if (p.test(str)) {
                logger.warn(`[SEC-BLOCK] EVENT=WAF_SQLI IP=${req.ip} LOCATION=${location} PAYLOAD=${str.substring(0, 100)}`);
                return 'SQL_INJECTION';
            }
        }

        // Path Traversal
        for (const p of pathTraversalPatterns) {
            if (p.test(str)) {
                logger.warn(`[SEC-BLOCK] EVENT=WAF_PATH_TRAVERSAL IP=${req.ip} LOCATION=${location} PAYLOAD=${str.substring(0, 100)}`);
                return 'PATH_TRAVERSAL';
            }
        }

        // Command Injection
        for (const p of commandInjectionPatterns) {
            if (p.test(str)) {
                logger.warn(`[SEC-BLOCK] EVENT=WAF_COMMAND_INJECTION IP=${req.ip} LOCATION=${location} PAYLOAD=${str.substring(0, 100)}`);
                return 'COMMAND_INJECTION';
            }
        }

        // SSRF (only check URL-like fields)
        if (location.includes('url') || location.includes('link') || location.includes('redirect') || location.includes('callback')) {
            for (const p of ssrfPatterns) {
                if (p.test(str)) {
                    logger.warn(`[SEC-BLOCK] EVENT=WAF_SSRF IP=${req.ip} LOCATION=${location} PAYLOAD=${str.substring(0, 100)}`);
                    return 'SSRF';
                }
            }
        }

        // SSTI (check template-looking strings — skip if just normal data)
        if (/[{<%#$]/.test(str)) {
            for (const p of sstiPatterns) {
                if (p.test(str)) {
                    // Avoid false positives on JSON-like data
                    try { JSON.parse(str); return null; } catch {}
                    logger.warn(`[SEC-BLOCK] EVENT=WAF_SSTI IP=${req.ip} LOCATION=${location} PAYLOAD=${str.substring(0, 100)}`);
                    return 'SSTI';
                }
            }
        }

        // Log Injection (only check query/params, not body — body may have legitimate newlines)
        if (location.startsWith('query') || location.startsWith('params')) {
            for (const p of logInjectionPatterns) {
                if (p.test(str)) {
                    logger.warn(`[SEC-BLOCK] EVENT=WAF_LOG_INJECTION IP=${req.ip} LOCATION=${location}`);
                    return 'LOG_INJECTION';
                }
            }
        }

        return null;
    };

    const inspectObject = (obj: any, location: string, depth = 0): string | null => {
        if (!obj || depth > 5) return null; // Max recursion depth

        for (const key in obj) {
            // Prototype Pollution
            if (DANGEROUS_KEYS.includes(key)) {
                logger.warn(`[SEC-BLOCK] EVENT=WAF_PROTOTYPE_POLLUTION IP=${req.ip} LOCATION=${location} KEY=${key}`);
                return 'PROTOTYPE_POLLUTION';
            }

            const value = obj[key];
            if (typeof value === 'string') {
                const threat = checkString(value, `${location}.${key}`);
                if (threat) return threat;
            } else if (Array.isArray(value)) {
                for (let i = 0; i < Math.min(value.length, 100); i++) {
                    if (typeof value[i] === 'string') {
                        const threat = checkString(value[i], `${location}.${key}[${i}]`);
                        if (threat) return threat;
                    } else if (typeof value[i] === 'object') {
                        const threat = inspectObject(value[i], `${location}.${key}[${i}]`, depth + 1);
                        if (threat) return threat;
                    }
                }
            } else if (typeof value === 'object') {
                const threat = inspectObject(value, `${location}.${key}`, depth + 1);
                if (threat) return threat;
            }
        }
        return null;
    };

    // ========================================
    // RUN CHECKS
    // ========================================
    const blockedMsg = {
        error: 'Requisicao bloqueada',
        message: 'Sua requisicao foi bloqueada por conter padroes suspeitos. Se voce acredita que isso e um erro, entre em contato com o suporte.'
    };

    const bodyThreat = inspectObject(req.body, 'body');
    if (bodyThreat) return res.status(403).json({ ...blockedMsg, type: bodyThreat });

    const queryThreat = inspectObject(req.query, 'query');
    if (queryThreat) return res.status(403).json({ ...blockedMsg, type: queryThreat });

    const paramsThreat = inspectObject(req.params, 'params');
    if (paramsThreat) return res.status(403).json({ ...blockedMsg, type: paramsThreat });

    // Check URL path itself for path traversal and command injection
    const urlThreat = checkString(decodeURIComponent(req.path), 'url');
    if (urlThreat) return res.status(403).json({ ...blockedMsg, type: urlThreat });

    next();
};
