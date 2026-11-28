export const DAY_MS = 86400000;
export const PAGE_SIZE = 12;
export type Category = 'quote_request' | 'follow_up' | 'adjustment' | 'quoted' | 'operational' | 'other' | 'review';
export type DeadlineEvent = { raw:string; date:string|null; time:string|null; datetime:string|null; timezone:'America/Lima'; status:'confirmed'|'ambiguous'; kind:'extension'|'stated'; weekday:string|null };
type Part = { filename?: string; mimeType?: string; parts?: Part[]; headers?: {name:string;value:string}[]; body?: {data?:string;size?:number;attachmentId?:string} };
type Message = { id?: string; internalDate?: string; labelIds?: string[]; snippet?: string; bodyText?: string; bodyLimited?: boolean; payload?: Part & { headers?: {name:string;value:string}[] } };
export type Candidate = { thread_id:string; message_id:string; subject:string; sender:string; received_at:string; snippet:string; category:Category; reason:string; reference:string|null; deadline_hint:string|null; deadline_events:DeadlineEvent[]; message_count:number; attachments:{name:string;mime:string;supported:boolean}[]; existing_status?:string|null; text_source:'body'|'snippet'; body_limited:boolean; import_policy:'new_candidate'|'link_existing'|'review_required'|'not_importable' };
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

const BODY_CHARS=48000, MAX_BODY_MESSAGES=12, MAX_JSON_BYTES=2*1024*1024;
const decodeEntities=(s:string)=>s.replace(/&(?:nbsp|amp|lt|gt|quot|apos|#39|#160|#x[0-9a-f]+|#\d+);/gi,token=>{
  const named:Record<string,string>={'&nbsp;':' ','&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&apos;':"'",'&#39;':"'",'&#160;':' '};
  const key=token.toLowerCase();if(named[key]!==undefined)return named[key];
  const n=key.startsWith('&#x')?parseInt(key.slice(3,-1),16):Number(key.slice(2,-1));
  return Number.isInteger(n)&&n>0&&n<=0x10ffff&&!(n>=0xd800&&n<=0xdfff)?String.fromCodePoint(n):' ';
});
function htmlText(s:string){return decodeEntities(s.replace(/<!--[\s\S]*?-->/g,' ').replace(/<(script|style|head|noscript)\b[^>]*>[\s\S]*?<\/\1\s*>/gi,' ').replace(/<br\b[^>]*>|<\/(?:p|div|li|tr|h[1-6]|blockquote)>/gi,'\n').replace(/<[^>]*>/g,' '));}
export function extractMessageText(payload:Part|undefined):{text:string;limited:boolean}{
  const plain:string[]=[],html:string[]=[];let limited=false,nodes=0,used=0;
  function walk(p:Part|undefined,depth:number){
    if(!p)return;if(depth>5||++nodes>100){limited=true;return;}
    if(p.filename||p.headers?.some(x=>x.name.toLowerCase()==='content-disposition'&&/^\s*attachment\b/i.test(x.value)))return;
    const mime=(p.mimeType??'').toLowerCase().split(';')[0];
    if(mime==='text/plain'||mime==='text/html'){
      if(p.body?.attachmentId||!p.body?.data){limited=true;return;}
      const data=p.body.data;if(data.length>BODY_CHARS*8||used+data.length>BODY_CHARS*8){limited=true;return;}
      try{const b64=data.replace(/-/g,'+').replace(/_/g,'/');const bin=atob(b64.padEnd(Math.ceil(b64.length/4)*4,'='));
        const decoded=new TextDecoder().decode(Uint8Array.from(bin,c=>c.charCodeAt(0)));
        used+=data.length;
        const value=mime==='text/html'?htmlText(decoded):decoded;
        (mime==='text/html'?html:plain).push(value);
      }catch{limited=true;}
    }else if(mime.startsWith('multipart/')||!mime){for(const child of p.parts??[])walk(child,depth+1);}
  }
  walk(payload,0);const text=(plain.length?plain:html).join('\n').replace(/\r\n?/g,'\n').replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g,' ').trim();
  return {text:text.slice(0,BODY_CHARS),limited:limited||text.length>BODY_CHARS||!text};
}
const messageText=(m:{bodyText?:string;snippet?:string})=>m.bodyText||decodeEntities(m.snippet??'');
function primaryText(m:{bodyText?:string;snippet?:string},forward=false){
  const s=messageText(m);
  if(forward)return s;
  // Classify the new message, not quoted reply history; deadline parser may use both.
  const marker=/\n\s*(?:[- ]*(?:forwarded message|mensaje reenviado)[- ]*|(?:De|From):[^\n]*(?:\n|$)|On .{0,220}wrote:|El .{0,220}escribi[oó]:|>)/i.exec(s);
  return marker?s.slice(0,marker.index):s;
}
export function importPolicy(c:Pick<Candidate,'category'|'existing_status'|'body_limited'|'deadline_events'>):Candidate['import_policy']{
  if(c.category==='other'||c.category==='operational'||c.category==='quoted')return 'not_importable';
  if(c.existing_status)return 'link_existing';
  if(c.category!=='quote_request'||c.body_limited||c.deadline_events.some(e=>e.status==='ambiguous'))return 'review_required';
  return 'new_candidate';
}

