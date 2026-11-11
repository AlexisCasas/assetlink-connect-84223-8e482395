import { supabase } from '@/integrations/supabase/client';
import { isValidUuid } from '@/lib/providerHelpers';

export const PILOT_TRENDS_TIME_ZONE = 'America/Lima' as const;
const DAY_MS = 86_400_000;

/** One daily record is a completed local calendar day label, not a UTC timestamp. */
export type DailyOrderTrend = { date: string; created: number; completed: number };
export type DailyRequestTrend = { date: string; created: number };

export interface DelegatedClientTrends {
  asOf: string;
  startDate: string;
  endDate: string;
  timeZone: typeof PILOT_TRENDS_TIME_ZONE;
  availability: { workOrders: boolean; requests: boolean };
  workOrders: { daily: DailyOrderTrend[] } | null;
  requests: { daily: DailyRequestTrend[] } | null;
}

export function utcCalendarDay(date: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const [year, month, day] = date.split('-').map(Number);
  const value = Date.UTC(year, month - 1, day);
  const timestamp = new Date(value);
  if (!Number.isFinite(value)
    || timestamp.getUTCFullYear() !== year
    || timestamp.getUTCMonth() + 1 !== month
    || timestamp.getUTCDate() !== day) return null;
  return value;
}

export function dateRangeError(start: string, end: string): string | null {
  const from = utcCalendarDay(start);
  const to = utcCalendarDay(end);
  if (from === null || to === null) return 'Selecciona fechas válidas.';
  const days = (to - from) / DAY_MS + 1;
  if (days < 1) return 'La fecha final no puede ser anterior a la inicial.';
  if (days > 366) return 'El período máximo permitido es de 366 días.';
  return null;
}

export function shiftCalendarDate(date: string, changeDays: number): string {
  const start = utcCalendarDay(date);
  if (start === null || !Number.isSafeInteger(changeDays)) {
    throw new Error('No se pudo calcular el período.');
  }
  return new Date(start + changeDays * DAY_MS).toISOString().slice(0, 10);
}

export function todayInLima(): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: PILOT_TRENDS_TIME_ZONE,
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(new Date());
  const value = (key: string) => parts.find((part) => part.type === key)?.value ?? '';
  return `${value('year')}-${value('month')}-${value('day')}`;
}

type RpcResult = { data: unknown; error: { code?: string; message: string } | null };
const invokeTrends = supabase.rpc.bind(supabase) as unknown as (
  name: 'get_facility_management_client_trends',
  args: {
    _client_organization_id: string;
    _relationship_id: string;
    _start_date: string;
    _end_date: string;
    _time_zone: typeof PILOT_TRENDS_TIME_ZONE;
  },
) => PromiseLike<RpcResult>;

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Formato de tendencias no válido.');
  }
  return value as Record<string, unknown>;
}

function nonnegativeInteger(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new Error('Los indicadores diarios contienen valores no válidos.');
  }
  return value;
}

function dailySeries<T>(value: unknown, start: string, end: string, type: 'work_orders' | 'requests'): T[] {
  const raw = object(value);
  if (!Array.isArray(raw.daily)) throw new Error('Falta la serie diaria de indicadores.');
  const from = utcCalendarDay(start);
  const to = utcCalendarDay(end);
  if (from === null || to === null || raw.daily.length !== (to - from) / DAY_MS + 1) {
    throw new Error('La serie diaria está incompleta.');
  }
  return raw.daily.map((entry: unknown, i: number) => {
    const row = object(entry);
    const expectedDate = shiftCalendarDate(start, i);
    if (row.date !== expectedDate) throw new Error('La serie diaria no coincide con el período.');
    const created = nonnegativeInteger(row.created);
    if (type === 'work_orders') {
      return { date: expectedDate, created, completed: nonnegativeInteger(row.completed) } as T;
    }
    return { date: expectedDate, created } as T;
  });
}

function parseTrends(data: unknown, start: string, end: string): DelegatedClientTrends {
  const raw = object(data);
  const flags = object(raw.availability);
  if (raw.start_date !== start || raw.end_date !== end
    || raw.time_zone !== PILOT_TRENDS_TIME_ZONE
    || typeof flags.work_orders !== 'boolean'
    || typeof flags.requests !== 'boolean'
    || typeof raw.as_of !== 'string'
    || !Number.isFinite(Date.parse(raw.as_of))) {
    throw new Error('Las tendencias no coinciden con el período solicitado.');
  }
  if (!flags.work_orders && raw.work_orders !== null) {
    throw new Error('La sección de OT sin acceso debe estar oculta.');
  }
  if (!flags.requests && raw.requests !== null) {
    throw new Error('La sección de solicitudes sin acceso debe estar oculta.');
  }
  const workOrders = flags.work_orders
    ? { daily: dailySeries<DailyOrderTrend>(raw.work_orders, start, end, 'work_orders') }
    : null;
  const requests = flags.requests
    ? { daily: dailySeries<DailyRequestTrend>(raw.requests, start, end, 'requests') }
    : null;
  return {
    asOf: raw.as_of,
    startDate: start,
    endDate: end,
    timeZone: PILOT_TRENDS_TIME_ZONE,
    availability: { workOrders: flags.work_orders, requests: flags.requests },
    workOrders, requests,
  };
}

/** Uses only the authorized B2 aggregate RPC. It never queries raw client rows. */
export async function fetchDelegatedClientTrends(
  clientId: string, relationshipId: string, start: string, end: string,
): Promise<DelegatedClientTrends> {
  if (!isValidUuid(clientId) || !isValidUuid(relationshipId)) {
    throw new Error('La relación de Facility Manager no es válida.');
  }
  const rangeError = dateRangeError(start, end);
  if (rangeError) throw new Error(rangeError);
  const { data, error } = await invokeTrends('get_facility_management_client_trends', {
    _client_organization_id: clientId,
    _relationship_id: relationshipId,
    _start_date: start,
    _end_date: end,
    _time_zone: PILOT_TRENDS_TIME_ZONE,
  });
  if (error) {
    if (error.code === '42501') {
      throw new Error('Sin acceso a tendencias: verifica el permiso de reportes y tu asignación.');
    }
    if (error.code === '22023') {
      throw new Error('El rango de fechas o la zona horaria no son válidos.');
    }
    if (error.code === 'PGRST202' || /could not find the function|schema cache/i.test(error.message)) {
      throw new Error('Las tendencias históricas aún no están habilitadas en este entorno.');
    }
    throw new Error('No fue posible consultar las tendencias históricas.');
  }
  return parseTrends(data, start, end);
}
