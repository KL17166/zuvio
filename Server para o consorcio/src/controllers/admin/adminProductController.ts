import { Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { paginate, paginationMeta, buildPageUrl } from '../../utils/pagination';

// GET /admin/products
export const listProducts = async (req: Request, res: Response) => {
    try {
        const typeFilter = req.query.type as string | undefined;
        const where = typeFilter ? { type: typeFilter.toUpperCase() } : {};
        const { page, limit, skip } = paginate(req);

        const [products, total] = await Promise.all([
            prisma.product.findMany({
                where,
                include: { plans: true },
                orderBy: { name: 'asc' },
                skip,
                take: limit
            }),
            prisma.product.count({ where })
        ]);

        const parsedProducts = products.map(p => ({
            ...p,
            price: p.price.toNumber(),
            specs: p.specs ? JSON.parse(p.specs) : {}
        }));

        const pagination = paginationMeta(total, page, limit);

        res.render('pages/products/index', {
            path: '/products',
            products: parsedProducts,
            typeFilter: typeFilter || '',
            pagination,
            buildPageUrl: (p: number) => buildPageUrl('/admin/products', req.query as Record<string, any>, p)
        });
    } catch (error) {
        logger.error('Load products error:', error);
        res.status(500).send('Erro ao carregar produtos');
    }
};

// GET /admin/products/new
export const newProductForm = (req: Request, res: Response) => {
    res.render('pages/products/form', {
        path: '/products',
        editing: false,
        product: { active: true, type: 'MOTO' }
    });
};

// POST /admin/products/new
export const createProduct = async (req: Request, res: Response) => {
    try {
        const { name, price, type, category, imageUrls, description, brand, model, year, specs, active, minDuration, maxDuration, adminFeeRate, isFeatured, isPopular } = req.body;

        const min = parseInt(minDuration) || 12;
        const max = parseInt(maxDuration) || 60;
        const fee = parseFloat(adminFeeRate) || 15.0;

        // Parse JSON lists/objects injected by our JS frontend
        let parsedImageUrls: string[] = [];
        try { if (imageUrls) parsedImageUrls = JSON.parse(imageUrls); } catch (e) {}
        
        // Se a lista estiver vazia mas houver pelo menos uma URL enviada (caso raro de falha no JS do form), tenta salvar
        if (parsedImageUrls.length === 0 && req.body.imageUrl) {
            parsedImageUrls.push(req.body.imageUrl);
        }

        // Parse JSON specs injected by our JS frontend
        let parsedSpecs: any = {};
        try { if (specs) parsedSpecs = JSON.parse(specs); } catch(e) {}

        const product = await prisma.product.create({
            data: {
                name,
                price: parseFloat(price),
                type: type || 'MOTO',
                category: category || 'geral',
                imageUrl: parsedImageUrls.length > 0 ? parsedImageUrls[0] : '',
                imageUrls: JSON.stringify(parsedImageUrls),
                description,
                brand: brand || null,
                model: model || null,
                year: year ? parseInt(year) : null,
                specs: Object.keys(parsedSpecs).length > 0 ? JSON.stringify(parsedSpecs) : null,
                active: active === 'on',
                isFeatured: isFeatured === 'on',
                isPopular: isPopular === 'on',
                minDuration: min,
                maxDuration: max,
                adminFeeRate: fee
            }
        });

        // Auto-generate plans (e.g., every 12 months or just min/max/mid)
        const durations = new Set<number>();
        durations.add(min);
        durations.add(max);
        for (let d = min; d <= max; d += 12) {
            durations.add(d);
        }

        const plansToCreate = Array.from(durations).sort((a, b) => a - b).map(duration => ({
            name: `${duration} Meses`,
            durationMonths: duration,
            adminFeeRate: fee,
            fundRate: 2.0, // Default fund rate
            productId: product.id,
            active: true
        }));

        await prisma.consortiumPlan.createMany({ data: plansToCreate });

        req.flash('success_msg', 'Produto e planos criados com sucesso!');
        res.redirect('/admin/products');
    } catch (error) {
        logger.error('Create product error:', error);
        req.flash('error_msg', 'Erro ao criar produto.');
        res.redirect('/admin/products/new');
    }
};

// GET /admin/products/:id/edit
export const editProductForm = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;
        const product = await prisma.product.findUnique({ where: { id } });
        if (!product) return res.redirect('/admin/products');

        res.render('pages/products/form', {
            path: '/products',
            editing: true,
            product
        });
    } catch (e) {
        res.redirect('/admin/products');
    }
};

