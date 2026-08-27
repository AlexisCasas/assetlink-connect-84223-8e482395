import type { OrganizationMemberRole } from '@/types/organization';

/**
 * Per-enum-value label. Keeps `owner` and `admin` visually distinct in role
 * pickers/lists (they're both "administrator-tier" functionally, but a
 * select showing two identical "Administrador" options would be unusable).
 */
export const ORGANIZATION_ROLE_LABELS: Record<OrganizationMemberRole, string> = {
  owner: 'Propietario',
  admin: 'Administrador',
  manager: 'Planner / Gestor',
  requester: 'Solicitante',
  quote_manager: 'Cotizador',
  technician: 'Técnico',
  operator: 'Operador',
  viewer: 'Visor',
};

/** Minimum functional role set for creating/editing operational members. */
export const OPERATION_MEMBER_ROLES: OrganizationMemberRole[] = ['admin', 'manager', 'technician', 'viewer'];

export const isOrganizationAdminRole = (role: OrganizationMemberRole): boolean => role === 'owner' || role === 'admin';
export const isPlannerRole = (role: OrganizationMemberRole): boolean => role === 'manager';
export const isTechnicianRole = (role: OrganizationMemberRole): boolean => role === 'technician';

/** Who can plan/organize operational work: create it, assign technicians. */
export const canPlanWork = (role: OrganizationMemberRole | null | undefined): boolean =>
  !!role && (isOrganizationAdminRole(role) || isPlannerRole(role));

/** Who executes operational work: technicians themselves. */
export const canExecuteWork = (role: OrganizationMemberRole | null | undefined): boolean =>
  !!role && isTechnicianRole(role);

/**
 * Collapsed functional label for the minimal internal-operation model
 * (owner/admin => Administrador, manager => Planner/Gestor,
 * technician => Técnico). Falls back to the per-role label for the rest.
 */
export const getFunctionalRoleLabel = (role: OrganizationMemberRole): string => {
  if (isOrganizationAdminRole(role)) return 'Administrador';
  if (isPlannerRole(role)) return 'Planner / Gestor';
  if (isTechnicianRole(role)) return 'Técnico';
  return ORGANIZATION_ROLE_LABELS[role];
};
