import { Request } from 'express';

export interface PaginationParams {
    page: number;
    limit: number;
    skip: number;
}

export interface PaginationMeta {
    total: number;
    page: number;
    pages: number;
    limit: number;
    hasNext: boolean;
    hasPrev: boolean;
}

/**
 * Extract pagination params from request query.
 * Defaults: page=1, limit=25. Max limit=100.
 */
export function paginate(req: Request): PaginationParams {
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const parsedLimit = parseInt(req.query.limit as string);
    const rawLimit = isNaN(parsedLimit) ? 25 : parsedLimit;
    const limit = Math.min(Math.max(1, rawLimit), 100);
    const skip = (page - 1) * limit;
    return { page, limit, skip };
}

/**
 * Build pagination metadata from total count and current params.
 */
export function paginationMeta(total: number, page: number, limit: number): PaginationMeta {
    const pages = Math.max(1, Math.ceil(total / limit));
    return {
        total,
        page: Math.min(page, pages),
        pages,
        limit,
        hasNext: page < pages,
        hasPrev: page > 1
    };
}

/**
 * Build a query string preserving existing params but replacing page.
 */
export function buildPageUrl(baseUrl: string, query: Record<string, any>, page: number): string {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(query)) {
        if (key !== 'page' && value !== undefined && value !== '') {
            params.set(key, String(value));
        }
    }
    params.set('page', String(page));
    return `${baseUrl}?${params.toString()}`;
}
