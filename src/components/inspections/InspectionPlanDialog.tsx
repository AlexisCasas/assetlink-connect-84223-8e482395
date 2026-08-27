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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useOrganizationTechnicians } from '@/hooks/useOrganizationTechnicians';
import { useOrganizationPlanners } from '@/hooks/useOrganizationPlanners';
import type { ChecklistTemplate } from '@/types/checklist';
import type { Asset } from '@/types/asset';
import type { ClientBranch } from '@/types/request';
import type { InspectionFrequency, InspectionPlan, InspectionPlanInput } from '@/types/inspection';

interface InspectionPlanDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  organizationId: string | null | undefined;
  templates: ChecklistTemplate[];
  branches: ClientBranch[];
  assets: Asset[];
  plan: InspectionPlan | null;
  saving: boolean;
  onSave: (input: InspectionPlanInput, planId: string | undefined) => Promise<boolean>;
}

const FREQUENCY_OPTIONS: { value: InspectionFrequency; label: string }[] = [
  { value: 'one_time', label: 'Única vez' },
  { value: 'daily', label: 'Diaria' },
  { value: 'weekly', label: 'Semanal' },
  { value: 'monthly', label: 'Mensual' },
  { value: 'quarterly', label: 'Trimestral' },
  { value: 'semiannual', label: 'Semestral' },
  { value: 'annual', label: 'Anual' },
];

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
  startDate: string;
  nextDueAt: string;
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
  startDate: new Date().toISOString().slice(0, 10),
  nextDueAt: '',
});

const draftFromPlan = (plan: InspectionPlan | null): PlanDraft => ({
  templateId: plan?.templateId ?? '',
  title: plan?.title ?? '',
  description: plan?.description ?? '',
  branchId: plan?.branchId ?? '',
  areaAssetId: plan?.areaAssetId ?? '',
  assetId: plan?.assetId ?? '',
  responsibleMemberId: plan?.responsibleMemberId ?? '',
  frequency: plan?.frequency ?? 'one_time',
  startDate: plan?.startDate ?? new Date().toISOString().slice(0, 10),
  nextDueAt: toDateInputValue(plan?.nextDueAt ?? null),
});

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
 * Bug fix (see feature/generic-checklists-inspections follow-up): this
 * form used to reset to defaults whenever the *tab regained focus* — not a
 * bug in this file's own effect logic alone, but that effect's dependency
 * on `templates` combined with the caller passing a freshly-`.filter()`ed
 * array on every render (fixed in InspectionsView.tsx too) meant any
 * unrelated re-render (e.g. Supabase Auth's token refresh on window focus)
 * re-ran the reset. Two independent hardenings now:
 *   1. Initialization only happens on an explicit closed→open transition or
 *      when the *id* of the edited plan changes — never merely because a
 *      prop array/object got a new reference. Tracked via refs, not deps.
 *   2. The in-progress draft is mirrored into sessionStorage (keyed by
 *      organization + plan id, or "new") while the dialog is open, and
 *      restored on the next open if the form was never saved/cancelled —
 *      so even an actual remount cannot silently lose typed data.
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
  const [startDate, setStartDate] = useState('');
  const [nextDueAt, setNextDueAt] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  const wasOpenRef = useRef(false);
  const initializedForRef = useRef<string | null>(null);

  const draftKey = draftStorageKey(organizationId, plan);

  // Initialize ONLY on a closed→open transition, or when the id of the
  // plan being edited actually changes while open — deliberately keyed off
  // `plan?.id` (a primitive), not `plan` itself or `templates`/`branches`/
  // `assets`/technician-planner lists, so a background refetch that
  // produces new array/object references can never wipe the draft.
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
      setStartDate(next.startDate);
      setNextDueAt(next.nextDueAt);
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
    writeDraft(draftKey, { templateId, title, description, branchId, areaAssetId, assetId, responsibleMemberId, frequency, startDate, nextDueAt });
  }, [open, draftKey, templateId, title, description, branchId, areaAssetId, assetId, responsibleMemberId, frequency, startDate, nextDueAt]);

  const responsibleOptions = [
    ...planners.map((p) => ({ id: p.memberId, label: `${p.name} (planner)` })),
    ...technicians.map((t) => ({ id: t.memberId, label: `${t.name} (técnico)` })),
  ];

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
      startDate,
      nextDueAt: nextDueAt ? new Date(nextDueAt).toISOString() : null,
    };
    const ok = await onSave(input, plan?.id);
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
            Programa una plantilla de checklist sobre una sede, área y/o activo, con responsable y periodicidad.
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
