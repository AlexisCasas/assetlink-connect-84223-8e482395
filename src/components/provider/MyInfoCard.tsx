import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Pencil, Save, X, Mail, KeyRound } from 'lucide-react';
import type { ProviderProfileRow } from '@/types/provider';
import { ChangePasswordDialog } from './ChangePasswordDialog';

interface Props {
  profile: ProviderProfileRow;
  onUpdated: (p: ProviderProfileRow) => void;
}

export const MyInfoCard = ({ profile, onUpdated }: Props) => {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [pwOpen, setPwOpen] = useState(false);
  const [form, setForm] = useState({
    contact_name: profile.contact_name ?? '',
    contact_email: profile.contact_email ?? '',
    phone: profile.phone ?? '',
    whatsapp_phone: profile.whatsapp_phone ?? '',
    position: profile.position ?? '',
  });

  const cancel = () => {
    setForm({
      contact_name: profile.contact_name ?? '',
      contact_email: profile.contact_email ?? '',
      phone: profile.phone ?? '',
      whatsapp_phone: profile.whatsapp_phone ?? '',
      position: profile.position ?? '',
    });
    setEditing(false);
  };

  const save = async () => {
    setSaving(true);
    const { data, error } = await supabase
      .from('provider_profiles')
      .update(form)
      .eq('provider_id', profile.provider_id)
      .select()
      .single();
    setSaving(false);
    if (error) { toast.error('Error al guardar'); return; }
    onUpdated(data as ProviderProfileRow);
    setEditing(false);
    toast.success('Información actualizada');
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-semibold">Mi información</h2>
        {!editing && (
          <Button size="sm" variant="outline" onClick={() => setEditing(true)}>
            <Pencil className="h-4 w-4 mr-2" />Editar datos
          </Button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div>
          <Label>Correo electrónico</Label>
          <Input value={form.contact_email} readOnly className="bg-muted" />
        </div>
        <div>
          <Label>Nombre de contacto</Label>
          <Input value={form.contact_name} readOnly={!editing} onChange={e => setForm({...form, contact_name: e.target.value})} className={editing ? '' : 'bg-muted'} />
        </div>
        <div>
          <Label>Teléfono</Label>
          <Input value={form.phone} readOnly={!editing} onChange={e => setForm({...form, phone: e.target.value})} className={editing ? '' : 'bg-muted'} />
        </div>
        <div>
          <Label>Teléfono WhatsApp</Label>
          <Input value={form.whatsapp_phone} readOnly={!editing} onChange={e => setForm({...form, whatsapp_phone: e.target.value})} className={editing ? '' : 'bg-muted'} />
        </div>
        <div>
          <Label>Cargo / puesto</Label>
          <Input value={form.position} readOnly={!editing} onChange={e => setForm({...form, position: e.target.value})} className={editing ? '' : 'bg-muted'} />
        </div>
      </div>

      <div className="flex flex-wrap gap-2 mt-6">
        <Button variant="outline" size="sm" onClick={() => toast.info('Cambio de correo no disponible en mockup')}>
          <Mail className="h-4 w-4 mr-2" />Cambiar correo
        </Button>
        <Button variant="outline" size="sm" onClick={() => setPwOpen(true)}>
          <KeyRound className="h-4 w-4 mr-2" />Cambiar contraseña
        </Button>
        {editing && (
          <>
            <Button size="sm" onClick={save} disabled={saving}>
              <Save className="h-4 w-4 mr-2" />Guardar cambios
            </Button>
            <Button size="sm" variant="ghost" onClick={cancel}>
              <X className="h-4 w-4 mr-2" />Cancelar
            </Button>
          </>
        )}
      </div>

      <ChangePasswordDialog open={pwOpen} onOpenChange={setPwOpen} />
    </Card>
  );
};