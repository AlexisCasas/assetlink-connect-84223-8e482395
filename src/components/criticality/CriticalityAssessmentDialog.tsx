import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Badge } from '@/components/ui/badge';
import { ASSET_CRITICALITY_LABELS } from '@/lib/assetLabels';
import { thresholdRanges } from '@/lib/criticalityThresholds';
import { useCriticalityThresholds } from '@/hooks/useCriticalityThresholds';
import type {
  CriticalityAnswer,
  CriticalityAssessment,
  CriticalityAssessmentPreview,
  CriticalityParameter,
} from '@/types/criticalityMatrix';

interface CriticalityAssessmentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  assetId: string;
  assetName: string;
  /** Organization of the asset — used only to show its thresholds legend. */
  organizationId: string;
  activeParameters: CriticalityParameter[];
  saving: boolean;
  onSave: (assetId: string, answers: CriticalityAnswer[], notes: string | null) => Promise<CriticalityAssessment | null>;
  /** Server-side preview (preview_bulk_asset_criticality with one row). */
  onPreview: (assetId: string, answers: CriticalityAnswer[]) => Promise<CriticalityAssessmentPreview>;
  onSaved: () => void;
}

type PreviewState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'ready'; result: CriticalityAssessmentPreview }
  | { status: 'error' };

const PREVIEW_DEBOUNCE_MS = 250;

export function CriticalityAssessmentDialog({
  open,
  onOpenChange,
  assetId,
  assetName,
  organizationId,
  activeParameters,
  saving,
  onSave,
  onPreview,
  onSaved,
}: CriticalityAssessmentDialogProps) {
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [notes, setNotes] = useState('');
  const [formError, setFormError] = useState<string | null>(null);
  const [preview, setPreview] = useState<PreviewState>({ status: 'idle' });
  // Monotonic id of the latest preview request: a response is only applied
  // if it still belongs to the latest request, so a slow answer for an older
  // selection can never overwrite the preview of the current one.
  const previewRequestRef = useRef(0);
  const { thresholds } = useCriticalityThresholds(open ? organizationId : null);

  useEffect(() => {
    if (!open) return;
    setAnswers({});
    setNotes('');
    setFormError(null);
    setPreview({ status: 'idle' });
  }, [open, assetId]);

  const answeredCount = activeParameters.filter((parameter) => !!answers[parameter.id]).length;
  const allAnswered = activeParameters.length > 0 && answeredCount === activeParameters.length;

  const payload = useMemo<CriticalityAnswer[]>(
    () => activeParameters.map((parameter) => ({ parameterId: parameter.id, optionId: answers[parameter.id] ?? null })),
    [activeParameters, answers],
  );

  useEffect(() => {
    const requestId = ++previewRequestRef.current;
    // No partial score: the server only scores a complete evaluation, and the
    // browser never computes one on its own.
    if (!open || !allAnswered) {
      setPreview({ status: 'idle' });
      return;
    }
    setPreview({ status: 'loading' });
    const timer = window.setTimeout(() => {
      onPreview(assetId, payload)
        .then((result) => {
          if (requestId === previewRequestRef.current) setPreview({ status: 'ready', result });
        })
        .catch(() => {
          if (requestId === previewRequestRef.current) setPreview({ status: 'error' });
        });
    }, PREVIEW_DEBOUNCE_MS);
    return () => window.clearTimeout(timer);
  }, [open, allAnswered, assetId, payload, onPreview]);

  const handleSubmit = async () => {
    if (!allAnswered) {
      setFormError('Selecciona una opción para cada parámetro activo.');
      return;
    }
    setFormError(null);

    const result = await onSave(assetId, payload, notes.trim() || null);
    if (result) {
      onOpenChange(false);
      onSaved();
    } else {
      setFormError('No se pudo guardar la evaluación. Intenta nuevamente.');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Evaluar criticidad — {assetName}</DialogTitle>
        </DialogHeader>

        {activeParameters.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Esta organización todavía no tiene parámetros de criticidad activos configurados. Ve a "Criticidad" para crearlos.
          </p>
        ) : (
          <div className="space-y-5">
            {activeParameters.map((parameter) => (
              <div key={parameter.id} className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <Label className="text-sm font-medium">{parameter.name}</Label>
                  <Badge variant="secondary">Peso: {parameter.weight}%</Badge>
                </div>
                {parameter.description && <p className="text-xs text-muted-foreground">{parameter.description}</p>}
                <RadioGroup
                  value={answers[parameter.id] ?? ''}
                  onValueChange={(value) => setAnswers((current) => ({ ...current, [parameter.id]: value }))}
                >
                  {parameter.options.map((option) => (
                    <div key={option.id} className="flex items-center space-x-2">
                      <RadioGroupItem value={option.id} id={`option-${option.id}`} disabled={saving} />
                      <Label htmlFor={`option-${option.id}`} className="cursor-pointer text-sm font-normal">
                        {option.label} <span className="text-xs text-muted-foreground">(puntuación {option.score})</span>
                      </Label>
                    </div>
                  ))}
                </RadioGroup>
              </div>
            ))}

            <div className="space-y-1">
              <Label htmlFor="assessment-notes">Notas (opcional)</Label>
              <Textarea id="assessment-notes" value={notes} onChange={(e) => setNotes(e.target.value)} disabled={saving} />
            </div>

            <div className="space-y-2 rounded-md border bg-muted/30 p-3">
              <p className="text-sm font-medium">
                {preview.status === 'idle' && `Responde los ${activeParameters.length} parámetros para ver la vista previa (${answeredCount} de ${activeParameters.length}).`}
                {preview.status === 'loading' && 'Calculando vista previa…'}
                {preview.status === 'error' && 'No se pudo calcular la vista previa. Puedes guardar igualmente: el resultado lo calcula el servidor.'}
                {preview.status === 'ready' && (preview.result.valid && preview.result.calculatedCriticality
                  ? `Vista previa: score ${preview.result.score} — criticidad ${ASSET_CRITICALITY_LABELS[preview.result.calculatedCriticality]}`
                  : `Vista previa no disponible: ${preview.result.errors.join(' · ') || 'respuestas incompletas.'}`)}
              </p>
              {thresholds && (
                <div className="flex flex-wrap gap-1.5">
                  {thresholdRanges(thresholds).map((range) => (
                    <Badge key={range.criticality} variant="outline" className="text-xs font-normal">
                      {range.label}: {range.range}
                    </Badge>
                  ))}
                </div>
              )}
              <p className="text-xs text-muted-foreground">
                El score y la criticidad los calcula el servidor con los umbrales vigentes de la organización. Es información operativa para orientar la decisión; el resultado se registra al guardar.
              </p>
            </div>

            {formError && <p className="text-sm text-destructive">{formError}</p>}

            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
              <Button onClick={() => void handleSubmit()} disabled={saving || !allAnswered}>
                {saving ? 'Guardando…' : 'Guardar evaluación'}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
