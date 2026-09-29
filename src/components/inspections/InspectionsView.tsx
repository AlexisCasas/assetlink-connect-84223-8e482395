import { useEffect, useMemo, useRef, useState } from 'react';
import { ClipboardCheck, ListChecks, Plus, Pencil, EyeOff, Eye, CalendarClock, PlayCircle, History } from 'lucide-react';
import { useAssets } from '@/hooks/useAssets';
import { useDirectInspectionScope, type InspectionScope } from '@/hooks/useInspectionScope';
import { useFacilityManagementInspectionTargets } from '@/hooks/useFacilityManagementReferenceDirectories';
import { useChecklistTemplates } from '@/hooks/useChecklistTemplates';
import { useInspectionPlans } from '@/hooks/useInspectionPlans';
import { useInspectionRuns } from '@/hooks/useInspectionRuns';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useToast } from '@/hooks/use-toast';
import { ChecklistTemplateEditorDialog } from './ChecklistTemplateEditorDialog';
import { ChecklistItemEditorDialog } from './ChecklistItemEditorDialog';
import { ChecklistOptionEditorDialog } from './ChecklistOptionEditorDialog';
import { InspectionPlanDialog } from './InspectionPlanDialog';
import { InspectionRunDialog } from './InspectionRunDialog';
import type { ChecklistTemplate, ChecklistTemplateItem, ChecklistResponseOption } from '@/types/checklist';
import type { InspectionPlan } from '@/types/inspection';

const FREQUENCY_LABELS: Record<string, string> = {
  one_time: 'Única vez',
  daily: 'Diaria', // legacy value, never offered as a choice in the form
  weekly: 'Semanal',
  monthly: 'Mensual',
  quarterly: 'Trimestral',
  semiannual: 'Semestral',
  annual: 'Anual',
  custom: 'Personalizada',
};

const CUSTOM_UNIT_LABELS: Record<string, string> = {
  days: 'días',
  weeks: 'semanas',
  months: 'meses',
  years: 'años',
};

const frequencyDisplay = (plan: InspectionPlan) => plan.frequency === 'custom' && plan.customInterval != null && plan.customUnit
  ? `Cada ${plan.customInterval} ${CUSTOM_UNIT_LABELS[plan.customUnit] ?? plan.customUnit}`
  : FREQUENCY_LABELS[plan.frequency] ?? plan.frequency;

const alertRulesDisplay = (plan: InspectionPlan): string => {
  if (plan.alertRules.length === 0) return 'Sin alertas configuradas';
  const beforeDue = plan.alertRules
    .filter((rule) => rule.alertType === 'before_due')
    .sort((a, b) => (b.daysBefore ?? 0) - (a.daysBefore ?? 0))
    .map((rule) => `${rule.daysBefore}d`);
  const hasOverdue = plan.alertRules.some((rule) => rule.alertType === 'overdue');
  return [...beforeDue, ...(hasOverdue ? ['Vencido'] : [])].join(', ');
};

// A delegated FM never receives a name derived from an email: when the
// client assigned someone without a display name, only that fact is shown.
const responsibleLabel = (item: { hasResponsible: boolean; responsibleName: string | null }) =>
  item.responsibleName ?? (item.hasResponsible ? 'asignado por el cliente' : null);

const STATUS_LABELS: Record<string, string> = {
  scheduled: 'Programada',
  in_progress: 'En progreso',
  completed: 'Completada',
  cancelled: 'Cancelada',
  overdue: 'Vencida',
};

const RESULT_LABELS: Record<string, string> = {
  passed: 'Conforme',
  failed: 'No conforme',
  not_applicable: 'No aplica',
};

const resultBadgeVariant = (result: string | null) => {
  if (result === 'failed') return 'destructive' as const;
  if (result === 'passed') return 'secondary' as const;
  return 'outline' as const;
};

const formatDate = (value: string | null) => value ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '—';

