import { useEffect, useRef, useState } from 'react';
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
import { Checkbox } from '@/components/ui/checkbox';
import { Badge } from '@/components/ui/badge';
import { X, Plus } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useOrganizationTechnicians } from '@/hooks/useOrganizationTechnicians';
import { useOrganizationPlanners } from '@/hooks/useOrganizationPlanners';
import type { ChecklistTemplate } from '@/types/checklist';
import type { Asset } from '@/types/asset';
import type { ClientBranch } from '@/types/request';
import type {
  InspectionAlertRuleDraft,
  InspectionCustomUnit,
  InspectionFrequency,
  InspectionPlan,
  InspectionPlanInput,
} from '@/types/inspection';

interface InspectionPlanDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  organizationId: string | null | undefined;
  templates: ChecklistTemplate[];
  branches: ClientBranch[];
  assets: Asset[];
  plan: InspectionPlan | null;
  saving: boolean;
  onSave: (input: InspectionPlanInput, planId: string | undefined, alertRules: InspectionAlertRuleDraft[]) => Promise<boolean>;
}

const FREQUENCY_OPTIONS: { value: InspectionFrequency; label: string }[] = [
  { value: 'one_time', label: 'Única vez' },
  { value: 'weekly', label: 'Semanal' },
  { value: 'monthly', label: 'Mensual' },
  { value: 'quarterly', label: 'Trimestral' },
  { value: 'semiannual', label: 'Semestral' },
  { value: 'annual', label: 'Anual' },
  { value: 'custom', label: 'Personalizada' },
];

const CUSTOM_UNIT_OPTIONS: { value: InspectionCustomUnit; label: string }[] = [
  { value: 'days', label: 'días' },
  { value: 'weeks', label: 'semanas' },
  { value: 'months', label: 'meses' },
  { value: 'years', label: 'años' },
];

/** Suggested starting point for a brand-new plan's "Alertas" section — the
 * user can freely add/remove from here (e.g. ITSE typically adds 90/60/30 +
 * vencido). Never applied when editing an existing plan. */
const DEFAULT_NEW_PLAN_ALERT_RULES: InspectionAlertRuleDraft[] = [
  { alertType: 'before_due', daysBefore: 30, label: '30 días antes' },
  { alertType: 'overdue', daysBefore: null, label: 'Vencido' },
];

const QUICK_ADD_DAYS = [90, 60, 30];

const toDateInputValue = (iso: string | null) => (iso ? iso.slice(0, 10) : '');

interface PlanDraft {
  templateId: string;
  title: string;
  description: string;
  branchId: string;
  areaAssetId: string;
  assetId: string;
  responsibleMemberId: string;
  frequency: InspectionFrequency;
  customInterval: string;
  customUnit: InspectionCustomUnit;
  startDate: string;
  nextDueAt: string;
  alertRules: InspectionAlertRuleDraft[];
}

const emptyDraft = (): PlanDraft => ({
  templateId: '',
  title: '',
  description: '',
  branchId: '',
  areaAssetId: '',
  assetId: '',
  responsibleMemberId: '',
  frequency: 'one_time',
  customInterval: '1',
  customUnit: 'days',
  startDate: new Date().toISOString().slice(0, 10),
  nextDueAt: '',
  alertRules: [],
});

const draftFromPlan = (plan: InspectionPlan | null): PlanDraft => plan ? {
  templateId: plan.templateId,
  title: plan.title,
  description: plan.description ?? '',
  branchId: plan.branchId ?? '',
  areaAssetId: plan.areaAssetId ?? '',
  assetId: plan.assetId ?? '',
  responsibleMemberId: plan.responsibleMemberId ?? '',
  frequency: plan.frequency,
  customInterval: plan.customInterval != null ? String(plan.customInterval) : '1',
  customUnit: plan.customUnit ?? 'days',
  startDate: plan.startDate,
  nextDueAt: toDateInputValue(plan.nextDueAt),
  alertRules: plan.alertRules.map((rule) => ({ alertType: rule.alertType, daysBefore: rule.daysBefore, label: rule.label ?? '' })),
} : { ...emptyDraft(), alertRules: DEFAULT_NEW_PLAN_ALERT_RULES };

