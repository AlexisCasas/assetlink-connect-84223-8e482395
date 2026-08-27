import { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Badge } from '@/components/ui/badge';
import type { InspectionRunDetail } from '@/types/inspection';
import type { SubmitInspectionRunAnswerInput, SubmitInspectionRunEvidenceInput } from '@/hooks/useInspectionRuns';

interface InspectionRunDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  runId: string | null;
  loadRunDetail: (runId: string) => Promise<InspectionRunDetail | null>;
  saving: boolean;
  onSave: (
    runId: string,
    startedAt: string,
    completedAt: string,
    answers: SubmitInspectionRunAnswerInput[],
    evidences: SubmitInspectionRunEvidenceInput[],
    notes: string | null,
  ) => Promise<boolean>;
  onSaved: () => void;
}

interface AnswerDraft {
  responseOptionId: string;
  observations: string;
  evidenceFileName: string;
  evidenceFileUrl: string;
}

const formatDate = (value: string | null) => value ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '—';

/**
 * "Ejecución" form: shows the run's active template items, one selector
 * per item (from the template's own response_options — Cumple/No cumple/
 * No aplica or whatever the template defines), an observation per item,
 * and an optional evidence link/metadata per item. started_at is captured
 * the moment the dialog opens; completed_at at save time.
 */
