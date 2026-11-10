import { supabase } from '@/integrations/supabase/client';
import { isValidUuid } from '@/lib/providerHelpers';

/** D4: FM-client-only notes, not operator work logs, work_order.observations,
 * provider messages or direct table reads. All rights are rechecked in SQL. */
export interface DelegatedExternalFollowup {
  id: string;
  body: string;
  createdAt: string;
  authoredByMe: boolean;
}
export interface DelegatedExternalFollowupPage {
  items: DelegatedExternalFollowup[];
  total: number;
  limit: number;
  offset: number;
}

type FollowupRpc = 'get_facility_management_work_order_followups'
  | 'add_facility_management_work_order_followup';
type RpcArgs = Record<string, string | number>;
type RpcResult = { data: unknown; error: { message: string; code?: string } | null };
const invoke = supabase.rpc.bind(supabase) as unknown as (
  name: FollowupRpc, args: RpcArgs
) => PromiseLike<RpcResult>;

function record(value: unknown): Record<string, unknown> {
  if (!value || Array.isArray(value) || typeof value !== 'object')
    throw new Error('Respuesta del seguimiento no válida.');
  return value as Record<string, unknown>;
}
function parseNote(value: unknown): DelegatedExternalFollowup {
  const n = record(value);
  if (typeof n.id !== 'string' || !isValidUuid(n.id)
    || typeof n.body !== 'string' || n.body.length < 1 || n.body.length > 2000
    || typeof n.created_at !== 'string'
    || !Number.isFinite(Date.parse(n.created_at))
    || typeof n.authored_by_me !== 'boolean')
    throw new Error('Respuesta del seguimiento no válida.');
  return {
    id: n.id,
    body: n.body,
    createdAt: n.created_at,
    authoredByMe: n.authored_by_me,
  };
}
function scope(clientId: string, relationId: string, orderId: string) {
  if (![clientId, relationId, orderId].every(isValidUuid))
    throw new Error('Seguimiento no disponible para esta orden.');
  return {
    _client_organization_id: clientId,
    _relationship_id: relationId,
    _work_order_id: orderId,
  };
}
function safeError(error: RpcResult['error'], writing: boolean): Error {
  if (error?.code === '42501' || /not authorized|permission denied/i.test(error?.message ?? ''))
    return new Error('Ya no tienes permiso para consultar o registrar este seguimiento.');
  if (error?.code === 'PGRST202' || /schema cache|not found/i.test(error?.message ?? ''))
    return new Error('El seguimiento del cliente aún no está habilitado.');
  if (error?.code === '22023')
    return new Error('La nota o el identificador de envío no son válidos.');
  return new Error(writing
    ? 'No se pudo registrar la nota de seguimiento. Inténtalo de nuevo.'
    : 'No se pudo consultar el seguimiento. Inténtalo de nuevo.');
}

export async function fetchDelegatedExternalFollowups(
  clientId: string, relationId: string, orderId: string,
  limit = 20, offset = 0,
): Promise<DelegatedExternalFollowupPage> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 50
    || !Number.isInteger(offset) || offset < 0 || offset > 10000)
    throw new Error('Paginación de seguimiento no válida.');
  const { data, error } = await invoke('get_facility_management_work_order_followups', {
    ...scope(clientId, relationId, orderId), _limit: limit, _offset: offset,
  });
  if (error) throw safeError(error, false);
  const page = record(data);
  if (!Array.isArray(page.items) || typeof page.total !== 'number'
    || !Number.isInteger(page.total) || page.total < 0
    || page.total > 1_000_000)
    throw new Error('Respuesta del seguimiento no válida.');
  return {
    items: page.items.map(parseNote),
    total: page.total, limit, offset,
  };
}

export async function addDelegatedExternalFollowup(
  clientId: string, relationId: string, orderId: string,
  body: string, idempotencyKey: string,
): Promise<DelegatedExternalFollowup> {
  const trimmed = body.trim();
  if (!trimmed || trimmed.length > 2000 || !isValidUuid(idempotencyKey))
    throw new Error('Escribe una nota de 1 a 2000 caracteres.');
  const { data, error } = await invoke('add_facility_management_work_order_followup', {
    ...scope(clientId, relationId, orderId),
    _body: trimmed, _idempotency_key: idempotencyKey,
  });
  if (error) throw safeError(error, true);
  return parseNote(data);
}
