import type { FacilityManagementPortfolioEntry } from '@/types/facilityManagement';

type ReportsAccessEntry = Pick<
  FacilityManagementPortfolioEntry,
  'status' | 'clientOrganizationStatus' | 'permissions'
>;

interface ReportsAccessContext {
  entry: ReportsAccessEntry;
  /** Effective access from get_my_facility_management_clients, not just portfolio grants. */
  allowed: boolean;
  loading: boolean;
  error: boolean;
}

/**
 * Explains why reports are unavailable without ever overriding the
 * delegated-authorization gate. A missing permission must not make the
 * action disappear: the client organization controls reports.view.
 */
export function delegatedReportsAccessReason({
  entry, allowed, loading, error,
}: ReportsAccessContext): string | null {
  if (entry.status !== 'active' || entry.clientOrganizationStatus !== 'active') {
    return 'La relación con el cliente o el cliente mismo no está activo.';
  }
  if (!entry.permissions.includes('reports.view')) {
    return 'El cliente debe habilitar Reportes → Ver reportes (reports.view).';
  }
  if (loading) {
    return 'Verificando tu asignación y permisos para este cliente…';
  }
  if (error) {
    return 'No se pudo verificar tu acceso. Vuelve a cargar la página.';
  }
  if (!allowed) {
    return 'Tu usuario necesita estar asignado a este cliente con rol de administrador o responsable.';
  }
  return null;
}