export function InspectionRunDialog({ open, onOpenChange, runId, loadRunDetail, saving, onSave, onSaved }: InspectionRunDialogProps) {
  const [detail, setDetail] = useState<InspectionRunDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [startedAt, setStartedAt] = useState<string>('');
  const [answers, setAnswers] = useState<Record<string, AnswerDraft>>({});
  const [notes, setNotes] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !runId) {
      setDetail(null);
      setAnswers({});
      setNotes('');
      setFormError(null);
      return;
    }
    setLoading(true);
    setLoadError(null);
    setStartedAt(new Date().toISOString());
    loadRunDetail(runId)
      .then((data) => {
        setDetail(data);
        if (data) {
          const initial: Record<string, AnswerDraft> = {};
          for (const answer of data.answers) {
            initial[answer.templateItemId] = {
              responseOptionId: answer.responseOptionId ?? '',
              observations: answer.observations ?? '',
              evidenceFileName: '',
              evidenceFileUrl: '',
            };
          }
          setAnswers(initial);
          setNotes(data.notes ?? '');
        }
      })
      .catch((err) => setLoadError(err instanceof Error ? err.message : 'No se pudo cargar la inspección.'))
      .finally(() => setLoading(false));
  }, [open, runId, loadRunDetail]);

  const setAnswer = (itemId: string, patch: Partial<AnswerDraft>) => {
    setAnswers((current) => ({
      ...current,
      [itemId]: {
        responseOptionId: current[itemId]?.responseOptionId ?? '',
        observations: current[itemId]?.observations ?? '',
        evidenceFileName: current[itemId]?.evidenceFileName ?? '',
        evidenceFileUrl: current[itemId]?.evidenceFileUrl ?? '',
        ...patch,
      },
    }));
  };

  const requiredItems = detail?.items.filter((item) => item.isRequired) ?? [];
  const answeredRequiredCount = requiredItems.filter((item) => !!answers[item.id]?.responseOptionId).length;
  const allRequiredAnswered = requiredItems.length > 0 && answeredRequiredCount === requiredItems.length;

  const previewFailure = detail?.items.some((item) => {
    const selected = answers[item.id]?.responseOptionId;
    if (!selected) return false;
    return detail.responseOptions.find((o) => o.id === selected)?.isFailure ?? false;
  }) ?? false;

  const handleSubmit = async () => {
    if (!detail || !runId) return;
    if (!allRequiredAnswered) {
      setFormError('Responde todos los ítems obligatorios antes de guardar.');
      return;
    }
    setFormError(null);

    const answerPayload: SubmitInspectionRunAnswerInput[] = detail.items
      .filter((item) => !!answers[item.id]?.responseOptionId)
      .map((item) => ({
        templateItemId: item.id,
        responseOptionId: answers[item.id]!.responseOptionId,
        observations: answers[item.id]!.observations.trim() || null,
      }));

    const evidencePayload: SubmitInspectionRunEvidenceInput[] = detail.items
      .filter((item) => !!answers[item.id]?.evidenceFileName.trim())
      .map((item) => ({
        templateItemId: item.id,
        fileName: answers[item.id]!.evidenceFileName.trim(),
        fileUrl: answers[item.id]!.evidenceFileUrl.trim() || null,
      }));

    const completedAt = new Date().toISOString();
    const ok = await onSave(runId, startedAt || completedAt, completedAt, answerPayload, evidencePayload, notes.trim() || null);
    if (ok) {
      onOpenChange(false);
      onSaved();
    } else {
      setFormError('No se pudo guardar la ejecución. Intenta nuevamente.');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{detail ? `Ejecutar — ${detail.templateName}` : 'Ejecutar inspección'}</DialogTitle>
          <DialogDescription>Responde cada ítem del checklist, agrega observaciones y evidencia opcional, y guarda la ejecución.</DialogDescription>
        </DialogHeader>

        {loading ? (
          <p className="text-sm text-muted-foreground">Cargando inspección…</p>
        ) : loadError ? (
          <p className="text-sm text-destructive">{loadError}</p>
        ) : !detail ? (
          <p className="text-sm text-muted-foreground">Selecciona una ejecución.</p>
        ) : (
          <div className="space-y-5">
            <div className="rounded-md border bg-muted/30 p-3 text-xs text-muted-foreground">
              {detail.assetName && <p>Activo: {detail.assetName}</p>}
              {detail.areaAssetName && <p>Área: {detail.areaAssetName}</p>}
              {detail.branchName && <p>Sede: {detail.branchName}</p>}
              {detail.responsibleName && <p>Responsable: {detail.responsibleName}</p>}
              {detail.status === 'completed' && <p>Completada: {formatDate(detail.completedAt)} — Resultado: {detail.result}</p>}
            </div>

            {detail.items.length === 0 ? (
              <p className="text-sm text-muted-foreground">Esta plantilla no tiene ítems activos.</p>
            ) : (
              detail.items.map((item) => (
                <div key={item.id} className="space-y-2 rounded-md border p-3">
                  <div className="flex items-start justify-between gap-2">
                    <Label className="text-sm font-medium">
                      {item.question}{item.isRequired && <span className="text-destructive"> *</span>}
                    </Label>
                  </div>
                  {item.helpText && <p className="text-xs text-muted-foreground">{item.helpText}</p>}

                  <RadioGroup
                    value={answers[item.id]?.responseOptionId ?? ''}
                    onValueChange={(value) => setAnswer(item.id, { responseOptionId: value })}
                  >
                    {detail.responseOptions.map((option) => (
                      <div key={option.id} className="flex items-center space-x-2">
                        <RadioGroupItem value={option.id} id={`${item.id}-${option.id}`} disabled={saving} />
                        <Label htmlFor={`${item.id}-${option.id}`} className="cursor-pointer text-sm font-normal">{option.label}</Label>
                      </div>
                    ))}
                  </RadioGroup>

                  <Input
                    placeholder="Observación (opcional)"
                    value={answers[item.id]?.observations ?? ''}
                    onChange={(e) => setAnswer(item.id, { observations: e.target.value })}
                    disabled={saving}
                  />
                  <div className="grid gap-2 sm:grid-cols-2">
                    <Input
                      placeholder="Nombre de evidencia (opcional)"
                      value={answers[item.id]?.evidenceFileName ?? ''}
                      onChange={(e) => setAnswer(item.id, { evidenceFileName: e.target.value })}
                      disabled={saving}
                    />
                    <Input
                      placeholder="Link de evidencia (opcional)"
                      value={answers[item.id]?.evidenceFileUrl ?? ''}
                      onChange={(e) => setAnswer(item.id, { evidenceFileUrl: e.target.value })}
                      disabled={saving}
                    />
                  </div>
                </div>
              ))
            )}

            <div className="space-y-1">
              <Label htmlFor="run-notes">Notas generales</Label>
              <Textarea id="run-notes" value={notes} onChange={(e) => setNotes(e.target.value)} disabled={saving} />
            </div>

            {detail.status !== 'completed' && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <Badge variant={previewFailure ? 'destructive' : 'secondary'}>
                  {previewFailure ? 'Se detectó una no conformidad' : 'Sin no conformidades hasta ahora'}
                </Badge>
                <span>{answeredRequiredCount} de {requiredItems.length} ítems obligatorios respondidos.</span>
              </div>
            )}

            {formError && <p className="text-sm text-destructive">{formError}</p>}

            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cerrar</Button>
              {detail.status !== 'completed' && (
                <Button onClick={() => void handleSubmit()} disabled={saving || !allRequiredAnswered}>
                  {saving ? 'Guardando…' : 'Guardar ejecución'}
                </Button>
              )}
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
