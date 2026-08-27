import { useEffect, useMemo, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Clock, Plus, Trash2 } from 'lucide-react';
import { useActivityReports } from '@/hooks/useActivityReports';
import { toDatetimeLocalValue, fromDatetimeLocalValue } from '@/lib/dateTime';
import type { ActivityReportEvidenceInput, ActivityReportMaterialInput, ActivityReportStatus } from '@/types/activityReport';

interface ActivityReportDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  activityId: string | null;
  onSaved: () => void;
}

const REPORT_STATUS_LABELS: Record<ActivityReportStatus, string> = {
  pending: 'Pendiente',
  in_progress: 'En ejecución',
  completed: 'Finalizada',
  blocked: 'Bloqueada',
};

const formatDate = (value: string) => new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));

const nowAsDatetimeLocal = () => toDatetimeLocalValue(new Date().toISOString());

export function ActivityReportDialog({ open, onOpenChange, activityId, onSaved }: ActivityReportDialogProps) {
  const { formData, loadingForm, saving, error, loadFormData, submitReport } = useActivityReports();

  const [startedAt, setStartedAt] = useState('');
  const [finishedAt, setFinishedAt] = useState('');
  const [observations, setObservations] = useState('');
  const [finalStatus, setFinalStatus] = useState<ActivityReportStatus>('completed');
  const [materialQuantities, setMaterialQuantities] = useState<Record<string, string>>({});
  const [evidences, setEvidences] = useState<ActivityReportEvidenceInput[]>([]);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (open && activityId) void loadFormData(activityId);
  }, [open, activityId, loadFormData]);

  useEffect(() => {
    if (!open) return;
    setStartedAt('');
    setFinishedAt('');
    setObservations('');
    setFinalStatus('completed');
    setMaterialQuantities({});
    setEvidences([]);
    setFormError(null);
  }, [open, activityId]);

  const actualHoursPreview = useMemo(() => {
    if (!startedAt || !finishedAt) return null;
    const start = new Date(startedAt).getTime();
    const finish = new Date(finishedAt).getTime();
    if (Number.isNaN(start) || Number.isNaN(finish) || finish < start) return null;
    return Math.round(((finish - start) / 3_600_000) * 100) / 100;
  }, [startedAt, finishedAt]);

  const addEvidenceRow = () => setEvidences((current) => [...current, { fileName: '' }]);
  const removeEvidenceRow = (index: number) => setEvidences((current) => current.filter((_, i) => i !== index));
  const updateEvidenceRow = (index: number, patch: Partial<ActivityReportEvidenceInput>) => {
    setEvidences((current) => current.map((row, i) => (i === index ? { ...row, ...patch } : row)));
  };

  const handleSubmit = async () => {
    if (!activityId || !formData) return;
    if (!startedAt || !finishedAt) {
      setFormError('Completa Desde y Hasta.');
      return;
    }
    const startedIso = fromDatetimeLocalValue(startedAt);
    const finishedIso = fromDatetimeLocalValue(finishedAt);
    if (!startedIso || !finishedIso || new Date(finishedIso) < new Date(startedIso)) {
      setFormError('"Hasta" no puede ser anterior a "Desde".');
      return;
    }
    const invalidEvidence = evidences.some((evidence) => !evidence.fileName.trim());
    if (invalidEvidence) {
      setFormError('Cada evidencia necesita un nombre de archivo.');
      return;
    }
    setFormError(null);

    const materials: ActivityReportMaterialInput[] = formData.availableMaterials
      .map((material) => ({
        materialId: material.materialId,
        workOrderMaterialId: material.workOrderMaterialId,
        quantityUsed: Number(materialQuantities[material.materialId] ?? '0') || 0,
        unit: material.unit,
      }))
      .filter((material) => material.quantityUsed > 0);

    const ok = await submitReport({
      activityId,
      startedAt: startedIso,
      finishedAt: finishedIso,
      observations: observations.trim() || undefined,
      finalStatus,
      materials,
      evidences: evidences.filter((evidence) => evidence.fileName.trim()).map((evidence) => ({
        fileName: evidence.fileName.trim(),
        fileUrl: evidence.fileUrl?.trim() || undefined,
        notes: evidence.notes?.trim() || undefined,
      })),
    });

    if (ok) {
      onSaved();
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Reportar actividad</DialogTitle>
          {formData && <DialogDescription>{formData.workOrder.workOrderNumber} — {formData.activity.description}</DialogDescription>}
        </DialogHeader>

        {loadingForm || !formData ? (
          <p className="text-sm text-muted-foreground">Cargando…</p>
        ) : (
          <div className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2 text-sm">
              <div>
                <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Actividad</p>
                <p className="mt-1">{formData.activity.description}</p>
              </div>
              <div>
                <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Horas estimadas</p>
                <p className="mt-1">{formData.activity.estimatedHours ?? '—'} h</p>
              </div>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-1">
                <Label htmlFor="report-started-at">Desde *</Label>
                <div className="flex gap-1">
                  <Input id="report-started-at" type="datetime-local" value={startedAt} onChange={(e) => setStartedAt(e.target.value)} disabled={saving} />
                  <Button type="button" variant="outline" size="icon" title="Usar hora actual" onClick={() => setStartedAt(nowAsDatetimeLocal())} disabled={saving}>
                    <Clock className="h-4 w-4" />
                  </Button>
                </div>
              </div>
              <div className="space-y-1">
                <Label htmlFor="report-finished-at">Hasta *</Label>
                <div className="flex gap-1">
                  <Input id="report-finished-at" type="datetime-local" value={finishedAt} onChange={(e) => setFinishedAt(e.target.value)} disabled={saving} />
                  <Button type="button" variant="outline" size="icon" title="Usar hora actual" onClick={() => setFinishedAt(nowAsDatetimeLocal())} disabled={saving}>
                    <Clock className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </div>

            {actualHoursPreview !== null && (
              <p className="text-sm text-muted-foreground">Horas reales: <span className="font-medium text-foreground">{actualHoursPreview} h</span></p>
            )}

            <div className="space-y-1">
              <Label htmlFor="report-observations">Observaciones</Label>
              <Textarea id="report-observations" value={observations} onChange={(e) => setObservations(e.target.value)} rows={3} disabled={saving} />
            </div>

            <div className="space-y-1">
              <Label>Estado final</Label>
              <Select value={finalStatus} onValueChange={(value) => setFinalStatus(value as ActivityReportStatus)} disabled={saving}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent className="bg-popover">
                  {Object.entries(REPORT_STATUS_LABELS).map(([value, label]) => (
                    <SelectItem key={value} value={value}>{label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Material utilizado</Label>
              {formData.availableMaterials.length === 0 ? (
                <p className="text-xs text-muted-foreground">Esta OT no tiene materiales planificados.</p>
              ) : (
                <div className="space-y-2 rounded-md border p-2">
                  {formData.availableMaterials.map((material) => (
                    <div key={material.materialId} className="flex items-center justify-between gap-2 text-sm">
                      <div className="min-w-0">
                        <p className="truncate">{material.code} — {material.name}</p>
                        <p className="text-xs text-muted-foreground">Planificado: {material.plannedQuantity} {material.unit} · Stock: {material.currentStock}</p>
                      </div>
                      <Input
                        type="number"
                        min={0}
                        step={0.01}
                        className="w-24 shrink-0"
                        value={materialQuantities[material.materialId] ?? ''}
                        onChange={(e) => setMaterialQuantities((current) => ({ ...current, [material.materialId]: e.target.value }))}
                        placeholder="0"
                        disabled={saving}
                      />
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label>Evidencias (opcional)</Label>
                <Button type="button" size="sm" variant="outline" onClick={addEvidenceRow} disabled={saving}>
                  <Plus className="mr-1 h-3.5 w-3.5" /> Agregar
                </Button>
              </div>
              {evidences.length > 0 && (
                <div className="space-y-2">
                  {evidences.map((evidence, index) => (
                    <div key={index} className="flex items-start gap-2 rounded-md border p-2">
                      <div className="flex-1 space-y-1">
                        <Input placeholder="Nombre del archivo" value={evidence.fileName} onChange={(e) => updateEvidenceRow(index, { fileName: e.target.value })} disabled={saving} />
                        <Input placeholder="Link (opcional)" value={evidence.fileUrl ?? ''} onChange={(e) => updateEvidenceRow(index, { fileUrl: e.target.value })} disabled={saving} />
                      </div>
                      <Button type="button" variant="ghost" size="icon" onClick={() => removeEvidenceRow(index)} disabled={saving}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}
              <p className="text-xs text-muted-foreground">
                Por ahora solo se guarda nombre y link de referencia — la carga real de archivos queda pendiente.
              </p>
            </div>

            {formData.myPreviousReports.length > 0 && (
              <div className="space-y-1">
                <Label>Tus reportes anteriores de esta actividad</Label>
                <div className="space-y-1 rounded-md border p-2">
                  {formData.myPreviousReports.map((report) => (
                    <div key={report.id} className="text-xs text-muted-foreground">
                      {formatDate(report.startedAt)} – {formatDate(report.finishedAt)} · {report.actualHours} h · {REPORT_STATUS_LABELS[report.finalStatus]}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {(formError || error) && <p className="text-sm text-destructive">{formError ?? error}</p>}

            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
              <Button onClick={() => void handleSubmit()} disabled={saving}>
                {saving ? 'Guardando…' : 'Guardar reporte'}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
