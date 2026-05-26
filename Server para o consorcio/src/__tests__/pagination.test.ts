import { paginate, paginationMeta, buildPageUrl } from '../utils/pagination';

describe('paginate', () => {
    const mockReq = (query: Record<string, string> = {}) =>
        ({ query } as any);

    it('should return default values when no query params', () => {
        const result = paginate(mockReq());
        expect(result).toEqual({ page: 1, limit: 25, skip: 0 });
    });

    it('should parse page and limit from query', () => {
        const result = paginate(mockReq({ page: '3', limit: '10' }));
        expect(result).toEqual({ page: 3, limit: 10, skip: 20 });
    });

    it('should enforce minimum page of 1', () => {
        const result = paginate(mockReq({ page: '-5' }));
        expect(result.page).toBe(1);
    });

    it('should enforce maximum limit of 100', () => {
        const result = paginate(mockReq({ limit: '999' }));
        expect(result.limit).toBe(100);
    });

    it('should enforce minimum limit of 1', () => {
        const result = paginate(mockReq({ limit: '0' }));
        expect(result.limit).toBe(1);
    });
});

describe('paginationMeta', () => {
    it('should calculate correct metadata', () => {
        const meta = paginationMeta(100, 3, 10);
        expect(meta).toEqual({
            total: 100,
            page: 3,
            pages: 10,
            limit: 10,
            hasNext: true,
            hasPrev: true
        });
    });

    it('should handle first page', () => {
        const meta = paginationMeta(50, 1, 10);
        expect(meta.hasPrev).toBe(false);
        expect(meta.hasNext).toBe(true);
    });

    it('should handle last page', () => {
        const meta = paginationMeta(50, 5, 10);
        expect(meta.hasNext).toBe(false);
        expect(meta.hasPrev).toBe(true);
    });

    it('should handle single page', () => {
        const meta = paginationMeta(5, 1, 10);
        expect(meta.pages).toBe(1);
        expect(meta.hasNext).toBe(false);
        expect(meta.hasPrev).toBe(false);
    });

    it('should handle empty results', () => {
        const meta = paginationMeta(0, 1, 10);
        expect(meta.pages).toBe(1);
        expect(meta.total).toBe(0);
    });

    it('should clamp page to max pages', () => {
        const meta = paginationMeta(10, 99, 10);
        expect(meta.page).toBe(1);
    });
});

describe('buildPageUrl', () => {
    it('should build URL with page parameter', () => {
        const url = buildPageUrl('/admin/clients', {}, 2);
        expect(url).toBe('/admin/clients?page=2');
    });

    it('should preserve existing query params', () => {
        const url = buildPageUrl('/admin/clients', { search: 'test', status: 'active' }, 3);
        expect(url).toContain('search=test');
        expect(url).toContain('status=active');
        expect(url).toContain('page=3');
    });

    it('should replace existing page param', () => {
        const url = buildPageUrl('/admin/clients', { page: '1', search: 'test' }, 5);
        expect(url).toContain('page=5');
        expect(url).not.toContain('page=1');
    });

    it('should skip empty values', () => {
        const url = buildPageUrl('/admin/clients', { search: '', status: '' }, 1);
        expect(url).toBe('/admin/clients?page=1');
    });
});
