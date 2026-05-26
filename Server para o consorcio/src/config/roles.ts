// Centralized role constants — prevents typos and phantom role strings across the codebase

export const AdminRoles = {
    MASTER: 'MASTER',
    MANAGER: 'MANAGER',
    SUPPORT: 'SUPPORT',
} as const;

export type AdminRole = typeof AdminRoles[keyof typeof AdminRoles];

/** All valid admin roles as an array (use for includes() checks) */
export const ADMIN_ROLE_LIST: string[] = [AdminRoles.MASTER, AdminRoles.MANAGER, AdminRoles.SUPPORT];

/** All valid roles that can be assigned to any user */
export const ALL_VALID_ROLES: string[] = [...ADMIN_ROLE_LIST, 'CLIENT'];
