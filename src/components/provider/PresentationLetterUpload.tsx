import { useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { FileText, Upload, Trash2 } from 'lucide-react';
import type { ProviderProfileRow } from '@/types/provider';

interface Props {
  profile: ProviderProfileRow;
  onUpdated: (p: ProviderProfileRow) => void;
}

export const PresentationLetterUpload = ({ profile, onUpdated }: Props) => {
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);

  const upload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setBusy(true);
    const path = `${profile.provider_id}/letter-${Date.now()}-${file.name}`;
    const { error: upErr } = await supabase.storage.from('provider-documents').upload(path, file);
    if (upErr) { setBusy(false); toast.error('Error subiendo'); return; }
    const { data: signed } = await supabase.storage.from('provider-documents').createSignedUrl(path, 60 * 60 * 24 * 365);
    const { data, error } = await supabase.from('provider_profiles').update({
      presentation_letter_url: signed?.signedUrl ?? path,
      presentation_letter_name: file.name,
    }).eq('provider_id', profile.provider_id).select().single();
    setBusy(false);
    if (error) { toast.error('Error guardando'); return; }
    onUpdated(data as ProviderProfileRow);
    toast.success('Carta de presentación actualizada');
  };

  const remove = async () => {
    if (!confirm('¿Eliminar carta de presentación?')) return;
    const { data, error } = await supabase.from('provider_profiles').update({
      presentation_letter_url: null, presentation_letter_name: null,
    }).eq('provider_id', profile.provider_id).select().single();
    if (error) { toast.error('Error'); return; }
    onUpdated(data as ProviderProfileRow);
    toast.success('Eliminada');
  };

  return (
    <div className="space-y-2">
      <h3 className="font-semibold">Carta de presentación</h3>
      <p className="text-xs text-muted-foreground">
        Solo podrás tener una carta de presentación activa. Si subes otro archivo, el anterior será reemplazado.
      </p>
      <input type="file" accept=".pdf,.doc,.docx" ref={fileRef} onChange={upload} className="hidden" />
      {profile.presentation_letter_name ? (
        <div className="flex items-center justify-between p-3 border rounded-md bg-muted/30">
          <div className="flex items-center gap-2">
            <FileText className="h-4 w-4" />
            <span className="text-sm">{profile.presentation_letter_name}</span>
          </div>
          <div className="flex gap-2">
            <Button size="sm" variant="outline" onClick={() => fileRef.current?.click()} disabled={busy}>
              <Upload className="h-4 w-4 mr-1" />Reemplazar
            </Button>
            <Button size="sm" variant="ghost" onClick={remove}><Trash2 className="h-4 w-4" /></Button>
          </div>
        </div>
      ) : (
        <Button size="sm" variant="outline" onClick={() => fileRef.current?.click()} disabled={busy}>
          <Upload className="h-4 w-4 mr-2" />{busy ? 'Subiendo…' : 'Subir carta'}
        </Button>
      )}
    </div>
  );
};