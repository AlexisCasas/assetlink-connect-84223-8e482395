import { useEffect, useState } from 'react';
import { LayoutTemplate, Loader2 } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useCriticalityTemplates } from '@/hooks/useCriticalityTemplates';
import { CriticalityTemplatePreview } from './CriticalityTemplatePreview';
import type { CriticalityTemplateDetail } from '@/types/criticalityMatrix';

interface CriticalityTemplatesDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  organizationId: string;
  /** Whether the organization already has an active matrix — drives the
   * "esto reemplazará tu configuración" confirmation. */
  hasActiveMatrix: boolean;
  onApplied: () => void;
}

export function CriticalityTemplatesDialog({
  open,
  onOpenChange,
  organizationId,
  hasActiveMatrix,
  onApplied,
}: CriticalityTemplatesDialogProps) {
  const { templates, loading, saving, error, refresh, loadTemplate, applyTemplate } = useCriticalityTemplates(organizationId);
  const [selected, setSelected] = useState<CriticalityTemplateDetail | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [confirming, setConfirming] = useState(false);

  useEffect(() => {
    if (open) {
      void refresh();
      setSelected(null);
      setConfirming(false);
    }
  }, [open, refresh]);

  const handleSelect = async (templateId: string) => {
    setLoadingDetail(true);
    setConfirming(false);
    const detail = await loadTemplate(templateId);
    setSelected(detail);
    setLoadingDetail(false);
  };

  const handleApply = async () => {
    if (!selected) return;
    const ok = await applyTemplate(selected.id);
    if (ok) {
      onApplied();
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <LayoutTemplate className="h-5 w-5" /> Plantillas de criticidad
          </DialogTitle>
          <DialogDescription>
            Aplica una plantilla para configurar la matriz de esta organización. Puedes adaptarla después.
          </DialogDescription>
        </DialogHeader>

        {error && <p className="text-sm text-destructive">{error}</p>}

        {loading ? (
          <p className="text-sm text-muted-foreground">Cargando plantillas…</p>
        ) : templates.length === 0 ? (
          <div className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">
            <p className="font-medium text-foreground">Todavía no hay plantillas disponibles.</p>
            <p className="mt-1">
              Puedes configurar tu matriz y luego usar “Guardar como plantilla” para reutilizarla.
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {templates.map((template) => (
              <button
                key={template.id}
                type="button"
                onClick={() => void handleSelect(template.id)}
                className={`w-full rounded-md border p-3 text-left transition-colors hover:bg-muted/50 ${
                  selected?.id === template.id ? 'border-primary bg-primary/5' : ''
                }`}
              >
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium">{template.name}</span>
                  <Badge variant={template.scope === 'system' ? 'secondary' : 'outline'}>
                    {template.scope === 'system' ? 'Sistema' : 'Propia'}
                  </Badge>
                  {template.category && <Badge variant="outline">{template.category}</Badge>}
                  <Badge variant="outline">{template.parameterCount} parámetros</Badge>
                  <Badge variant="outline">Peso {template.totalWeight}%</Badge>
                </div>
                {template.description && (
                  <p className="mt-1 text-xs text-muted-foreground">{template.description}</p>
                )}
              </button>
            ))}
          </div>
        )}

        {loadingDetail && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Cargando plantilla…
          </p>
        )}

        {selected && !loadingDetail && (
          <div className="rounded-lg border p-3">
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Vista previa: {selected.name}
            </p>
            <CriticalityTemplatePreview template={selected} />
          </div>
        )}

        {confirming && hasActiveMatrix && (
          <div className="rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
            Ya existe una matriz configurada. Aplicar esta plantilla reemplazará la configuración activa.
            Las evaluaciones históricas no serán eliminadas.
          </div>
        )}

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
          {selected && (
            hasActiveMatrix && !confirming ? (
              <Button onClick={() => setConfirming(true)} disabled={saving || selected.parameters.length === 0}>
                Aplicar plantilla
              </Button>
            ) : (
              <Button onClick={() => void handleApply()} disabled={saving || selected.parameters.length === 0}>
                {saving ? 'Aplicando…' : hasActiveMatrix ? 'Sí, reemplazar matriz' : 'Aplicar plantilla'}
              </Button>
            )
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
