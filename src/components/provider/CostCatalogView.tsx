import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Archive, Box, Building2, Check, Edit2, Plus, RefreshCw, Search, Truck, X } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { CostRatesPanel } from '@/components/provider/CostRatesPanel';

type CatalogRow = {
  id: string;
  organization_id: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

type Supplier = CatalogRow & {
  display_name: string;
  legal_name: string | null;
  tax_id: string | null;
  email: string | null;
  phone: string | null;
  notes: string | null;
};

type CostItem = CatalogRow & {
  code: string | null;
  name: string;
  description: string | null;
  category_code: string;
  default_unit_code: string;
  technical_specification: string | null;
};

type Category = { code: string; name: string; cost_level: string; sort_order: number };
type Unit = { code: string; name: string; dimension: string };

type QueryResult = { data: unknown; error: { message: string } | null };
interface CatalogQuery extends PromiseLike<QueryResult> {
  select(columns?: string): CatalogQuery;
  insert(values: Record<string, unknown>): CatalogQuery;
  update(values: Record<string, unknown>): CatalogQuery;
  eq(column: string, value: string | boolean): CatalogQuery;
  order(column: string, options?: { ascending?: boolean }): CatalogQuery;
}
const catalogDb = supabase as unknown as { from: (table: string) => CatalogQuery };

type CatalogTab = 'suppliers' | 'items' | 'rates';
const canManageCostCatalog = (role: string | undefined) =>
  !!role && ['owner', 'admin', 'manager', 'quote_manager'].includes(role);

const emptySupplier = {
  display_name: '', legal_name: '', tax_id: '', email: '', phone: '', notes: '',
};
const emptyItem = {
  code: '', name: '', description: '', category_code: 'MATERIAL',
  default_unit_code: 'UND', technical_specification: '',
};

export function CostCatalogView() {
  const { currentOrganization, currentMembership } = useAuth();
  const organizationId = currentOrganization?.id ?? '';
  const authorized = currentOrganization?.organizationType === 'provider_company'
    && currentMembership?.isActive
    && currentMembership.organizationId === organizationId
    && canManageCostCatalog(currentMembership.role);

  const [tab, setTab] = useState<CatalogTab>('items');
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [items, setItems] = useState<CostItem[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [units, setUnits] = useState<Unit[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState('');
  const [showInactive, setShowInactive] = useState(false);
  const [supplierForm, setSupplierForm] = useState(emptySupplier);
  const [itemForm, setItemForm] = useState(emptyItem);
  const [editingSupplierId, setEditingSupplierId] = useState<string | null>(null);
  const [editingItemId, setEditingItemId] = useState<string | null>(null);

  const loadCatalog = useCallback(async () => {
    if (!organizationId || !authorized) return;
    setLoading(true);
    try {
      const [supplierResult, itemResult, categoryResult, unitResult] = await Promise.all([
        catalogDb.from('provider_cost_suppliers').select('*').eq('organization_id', organizationId).order('display_name'),
        catalogDb.from('provider_cost_items').select('*').eq('organization_id', organizationId).order('name'),
        catalogDb.from('provider_cost_categories').select('code,name,cost_level,sort_order').eq('is_active', true).order('sort_order'),
        catalogDb.from('provider_cost_units').select('code,name,dimension').eq('is_active', true).order('name'),
      ]);
      for (const result of [supplierResult, itemResult, categoryResult, unitResult]) {
        if (result.error) throw new Error(result.error.message);
      }
      setSuppliers((supplierResult.data ?? []) as Supplier[]);
      setItems((itemResult.data ?? []) as CostItem[]);
      setCategories((categoryResult.data ?? []) as Category[]);
      setUnits((unitResult.data ?? []) as Unit[]);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo cargar el catálogo.');
    } finally {
      setLoading(false);
    }
  }, [organizationId, authorized]);

  useEffect(() => { void loadCatalog(); }, [loadCatalog]);

  const filteredSuppliers = useMemo(() => suppliers.filter((supplier) => {
    const text = [supplier.display_name, supplier.legal_name, supplier.tax_id, supplier.email].filter(Boolean).join(' ').toLowerCase();
    return (showInactive || supplier.is_active) && (!search || text.includes(search.toLowerCase()));
  }), [suppliers, search, showInactive]);

  const filteredItems = useMemo(() => items.filter((item) => {
    const text = [item.code, item.name, item.description, item.technical_specification, item.category_code, item.default_unit_code].filter(Boolean).join(' ').toLowerCase();
    return (showInactive || item.is_active) && (!search || text.includes(search.toLowerCase()));
  }), [items, search, showInactive]);

  const resetSupplierForm = () => { setSupplierForm(emptySupplier); setEditingSupplierId(null); };
  const resetItemForm = () => { setItemForm(emptyItem); setEditingItemId(null); };

  const saveSupplier = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!authorized || !organizationId || !supplierForm.display_name.trim()) return;
    setSaving(true);
    try {
      const payload = {
        display_name: supplierForm.display_name.trim(),
        legal_name: supplierForm.legal_name.trim() || null,
        tax_id: supplierForm.tax_id.trim() || null,
        email: supplierForm.email.trim() || null,
        phone: supplierForm.phone.trim() || null,
        notes: supplierForm.notes.trim() || null,
      };
      const query = editingSupplierId
        ? catalogDb.from('provider_cost_suppliers').update(payload).eq('id', editingSupplierId).eq('organization_id', organizationId)
        : catalogDb.from('provider_cost_suppliers').insert({ organization_id: organizationId, ...payload });
      const { data, error } = await (editingSupplierId ? query.select('id') : query);
      if (error) throw new Error(error.message);
      if (editingSupplierId && (!Array.isArray(data) || data.length !== 1)) throw new Error('El proveedor no pudo actualizarse. Verifica permisos y vuelve a cargar.');
      toast.success(editingSupplierId ? 'Proveedor actualizado.' : 'Proveedor registrado.');
      resetSupplierForm();
      await loadCatalog();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo guardar el proveedor.');
    } finally {
      setSaving(false);
    }
  };

  const saveItem = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!authorized || !organizationId || !itemForm.name.trim()) return;
    setSaving(true);
    try {
      const payload = {
        code: itemForm.code.trim() || null,
        name: itemForm.name.trim(),
        description: itemForm.description.trim() || null,
        category_code: itemForm.category_code,
        default_unit_code: itemForm.default_unit_code,
        technical_specification: itemForm.technical_specification.trim() || null,
      };
      const query = editingItemId
        ? catalogDb.from('provider_cost_items').update(payload).eq('id', editingItemId).eq('organization_id', organizationId)
        : catalogDb.from('provider_cost_items').insert({ organization_id: organizationId, ...payload });
      const { data, error } = await (editingItemId ? query.select('id') : query);
      if (error) throw new Error(error.message);
      if (editingItemId && (!Array.isArray(data) || data.length !== 1)) throw new Error('El recurso no pudo actualizarse. Verifica permisos y vuelve a cargar.');
      toast.success(editingItemId ? 'Recurso actualizado.' : 'Recurso registrado.');
      resetItemForm();
      await loadCatalog();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo guardar el recurso.');
    } finally {
      setSaving(false);
    }
  };

  const toggleActive = async (kind: CatalogTab, row: Supplier | CostItem) => {
    if (!authorized || !organizationId) return;
    const table = kind === 'suppliers' ? 'provider_cost_suppliers' : 'provider_cost_items';
    try {
      const { data, error } = await catalogDb.from(table).update({ is_active: !row.is_active })
        .eq('id', row.id).eq('organization_id', organizationId).select('id');
      if (error) throw new Error(error.message);
      if (!Array.isArray(data) || data.length !== 1) throw new Error('No se actualizó el estado. Verifica tus permisos y vuelve a cargar.');
      toast.success(row.is_active ? 'Registro desactivado.' : 'Registro activado.');
      await loadCatalog();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo cambiar el estado.');
    }
  };

  if (!authorized) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center p-6">
        <Card className="max-w-lg"><CardContent className="p-8 text-center">
          <h2 className="font-semibold">Acceso restringido</h2>
          <p className="mt-2 text-sm text-muted-foreground">El catálogo de costos está disponible para usuarios autorizados de organizaciones proveedoras.</p>
        </CardContent></Card>
      </div>
    );
  }

  const activeSuppliers = suppliers.filter((row) => row.is_active).length;
  const activeItems = items.filter((row) => row.is_active).length;

  return (
    <div className="space-y-6 p-6">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Catálogo de costos</h1>
          <p className="mt-1 text-sm text-muted-foreground">Administra proveedores y recursos reutilizables para preparar nuevas cotizaciones.</p>
        </div>
        <Button variant="outline" onClick={() => void loadCatalog()} disabled={loading}>
          <RefreshCw className="mr-2 h-4 w-4" />Actualizar
        </Button>
      </header>

      <div className="grid gap-3 sm:grid-cols-2">
        <Card><CardContent className="flex items-center gap-3 p-4">
          <div className="rounded-lg bg-muted p-3"><Truck className="h-5 w-5" /></div>
          <div><p className="text-sm text-muted-foreground">Proveedores activos</p><p className="text-2xl font-semibold">{activeSuppliers}</p></div>
        </CardContent></Card>
        <Card><CardContent className="flex items-center gap-3 p-4">
          <div className="rounded-lg bg-muted p-3"><Box className="h-5 w-5" /></div>
          <div><p className="text-sm text-muted-foreground">Recursos activos</p><p className="text-2xl font-semibold">{activeItems}</p></div>
        </CardContent></Card>
      </div>

      <div className="flex flex-wrap items-center gap-2 border-b pb-3">
        <Button size="sm" variant={tab === 'items' ? 'default' : 'outline'} onClick={() => { setTab('items'); setSearch(''); }}>Recursos</Button>
        <Button size="sm" variant={tab === 'suppliers' ? 'default' : 'outline'} onClick={() => { setTab('suppliers'); setSearch(''); }}>Proveedores</Button>
        <Button size="sm" variant={tab === 'rates' ? 'default' : 'outline'} onClick={() => { setTab('rates'); setSearch(''); }}>Tarifas</Button>
      </div>

      {tab !== 'rates' && (
        <div className="flex flex-wrap items-center gap-3">
          <div className="relative min-w-56 flex-1">
            <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
            <Input value={search} onChange={(event) => setSearch(event.target.value)} className="pl-9" placeholder={tab === 'items' ? 'Buscar recursos...' : 'Buscar proveedores...'} />
          </div>
          <Button size="sm" variant={showInactive ? 'secondary' : 'outline'} onClick={() => setShowInactive((value) => !value)}>
            {showInactive ? 'Ocultar inactivos' : 'Mostrar inactivos'}
          </Button>
        </div>
      )}

      {tab === 'rates' ? (
        <CostRatesPanel />
      ) : loading ? <div className="py-12 text-center text-sm text-muted-foreground">Cargando catálogo…</div> : (
        <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_380px]">
          <div className="space-y-3">
            {tab === 'items' ? filteredItems.map((item) => (
              <Card key={item.id}>
                <CardContent className="flex flex-wrap items-start justify-between gap-4 p-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-medium">{item.name}</p>
                      <Badge variant={item.is_active ? 'default' : 'secondary'}>{item.is_active ? 'Activo' : 'Inactivo'}</Badge>
                      {item.code && <span className="text-xs text-muted-foreground">{item.code}</span>}
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">{categories.find((category) => category.code === item.category_code)?.name ?? item.category_code} · {units.find((unit) => unit.code === item.default_unit_code)?.name ?? item.default_unit_code}</p>
                    {item.description && <p className="mt-2 text-sm">{item.description}</p>}
                    {item.technical_specification && <p className="mt-1 text-xs text-muted-foreground">Especificación: {item.technical_specification}</p>}
                  </div>
                  <div className="flex shrink-0 gap-2">
                    <Button size="sm" variant="outline" onClick={() => { setItemForm({ code: item.code ?? '', name: item.name, description: item.description ?? '', category_code: item.category_code, default_unit_code: item.default_unit_code, technical_specification: item.technical_specification ?? '' }); setEditingItemId(item.id); setTab('items'); }}><Edit2 className="mr-1 h-3.5 w-3.5" />Editar</Button>
                    <Button size="sm" variant="ghost" onClick={() => void toggleActive('items', item)}>{item.is_active ? <Archive className="mr-1 h-3.5 w-3.5" /> : <Check className="mr-1 h-3.5 w-3.5" />}{item.is_active ? 'Desactivar' : 'Activar'}</Button>
                  </div>
                </CardContent>
              </Card>
            )) : filteredSuppliers.map((supplier) => (
              <Card key={supplier.id}>
                <CardContent className="flex flex-wrap items-start justify-between gap-4 p-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-medium">{supplier.display_name}</p>
                      <Badge variant={supplier.is_active ? 'default' : 'secondary'}>{supplier.is_active ? 'Activo' : 'Inactivo'}</Badge>
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">{supplier.legal_name || 'Sin razón social'} · RUC {supplier.tax_id || 'no informado'}</p>
                    {(supplier.email || supplier.phone) && <p className="mt-1 text-xs text-muted-foreground">{[supplier.email, supplier.phone].filter(Boolean).join(' · ')}</p>}
                    {supplier.notes && <p className="mt-2 text-sm">{supplier.notes}</p>}
                  </div>
                  <div className="flex shrink-0 gap-2">
                    <Button size="sm" variant="outline" onClick={() => { setSupplierForm({ display_name: supplier.display_name, legal_name: supplier.legal_name ?? '', tax_id: supplier.tax_id ?? '', email: supplier.email ?? '', phone: supplier.phone ?? '', notes: supplier.notes ?? '' }); setEditingSupplierId(supplier.id); setTab('suppliers'); }}><Edit2 className="mr-1 h-3.5 w-3.5" />Editar</Button>
                    <Button size="sm" variant="ghost" onClick={() => void toggleActive('suppliers', supplier)}>{supplier.is_active ? <Archive className="mr-1 h-3.5 w-3.5" /> : <Check className="mr-1 h-3.5 w-3.5" />}{supplier.is_active ? 'Desactivar' : 'Activar'}</Button>
                  </div>
                </CardContent>
              </Card>
            ))}
            {tab === 'items' && filteredItems.length === 0 && <Card><CardContent className="p-8 text-center"><Box className="mx-auto mb-2 h-7 w-7 text-muted-foreground" /><p className="font-medium">Todavía no hay recursos registrados.</p><p className="mt-1 text-sm text-muted-foreground">Agrega materiales, mano de obra, equipos o servicios para reutilizarlos en futuras cotizaciones.</p></CardContent></Card>}
            {tab === 'suppliers' && filteredSuppliers.length === 0 && <Card><CardContent className="p-8 text-center"><Building2 className="mx-auto mb-2 h-7 w-7 text-muted-foreground" /><p className="font-medium">Todavía no hay proveedores registrados.</p><p className="mt-1 text-sm text-muted-foreground">Registra un proveedor cuando necesites asociarlo a una tarifa o comparar alternativas.</p></CardContent></Card>}
          </div>

          <Card className="h-fit">
            <CardHeader>
              <CardTitle className="text-base">{tab === 'items' ? (editingItemId ? 'Editar recurso' : 'Nuevo recurso') : (editingSupplierId ? 'Editar proveedor' : 'Nuevo proveedor')}</CardTitle>
              <CardDescription>{tab === 'items' ? 'El recurso se podrá asociar a uno o varios proveedores más adelante.' : 'El proveedor puede registrarse ahora y asociarse a una tarifa cuando corresponda.'}</CardDescription>
            </CardHeader>
            <CardContent>
              {tab === 'items' ? (
                <form className="space-y-3" onSubmit={saveItem}>
                  <div className="space-y-1.5"><Label htmlFor="cost-item-name">Nombre *</Label><Input id="cost-item-name" value={itemForm.name} onChange={(event) => setItemForm({ ...itemForm, name: event.target.value })} required maxLength={200} /></div>
                  <div className="space-y-1.5"><Label htmlFor="cost-item-code">Código interno</Label><Input id="cost-item-code" value={itemForm.code} onChange={(event) => setItemForm({ ...itemForm, code: event.target.value })} maxLength={60} placeholder="Opcional" /></div>
                  <div className="space-y-1.5"><Label htmlFor="cost-item-category">Categoría *</Label><select id="cost-item-category" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={itemForm.category_code} onChange={(event) => setItemForm({ ...itemForm, category_code: event.target.value })}>{categories.map((category) => <option key={category.code} value={category.code}>{category.name}</option>)}</select></div>
                  <div className="space-y-1.5"><Label htmlFor="cost-item-unit">Unidad base *</Label><select id="cost-item-unit" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={itemForm.default_unit_code} onChange={(event) => setItemForm({ ...itemForm, default_unit_code: event.target.value })}>{units.map((unit) => <option key={unit.code} value={unit.code}>{unit.code} · {unit.name}</option>)}</select></div>
                  <div className="space-y-1.5"><Label htmlFor="cost-item-description">Descripción</Label><Textarea id="cost-item-description" value={itemForm.description} onChange={(event) => setItemForm({ ...itemForm, description: event.target.value })} rows={2} /></div>
                  <div className="space-y-1.5"><Label htmlFor="cost-item-spec">Especificación técnica</Label><Textarea id="cost-item-spec" value={itemForm.technical_specification} onChange={(event) => setItemForm({ ...itemForm, technical_specification: event.target.value })} rows={2} /></div>
                  <div className="flex gap-2 pt-2"><Button type="submit" disabled={saving || !itemForm.name.trim()} className="flex-1"><Plus className="mr-2 h-4 w-4" />{saving ? 'Guardando…' : editingItemId ? 'Guardar cambios' : 'Registrar recurso'}</Button>{editingItemId && <Button type="button" variant="outline" onClick={resetItemForm}><X className="h-4 w-4" /></Button>}</div>
                </form>
              ) : (
                <form className="space-y-3" onSubmit={saveSupplier}>
                  <div className="space-y-1.5"><Label htmlFor="supplier-display-name">Nombre comercial *</Label><Input id="supplier-display-name" value={supplierForm.display_name} onChange={(event) => setSupplierForm({ ...supplierForm, display_name: event.target.value })} required maxLength={200} /></div>
                  <div className="space-y-1.5"><Label htmlFor="supplier-legal-name">Razón social</Label><Input id="supplier-legal-name" value={supplierForm.legal_name} onChange={(event) => setSupplierForm({ ...supplierForm, legal_name: event.target.value })} maxLength={200} /></div>
                  <div className="space-y-1.5"><Label htmlFor="supplier-tax-id">RUC</Label><Input id="supplier-tax-id" value={supplierForm.tax_id} onChange={(event) => setSupplierForm({ ...supplierForm, tax_id: event.target.value.replace(/\D/g, '').slice(0, 20) })} maxLength={20} inputMode="numeric" /></div>
                  <div className="space-y-1.5"><Label htmlFor="supplier-email">Correo</Label><Input id="supplier-email" type="email" value={supplierForm.email} onChange={(event) => setSupplierForm({ ...supplierForm, email: event.target.value })} /></div>
                  <div className="space-y-1.5"><Label htmlFor="supplier-phone">Teléfono</Label><Input id="supplier-phone" value={supplierForm.phone} onChange={(event) => setSupplierForm({ ...supplierForm, phone: event.target.value })} maxLength={40} /></div>
                  <div className="space-y-1.5"><Label htmlFor="supplier-notes">Observaciones</Label><Textarea id="supplier-notes" value={supplierForm.notes} onChange={(event) => setSupplierForm({ ...supplierForm, notes: event.target.value })} rows={3} /></div>
                  <div className="flex gap-2 pt-2"><Button type="submit" disabled={saving || !supplierForm.display_name.trim()} className="flex-1"><Plus className="mr-2 h-4 w-4" />{saving ? 'Guardando…' : editingSupplierId ? 'Guardar cambios' : 'Registrar proveedor'}</Button>{editingSupplierId && <Button type="button" variant="outline" onClick={resetSupplierForm}><X className="h-4 w-4" /></Button>}</div>
                </form>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
