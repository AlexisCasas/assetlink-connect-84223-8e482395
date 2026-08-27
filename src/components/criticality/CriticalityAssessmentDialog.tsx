import { useEffect, useMemo, useState } from 'react';
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
import type { AssetCriticality } from '@/types/asset';
import type { CriticalityAnswer, CriticalityAssessment, CriticalityParameter } from '@/types/criticalityMatrix';

interface CriticalityAssessmentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  assetId: string;
  assetName: string;
  activeParameters: CriticalityParameter[];
  saving: boolean;
  onSave: (assetId: string, answers: CriticalityAnswer[], notes: string | null) => Promise<CriticalityAssessment | null>;
  onSaved: () => void;
}

/** Same MVP thresholds as calculate_asset_criticality in
 * 20260829190000_configurable_criticality_matrix.sql — preview only, the
 * server always recomputes and is the authority for what gets stored. */
const classify = (score: number): AssetCriticality => {
  if (score < 25) return 'low';
  if (score < 50) return 'medium';
  if (score < 75) return 'high';
  return 'critical';
};

export function CriticalityAssessmentDialog({ open, onOpenChange, assetId, assetName, activeParameters, saving, onSave, onSaved }: CriticalityAssessmentDialogProps) {
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [notes, setNotes] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setAnswers({});
    setNotes('');
    setFormError(null);
  }, [open, assetId]);

  const preview = useMemo(() => {
    let score = 0;
    for (const parameter of activeParameters) {
      const optionId = answers[parameter.id];
      const option = parameter.options.find((o) => o.id === optionId);
      if (option) score += Math.round((option.score * parameter.weight / 100) * 100) / 100;
    }
    return { score: Math.round(score * 100) / 100, criticality: classify(score) };
  }, [activeParameters, answers]);

  const answeredCount = activeParameters.filter((parameter) => !!answers[parameter.id]).length;
  const allAnswered = activeParameters.length > 0 && answeredCount === activeParameters.length;

  const handleSubmit = async () => {
    if (!allAnswered) {
      setFormError('Selecciona una opción para cada parámetro activo.');
      return;
    }
    setFormError(null);

    const payload: CriticalityAnswer[] = activeParameters.map((parameter) => ({
      parameterId: parameter.id,
      optionId: answers[parameter.id],
    }));
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

            <div className="rounded-md border bg-muted/30 p-3">
              <p className="text-sm font-medium">
                Vista previa: score {preview.score} — criticidad estimada {ASSET_CRITICALITY_LABELS[preview.criticality]}
              </p>
              <p className="text-xs text-muted-foreground">
                {answeredCount} de {activeParameters.length} parámetros respondidos. Esta es información operativa para orientar la decisión, no un resultado final hasta guardar.
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
