import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Upload, X, CheckCircle, Clock } from 'lucide-react';
import type { ProviderProfileRow, CertificationStatus } from '@/types/provider';

interface Props {
  profile: ProviderProfileRow;
  onUpdated: (p: ProviderProfileRow) => void;
}

const statusBadge = (s: CertificationStatus) => {
  if (s === 'certified') return <Badge className="bg-green-600 hover:bg-green-600"><CheckCircle className="h-3 w-3 mr-1" />Certificado</Badge>;
  if (s === 'in_review') return <Badge variant="secondary"><Clock className="h-3 w-3 mr-1" />En revisión</Badge>;
  if (s === 'rejected') return <Badge variant="destructive">Rechazado</Badge>;
  return <Badge variant="outline">No certificado</Badge>;
};

export const CertificationBlock = ({ profile, onUpdated }: Props) => {
  const [docs, setDocs] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);

  const onFiles = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files) return;
    const incoming = Array.from(e.target.files);
    if (docs.length + incoming.length > 5) { toast.error('Máximo 5 documentos'); return; }
    setDocs([...docs, ...incoming]);
  };

  const submit = async () => {
    if (docs.length !== 5) { toast.error('Debes subir 5 documentos'); return; }
    setBusy(true);
    for (const f of docs) {
      const path = `${profile.provider_id}/cert-${Date.now()}-${f.name}`;
      await supabase.storage.from('provider-documents').upload(path, f);
      await supabase.from('provider_documents').insert({
        provider_id: profile.provider_id,
        document_type: 'certification_document',
        file_name: f.name,
        file_url: path,
        status: 'in_review',
      });
    }
    const { data, error } = await supabase.from('provider_profiles')
      .update({ certification_status: 'in_review' })
      .eq('provider_id', profile.provider_id).select().single();
    setBusy(false);
    if (error) { toast.error('Error'); return; }
    onUpdated(data as ProviderProfileRow);
    setDocs([]);
    toast.success('Solicitud enviada. Quedará en revisión.');
  };

  return (
    <div className="space-y-3 pt-2 border-t">
      <div className="flex items-center justify-between">
        <h3 className="font-semibold">Certificación de proveedor</h3>
        {statusBadge(profile.certification_status)}
      </div>
      <p className="text-sm text-muted-foreground">
        Sube 5 documentos que acrediten tu empresa para iniciar la certificación.
      </p>

      {profile.certification_status === 'not_started' || profile.certification_status === 'rejected' ? (
        <>
          <div>
            <Label>Documentos ({docs.length}/5)</Label>
            <Input type="file" multiple accept=".pdf,.doc,.docx,.jpg,.jpeg,.png" onChange={onFiles} disabled={docs.length >= 5} />
          </div>
          {docs.length > 0 && (
            <div className="space-y-1">
              {docs.map((f, i) => (
                <div key={i} className="flex items-center justify-between p-2 bg-muted rounded text-sm">
                  <span>{f.name}</span>
                  <Button size="sm" variant="ghost" onClick={() => setDocs(docs.filter((_, j) => j !== i))}><X className="h-4 w-4" /></Button>
                </div>
              ))}
            </div>
          )}
          <Button onClick={submit} disabled={docs.length !== 5 || busy}>
            <Upload className="h-4 w-4 mr-2" />{busy ? 'Enviando…' : 'Enviar Solicitud de Certificación'}
          </Button>
        </>
      ) : profile.certification_status === 'in_review' ? (
        <div className="p-3 bg-muted rounded text-sm">Tu solicitud está siendo revisada.</div>
      ) : (
        <div className="p-3 bg-muted rounded text-sm">¡Eres un proveedor certificado!</div>
      )}
    </div>
  );
};