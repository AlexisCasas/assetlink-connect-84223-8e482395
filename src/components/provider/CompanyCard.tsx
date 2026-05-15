import { useState, useRef } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Pencil, Save, X, Upload, Building2 } from 'lucide-react';
import type { ProviderProfileRow } from '@/types/provider';
import { COUNTRIES, CURRENCIES, TIMEZONES } from '@/types/provider';

interface Props {
  profile: ProviderProfileRow;
  onUpdated: (p: ProviderProfileRow) => void;
}

const required: (keyof ProviderProfileRow)[] = ['business_name','tax_id','country','currency','timezone'];

export const CompanyCard = ({ profile, onUpdated }: Props) => {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const [form, setForm] = useState({
    business_name: profile.business_name ?? '',
    commercial_name: profile.commercial_name ?? '',
    tax_id: profile.tax_id ?? '',
    country: profile.country ?? '',
    currency: profile.currency ?? '',
    timezone: profile.timezone ?? '',
    fiscal_address: profile.fiscal_address ?? '',
    city: profile.city ?? '',
    region: profile.region ?? '',
    website: profile.website ?? '',
    industry: profile.industry ?? '',
  });

  const cancel = () => { setForm({ ...form, ...{
    business_name: profile.business_name ?? '', commercial_name: profile.commercial_name ?? '',
    tax_id: profile.tax_id ?? '', country: profile.country ?? '', currency: profile.currency ?? '',
    timezone: profile.timezone ?? '', fiscal_address: profile.fiscal_address ?? '',
    city: profile.city ?? '', region: profile.region ?? '', website: profile.website ?? '',
    industry: profile.industry ?? '',
  }}); setEditing(false); };

  const save = async () => {
    for (const k of required) if (!(form as any)[k]) { toast.error(`Campo requerido: ${k}`); return; }
    setSaving(true);
    const { data, error } = await supabase.from('provider_profiles').update(form).eq('provider_id', profile.provider_id).select().single();
    setSaving(false);
    if (error) { toast.error('Error al guardar'); return; }
    onUpdated(data as ProviderProfileRow);
    setEditing(false);
    toast.success('Datos de empresa actualizados');
  };

  const handleLogo = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    const path = `${profile.provider_id}/logo-${Date.now()}-${file.name}`;
    const { error: upErr } = await supabase.storage.from('provider-logos').upload(path, file, { upsert: true });
    if (upErr) { setUploading(false); toast.error('Error subiendo logo'); return; }
    const { data: pub } = supabase.storage.from('provider-logos').getPublicUrl(path);
    const { data, error } = await supabase.from('provider_profiles').update({ logo_url: pub.publicUrl }).eq('provider_id', profile.provider_id).select().single();
    setUploading(false);
    if (error) { toast.error('Error guardando logo'); return; }
    onUpdated(data as ProviderProfileRow);
    toast.success('Logo actualizado');
  };

  const profileComplete = required.every(k => (profile as any)[k]);
  const statusBadge = profileComplete ? <Badge variant="default">Perfil completo</Badge> : <Badge variant="secondary">Perfil incompleto</Badge>;

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <h2 className="text-xl font-semibold">Empresa</h2>
          {statusBadge}
        </div>
        {!editing && (
          <Button size="sm" variant="outline" onClick={() => setEditing(true)}>
            <Pencil className="h-4 w-4 mr-2" />Editar
          </Button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-[180px_1fr] gap-6">
        <div className="space-y-2">
          <div className="w-40 h-40 rounded-lg border bg-muted flex items-center justify-center overflow-hidden">
            {profile.logo_url ? (
              <img src={profile.logo_url} alt="Logo" className="w-full h-full object-contain" />
            ) : (
              <Building2 className="h-12 w-12 text-muted-foreground" />
            )}
          </div>
          <input type="file" accept="image/*" ref={fileRef} onChange={handleLogo} className="hidden" />
          <Button size="sm" variant="outline" className="w-40" onClick={() => fileRef.current?.click()} disabled={uploading}>
            <Upload className="h-4 w-4 mr-2" />{uploading ? 'Subiendo…' : 'Cambiar logo'}
          </Button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div><Label>Razón social *</Label><Input value={form.business_name} readOnly={!editing} onChange={e => setForm({...form, business_name: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
          <div><Label>Nombre comercial</Label><Input value={form.commercial_name} readOnly={!editing} onChange={e => setForm({...form, commercial_name: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
          <div><Label>RUC / Código tributario *</Label><Input value={form.tax_id} readOnly={!editing} onChange={e => setForm({...form, tax_id: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
          <div>
            <Label>País *</Label>
            {editing ? (
              <Select value={form.country} onValueChange={v => setForm({...form, country: v})}>
                <SelectTrigger><SelectValue placeholder="Selecciona" /></SelectTrigger>
                <SelectContent>{COUNTRIES.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            ) : <Input value={form.country} readOnly className="bg-muted" />}
          </div>
          <div>
            <Label>Moneda *</Label>
            {editing ? (
              <Select value={form.currency} onValueChange={v => setForm({...form, currency: v})}>
                <SelectTrigger><SelectValue placeholder="Selecciona" /></SelectTrigger>
                <SelectContent>{CURRENCIES.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            ) : <Input value={form.currency} readOnly className="bg-muted" />}
          </div>
          <div>
            <Label>Zona horaria *</Label>
            {editing ? (
              <Select value={form.timezone} onValueChange={v => setForm({...form, timezone: v})}>
                <SelectTrigger><SelectValue placeholder="Selecciona" /></SelectTrigger>
                <SelectContent>{TIMEZONES.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            ) : <Input value={form.timezone} readOnly className="bg-muted" />}
          </div>
          <div className="md:col-span-2"><Label>Dirección fiscal</Label><Input value={form.fiscal_address} readOnly={!editing} onChange={e => setForm({...form, fiscal_address: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
          <div><Label>Ciudad</Label><Input value={form.city} readOnly={!editing} onChange={e => setForm({...form, city: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
          <div><Label>Departamento / Región</Label><Input value={form.region} readOnly={!editing} onChange={e => setForm({...form, region: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
          <div><Label>Página web</Label><Input value={form.website} readOnly={!editing} onChange={e => setForm({...form, website: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
          <div><Label>Rubro / sector</Label><Input value={form.industry} readOnly={!editing} onChange={e => setForm({...form, industry: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
        </div>
      </div>

      {editing && (
        <div className="flex gap-2 mt-6">
          <Button size="sm" onClick={save} disabled={saving}><Save className="h-4 w-4 mr-2" />Guardar cambios</Button>
          <Button size="sm" variant="ghost" onClick={cancel}><X className="h-4 w-4 mr-2" />Cancelar</Button>
        </div>
      )}
    </Card>
  );
};