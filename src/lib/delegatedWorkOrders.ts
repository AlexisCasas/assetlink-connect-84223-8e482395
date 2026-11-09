import { supabase } from '@/integrations/supabase/client';
import { isValidUuid } from '@/lib/providerHelpers';

/**
 * 9C.6-C1: only the two public B1 RPCs. The generated Supabase types predate
 * the B1 Cloud migration; do not edit generated types or use raw tables.
 * RPC names, argument names and response shapes are contract-checked here.
 */
export type DelegatedWorkOrderStatus = 'pending' | 'assigned' | 'in_progress' | 'completed' | 'closed';
export type DelegatedWorkOrderStatusFilter = DelegatedWorkOrderStatus | 'all';

const STATUSES: readonly DelegatedWorkOrderStatus[] = [
  'pending', 'assigned', 'in_progress', 'completed', 'closed',
];

export interface DelegatedWorkOrder {
  id: string;
  workOrderNumber: string;
  workOrderType: 'internal' | 'external';
  title: string;
  description: string | null;
  status: DelegatedWorkOrderStatus;
  priority: string;
  requestNumber: string | null;
  assetLabel: string | null;
  operatorLabel: string;
  hasPlanner: boolean;
  hasTechnician: boolean;
  scheduledAt: string | null;
  dueAt: string | null;
  createdAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  totalAmount: number | null;
  pricesVisible: boolean;
}

export interface DelegatedWorkOrderPage {
  items: DelegatedWorkOrder[];
  total: number;
  limit: number;
  offset: number;
}

type RpcName = 'get_facility_management_work_orders' | 'get_facility_management_work_order';
type RpcArgs = Record<string, string | number | null>;
type RpcResult = { data: unknown; error: { message: string } | null };

// Keep Supabase's method bound to the client: rpc uses its REST client internally.
const callReadRpc = supabase.rpc.bind(supabase) as unknown as (
  name: RpcName,
  args: RpcArgs,
) => PromiseLike<RpcResult>;

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Respuesta de órdenes de trabajo no válida.');
  }
  return value as Record<string, unknown>;
}

function nullableString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function parseWorkOrder(value: unknown): DelegatedWorkOrder {
  const row = asRecord(value);
  if (
    typeof row.id !== 'string' || !isValidUuid(row.id) ||
    typeof row.work_order_number !== 'string' ||
    (row.work_order_type !== 'internal' && row.work_order_type !== 'external') ||
    typeof row.status !== 'string' ||
    !STATUSES.includes(row.status as DelegatedWorkOrderStatus)
  ) {
    throw new Error('Respuesta de órdenes de trabajo no válida.');
  }

  const pricesVisible = row.prices_visible === true;
  const isMaskedExternal = row.work_order_type === 'external' && !pricesVisible;

  return {
    id: row.id,
    workOrderNumber: row.work_order_number,
    workOrderType: row.work_order_type,
    status: row.status as DelegatedWorkOrderStatus,
    priority: typeof row.priority === 'string' ? row.priority : 'medium',
    title: isMaskedExternal ? 'Orden externa' : (nullableString(row.title) ?? 'Orden sin título'),
    description: isMaskedExternal ? null : nullableString(row.description),
    requestNumber: nullableString(row.request_number),
    assetLabel: nullableString(row.asset_label),
    operatorLabel: row.work_order_type === 'internal' ? 'Interna' : 'Proveedor externo',
    hasPlanner: row.has_planner === true,
    hasTechnician: row.has_technician === true,
    scheduledAt: nullableString(row.scheduled_at),
    dueAt: nullableString(row.due_at),
    createdAt: nullableString(row.created_at),
    startedAt: nullableString(row.started_at),
    completedAt: nullableString(row.completed_at),
    pricesVisible,
    totalAmount: pricesVisible && typeof row.total_amount === 'number' && Number.isFinite(row.total_amount)
      ? row.total_amount : null,
  };
}

export async function fetchDelegatedWorkOrders(
  clientOrganizationId: string,
  status: DelegatedWorkOrderStatusFilter = 'all',
  limit = 20,
  offset = 0,
): Promise<DelegatedWorkOrderPage> {
  if (!isValidUuid(clientOrganizationId)) throw new Error('Cliente no disponible.');
  if (status !== 'all' && !STATUSES.includes(status)) throw new Error('Filtro no válido.');
  if (!Number.isInteger(limit) || limit < 1 || limit > 100 ||
      !Number.isInteger(offset) || offset < 0 || offset > 100_000) {
    throw new Error('Paginación no válida.');
  }

  const { data, error } = await callReadRpc('get_facility_management_work_orders', {
    _client_organization_id: clientOrganizationId,
    _status: status === 'all' ? null : status,
    _limit: limit,
    _offset: offset,
  });
  if (error) throw new Error(error.message);

  const payload = asRecord(data);
  if (
    !Array.isArray(payload.items) ||
    typeof payload.total !== 'number' || !Number.isInteger(payload.total) ||
    payload.total < 0
  ) {
    throw new Error('Respuesta de órdenes de trabajo no válida.');
  }

  return { items: payload.items.map(parseWorkOrder), total: payload.total, limit, offset };
}

export async function fetchDelegatedWorkOrder(
  clientOrganizationId: string,
  workOrderId: string,
): Promise<DelegatedWorkOrder> {
  if (!isValidUuid(clientOrganizationId) || !isValidUuid(workOrderId)) {
    throw new Error('Orden no disponible o sin acceso.');
  }
  const { data, error } = await callReadRpc('get_facility_management_work_order', {
    _client_organization_id: clientOrganizationId,
    _work_order_id: workOrderId,
  });
  if (error) {
    // Do not expose whether a foreign UUID exists or why the RPC denied access.
    if (error.message.includes('Not authorized')) throw new Error('Orden no disponible o sin acceso.');
    throw new Error(error.message);
  }
  if (data === null) throw new Error('Orden no disponible o sin acceso.');
  return parseWorkOrder(data);
}
