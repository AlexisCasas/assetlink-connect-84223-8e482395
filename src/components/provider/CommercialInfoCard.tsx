import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Pencil, Save, X } from 'lucide-react';
import type { ProviderProfileRow } from '@/types/provider';
import { EMPLOYEE_RANGES } from '@/types/provider';
import { CommercialClientsTable } from './CommercialClientsTable';
import { PresentationLetterUpload } from './PresentationLetterUpload';
import { CertificationBlock } from './CertificationBlock';

interface Props {
  profile: ProviderProfileRow;
  onUpdated: (p: ProviderProfileRow) => void;
  specialties: string[];
}

export const CommercialInfoCard = ({ profile, onUpdated, specialties }: Props) => {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({
    foundation_year: profile.foundation_year ?? '',
    employee_range: profile.employee_range ?? '',
    coverage_area: profile.coverage_area ?? '',
    company_description: profile.company_description ?? '',
  });

  const cancel = () => {
    setForm({
      foundation_year: profile.foundation_year ?? '',
      employee_range: profile.employee_range ?? '',
      coverage_area: profile.coverage_area ?? '',
      company_description: profile.company_description ?? '',
    });
    setEditing(false);
  };

  const save = async () => {
    setSaving(true);
    const { data, error } = await supabase.from('provider_profiles').update({
      foundation_year: form.foundation_year ? Number(form.foundation_year) : null,
      employee_range: form.employee_range || null,
      coverage_area: form.coverage_area || null,
      company_description: form.company_description || null,
    }).eq('provider_id', profile.provider_id).select().single();
    setSaving(false);
    if (error) { toast.error('Error al guardar'); return; }
    onUpdated(data as ProviderProfileRow);
    setEditing(false);
    toast.success('Información comercial actualizada');
  };

  const toggleInvitations = async (v: boolean) => {
    const { data, error } = await supabase.from('provider_profiles')
      .update({ receive_all_invitations: v })
      .eq('provider_id', profile.provider_id).select().single();
    if (error) { toast.error('Error'); return; }
    onUpdated(data as ProviderProfileRow);
  };

  return (
    <Card className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">Información Comercial</h2>
        {!editing && (
          <Button size="sm" variant="outline" onClick={() => setEditing(true)}>
            <Pencil className="h-4 w-4 mr-2" />Editar
          </Button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div><Label>Año de constitución</Label><Input type="number" value={form.foundation_year} readOnly={!editing} onChange={e => setForm({...form, foundation_year: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
        <div>
          <Label>Número de empleados</Label>
          {editing ? (
            <Select value={form.employee_range} onValueChange={v => setForm({...form, employee_range: v})}>
              <SelectTrigger><SelectValue placeholder="Selecciona" /></SelectTrigger>
              <SelectContent>{EMPLOYEE_RANGES.map(r => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
            </Select>
          ) : <Input value={form.employee_range} readOnly className="bg-muted" />}
        </div>
        <div className="md:col-span-2"><Label>Zona de cobertura</Label><Input value={form.coverage_area} readOnly={!editing} onChange={e => setForm({...form, coverage_area: e.target.value})} className={editing ? '' : 'bg-muted'} /></div>
        <div className="md:col-span-2">
          <Label>Especialidades</Label>
          <div className="flex flex-wrap gap-2 mt-1 p-2 border rounded-md bg-muted min-h-10">
            {specialties.length ? specialties.map(s => <span key={s} className="px-2 py-1 bg-background border rounded text-xs">{s}</span>) : <span className="text-xs text-muted-foreground">Sin especialidades</span>}
          </div>
        </div>
        <div className="md:col-span-2"><Label>Descripción comercial</Label><Textarea value={form.company_description} readOnly={!editing} onChange={e => setForm({...form, company_description: e.target.value})} className={editing ? '' : 'bg-muted'} rows={3} /></div>
      </div>

      {editing && (
        <div className="flex gap-2">
          <Button size="sm" onClick={save} disabled={saving}><Save className="h-4 w-4 mr-2" />Guardar</Button>
          <Button size="sm" variant="ghost" onClick={cancel}><X className="h-4 w-4 mr-2" />Cancelar</Button>
        </div>
      )}

      <CommercialClientsTable providerId={profile.provider_id} />

      <PresentationLetterUpload profile={profile} onUpdated={onUpdated} />

      <div className="flex items-center justify-between p-3 border rounded-md">
        <div>
          <p className="font-medium text-sm">Recibir invitaciones</p>
          <p className="text-xs text-muted-foreground">Deseo recibir correos de invitación a licitaciones de todos los compradores.</p>
        </div>
        <Switch checked={profile.receive_all_invitations} onCheckedChange={toggleInvitations} />
      </div>

      <CertificationBlock profile={profile} onUpdated={onUpdated} />
    </Card>
  );
};