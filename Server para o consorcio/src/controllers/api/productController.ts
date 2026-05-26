import { Request, Response, NextFunction } from 'express';
import { prisma } from '../../config/database';

// Helper para tratar imageUrls que podem vir como string malformada do banco
const safeParseImageUrls = (imageUrls: any): string[] => {
    if (!imageUrls) return [];
    if (Array.isArray(imageUrls)) return imageUrls;
    if (typeof imageUrls !== 'string') return [];

    try {
        return JSON.parse(imageUrls);
    } catch (e) {
        try {
            const normalized = imageUrls.replace(/'/g, '"').replace(/,\s*]/g, ']');
            return JSON.parse(normalized);
        } catch (e2) {
            if (imageUrls.startsWith('http')) return [imageUrls];
            return [];
        }
    }
};

// Helper to safely parse JSON specs
const safeParseSpecs = (specs: any): Record<string, any> => {
    if (!specs) return {};
    if (typeof specs === 'object') return specs;
    try {
        return JSON.parse(specs);
    } catch {
        return {};
    }
};

export const getProducts = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { type, category } = req.query as { type?: string; category?: string };

        const where: any = { active: true };
        if (type) {
            where.type = type.toUpperCase();
        }
        if (category) {
            where.category = category;
        }

        const products = await prisma.product.findMany({
            where,
            include: {
                plans: {
                    where: { active: true },
                    orderBy: { durationMonths: 'asc' }
                }
            }
        });

        // Transform response and calculate installments
        const formattedProducts = products.map(product => {
            const price = product.price.toNumber();
            return {
                ...product,
                price,
                imageUrls: safeParseImageUrls(product.imageUrls),
                specs: safeParseSpecs(product.specs),
                plans: (product as any).plans.map((plan: any) => {
                    const totalRate = Number(plan.adminFeeRate) + Number(plan.fundRate);
                    const totalCost = price * (1 + totalRate / 100);
                    const monthlyInstallment = totalCost / plan.durationMonths;
                    return {
                        ...plan,
                        monthlyInstallment: Number(monthlyInstallment.toFixed(2))
                    };
                })
            };
        });

        res.json(formattedProducts);
    } catch (error) {
        next(error);
    }
};

export const getProductById = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { id } = req.params as { id: string };
        const product = await prisma.product.findUnique({
            where: { id },
            include: {
                plans: {
                    where: { active: true },
                    orderBy: { durationMonths: 'asc' }
                }
            }
        });

        if (!product) {
            return res.status(404).json({ message: 'Produto não encontrado' });
        }

        const price = product.price.toNumber();
        const formattedProduct = {
            ...product,
            price,
            imageUrls: safeParseImageUrls(product.imageUrls),
            specs: safeParseSpecs(product.specs),
            plans: (product as any).plans.map((plan: any) => {
                const totalRate = Number(plan.adminFeeRate) + Number(plan.fundRate);
                const totalCost = price * (1 + totalRate / 100);
                const monthlyInstallment = totalCost / plan.durationMonths;
                return {
                    ...plan,
                    monthlyInstallment: Number(monthlyInstallment.toFixed(2))
                };
            })
        };
        res.json(formattedProduct);
    } catch (error) {
        next(error);
    }
};
