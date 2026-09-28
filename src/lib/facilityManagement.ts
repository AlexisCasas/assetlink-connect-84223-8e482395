import { Constants } from '@/integrations/supabase/types';
import type { Organization, OrganizationMember, OrganizationMemberRole, OrganizationRelationshipStatus } from '@/types/organization';
import type {
  FacilityManagementMode,
  FacilityManagementOperationalClient,
  FacilityManagementOperationalModule,
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

// ---------------------------------------------------------------------------
// Acceso OPERATIVO delegado (9C.1). Única fuente frontend de la matriz de
// roles; espejo de has_facility_management_operational_access_all y de las
// capacidades can_*_criticality del backend. Es UX: RLS/RPCs vuelven a
// validar todo. *.manage nunca sustituye a *.view.
// ---------------------------------------------------------------------------
const FM_ASSET_VIEW_ROLES: readonly OrganizationMemberRole[] = ['owner', 'admin', 'manager', 'technician'];
const FM_MANAGER_ROLES: readonly OrganizationMemberRole[] = ['owner', 'admin', 'manager'];

type OperationalClientAccess = Pick<FacilityManagementOperationalClient, 'membershipRole' | 'permissions'>;

const grants = (client: OperationalClientAccess, ...required: FacilityManagementPermission[]) =>
  required.every((permission) => client.permissions.includes(permission));

export const canFacilityManagerViewAssets = (client: OperationalClientAccess) =>
  FM_ASSET_VIEW_ROLES.includes(client.membershipRole) && grants(client, 'assets.view');

export const canFacilityManagerManageAssets = (client: OperationalClientAccess) =>
  FM_MANAGER_ROLES.includes(client.membershipRole) && grants(client, 'assets.view', 'assets.manage');

export const canFacilityManagerViewCriticality = (client: OperationalClientAccess) =>
  FM_MANAGER_ROLES.includes(client.membershipRole) && grants(client, 'criticality.view');

export const canFacilityManagerManageCriticality = (client: OperationalClientAccess) =>
  FM_MANAGER_ROLES.includes(client.membershipRole) && grants(client, 'criticality.view', 'criticality.manage');

/** Historial de evaluaciones de un activo: poder ver el activo y la criticidad. */
export const canFacilityManagerViewAssetCriticalityAssessments = (client: OperationalClientAccess) =>
  FM_MANAGER_ROLES.includes(client.membershipRole) && grants(client, 'assets.view', 'criticality.view');

/** Evaluar criticidad de un activo: no exige assets.manage, sí verlo. */
export const canFacilityManagerEvaluateAssetCriticality = (client: OperationalClientAccess) =>
  FM_MANAGER_ROLES.includes(client.membershipRole) && grants(client, 'assets.view', 'criticality.view', 'criticality.manage');

/** Editar a mano assets.criticality: gestionar el activo Y la criticidad
 * (el backend lo exige en trg_assets_enforce_delegated_write_limits). */
export const canFacilityManagerEditAssetCriticalityValue = (client: OperationalClientAccess) =>
  canFacilityManagerManageAssets(client) && canFacilityManagerManageCriticality(client);

// ---------------------------------------------------------------------------
// 9C.2: Inspecciones + Preventivo. Espejo de can_view_inspections /
// can_plan_inspections / can_execute_inspections_as_facility_manager y de
// can_view/plan_preventive_maintenance + can_record_preventive_meter_reading.
// ---------------------------------------------------------------------------
const FM_OPERATOR_ROLES: readonly OrganizationMemberRole[] = ['owner', 'admin', 'manager', 'technician'];

export const canFacilityManagerViewInspections = (client: OperationalClientAccess) =>
  FM_OPERATOR_ROLES.includes(client.membershipRole) && grants(client, 'inspections.view');

/** Plantillas, ítems, opciones, planes y alertas. */
export const canFacilityManagerManageInspections = (client: OperationalClientAccess) =>
  FM_MANAGER_ROLES.includes(client.membershipRole) && grants(client, 'inspections.view', 'inspections.manage');

/** Crear una ejecución desde un plan y completar el checklist. Un technician
 * ejecuta sin poder planificar. */
export const canFacilityManagerExecuteInspections = (client: OperationalClientAccess) =>
  FM_OPERATOR_ROLES.includes(client.membershipRole) && grants(client, 'inspections.view', 'inspections.manage');

export const canFacilityManagerViewPreventive = (client: OperationalClientAccess) =>
  FM_OPERATOR_ROLES.includes(client.membershipRole) && grants(client, 'preventive_maintenance.view');

/** Fichas, planes y omitir ciclos. */
export const canFacilityManagerManagePreventive = (client: OperationalClientAccess) =>
  FM_MANAGER_ROLES.includes(client.membershipRole) && grants(client, 'preventive_maintenance.view', 'preventive_maintenance.manage');

export const canFacilityManagerRecordMeterReading = (client: OperationalClientAccess) =>
  FM_OPERATOR_ROLES.includes(client.membershipRole) && grants(client, 'preventive_maintenance.view', 'preventive_maintenance.manage');

/** Crear, corregir, retirar y reemplazar medidores. */
export const canFacilityManagerManageMeters = (client: OperationalClientAccess) =>
  canFacilityManagerManagePreventive(client);

const MODULE_VIEW_CHECKS: Record<FacilityManagementOperationalModule, (client: OperationalClientAccess) => boolean> = {
  assets: canFacilityManagerViewAssets,
  criticality: canFacilityManagerViewCriticality,
  inspections: canFacilityManagerViewInspections,
  'preventive-maintenance': canFacilityManagerViewPreventive,
};

export const canFacilityManagerOpenModule = (
  client: OperationalClientAccess,
  module: FacilityManagementOperationalModule,
) => MODULE_VIEW_CHECKS[module](client);

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
