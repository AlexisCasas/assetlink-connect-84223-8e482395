import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Calculator, CalendarDays, CheckCircle2, RefreshCw, Save, Wallet } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

type QueryResult = { data: unknown; error: { message: string } | null };
interface CatalogQuery extends PromiseLike<QueryResult> {
  select(columns?: string): CatalogQuery;
  insert(values: Record<string, unknown>): CatalogQuery;
  update(values: Record<string, unknown>): CatalogQuery;
  eq(column: string, value: string | boolean): CatalogQuery;
  order(column: string, options?: { ascending?: boolean }): CatalogQuery;
}
const catalogDb = supabase as unknown as { from: (table: string) => CatalogQuery };

type CostItem = { id: string; name: string; code: string | null; default_unit_code: string; is_active: boolean };
type Supplier = { id: string; display_name: string; is_active: boolean };
type Unit = { code: string; name: string; dimension: string };
type FxSettings = {
  organization_id: string;
  default_usd_pen_rate: number | null;
  fx_source: string | null;
  fx_date: string | null;
  fx_reference: string | null;
};
type Rate = {
  id: string;
  cost_item_id: string;
  supplier_id: string | null;
  version_number: number;
  unit_code: string;
  currency_code: 'PEN' | 'USD';
  unit_cost_original: number;
  fx_rate_to_pen: number;
  unit_cost_pen: number;
  fx_source: string;
  fx_date: string | null;
  tax_treatment: string;
  tax_rate: number | null;
  source_type: string;
  source_reference: string | null;
  source_date: string | null;
  source_document_ref: string | null;
  source_notes: string | null;
  valid_from: string;
  valid_until: string | null;
  status: string;
  created_at: string;
};
type RateForm = {
  cost_item_id: string;
  supplier_id: string;
  unit_code: string;
  currency_code: 'PEN' | 'USD';
  unit_cost_original: string;
  fx_mode: 'default' | 'manual';
  fx_rate_to_pen: string;
  fx_date: string;
  fx_reference: string;
  tax_treatment: 'inclusive' | 'exclusive' | 'not_applicable' | 'unknown';
  tax_rate: string;
  source_type: 'supplier_quote' | 'supplier_invoice' | 'purchase_record' | 'internal_cost_sheet' | 'payroll_basis' | 'manual';
  source_reference: string;
  source_date: string;
  source_document_ref: string;
  source_notes: string;
  valid_from: string;
  valid_until: string;
};
const localToday = () => {
  const now = new Date();
  return new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
};
const newRateForm = (): RateForm => ({
  cost_item_id: '', supplier_id: '', unit_code: 'UND', currency_code: 'PEN',
  unit_cost_original: '', fx_mode: 'manual', fx_rate_to_pen: '', fx_date: '',
  fx_reference: '', tax_treatment: 'unknown', tax_rate: '', source_type: 'manual',
  source_reference: '', source_date: '', source_document_ref: '', source_notes: '',
  valid_from: localToday(), valid_until: '',
});
const money = (value: number, currency: 'PEN' | 'USD') =>
  new Intl.NumberFormat('es-PE', { style: 'currency', currency, maximumFractionDigits: 2 }).format(Number(value));
const dateLabel = (value: string | null) => value
  ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(value + 'T12:00:00Z'))
  : 'Sin vencimiento';
const sourceLabels: Record<string, string> = {
  supplier_quote: 'Cotización proveedor',
  supplier_invoice: 'Factura proveedor',
  purchase_record: 'Registro de compra',
  internal_cost_sheet: 'Hoja de costos interna',
  payroll_basis: 'Base de planilla',
  manual: 'Registro manual',
};
const statusLabels: Record<string, string> = {
  draft: 'Borrador', pending_review: 'Pendiente de revisión', approved: 'Aprobada',
  rejected: 'Rechazada', archived: 'Archivada',
};

