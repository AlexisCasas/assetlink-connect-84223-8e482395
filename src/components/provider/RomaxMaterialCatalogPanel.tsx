import { Fragment, useCallback, useEffect, useMemo, useState } from 'react';
import { AlertCircle, Boxes, CheckCircle2, ChevronDown, ChevronLeft, ChevronRight, ClipboardList, RefreshCw, Search } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';

type QueryResult = { data: unknown; error: { message: string } | null };
interface CatalogQuery extends PromiseLike<QueryResult> {
  select(columns?: string): CatalogQuery;
  eq(column: string, value: string | boolean): CatalogQuery;
  order(column: string, options?: { ascending?: boolean }): CatalogQuery;
}
const catalogDb = supabase as unknown as { from: (table: string) => CatalogQuery };

type MaterialItem = {
  id: string;
  code: string | null;
  name: string;
  description: string | null;
  category_code: string;
  default_unit_code: string;
  technical_specification: string | null;
  is_active: boolean;
  material_family_id: string | null;
  material_subfamily_id: string | null;
  technical_validation_status: 'preliminary' | 'in_review' | 'validated' | null;
};
type Family = { id: string; code: string; name: string; is_active: boolean };
type Subfamily = { id: string; family_id: string; code: string; name: string; is_active: boolean };
type SourceIdentity = {
  id: string;
  cost_item_id: string | null;
  source_code: string;
  source_name: string;
  source_unit: string;
  source_family: string | null;
  source_subfamily: string | null;
  source_specification: string | null;
  source_brand: string | null;
  mapping_status: 'pending' | 'confirmed' | 'needs_review';
};

type MainView = 'materials' | 'review';
type StatusFilter = 'all' | 'preliminary' | 'in_review' | 'validated' | 'legacy';
const PAGE_SIZE = 25;

const statusLabel = (status: MaterialItem['technical_validation_status']) => {
  if (status === 'preliminary') return 'Preliminar';
  if (status === 'in_review') return 'En revisión técnica';
  if (status === 'validated') return 'Validado técnicamente';
  return 'Legado · sin evaluar';
};

const statusVariant = (status: MaterialItem['technical_validation_status']): 'default' | 'secondary' | 'outline' => {
  if (status === 'validated') return 'default';
  if (status === 'preliminary') return 'secondary';
  return 'outline';
};

