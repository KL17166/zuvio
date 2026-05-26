import { Router } from 'express';
import authRoutes from './authRoutes';
import productRoutes from './productRoutes';
import apiRoutes from './apiRoutes';
// webhookRoutes are mounted directly in app.ts (before securityMiddleware)

const router = Router();

router.use('/auth', authRoutes);
router.use('/products', productRoutes);
// Backward compatibility: /motorcycles → same as /products?type=MOTO
router.use('/motorcycles', productRoutes);
router.use('/', apiRoutes);

export default router;