function forwardedSender(m:Message):string|null {
  const text=clean(messageText(m),12000);
  if(!/(?:forwarded message|begin forwarded message|mensaje reenviado)/i.test(text))return null;
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
const follow=/\b(recordatorio|seguimiento|prorroga|ampliacion (?:de |del )?plazo|se (?:extiende|amplia|prorroga) (?:el )?plazo|extiende plazo|amplia plazo|nuevo plazo|nueva fecha|reprogramacion)\b/;
const support=/\b(suplayer|suplayers|notificaciones? de invitaciones|incidencia de correo|soporte de plataforma)\b/;
const operation=/\b(orden de compra|orden de servicio|acta de conformidad|factura|coordinacion de visita|inicio de trabajos|ejecucion de trabajos|documentos? sst|ingreso a tienda)\b/;
const requestQuote=/\b(solicit(?:a|amos|ud|ar|an)|requerimiento|invitacion|invitamos|invita|favor|agradeceremos|necesitamos|convocatoria|cotizar|presentar propuesta)\b/;
const sentQuote=/\b(adjuntamos|adjunto|enviamos|remitimos|compartimos|se adjunta|se envia|envio)\b.{0,120}\b(cotizacion|propuesta|presupuesto)\b|\b(cotizacion|propuesta|presupuesto)\b.{0,120}\b(adjunta|enviada|remitida)\b/;
const references=(s:string)=>Array.from(new Set((s.toUpperCase().match(/\bSC[-\s]?\d{4,}(?:-\d{4})?\b/g)??[]).map(x=>x.replace(/\s+/g,'-'))));
const rmxReference=(s:string)=>s.toUpperCase().match(/\bRMX[-\s]?\d{4}[-\s]?\d{3,}\b/)?.[0].replace(/\s+/g,'-')??null;
const weekdayIndex:Record<string,number>={domingo:0,lunes:1,martes:2,miercoles:3,jueves:4,viernes:5,sabado:6};
const datePattern=/(?<![\d-])\b(?:(lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo)\s+)?(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?\b/gi;
const isoDatePattern=/\b(\d{4})-(\d{2})-(\d{2})\b/g;
const deadlineCue=/(?:plazo|deadline|fecha\s+limite|(?:envio|entrega|presentacion)\s+de\s+(?:su\s+)?propuestas?|(?:enviar|presentar)\s+(?:su\s+)?propuestas?|se\s+extiende|se\s+amplia|prorroga)/gi;
export function parseDeadlineEvents(messages:{snippet?:string;bodyText?:string;internalDate?:string}[]):DeadlineEvent[] {
  const found:DeadlineEvent[]=[];let previousCurrent:DeadlineEvent|null=null;
  for(const message of messages){
    const text=messageText(message).slice(0,BODY_CHARS),currentEnd=primaryText(message).length;
    let currentEvent:DeadlineEvent|null=null;
    datePattern.lastIndex=0;isoDatePattern.lastIndex=0;
    const dateMatches=[
      ...Array.from(text.matchAll(datePattern),match=>({index:match.index??0,full:match[0],weekday:match[1]??null,day:Number(match[2]),month:Number(match[3]),yearRaw:match[4]})),
      ...Array.from(text.matchAll(isoDatePattern),match=>({index:match.index??0,full:match[0],weekday:null,day:Number(match[3]),month:Number(match[2]),yearRaw:match[1]})),
    ].sort((a,b)=>a.index-b.index);
    for(const match of dateMatches){
      const {index,full,weekday:matchedWeekday,day,month,yearRaw}=match,before=text.slice(Math.max(0,index-120),index),after=text.slice(index+full.length,index+55);
      const nearBefore=norm(before);
      const cues=[...nearBefore.matchAll(deadlineCue)];
      const cue=cues[cues.length-1];
      if(!cue)continue;
      const tail=nearBefore.slice(cue.index??0);
      if(/(?:fecha\s+(?:para|de)\s+visitas?|visita\s+tecnica|enviado\s+el:|(?:^|\n)\s*date:|(?:^|\n)\s*fecha:|inicio\s+de\s+trabajo)/i.test(tail))continue;
      if(/[.!?]\s+[a-z]/i.test(tail.replace(/\b[ap]\.?\s*m\.?/gi,''))||tail.length>110||/\d{1,4}[./-]\d{1,2}\b/.test(tail))continue;
      // Ignore dates inside reply envelope headers or unrelated signature lines.
      if(/(?:^|\n)\s*(?:enviado(?:\s+el)?|date|sent|fecha)\s*:[^\n]*$/i.test(nearBefore)&&!/(?:plazo|deadline|propuesta)[^\n]*$/i.test(nearBefore))continue;
      const baseYear=new Date(Number(message.internalDate)).getUTCFullYear()||new Date().getUTCFullYear();
      const year=yearRaw?(Number(yearRaw)<100?2000+Number(yearRaw):Number(yearRaw)):baseYear;
      const candidate=new Date(Date.UTC(year,month-1,day));
      const valid=candidate.getUTCFullYear()===year&&candidate.getUTCMonth()===month-1&&candidate.getUTCDate()===day;
      const weekday=matchedWeekday?norm(matchedWeekday):null;
      const weekdayMismatch=!!weekday&&valid&&candidate.getUTCDay()!==weekdayIndex[weekday];
      const timeMatch=after.match(/^[\s–—-]*(?:(?:a|hasta)\s+las?\s*)?(\d{1,2})(?::(\d{2}))?\s*(a\.?\s*m\.?|p\.?\s*m\.?)/i);
      let time:string|null=null,datetime:string|null=null;
      if(timeMatch){
        let hour=Number(timeMatch[1]);const minute=Number(timeMatch[2]??0),meridiem=norm(timeMatch[3]).replace(/\s/g,'').replace(/\./g,'');
        if(hour>=1&&hour<=12&&minute<60){if(meridiem.startsWith('p')&&hour<12)hour+=12;if(meridiem.startsWith('a')&&hour===12)hour=0;time=String(hour).padStart(2,'0')+':'+String(minute).padStart(2,'0');}
      }
      const status:DeadlineEvent['status']=valid&&!weekdayMismatch?'confirmed':'ambiguous';
      const date=valid&&!weekdayMismatch?candidate.toISOString().slice(0,10):null;
      if(date&&time)datetime=date+'T'+time+':00-05:00';
      let kind:DeadlineEvent['kind']=/(?:se\s+extiende|se\s+amplia|prorroga|nuevo\s+plazo|amplia\s+plazo|extiende\s+plazo|ampliacion\s+(?:de|del)\s+plazo)[^\d]{0,110}$/i.test(nearBefore)?'extension':'stated';
      if(index<currentEnd&&date&&previousCurrent?.date&&(date!==previousCurrent.date||(time&&previousCurrent.time&&time!==previousCurrent.time)))kind='extension';
      const raw=clean(text.slice(Math.max(0,index-65),Math.min(text.length,index+full.length+35)),180);
      const event:DeadlineEvent={raw,date,time,datetime,timezone:'America/Lima',status,kind,weekday:matchedWeekday};
      if(!found.some(x=>x.date===event.date&&x.time===event.time&&x.kind===event.kind))found.push(event);
      if(index<currentEnd&&event.status==='confirmed')currentEvent=event;
    }
    if(currentEvent)previousCurrent=currentEvent;
  }
  return found;
}
export function classifyThread(thread:{id?:string;messages?:Message[]},from:number,to:number):Candidate|null {
  if(!validId(thread.id))return null;
  const messages=(thread.messages??[]).filter(m=>validId(m.id)&&!isExcluded(m)&&Number(m.internalDate)>=from&&Number(m.internalDate)<=to).sort((a,b)=>Number(a.internalDate)-Number(b.internalDate));
  const external=messages.filter(m=>!isSent(m)&&!m.labelIds?.includes('CATEGORY_PROMOTIONS'));
  const forwarded=messages.filter(m=>isInternal(m)&&!!forwardedSender(m));
  const sourceMessages=external.length?external:forwarded;
  const internal=messages.filter(isSent);
  const quoteReplies=internal.filter(m=>sentQuote.test(norm(clean(m.snippet,500)))&&attachments(m).length>0);
  if(!sourceMessages.length&&!quoteReplies.length)return null;
  const m=sourceMessages.length?sourceMessages[sourceMessages.length-1]:quoteReplies[quoteReplies.length-1];
  const subject=header(m,'Subject'),snippet=clean(m.snippet,500),sender=header(m,'From');
  const text=norm(subject+' '+primaryText(m,!!forwardedSender(m)));
  const context=sourceMessages.map(x=>header(x,'Subject')+' '+primaryText(x,!!forwardedSender(x))).join(' ');
  const commercialText=text.replace(/\bfecha\s+propuesta\s+(?:de|para)\b/g,'fecha prevista para');
  const explicitRequest=quote.test(commercialText)&&requestQuote.test(commercialText);
  const retailPromotion=/\b(black friday|cyber monday|cyber days|cupon|oferta exclusiva|promocion exclusiva|envio gratis|compra ahora)\b/.test(norm(subject+' '+snippet))&&!explicitRequest;
  const bodyLimited=(sourceMessages.length?sourceMessages:quoteReplies).some(x=>x.bodyLimited===true);
  const refs=references(context);
  const latestSourceAt=Number(m.internalDate);
  const sentEvidence=quoteReplies.some(x=>Number(x.internalDate)>latestSourceAt);
  const unresolvedInternalReply=internal.some(x=>Number(x.internalDate)>latestSourceAt&&!forwardedSender(x));
  const deadlineMessages=sourceMessages.length?sourceMessages:quoteReplies;
  const deadlineEvents=parseDeadlineEvents(deadlineMessages);
  let category:Category='other',reason='No se detectó una solicitud comercial explícita.';
  if(!sourceMessages.length){category='quoted';reason='Cotización enviada desde un alias interno de ROMAX; no es una nueva solicitud.';}
  else if(retailPromotion){category='other';reason='Promoción comercial ajena a una solicitud de ROMAX.';}
  else if(support.test(text+' '+norm(context))){category='other';reason='Comunicación de soporte o notificaciones de una plataforma; no es una solicitud comercial.';}
  else if(refs.length>1){category='review';reason='Hay varias referencias de solicitud en la conversación.';}
  else if(adjust.test(text)&&!explicitRequest){category='adjustment';reason='Se detectó una petición de ajuste comercial.';}
  else if(sentEvidence&&quote.test(norm(context))){category='quoted';reason='Existe una cotización posterior enviada por ROMAX; verificar antes de descartar.';}
  else if(unresolvedInternalReply&&quote.test(norm(context))){category='review';reason='Hay una respuesta posterior de ROMAX, pero no confirma el envío de una cotización.';}
  else if(follow.test(text)||deadlineEvents.some(e=>e.kind==='extension')){category='follow_up';reason='Se detectó una actualización o ampliación de plazo de una solicitud.';}
  else if(operation.test(text)&&!explicitRequest){category='operational';reason='Parece una coordinación operativa o documento de compra.';}
  else if(explicitRequest||(!operation.test(text)&&quote.test(text+' '+norm(context))&&requestQuote.test(text+' '+norm(context)))){category='quote_request';reason='El asunto o extracto contiene una petición de cotización.';}
  else if(quote.test(text+' '+norm(context))||operation.test(text)){category='review';reason='Hay indicios comerciales, pero el extracto no permite distinguir el caso con seguridad.';}
  const attachmentMessages=sourceMessages.length?sourceMessages:quoteReplies;
  const allAttachments=Array.from(new Map(attachmentMessages.flatMap(attachments).map(x=>[x.name+'\0'+x.mime,x])).values()).slice(0,50);
  const currentDeadline=[...deadlineEvents].reverse().find(e=>e.kind==='extension')??deadlineEvents[deadlineEvents.length-1]??null;
  const reference=refs.length===1?refs[0]:rmxReference(context+' '+subject+' '+snippet+' '+allAttachments.map(x=>x.name).join(' ')+' '+quoteReplies.map(x=>clean(x.snippet,500)+' '+attachments(x).map(y=>y.name).join(' ')).join(' '));
  const candidate:Candidate={thread_id:thread.id,message_id:m.id!,subject:subject||'Sin asunto',sender:forwardedSender(m)??sender,received_at:new Date(Number(m.internalDate)).toISOString(),snippet,category,reason,reference,deadline_hint:currentDeadline?.raw??null,deadline_events:deadlineEvents,message_count:messages.length,attachments:allAttachments,text_source:(sourceMessages.length?sourceMessages:quoteReplies).some(x=>!!x.bodyText)?'body':'snippet',body_limited:bodyLimited,import_policy:'review_required'};
  candidate.import_policy=importPolicy(candidate);return candidate;
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
    const reader=response.body?.getReader();if(!reader)throw new Error('Empty Gmail response');
    let size=0;const chunks:Uint8Array[]=[];
    try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>MAX_JSON_BYTES){await reader.cancel();throw new Error('Gmail response limit');}chunks.push(value);}}finally{reader.releaseLock();}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
    return JSON.parse(new TextDecoder().decode(bytes));
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
      // First pass: metadata only, including older thread messages; never read older bodies.
      url.search=new URLSearchParams({format:'full',fields:'id,messages(id,internalDate,labelIds,snippet,payload(headers(name,value),filename,mimeType,parts(filename,mimeType,parts(filename,mimeType,parts(filename,mimeType)))) )'.replace(/\s/g,'')}).toString();
      const thread=await get(url);
      if(thread.id!==id)throw new Error('Thread identity mismatch');
      const messages:Message[]=(thread.messages??[]).filter((m:Message)=>validId(m.id)&&!isExcluded(m)&&Number(m.internalDate)>=from&&Number(m.internalDate)<=to);
      const readable=messages.filter(m=>!m.labelIds?.includes('CATEGORY_PROMOTIONS')).sort((a,b)=>Number(b.internalDate)-Number(a.internalDate));
      const partFields=(depth:number):string=>'filename,mimeType,headers(name,value),body(size,data,attachmentId)'+(depth>0?',parts('+partFields(depth-1)+')':'');
      for(const m of readable.slice(MAX_BODY_MESSAGES))m.bodyLimited=true;
      // One text-body GET at a time per thread; at most three concurrent threads.
      for(const m of readable.slice(0,MAX_BODY_MESSAGES)){
        const messageUrl=new URL('https://gmail.googleapis.com/gmail/v1/users/me/messages/'+encodeURIComponent(m.id!));
        messageUrl.search=new URLSearchParams({format:'full',fields:'id,payload('+partFields(4)+')'}).toString();
        try{
          const data=await get(messageUrl);
          if(data.id!==m.id)throw new Error('Message identity mismatch');
          const extracted=extractMessageText(data.payload);
          m.bodyText=extracted.text;m.bodyLimited=extracted.limited;
        }catch(error){
          if(error instanceof Error&&error.message==='Gmail response limit'){m.bodyLimited=true;continue;}
          throw error;
        }
      }
      return classifyThread({id,messages},from,to);
    }));
    candidates.push(...batch.filter((x):x is Candidate=>x!==null));
  }
  return {candidates,scanned:ids.length,next:typeof result.nextPageToken==='string'&&result.nextPageToken.length<4096?result.nextPageToken:null,estimate:Number.isSafeInteger(result.resultSizeEstimate)?result.resultSizeEstimate:null};
}
