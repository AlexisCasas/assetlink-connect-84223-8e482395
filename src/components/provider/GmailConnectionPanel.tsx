import { useCallback, useEffect, useState } from 'react';
import { Mail } from 'lucide-react';
import { canConfirmGmailImport } from './gmailImportPolicy';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export const GMAIL_ATTEMPT_KEY = 'romax-gmail-oauth-attempt-v1';
const GMAIL_FUNCTION_NAME = import.meta.env.VITE_ROMAX_GMAIL_FUNCTION_NAME || 'romax-gmail-connection';
const GMAIL_QA_MODE = GMAIL_FUNCTION_NAME === 'romax-gmail-connection-qa';
type DeadlineEvent = { raw:string; date:string|null; time:string|null; datetime:string|null; timezone:'America/Lima'; status:'confirmed'|'ambiguous'; kind:'extension'|'stated'; weekday:string|null };
type Candidate = { thread_id:string; subject:string; sender:string; received_at:string; snippet:string; category:string; reason:string; reference:string|null; deadline_hint:string|null; deadline_events?:DeadlineEvent[]; message_count:number; attachments:{name:string;mime:string;supported:boolean}[]; existing_status?:string|null; existing_opportunity_id?:string|null; confirmation_token?:string|null; text_source?:'body'|'snippet'; body_limited?:boolean; import_policy?:'new_candidate'|'link_existing'|'review_required'|'not_importable' };
type Preview = { window_start:string; window_end:string; candidates:Candidate[]; scanned:number; estimate:number|null; next_cursor:string|null };
const labels:Record<string,string>={quote_request:'Nueva solicitud candidata',follow_up:'Actualización / seguimiento',adjustment:'Reajuste',quoted:'Posiblemente cotizada',operational:'Operativa',other:'Otros',review:'Requiere revisión'};
type Result = { status?: string; mailbox?: string; authorization_url?: string; state?: string; verified?: boolean; error?: string; outcome?: 'imported'|'already_exists'; opportunity_id?:string; opportunity_status?:string } & Partial<Preview>;
export async function gmailConnection(organizationId: string, action: string, extra: Record<string,string|boolean> = {}): Promise<Result> {
  const { data, error } = await supabase.functions.invoke(GMAIL_FUNCTION_NAME, { body: { ...extra, organization_id:organizationId, action } });
  if (error || !data || data.error) throw new Error('No se pudo completar la operación. Comprueba la configuración o vuelve a conectar.');
  return data as Result;
}
export default function GmailConnectionPanel({ organizationId,onImported,onOpenOpportunity }: { organizationId: string; onImported:()=>Promise<void>; onOpenOpportunity:(id:string)=>void }) {
  const [status,setStatus] = useState('loading');
  const [mailbox,setMailbox] = useState('');
  const [busy,setBusy] = useState(false);
  const [message,setMessage] = useState('');
  const [preview,setPreview] = useState<Preview|null>(null);
  const [filter,setFilter] = useState('all');
  const [search,setSearch] = useState('');
  const [confirming,setConfirming]=useState<string|null>(null);
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
  useEffect(()=>{if(!connected){setPreview(null);setConfirming(null);}},[connected]);
  const sync=async(more=false)=>{
    setBusy(true);setMessage('');
    setConfirming(null);
    if(!more)setPreview(null);
    try {
      const cursor=more?preview?.next_cursor:null;
      if(more&&!cursor)return;
      const result=await gmailConnection(organizationId,'preview',cursor?{cursor}:{});
      if(!Array.isArray(result.candidates)||!result.window_start||!result.window_end||typeof result.scanned!=='number')throw new Error('Invalid preview');
      const page=result as Preview;
      setPreview(old=>more&&old?{...page,scanned:old.scanned+page.scanned,candidates:[...new Map([...old.candidates,...page.candidates].map(c=>[c.thread_id,c])).values()]}:page);
    }catch{setMessage('No se pudo completar la lectura. Reintenta; no se ha importado nada.');}
    finally{setBusy(false);}
  };
  const confirmImport=async(c:Candidate)=>{
    if(busy||confirming!==c.thread_id||!canConfirmGmailImport(c)||!c.confirmation_token)return;
    setBusy(true);setMessage('');setConfirming(null);
    try{
      const result=await gmailConnection(organizationId,'confirm_import',{confirmed:true,confirmation_token:c.confirmation_token});
      if(!result.opportunity_id||!['imported','already_exists'].includes(result.outcome??''))throw new Error('Invalid result');
      setPreview(old=>old?{...old,candidates:old.candidates.map(item=>item.thread_id===c.thread_id?{...item,confirmation_token:null,existing_status:result.status??'new',existing_opportunity_id:result.opportunity_id,import_policy:'link_existing'}:item)}:old);
      setMessage(result.outcome==='imported'?'Oportunidad registrada. Revisa su vinculación comercial.':'La conversación ya tiene una oportunidad. No se creó un duplicado.');
      await onImported();
    }catch{setMessage('No se pudo confirmar el resultado. Sincroniza nuevamente para verificar si ya existe la oportunidad.');setPreview(null);}
    finally{setBusy(false);}
  };
  const visible=(preview?.candidates??[]).filter(c=>(filter==='all'||c.category===filter)&&[c.subject,c.sender,c.reference,c.snippet].join(' ').toLowerCase().includes(search.toLowerCase()));
  const date=(s:string)=>new Date(s).toLocaleString('es-PE',{timeZone:'America/Lima'});
  return <Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><Mail className="h-5 w-5"/>Bandeja Gmail</CardTitle></CardHeader>
    <CardContent className="space-y-3">
      <p className="text-sm text-muted-foreground">{connected ? mailbox : status==='unavailable' ? 'Conexión no disponible o pendiente de configuración.' : status==='revoking' ? 'Revocación pendiente.' : status==='loading' ? 'Verificando conexión…' : 'Conecta el buzón comercial autorizado.'}</p>
      <div className="flex flex-wrap gap-2">
        {!GMAIL_QA_MODE && ['disconnected','pending'].includes(status) && <Button disabled={busy} onClick={()=>void perform('start')}>Conectar Gmail</Button>}
        {!GMAIL_QA_MODE && connected && <Button variant="outline" disabled={busy} onClick={()=>void perform('verify')}>Verificar conexión</Button>}
        {!GMAIL_QA_MODE && ['connected','pending','revoking'].includes(status) && <Button variant="outline" disabled={busy} onClick={()=>{if(window.confirm('¿Desconectar Gmail?')) void perform('disconnect');}}>Desconectar</Button>}
        <Button variant="outline" disabled={busy} onClick={()=>void load()}>Actualizar estado</Button>
        <Button disabled={busy||!connected} onClick={()=>void sync()}>{busy?'Procesando…':'Sincronizar Gmail'}</Button>
      </div>
      {GMAIL_QA_MODE && <p className="text-xs text-muted-foreground">Entorno QA: conexión y desconexión deshabilitadas. La importación solo se habilita por autorización de servidor.</p>}
      {message && <p role="status" className="text-sm">{message}</p>}
      <p className="text-xs text-muted-foreground">Lectura de los últimos siete días. Solo se crea una oportunidad si el propietario confirma un candidato habilitado por el servidor. No se descargan adjuntos.</p>
      {connected&&preview&&<section className="space-y-3 border-t pt-4">
        <h3 className="font-semibold">Vista previa de solicitudes</h3>
        <p className="text-xs text-muted-foreground">{date(preview.window_start)} — {date(preview.window_end)} (Lima). {preview.scanned} conversaciones consultadas · {preview.candidates.length} con mensajes recibidos. {preview.next_cursor?'Hay más páginas por revisar.':'Fin de los resultados devueltos.'}</p>
        <div className="flex flex-wrap gap-2">
          <input className="min-w-0 flex-1 rounded-md border bg-background p-2 text-sm" aria-label="Buscar en Gmail" placeholder="Buscar asunto, remitente o referencia" value={search} onChange={e=>setSearch(e.target.value)}/>
          <select className="rounded-md border bg-background p-2 text-sm" aria-label="Clasificación Gmail" value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">Todas ({preview.candidates.length})</option>{Object.entries(labels).map(([k,v])=><option key={k} value={k}>{v} ({preview.candidates.filter(c=>c.category===k).length})</option>)}</select>
        </div>
        {visible.length===0&&<p className="text-sm text-muted-foreground">No hay resultados con estos filtros.</p>}
        {visible.map(c=><article key={c.thread_id} className="space-y-2 rounded-lg border p-3 text-sm break-words">
          <div className="flex flex-wrap items-center justify-between gap-2"><p className="font-medium">{c.subject}</p><span className="rounded-full bg-muted px-2 py-1 text-xs">{labels[c.category]??c.category}</span></div>
          <p className="text-xs text-muted-foreground">{c.sender||'Remitente no informado'} · {date(c.received_at)} · {c.message_count} mensajes en ventana</p>
          <p>{c.reason}</p>
          {c.existing_status&&<p className="font-medium">Ya existe una oportunidad Gmail ({c.existing_status}). No duplicar.</p>}
          {c.import_policy==='review_required'&&<p className="font-medium">Revisión requerida antes de importar; no crear una oportunidad independiente.</p>}
          {c.import_policy==='link_existing'&&<div className="flex flex-wrap items-center gap-2"><p className="font-medium">Oportunidad existente; no duplicar.</p>{c.existing_opportunity_id&&<Button size="sm" variant="outline" disabled={busy} onClick={()=>onOpenOpportunity(c.existing_opportunity_id!)}>Ver solicitud registrada</Button>}</div>}
          {c.body_limited&&<p className="text-xs">Texto incompleto o limitado. Verificar en Gmail.</p>}
          {c.reference&&<p>Referencia: {c.reference}</p>}
          {c.deadline_events?.length ? <div className="space-y-1"><p className="font-medium">Historial de plazos:</p>{c.deadline_events.map((event,i)=><p key={i} className="text-xs">{event.kind==='extension'?'Actualización de plazo':'Plazo indicado'}: {event.raw} {event.status==='ambiguous'?'· Fecha por confirmar':`· ${event.date??''}${event.time?` ${event.time}`:''} (${event.timezone})`}</p>)}</div> : c.deadline_hint&&<p>Plazo mencionado (sin confirmar): {c.deadline_hint}</p>}
          {c.snippet&&<p className="rounded-md bg-muted/50 p-2">{c.snippet}</p>}
          {c.attachments.length>0&&<details><summary className="cursor-pointer">{c.attachments.length} adjuntos identificados</summary><ul className="mt-1 list-disc pl-5">{c.attachments.map((x,i)=><li key={i}>{x.name} · {x.supported?'Tipo previsto':'Otro tipo'}</li>)}</ul></details>}
          {canConfirmGmailImport(c)&&(confirming===c.thread_id?<div className="space-y-2 rounded-md border p-3" role="group" aria-label="Confirmar importación"><p className="font-medium">¿Crear esta oportunidad en ROMAX?</p><p>Se guardarán el asunto, remitente, fecha y extracto. Quedará sin cliente, sede ni contacto vinculados. No se importarán archivos.</p><div className="flex flex-wrap gap-2"><Button disabled={busy} onClick={()=>void confirmImport(c)}>Confirmar y crear oportunidad</Button><Button variant="outline" disabled={busy} onClick={()=>setConfirming(null)}>Cancelar</Button></div></div>:<Button variant="outline" disabled={busy} onClick={()=>setConfirming(c.thread_id)}>Revisar e importar</Button>)}
        </article>)}
        {preview.next_cursor&&<Button variant="outline" disabled={busy} onClick={()=>void sync(true)}>Cargar más conversaciones</Button>}
        <p className="text-xs text-muted-foreground">Resultados temporales en pantalla. Si la importación no está habilitada, solo se permite revisar; las confirmaciones caducan tras cinco minutos. Clasificación basada en el texto disponible y los extractos; no garantiza que una solicitud esté pendiente. El cuerpo completo no se guarda.</p>
      </section>}
    </CardContent></Card>;
}
