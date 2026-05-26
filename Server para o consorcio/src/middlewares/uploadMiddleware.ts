import multer from 'multer';
import path from 'path';
import fs from 'fs';

// Ensure upload directory exists
const uploadDir = path.join(process.cwd(), 'public', 'uploads', 'documents');
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

// Allowed file types: images + PDF
const ALLOWED_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.pdf'];
const ALLOWED_MIME_TYPES = [
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'application/pdf'
];

// Dangerous extensions that should NEVER be accepted
const BLOCKED_EXTENSIONS = [
    '.exe', '.bat', '.cmd', '.com', '.msi', '.scr', '.pif',  // Windows executables
    '.sh', '.bash', '.csh',                                     // Shell scripts
    '.php', '.php3', '.php4', '.php5', '.phtml',               // PHP
    '.asp', '.aspx', '.jsp', '.jspx', '.cgi',                 // Server-side
    '.js', '.ts', '.py', '.rb', '.pl',                         // Script languages
    '.html', '.htm', '.svg', '.xml',                           // Could contain XSS
    '.dll', '.so', '.dylib',                                   // Libraries
    '.zip', '.tar', '.gz', '.rar', '.7z',                      // Archives
];

const storage = multer.diskStorage({
    destination: (req: any, file, cb) => {
        const userId = req.user?.userId || 'unknown';
        const userUploadDir = path.join(uploadDir, userId);
        
        if (!fs.existsSync(userUploadDir)) {
            fs.mkdirSync(userUploadDir, { recursive: true });
        }
        
        cb(null, userUploadDir);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        // Sanitize original name - remove anything except alphanumeric, dash, underscore, dot
        const sanitizedName = file.originalname.replace(/[^a-zA-Z0-9.\-_]/g, '_');
        const ext = path.extname(sanitizedName).toLowerCase();
        cb(null, file.fieldname + '-' + uniqueSuffix + ext);
    }
});

const fileFilter = (req: any, file: any, cb: any) => {
    const ext = path.extname(file.originalname).toLowerCase();

    // 1. Block dangerous extensions explicitly
    if (BLOCKED_EXTENSIONS.includes(ext)) {
        return cb(new Error(`Tipo de arquivo bloqueado: ${ext}. Apenas imagens (JPG, PNG, GIF, WebP) e PDF sao aceitos.`), false);
    }

    // 2. Check allowed extension
    if (!ALLOWED_EXTENSIONS.includes(ext)) {
        return cb(new Error(`Extensao nao permitida: ${ext}. Apenas imagens (JPG, PNG, GIF, WebP) e PDF sao aceitos.`), false);
    }

    // 3. Check MIME type
    if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
        return cb(new Error(`Tipo MIME nao permitido: ${file.mimetype}. O arquivo pode estar disfarçado.`), false);
    }

    // 4. Cross-validate extension vs MIME type
    const mimeExtMap: Record<string, string[]> = {
        'image/jpeg': ['.jpg', '.jpeg'],
        'image/png': ['.png'],
        'image/gif': ['.gif'],
        'image/webp': ['.webp'],
        'application/pdf': ['.pdf']
    };

    const validExtsForMime = mimeExtMap[file.mimetype];
    if (validExtsForMime && !validExtsForMime.includes(ext)) {
        return cb(new Error(`A extensao ${ext} nao corresponde ao tipo do arquivo (${file.mimetype}). Upload bloqueado por seguranca.`), false);
    }

    cb(null, true);
};

export const upload = multer({
    storage: storage,
    fileFilter: fileFilter,
    limits: {
        fileSize: 5 * 1024 * 1024, // 5MB limit
        files: 1 // Only 1 file per request
    }
});
