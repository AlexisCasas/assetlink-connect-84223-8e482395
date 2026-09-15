import {
  History,
  Settings2,
  FileText,
  ClipboardList,
  ListChecks,
  Wrench,
  Package,
  Camera,
  RefreshCw,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useEffect } from 'react';
import { useAssetHistory } from '@/hooks/useAssetHistory';
import type { AssetHistoryEventType, AssetHistoryGroup, AssetHistoryItem } from '@/types/assetHistory';

interface AssetHistoryProps {
  assetId: string;
  /** Se incrementa desde fuera cuando algo acaba de escribir un evento de
   * este activo (p. ej. crear un aviso de avería), para no obligar al
   * usuario a pulsar "Actualizar" para ver lo que él mismo acaba de hacer.
   * Mismo patrón que CriticalityAssessmentHistory. */
  refreshToken?: number;
}

const EVENT_TYPE_TO_GROUP: Record<AssetHistoryEventType, AssetHistoryGroup> = {
  asset_created: 'asset',
  asset_event: 'asset',
  request_created: 'request',
  work_order_created: 'work_order',
  activity_created: 'activity',
  technician_report: 'intervention',
  material_used: 'material',
  evidence_added: 'evidence',
  inspection_created: 'asset',
};

const GROUP_LABELS: Record<AssetHistoryGroup, string> = {
  asset: 'Evento del activo',
  request: 'Solicitud',
  work_order: 'OT',
  activity: 'Actividad',
  intervention: 'Intervención',
  material: 'Material',
  evidence: 'Evidencia',
};

const GROUP_ICONS: Record<AssetHistoryGroup, typeof Settings2> = {
  asset: Settings2,
  request: FileText,
  work_order: ClipboardList,
  activity: ListChecks,
  intervention: Wrench,
  material: Package,
  evidence: Camera,
};

const GROUP_COLORS: Record<AssetHistoryGroup, string> = {
  asset: 'bg-slate-500/10 text-slate-600 border-slate-500/20',
  request: 'bg-blue-500/10 text-blue-600 border-blue-500/20',
  work_order: 'bg-violet-500/10 text-violet-600 border-violet-500/20',
  activity: 'bg-amber-500/10 text-amber-600 border-amber-500/20',
  intervention: 'bg-orange-500/10 text-orange-600 border-orange-500/20',
  material: 'bg-teal-500/10 text-teal-600 border-teal-500/20',
  evidence: 'bg-pink-500/10 text-pink-600 border-pink-500/20',
};

const formatDate = (value: string) => new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));

const workOrderReference = (item: AssetHistoryItem): string | null => {
  const workOrderNumber = item.metadata?.work_order_number;
  return typeof workOrderNumber === 'string' ? workOrderNumber : null;
};

/**
 * Single reverse-chronological timeline (never split into per-type
 * sections — that would break "orden cronológico"), each item tagged with
 * a colored group badge/icon so the type is still easy to scan at a
 * glance. Reads get_asset_integrated_history — nothing here writes
 * anything; the whole timeline is assembled live from source tables.
 */
export function AssetHistory({ assetId, refreshToken = 0 }: AssetHistoryProps) {
  const { items, loading, error, refresh } = useAssetHistory(assetId);

  useEffect(() => {
    if (refreshToken > 0) void refresh();
  }, [refreshToken, refresh]);

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
          <History className="h-4 w-4" /> Historial del activo
        </p>
        <Button variant="outline" size="icon" className="h-7 w-7" onClick={() => void refresh()} disabled={loading}>
          <RefreshCw className="h-3.5 w-3.5" />
          <span className="sr-only">Actualizar</span>
        </Button>
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Cargando historial…</p>
      ) : error ? (
        <p className="text-sm text-destructive">{error}</p>
      ) : items.length === 0 ? (
        <p className="text-sm text-muted-foreground">Este activo aún no tiene historial operativo.</p>
      ) : (
        <div className="space-y-2">
          {items.map((item) => {
            const group = EVENT_TYPE_TO_GROUP[item.eventType] ?? 'asset';
            const Icon = GROUP_ICONS[group];
            const workOrderNumber = workOrderReference(item);
            return (
              <div key={item.id} className="rounded-md border p-3 text-sm">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="flex items-start gap-2 min-w-0">
                    <Icon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <Badge variant="outline" className={GROUP_COLORS[group]}>{GROUP_LABELS[group]}</Badge>
                        {item.status && <Badge variant="secondary" className="text-xs">{item.status}</Badge>}
                      </div>
                      <p className="mt-1 font-medium break-words">{item.title}</p>
                      {item.description && <p className="text-xs text-muted-foreground break-words">{item.description}</p>}
                    </div>
                  </div>
                  <span className="shrink-0 text-xs text-muted-foreground">{formatDate(item.eventDate)}</span>
                </div>
                <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                  {item.actorName && <span>Por: {item.actorName}</span>}
                  {workOrderNumber && <span>OT: {workOrderNumber}</span>}
                  {group === 'material' && typeof item.metadata?.quantity_used === 'number' && (
                    <span>Cantidad: {item.metadata.quantity_used as number} {String(item.metadata?.unit ?? '')}</span>
                  )}
                  {group === 'evidence' && typeof item.metadata?.file_url === 'string' && item.metadata.file_url && (
                    <a href={item.metadata.file_url as string} target="_blank" rel="noreferrer" className="underline">
                      Ver evidencia
                    </a>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
