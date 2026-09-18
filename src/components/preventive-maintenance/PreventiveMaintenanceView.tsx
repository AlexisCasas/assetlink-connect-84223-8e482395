import { useEffect, useRef, useState } from 'react';
import { CalendarClock, ClipboardList, Gauge, Plus, SkipForward, Wrench } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Textarea } from '@/components/ui/textarea';
import { useAuth } from '@/contexts/AuthContext';
import { useAssetMeters } from '@/hooks/useAssetMeters';
import { useInventoryCatalog } from '@/hooks/useInventoryCatalog';
import { useOrganizationPlanners } from '@/hooks/useOrganizationPlanners';
import { usePreventiveMaintenance } from '@/hooks/usePreventiveMaintenance';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import type { Database } from '@/integrations/supabase/types';
import type {
  MaintenanceCard,
  MaintenanceCardDraft,
  PreventiveFrequency,
  PreventiveOccurrence,
  PreventivePlan,
  PreventivePlanDraft,
} from '@/types/preventiveMaintenance';
import { AssetMetersPanel } from './AssetMetersPanel';
import { PreventiveRequestDialog } from './PreventiveRequestDialog';

type AssetOption = Pick<Database['public']['Tables']['assets']['Row'], 'id' | 'name' | 'code' | 'status'>;

const frequencyLabels: Record<PreventiveFrequency, string> = {
  weekly: 'Semanal', monthly: 'Mensual', quarterly: 'Trimestral', semiannual: 'Semestral', annual: 'Anual', custom: 'Personalizada',
};
const timingLabels = { upcoming: 'Próximo', due: 'Por atender', overdue: 'Vencido', no_reading: 'Sin lectura de medidor' } as const;
const statusLabels = { open: 'Abierta', planned: 'Planificada', completed: 'Completada', skipped: 'Omitida', cancelled: 'Cancelada' } as const;
type PreventiveTab = 'cards' | 'plans' | 'occurrences' | 'meters';

const emptyCard = (): MaintenanceCardDraft => ({ code: '', name: '', description: '', category: '', estimatedHours: null, procedureNotes: '', safetyNotes: '', tasks: [], materials: [] });
const emptyPlan = (): PreventivePlanDraft => ({ assetId: '', cardId: '', triggerType: 'calendar', priority: 'medium', defaultRequestType: 'internal', responsibleMemberId: null, planningLeadDays: 30, frequency: 'monthly', firstDueAt: '', meterId: null, intervalValue: null, baselineReadingId: null, meterLeadValue: 0 });
const datetimeLocal = (value: string | null) => value ? new Date(new Date(value).getTime() - new Date(value).getTimezoneOffset() * 60000).toISOString().slice(0, 16) : '';

