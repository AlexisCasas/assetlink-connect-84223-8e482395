import { Constants } from '@/integrations/supabase/types';
import type { Organization, OrganizationMember, OrganizationRelationshipStatus } from '@/types/organization';
import type {
  FacilityManagementMode,
  FacilityManagementPermission,
  FacilityManagementPermissionGroup,
} from '@/types/facilityManagement';

/** Orden del enum en la base de datos (tipos generados). */
export const FACILITY_MANAGEMENT_PERMISSIONS: readonly FacilityManagementPermission[] =
  Constants.public.Enums.facility_management_permission;

// Record exhaustivo: si el enum gana un valor, TypeScript obliga a darle label.
export const FACILITY_MANAGEMENT_PERMISSION_LABELS: Record<FacilityManagementPermission, string> = {
  'assets.view': 'Ver activos',
  'assets.manage': 'Gestionar activos',
  'criticality.view': 'Ver criticidad',
  'criticality.manage': 'Gestionar criticidad',
  'inspections.view': 'Ver inspecciones',
  'inspections.manage': 'Gestionar inspecciones',
  'preventive_maintenance.view': 'Ver mantenimiento preventivo',
  'preventive_maintenance.manage': 'Gestionar mantenimiento preventivo',
  'maintenance_notices.view': 'Ver avisos de avería',
  'maintenance_notices.report': 'Reportar avisos de avería',
  'maintenance_notices.manage': 'Gestionar avisos de avería',
  'requests.view': 'Ver solicitudes',
  'requests.create': 'Crear solicitudes',
  'requests.manage': 'Gestionar solicitudes',
  'providers.manage': 'Gestionar proveedores',
  'quotes.view': 'Ver cotizaciones',
  'quotes.manage': 'Gestionar cotizaciones',
  'quotes.approve': 'Aprobar cotizaciones',
  'work_orders.view': 'Ver órdenes de trabajo',
  'work_orders.manage': 'Gestionar órdenes de trabajo',
  'reports.view': 'Ver reportes',
};

const MODULE_LABELS: Record<string, string> = {
  assets: 'Activos',
  criticality: 'Criticidad',
  inspections: 'Inspecciones',
  preventive_maintenance: 'Mantenimiento preventivo',
  maintenance_notices: 'Avisos de avería',
  requests: 'Solicitudes',
  providers: 'Proveedores',
  quotes: 'Cotizaciones',
  work_orders: 'Órdenes de trabajo',
  reports: 'Reportes',
};

/** Agrupa por módulo (prefijo antes del punto), respetando el orden del
 * enum. Si se pasa `only`, incluye solo esos permisos y omite grupos vacíos. */
export const groupFacilityManagementPermissions = (
  only?: readonly FacilityManagementPermission[],
): FacilityManagementPermissionGroup[] => {
  const filter = only ? new Set(only) : null;
  const groups = new Map<string, FacilityManagementPermissionGroup>();
  for (const code of FACILITY_MANAGEMENT_PERMISSIONS) {
    if (filter && !filter.has(code)) continue;
    const key = code.split('.')[0];
    const group = groups.get(key) ?? { key, label: MODULE_LABELS[key] ?? key, permissions: [] };
    group.permissions.push({ code, label: FACILITY_MANAGEMENT_PERMISSION_LABELS[code] });
    groups.set(key, group);
  }
  return Array.from(groups.values());
};

export const FACILITY_MANAGEMENT_STATUS_LABELS: Record<OrganizationRelationshipStatus, string> = {
  pending: 'Pendiente',
  active: 'Activa',
  suspended: 'Suspendida',
  ended: 'Finalizada',
};

const TRANSITION_LABELS: Record<OrganizationRelationshipStatus, string> = {
  pending: 'Reabrir como pendiente',
  active: 'Activar',
  suspended: 'Suspender',
  ended: 'Finalizar',
};

// Espejo de la máquina de estados de set_facility_management_relationship_status
// (9A). El backend la vuelve a validar; esto solo evita ofrecer botones que
// serían rechazados.
const ALLOWED_TRANSITIONS: Record<OrganizationRelationshipStatus, OrganizationRelationshipStatus[]> = {
  pending: ['active', 'suspended', 'ended'],
  active: ['suspended', 'ended'],
  suspended: ['active', 'ended'],
  ended: ['pending'],
};

export const getFacilityManagementTransitions = (status: OrganizationRelationshipStatus) =>
  ALLOWED_TRANSITIONS[status].map((next) => ({
    next,
    label: status === 'suspended' && next === 'active' ? 'Reactivar' : TRANSITION_LABELS[next],
  }));

/** Permisos y equipo solo se pueden configurar mientras la relación no está
 * finalizada (el backend rechaza `ended` con 55000). */
export const isFacilityManagementRelationshipEditable = (status: OrganizationRelationshipStatus) => status !== 'ended';

/** Qué variante de la vista le corresponde al contexto actual, o null si
 * ninguna. Solo owner/admin activos de un cliente o de un Facility Manager.
 * Es un gate de UI: la autorización real vive en las RPCs. */
export const getFacilityManagementMode = (
  organization: Pick<Organization, 'id' | 'organizationType'> | null,
  membership: Pick<OrganizationMember, 'organizationId' | 'role' | 'isActive'> | null,
): FacilityManagementMode | null => {
  if (!organization || !membership?.isActive || membership.organizationId !== organization.id) return null;
  if (membership.role !== 'owner' && membership.role !== 'admin') return null;
  if (organization.organizationType === 'client_company') return 'client';
  if (organization.organizationType === 'facility_manager') return 'facility_manager';
  return null;
};

export const FACILITY_MANAGEMENT_NAV_LABELS: Record<FacilityManagementMode, string> = {
  client: 'Facility Managers',
  facility_manager: 'Clientes administrados',
};

/** Mensaje en español a partir del SQLSTATE estable de las RPCs 9A/9B. */
export const toFacilityManagementErrorMessage = (error: unknown): string => {
  const code = typeof error === 'object' && error !== null && 'code' in error ? String((error as { code: unknown }).code) : null;
  switch (code) {
    case '42501': return 'No tienes permisos para realizar esta acción.';
    case 'P0002': return 'La relación ya no existe.';
    case '55000': return 'La acción no está permitida en el estado actual de la relación.';
    case '22023': return 'Los datos enviados no son válidos para esta relación.';
    default:
      return error instanceof Error ? error.message
        : typeof error === 'object' && error !== null && 'message' in error ? String((error as { message: unknown }).message)
          : 'Ocurrió un error inesperado.';
  }
};