// No sensitive data here — just plan configuration already visible on
// screen to this organization's own users. Per-tab (sessionStorage), not
// shared across tabs/devices.
const draftStorageKey = (organizationId: string | null | undefined, plan: InspectionPlan | null) =>
  organizationId ? `inspection-plan-draft:${organizationId}:${plan ? plan.id : 'new'}` : null;

const readDraft = (key: string): PlanDraft | null => {
  try {
    const raw = sessionStorage.getItem(key);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<PlanDraft>;
    if (typeof parsed !== 'object' || parsed === null) return null;
    return { ...emptyDraft(), ...parsed };
  } catch {
    return null;
  }
};

const writeDraft = (key: string, draft: PlanDraft) => {
  try {
    sessionStorage.setItem(key, JSON.stringify(draft));
  } catch {
    // sessionStorage unavailable/full — draft persistence is a convenience,
    // never worth failing the form over.
  }
};

const clearDraftStorage = (key: string | null) => {
  if (!key) return;
  try {
    sessionStorage.removeItem(key);
  } catch {
    // ignore
  }
};

/**
 * Periodicidad (incluye "Personalizada": cada [N] [días/semanas/meses/años])
 * y sección "Alertas" (N días antes / vencido), configurables por plan —
 * funciona igual para cualquier plantilla (ITSE, luces de emergencia,
 * techos, auditoría interna…), nunca hardcodeado. Ver
 * docs/INSPECTION_SCHEDULING_ALERTS.md.
 *
 * Mantiene el fix de la fase anterior (ver
 * docs/GENERIC_CHECKLISTS_INSPECTIONS.md): inicialización solo en la
 * transición cerrado→abierto o cuando cambia el id del plan editado
 * (nunca por refetch de templates/branches/assets), más un draft espejado
 * en sessionStorage restaurado al reabrir y limpiado solo al guardar con
 * éxito o cancelar explícitamente.
 */