export function CostRatesPanel() {
  const { currentOrganization, currentMembership, user } = useAuth();
  const organizationId = currentOrganization?.id ?? '';
  const canManage = currentOrganization?.organizationType === 'provider_company'
    && currentMembership?.isActive
    && currentMembership.organizationId === organizationId
    && !!currentMembership.role
    && ['owner', 'admin', 'manager', 'quote_manager'].includes(currentMembership.role);
  const canManageFx = !!currentMembership?.isActive
    && currentMembership.organizationId === organizationId
    && ['owner', 'admin', 'manager'].includes(currentMembership.role);

  const [items, setItems] = useState<CostItem[]>([]);
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [units, setUnits] = useState<Unit[]>([]);
  const [settings, setSettings] = useState<FxSettings | null>(null);
  const [rates, setRates] = useState<Rate[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [savingFx, setSavingFx] = useState(false);
  const [form, setForm] = useState<RateForm>(newRateForm());
  const [fxRateForm, setFxRateForm] = useState({ rate: '', date: '', reference: '' });

  const loadData = useCallback(async () => {
    if (!organizationId || !canManage) return;
    setLoading(true);
    try {
      const [itemResult, supplierResult, unitResult, settingResult, rateResult] = await Promise.all([
        catalogDb.from('provider_cost_items').select('*').eq('organization_id', organizationId).order('name'),
        catalogDb.from('provider_cost_suppliers').select('*').eq('organization_id', organizationId).order('display_name'),
        catalogDb.from('provider_cost_units').select('code,name,dimension').eq('is_active', true).order('name'),
        catalogDb.from('provider_cost_settings').select('*').eq('organization_id', organizationId),
        catalogDb.from('provider_cost_rates').select('*').eq('organization_id', organizationId).order('created_at', { ascending: false }),
      ]);
      for (const result of [itemResult, supplierResult, unitResult, settingResult, rateResult]) {
        if (result.error) throw new Error(result.error.message);
      }
      const loadedItems = (itemResult.data ?? []) as CostItem[];
      const loadedSettings = ((settingResult.data ?? []) as FxSettings[])[0] ?? null;
      setItems(loadedItems);
      setSuppliers((supplierResult.data ?? []) as Supplier[]);
      setUnits((unitResult.data ?? []) as Unit[]);
      setSettings(loadedSettings);
      setRates((rateResult.data ?? []) as Rate[]);
      if (loadedSettings) {
        setFxRateForm({
          rate: loadedSettings.default_usd_pen_rate === null ? '' : String(loadedSettings.default_usd_pen_rate),
          date: loadedSettings.fx_date ?? '',
          reference: loadedSettings.fx_reference ?? '',
        });
      }
      setForm((current) => ({
        ...current,
        cost_item_id: current.cost_item_id || loadedItems.find((item) => item.is_active)?.id || '',
        unit_code: current.cost_item_id
          ? current.unit_code
          : loadedItems.find((item) => item.is_active)?.default_unit_code || 'UND',
        fx_mode: loadedSettings?.default_usd_pen_rate ? 'default' : 'manual',
      }));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudieron cargar las tarifas.');
    } finally {
      setLoading(false);
    }
  }, [organizationId, canManage]);

  useEffect(() => { void loadData(); }, [loadData]);

  const activeItems = useMemo(() => items.filter((item) => item.is_active), [items]);
  const activeSuppliers = useMemo(() => suppliers.filter((supplier) => supplier.is_active), [suppliers]);
  const selectedItem = useMemo(
    () => activeItems.find((item) => item.id === form.cost_item_id) ?? null,
    [activeItems, form.cost_item_id],
  );
  const selectedSupplier = useMemo(
    () => activeSuppliers.find((supplier) => supplier.id === form.supplier_id) ?? null,
    [activeSuppliers, form.supplier_id],
  );
  const defaultFxReady = settings?.default_usd_pen_rate !== null
    && settings?.default_usd_pen_rate !== undefined
    && !!settings.fx_date;

  const saveDefaultFx = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!canManageFx || !organizationId || !user?.id) return;
    const rate = Number(fxRateForm.rate);
    if (!Number.isFinite(rate) || rate <= 0 || !fxRateForm.date) {
      toast.error('Ingresa un tipo de cambio mayor que cero y su fecha.');
      return;
    }
    setSavingFx(true);
    try {
      const payload = {
        default_usd_pen_rate: rate,
        fx_source: 'manual',
        fx_date: fxRateForm.date,
        fx_reference: fxRateForm.reference.trim() || null,
        updated_by: user.id,
      };
      const query = settings
        ? catalogDb.from('provider_cost_settings').update(payload).eq('organization_id', organizationId)
        : catalogDb.from('provider_cost_settings').insert({ organization_id: organizationId, ...payload });
      const { error } = await query;
      if (error) throw new Error(error.message);
      toast.success('Tipo de cambio predeterminado guardado.');
      await loadData();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo guardar el tipo de cambio.');
    } finally {
      setSavingFx(false);
    }
  };

  const saveRate = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!canManage || !organizationId || !selectedItem) return;
    const original = Number(form.unit_cost_original);
    if (!Number.isFinite(original) || original < 0) {
      toast.error('Ingresa un costo unitario válido.');
      return;
    }
    if (form.currency_code === 'USD' && form.fx_mode === 'default' && !defaultFxReady) {
      toast.error('Configura primero el tipo de cambio predeterminado o selecciona uno manual para esta tarifa.');
      return;
    }
    const manualFx = Number(form.fx_rate_to_pen);
    if (form.currency_code === 'USD' && form.fx_mode === 'manual'
      && (!Number.isFinite(manualFx) || manualFx <= 0 || !form.fx_date)) {
      toast.error('Para USD ingresa el tipo de cambio manual y su fecha.');
      return;
    }
    if (form.valid_until && form.valid_until < form.valid_from) {
      toast.error('La fecha de vencimiento no puede ser anterior al inicio de vigencia.');
      return;
    }
    setSaving(true);
    try {
      const isUsd = form.currency_code === 'USD';
      const payload: Record<string, unknown> = {
        organization_id: organizationId,
        cost_item_id: selectedItem.id,
        supplier_id: selectedSupplier?.id ?? null,
        unit_code: selectedItem.default_unit_code,
        currency_code: form.currency_code,
        unit_cost_original: original,
        fx_rate_to_pen: isUsd
          ? (form.fx_mode === 'default' ? 1 : manualFx)
          : 1,
        fx_source: isUsd
          ? (form.fx_mode === 'default' ? 'organization_default' : 'manual')
          : 'not_required',
        fx_date: isUsd && form.fx_mode === 'manual' ? form.fx_date : null,
        fx_reference: isUsd && form.fx_mode === 'manual' ? (form.fx_reference.trim() || null) : null,
        tax_treatment: form.tax_treatment,
        tax_rate: form.tax_rate.trim() ? Number(form.tax_rate) : null,
        source_type: form.source_type,
        source_reference: form.source_reference.trim() || null,
        source_date: form.source_date || null,
        source_document_ref: form.source_document_ref.trim() || null,
        source_notes: form.source_notes.trim() || null,
        valid_from: form.valid_from,
        valid_until: form.valid_until || null,
        status: 'pending_review',
      };
      const { error } = await catalogDb.from('provider_cost_rates').insert(payload);
      if (error) throw new Error(error.message);
      toast.success('Tarifa registrada y enviada a revisión.');
      setForm((current) => ({ ...newRateForm(), cost_item_id: current.cost_item_id, unit_code: selectedItem.default_unit_code }));
      await loadData();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo registrar la tarifa.');
    } finally {
      setSaving(false);
    }
  };

  if (!canManage) {
    return <Card><CardContent className="p-8 text-center text-sm text-muted-foreground">No tienes permisos para consultar el catálogo de tarifas de esta organización.</CardContent></Card>;
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">Tarifas registradas</h2>
          <p className="text-sm text-muted-foreground">Registra costos de proveedores o costos internos. Cada alta crea una nueva versión y conserva su fuente.</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => void loadData()} disabled={loading}>
          <RefreshCw className="mr-2 h-4 w-4" />Actualizar
        </Button>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base"><Wallet className="h-4 w-4" />Tipo de cambio predeterminado PEN/USD</CardTitle>
          <CardDescription>Se utiliza como referencia para nuevas tarifas en USD. Cada tarifa guarda una copia de la tasa y fecha usadas; cambiar el valor predeterminado no altera tarifas anteriores.</CardDescription>
        </CardHeader>
        <CardContent>
          {defaultFxReady && (
            <div className="mb-4 rounded-md border bg-muted/40 p-3 text-sm">
              <p className="font-medium">Configuración vigente: 1 USD = {Number(settings?.default_usd_pen_rate).toFixed(4)} PEN</p>
              <p className="text-muted-foreground">Fecha: {dateLabel(settings?.fx_date ?? null)}{settings?.fx_reference ? ` · ${settings.fx_reference}` : ''}</p>
            </div>
          )}
          {canManageFx ? (
            <form onSubmit={saveDefaultFx} className="grid gap-3 md:grid-cols-4">
              <div className="space-y-1.5"><Label htmlFor="default-fx-rate">Tipo de cambio</Label><Input id="default-fx-rate" type="number" min="0.000001" step="0.000001" value={fxRateForm.rate} onChange={(event) => setFxRateForm({ ...fxRateForm, rate: event.target.value })} required placeholder="Ej. 3.7500" /></div>
              <div className="space-y-1.5"><Label htmlFor="default-fx-date">Fecha de referencia</Label><Input id="default-fx-date" type="date" value={fxRateForm.date} onChange={(event) => setFxRateForm({ ...fxRateForm, date: event.target.value })} required /></div>
              <div className="space-y-1.5"><Label htmlFor="default-fx-ref">Fuente / referencia</Label><Input id="default-fx-ref" value={fxRateForm.reference} onChange={(event) => setFxRateForm({ ...fxRateForm, reference: event.target.value })} placeholder="Ej. fuente consultada" /></div>
              <div className="flex items-end"><Button type="submit" className="w-full" disabled={savingFx}><Save className="mr-2 h-4 w-4" />{savingFx ? 'Guardando…' : settings ? 'Actualizar referencia' : 'Guardar referencia'}</Button></div>
            </form>
          ) : (
            <p className="text-sm text-muted-foreground">Solo owner, admin o manager pueden modificar el tipo de cambio predeterminado.</p>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_390px]">
        <div className="space-y-3">
          {loading ? <p className="py-10 text-center text-sm text-muted-foreground">Cargando tarifas…</p> : rates.length === 0 ? (
            <Card><CardContent className="p-8 text-center">
              <Calculator className="mx-auto mb-2 h-8 w-8 text-muted-foreground" />
              <p className="font-medium">Todavía no hay tarifas registradas.</p>
              <p className="mt-1 text-sm text-muted-foreground">Las tarifas que registres aparecerán aquí con su versión, proveedor, moneda y estado de revisión.</p>
            </CardContent></Card>
          ) : rates.map((rate) => {
            const item = items.find((row) => row.id === rate.cost_item_id);
            const supplier = suppliers.find((row) => row.id === rate.supplier_id);
            return (
              <Card key={rate.id}>
                <CardContent className="space-y-2 p-4">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <p className="font-medium">{item?.name ?? 'Recurso no disponible'} <span className="text-xs text-muted-foreground">v{rate.version_number}</span></p>
                      <p className="text-xs text-muted-foreground">{supplier?.display_name ?? (rate.supplier_id ? 'Proveedor inactivo/no disponible' : 'Costo interno')}</p>
                    </div>
                    <Badge variant={rate.status === 'approved' ? 'default' : rate.status === 'rejected' ? 'destructive' : 'secondary'}>{statusLabels[rate.status] ?? rate.status}</Badge>
                  </div>
                  <div className="grid grid-cols-2 gap-3 rounded-md bg-muted/40 p-3 sm:grid-cols-3">
                    <div><p className="text-xs text-muted-foreground">Costo original</p><p className="font-semibold">{money(Number(rate.unit_cost_original), rate.currency_code)}</p></div>
                    <div><p className="text-xs text-muted-foreground">Equivalente PEN</p><p className="font-semibold">{money(Number(rate.unit_cost_pen), 'PEN')}</p></div>
                    <div><p className="text-xs text-muted-foreground">Unidad</p><p className="font-semibold">{rate.unit_code}</p></div>
                  </div>
                  <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
                    <span>Vigencia: {dateLabel(rate.valid_from)} – {dateLabel(rate.valid_until)}</span>
                    <span>Fuente: {sourceLabels[rate.source_type] ?? rate.source_type}</span>
                    {rate.currency_code === 'USD' && <span>FX: {Number(rate.fx_rate_to_pen).toFixed(4)} · {dateLabel(rate.fx_date)}</span>}
                    {rate.tax_treatment !== 'unknown' && <span>IGV: {rate.tax_treatment === 'inclusive' ? 'incluido' : rate.tax_treatment === 'exclusive' ? 'no incluido' : 'no aplica'}{rate.tax_rate !== null ? ` (${rate.tax_rate}%)` : ''}</span>}
                  </div>
                  {rate.source_reference && <p className="text-xs text-muted-foreground">Referencia: {rate.source_reference}</p>}
                </CardContent>
              </Card>
            );
          })}
        </div>

        <Card className="h-fit">
          <CardHeader>
            <CardTitle className="text-base">Registrar nueva tarifa</CardTitle>
            <CardDescription>Se guarda como pendiente de revisión. Para corregir un precio se crea una nueva versión; no se sobrescribe una tarifa aprobada.</CardDescription>
          </CardHeader>
          <CardContent>
            {activeItems.length === 0 ? <p className="text-sm text-muted-foreground">Primero registra al menos un recurso activo en la pestaña Recursos.</p> : (
              <form className="space-y-3" onSubmit={saveRate}>
                <div className="space-y-1.5"><Label htmlFor="rate-item">Recurso *</Label><select id="rate-item" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.cost_item_id} onChange={(event) => { const item = items.find((row) => row.id === event.target.value); setForm({ ...form, cost_item_id: event.target.value, unit_code: item?.default_unit_code ?? 'UND' }); }} required>{activeItems.map((item) => <option key={item.id} value={item.id}>{item.name}{item.code ? ` · ${item.code}` : ''}</option>)}</select></div>
                <div className="space-y-1.5"><Label htmlFor="rate-supplier">Proveedor</Label><select id="rate-supplier" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.supplier_id} onChange={(event) => setForm({ ...form, supplier_id: event.target.value })}><option value="">Costo interno / sin proveedor</option>{activeSuppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.display_name}</option>)}</select></div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1.5"><Label>Unidad del recurso</Label><div className="flex h-10 items-center rounded-md border bg-muted/40 px-3 text-sm">{selectedItem.default_unit_code}</div><p className="text-xs text-muted-foreground">La tarifa conserva la unidad base del recurso; no se realizan conversiones automáticas.</p></div>
                  <div className="space-y-1.5"><Label htmlFor="rate-currency">Moneda *</Label><select id="rate-currency" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.currency_code} onChange={(event) => setForm({ ...form, currency_code: event.target.value as 'PEN' | 'USD', fx_mode: defaultFxReady ? 'default' : 'manual' })}><option value="PEN">PEN · Soles</option><option value="USD">USD · Dólares</option></select></div>
                </div>
                <div className="space-y-1.5"><Label htmlFor="rate-original-cost">Costo unitario *</Label><Input id="rate-original-cost" type="number" min="0" step="0.000001" value={form.unit_cost_original} onChange={(event) => setForm({ ...form, unit_cost_original: event.target.value })} required /></div>
                {form.currency_code === 'USD' && (
                  <div className="space-y-3 rounded-md border p-3">
                    <Label>Conversión a soles</Label>
                    {defaultFxReady && <label className="flex items-center gap-2 text-sm"><input type="radio" name="rate-fx-mode" checked={form.fx_mode === 'default'} onChange={() => setForm({ ...form, fx_mode: 'default' })} />Usar tipo de cambio predeterminado ({Number(settings?.default_usd_pen_rate).toFixed(4)})</label>}
                    <label className="flex items-center gap-2 text-sm"><input type="radio" name="rate-fx-mode" checked={form.fx_mode === 'manual'} onChange={() => setForm({ ...form, fx_mode: 'manual' })} />Registrar tipo de cambio para esta tarifa</label>
                    {form.fx_mode === 'manual' && <div className="grid gap-2">
                      <div className="space-y-1.5"><Label htmlFor="rate-fx-value">Tipo de cambio *</Label><Input id="rate-fx-value" type="number" min="0.000001" step="0.000001" value={form.fx_rate_to_pen} onChange={(event) => setForm({ ...form, fx_rate_to_pen: event.target.value })} required /></div>
                      <div className="space-y-1.5"><Label htmlFor="rate-fx-date">Fecha del tipo de cambio *</Label><Input id="rate-fx-date" type="date" value={form.fx_date} onChange={(event) => setForm({ ...form, fx_date: event.target.value })} required /></div>
                      <div className="space-y-1.5"><Label htmlFor="rate-fx-reference">Fuente / referencia</Label><Input id="rate-fx-reference" value={form.fx_reference} onChange={(event) => setForm({ ...form, fx_reference: event.target.value })} placeholder="Opcional" /></div>
                    </div>}
                  </div>
                )}
                <div className="space-y-1.5"><Label htmlFor="rate-source">Origen del costo *</Label><select id="rate-source" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.source_type} onChange={(event) => setForm({ ...form, source_type: event.target.value as RateForm['source_type'] })}><option value="supplier_quote">Cotización de proveedor</option><option value="supplier_invoice">Factura de proveedor</option><option value="purchase_record">Registro de compra</option><option value="internal_cost_sheet">Hoja de costos interna</option><option value="payroll_basis">Base de planilla</option><option value="manual">Registro manual</option></select></div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1.5"><Label htmlFor="rate-source-ref">N.° referencia</Label><Input id="rate-source-ref" value={form.source_reference} onChange={(event) => setForm({ ...form, source_reference: event.target.value })} /></div>
                  <div className="space-y-1.5"><Label htmlFor="rate-source-date">Fecha fuente</Label><Input id="rate-source-date" type="date" value={form.source_date} onChange={(event) => setForm({ ...form, source_date: event.target.value })} /></div>
                </div>
                <div className="space-y-1.5"><Label htmlFor="rate-document-ref">Documento / ubicación</Label><Input id="rate-document-ref" value={form.source_document_ref} onChange={(event) => setForm({ ...form, source_document_ref: event.target.value })} placeholder="Nombre o referencia del archivo" /></div>
                <div className="space-y-1.5"><Label htmlFor="rate-tax">Tratamiento de IGV</Label><select id="rate-tax" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.tax_treatment} onChange={(event) => setForm({ ...form, tax_treatment: event.target.value as RateForm['tax_treatment'] })}><option value="unknown">Por confirmar</option><option value="inclusive">Incluido</option><option value="exclusive">No incluido</option><option value="not_applicable">No aplica</option></select></div>
                <div className="space-y-1.5"><Label htmlFor="rate-tax-value">Tasa IGV (%)</Label><Input id="rate-tax-value" type="number" min="0" max="100" step="0.0001" value={form.tax_rate} onChange={(event) => setForm({ ...form, tax_rate: event.target.value })} placeholder="Opcional" /></div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1.5"><Label htmlFor="rate-valid-from">Vigente desde *</Label><Input id="rate-valid-from" type="date" value={form.valid_from} onChange={(event) => setForm({ ...form, valid_from: event.target.value })} required /></div>
                  <div className="space-y-1.5"><Label htmlFor="rate-valid-until">Hasta</Label><Input id="rate-valid-until" type="date" value={form.valid_until} onChange={(event) => setForm({ ...form, valid_until: event.target.value })} /></div>
                </div>
                <div className="space-y-1.5"><Label htmlFor="rate-notes">Observaciones</Label><Textarea id="rate-notes" rows={2} value={form.source_notes} onChange={(event) => setForm({ ...form, source_notes: event.target.value })} /></div>
                <div className="rounded-md bg-muted/40 p-3 text-xs text-muted-foreground">
                  <p className="font-medium text-foreground">Resultado estimado</p>
                  {form.currency_code === 'PEN'
                    ? money(Number(form.unit_cost_original || 0), 'PEN')
                    : form.fx_mode === 'default' && defaultFxReady
                      ? money(Number(form.unit_cost_original || 0) * Number(settings?.default_usd_pen_rate), 'PEN')
                      : money(Number(form.unit_cost_original || 0) * Number(form.fx_rate_to_pen || 0), 'PEN')}
                  <p className="mt-1">La tarifa se guardará como pendiente de revisión. No se modifica el precio de venta ni las cotizaciones históricas.</p>
                </div>
                <Button type="submit" className="w-full" disabled={saving || !form.cost_item_id || !form.unit_cost_original || (form.currency_code === 'USD' && form.fx_mode === 'default' && !defaultFxReady)}>
                  <CheckCircle2 className="mr-2 h-4 w-4" />{saving ? 'Registrando…' : 'Registrar tarifa'}
                </Button>
              </form>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
