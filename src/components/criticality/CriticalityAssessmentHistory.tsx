import { useEffect, useState } from 'react';
import { History } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { ASSET_CRITICALITY_LABELS } from '@/lib/assetLabels';
import type { CriticalityAssessment } from '@/types/criticalityMatrix';

interface CriticalityAssessmentHistoryProps {
  assetId: string;
  /** Bumped by the parent every time a new evaluation is saved, to refetch. */
  refreshToken: number;
  loadAssessments: (assetId: string) => Promise<CriticalityAssessment[]>;
}

const formatDate = (value: string) => new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));

/**
 * Read-only evaluation history for one asset — each row a frozen snapshot
 * (get_asset_criticality_assessments), never re-derived from the current
 * matrix configuration. Purely informational: no comparison across assets
 * or technicians here.
 */
export function CriticalityAssessmentHistory({ assetId, refreshToken, loadAssessments }: CriticalityAssessmentHistoryProps) {
  const [assessments, setAssessments] = useState<CriticalityAssessment[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    loadAssessments(assetId)
      .then((data) => { if (!cancelled) setAssessments(data); })
      .catch((err) => { if (!cancelled) setError(err instanceof Error ? err.message : 'No se pudo cargar el historial de evaluaciones.'); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [assetId, refreshToken, loadAssessments]);

  return (
    <div className="space-y-2">
      <p className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        <History className="h-3.5 w-3.5" /> Historial de evaluaciones de criticidad
      </p>

      {loading ? (
        <p className="text-sm text-muted-foreground">Cargando evaluaciones…</p>
      ) : error ? (
        <p className="text-sm text-destructive">{error}</p>
      ) : assessments.length === 0 ? (
        <p className="text-sm text-muted-foreground">Este activo aún no tiene evaluaciones de criticidad.</p>
      ) : (
        <div className="space-y-2">
          {assessments.map((assessment) => (
            <div key={assessment.id} className="rounded-md border p-2.5 text-sm">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <Badge variant="secondary">Score: {assessment.score}</Badge>
                  <Badge variant="outline">{ASSET_CRITICALITY_LABELS[assessment.calculatedCriticality]}</Badge>
                </div>
                <span className="text-xs text-muted-foreground">{formatDate(assessment.createdAt)}</span>
              </div>
              <p className="mt-1 text-xs text-muted-foreground">
                {assessment.createdByName ? `Por: ${assessment.createdByName}` : null}
                {assessment.manualCriticality ? ` · Criticidad manual previa: ${ASSET_CRITICALITY_LABELS[assessment.manualCriticality]}` : ''}
              </p>
              {assessment.notes && <p className="mt-1 text-xs">{assessment.notes}</p>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
