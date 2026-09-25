import { AlertTriangle } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { ASSET_CRITICALITY_LABELS } from '@/lib/assetLabels';
import { formatThresholdNumber, formatThresholdTriplet, thresholdRanges } from '@/lib/criticalityThresholds';
import type { CriticalityTemplateDetail, CriticalityThresholdValues } from '@/types/criticalityMatrix';

interface CriticalityTemplatePreviewProps {
  template: CriticalityTemplateDetail;
  /** The organization's current effective thresholds, for comparison. */
  currentThresholds: CriticalityThresholdValues | null;
}

/** Read-only rendering of a template's parameters/options — shown before
 * applying it, so the user never replaces their matrix blind. */
export function CriticalityTemplatePreview({ template, currentThresholds }: CriticalityTemplatePreviewProps) {
  const totalWeight = Math.round(
    template.parameters.reduce((sum, parameter) => sum + parameter.weight, 0) * 100,
  ) / 100;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={template.scope === 'system' ? 'secondary' : 'outline'}>
          {template.scope === 'system' ? 'Plantilla del sistema' : 'Plantilla propia'}
        </Badge>
        {template.category && <Badge variant="outline">{template.category}</Badge>}
        <Badge variant="outline">{template.parameters.length} parámetros</Badge>
        <Badge variant={totalWeight === 100 ? 'secondary' : 'outline'}>Peso total: {totalWeight}%</Badge>
      </div>

      {template.description && <p className="text-sm text-muted-foreground">{template.description}</p>}

      <div className="space-y-1.5 rounded-md border p-3 text-sm">
        <p className="font-medium">Umbrales de clasificación</p>
        {template.thresholds ? (
          <>
            <p>
              De la plantilla: <span className="font-medium">{formatThresholdTriplet(template.thresholds)}</span>
              {currentThresholds && <span className="text-muted-foreground"> · actuales: {formatThresholdTriplet(currentThresholds)}</span>}
            </p>
            <div className="flex flex-wrap gap-1.5">
              {thresholdRanges(template.thresholds).map((item) => (
                <Badge key={item.criticality} variant="outline" className="text-xs font-normal">{item.label}: {item.range}</Badge>
              ))}
            </div>
            <p className="text-xs text-muted-foreground">Al aplicar la plantilla también se aplicarán sus umbrales.</p>
          </>
        ) : (
          <p className="text-muted-foreground">
            Plantilla sin umbrales (formato anterior): se conservarán los umbrales actuales
            {currentThresholds ? ` (${formatThresholdTriplet(currentThresholds)})` : ''}.
          </p>
        )}
        {template.minPossibleScore !== null && template.maxPossibleScore !== null && (
          <p className="text-xs text-muted-foreground">
            Score posible con esta plantilla: {formatThresholdNumber(template.minPossibleScore)} – {formatThresholdNumber(template.maxPossibleScore)}.
          </p>
        )}
        {template.unreachableCategories.length > 0 && (
          <p className="flex items-start gap-2 text-amber-700">
            <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            Con sus propios umbrales, esta plantilla nunca produciría: {template.unreachableCategories.map((category) => ASSET_CRITICALITY_LABELS[category]).join(', ')}.
          </p>
        )}
      </div>

      {template.parameters.length === 0 ? (
        <p className="text-sm text-muted-foreground">Esta plantilla no tiene parámetros activos.</p>
      ) : (
        <div className="space-y-2">
          {template.parameters.map((parameter) => (
            <div key={parameter.id} className="rounded-md border p-3">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium">{parameter.name}</span>
                <Badge variant="outline" className="font-mono text-[10px]">{parameter.code}</Badge>
                <Badge variant="secondary">{parameter.weight}%</Badge>
              </div>
              {parameter.description && (
                <p className="mt-1 text-xs text-muted-foreground">{parameter.description}</p>
              )}
              <div className="mt-2 flex flex-wrap gap-1.5">
                {parameter.options.map((option) => (
                  <Badge key={option.id} variant="outline" className="text-xs">
                    {option.label} · {option.score}
                  </Badge>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