/**
 * Generic checklist/inspection engine. ITSE is never a module here — it is
 * just one row a client_company organization can create under "Plantillas"
 * ("Plantilla ITSE"), same as any other checklist (techos, gerencial,
 * preventivo, auditoría interna, luces de emergencia…). See
 * docs/GENERIC_CHECKLISTS_INSPECTIONS.md.
 */
interface InspectionsViewProps {
  /** Deep-link target from a notification — e.g. inspection_due_soon_future/
   * inspection_overdue_future resolve to metadata.plan_id, never
   * notification.entity_id (that one is a synthetic dedup key, see
   * docs/NOTIFICATION_DEEP_LINKS.md). Dashboard parses the hash and passes
   * these down; this component never reads window.location.hash itself. */
  focusPlanId?: string;
  focusRunId?: string;
  /** Omitted: direct mode (the active client organization, historic rules).
   * Delegated Facility Manager mode passes the operated client's scope. */
  scope?: InspectionScope;
}

export function InspectionsView({ focusPlanId, focusRunId, scope: explicitScope }: InspectionsViewProps = {}) {
  const directScope = useDirectInspectionScope();
  const scope = explicitScope ?? directScope;
  const isDelegated = scope.mode === 'facility_manager';
  const canPlanWork = scope.canPlan;
  const { toast } = useToast();

  const organizationId = scope.canView ? scope.organizationId ?? undefined : undefined;
  const { templates, saving: templateSaving, error: templateError, saveTemplate, saveItem, toggleItemActive, saveOption, toggleOptionActive } = useChecklistTemplates(organizationId);
  // Direct: the active client's own assets/branches (unchanged). Delegated:
  // useAssets() stays disabled (the active org is the FM) and planning uses
  // the minimal target directory instead — inspections never imply assets.view.
  const directAssets = useAssets();
  const delegatedTargets = useFacilityManagementInspectionTargets(isDelegated && canPlanWork ? scope.organizationId : null);
  const assets = isDelegated ? delegatedTargets.assets : directAssets.assets;
  const branches = isDelegated ? delegatedTargets.branches : directAssets.branches;
  const { plans, loading: plansLoading, saving: planSaving, error: planError, savePlanWithAlertRules, createRunFromPlan } = useInspectionPlans(organizationId);
  const { runs, saving: runSaving, error: runError, loadRunDetail, submitRun, refresh: refreshRuns } = useInspectionRuns(organizationId);

  const [activeTab, setActiveTab] = useState<string>(scope.preferRunsTab ? 'runs' : 'templates');

  const [templateDialogOpen, setTemplateDialogOpen] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<ChecklistTemplate | null>(null);
  const [itemDialogOpen, setItemDialogOpen] = useState(false);
  const [editingItem, setEditingItem] = useState<ChecklistTemplateItem | null>(null);
  const [itemTemplate, setItemTemplate] = useState<ChecklistTemplate | null>(null);
  const [optionDialogOpen, setOptionDialogOpen] = useState(false);
  const [editingOption, setEditingOption] = useState<ChecklistResponseOption | null>(null);
  const [optionTemplate, setOptionTemplate] = useState<ChecklistTemplate | null>(null);

  const [planDialogOpen, setPlanDialogOpen] = useState(false);
  const [editingPlan, setEditingPlan] = useState<InspectionPlan | null>(null);

  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const [activeRunId, setActiveRunId] = useState<string | null>(null);

  // Memoized so this only produces a new array reference when `templates`
  // itself actually changes — an inline `.filter()` in the JSX below would
  // create a fresh array on every render of InspectionsView (including
  // ones with no real data change, e.g. an auth token refresh on window
  // focus re-rendering the tree), which fed straight into
  // InspectionPlanDialog's reset effect and wiped the in-progress draft.
  const activeTemplates = useMemo(() => templates.filter((t) => t.isActive), [templates]);

  // Guards against reprocessing the same focus target on every render — only
  // acts again if the deep link target itself changes. Placed before the
  // `!currentOrganization` early return below (Rules of Hooks: every hook in
  // this component must run on every render, including the one where that
  // return fires) and uses the state setters directly rather than
  // openEditPlan/openRun, which are only defined further down.
  const processedFocusKeyRef = useRef<string | null>(null);
  useEffect(() => {
    if (focusRunId) {
      const key = `run:${focusRunId}`;
      if (processedFocusKeyRef.current === key) return;
      processedFocusKeyRef.current = key;
      setActiveTab('runs');
      // InspectionRunDialog loads the run directly via loadRunDetail(runId)
      // (its own RLS-scoped query) — no need to wait for the `runs` list.
      setActiveRunId(focusRunId);
      setRunDialogOpen(true);
      return;
    }

    if (focusPlanId) {
      if (plansLoading) return;
      const key = `plan:${focusPlanId}`;
      if (processedFocusKeyRef.current === key) return;
      processedFocusKeyRef.current = key;
      setActiveTab('plans');
      const plan = plans.find((p) => p.id === focusPlanId);
      if (plan) {
        setEditingPlan(plan);
        setPlanDialogOpen(true);
      } else {
        toast({
          title: 'No se pudo abrir el plan de inspección',
          description: 'Puede haber sido eliminado o ya no tienes acceso.',
          variant: 'destructive',
        });
      }
    }
  }, [focusPlanId, focusRunId, plansLoading, plans, toast]);

  if (!scope.organizationId) {
    return <EmptyState message="Sin organización asignada" />;
  }
  if (!scope.canView) {
    return <EmptyState message="No tienes acceso a las inspecciones de esta organización." />;
  }

  const openCreateTemplate = () => { setEditingTemplate(null); setTemplateDialogOpen(true); };
  const openEditTemplate = (template: ChecklistTemplate) => { setEditingTemplate(template); setTemplateDialogOpen(true); };
  const openCreateItem = (template: ChecklistTemplate) => { setItemTemplate(template); setEditingItem(null); setItemDialogOpen(true); };
  const openEditItem = (template: ChecklistTemplate, item: ChecklistTemplateItem) => { setItemTemplate(template); setEditingItem(item); setItemDialogOpen(true); };
  const openCreateOption = (template: ChecklistTemplate) => { setOptionTemplate(template); setEditingOption(null); setOptionDialogOpen(true); };
  const openEditOption = (template: ChecklistTemplate, option: ChecklistResponseOption) => { setOptionTemplate(template); setEditingOption(option); setOptionDialogOpen(true); };

  const openCreatePlan = () => { setEditingPlan(null); setPlanDialogOpen(true); };
  const openEditPlan = (plan: InspectionPlan) => { setEditingPlan(plan); setPlanDialogOpen(true); };

  const handleCreateRun = async (planId: string) => {
    const runId = await createRunFromPlan(planId);
    if (runId) {
      toast({ title: 'Ejecución creada', description: 'Se creó una nueva ejecución para este plan.' });
      await refreshRuns();
    } else {
      toast({ title: 'No se pudo crear la ejecución', description: planError ?? 'Intenta nuevamente.', variant: 'destructive' });
    }
  };

  const openRun = (runId: string) => { setActiveRunId(runId); setRunDialogOpen(true); };

  const nextItemSequence = (template: ChecklistTemplate | null) => (!template || template.items.length === 0 ? 1 : Math.max(...template.items.map((i) => i.sequence)) + 1);
  const nextOptionSequence = (template: ChecklistTemplate | null) => (!template || template.responseOptions.length === 0 ? 1 : Math.max(...template.responseOptions.map((o) => o.sequence)) + 1);

  // Direct technician: only runs assigned to their client membership. A
  // delegated FM technician is scoped by the relationship assignment instead.
  const visibleRuns = scope.runsResponsibleMemberId
    ? runs.filter((run) => run.responsibleMemberId === scope.runsResponsibleMemberId)
    : runs;

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="text-2xl font-semibold">Inspecciones</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Motor genérico de checklists e inspecciones — ITSE es solo una plantilla más, no un módulo aparte.
        </p>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="templates">Plantillas</TabsTrigger>
          <TabsTrigger value="plans">Programación</TabsTrigger>
          <TabsTrigger value="runs">Ejecuciones / Historial</TabsTrigger>
        </TabsList>

        {/* ---------------------------------------------------------------- Plantillas */}
        <TabsContent value="templates" className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Parámetros, ítems y opciones de respuesta por plantilla.</p>
            {canPlanWork && (
              <Button onClick={openCreateTemplate}>
                <Plus className="mr-2 h-4 w-4" /> Crear plantilla
              </Button>
            )}
          </div>

          {templateError && <p className="text-sm text-destructive">{templateError}</p>}

          {templates.length === 0 ? (
            <Card>
              <CardContent className="flex min-h-48 flex-col items-center justify-center gap-2 text-center">
                <ClipboardCheck className="h-8 w-8 text-muted-foreground" />
                <p className="font-medium">Aún no hay plantillas de checklist.</p>
                <p className="text-sm text-muted-foreground">Crea una plantilla como "Inspección de luces de emergencia".</p>
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-4">
              {templates.map((template) => (
                <Card key={template.id} className={!template.isActive ? 'opacity-60' : undefined}>
                  <CardHeader className="flex flex-row items-start justify-between space-y-0">
                    <div>
                      <CardTitle className="flex items-center gap-2 text-base">
                        <ListChecks className="h-4 w-4 text-muted-foreground" /> {template.name}
                        {template.category && <Badge variant="outline">{template.category}</Badge>}
                        {!template.isActive && <Badge variant="outline">Inactiva</Badge>}
                      </CardTitle>
                      {template.description && <p className="mt-1 text-sm text-muted-foreground">{template.description}</p>}
                    </div>
                    {canPlanWork && (
                      <div className="flex shrink-0 items-center gap-2">
                        <Button variant="ghost" size="icon" onClick={() => openEditTemplate(template)} title="Editar plantilla">
                          <Pencil className="h-4 w-4" />
                        </Button>
                      </div>
                    )}
                  </CardHeader>
                  <CardContent className="space-y-4">
                    <div>
                      <div className="mb-2 flex items-center justify-between">
                        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Ítems</p>
                        {canPlanWork && (
                          <Button variant="outline" size="sm" onClick={() => openCreateItem(template)}>
                            <Plus className="mr-1 h-3.5 w-3.5" /> Ítem
                          </Button>
                        )}
                      </div>
                      {template.items.length === 0 ? (
                        <p className="text-sm text-muted-foreground">Sin ítems todavía.</p>
                      ) : (
                        <div className="space-y-1.5">
                          {template.items.map((item) => (
                            <div key={item.id} className={`flex items-center justify-between rounded-md border p-2 text-sm ${!item.isActive ? 'opacity-60' : ''}`}>
                              <span>{item.question}{item.section && <span className="ml-2 text-xs text-muted-foreground">({item.section})</span>}</span>
                              <div className="flex items-center gap-2">
                                {item.isRequired && <Badge variant="secondary" className="text-xs">Obligatorio</Badge>}
                                {!item.isActive && <Badge variant="outline" className="text-xs">Inactivo</Badge>}
                                {canPlanWork && (
                                  <>
                                    <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openEditItem(template, item)}><Pencil className="h-3.5 w-3.5" /></Button>
                                    <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => void toggleItemActive(item.id, !item.isActive)}>
                                      {item.isActive ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                                    </Button>
                                  </>
                                )}
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>

                    <div>
                      <div className="mb-2 flex items-center justify-between">
                        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Opciones de respuesta</p>
                        {canPlanWork && (
                          <Button variant="outline" size="sm" onClick={() => openCreateOption(template)}>
                            <Plus className="mr-1 h-3.5 w-3.5" /> Opción
                          </Button>
                        )}
                      </div>
                      {template.responseOptions.length === 0 ? (
                        <p className="text-sm text-muted-foreground">Sin opciones todavía (ej. Cumple / No cumple / No aplica).</p>
                      ) : (
                        <div className="space-y-1.5">
                          {template.responseOptions.map((option) => (
                            <div key={option.id} className={`flex items-center justify-between rounded-md border p-2 text-sm ${!option.isActive ? 'opacity-60' : ''}`}>
                              <span>{option.label}</span>
                              <div className="flex items-center gap-2">
                                {option.isFailure && <Badge variant="destructive" className="text-xs">No conformidad</Badge>}
                                {!option.isActive && <Badge variant="outline" className="text-xs">Inactiva</Badge>}
                                {canPlanWork && (
                                  <>
                                    <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openEditOption(template, option)}><Pencil className="h-3.5 w-3.5" /></Button>
                                    <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => void toggleOptionActive(option.id, !option.isActive)}>
                                      {option.isActive ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                                    </Button>
                                  </>
                                )}
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </TabsContent>

        {/* ---------------------------------------------------------------- Programación */}
        <TabsContent value="plans" className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Planes recurrentes sobre sede/área/activo.</p>
            {canPlanWork && (
              <Button onClick={openCreatePlan} disabled={templates.length === 0}>
                <Plus className="mr-2 h-4 w-4" /> Crear plan
              </Button>
            )}
          </div>

          {planError && <p className="text-sm text-destructive">{planError}</p>}

          {plans.length === 0 ? (
            <Card>
              <CardContent className="flex min-h-40 flex-col items-center justify-center gap-2 text-center">
                <CalendarClock className="h-8 w-8 text-muted-foreground" />
                <p className="font-medium">Aún no hay planes de inspección.</p>
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-2">
              {plans.map((plan) => (
                <Card key={plan.id} className={!plan.isActive ? 'opacity-60' : undefined}>
                  <CardContent className="flex flex-wrap items-center justify-between gap-3 py-4">
                    <div className="min-w-0">
                      <p className="font-medium">{plan.title}</p>
                      <p className="text-xs text-muted-foreground">
                        {plan.templateName} · {[plan.branchName, plan.areaAssetName, plan.assetName].filter(Boolean).join(' / ') || 'Sin destino'}
                        {responsibleLabel(plan) && ` · Responsable: ${responsibleLabel(plan)}`}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {frequencyDisplay(plan)} · Próxima: {formatDate(plan.nextDueAt)}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Alertas: {alertRulesDisplay(plan)}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      {!plan.isActive && <Badge variant="outline">Inactivo</Badge>}
                      {canPlanWork && (
                        <Button variant="ghost" size="icon" onClick={() => openEditPlan(plan)} title="Editar plan"><Pencil className="h-4 w-4" /></Button>
                      )}
                      {scope.canExecute && (
                        <Button variant="outline" size="sm" onClick={() => void handleCreateRun(plan.id)} disabled={runSaving}>
                          <PlayCircle className="mr-1 h-3.5 w-3.5" /> Crear ejecución
                        </Button>
                      )}
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </TabsContent>

        {/* ---------------------------------------------------------------- Ejecuciones / Historial */}
        <TabsContent value="runs" className="space-y-4">
          {runError && <p className="text-sm text-destructive">{runError}</p>}

          {visibleRuns.length === 0 ? (
            <Card>
              <CardContent className="flex min-h-40 flex-col items-center justify-center gap-2 text-center">
                <History className="h-8 w-8 text-muted-foreground" />
                <p className="font-medium">{scope.runsResponsibleMemberId ? 'No tienes inspecciones asignadas.' : 'Aún no hay ejecuciones registradas.'}</p>
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-2">
              {visibleRuns.map((run) => (
                <Card key={run.id}>
                  <CardContent className="flex flex-wrap items-center justify-between gap-3 py-4">
                    <div className="min-w-0">
                      <p className="font-medium">{run.templateName}</p>
                      <p className="text-xs text-muted-foreground">
                        {[run.branchName, run.areaAssetName, run.assetName].filter(Boolean).join(' / ') || 'Sin destino'}
                        {responsibleLabel(run) && ` · Responsable: ${responsibleLabel(run)}`}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Programada: {formatDate(run.scheduledFor)}{run.completedAt && ` · Completada: ${formatDate(run.completedAt)}`}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      <Badge variant="outline">{STATUS_LABELS[run.status] ?? run.status}</Badge>
                      {run.result && <Badge variant={resultBadgeVariant(run.result)}>{RESULT_LABELS[run.result] ?? run.result}</Badge>}
                      {run.status === 'completed' || !scope.canExecute ? (
                        <Button variant="outline" size="sm" onClick={() => openRun(run.id)}>Ver detalle</Button>
                      ) : (
                        <Button variant="outline" size="sm" onClick={() => openRun(run.id)}>Ejecutar</Button>
                      )}
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </TabsContent>
      </Tabs>

      {canPlanWork && (
        <>
          <ChecklistTemplateEditorDialog
            open={templateDialogOpen}
            onOpenChange={setTemplateDialogOpen}
            template={editingTemplate}
            saving={templateSaving}
            onSave={(input, id) => saveTemplate(input, id)}
          />
          <ChecklistItemEditorDialog
            open={itemDialogOpen}
            onOpenChange={setItemDialogOpen}
            templateId={itemTemplate?.id ?? null}
            templateName={itemTemplate?.name ?? ''}
            item={editingItem}
            nextSequence={nextItemSequence(itemTemplate)}
            saving={templateSaving}
            onSave={(input, id) => saveItem(input, id)}
          />
          <ChecklistOptionEditorDialog
            open={optionDialogOpen}
            onOpenChange={setOptionDialogOpen}
            templateId={optionTemplate?.id ?? null}
            templateName={optionTemplate?.name ?? ''}
            option={editingOption}
            nextSequence={nextOptionSequence(optionTemplate)}
            saving={templateSaving}
            onSave={(input, id) => saveOption(input, id)}
          />
          <InspectionPlanDialog
            open={planDialogOpen}
            onOpenChange={setPlanDialogOpen}
            organizationId={scope.canChooseResponsible ? organizationId : null}
            draftScopeKey={scope.draftScopeKey}
            canChooseResponsible={scope.canChooseResponsible}
            showHistoricTargets={isDelegated}
            templates={activeTemplates}
            branches={branches}
            assets={assets}
            plan={editingPlan}
            saving={planSaving}
            onSave={(input, id, rules) => savePlanWithAlertRules(input, id, rules)}
          />
        </>
      )}

      <InspectionRunDialog
        open={runDialogOpen}
        onOpenChange={setRunDialogOpen}
        runId={activeRunId}
        readOnly={!scope.canExecute}
        allowMaintenanceNotices={scope.canReportMaintenanceNotices}
        noticeAssetDirectoryClientId={scope.maintenanceNoticeAssetDirectoryClientId}
        loadRunDetail={loadRunDetail}
        saving={runSaving}
        onSave={submitRun}
        onSaved={() => toast({ title: 'Inspección guardada', description: 'La ejecución se registró correctamente.' })}
      />
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <div className="p-6">
      <Card><CardContent className="flex min-h-56 flex-col items-center justify-center gap-3 text-center">
        <ClipboardCheck className="h-10 w-10 text-muted-foreground" />
        <p className="font-medium">{message}</p>
      </CardContent></Card>
    </div>
  );
}