export function RomaxMaterialCatalogPanel() {
  const { currentOrganization, currentMembership } = useAuth();
  const organizationId = currentOrganization?.id ?? '';
  const authorized = currentOrganization?.organizationType === 'provider_company'
    && currentMembership?.isActive
    && currentMembership.organizationId === organizationId
    && !!currentMembership.role;

  const [items, setItems] = useState<MaterialItem[]>([]);
  const [families, setFamilies] = useState<Family[]>([]);
  const [subfamilies, setSubfamilies] = useState<Subfamily[]>([]);
  const [sources, setSources] = useState<SourceIdentity[]>([]);
  const [loading, setLoading] = useState(true);
  const [view, setView] = useState<MainView>('materials');
  const [search, setSearch] = useState('');
  const [familyFilter, setFamilyFilter] = useState('all');
  const [subfamilyFilter, setSubfamilyFilter] = useState('all');
  const [unitFilter, setUnitFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [showInactive, setShowInactive] = useState(false);
  const [page, setPage] = useState(1);
  const [selectedItemId, setSelectedItemId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!organizationId || !authorized) {
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const [itemResult, familyResult, subfamilyResult, sourceResult] = await Promise.all([
        catalogDb.from('provider_cost_items')
          .select('id,code,name,description,category_code,default_unit_code,technical_specification,is_active,material_family_id,material_subfamily_id,technical_validation_status')
          .eq('organization_id', organizationId).order('name'),
        catalogDb.from('provider_material_families')
          .select('id,code,name,is_active').eq('organization_id', organizationId).order('name'),
        catalogDb.from('provider_material_subfamilies')
          .select('id,family_id,code,name,is_active').eq('organization_id', organizationId).order('name'),
        catalogDb.from('provider_cost_item_sources')
          .select('id,cost_item_id,source_code,source_name,source_unit,source_family,source_subfamily,source_specification,source_brand,mapping_status')
          .eq('organization_id', organizationId).order('source_code'),
      ]);
      for (const result of [itemResult, familyResult, subfamilyResult, sourceResult]) {
        if (result.error) throw new Error(result.error.message);
      }
      setItems((itemResult.data ?? []) as MaterialItem[]);
      setFamilies((familyResult.data ?? []) as Family[]);
      setSubfamilies((subfamilyResult.data ?? []) as Subfamily[]);
      setSources((sourceResult.data ?? []) as SourceIdentity[]);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo cargar el catálogo técnico.');
    } finally {
      setLoading(false);
    }
  }, [organizationId, authorized]);

  useEffect(() => { void load(); }, [load]);

  const familyById = useMemo(() => new Map(families.map((family) => [family.id, family])), [families]);
  const subfamilyById = useMemo(() => new Map(subfamilies.map((subfamily) => [subfamily.id, subfamily])), [subfamilies]);
  const sourceByItemId = useMemo(() => new Map(sources.filter((source) => source.cost_item_id).map((source) => [source.cost_item_id as string, source])), [sources]);
  const pendingSources = useMemo(() => sources.filter((source) => source.mapping_status !== 'confirmed' || !source.cost_item_id), [sources]);
  const units = useMemo(() => [...new Set(items.map((item) => item.default_unit_code))].sort(), [items]);
  const availableSubfamilies = useMemo(() => subfamilies.filter((subfamily) => subfamily.is_active && (familyFilter === 'all' || subfamily.family_id === familyFilter)), [subfamilies, familyFilter]);

  const filteredItems = useMemo(() => items.filter((item) => {
    const family = item.material_family_id ? familyById.get(item.material_family_id) : undefined;
    const subfamily = item.material_subfamily_id ? subfamilyById.get(item.material_subfamily_id) : undefined;
    const source = sourceByItemId.get(item.id);
    const haystack = [
      item.code, item.name, item.description, item.technical_specification, item.category_code,
      item.default_unit_code, family?.name, subfamily?.name, source?.source_code, source?.source_family,
    ].filter(Boolean).join(' ').toLocaleLowerCase();
    const matchesStatus = statusFilter === 'all'
      || (statusFilter === 'legacy' && item.technical_validation_status === null)
      || item.technical_validation_status === statusFilter;
    return (showInactive || item.is_active)
      && (familyFilter === 'all' || item.material_family_id === familyFilter)
      && (subfamilyFilter === 'all' || item.material_subfamily_id === subfamilyFilter)
      && (unitFilter === 'all' || item.default_unit_code === unitFilter)
      && matchesStatus
      && (!search || haystack.includes(search.trim().toLocaleLowerCase()));
  }), [items, familyById, subfamilyById, sourceByItemId, showInactive, familyFilter, subfamilyFilter, unitFilter, statusFilter, search]);

  const filteredPending = useMemo(() => pendingSources.filter((source) => {
    const haystack = [source.source_code, source.source_name, source.source_unit, source.source_family, source.source_subfamily, source.source_specification, source.source_brand].filter(Boolean).join(' ').toLocaleLowerCase();
    return !search || haystack.includes(search.trim().toLocaleLowerCase());
  }), [pendingSources, search]);

  const totalPages = Math.max(1, Math.ceil(filteredItems.length / PAGE_SIZE));
  const pageRows = filteredItems.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const preliminaryCount = items.filter((item) => item.technical_validation_status === 'preliminary').length;
  const legacyCount = items.filter((item) => item.technical_validation_status === null).length;

  useEffect(() => { setPage(1); }, [search, familyFilter, subfamilyFilter, unitFilter, statusFilter, showInactive, view]);

  useEffect(() => {
    if (familyFilter !== 'all' && subfamilyFilter !== 'all' && !availableSubfamilies.some((subfamily) => subfamily.id === subfamilyFilter)) {
      setSubfamilyFilter('all');
    }
  }, [familyFilter, subfamilyFilter, availableSubfamilies]);

  if (!authorized) {
    return (
      <Card><CardContent className="p-6 text-center text-sm text-muted-foreground">
        El catálogo técnico está disponible para usuarios autorizados de organizaciones proveedoras.
      </CardContent></Card>
    );
  }

  if (loading) return <div className="py-12 text-center text-sm text-muted-foreground">Cargando catálogo técnico…</div>;

  return (
    <div className="space-y-5">
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Card><CardContent className="flex items-center gap-3 p-4"><Boxes className="h-5 w-5 text-muted-foreground" /><div><p className="text-xs text-muted-foreground">Recursos totales</p><p className="text-2xl font-semibold tabular-nums">{items.length}</p></div></CardContent></Card>
        <Card><CardContent className="flex items-center gap-3 p-4"><CheckCircle2 className="h-5 w-5 text-muted-foreground" /><div><p className="text-xs text-muted-foreground">Materiales preliminares</p><p className="text-2xl font-semibold tabular-nums">{preliminaryCount}</p></div></CardContent></Card>
        <Card><CardContent className="flex items-center gap-3 p-4"><AlertCircle className="h-5 w-5 text-muted-foreground" /><div><p className="text-xs text-muted-foreground">Pendientes de homologación</p><p className="text-2xl font-semibold tabular-nums">{pendingSources.length}</p></div></CardContent></Card>
        <Card><CardContent className="flex items-center gap-3 p-4"><ClipboardList className="h-5 w-5 text-muted-foreground" /><div><p className="text-xs text-muted-foreground">Familias / subfamilias</p><p className="text-2xl font-semibold tabular-nums">{families.length} / {subfamilies.length}</p></div></CardContent></Card>
      </div>

      <div className="flex flex-wrap items-center gap-2 border-b pb-3">
        <Button size="sm" variant={view === 'materials' ? 'default' : 'outline'} onClick={() => setView('materials')}>Materiales</Button>
        <Button size="sm" variant={view === 'review' ? 'default' : 'outline'} onClick={() => setView('review')}>Pendientes ({pendingSources.length})</Button>
        <div className="ml-auto">
          <Button size="sm" variant="outline" onClick={() => void load()} disabled={loading}><RefreshCw className="mr-2 h-4 w-4" />Actualizar</Button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <div className="relative min-w-56 flex-1">
          <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
          <Input value={search} onChange={(event) => setSearch(event.target.value)} className="pl-9" placeholder={view === 'materials' ? 'Buscar por código, material o especificación…' : 'Buscar pendientes por código o descripción…'} />
        </div>
        {view === 'materials' && (
          <>
            <select aria-label="Filtrar por familia" className="h-10 min-w-44 rounded-md border bg-background px-3 text-sm" value={familyFilter} onChange={(event) => setFamilyFilter(event.target.value)}>
              <option value="all">Todas las familias</option>
              {families.filter((family) => family.is_active).map((family) => <option key={family.id} value={family.id}>{family.name}</option>)}
            </select>
            <select aria-label="Filtrar por subfamilia" className="h-10 min-w-44 rounded-md border bg-background px-3 text-sm" value={subfamilyFilter} onChange={(event) => setSubfamilyFilter(event.target.value)}>
              <option value="all">Todas las subfamilias</option>
              {availableSubfamilies.map((subfamily) => <option key={subfamily.id} value={subfamily.id}>{subfamily.name}</option>)}
            </select>
            <select aria-label="Filtrar por unidad" className="h-10 min-w-32 rounded-md border bg-background px-3 text-sm" value={unitFilter} onChange={(event) => setUnitFilter(event.target.value)}>
              <option value="all">Todas las unidades</option>
              {units.map((unit) => <option key={unit} value={unit}>{unit}</option>)}
            </select>
            <select aria-label="Filtrar por estado técnico" className="h-10 min-w-40 rounded-md border bg-background px-3 text-sm" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value as StatusFilter)}>
              <option value="all">Todos los estados</option>
              <option value="preliminary">Preliminar</option>
              <option value="in_review">En revisión técnica</option>
              <option value="validated">Validado técnicamente</option>
              <option value="legacy">Recursos anteriores</option>
            </select>
            <Button size="sm" variant={showInactive ? 'secondary' : 'outline'} onClick={() => setShowInactive((value) => !value)}>{showInactive ? 'Ocultar inactivos' : 'Mostrar inactivos'}</Button>
          </>
        )}
      </div>

      {view === 'materials' ? (
        <>
          <div className="flex items-center justify-between text-sm text-muted-foreground">
            <span>{filteredItems.length} resultados · Página {page} de {totalPages}</span>
            <span>{legacyCount} recursos anteriores sin evaluación técnica</span>
          </div>
          <div className="overflow-x-auto rounded-md border">
            <table className="w-full min-w-[850px] text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-3 font-medium">Código</th>
                  <th className="px-3 py-3 font-medium">Material / recurso</th>
                  <th className="px-3 py-3 font-medium">Familia técnica</th>
                  <th className="px-3 py-3 font-medium">Unidad</th>
                  <th className="px-3 py-3 font-medium">Estado técnico</th>
                  <th className="px-3 py-3 font-medium">Estado</th>
                  <th className="px-3 py-3 font-medium"><span className="sr-only">Detalle</span></th>
                </tr>
              </thead>
              <tbody>
                {pageRows.map((item) => {
                  const family = item.material_family_id ? familyById.get(item.material_family_id) : undefined;
                  const subfamily = item.material_subfamily_id ? subfamilyById.get(item.material_subfamily_id) : undefined;
                  const source = sourceByItemId.get(item.id) ?? null;
                  const isExpanded = selectedItemId === item.id;
                  return (
                    <Fragment key={item.id}>
                      <tr className="border-t align-top hover:bg-muted/30">
                        <td className="px-3 py-3 font-mono text-xs">{item.code ?? '—'}</td>
                        <td className="px-3 py-3"><p className="font-medium">{item.name}</p>{item.technical_specification && <p className="mt-1 max-w-sm text-xs text-muted-foreground">{item.technical_specification}</p>}</td>
                        <td className="px-3 py-3"><p>{family?.name ?? 'Sin familia'}</p><p className="text-xs text-muted-foreground">{subfamily?.name ?? 'Sin subfamilia asignada'}</p></td>
                        <td className="px-3 py-3">{item.default_unit_code}</td>
                        <td className="px-3 py-3"><Badge variant={statusVariant(item.technical_validation_status)}>{statusLabel(item.technical_validation_status)}</Badge></td>
                        <td className="px-3 py-3"><Badge variant={item.is_active ? 'default' : 'secondary'}>{item.is_active ? 'Activo' : 'Inactivo'}</Badge></td>
                        <td className="px-3 py-3">
                          <Button
                            size="sm"
                            variant="ghost"
                            aria-label={isExpanded ? 'Ocultar detalle' : 'Ver detalle'}
                            aria-expanded={isExpanded}
                            aria-controls={`material-details-${item.id}`}
                            onClick={() => setSelectedItemId((current) => current === item.id ? null : item.id)}
                          >
                            <ChevronDown className={'h-4 w-4 transition-transform ' + (isExpanded ? 'rotate-180' : '')} />
                          </Button>
                        </td>
                      </tr>
                      {isExpanded && (
                        <tr className="border-t bg-muted/20">
                          <td colSpan={7} className="px-3 py-4">
                            <div id={`material-details-${item.id}`} className="w-full min-w-0 rounded-lg border bg-card p-4">
                              <div className="mb-4 flex flex-wrap items-start justify-between gap-2">
                                <div className="min-w-0">
                                  <h3 className="break-words font-semibold">{item.name}</h3>
                                  <p className="break-words text-xs text-muted-foreground">{item.code ?? 'Sin código'} · {item.default_unit_code}</p>
                                </div>
                                <Badge variant={statusVariant(item.technical_validation_status)}>{statusLabel(item.technical_validation_status)}</Badge>
                              </div>
                              <div className="grid grid-cols-1 gap-x-6 gap-y-4 text-sm sm:grid-cols-2">
                                <div className="min-w-0">
                                  <p className="text-xs text-muted-foreground">Descripción</p>
                                  <p className="break-words [overflow-wrap:anywhere]">{item.description || 'Sin descripción'}</p>
                                </div>
                                <div className="min-w-0">
                                  <p className="text-xs text-muted-foreground">Especificación técnica</p>
                                  <p className="break-words [overflow-wrap:anywhere]">{item.technical_specification || 'Sin especificación registrada'}</p>
                                </div>
                                <div className="min-w-0">
                                  <p className="text-xs text-muted-foreground">Familia / subfamilia técnica</p>
                                  <p className="break-words [overflow-wrap:anywhere]">{family?.name ?? 'Sin familia'} / {subfamily?.name ?? 'Sin subfamilia asignada'}</p>
                                </div>
                                <div className="min-w-0">
                                  <p className="text-xs text-muted-foreground">Código original del Excel</p>
                                  <p className="break-words [overflow-wrap:anywhere]">{source?.source_code ?? 'Sin código de origen'}</p>
                                </div>
                                <div className="min-w-0">
                                  <p className="text-xs text-muted-foreground">Nombre original del Excel</p>
                                  <p className="break-words [overflow-wrap:anywhere]">{source?.source_name ?? 'Sin nombre de origen'}</p>
                                </div>
                                <div className="min-w-0">
                                  <p className="text-xs text-muted-foreground">Unidad original del Excel</p>
                                  <p className="break-words [overflow-wrap:anywhere]">{source?.source_unit ?? 'Sin unidad de origen'}</p>
                                </div>
                                {source && (
                                  <>
                                    <div className="min-w-0">
                                      <p className="text-xs text-muted-foreground">Familia / subfamilia original</p>
                                      <p className="break-words [overflow-wrap:anywhere]">{source.source_family || 'Sin familia de origen'} / {source.source_subfamily || 'Sin subfamilia de origen'}</p>
                                    </div>
                                    <div className="min-w-0">
                                      <p className="text-xs text-muted-foreground">Especificación original</p>
                                      <p className="break-words [overflow-wrap:anywhere]">{source.source_specification || 'Sin especificación original'}</p>
                                    </div>
                                    <div className="min-w-0">
                                      <p className="text-xs text-muted-foreground">Marca original</p>
                                      <p className="break-words [overflow-wrap:anywhere]">{source.source_brand || 'Sin marca registrada'}</p>
                                    </div>
                                  </>
                                )}
                                <div className="min-w-0">
                                  <p className="text-xs text-muted-foreground">Vinculación de origen</p>
                                  <Badge variant={source?.mapping_status === 'confirmed' ? 'secondary' : 'outline'}>{source?.mapping_status === 'confirmed' ? 'Identidad vinculada' : 'Sin vínculo confirmado'}</Badge>
                                </div>
                                <div className="min-w-0 sm:col-span-2">
                                  <p className="text-xs text-muted-foreground">Aprobación comercial</p>
                                  <p className="break-words text-muted-foreground">No evaluada en esta fase. Este estado técnico no habilita el recurso para cotizar.</p>
                                </div>
                              </div>
                            </div>
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  );
                })}
                {pageRows.length === 0 && <tr><td colSpan={7} className="px-4 py-10 text-center text-muted-foreground">No hay materiales que coincidan con los filtros.</td></tr>}
              </tbody>
            </table>
          </div>
          <div className="flex items-center justify-end gap-2">
            <Button size="sm" variant="outline" onClick={() => setPage((value) => Math.max(1, value - 1))} disabled={page <= 1}><ChevronLeft className="mr-1 h-4 w-4" />Anterior</Button>
            <Button size="sm" variant="outline" onClick={() => setPage((value) => Math.min(totalPages, value + 1))} disabled={page >= totalPages}>Siguiente<ChevronRight className="ml-1 h-4 w-4" /></Button>
          </div>
          {selectedItem && (
            <Card>
              <CardHeader><CardTitle className="text-base">{selectedItem.name}</CardTitle><CardDescription>{selectedItem.code ?? 'Sin código'} · {selectedItem.default_unit_code}</CardDescription></CardHeader>
              <CardContent className="grid gap-4 text-sm sm:grid-cols-2">
                <div><p className="text-xs text-muted-foreground">Descripción</p><p>{selectedItem.description || 'Sin descripción'}</p></div>
                <div><p className="text-xs text-muted-foreground">Especificación técnica</p><p>{selectedItem.technical_specification || 'Sin especificación registrada'}</p></div>
                <div><p className="text-xs text-muted-foreground">Familia / subfamilia</p><p>{selectedItem.material_family_id ? familyById.get(selectedItem.material_family_id)?.name ?? 'No encontrada' : 'Sin familia'} / {selectedItem.material_subfamily_id ? subfamilyById.get(selectedItem.material_subfamily_id)?.name ?? 'No encontrada' : 'Pendiente de asignación'}</p></div>
                <div><p className="text-xs text-muted-foreground">Identidad del Excel</p><p>{selectedSource ? selectedSource.source_code + ' · unidad original ' + selectedSource.source_unit : 'Sin vínculo de origen'}</p></div>
                {selectedSource && <div className="sm:col-span-2"><p className="text-xs text-muted-foreground">Clasificación original</p><p>{selectedSource.source_family || 'Sin familia de origen'} / {selectedSource.source_subfamily || 'Sin subfamilia de origen'}</p>{selectedSource.source_specification && <p className="mt-1 text-xs text-muted-foreground">{selectedSource.source_specification}</p>}{selectedSource.source_brand && <p className="mt-1 text-xs text-muted-foreground">Marca: {selectedSource.source_brand}</p>}</div>}
                <div><p className="text-xs text-muted-foreground">Vinculación de origen</p><Badge variant={selectedSource?.mapping_status === 'confirmed' ? 'secondary' : 'outline'}>{selectedSource?.mapping_status === 'confirmed' ? 'Identidad vinculada' : 'Sin vínculo confirmado'}</Badge></div>
                <div><p className="text-xs text-muted-foreground">Aprobación comercial</p><p className="text-muted-foreground">No evaluada en esta fase. Este estado técnico no habilita el recurso para cotizar.</p></div>
              </CardContent>
            </Card>
          )}
        </>
      ) : (
        <Card>
          <CardHeader><CardTitle className="text-base">Identidades pendientes de homologación</CardTitle><CardDescription>Se conservan los códigos y datos originales. Esta pantalla no fusiona ni aprueba equivalencias.</CardDescription></CardHeader>
          <CardContent>
            <div className="overflow-x-auto rounded-md border">
              <table className="w-full min-w-[720px] text-sm">
                <thead className="bg-muted/60 text-left"><tr><th className="px-3 py-3 font-medium">Código de origen</th><th className="px-3 py-3 font-medium">Material</th><th className="px-3 py-3 font-medium">Unidad original</th><th className="px-3 py-3 font-medium">Familia de origen</th><th className="px-3 py-3 font-medium">Motivo / estado</th></tr></thead>
                <tbody>
                  {filteredPending.map((source) => (
                    <tr key={source.id} className="border-t align-top">
                      <td className="px-3 py-3 font-mono text-xs">{source.source_code}</td>
                      <td className="px-3 py-3"><p className="font-medium">{source.source_name}</p>{source.source_specification && <p className="mt-1 text-xs text-muted-foreground">{source.source_specification}</p>}</td>
                      <td className="px-3 py-3">{source.source_unit}</td>
                      <td className="px-3 py-3">{source.source_family || 'Sin clasificar'}{source.source_subfamily && <p className="text-xs text-muted-foreground">{source.source_subfamily}</p>}</td>
                      <td className="px-3 py-3"><Badge variant="outline">{['GL', 'ZZ'].includes(source.source_unit.trim().toUpperCase()) ? 'Unidad por confirmar' : 'Revisión manual pendiente'}</Badge></td>
                    </tr>
                  ))}
                  {filteredPending.length === 0 && <tr><td colSpan={5} className="px-4 py-10 text-center text-muted-foreground">No hay identidades pendientes con ese criterio.</td></tr>}
                </tbody>
              </table>
            </div>
            <p className="mt-3 text-xs text-muted-foreground">Pendientes visibles: {filteredPending.length} de {pendingSources.length}. No se muestran costos, precios ni datos de proveedores.</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
