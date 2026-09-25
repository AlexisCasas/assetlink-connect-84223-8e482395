import { AlertTriangle, Pencil, SlidersHorizontal } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ASSET_CRITICALITY_LABELS } from '@/lib/assetLabels';
import { THRESHOLDS_CHANGE_NOTICE, formatThresholdNumber, thresholdRanges } from '@/lib/criticalityThresholds';
import type { CriticalityThresholds } from '@/types/criticalityMatrix';

interface CriticalityThresholdsCardProps {
  thresholds: CriticalityThresholds | null;
  loading: boolean;
  error: string | null;
  canManage: boolean;
  onEdit: () => void;
}

/** Read-only summary of the organization's classification thresholds. Every
 * derived value (defaults, score range, unreachable categories) comes from
 * get_criticality_thresholds — nothing is classified here. */
export function CriticalityThresholdsCard({ thresholds, loading, error, canManage, onEdit }: CriticalityThresholdsCardProps) {
  const range = thresholds?.activeMatrix;
  const hasRange = range && range.minPossibleScore !== null && range.maxPossibleScore !== null;

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between space-y-0 pb-3">
        <div>
          <CardTitle className="flex flex-wrap items-center gap-2 text-base">
            <SlidersHorizontal className="h-4 w-4 text-muted-foreground" /> Umbrales de clasificación
            {thresholds && (thresholds.isDefault
              ? <Badge variant="secondary">Valores por defecto</Badge>
              : <Badge variant="outline">Personalizados</Badge>)}
          </CardTitle>
          <p className="mt-1 text-sm text-muted-foreground">
            Puntos de corte del score para clasificar la criticidad de cada evaluación.
          </p>
        </div>
        {canManage && (
          <Button variant="outline" size="sm" onClick={onEdit} disabled={loading || !thresholds}>
            <Pencil className="mr-1 h-3.5 w-3.5" /> Editar umbrales
          </Button>
        )}
      </CardHeader>
      <CardContent className="space-y-3">
        {error ? (
          <p className="text-sm text-destructive">{error}</p>
        ) : !thresholds ? (
          <p className="text-sm text-muted-foreground">{loading ? 'Cargando umbrales…' : 'Sin datos de umbrales.'}</p>
        ) : (
          <>
            <div className="flex flex-wrap gap-2">
              {thresholdRanges(thresholds).map((item) => (
                <Badge
                  key={item.criticality}
                  variant={item.criticality === 'critical' ? 'destructive' : item.criticality === 'high' ? 'default' : 'secondary'}
                  className="font-normal"
                >
                  <span className="font-medium">{item.label}</span>&nbsp;·&nbsp;{item.range}
                </Badge>
              ))}
            </div>

            <p className="text-xs text-muted-foreground">
              {hasRange
                ? `Score posible con la matriz activa: ${formatThresholdNumber(range.minPossibleScore!)} – ${formatThresholdNumber(range.maxPossibleScore!)}.`
                : 'Sin matriz activa: no hay rango de score que evaluar.'}
            </p>

            {thresholds.unreachableCategories.length > 0 && (
              <div className="space-y-1 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
                {thresholds.unreachableCategories.map((category) => (
                  <p key={category} className="flex items-start gap-2">
                    <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
                    <span>
                      Con la matriz activa ninguna evaluación puede resultar <strong>{ASSET_CRITICALITY_LABELS[category]}</strong>.
                    </span>
                  </p>
                ))}
                <p className="text-xs text-muted-foreground">Revisa los umbrales o los puntajes de la matriz. Es una advertencia, no bloquea las evaluaciones.</p>
              </div>
            )}

            <p className="text-xs text-muted-foreground">{THRESHOLDS_CHANGE_NOTICE}</p>
          </>
        )}
      </CardContent>
    </Card>
  );
}
