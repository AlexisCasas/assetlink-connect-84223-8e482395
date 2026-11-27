export const DAY_MS = 86400000;
export const PAGE_SIZE = 12;
export type Category = 'quote_request' | 'follow_up' | 'adjustment' | 'quoted' | 'operational' | 'other' | 'review';
export type DeadlineEvent = { raw:string; date:string|null; time:string|null; datetime:string|null; timezone:'America/Lima'; status:'confirmed'|'ambiguous'; kind:'extension'|'stated'; weekday:string|null };
type Part = { filename?: string; mimeType?: string; parts?: Part[] };
type Message = { id?: string; internalDate?: string; labelIds?: string[]; snippet?: string; payload?: Part & { headers?: {name:string;value:string}[] } };
export type Candidate = { thread_id:string; message_id:string; subject:string; sender:string; received_at:string; snippet:string; category:Category; reason:string; reference:string|null; deadline_hint:string|null; deadline_events:DeadlineEvent[]; message_count:number; attachments:{name:string;mime:string;supported:boolean}[]; existing_status?:string|null };
const clean = (s:unknown,max:number) => typeof s==='string' ? s.replace(/[\u0000-\u001f\u007f]/g,' ').slice(0,max).trim() : '';
const norm = (s:string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const header = (m:Message,name:string) => clean(m.payload?.headers?.find(h=>h.name.toLowerCase()===name.toLowerCase())?.value,500);
const validId=(id:unknown):id is string=>typeof id==='string' && /^[a-zA-Z0-9_-]{1,128}$/.test(id);
const emailFrom=(m:Message) => {
  const value=header(m,'From');
  const bracket=value.match(/<([^<>\s]+@[^<>\s]+)>/)?.[1];
  return (bracket??value.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)?.[0]??'').toLowerCase();
};
const isInternal=(m:Message)=>emailFrom(m).endsWith('@romaxfm.com');
const isSent=(m:Message)=>m.labelIds?.includes('SENT')===true||isInternal(m);
const isExcluded=(m:Message)=>m.labelIds?.some(l=>['SPAM','TRASH','DRAFT'].includes(l))===true;
function forwardedSender(m:Message):string|null {
  const text=clean(m.snippet,1200);
  const matches=[...text.matchAll(/(?:De|From):\s*[^<]{0,180}<([^>\s]+@[^>\s]+)>/gi)];
  for(const match of matches){const email=match[1].toLowerCase();if(!email.endsWith('@romaxfm.com'))return email;}
  return null;
}
function attachments(m:Message) {
  const out:Candidate['attachments']=[];
  function walk(p:Part|undefined,depth:number) {
    if(!p||depth>8||out.length>=50)return;
    const name=clean(p.filename,250),mime=clean(p.mimeType,120);
    if(name)out.push({name,mime,supported:/\.(pdf|xlsx?|docx?)$/i.test(name)});
    for(const child of (p.parts??[]).slice(0,100))walk(child,depth+1);
  }
  walk(m.payload,0); return out;
}
const quote=/\b(cotizacion|cotizar|presupuesto|licitacion|propuesta(?: economica)?|rfq|solicitud de oferta)\b/;
const adjust=/\b(reajuste|reajustar|mejora de precio|mejorar el precio|descuento|actualizar (?:la )?(?:cotizacion|propuesta))\b/;
const follow=/\b(recordatorio|seguimiento|prorroga|ampliacion (?:de |del )?plazo|se (?:extiende|amplia|prorroga) (?:el )?plazo|extiende plazo|amplia plazo|nuevo plazo|nueva fecha|fecha limite|reprogramacion)\b/;
const support=/\b(suplayer|suplayers|notificaciones? de invitaciones|incidencia de correo|soporte de plataforma)\b/;
const operation=/\b(orden de compra|orden de servicio|acta de conformidad|factura|coordinacion de visita|inicio de trabajos|ejecucion de trabajos|documentos? sst|ingreso a tienda)\b/;
const requestQuote=/\b(solicit(?:a|amos|ud|ar|an)|requerimiento|invitacion|favor|agradeceremos|necesitamos|convocatoria|cotizar)\b/;
const sentQuote=/\b(adjuntamos|adjunto|enviamos|remitimos|compartimos|se adjunta|se envia)\b.{0,120}\b(cotizacion|propuesta|presupuesto)\b|\b(cotizacion|propuesta|presupuesto)\b.{0,120}\b(adjunta|enviada|remitida)\b/;
const references=(s:string)=>Array.from(new Set((s.toUpperCase().match(/\bSC[-\s]?\d{4,}(?:-\d{4})?\b/g)??[]).map(x=>x.replace(/\s+/g,'-'))));
const rmxReference=(s:string)=>s.toUpperCase().match(/\bRMX[-\s]?\d{4}[-\s]?\d{3,}\b/)?.[0].replace(/\s+/g,'-')??null;
const weekdayIndex:Record<string,number>={domingo:0,lunes:1,martes:2,miercoles:3,jueves:4,viernes:5,sabado:6};
const datePattern=/\b(?:(lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo)\s+)?(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?\b/gi;
const isoDatePattern=/\b(\d{4})-(\d{2})-(\d{2})\b/g;
const deadlineCue=/(?:plazo|deadline|fecha\s+limite|fecha\s+de\s+envio\s+de\s+propuesta|envio\s+de\s+propuesta|entrega\s+de\s+propuesta|se\s+extiende|se\s+amplia|prorroga|hasta\s+(?:el\s+)?(?:dia\s+)?)/i;
export function parseDeadlineEvents(messages:{snippet?:string;internalDate?:string}[]):DeadlineEvent[] {
  const found:DeadlineEvent[]=[];
  for(const message of messages){
    const text=clean(message.snippet,1200),baseYear=new Date(Number(message.internalDate)).getUTCFullYear()||new Date().getUTCFullYear();
    datePattern.lastIndex=0;isoDatePattern.lastIndex=0;
    const dateMatches=[
      ...Array.from(text.matchAll(datePattern),match=>({index:match.index??0,full:match[0],weekday:matchedWeekday,day:Number(match[2]),month:Number(match[3]),yearRaw:match[4]})),
      ...Array.from(text.matchAll(isoDatePattern),match=>({index:match.index??0,full:match[0],weekday:null,day:Number(match[3]),month:Number(match[2]),yearRaw:match[1]})),
    ].sort((a,b)=>a.index-b.index);
    for(const match of dateMatches){
      const {index,full,weekday:matchedWeekday,day,month,yearRaw}=match,before=text.slice(Math.max(0,index-120),index),after=text.slice(index+full.length,index+55);
      if(!deadlineCue.test(norm(before))&&!/^\s*(?:a\s+las?\s*)?\d{1,2}(?::\d{2})?\s*(?:a\.?\s*m\.?|p\.?\s*m\.?)/i.test(after))continue;
      const nearBefore=norm(before.slice(-85));
      if(/fecha\s+de\s+visita|visita\s+tecnica/.test(nearBefore)&&!/(plazo|deadline|entrega|envio|vencimiento)/.test(nearBefore.slice(-45)))continue;
      const baseYear=new Date(Number(message.internalDate)).getUTCFullYear()||new Date().getUTCFullYear();
      const year=yearRaw?(Number(yearRaw)<100?2000+Number(yearRaw):Number(yearRaw)):baseYear;
      const candidate=new Date(Date.UTC(year,month-1,day));
      const valid=candidate.getUTCFullYear()===year&&candidate.getUTCMonth()===month-1&&candidate.getUTCDate()===day;
      const weekday=matchedWeekday?norm(matchedWeekday):null;
      const weekdayMismatch=!!weekday&&valid&&candidate.getUTCDay()!==weekdayIndex[weekday];
      const timeMatch=after.match(/^[\s–—-]*(?:a\s+las?\s*)?(\d{1,2})(?::(\d{2}))?\s*(a\.?\s*m\.?|p\.?\s*m\.?)/i);
      let time:string|null=null,datetime:string|null=null;
      if(timeMatch){
        let hour=Number(timeMatch[1]);const minute=Number(timeMatch[2]??0),meridiem=norm(timeMatch[3]).replace(/\s/g,'').replace(/\./g,'');
        if(hour>=1&&hour<=12&&minute<60){if(meridiem.startsWith('p')&&hour<12)hour+=12;if(meridiem.startsWith('a')&&hour===12)hour=0;time=String(hour).padStart(2,'0')+':'+String(minute).padStart(2,'0');}
      }
      const status:DeadlineEvent['status']=valid&&!weekdayMismatch?'confirmed':'ambiguous';
      const date=valid&&!weekdayMismatch?candidate.toISOString().slice(0,10):null;
      if(date&&time)datetime=date+'T'+time+':00-05:00';
      const kind:DeadlineEvent['kind']=/se\s+extiende|se\s+amplia|prorroga|nuevo\s+plazo|amplia\s+plazo|extiende\s+plazo/i.test(nearBefore)?'extension':'stated';
      const raw=clean(text.slice(Math.max(0,index-65),Math.min(text.length,index+full.length+35)),180);
      const event:DeadlineEvent={raw,date,time,datetime,timezone:'America/Lima',status,kind,weekday:match[1]??null};
      if(!found.some(x=>x.date===event.date&&x.time===event.time&&x.kind===event.kind))found.push(event);
    }
  }
  return found;
}
export function classifyThread(thread:{id?:string;messages?:Message[]},from:number,to:number):Candidate|null {
  if(!validId(thread.id))return null;
  const messages=(thread.messages??[]).filter(m=>validId(m.id)&&!isExcluded(m)&&Number(m.internalDate)>=from&&Number(m.internalDate)<=to).sort((a,b)=>Number(a.internalDate)-Number(b.internalDate));
  const external=messages.filter(m=>!isSent(m));
  const forwarded=messages.filter(m=>isInternal(m)&&!!forwardedSender(m));
  const sourceMessages=external.length?external:forwarded;
  const internal=messages.filter(isSent);
  const quoteReplies=internal.filter(m=>sentQuote.test(norm(clean(m.snippet,500)))&&attachments(m).length>0);
  if(!sourceMessages.length&&!quoteReplies.length)return null;
  const m=sourceMessages.length?sourceMessages[sourceMessages.length-1]:quoteReplies[quoteReplies.length-1];
  const subject=header(m,'Subject'),snippet=clean(m.snippet,500),sender=header(m,'From');
  const text=norm(subject+' '+snippet);
  const context=sourceMessages.map(x=>header(x,'Subject')+' '+clean(x.snippet,500)).join(' ');
  const refs=references(context);
  const latestSourceAt=Number(m.internalDate);
  const sentEvidence=quoteReplies.some(x=>Number(x.internalDate)>latestSourceAt);
  const unresolvedInternalReply=internal.some(x=>Number(x.internalDate)>latestSourceAt&&!forwardedSender(x));
  const deadlineMessages=sourceMessages.length?sourceMessages:quoteReplies;
  const deadlineEvents=parseDeadlineEvents(deadlineMessages);
  let category:Category='other',reason='No se detectó una solicitud comercial explícita.';
  if(!sourceMessages.length){category='quoted';reason='Cotización enviada desde un alias interno de ROMAX; no es una nueva solicitud.';}
  else if(support.test(text+' '+norm(context))){category='other';reason='Comunicación de soporte o notificaciones de una plataforma; no es una solicitud comercial.';}
  else if(refs.length>1){category='review';reason='Hay varias referencias de solicitud en la conversación.';}
  else if(adjust.test(text)){category='adjustment';reason='Se detectó una petición de ajuste comercial.';}
  else if(sentEvidence&&quote.test(norm(context))){category='quoted';reason='Existe una cotización posterior enviada por ROMAX; verificar antes de descartar.';}
  else if(unresolvedInternalReply&&quote.test(norm(context))){category='review';reason='Hay una respuesta posterior de ROMAX, pero no confirma el envío de una cotización.';}
  else if(follow.test(text)||deadlineEvents.some(e=>e.kind==='extension')){category='follow_up';reason='Se detectó una actualización o ampliación de plazo de una solicitud.';}
  else if(operation.test(text)&&!quote.test(text)){category='operational';reason='Parece una coordinación operativa o documento de compra.';}
  else if(quote.test(text+' '+norm(context))&&requestQuote.test(text+' '+norm(context))&&!operation.test(text)){category='quote_request';reason='El asunto o extracto contiene una petición de cotización.';}
  else if(quote.test(text+' '+norm(context))||operation.test(text)){category='review';reason='Hay indicios comerciales, pero el extracto no permite distinguir el caso con seguridad.';}
  const attachmentMessages=sourceMessages.length?sourceMessages:quoteReplies;
  const allAttachments=Array.from(new Map(attachmentMessages.flatMap(attachments).map(x=>[x.name+'\0'+x.mime,x])).values()).slice(0,50);
  const currentDeadline=[...deadlineEvents].reverse().find(e=>e.kind==='extension')??deadlineEvents[deadlineEvents.length-1]??null;
  const reference=refs.length===1?refs[0]:rmxReference(context+' '+subject+' '+snippet);
  return {thread_id:thread.id,message_id:m.id!,subject:subject||'Sin asunto',sender:forwardedSender(m)??sender,received_at:new Date(Number(m.internalDate)).toISOString(),snippet,category,reason,reference,deadline_hint:currentDeadline?.raw??null,deadline_events:deadlineEvents,message_count:messages.length,attachments:allAttachments};
}
export async function readPreview(request:typeof fetch,token:string,from:number,to:number,pageToken?:string) {
  const started=Date.now();
  const root='https://gmail.googleapis.com/gmail/v1/users/me/threads';
  const get=async(url:URL)=>{
    const remaining=25000-(Date.now()-started);
    if(remaining<=0)throw new Error('Preview timeout');
    let response=await request(url,{method:'GET',headers:{Authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(Math.min(remaining,8000))});
    if([429,502,503,504].includes(response.status)&&remaining>3500){
      await new Promise(resolve=>setTimeout(resolve,350));
      response=await request(url,{method:'GET',headers:{Authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(Math.min(remaining-350,8000))});
    }
    if(!response.ok)throw new Error('Preview request failed');
    return await response.json();
  };
  const list=new URL(root);
  list.search=new URLSearchParams({q:'after:'+Math.floor(from/1000)+' before:'+Math.ceil(to/1000)+' -in:spam -in:trash -in:drafts',maxResults:String(PAGE_SIZE),includeSpamTrash:'false',fields:'threads(id),nextPageToken,resultSizeEstimate'}).toString();
  if(pageToken)list.searchParams.set('pageToken',pageToken);
  const result=await get(list);
  const ids=[...new Set<string>((result.threads??[]).map((x:{id?:string})=>x.id).filter(validId))].slice(0,PAGE_SIZE);
  const candidates:Candidate[]=[];
  for(let i=0;i<ids.length;i+=3){
    const batch=await Promise.all(ids.slice(i,i+3).map(async id=>{
      const url=new URL(root+'/'+encodeURIComponent(id));
      // Request only headers, snippets and attachment names; never body.data or attachment endpoints.
      url.search=new URLSearchParams({format:'full',fields:'id,messages(id,internalDate,labelIds,snippet,payload(headers(name,value),filename,mimeType,parts(filename,mimeType,parts(filename,mimeType,parts(filename,mimeType)))) )'.replace(/\s/g,'')}).toString();
      const thread=await get(url);
      if(thread.id!==id)throw new Error('Thread identity mismatch');
      return classifyThread(thread,from,to);
    }));
    candidates.push(...batch.filter((x):x is Candidate=>x!==null));
  }
  return {candidates,scanned:ids.length,next:typeof result.nextPageToken==='string'&&result.nextPageToken.length<4096?result.nextPageToken:null,estimate:Number.isSafeInteger(result.resultSizeEstimate)?result.resultSizeEstimate:null};
}
