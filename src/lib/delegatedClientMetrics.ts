import { supabase } from '@/integrations/supabase/client';
import { isValidUuid } from '@/lib/providerHelpers';

/**
 * 9C.7-C1: read-only delegated KPI transport. Never query raw public tables,
 * never fall back to the client's own get_dashboard_metrics.
 * The new B1 RPC validates the relationship, assigned FM and each grant.
 */
export interface DelegatedClientMetrics {
  asOf: string;
  availability: {
    workOrders: boolean;
    requests: boolean;
    assets: boolean;
  };
  workOrders: {
    total: number;
    open: number;
    overdueOpen: number;
    byStatus: {
      pending: number;
      assigned: number;
      inProgress: number;
      completed: number;
      closed: number;
    };
    byType: { internal: number; external: number };
  } | null;
  requests: { open: number } | null;
  assets: { active: number; critical: number } | null;
}

type RpcResult = {
  data: unknown;
  error: { code?: string; message: string } | null;
};
const invokeMetrics = supabase.rpc.bind(supabase) as unknown as (
  name: 'get_facility_management_client_metrics',
  args: { _client_organization_id: string; _relationship_id: string },
) => PromiseLike<RpcResult>;

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('La respuesta de indicadores no tiene un formato válido.');
  }
  return value as Record<string, unknown>;
}

function count(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new Error('La respuesta de indicadores contiene un valor no válido.');
  }
  return value;
}

function parseMetrics(data: unknown): DelegatedClientMetrics {
  const raw = record(data);
  const allowed = record(raw.availability);
  if (typeof allowed.work_orders !== 'boolean'
    || typeof allowed.requests !== 'boolean'
    || typeof allowed.assets !== 'boolean'
    || typeof raw.as_of !== 'string'
    || !Number.isFinite(Date.parse(raw.as_of))) {
    throw new Error('La respuesta de indicadores no tiene un formato válido.');
  }

  let workOrders: DelegatedClientMetrics['workOrders'] = null;
  if (allowed.work_orders) {
    const wo = record(raw.work_orders);
    const statuses = record(wo.by_status);
    const types = record(wo.by_type);
    workOrders = {
      total: count(wo.total),
      open: count(wo.open),
      overdueOpen: count(wo.overdue_open),
      byStatus: {
        pending: count(statuses.pending),
        assigned: count(statuses.assigned),
        inProgress: count(statuses.in_progress),
        completed: count(statuses.completed),
        closed: count(statuses.closed),
      },
      byType: {
        internal: count(types.internal),
        external: count(types.external),
      },
    };
    const { byStatus, byType } = workOrders;
    if (Object.values(byStatus).reduce((a, b) => a + b, 0) !== workOrders.total
      || byType.internal + byType.external !== workOrders.total
      || byStatus.pending + byStatus.assigned + byStatus.inProgress !== workOrders.open
      || workOrders.overdueOpen > workOrders.open) {
      throw new Error('El desglose de órdenes de trabajo no es coherente.');
    }
  } else if (raw.work_orders !== null) {
    throw new Error('La sección de órdenes sin permiso no está correctamente oculta.');
  }

  let requests: DelegatedClientMetrics['requests'] = null;
  if (allowed.requests) {
    requests = { open: count(record(raw.requests).open) };
  } else if (raw.requests !== null) {
    throw new Error('La sección de solicitudes sin permiso no está correctamente oculta.');
  }

  let assets: DelegatedClientMetrics['assets'] = null;
  if (allowed.assets) {
    const assetRows = record(raw.assets);
    assets = { active: count(assetRows.active), critical: count(assetRows.critical) };
    if (assets.critical > assets.active) {
      throw new Error('Los indicadores de activos no son coherentes.');
    }
  } else if (raw.assets !== null) {
    throw new Error('La sección de activos sin permiso no está correctamente oculta.');
  }

  return {
    asOf: raw.as_of,
    availability: {
      workOrders: allowed.work_orders,
      requests: allowed.requests,
      assets: allowed.assets,
    },
    workOrders,
    requests,
    assets,
  };
}

export async function fetchDelegatedClientMetrics(
  clientId: string,
  relationshipId: string,
): Promise<DelegatedClientMetrics> {
  if (!isValidUuid(clientId) || !isValidUuid(relationshipId)) {
    throw new Error('La relación de Facility Manager no es válida.');
  }
  const { data, error } = await invokeMetrics('get_facility_management_client_metrics', {
    _client_organization_id: clientId,
    _relationship_id: relationshipId,
  });
  if (error) {
    if (error.code === '42501') {
      throw new Error('Sin acceso: el cliente revocó el permiso de reportes o tu asignación.');
    }
    if (error.code === 'PGRST202' || /could not find the function|schema cache/i.test(error.message)) {
      throw new Error('Los indicadores delegados aún no están habilitados en este entorno.');
    }
    throw new Error('No fue posible consultar los indicadores. Inténtalo nuevamente.');
  }
  return parseMetrics(data);
}
