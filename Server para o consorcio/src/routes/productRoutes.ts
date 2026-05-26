import { Router } from 'express';
import { getProducts, getProductById } from '../controllers/api/productController';

const router = Router();

// GET /products — all active products (optional ?type=MOTO filter)
router.get('/', getProducts);

// GET /products/:id — single product by ID
router.get('/:id', getProductById);

export default router;
