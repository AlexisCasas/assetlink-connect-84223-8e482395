import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowLeft, Plus, RefreshCw, Save, Trash2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { navigateToEntity } from '@/lib/entityNavigation';
import { useToast } from '@/hooks/use-toast';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

type Props = { opportunityId?: string };

type Opportunity = {
  id: string;
  subject: string | null;
  sender_email: string | null;
  commercial_client_id: string | null;
  commercial_site_id: string | null;
};

type CostItem = { id: string; name: string; default_unit_code: string; category_code: string };

type AnalysisItem = {
  id?: string;
  item_type: string;
  description: string;
  quantity: string;
  unit_code: string;
  technical_specification: string;
  suggested_cost_item_id: string;
};

type Analysis = {
  id: string;
  version_number: number;
  status: string;
  source_type: string;
  requested_service: string | null;
  scope_of_work: string | null;
  missing_information: unknown;
  technical_considerations: unknown;
  risks: unknown;
};

const db = supabase as any;

const emptyItem = (): AnalysisItem => ({
  item_type: 'material',
  description: '',
  quantity: '',
  unit_code: '',
  technical_specification: '',
  suggested_cost_item_id: '',
});

const toLines = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter((row): row is string => typeof row === 'string') : [];

const OpportunityAnalysisView = ({ opportunityId }: Props) => {
  const { currentOrganization, currentMembership } = useAuth();
  const { toast } = useToast();
  const organizationId = currentOrganization?.id ?? '';
  const authorized = currentOrganization?.organizationType === 'provider_company'
    && currentMembership?.isActive
    && currentMembership.organizationId === organizationId
    && ['owner', 'admin', 'manager', 'quote_manager'].includes(currentMembership.role);

  const [opportunity, setOpportunity] = useState<Opportunity | null>(null);
  const [resources, setResources] = useState<CostItem[]>([]);
  const [latestAnalysis, setLatestAnalysis] = useState<Analysis | null>(null);
  const [requestedService, setRequestedService] = useState('');
  const [scope, setScope] = useState('');
  const [missingInformation, setMissingInformation] = useState('');
  const [technicalConsiderations, setTechnicalConsiderations] = useState('');
  const [risks, setRisks] = useState('');
  const [items, setItems] = useState<AnalysisItem[]>([emptyItem()]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const loadData = useCallback(async () => {
    if (!organizationId || !authorized || !opportunityId) return;
    setLoading(true);
    try {
      const [opportunityResult, resourceResult, analysisResult] = await Promise.all([
        db.from('romax_opportunities').select('id,subject,sender_email,commercial_client_id,commercial_site_id').eq('id', opportunityId).eq('organization_id', organizationId).maybeSingle(),
        db.from('provider_cost_items').select('id,name,default_unit_code,category_code').eq('organization_id', organizationId).eq('is_active', true).order('name'),
        db.from('romax_opportunity_analyses').select('*').eq('opportunity_id', opportunityId).eq('organization_id', organizationId).order('version_number', { ascending: false }).limit(1).maybeSingle(),
      ]);
      for (const result of [opportunityResult, resourceResult, analysisResult]) {
        if (result.error) throw new Error(result.error.message);
      }
      setOpportunity(opportunityResult.data as Opportunity | null);
      setResources((resourceResult.data ?? []) as CostItem[]);
      const analysis = analysisResult.data as Analysis | null;
      setLatestAnalysis(analysis);
      if (analysis) {
        setRequestedService(analysis.requested_service ?? '');
        setScope(analysis.scope_of_work ?? '');
        setMissingInformation(toLines(analysis.missing_information).join('\n'));
        setTechnicalConsiderations(toLines(analysis.technical_considerations).join('\n'));
        setRisks(toLines(analysis.risks).join('\n'));
        const itemResult = await db.from('romax_opportunity_analysis_items').select('id,item_type,description,quantity,unit_code,technical_specification,suggested_cost_item_id').eq('analysis_id', analysis.id).eq('organization_id', organizationId).order('created_at');
        if (itemResult.error) throw new Error(itemResult.error.message);
        setItems((itemResult.data ?? []).map((row: any) => ({
          id: row.id,
          item_type: row.item_type,
          description: row.description,
          quantity: row.quantity == null ? '' : String(row.quantity),
          unit_code: row.unit_code ?? '',
          technical_specification: row.technical_specification ?? '',
          suggested_cost_item_id: row.suggested_cost_item_id ?? '',
        })));
      }
    } catch (error) {
      toast({ title: 'No se pudo cargar el análisis', description: error instanceof Error ? error.message : 'Error inesperado.', variant: 'destructive' });
    } finally {
      setLoading(false);
    }
  }, [organizationId, authorized, opportunityId, toast]);

  useEffect(() => { void loadData(); }, [loadData]);

  const validItems = useMemo(() => items.filter((item) => item.description.trim()), [items]);

  const updateItem = (index: number, patch: Partial<AnalysisItem>) => {
    setItems((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, ...patch } : item));
  };

  const saveAnalysis = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!authorized || !organizationId || !opportunityId) return;
    if (!requestedService.trim() && !scope.trim() && validItems.length === 0) {
      toast({ title: 'Falta información', description: 'Registra al menos el servicio solicitado, el alcance o una partida.', variant: 'destructive' });
      return;
    }
    setSaving(true);
    try {
      const nextVersion = (latestAnalysis?.version_number ?? 0) + 1;
      const { data: analysis, error: analysisError } = await db.from('romax_opportunity_analyses').insert({
        organization_id: organizationId,
        opportunity_id: opportunityId,
        version_number: nextVersion,
        status: 'draft',
        source_type: 'manual',
        requested_service: requestedService.trim() || null,
        scope_of_work: scope.trim() || null,
        missing_information: missingInformation.split('\n').map((value) => value.trim()).filter(Boolean),
        technical_considerations: technicalConsiderations.split('\n').map((value) => value.trim()).filter(Boolean),
        risks: risks.split('\n').map((value) => value.trim()).filter(Boolean),
      }).select('id,version_number,status,source_type,requested_service,scope_of_work,missing_information,technical_considerations,risks').single();
      if (analysisError || !analysis) throw new Error(analysisError?.message ?? 'No se pudo crear la versión de análisis.');

      if (validItems.length) {
        const { error: itemsError } = await db.from('romax_opportunity_analysis_items').insert(validItems.map((item) => ({
          organization_id: organizationId,
          analysis_id: analysis.id,
          item_type: item.item_type,
          description: item.description.trim(),
          quantity: item.quantity ? Number(item.quantity) : null,
          unit_code: item.unit_code.trim() || null,
          technical_specification: item.technical_specification.trim() || null,
          suggested_cost_item_id: item.suggested_cost_item_id || null,
        })));
        if (itemsError) throw new Error(itemsError.message);
      }

      if (latestAnalysis?.id) {
        const { error: supersedeError } = await db.from('romax_opportunity_analyses')
          .update({ status: 'superseded' })
          .eq('id', latestAnalysis.id)
          .eq('organization_id', organizationId);
        if (supersedeError) throw new Error(supersedeError.message);
      }

      toast({ title: 'Análisis guardado', description: `Versión ${nextVersion} creada como borrador.` });
      await loadData();
    } catch (error) {
      toast({ title: 'No se pudo guardar el análisis', description: error instanceof Error ? error.message : 'Error inesperado.', variant: 'destructive' });
    } finally {
      setSaving(false);
    }
  };

  if (!authorized) {
    return <div className="p-6"><Card><CardContent className="p-8 text-center"><p className="font-medium">Acceso restringido.</p></CardContent></Card></div>;
  }

  if (!opportunityId) {
    return <div className="p-6"><Card><CardContent className="p-8 text-center"><p className="font-medium">Selecciona una oportunidad para iniciar el análisis.</p></CardContent></Card></div>;
  }

  if (!loading && !opportunity) {
    return <div className="p-6"><Card><CardContent className="p-8 text-center"><p className="font-medium">No se encontró la oportunidad.</p></CardContent></Card></div>;
  }

  return (
    <div className="space-y-6 p-6">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <Button variant="ghost" className="mb-2 px-0" onClick={() => navigateToEntity({ view: 'opportunities' })}>
            <ArrowLeft className="mr-2 h-4 w-4" />Volver a oportunidades
          </Button>
          <h1 className="text-2xl font-semibold tracking-tight">Análisis técnico</h1>
          <p className="mt-1 text-sm text-muted-foreground">{opportunity?.subject || 'Solicitud sin asunto'} · {opportunity?.sender_email || 'Remitente no informado'}</p>
        </div>
        <Button variant="outline" onClick={() => void loadData()} disabled={loading}><RefreshCw className="mr-2 h-4 w-4" />Actualizar</Button>
      </header>

      <form className="space-y-5" onSubmit={saveAnalysis}>
        <Card>
          <CardHeader>
            <CardTitle className="text-base">1. Entender la solicitud</CardTitle>
            <CardDescription>Esta capa describe qué se está solicitando. Todavía no calcula costos ni precios.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4">
            <div className="space-y-1.5"><Label htmlFor="analysis-service">Servicio solicitado</Label><Input id="analysis-service" value={requestedService} onChange={(event) => setRequestedService(event.target.value)} placeholder="Ej. instalación de ventiladores industriales" /></div>
            <div className="space-y-1.5"><Label htmlFor="analysis-scope">Alcance / trabajos incluidos</Label><Textarea id="analysis-scope" value={scope} onChange={(event) => setScope(event.target.value)} rows={5} placeholder="Describe los trabajos que deben ejecutarse." /></div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="text-base">2. Partidas identificadas</CardTitle><CardDescription>Materiales, equipos, mano de obra, movilización y otros elementos. Los precios quedan fuera de R4-A.</CardDescription></CardHeader>
          <CardContent className="space-y-3">
            {items.map((item, index) => (
              <div key={item.id ?? `new-${index}`} className="grid gap-3 rounded-md border p-3 md:grid-cols-[140px_1fr_100px_100px]">
                <select className="h-10 rounded-md border bg-background px-3 text-sm" value={item.item_type} onChange={(event) => updateItem(index, { item_type: event.target.value })}>
                  <option value="service">Servicio</option><option value="material">Material</option><option value="equipment">Equipo</option><option value="labor">Mano de obra</option><option value="mobilization">Movilización</option><option value="other">Otro</option>
                </select>
                <Input value={item.description} onChange={(event) => updateItem(index, { description: event.target.value })} placeholder="Descripción" />
                <Input type="number" min="0" step="any" value={item.quantity} onChange={(event) => updateItem(index, { quantity: event.target.value })} placeholder="Cantidad" />
                <Input value={item.unit_code} onChange={(event) => updateItem(index, { unit_code: event.target.value })} placeholder="Unidad" />
                <Textarea className="md:col-span-4" rows={2} value={item.technical_specification} onChange={(event) => updateItem(index, { technical_specification: event.target.value })} placeholder="Especificación / detalle técnico" />
                <select className="h-10 rounded-md border bg-background px-3 text-sm md:col-span-3" value={item.suggested_cost_item_id} onChange={(event) => updateItem(index, { suggested_cost_item_id: event.target.value })}>
                  <option value="">Sin recurso del catálogo todavía</option>
                  {resources.map((resource) => <option key={resource.id} value={resource.id}>{resource.name} · {resource.default_unit_code}</option>)}
                </select>
                <Button type="button" variant="ghost" onClick={() => setItems((current) => current.filter((_, itemIndex) => itemIndex !== index))} disabled={items.length === 1}><Trash2 className="mr-2 h-4 w-4" />Quitar</Button>
              </div>
            ))}
            <Button type="button" variant="outline" onClick={() => setItems((current) => [...current, emptyItem()])}><Plus className="mr-2 h-4 w-4" />Agregar partida</Button>
          </CardContent>
        </Card>

        <div className="grid gap-5 md:grid-cols-3">
          <Card><CardHeader><CardTitle className="text-base">Información faltante</CardTitle><CardDescription>Una línea por dato que debemos solicitar.</CardDescription></CardHeader><CardContent><Textarea value={missingInformation} onChange={(event) => setMissingInformation(event.target.value)} rows={7} placeholder="Ej. medidas del área\nEj. altura de instalación" /></CardContent></Card>
          <Card><CardHeader><CardTitle className="text-base">Consideraciones técnicas</CardTitle><CardDescription>Una línea por consideración.</CardDescription></CardHeader><CardContent><Textarea value={technicalConsiderations} onChange={(event) => setTechnicalConsiderations(event.target.value)} rows={7} placeholder="Ej. trabajo en altura\nEj. acceso restringido" /></CardContent></Card>
          <Card><CardHeader><CardTitle className="text-base">Riesgos</CardTitle><CardDescription>Una línea por riesgo detectado.</CardDescription></CardHeader><CardContent><Textarea value={risks} onChange={(event) => setRisks(event.target.value)} rows={7} placeholder="Ej. falta de medidas\nEj. interferencia con operación" /></CardContent></Card>
        </div>

        <div className="flex justify-end gap-2">
          <Badge variant="outline">R4-A · análisis manual</Badge>
          <Button type="submit" disabled={saving || loading}><Save className="mr-2 h-4 w-4" />{saving ? 'Guardando…' : 'Guardar análisis'}</Button>
        </div>
      </form>
    </div>
  );
};

export default OpportunityAnalysisView;
