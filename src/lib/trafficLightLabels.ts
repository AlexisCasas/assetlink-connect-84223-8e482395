import type { TrafficLightColor, TrafficLightReason, TrafficLightSourceType } from '@/types/assetTrafficLight';

export const TRAFFIC_LIGHT_ORDER: TrafficLightColor[] = ['green', 'amber', 'red'];

export const TRAFFIC_LIGHT_LABELS: Record<TrafficLightColor, string> = {
  green: 'Verde',
  amber: 'Ámbar',
  red: 'Rojo',
};

/** Same success/warning/destructive tokens already used elsewhere in this
 * codebase (e.g. getAssetStatusBadgeClass in assetLabels.ts) — no new
 * decorative colors introduced. */
export const TRAFFIC_LIGHT_BADGE_CLASS: Record<TrafficLightColor, string> = {
  green: 'bg-success/10 text-success border-success/20',
  amber: 'bg-warning/10 text-warning border-warning/20',
  red: 'bg-destructive/10 text-destructive border-destructive/20',
};

export const TRAFFIC_LIGHT_DOT_CLASS: Record<TrafficLightColor, string> = {
  green: 'bg-success',
  amber: 'bg-warning',
  red: 'bg-destructive',
};

export const TRAFFIC_LIGHT_SOURCE_LABELS: Record<TrafficLightSourceType, string> = {
  asset_status: 'Estado del activo',
  work_order_overdue: 'OT vencida',
  work_order_due_soon: 'OT próxima a vencer',
  inspection_overdue: 'Inspección vencida',
  inspection_due_soon: 'Inspección próxima a vencer',
  inspection_failed: 'Checklist con no conformidad',
};

/** Short, non-decorative summary of why a color is what it is — always
 * grounded in the actual reasons array, never invented text. Mirrors the
 * task's own examples ("Rojo por 1 OT vencida"). */
export const summarizeReasons = (color: TrafficLightColor, reasons: TrafficLightReason[]): string => {
  if (color === 'green' || reasons.length === 0) return 'Todo en regla';
  const relevant = reasons.filter((r) => r.severity === color);
  const counts = new Map<TrafficLightSourceType, number>();
  for (const reason of relevant) {
    counts.set(reason.sourceType, (counts.get(reason.sourceType) ?? 0) + 1);
  }
  const parts = Array.from(counts.entries()).map(([sourceType, count]) =>
    count > 1 ? `${count} ${TRAFFIC_LIGHT_SOURCE_LABELS[sourceType]}` : TRAFFIC_LIGHT_SOURCE_LABELS[sourceType]
  );
  const label = color === 'red' ? 'Rojo por' : 'Ámbar por';
  return `${label} ${parts.join(', ')}`;
};

export const formatReasonDate = (value: string | null): string =>
  value ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '—';
