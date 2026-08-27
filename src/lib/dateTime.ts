/** timestamptz (ISO) <-> <input type="datetime-local"> (local, no timezone).
 * Shared by every operational date field (work order scheduled_at/due_at,
 * activity due_at) so the conversion only lives in one place. */
export const toDatetimeLocalValue = (iso: string | null): string => {
  if (!iso) return '';
  const date = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

export const fromDatetimeLocalValue = (value: string): string | null => value ? new Date(value).toISOString() : null;
