import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Plus, Trash2, Save, Pencil, X } from 'lucide-react';
import type { ProviderCommercialClient } from '@/types/provider';

interface Props { providerId: string; }

const empty = (provider_id: string): ProviderCommercialClient => ({
  id: 'new', provider_id, business_name: '', contact_person: '', email: '', phone: '', extension: '',
});

export const CommercialClientsTable = ({ providerId }: Props) => {
  const [rows, setRows] = useState<ProviderCommercialClient[]>([]);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draft, setDraft] = useState<ProviderCommercialClient | null>(null);

  const load = async () => {
    const { data } = await supabase.from('provider_commercial_clients').select('*').eq('provider_id', providerId).order('created_at');
    setRows((data ?? []) as ProviderCommercialClient[]);
  };

  useEffect(() => { if (providerId) load(); }, [providerId]);

  const startNew = () => { setDraft(empty(providerId)); setEditingId('new'); };
  const startEdit = (r: ProviderCommercialClient) => { setDraft({ ...r }); setEditingId(r.id); };
  const cancel = () => { setDraft(null); setEditingId(null); };

  const save = async () => {
    if (!draft) return;
    if (!draft.business_name.trim()) { toast.error('Razón social requerida'); return; }
    if (draft.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(draft.email)) { toast.error('Correo inválido'); return; }
    if (draft.id === 'new') {
      const { error } = await supabase.from('provider_commercial_clients').insert({
        provider_id: providerId,
        business_name: draft.business_name,
        contact_person: draft.contact_person,
        email: draft.email,
        phone: draft.phone,
        extension: draft.extension,
      });
      if (error) { toast.error('Error al crear'); return; }
    } else {
      const { error } = await supabase.from('provider_commercial_clients').update({
        business_name: draft.business_name,
        contact_person: draft.contact_person,
        email: draft.email,
        phone: draft.phone,
        extension: draft.extension,
      }).eq('id', draft.id);
      if (error) { toast.error('Error al guardar'); return; }
    }
    toast.success('Cliente guardado');
    cancel(); load();
  };

  const remove = async (id: string) => {
    if (!confirm('¿Eliminar este cliente?')) return;
    const { error } = await supabase.from('provider_commercial_clients').delete().eq('id', id);
    if (error) { toast.error('Error'); return; }
    toast.success('Cliente eliminado'); load();
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="font-semibold">Principales clientes</h3>
        <Button size="sm" variant="outline" onClick={startNew} disabled={!!editingId}>
          <Plus className="h-4 w-4 mr-2" />Agregar cliente
        </Button>
      </div>
      <div className="border rounded-md overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Razón social</TableHead>
              <TableHead>Persona contacto</TableHead>
              <TableHead>Correo</TableHead>
              <TableHead>Teléfono</TableHead>
              <TableHead>Anexo</TableHead>
              <TableHead className="w-32">Acciones</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {editingId === 'new' && draft && (
              <EditRow draft={draft} setDraft={setDraft} save={save} cancel={cancel} />
            )}
            {rows.map(r => editingId === r.id && draft ? (
              <EditRow key={r.id} draft={draft} setDraft={setDraft} save={save} cancel={cancel} />
            ) : (
              <TableRow key={r.id}>
                <TableCell>{r.business_name}</TableCell>
                <TableCell>{r.contact_person}</TableCell>
                <TableCell>{r.email}</TableCell>
                <TableCell>{r.phone}</TableCell>
                <TableCell>{r.extension}</TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button size="sm" variant="ghost" onClick={() => startEdit(r)}><Pencil className="h-4 w-4" /></Button>
                    <Button size="sm" variant="ghost" onClick={() => remove(r.id)}><Trash2 className="h-4 w-4" /></Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
            {rows.length === 0 && editingId !== 'new' && (
              <TableRow><TableCell colSpan={6} className="text-center text-muted-foreground py-6">Sin clientes registrados</TableCell></TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
};

const EditRow = ({ draft, setDraft, save, cancel }: {
  draft: ProviderCommercialClient;
  setDraft: (d: ProviderCommercialClient) => void;
  save: () => void;
  cancel: () => void;
}) => (
  <TableRow className="bg-muted/30">
    <TableCell><Input value={draft.business_name} onChange={e => setDraft({...draft, business_name: e.target.value})} /></TableCell>
    <TableCell><Input value={draft.contact_person ?? ''} onChange={e => setDraft({...draft, contact_person: e.target.value})} /></TableCell>
    <TableCell><Input value={draft.email ?? ''} onChange={e => setDraft({...draft, email: e.target.value})} /></TableCell>
    <TableCell><Input value={draft.phone ?? ''} onChange={e => setDraft({...draft, phone: e.target.value})} /></TableCell>
    <TableCell><Input value={draft.extension ?? ''} onChange={e => setDraft({...draft, extension: e.target.value})} /></TableCell>
    <TableCell>
      <div className="flex gap-1">
        <Button size="sm" variant="default" onClick={save}><Save className="h-4 w-4" /></Button>
        <Button size="sm" variant="ghost" onClick={cancel}><X className="h-4 w-4" /></Button>
      </div>
    </TableCell>
  </TableRow>
);