import { FormEvent, useCallback, useEffect, useState } from 'react';
import { RefreshCw, Save, Settings2 } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

type QueryResult = { data: unknown; error: { message: string } | null };
interface SettingsQuery extends PromiseLike<QueryResult> {
  select(columns?: string): SettingsQuery;
  insert(values: Record<string, unknown>): SettingsQuery;
  update(values: Record<string, unknown>): SettingsQuery;
  eq(column: string, value: string | boolean): SettingsQuery;
}
const settingsDb = supabase as unknown as { from: (table: string) => SettingsQuery };

type PricingSettings = {
  organization_id: string;
  base_currency_code: string;
  default_usd_pen_rate: number | null;
  fx_source: string | null;
  fx_date: string | null;
  fx_reference: string | null;
};

export function PricingRulesPanel() {
  const { currentOrganization, currentMembership, user } = useAuth();
  const organizationId = currentOrganization?.id ?? '';
  const [settings, setSettings] = useState<PricingSettings | null>(null);
  const [rate, setRate] = useState('');
  const [date, setDate] = useState('');
  const [reference, setReference] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!organizationId || !currentMembership?.isActive || currentMembership.organizationId !== organizationId) {
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await settingsDb.from('provider_cost_settings')
        .select('organization_id,base_currency_code,default_usd_pen_rate,fx_source,fx_date,fx_reference')
        .eq('organization_id', organizationId);
      if (error) throw new Error(error.message);
      const current = ((data ?? []) as PricingSettings[])[0] ?? null;
      setSettings(current);
      setRate(current?.default_usd_pen_rate == null ? '' : String(current.default_usd_pen_rate));
      setDate(current?.fx_date ?? '');
      setReference(current?.fx_reference ?? '');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo cargar la configuración comercial.');
    } finally {
      setLoading(false);
    }
  }, [organizationId, currentMembership?.isActive, currentMembership?.organizationId]);

  useEffect(() => { void load(); }, [load]);

  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!organizationId || !user?.id) return;
    const numericRate = Number(rate);
    if (!Number.isFinite(numericRate) || numericRate <= 0 || !date) {
      toast.error('Ingresa un tipo de cambio mayor que cero y una fecha de referencia.');
      return;
    }
    setSaving(true);
    try {
      const payload = {
        default_usd_pen_rate: numericRate,
        fx_source: 'manual',
        fx_date: date,
        fx_reference: reference.trim() || null,
        updated_by: user.id,
      };
      const query = settings
        ? settingsDb.from('provider_cost_settings').update(payload).eq('organization_id', organizationId)
        : settingsDb.from('provider_cost_settings').insert({ organization_id: organizationId, ...payload });
      const { error } = await query;
      if (error) throw new Error(error.message);
      toast.success('Configuración FX guardada.');
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo guardar la configuración FX.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-5">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base"><Settings2 className="h-5 w-5" />Parámetros comerciales ROMAX</CardTitle>
          <CardDescription>Esta fase protege el acceso a la configuración FX existente. Los tramos FII, IGV y sus versiones se implementarán en R2-E2.2.</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? <p className="py-6 text-sm text-muted-foreground">Cargando configuración…</p> : (
            <>
              <div className="mb-4 rounded-md border bg-muted/40 p-3 text-sm">
                <p className="font-medium">Moneda base: {settings?.base_currency_code ?? 'PEN'}</p>
                <p className="mt-1 text-muted-foreground">Tipo de cambio configurado: {settings?.default_usd_pen_rate == null ? 'No configurado' : '1 USD = ' + Number(settings.default_usd_pen_rate).toFixed(4) + ' PEN'}</p>
                <p className="text-muted-foreground">Fecha: {settings?.fx_date ?? 'Sin fecha'}{settings?.fx_reference ? ' · ' + settings.fx_reference : ''}</p>
              </div>
              <form className="grid gap-3 md:grid-cols-4" onSubmit={save}>
                <div className="space-y-1.5"><Label htmlFor="romax-rules-fx-rate">Tipo de cambio USD/PEN</Label><Input id="romax-rules-fx-rate" type="number" min="0.000001" step="0.000001" value={rate} onChange={(event) => setRate(event.target.value)} required /></div>
                <div className="space-y-1.5"><Label htmlFor="romax-rules-fx-date">Fecha de referencia</Label><Input id="romax-rules-fx-date" type="date" value={date} onChange={(event) => setDate(event.target.value)} required /></div>
                <div className="space-y-1.5"><Label htmlFor="romax-rules-fx-reference">Fuente / referencia</Label><Input id="romax-rules-fx-reference" value={reference} onChange={(event) => setReference(event.target.value)} placeholder="Fuente consultada" /></div>
                <div className="flex items-end"><Button type="submit" className="w-full" disabled={saving}><Save className="mr-2 h-4 w-4" />{saving ? 'Guardando…' : 'Guardar configuración'}</Button></div>
              </form>
            </>
          )}
        </CardContent>
      </Card>
      <div className="flex justify-end"><Button variant="outline" size="sm" onClick={() => void load()} disabled={loading}><RefreshCw className="mr-2 h-4 w-4" />Actualizar</Button></div>
    </div>
  );
}