// POST /admin/products/:id/edit
export const updateProduct = async (req: Request, res: Response) => {
    const id = req.params.id as string;
    try {
        const { name, price, type, category, imageUrls, description, brand, model, year, specs, active, minDuration, maxDuration, adminFeeRate, isFeatured, isPopular } = req.body;

        const min = parseInt(minDuration) || 12;
        const max = parseInt(maxDuration) || 60;
        const fee = parseFloat(adminFeeRate) || 15.0;

        // Parse JSON lists/objects injected by our JS frontend
        let parsedImageUrls: string[] = [];
        try { if (imageUrls) parsedImageUrls = JSON.parse(imageUrls); } catch (e) {}

        // Se a lista estiver vazia mas houver pelo menos uma URL enviada
        if (parsedImageUrls.length === 0 && req.body.imageUrl) {
            parsedImageUrls.push(req.body.imageUrl);
        }

        // Parse JSON specs injected by our JS frontend
        let parsedSpecs: any = {};
        try { if (specs) parsedSpecs = JSON.parse(specs); } catch(e) {}

        await prisma.product.update({
            where: { id },
            data: {
                name,
                price: parseFloat(price),
                type: type || 'MOTO',
                category: category || 'geral',
                imageUrl: parsedImageUrls.length > 0 ? parsedImageUrls[0] : '',
                imageUrls: JSON.stringify(parsedImageUrls),
                description,
                brand: brand || null,
                model: model || null,
                year: year ? parseInt(year) : null,
                specs: Object.keys(parsedSpecs).length > 0 ? JSON.stringify(parsedSpecs) : null,
                active: active === 'on',
                isFeatured: isFeatured === 'on',
                isPopular: isPopular === 'on',
                minDuration: min,
                maxDuration: max,
                adminFeeRate: fee
            }
        });

        // Auto-generate missing plans
        const durations = new Set<number>();
        durations.add(min);
        durations.add(max);
        for (let d = min; d <= max; d += 12) {
            durations.add(d);
        }

        const existingPlans = await prisma.consortiumPlan.findMany({
             where: { productId: id }
        });
        const existingDurations = new Set(existingPlans.map(p => p.durationMonths));

        const plansToCreate = Array.from(durations)
            .filter(d => !existingDurations.has(d))
            .map(duration => ({
                name: `${duration} Meses`,
                durationMonths: duration,
                adminFeeRate: fee,
                fundRate: 2.0,
                productId: id,
                active: true
            }));

        if (plansToCreate.length > 0) {
            await prisma.consortiumPlan.createMany({ data: plansToCreate });
        }

        req.flash('success_msg', 'Produto atualizado e planos ajustados!');
        res.redirect('/admin/products');
    } catch (error) {
        req.flash('error_msg', 'Erro ao atualizar produto.');
        res.redirect(`/admin/products/${id}/edit`);
    }
};

// POST /admin/products/:id/delete
export const deleteProduct = async (req: Request, res: Response) => {
    try {
        const id = req.params.id as string;

        // Check if there are active subscriptions linked to this product's plans
        const activeSubscriptions = await prisma.subscription.count({
            where: {
                plan: { productId: id },
                status: { in: ['ACTIVE', 'PENDING', 'CONTEMPLATED'] }
            }
        });

        if (activeSubscriptions > 0) {
            req.flash('error_msg', `Não é possível excluir: existem ${activeSubscriptions} contrato(s) ativo(s) para este produto.`);
            return res.redirect('/admin/products');
        }

        // Delete plans first, then product
        await prisma.consortiumPlan.deleteMany({ where: { productId: id } });
        await prisma.product.delete({ where: { id } });

        req.flash('success_msg', 'Produto e planos removidos com sucesso!');
        res.redirect('/admin/products');
    } catch (error) {
        logger.error('Delete product error:', error);
        req.flash('error_msg', 'Erro ao excluir produto.');
        res.redirect('/admin/products');
    }
};