export function PreventiveMaintenanceView({ focusPlanId, focusOccurrenceId, focusAssetId }: { focusPlanId?: string; focusOccurrenceId?: string; focusAssetId?: string }) {
  const { currentOrganization, currentMembership } = useAuth();
  const organizationId = currentOrganization?.id;
  const canManage = currentOrganization?.organizationType === 'client_company' && !!currentMembership?.isActive && ['owner', 'admin', 'manager'].includes(currentMembership.role);
  const state = usePreventiveMaintenance(organizationId);
  const { catalog } = useInventoryCatalog(organizationId);
  const { planners } = useOrganizationPlanners(canManage ? organizationId : null);
  const { toast } = useToast();
  const [assets, setAssets] = useState<AssetOption[]>([]);
  const [cardOpen, setCardOpen] = useState(false);
  const [editingCard, setEditingCard] = useState<MaintenanceCard | null>(null);
  const [cardDraft, setCardDraft] = useState<MaintenanceCardDraft>(emptyCard());
  const [planOpen, setPlanOpen] = useState(false);
  const [editingPlan, setEditingPlan] = useState<PreventivePlan | null>(null);
  const [planDraft, setPlanDraft] = useState<PreventivePlanDraft>(emptyPlan());
  const [planningOccurrence, setPlanningOccurrence] = useState<PreventiveOccurrence | null>(null);
  const [meterAssetId, setMeterAssetId] = useState('');
  const [activeTab, setActiveTab] = useState<PreventiveTab>(() => focusOccurrenceId ? 'occurrences' : focusPlanId || focusAssetId ? 'plans' : 'cards');
  const planMeters = useAssetMeters(planDraft.assetId);
  const handledCreateAssetRef = useRef<string | null>(null);

  useEffect(() => {
    if (!organizationId) { setAssets([]); return; }
    void supabase.from('assets').select('id,name,code,status').eq('organization_id', organizationId).neq('status', 'archived').order('name').then(({ data }) => setAssets(data ?? []));
  }, [organizationId]);

  useEffect(() => {
    if (focusOccurrenceId) setActiveTab('occurrences');
    else if (focusPlanId || focusAssetId) setActiveTab('plans');
  }, [focusAssetId, focusOccurrenceId, focusPlanId]);

  useEffect(() => {
    if (!focusAssetId || !canManage || handledCreateAssetRef.current === focusAssetId) return;
    if (!assets.some((asset) => asset.id === focusAssetId)) return;
    handledCreateAssetRef.current = focusAssetId;
    setActiveTab('plans');
    setEditingPlan(null);
    setPlanDraft({ ...emptyPlan(), assetId: focusAssetId });
    setPlanOpen(true);
  }, [assets, canManage, focusAssetId]);

  const focusedPlan = focusPlanId ? state.plans.find((plan) => plan.id === focusPlanId) : null;
  const focusedOccurrence = focusOccurrenceId ? state.occurrences.find((occurrence) => occurrence.id === focusOccurrenceId) : null;
  const planningPlan = planningOccurrence ? state.plans.find((plan) => plan.id === planningOccurrence.plan_id) ?? null : null;

  if (currentOrganization?.organizationType !== 'client_company') {
    return <div className="flex h-full items-center justify-center p-6 text-sm text-muted-foreground">Mantenimiento preventivo se administra desde una organización cliente.</div>;
  }

  const openCard = (card?: MaintenanceCard) => {
    setEditingCard(card ?? null);
    setCardDraft(card ? {
      code: card.code, name: card.name, description: card.description ?? '', category: card.category ?? '', estimatedHours: card.estimated_hours,
      procedureNotes: card.procedure_notes ?? '', safetyNotes: card.safety_notes ?? '',
      tasks: card.tasks.map((task) => ({ ...task })), materials: card.materials.map((material) => ({ ...material })),
    } : emptyCard());
    setCardOpen(true);
  };

  const saveCard = async () => {
    const ok = await state.saveCard(cardDraft, editingCard?.id);
    if (ok) { setCardOpen(false); toast({ title: editingCard ? 'Ficha actualizada' : 'Ficha creada' }); }
  };

  const openPlan = (plan?: PreventivePlan) => {
    setEditingPlan(plan ?? null);
    setPlanDraft(plan ? {
      assetId: plan.asset_id, cardId: plan.card_id, triggerType: plan.trigger_type, priority: plan.priority,
      defaultRequestType: plan.default_request_type, responsibleMemberId: plan.responsible_member_id,
      planningLeadDays: plan.planning_lead_days, frequency: plan.frequency, customInterval: plan.custom_interval,
      customUnit: plan.custom_unit, firstDueAt: datetimeLocal(plan.first_due_at), meterId: plan.meter_id,
      intervalValue: plan.interval_value, baselineReadingId: plan.baseline_reading_id, meterLeadValue: plan.meter_lead_value,
    } : emptyPlan());
    setPlanOpen(true);
  };

  const savePlan = async () => {
    const payload = { ...planDraft, firstDueAt: planDraft.firstDueAt ? new Date(planDraft.firstDueAt).toISOString() : null };
    const ok = await state.savePlan(payload, editingPlan?.id);
    if (ok) { setPlanOpen(false); toast({ title: editingPlan ? 'Plan actualizado' : 'Plan creado', description: editingPlan ? 'El ciclo vigente no fue desplazado.' : 'Se creó también la ocurrencia #1.' }); }
  };

  const skip = async (occurrence: PreventiveOccurrence) => {
    const reason = window.prompt('Motivo obligatorio para omitir este ciclo:');
    if (!reason) return;
    if (await state.skipOccurrence(occurrence.id, reason)) toast({ title: 'Ciclo omitido', description: 'El siguiente ciclo conserva la cadencia original.' });
  };

  const togglePlan = async (plan: PreventivePlan) => {
    let reason: string | undefined;
    if (plan.is_active) {
      const entered = window.prompt('Motivo de desactivación:');
      if (!entered) return;
      reason = entered;
    }
    await state.setPlanActive(plan.id, !plan.is_active, reason);
  };

  const renderDue = (occurrence: PreventiveOccurrence, plan?: PreventivePlan) => occurrence.due_at
    ? new Date(occurrence.due_at).toLocaleString()
    : `${occurrence.due_meter_value ?? '—'} ${plan?.meter_unit ?? ''}`;

  return (
    <div className="space-y-5 p-6">
      <div><h1 className="text-2xl font-semibold">Mantenimiento preventivo</h1><p className="text-sm text-muted-foreground">Fichas reutilizables, planes recurrentes y ciclos trazables hasta la orden de trabajo.</p></div>
      {state.error && <p className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">{state.error}</p>}
      {focusedPlan && <p className="rounded-md border border-onefacility-blue/30 bg-onefacility-blue/5 p-3 text-sm">Enlace abierto: {focusedPlan.card_code} · {focusedPlan.asset_name}</p>}
      {!state.loading && focusPlanId && !focusedPlan && <p className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">El plan del enlace no existe o no está disponible en esta organización.</p>}
      {!state.loading && focusOccurrenceId && !focusedOccurrence && <p className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">La ocurrencia del enlace no existe o no está disponible en esta organización.</p>}

      <Tabs value={activeTab} onValueChange={(value) => setActiveTab(value as PreventiveTab)} className="space-y-4">
        <TabsList><TabsTrigger value="cards">Cartillas</TabsTrigger><TabsTrigger value="plans">Planes</TabsTrigger><TabsTrigger value="occurrences">Próximos / Pendientes</TabsTrigger><TabsTrigger value="meters">Medidores</TabsTrigger></TabsList>

        <TabsContent value="plans" className="space-y-3">
          <div className="flex justify-end">{canManage && <Button onClick={() => openPlan()}><Plus className="mr-2 h-4 w-4" />Nuevo plan</Button>}</div>
          {state.loading ? <p>Cargando…</p> : state.plans.length === 0 ? <Empty text="Aún no hay planes preventivos." /> : state.plans.map((plan) => (
            <Card key={plan.id} className={focusedPlan?.id === plan.id ? 'ring-2 ring-onefacility-blue' : ''}><CardContent className="flex flex-col gap-3 pt-6 lg:flex-row lg:items-center">
              <div className="min-w-0 flex-1"><div className="flex flex-wrap items-center gap-2"><span className="font-semibold">{plan.card_code} · {plan.card_name}</span><Badge variant={plan.is_active ? 'default' : 'secondary'}>{plan.is_active ? 'Activo' : 'Inactivo'}</Badge><Badge variant="outline">{plan.trigger_type === 'calendar' ? 'Calendario' : `Medidor · ${plan.meter_name}`}</Badge>{plan.timing_status && <Badge variant={plan.timing_status === 'overdue' ? 'destructive' : 'outline'}>{timingLabels[plan.timing_status]}</Badge>}</div><p className="mt-1 text-sm text-muted-foreground">{plan.asset_name} · ciclo #{plan.current_occurrence?.sequence ?? '—'} · vence {plan.current_occurrence ? renderDue(plan.current_occurrence, plan) : 'sin ciclo vigente'}{plan.trigger_type === 'meter' && plan.meter_remaining_value !== null ? ` · ${plan.meter_remaining_value >= 0 ? 'faltan' : 'excedido por'} ${Math.abs(plan.meter_remaining_value)} ${plan.meter_unit ?? ''}` : ''}</p></div>
              {canManage && <div className="flex gap-2"><Button size="sm" variant="outline" onClick={() => openPlan(plan)}>Editar</Button><Button size="sm" variant="outline" onClick={() => void togglePlan(plan)}>{plan.is_active ? 'Desactivar' : 'Reactivar'}</Button></div>}
            </CardContent></Card>
          ))}
        </TabsContent>

        <TabsContent value="cards" className="space-y-3">
          <div className="flex justify-end">{canManage && <Button onClick={() => openCard()}><Plus className="mr-2 h-4 w-4" />Nueva ficha</Button>}</div>
          {state.cards.length === 0 ? <Empty text="Aún no hay fichas de mantenimiento." /> : state.cards.map((card) => (
            <Card key={card.id}><CardContent className="flex items-center gap-3 pt-6"><ClipboardList className="h-5 w-5 text-muted-foreground" /><div className="min-w-0 flex-1"><div className="flex items-center gap-2"><span className="font-semibold">{card.code} · {card.name}</span><Badge variant={card.is_active ? 'default' : 'secondary'}>{card.is_active ? 'Activa' : 'Inactiva'}</Badge></div><p className="text-sm text-muted-foreground">{card.tasks.length} tareas · {card.materials.length} materiales · {card.estimated_hours ?? '—'} h estimadas</p></div>{canManage && <><Button size="sm" variant="outline" onClick={() => openCard(card)}>Editar</Button><Button size="sm" variant="ghost" onClick={() => void state.setCardActive(card.id, !card.is_active)}>{card.is_active ? 'Desactivar' : 'Activar'}</Button></>}</CardContent></Card>
          ))}
        </TabsContent>

        <TabsContent value="occurrences" className="space-y-3">
          {state.occurrences.length === 0 ? <Empty text="No hay ciclos registrados." /> : state.occurrences.map((occurrence) => {
            const plan = state.plans.find((item) => item.id === occurrence.plan_id);
            return <Card key={occurrence.id} className={focusedOccurrence?.id === occurrence.id ? 'ring-2 ring-onefacility-blue' : ''}><CardContent className="flex flex-col gap-3 pt-6 md:flex-row md:items-center"><CalendarClock className="h-5 w-5 text-muted-foreground" /><div className="flex-1"><div className="flex items-center gap-2"><span className="font-medium">{occurrence.card_code ?? plan?.card_code} · ciclo #{occurrence.sequence}</span><Badge variant="outline">{statusLabels[occurrence.status]}</Badge></div><p className="text-sm text-muted-foreground">{occurrence.asset_name ?? plan?.asset_name} · {renderDue(occurrence, plan)}</p></div>{canManage && occurrence.status === 'open' && <div className="flex gap-2"><Button size="sm" onClick={() => setPlanningOccurrence(occurrence)}><Wrench className="mr-1 h-4 w-4" />Planificar</Button><Button size="sm" variant="outline" onClick={() => void skip(occurrence)}><SkipForward className="mr-1 h-4 w-4" />Omitir</Button></div>}</CardContent></Card>;
          })}
        </TabsContent>

        <TabsContent value="meters" className="space-y-4"><div className="max-w-md"><Label>Activo</Label><Select value={meterAssetId} onValueChange={setMeterAssetId}><SelectTrigger><SelectValue placeholder="Selecciona un activo" /></SelectTrigger><SelectContent>{assets.map((asset) => <SelectItem key={asset.id} value={asset.id}>{asset.code ? `${asset.code} · ` : ''}{asset.name}</SelectItem>)}</SelectContent></Select></div>{meterAssetId ? <AssetMetersPanel assetId={meterAssetId} organizationId={organizationId!} canManage={canManage} /> : <Empty text="Selecciona un activo para consultar sus medidores." />}</TabsContent>
      </Tabs>

      <Dialog open={cardOpen} onOpenChange={setCardOpen}><DialogContent className="max-h-[90vh] max-w-3xl overflow-y-auto"><DialogHeader><DialogTitle>{editingCard ? 'Editar ficha' : 'Nueva ficha de mantenimiento'}</DialogTitle></DialogHeader><div className="grid gap-4 md:grid-cols-2"><Field label="Código"><Input value={cardDraft.code} onChange={(e) => setCardDraft({ ...cardDraft, code: e.target.value })} /></Field><Field label="Nombre"><Input value={cardDraft.name} onChange={(e) => setCardDraft({ ...cardDraft, name: e.target.value })} /></Field><Field label="Categoría"><Input value={cardDraft.category} onChange={(e) => setCardDraft({ ...cardDraft, category: e.target.value })} /></Field><Field label="Horas estimadas"><Input type="number" min="0" value={cardDraft.estimatedHours ?? ''} onChange={(e) => setCardDraft({ ...cardDraft, estimatedHours: e.target.value ? Number(e.target.value) : null })} /></Field><div className="md:col-span-2"><Field label="Descripción"><Textarea value={cardDraft.description} onChange={(e) => setCardDraft({ ...cardDraft, description: e.target.value })} /></Field></div><div className="md:col-span-2"><Field label="Procedimiento"><Textarea value={cardDraft.procedureNotes} onChange={(e) => setCardDraft({ ...cardDraft, procedureNotes: e.target.value })} /></Field></div><div className="md:col-span-2"><Field label="Seguridad"><Textarea value={cardDraft.safetyNotes} onChange={(e) => setCardDraft({ ...cardDraft, safetyNotes: e.target.value })} /></Field></div></div><Section title="Tareas" onAdd={() => setCardDraft({ ...cardDraft, tasks: [...cardDraft.tasks, { title: '', description: '', estimated_hours: null, is_required: true }] })}>{cardDraft.tasks.map((task, index) => <div key={index} className="grid grid-cols-[1fr_120px_auto] gap-2"><Input value={task.title} onChange={(e) => setCardDraft({ ...cardDraft, tasks: cardDraft.tasks.map((item, i) => i === index ? { ...item, title: e.target.value } : item) })} placeholder="Tarea" /><Input type="number" min="0" value={task.estimated_hours ?? ''} onChange={(e) => setCardDraft({ ...cardDraft, tasks: cardDraft.tasks.map((item, i) => i === index ? { ...item, estimated_hours: e.target.value ? Number(e.target.value) : null } : item) })} placeholder="Horas" /><Button variant="ghost" onClick={() => setCardDraft({ ...cardDraft, tasks: cardDraft.tasks.filter((_, i) => i !== index) })}>Quitar</Button></div>)}</Section><Section title="Materiales previstos (sin reservar stock)" onAdd={() => setCardDraft({ ...cardDraft, materials: [...cardDraft.materials, { material_id: null, description: '', quantity: 1, unit: 'und', notes: '' }] })}>{cardDraft.materials.map((material, index) => <div key={index} className="grid gap-2 rounded-md border p-2 md:grid-cols-[1fr_100px_100px_auto]"><Select value={material.material_id ?? 'manual'} onValueChange={(value) => { const selected = catalog.materials.find((item) => item.id === value); setCardDraft({ ...cardDraft, materials: cardDraft.materials.map((item, i) => i === index ? { ...item, material_id: value === 'manual' ? null : value, description: selected?.name ?? item.description, unit: selected?.unit ?? item.unit } : item) }); }}><SelectTrigger><SelectValue placeholder="Material" /></SelectTrigger><SelectContent><SelectItem value="manual">Descripción libre</SelectItem>{catalog.materials.map((item) => <SelectItem key={item.id} value={item.id}>{item.code} · {item.name} · stock {item.stock}</SelectItem>)}</SelectContent></Select><Input type="number" min="0.001" step="0.001" value={material.quantity} onChange={(e) => setCardDraft({ ...cardDraft, materials: cardDraft.materials.map((item, i) => i === index ? { ...item, quantity: Number(e.target.value) } : item) })} /><Input value={material.unit} onChange={(e) => setCardDraft({ ...cardDraft, materials: cardDraft.materials.map((item, i) => i === index ? { ...item, unit: e.target.value } : item) })} /><Button variant="ghost" onClick={() => setCardDraft({ ...cardDraft, materials: cardDraft.materials.filter((_, i) => i !== index) })}>Quitar</Button>{!material.material_id && <Input className="md:col-span-4" value={material.description} onChange={(e) => setCardDraft({ ...cardDraft, materials: cardDraft.materials.map((item, i) => i === index ? { ...item, description: e.target.value } : item) })} placeholder="Descripción" />}</div>)}</Section><DialogFooter><Button variant="outline" onClick={() => setCardOpen(false)}>Cancelar</Button><Button disabled={state.saving || !cardDraft.code.trim() || !cardDraft.name.trim()} onClick={() => void saveCard()}>Guardar ficha</Button></DialogFooter></DialogContent></Dialog>

      <Dialog open={planOpen} onOpenChange={setPlanOpen}><DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto"><DialogHeader><DialogTitle>{editingPlan ? 'Editar plan' : 'Nuevo plan preventivo'}</DialogTitle></DialogHeader><div className="grid gap-4 md:grid-cols-2"><Field label="Activo"><Select value={planDraft.assetId} disabled={!!editingPlan} onValueChange={(assetId) => setPlanDraft({ ...planDraft, assetId, meterId: null, baselineReadingId: null })}><SelectTrigger><SelectValue placeholder="Selecciona" /></SelectTrigger><SelectContent>{assets.map((asset) => <SelectItem key={asset.id} value={asset.id}>{asset.code ? `${asset.code} · ` : ''}{asset.name}</SelectItem>)}</SelectContent></Select></Field><Field label="Ficha"><Select value={planDraft.cardId} disabled={!!editingPlan} onValueChange={(cardId) => setPlanDraft({ ...planDraft, cardId })}><SelectTrigger><SelectValue placeholder="Selecciona" /></SelectTrigger><SelectContent>{state.cards.filter((card) => card.is_active || card.id === editingPlan?.card_id).map((card) => <SelectItem key={card.id} value={card.id}>{card.code} · {card.name}</SelectItem>)}</SelectContent></Select></Field><Field label="Disparador"><Select value={planDraft.triggerType} disabled={!!editingPlan} onValueChange={(triggerType: 'calendar' | 'meter') => setPlanDraft({ ...planDraft, triggerType })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="calendar">Calendario</SelectItem><SelectItem value="meter">Medidor</SelectItem></SelectContent></Select></Field><Field label="Prioridad"><Select value={planDraft.priority} onValueChange={(priority: PreventivePlan['priority']) => setPlanDraft({ ...planDraft, priority })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="low">Baja</SelectItem><SelectItem value="medium">Media</SelectItem><SelectItem value="high">Alta</SelectItem><SelectItem value="urgent">Urgente</SelectItem></SelectContent></Select></Field><Field label="Tipo de solicitud por defecto"><Select value={planDraft.defaultRequestType} onValueChange={(defaultRequestType: 'internal' | 'external') => setPlanDraft({ ...planDraft, defaultRequestType })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="internal">Interna</SelectItem><SelectItem value="external">Externa</SelectItem></SelectContent></Select></Field><Field label="Responsable"><Select value={planDraft.responsibleMemberId ?? 'none'} onValueChange={(value) => setPlanDraft({ ...planDraft, responsibleMemberId: value === 'none' ? null : value })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="none">Sin asignar</SelectItem>{planners.map((planner) => <SelectItem key={planner.memberId} value={planner.memberId}>{planner.name}</SelectItem>)}</SelectContent></Select></Field><Field label="Anticipación"><Input type="number" min="0" value={planDraft.planningLeadDays} onChange={(e) => setPlanDraft({ ...planDraft, planningLeadDays: Number(e.target.value) })} /></Field>{planDraft.triggerType === 'calendar' ? <><Field label="Frecuencia"><Select value={planDraft.frequency ?? 'monthly'} onValueChange={(frequency: PreventiveFrequency) => setPlanDraft({ ...planDraft, frequency })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{Object.entries(frequencyLabels).map(([value, label]) => <SelectItem key={value} value={value}>{label}</SelectItem>)}</SelectContent></Select></Field><Field label="Primer vencimiento"><Input type="datetime-local" value={planDraft.firstDueAt ?? ''} onChange={(e) => setPlanDraft({ ...planDraft, firstDueAt: e.target.value })} /></Field>{planDraft.frequency === 'custom' && <><Field label="Cada"><Input type="number" min="1" value={planDraft.customInterval ?? 1} onChange={(e) => setPlanDraft({ ...planDraft, customInterval: Number(e.target.value) })} /></Field><Field label="Unidad"><Select value={planDraft.customUnit ?? 'months'} onValueChange={(customUnit: PreventivePlan['custom_unit']) => setPlanDraft({ ...planDraft, customUnit })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="days">Días</SelectItem><SelectItem value="weeks">Semanas</SelectItem><SelectItem value="months">Meses</SelectItem><SelectItem value="years">Años</SelectItem></SelectContent></Select></Field></>}</> : <><Field label="Medidor"><Select value={planDraft.meterId ?? ''} disabled={!!editingPlan} onValueChange={(meterId) => setPlanDraft({ ...planDraft, meterId, baselineReadingId: null })}><SelectTrigger><SelectValue placeholder="Selecciona" /></SelectTrigger><SelectContent>{planMeters.meters.filter((meter) => meter.is_active).map((meter) => <SelectItem key={meter.id} value={meter.id}>{meter.name} · {meter.unit}</SelectItem>)}</SelectContent></Select></Field><Field label="Lectura base real"><Select value={planDraft.baselineReadingId ?? ''} disabled={!!editingPlan} onValueChange={(baselineReadingId) => setPlanDraft({ ...planDraft, baselineReadingId })}><SelectTrigger><SelectValue placeholder="Selecciona" /></SelectTrigger><SelectContent>{planMeters.meters.find((meter) => meter.id === planDraft.meterId)?.readings.map((reading) => <SelectItem key={reading.id} value={reading.id}>{reading.value} · {new Date(reading.recorded_at).toLocaleString()}</SelectItem>)}</SelectContent></Select></Field><Field label="Intervalo del medidor"><Input type="number" min="0.001" step="0.001" value={planDraft.intervalValue ?? ''} onChange={(e) => setPlanDraft({ ...planDraft, intervalValue: Number(e.target.value) })} /></Field><Field label="Anticipación del medidor"><Input type="number" min="0" step="0.001" value={planDraft.meterLeadValue ?? 0} onChange={(e) => setPlanDraft({ ...planDraft, meterLeadValue: Number(e.target.value) })} /></Field></>}</div><DialogFooter><Button variant="outline" onClick={() => setPlanOpen(false)}>Cancelar</Button><Button disabled={state.saving || !planDraft.assetId || !planDraft.cardId} onClick={() => void savePlan()}>Guardar plan</Button></DialogFooter></DialogContent></Dialog>

      {planningOccurrence && planningPlan && <PreventiveRequestDialog plan={planningPlan} occurrence={planningOccurrence} onClose={() => setPlanningOccurrence(null)} onLink={state.linkRequest} />}
    </div>
  );
}

function Empty({ text }: { text: string }) { return <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground"><Gauge className="mx-auto mb-2 h-6 w-6 opacity-50" />{text}</div>; }
function Field({ label, children }: { label: string; children: React.ReactNode }) { return <div className="space-y-1.5"><Label>{label}</Label>{children}</div>; }
function Section({ title, onAdd, children }: { title: string; onAdd: () => void; children: React.ReactNode }) { return <div className="space-y-2"><div className="flex items-center justify-between"><Label>{title}</Label><Button type="button" size="sm" variant="outline" onClick={onAdd}><Plus className="mr-1 h-3 w-3" />Agregar</Button></div>{children}</div>; }
