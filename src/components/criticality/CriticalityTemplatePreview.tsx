import { Badge } from '@/components/ui/badge';
import type { CriticalityTemplateDetail } from '@/types/criticalityMatrix';

interface CriticalityTemplatePreviewProps {
  template: CriticalityTemplateDetail;
}

/** Read-only rendering of a template's parameters/options — shown before
 * applying it, so the user never replaces their matrix blind. */
export function CriticalityTemplatePreview({ template }: CriticalityTemplatePreviewProps) {
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