export function InspectionPlanDialog({ open, onOpenChange, organizationId, templates, branches, assets, plan, saving, onSave }: InspectionPlanDialogProps) {
  const { technicians } = useOrganizationTechnicians(organizationId);
  const { planners } = useOrganizationPlanners(organizationId);

  const [templateId, setTemplateId] = useState('');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [branchId, setBranchId] = useState('');
  const [areaAssetId, setAreaAssetId] = useState('');
  const [assetId, setAssetId] = useState('');
  const [responsibleMemberId, setResponsibleMemberId] = useState('');
  const [frequency, setFrequency] = useState<InspectionFrequency>('one_time');
  const [customInterval, setCustomInterval] = useState('1');
  const [customUnit, setCustomUnit] = useState<InspectionCustomUnit>('days');
  const [startDate, setStartDate] = useState('');
  const [nextDueAt, setNextDueAt] = useState('');
  const [alertRules, setAlertRules] = useState<InspectionAlertRuleDraft[]>([]);
  const [customDaysInput, setCustomDaysInput] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  const wasOpenRef = useRef(false);
  const initializedForRef = useRef<string | null>(null);

  const draftKey = draftStorageKey(organizationId, plan);

  // Initialize ONLY on a closed→open transition, or when the id of the
  // plan being edited actually changes while open — deliberately keyed off
  // `plan?.id` (a primitive), not `plan` itself or `templates`/`branches`/
  // `assets`/technician-planner lists, so a background refetch that
  // produces new array/object references can never wipe the draft (root
  // cause of a prior bug — see docs/GENERIC_CHECKLISTS_INSPECTIONS.md).
  useEffect(() => {
    if (!open) {
      wasOpenRef.current = false;
      return;
    }

    const planKey = plan?.id ?? 'new';
    const shouldInitialize = !wasOpenRef.current || initializedForRef.current !== planKey;

    if (shouldInitialize) {
      const key = draftStorageKey(organizationId, plan);
      const restored = key ? readDraft(key) : null;
      const next = restored ?? draftFromPlan(plan);

      setTemplateId(next.templateId);
      setTitle(next.title);
      setDescription(next.description);
      setBranchId(next.branchId);
      setAreaAssetId(next.areaAssetId);
      setAssetId(next.assetId);
      setResponsibleMemberId(next.responsibleMemberId);
      setFrequency(next.frequency);
      setCustomInterval(next.customInterval);
      setCustomUnit(next.customUnit);
      setStartDate(next.startDate);
      setNextDueAt(next.nextDueAt);
      setAlertRules(next.alertRules);
      setCustomDaysInput('');
      setFormError(null);

      initializedForRef.current = planKey;
    }

    wasOpenRef.current = true;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, plan?.id]);

  // Mirror every field change into sessionStorage while open, so an actual
  // remount (or simply closing without saving) never loses the draft.
  useEffect(() => {
    if (!open || !draftKey) return;
    writeDraft(draftKey, { templateId, title, description, branchId, areaAssetId, assetId, responsibleMemberId, frequency, customInterval, customUnit, startDate, nextDueAt, alertRules });
  }, [open, draftKey, templateId, title, description, branchId, areaAssetId, assetId, responsibleMemberId, frequency, customInterval, customUnit, startDate, nextDueAt, alertRules]);

  const responsibleOptions = [
    ...planners.map((p) => ({ id: p.memberId, label: `${p.name} (planner)` })),
    ...technicians.map((t) => ({ id: t.memberId, label: `${t.name} (técnico)` })),
  ];

  const beforeDueRules = alertRules.filter((r) => r.alertType === 'before_due');
  const hasOverdueRule = alertRules.some((r) => r.alertType === 'overdue');

  const addBeforeDueRule = (days: number) => {
    if (days < 0 || beforeDueRules.some((r) => r.daysBefore === days)) return;
    setAlertRules((current) => [...current, { alertType: 'before_due', daysBefore: days, label: `${days} días antes` }]);
  };

  const addCustomBeforeDueRule = () => {
    const days = Number(customDaysInput);
    if (!Number.isInteger(days) || days < 0) {
      setFormError('Los días antes deben ser un número entero mayor o igual a 0.');
      return;
    }
    if (beforeDueRules.some((r) => r.daysBefore === days)) {
      setFormError('Ya existe una alerta con esa cantidad de días.');
      return;
    }
    setFormError(null);
    addBeforeDueRule(days);
    setCustomDaysInput('');
  };

  const removeBeforeDueRule = (days: number | null) => {
    setAlertRules((current) => current.filter((r) => !(r.alertType === 'before_due' && r.daysBefore === days)));
  };

  const toggleOverdueRule = (checked: boolean) => {
    setAlertRules((current) => {
      if (checked) {
        if (current.some((r) => r.alertType === 'overdue')) return current;
        return [...current, { alertType: 'overdue', daysBefore: null, label: 'Vencido' }];
      }
      return current.filter((r) => r.alertType !== 'overdue');
    });
  };

  const handleCancel = () => {
    clearDraftStorage(draftKey);
    onOpenChange(false);
  };

  const handleSubmit = async () => {
    if (!templateId) {
      setFormError('Selecciona una plantilla.');
      return;
    }
    if (!title.trim()) {
      setFormError('El título del plan es obligatorio.');
      return;
    }
    if (!branchId && !areaAssetId && !assetId) {
      setFormError('Selecciona al menos una sede, área o activo.');
      return;
    }
    let customIntervalValue: number | null = null;
    if (frequency === 'custom') {
      customIntervalValue = Number(customInterval);
      if (!Number.isInteger(customIntervalValue) || customIntervalValue <= 0) {
        setFormError('El intervalo personalizado debe ser un número entero mayor a 0.');
        return;
      }
    }
    setFormError(null);

    const input: InspectionPlanInput = {
      templateId,
      title: title.trim(),
      description: description.trim() || null,
      branchId: branchId || null,
      areaAssetId: areaAssetId || null,
      assetId: assetId || null,
      responsibleMemberId: responsibleMemberId || null,
      frequency,
      customInterval: customIntervalValue,
      customUnit: frequency === 'custom' ? customUnit : null,
      startDate,
      nextDueAt: nextDueAt ? new Date(nextDueAt).toISOString() : null,
    };
    const ok = await onSave(input, plan?.id, alertRules);
    if (ok) {
      clearDraftStorage(draftKey);
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{plan ? 'Editar plan de inspección' : 'Nuevo plan de inspección'}</DialogTitle>
          <DialogDescription>
            Programa una plantilla de checklist sobre una sede, área y/o activo, con responsable, periodicidad y alertas.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1">
            <Label>Plantilla *</Label>
            <Select value={templateId} onValueChange={setTemplateId} disabled={saving}>
              <SelectTrigger><SelectValue placeholder={templates.length === 0 ? 'Crea una plantilla primero' : 'Selecciona plantilla'} /></SelectTrigger>
              <SelectContent className="bg-popover">
                {templates.map((template) => (
                  <SelectItem key={template.id} value={template.id}>{template.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1">
            <Label htmlFor="plan-title">Título *</Label>
            <Input id="plan-title" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Ej. Luces de emergencia — pasillo 3" disabled={saving} />
          </div>

          <div className="space-y-1">
            <Label htmlFor="plan-description">Descripción</Label>
            <Textarea id="plan-description" value={description} onChange={(e) => setDescription(e.target.value)} disabled={saving} />
          </div>

          <p className="text-xs text-muted-foreground">Selecciona al menos una sede, área o activo — pueden combinarse.</p>
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="space-y-1">
              <Label>Sede</Label>
              <Select value={branchId || 'none'} onValueChange={(v) => setBranchId(v === 'none' ? '' : v)} disabled={saving}>
                <SelectTrigger><SelectValue placeholder="Sin sede" /></SelectTrigger>
                <SelectContent className="bg-popover">
                  <SelectItem value="none">Sin sede</SelectItem>
                  {branches.map((branch) => (
                    <SelectItem key={branch.id} value={branch.id}>{branch.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Área</Label>
              <Select value={areaAssetId || 'none'} onValueChange={(v) => setAreaAssetId(v === 'none' ? '' : v)} disabled={saving}>
                <SelectTrigger><SelectValue placeholder="Sin área" /></SelectTrigger>
                <SelectContent className="bg-popover">
                  <SelectItem value="none">Sin área</SelectItem>
                  {assets.map((asset) => (
                    <SelectItem key={asset.id} value={asset.id}>{asset.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Activo</Label>
              <Select value={assetId || 'none'} onValueChange={(v) => setAssetId(v === 'none' ? '' : v)} disabled={saving}>
                <SelectTrigger><SelectValue placeholder="Sin activo" /></SelectTrigger>
                <SelectContent className="bg-popover">
                  <SelectItem value="none">Sin activo</SelectItem>
                  {assets.map((asset) => (
                    <SelectItem key={asset.id} value={asset.id}>{asset.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="space-y-1">
            <Label>Responsable</Label>
            <Select value={responsibleMemberId || 'none'} onValueChange={(v) => setResponsibleMemberId(v === 'none' ? '' : v)} disabled={saving}>
              <SelectTrigger><SelectValue placeholder="Sin asignar" /></SelectTrigger>
              <SelectContent className="bg-popover">
                <SelectItem value="none">Sin asignar</SelectItem>
                {responsibleOptions.map((option) => (
                  <SelectItem key={option.id} value={option.id}>{option.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="grid gap-3 sm:grid-cols-3">
            <div className="space-y-1">
              <Label>Periodicidad *</Label>
              <Select value={frequency} onValueChange={(v: InspectionFrequency) => setFrequency(v)} disabled={saving}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent className="bg-popover">
                  {FREQUENCY_OPTIONS.map((option) => (
                    <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label htmlFor="plan-start-date">Fecha de inicio *</Label>
              <Input id="plan-start-date" type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} disabled={saving} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="plan-next-due">Próxima inspección</Label>
              <Input id="plan-next-due" type="date" value={nextDueAt} onChange={(e) => setNextDueAt(e.target.value)} disabled={saving} />
            </div>
          </div>

          {frequency === 'custom' && (
            <div className="flex flex-wrap items-end gap-2 rounded-md border p-3">
              <span className="text-sm">Cada</span>
              <Input
                type="number"
                min={1}
                step={1}
                className="w-20"
                value={customInterval}
                onChange={(e) => setCustomInterval(e.target.value)}
                disabled={saving}
              />
              <Select value={customUnit} onValueChange={(v: InspectionCustomUnit) => setCustomUnit(v)} disabled={saving}>
                <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
                <SelectContent className="bg-popover">
                  {CUSTOM_UNIT_OPTIONS.map((option) => (
                    <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <span className="text-xs text-muted-foreground">
                Ej. "cada 45 días" o "cada 2 meses"
              </span>
            </div>
          )}

          <div className="space-y-2 rounded-md border p-3">
            <Label className="text-sm font-medium">Alertas</Label>
            <p className="text-xs text-muted-foreground">
              Notificaciones in-app para owner/admin/manager y el responsable del plan. Funciona igual para cualquier plantilla (ITSE, luces de emergencia, techos…).
            </p>

            <div className="flex flex-wrap items-center gap-2">
              {QUICK_ADD_DAYS.map((days) => {
                const active = beforeDueRules.some((r) => r.daysBefore === days);
                return (
                  <Button
                    key={days}
                    type="button"
                    variant={active ? 'default' : 'outline'}
                    size="sm"
                    disabled={saving || active}
                    onClick={() => addBeforeDueRule(days)}
                  >
                    {days} días antes
                  </Button>
                );
              })}
              <div className="flex items-center gap-1">
                <Input
                  type="number"
                  min={0}
                  step={1}
                  placeholder="Otro (días)"
                  className="w-28"
                  value={customDaysInput}
                  onChange={(e) => setCustomDaysInput(e.target.value)}
                  disabled={saving}
                />
                <Button type="button" variant="outline" size="sm" onClick={addCustomBeforeDueRule} disabled={saving || !customDaysInput}>
                  <Plus className="h-3.5 w-3.5" /> Agregar alerta
                </Button>
              </div>
            </div>

            {beforeDueRules.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {beforeDueRules
                  .slice()
                  .sort((a, b) => (b.daysBefore ?? 0) - (a.daysBefore ?? 0))
                  .map((rule) => (
                    <Badge key={rule.daysBefore} variant="secondary" className="flex items-center gap-1">
                      {rule.label || `${rule.daysBefore} días antes`}
                      <button type="button" onClick={() => removeBeforeDueRule(rule.daysBefore)} disabled={saving} aria-label={`Quitar alerta ${rule.daysBefore} días antes`}>
                        <X className="h-3 w-3" />
                      </button>
                    </Badge>
                  ))}
              </div>
            )}

            <div className="flex items-center gap-2 pt-1">
              <Checkbox id="plan-alert-overdue" checked={hasOverdueRule} onCheckedChange={(checked) => toggleOverdueRule(checked === true)} disabled={saving} />
              <Label htmlFor="plan-alert-overdue" className="cursor-pointer text-sm font-normal">Avisar cuando esté vencido</Label>
            </div>
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={handleCancel} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving || templates.length === 0}>
              {saving ? 'Guardando…' : 'Guardar plan'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
