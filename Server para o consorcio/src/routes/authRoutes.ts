import { Router } from 'express';
import { authenticate } from '../middlewares/authMiddleware';
import { upload } from '../middlewares/uploadMiddleware';
import { login, register, updateProfile, uploadDocument, getProfile, logout, changePassword } from '../controllers/api/authController';

const router = Router();

router.post('/register', register);
router.post('/login', login);
router.post('/logout', authenticate, logout);
router.get('/profile', authenticate, getProfile);
router.put('/profile', authenticate, updateProfile);
router.put('/password', authenticate, changePassword);
router.post('/upload', authenticate, upload.single('file'), uploadDocument);

export default router;
