import { useEffect, useMemo, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';

type Version = {
  id: string;
  version_number: number;
  status: string;
  source_type: string;
  created_by: string | null;
  created_at: string;
  requested_service: string | null;
  scope_of_work: string | null;
  missing_information: unknown;
  technical_considerations: unknown;
  risks: unknown;
};

type HistoricalItem = {
  id: string;
  analysis_id: string;
  item_type: string;
  description: string;
  quantity: number | null;
  unit_code: string | null;
  technical_specification: string | null;
  suggested_cost_item_id: string | null;
};

type Props = {
  organizationId: string;
  opportunityId: string;
  refreshKey: number;
};

const db = supabase as any;
const noteLines = (input: unknown) =>
  Array.isArray(input) ? input.filter((value): value is string => typeof value === 'string') : [];
const dateTime = (value: string) => new Date(value).toLocaleString('es-PE');
const stateLabel = (status: string) => ({
  draft: 'Borrador vigente',
  ready_for_review: 'Lista para revisión',
  superseded: 'Reemplazada',
}[status] ?? status);
const normalizedItems = (items: HistoricalItem[]) => items
  .map(({ item_type, description, quantity, unit_code, technical_specification, suggested_cost_item_id }) =>
    JSON.stringify({ item_type, description, quantity, unit_code, technical_specification, suggested_cost_item_id }))
  .sort().join('|');

export const OpportunityAnalysisHistory = ({ organizationId, opportunityId, refreshKey }: Props) => {
  const [versions, setVersions] = useState<Version[]>([]);
  const [selectedId, setSelectedId] = useState<string>('');
  const [items, setItems] = useState<HistoricalItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingItems, setLoadingItems] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let canceled = false;
    setLoading(true);
    setError(null);
    db.from('romax_opportunity_analyses')
      .select('id,version_number,status,source_type,created_by,created_at,requested_service,scope_of_work,missing_information,technical_considerations,risks')
      .eq('organization_id', organizationId)
      .eq('opportunity_id', opportunityId)
      .order('version_number', { ascending: false })
      .then(({ data, error: queryError }: { data: Version[] | null; error: { message: string } | null }) => {
        if (canceled) return;
        if (queryError) {
          setError(queryError.message);
          setVersions([]);
        } else {
          const next = data ?? [];
          setVersions(next);
          setSelectedId((current) => next.some((version) => version.id === current) ? current : (next[0]?.id ?? ''));
        }
        setLoading(false);
      });
    return () => { canceled = true; };
  }, [organizationId, opportunityId, refreshKey]);

  const latest = versions[0] ?? null;
  const selected = versions.find((version) => version.id === selectedId) ?? latest;
  const ids = useMemo(
    () => [...new Set([latest?.id, selected?.id].filter((id): id is string => !!id))],
    [latest?.id, selected?.id],
  );

  useEffect(() => {
    if (!ids.length) { setItems([]); return; }
    let canceled = false;
    setLoadingItems(true);
    setError(null);
    db.from('romax_opportunity_analysis_items')
      .select('id,analysis_id,item_type,description,quantity,unit_code,technical_specification,suggested_cost_item_id')
      .eq('organization_id', organizationId)
      .in('analysis_id', ids)
      .order('created_at')
      .then(({ data, error: queryError }: { data: HistoricalItem[] | null; error: { message: string } | null }) => {
        if (canceled) return;
        if (queryError) setError(queryError.message);
        else setItems(data ?? []);
        setLoadingItems(false);
      });
    return () => { canceled = true; };
  }, [organizationId, ids]);

  const selectedItems = items.filter((item) => item.analysis_id === selected?.id);
  const latestItems = items.filter((item) => item.analysis_id === latest?.id);
  const compare = selected && latest && selected.id !== latest.id;
  const checks = compare ? [
    { name: 'Servicio solicitado', changed: selected.requested_service !== latest.requested_service },
    { name: 'Alcance', changed: selected.scope_of_work !== latest.scope_of_work },
    { name: 'Información faltante', changed: JSON.stringify(selected.missing_information) !== JSON.stringify(latest.missing_information) },
    { name: 'Consideraciones', changed: JSON.stringify(selected.technical_considerations) !== JSON.stringify(latest.technical_considerations) },
    { name: 'Riesgos', changed: JSON.stringify(selected.risks) !== JSON.stringify(latest.risks) },
    { name: 'Partidas', changed: normalizedItems(selectedItems) !== normalizedItems(latestItems) },
  ] : [];

  const details = (version: Version | null, rows: HistoricalItem[]) => {
    if (!version) return null;
    return (
      <div className="space-y-3 text-sm">
        <p><span className="font-medium">Servicio: </span>{version.requested_service || 'Sin informar'}</p>
        <p className="whitespace-pre-wrap"><span className="font-medium">Alcance: </span>{version.scope_of_work || 'Sin informar'}</p>
        <div>
          <p className="font-medium">Partidas ({rows.length})</p>
          <ul className="ml-4 list-disc">
            {rows.map((item) => <li key={item.id}>{item.description} · {item.quantity ?? '—'} {item.unit_code ?? ''} ({item.item_type})</li>)}
          </ul>
        </div>
        <div><p className="font-medium">Información faltante</p><p className="whitespace-pre-wrap">{noteLines(version.missing_information).join('\n') || 'Ninguna'}</p></div>
        <div><p className="font-medium">Consideraciones</p><p className="whitespace-pre-wrap">{noteLines(version.technical_considerations).join('\n') || 'Ninguna'}</p></div>
        <div><p className="font-medium">Riesgos</p><p className="whitespace-pre-wrap">{noteLines(version.risks).join('\n') || 'Ninguno'}</p></div>
      </div>
    );
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Historial de versiones</CardTitle>
        <CardDescription>Consulta las versiones anteriores sin editar el histórico. Selecciona una versión para compararla con la vigente.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {loading ? <p className="text-sm text-muted-foreground">Cargando historial…</p> : versions.length === 0
          ? <p className="text-sm text-muted-foreground">Todavía no hay versiones guardadas.</p>
          : (
            <>
              <div className="flex flex-wrap gap-2">
                {versions.map((version, index) => (
                  <Button
                    key={version.id}
                    type="button"
                    size="sm"
                    variant={selected?.id === version.id ? 'default' : 'outline'}
                    onClick={() => setSelectedId(version.id)}
                    aria-pressed={selected?.id === version.id}
                  >
                    V{version.version_number} · {index === 0 ? 'Vigente' : 'Histórica'}
                  </Button>
                ))}
              </div>
              {selected && (
                <div className="flex flex-wrap gap-2 text-sm">
                  <Badge variant={selected.id === latest?.id ? 'default' : 'secondary'}>{stateLabel(selected.status)}</Badge>
                  <span>Creada: {dateTime(selected.created_at)}</span>
                  <span>· Responsable (ID): {selected.created_by?.slice(0, 8) ?? 'No informado'}</span>
                  <span>· Origen: {selected.source_type === 'manual' ? 'Manual' : 'IA'}</span>
                </div>
              )}
              {loadingItems && <p className="text-sm text-muted-foreground">Cargando partidas…</p>}
              {!loadingItems && selected && (
                <>
                  {compare && (
                    <div className="flex flex-wrap gap-2">
                      {checks.map((check) => (
                        <Badge key={check.name} variant={check.changed ? 'outline' : 'secondary'}>
                          {check.name}: {check.changed ? 'Cambió' : 'Sin cambios'}
                        </Badge>
                      ))}
                    </div>
                  )}
                  <div className={compare ? 'grid gap-4 lg:grid-cols-2' : ''}>
                    <div className="rounded-md border p-4">
                      <p className="mb-3 font-semibold">Versión {selected.version_number} {compare ? '(histórica)' : '(vigente)'}</p>
                      {details(selected, selectedItems)}
                    </div>
                    {compare && latest && (
                      <div className="rounded-md border p-4">
                        <p className="mb-3 font-semibold">Versión {latest.version_number} (vigente)</p>
                        {details(latest, latestItems)}
                      </div>
                    )}
                  </div>
                </>
              )}
            </>
          )}
        {error && <p role="alert" className="text-sm text-destructive">No se pudo cargar el historial: {error}</p>}
      </CardContent>
    </Card>
  );
};
