import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/contexts/AuthContext';
import { GMAIL_ATTEMPT_KEY, gmailConnection } from '@/components/provider/GmailConnectionPanel';

function readAttempt() {
  try {
    const params = new URLSearchParams(window.location.search);
    const raw = sessionStorage.getItem(GMAIL_ATTEMPT_KEY);
    if (!raw || params.has('error')) return null;
    const attempt = JSON.parse(raw) as { organizationId?: string; state?: string };
    const code = params.get('code');
    const state = params.get('state');
    if (!code || !state || state !== attempt.state || !attempt.organizationId) return null;
    return { code,state,organizationId:attempt.organizationId };
  } catch { return null; }
}
export default function GmailCallback() {
  const { loading,isAuthenticated } = useAuth();
  const [attempt] = useState(readAttempt);
  const [busy,setBusy] = useState(false);
  const [message,setMessage] = useState('');
  const [done,setDone] = useState(false);
  useEffect(()=>{ window.history.replaceState(null,'','/gmail/callback'); },[]);
  const finish = async () => {
    if(!attempt || !isAuthenticated || busy) return;
    setBusy(true);
    try {
      const result=await gmailConnection(attempt.organizationId,'complete',{code:attempt.code,state:attempt.state});
      if(result.status!=='connected') throw new Error('Not connected');
      setDone(true); setMessage('Buzón conectado correctamente.');
    } catch { setMessage('No se pudo completar la conexión. Regresa a Oportunidades e inicia nuevamente.'); }
    finally { sessionStorage.removeItem(GMAIL_ATTEMPT_KEY); setBusy(false); setDone(true); }
  };
  return <main className="flex min-h-screen items-center justify-center p-6"><section className="w-full max-w-lg space-y-4 rounded-lg border bg-card p-6">
    <h1 className="text-xl font-semibold">Conectar Gmail a One Facility</h1>
    <p className="text-sm text-muted-foreground">{loading ? 'Verificando sesión…' : !isAuthenticated ? 'La sesión expiró. Inicia sesión y vuelve a conectar.' : !attempt ? 'Solicitud inválida o cancelada. Inicia nuevamente desde Oportunidades.' : message || 'Confirma la conexión de solo lectura con tu sesión de propietario.'}</p>
    {!loading && isAuthenticated && attempt && !done && <Button disabled={busy} onClick={()=>void finish()}>Completar conexión</Button>}
    <Button asChild variant="outline"><Link to="/#opportunities">Volver a Oportunidades</Link></Button>
  </section></main>;
}
