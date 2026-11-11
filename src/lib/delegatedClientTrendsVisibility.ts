/** Only show a completed, successful and currently authorized trends response.
 * TanStack Query can retain old data during a background refresh or after a
 * failed refresh (including a 42501 permission revocation).
 */
export function visibleDelegatedClientTrends<T>(
  query: { data: T | undefined; isSuccess: boolean; isFetching: boolean },
  hasAccess: boolean,
  rangeIsValid: boolean,
): T | null {
  if (!hasAccess || !rangeIsValid || !query.isSuccess || query.isFetching) {
    return null;
  }
  return query.data ?? null;
}
