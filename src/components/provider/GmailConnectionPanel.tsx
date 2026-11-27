import { useCallback, useEffect, useState } from 'react';
import { Mail } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export const GMAIL_ATTEMPT_KEY = 'romax-gmail-oauth-attempt-v1';
type Result = { status?: string; mailbox?: string; authorization_url?: string; state?: string; verified?: boolean; error?: string };
export async function gmailConnection(organizationId: string, action: string, extra: Record<string,string> = {}): Promise<Result> {
  const { data, error } = await supabase.functions.invoke('romax-gmail-connection', { body: { ...extra, organization_id:organizationId, action } });
  if (error || !data || data.error) throw new Error('No se pudo completar la operación. Comprueba la configuración o vuelve a conectar.');
  return data as Result;
}
export default function GmailConnectionPanel({ organizationId }: { organizationId: string }) {
  const [status,setStatus] = useState('loading');
  const [mailbox,setMailbox] = useState('');
  const [busy,setBusy] = useState(false);
  const [message,setMessage] = useState('');
  const load = useCallback(async () => {
    try { const result=await gmailConnection(organizationId,'status'); setStatus(result.status ?? 'unavailable'); setMailbox(result.mailbox ?? ''); }
    catch { setStatus('unavailable'); }
  },[organizationId]);
  useEffect(()=>{ void load(); },[load]);
  const perform = async (action:string) => {
    setBusy(true); setMessage('');
    try {
      const result=await gmailConnection(organizationId,action);
      if (action==='start') {
        if (!result.authorization_url || !result.state) throw new Error('Conexión no disponible');
        const url=new URL(result.authorization_url);
        if(url.origin!=='https://accounts.google.com' || url.pathname!=='/o/oauth2/v2/auth') throw new Error('Destino no válido');
        sessionStorage.setItem(GMAIL_ATTEMPT_KEY,JSON.stringify({organizationId,state:result.state}));
        window.location.assign(url.toString());
        return;
      }
      if(action==='verify' && result.verified) setMessage('Acceso de solo lectura verificado.');
      if(action==='disconnect') { sessionStorage.removeItem(GMAIL_ATTEMPT_KEY); setMessage('Buzón desconectado.'); }
    } catch { setMessage('No se pudo completar la operación. Revisa la conexión y vuelve a intentarlo.'); }
    finally { await load(); setBusy(false); }
  };
  const connected=status==='connected';
  return <Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><Mail className="h-5 w-5"/>Bandeja Gmail</CardTitle></CardHeader>
    <CardContent className="space-y-3">
      <p className="text-sm text-muted-foreground">{connected ? mailbox : status==='unavailable' ? 'Conexión no disponible o pendiente de configuración.' : status==='revoking' ? 'Revocación pendiente.' : status==='loading' ? 'Verificando conexión…' : 'Conecta el buzón comercial autorizado.'}</p>
      <div className="flex flex-wrap gap-2">
        {['disconnected','pending'].includes(status) && <Button disabled={busy} onClick={()=>void perform('start')}>Conectar Gmail</Button>}
        {connected && <Button variant="outline" disabled={busy} onClick={()=>void perform('verify')}>Verificar conexión</Button>}
        {['connected','pending','revoking'].includes(status) && <Button variant="outline" disabled={busy} onClick={()=>{if(window.confirm('¿Desconectar Gmail?')) void perform('disconnect');}}>Desconectar</Button>}
        <Button variant="outline" disabled={busy} onClick={()=>void load()}>Actualizar estado</Button>
        <Button disabled>Sincronizar Gmail (próximo incremento)</Button>
      </div>
      {message && <p role="status" className="text-sm">{message}</p>}
      <p className="text-xs text-muted-foreground">Solo lectura. Esta etapa verifica la conexión; todavía no importa mensajes ni adjuntos.</p>
    </CardContent></Card>;
}
