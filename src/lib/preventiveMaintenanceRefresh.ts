export interface PreventiveMaintenanceRefreshChange {
  organizationId?: string | null;
  assetId?: string | null;
  source: symbol;
}

type RefreshListener = (change: PreventiveMaintenanceRefreshChange) => void;

const listeners = new Set<RefreshListener>();

export function notifyPreventiveMaintenanceRefresh(change: PreventiveMaintenanceRefreshChange) {
  listeners.forEach((listener) => listener(change));
}

export function subscribePreventiveMaintenanceRefresh(listener: RefreshListener) {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}
