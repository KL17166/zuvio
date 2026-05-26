import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { logger } from '../config/logger';

// =============================================
// JS CHALLENGE MIDDLEWARE — Anti-Bot Protection
// =============================================
// Forces first-time visitors to solve a lightweight
// JavaScript crypto puzzle. Bots/scrapers (wget, HTTrack,
// curl with fake UA) cannot execute JS, so they fail.
//
// Flow:
// 1. New IP arrives without challenge cookie → serve puzzle page
// 2. Browser auto-solves the puzzle (< 200ms) → POST answer
// 3. Server validates → sets signed cookie "jsc_passed"
// 4. All subsequent requests with valid cookie pass through
// =============================================

const CHALLENGE_SECRET = crypto.randomBytes(32).toString('hex');
const COOKIE_NAME = 'jsc_v';
const COOKIE_MAX_AGE = 24 * 60 * 60 * 1000; // 24 hours

// Paths that should NEVER be challenged (APIs, webhooks, static assets)
const BYPASS_PREFIXES = [
    '/api/',           // Flutter app API calls (authenticated via JWT)
    '/webhooks/',      // Payment gateway webhooks
    '/uploads/',       // Static uploaded files
    '/assets/',        // Static assets
    '/favicon',
    '/health',
];

const BYPASS_EXTENSIONS = ['.js', '.css', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico', '.woff', '.woff2', '.ttf', '.map'];

function getClientIP(req: Request): string {
    const fwd = req.headers['x-forwarded-for'];
    if (fwd) return (typeof fwd === 'string' ? fwd : fwd[0]).split(',')[0].trim();
    return req.socket.remoteAddress || req.ip || 'unknown';
}

/** Generate an HMAC-signed cookie value */
function signValue(ip: string, timestamp: number): string {
    const payload = `${ip}|${timestamp}`;
    const hmac = crypto.createHmac('sha256', CHALLENGE_SECRET).update(payload).digest('hex');
    return `${timestamp}.${hmac}`;
}

/** Verify the cookie is valid and not expired */
function verifyValue(ip: string, cookieValue: string): boolean {
    if (!cookieValue) return false;
    const parts = cookieValue.split('.');
    if (parts.length !== 2) return false;

    const timestamp = parseInt(parts[0], 10);
    if (isNaN(timestamp)) return false;
    if (Date.now() - timestamp > COOKIE_MAX_AGE) return false;

    const expected = signValue(ip, timestamp);
    return cookieValue === expected;
}

/** The JS puzzle page served to unverified visitors */
function challengePage(nonce: string): string {
    return `<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<title>Verificação de Segurança</title>
<style>
  body{margin:0;display:flex;align-items:center;justify-content:center;min-height:100vh;
       background:#0d0d0d;font-family:system-ui;color:#ccc}
  .box{text-align:center;padding:2rem}
  .spinner{width:40px;height:40px;border:3px solid #333;border-top-color:#7c3aed;
           border-radius:50%;margin:1rem auto;animation:spin .8s linear infinite}
  @keyframes spin{to{transform:rotate(360deg)}}
</style>
</head><body>
<div class="box">
  <div class="spinner"></div>
  <p>Verificando navegador...</p>
</div>
<script>
(function(){
  // Simple crypto puzzle: find a number where SHA-like hash starts with "00"
  var nonce="${nonce}";
  var answer=0;
  for(var i=0;i<1e6;i++){
    // Simple hash: XOR cascade of nonce + number
    var s=nonce+i;
    var h=0;
    for(var j=0;j<s.length;j++) h=((h<<5)-h+s.charCodeAt(j))|0;
    if((h&0xFFFF)===0){answer=i;break;}
  }
  // Submit answer via cookie and redirect
  document.cookie="${COOKIE_NAME}_answer="+nonce+"."+answer+";path=/;max-age=30";
  setTimeout(function(){location.reload()},300);
})();
</script>
</body></html>`;
}

/** Parse a cookie value from the raw Cookie header */
function parseCookie(req: Request, name: string): string | undefined {
    const raw = req.headers.cookie || '';
    const match = raw.split(';').map(s => s.trim()).find(s => s.startsWith(`${name}=`));
    return match ? decodeURIComponent(match.split('=').slice(1).join('=')) : undefined;
}

export const jsChallengeMiddleware = (req: Request, res: Response, next: NextFunction) => {
    const path = req.path.toLowerCase();

    // Skip challenge for API routes, webhooks, static assets
    if (BYPASS_PREFIXES.some(p => path.startsWith(p))) return next();
    if (BYPASS_EXTENSIONS.some(ext => path.endsWith(ext))) return next();

    // Skip non-GET requests (forms, AJAX)
    if (req.method !== 'GET') return next();

    const ip = getClientIP(req);

    // Check if already passed challenge
    const passedCookie = parseCookie(req, COOKIE_NAME);
    if (passedCookie && verifyValue(ip, passedCookie)) {
        return next();
    }

    // Check if the browser is submitting a challenge answer
    const answerCookie = parseCookie(req, `${COOKIE_NAME}_answer`);
    if (answerCookie) {
        const [nonce, answerStr] = answerCookie.split('.');
        const answer = parseInt(answerStr, 10);

        if (nonce && !isNaN(answer)) {
            // Verify the answer
            const s = nonce + answer;
            let h = 0;
            for (let j = 0; j < s.length; j++) h = ((h << 5) - h + s.charCodeAt(j)) | 0;

            if ((h & 0xFFFF) === 0) {
                // Correct! Set the signed pass-through cookie
                const signed = signValue(ip, Date.now());
                res.cookie(COOKIE_NAME, signed, {
                    maxAge: COOKIE_MAX_AGE,
                    httpOnly: true,
                    secure: true,
                    sameSite: 'lax',
                });
                // Clear the answer cookie
                res.clearCookie(`${COOKIE_NAME}_answer`);
                logger.info(`✅ JS challenge passed: IP ${ip}`);
                return next();
            }
        }
    }

    // Serve the challenge page
    const nonce = crypto.randomBytes(8).toString('hex');
    logger.info(`🧩 JS challenge served to IP ${ip} — path: ${path}`);

    res.status(202)
       .set('Cache-Control', 'no-store')
       .send(challengePage(nonce));
};
