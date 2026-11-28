import {useEffect,useRef,useState} from 'react';
import {Button} from '@/components/ui/button';
import {Badge} from '@/components/ui/badge';
import {gmailConnection,downloadUnscannedDocument} from './GmailConnectionPanel';
import {dateLabel,type Attachment,type Opportunity} from './romaxRequestList';
import {canRetain,canDownloadUnscanned,documentStatus,documentFilename,selectionWithinLimit} from './romaxDocuments';
type Props={organizationId:string;opportunity:Opportunity;attachments:Attachment[];gmailAllowed:boolean;onChanged:()=>Promise<void>};
export default function RequestDocuments({organizationId,opportunity,attachments,gmailAllowed,onChanged}:Props){
 const [selected,setSelected]=useState<string[]>([]),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[ack,setAck]=useState<string|null>(null);
 const alive=useRef(true),guard=useRef(false);
 useEffect(()=>{alive.current=true;return()=>{alive.current=false;};},[]);
 const owner=gmailAllowed&&opportunity.source_system==='gmail';
 const rows=attachments.filter(a=>a.opportunity_id===opportunity.id);
 const chosen=rows.filter(a=>selected.includes(a.id)&&canRetain(a));
 const run=async(action:'detect'|'retain'|'download',doc?:Attachment)=>{
   if(!owner||guard.current)return;
   if(action==='retain'&&!selectionWithinLimit(chosen))return;
   if(action==='download'&&(!doc||ack!==doc.id||!canDownloadUnscanned(doc)))return;
   guard.current=true;setBusy(true);setMessage('');
   try{
     if(action==='detect'){
       const r=await gmailConnection(organizationId,'discover_attachments',{opportunity_id:opportunity.id,confirmed:true});
       if(!r.discovery)throw new Error('missing');
       if(alive.current)setMessage('Detectados: '+r.discovery.detected+'. Nuevos: '+r.discovery.registered+'. Existentes: '+r.discovery.unchanged+(r.discovery.partial?'. Resultado parcial por límites de exploración.':'.'));
     }else if(action==='retain'){
       const r=await gmailConnection(organizationId,'quarantine_attachments',{opportunity_id:opportunity.id,attachment_ids:chosen.map(a=>a.id),confirmed:true});
       if(!r.quarantine)throw new Error('missing');
       if(alive.current){setSelected([]);setMessage('Conservados: '+r.quarantine.results.filter(a=>a.status==='quarantined').length+'. Existentes: '+r.quarantine.skipped+'. Fallidos o inciertos: '+r.quarantine.results.filter(a=>a.status!=='quarantined').length+'.');}
     }else if(doc){
       const blob=await downloadUnscannedDocument(organizationId,opportunity.id,doc.id);
       if(alive.current){const url=URL.createObjectURL(new Blob([blob],{type:'application/octet-stream'}));const link=document.createElement('a');link.href=url;link.download=documentFilename(doc);link.rel='noopener';document.body.appendChild(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);setMessage('Descarga solicitada. El archivo no ha sido escaneado.');setAck(null);}
     }
     await onChanged();
   }catch{if(alive.current)setMessage('No se pudo completar la operación. Comprueba la conexión, permisos o configuración y actualiza antes de reintentar.');}
   finally{guard.current=false;if(alive.current)setBusy(false);}
 };
 return <section className="space-y-3">
   <div className="flex flex-wrap items-center justify-between gap-2"><h3 className="font-medium">Documentos registrados ({rows.length})</h3>{owner&&<Button variant="outline" size="sm" disabled={busy} onClick={()=>void run('detect')}>Detectar adjuntos</Button>}</div>
   {owner&&<><div role="note" className="rounded border border-amber-500/50 bg-amber-500/10 p-3 text-sm">Piloto: los documentos conservados no tienen escaneo antimalware. Descárgalos solo si reconoces su origen; no se abren dentro del sistema.</div><div className="flex flex-wrap items-center gap-2"><Button disabled={busy||!selectionWithinLimit(chosen)} onClick={()=>void run('retain')}>Guardar seleccionados ({chosen.length})</Button><span className="text-xs text-muted-foreground">Máximo 5 archivos / 25 MiB por lote.</span></div></>}
   {!rows.length&&<p className="text-sm">No hay documentos registrados. Detectar adjuntos no descarga archivos.</p>}
   {rows.map(a=><div key={a.id} className="space-y-2 rounded border p-3 text-sm">
     <div className="flex items-start gap-2">{owner&&canRetain(a)&&<input aria-label={'Seleccionar '+a.filename} type="checkbox" checked={selected.includes(a.id)} disabled={busy} onChange={e=>setSelected(old=>e.target.checked?[...old,a.id]:old.filter(x=>x!==a.id))}/>}<div className="min-w-0 flex-1"><p className="break-words font-medium">{a.filename}</p><p className="text-xs text-muted-foreground">{a.mime_type||'Tipo no informado'} · {a.size_bytes==null?'Tamaño desconocido':(a.size_bytes/1048576).toFixed(2)+' MiB'} · {a.source_direction==='incoming'?'Recibido':a.source_direction==='outgoing'?'Enviado por ROMAX':'Origen no determinado'}{a.source_received_at?' · '+dateLabel(a.source_received_at):''}</p></div><Badge variant="outline">{documentStatus(a)}</Badge></div>
     {owner&&canDownloadUnscanned(a)&&<>{ack===a.id?<div className="space-y-2 rounded bg-muted p-2"><p>Confirmo que deseo descargar este archivo sin escaneo. Puede contener contenido peligroso.</p><div className="flex flex-wrap gap-2"><Button size="sm" disabled={busy} onClick={()=>void run('download',a)}>Aceptar riesgo y descargar</Button><Button size="sm" variant="outline" disabled={busy} onClick={()=>setAck(null)}>Cancelar</Button></div></div>:<Button size="sm" variant="outline" disabled={busy} onClick={()=>setAck(a.id)}>Descargar sin escaneo</Button>}</>}
     {a.availability_status==='quarantined'&&!canDownloadUnscanned(a)&&<p className="text-xs text-muted-foreground">En cuarentena. Formato pendiente de validación estructural.</p>}
   </div>)}
   <p role="status" className="text-sm">{busy?'Procesando documentos…':message}</p>
 </section>;
}
