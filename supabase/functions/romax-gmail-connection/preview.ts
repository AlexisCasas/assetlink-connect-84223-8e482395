export const DAY_MS = 86400000;
export const PAGE_SIZE = 12;
export type Category = 'quote_request' | 'follow_up' | 'adjustment' | 'quoted' | 'operational' | 'other' | 'review';
type Part = { filename?: string; mimeType?: string; parts?: Part[] };
type Message = { id?: string; internalDate?: string; labelIds?: string[]; snippet?: string; payload?: Part & { headers?: {name:string;value:string}[] } };
export type Candidate = { thread_id:string; message_id:string; subject:string; sender:string; received_at:string; snippet:string; category:Category; reason:string; reference:string|null; deadline_hint:string|null; message_count:number; attachments:{name:string;mime:string;supported:boolean}[]; existing_status?:string|null };
const clean = (s:unknown,max:number) => typeof s==='string' ? s.replace(/[\u0000-\u001f\u007f]/g,' ').slice(0,max).trim() : '';
const norm = (s:string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const header = (m:Message,name:string) => clean(m.payload?.headers?.find(h=>h.name.toLowerCase()===name)?.value,500);
const validId=(id:unknown):id is string=>typeof id==='string' && /^[a-zA-Z0-9_-]{1,128}$/.test(id);
const isSent=(m:Message)=>m.labelIds?.includes('SENT')===true;
const isExcluded=(m:Message)=>m.labelIds?.some(l=>['SPAM','TRASH','DRAFT'].includes(l))===true;
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
const quote=/\b(cotizacion|cotizar|presupuesto|licitacion|propuesta economica|rfq|solicitud de oferta)\b/;
const adjust=/\b(reajuste|reajustar|mejora de precio|mejorar el precio|descuento|actualizar (?:la )?(?:cotizacion|propuesta))\b/;
const follow=/\b(recordatorio|seguimiento|prorroga|ampliacion (?:de |del )?plazo|nuevo plazo|nueva fecha|fecha limite|reprogramacion)\b/;
const operation=/\b(orden de compra|orden de servicio|acta de conformidad|factura|coordinacion de visita|inicio de trabajos|ejecucion de trabajos)\b/;
const requestQuote=/\b(solicit(?:a|amos|ud|ar|an)|requerimiento|invitacion|favor|agradeceremos|necesitamos|convocatoria)\b/;
const sentQuote=/\b(adjuntamos|adjunto|enviamos|remitimos|compartimos|se adjunta|se envia)\b.{0,100}\b(cotizacion|propuesta|presupuesto)\b|\b(cotizacion|propuesta|presupuesto)\b.{0,100}\b(adjunta|enviada|remitida)\b/;
const references=(s:string)=>Array.from(new Set((s.toUpperCase().match(/\bSC[-\s]?\d{4,}(?:-\d{4})?\b/g)??[]).map(x=>x.replace(/\s+/g,'-'))));
export function classifyThread(thread:{id?:string;messages?:Message[]},from:number,to:number):Candidate|null {
  if(!validId(thread.id))return null;
  const messages=(thread.messages??[]).filter(m=>validId(m.id)&&!isExcluded(m)&&Number(m.internalDate)>=from&&Number(m.internalDate)<=to).sort((a,b)=>Number(a.internalDate)-Number(b.internalDate));
  const incoming=messages.filter(m=>!isSent(m));
  if(!incoming.length)return null;
  const m=incoming[incoming.length-1],subject=header(m,'Subject'),snippet=clean(m.snippet,500),text=norm(subject+' '+snippet);
  const previous=incoming.slice(0,-1);
  const context=incoming.map(x=>header(x,'Subject')+' '+clean(x.snippet,500)).join(' ');
  const refs=references(context);
  let category:Category='other',reason='No se detectó una solicitud comercial explícita.';
  const latestSent=messages.filter(x=>isSent(x)&&Number(x.internalDate)>Number(m.internalDate));
  const sentEvidence=latestSent.some(x=>sentQuote.test(norm(clean(x.snippet,500)))&&attachments(x).length>0);
  if(refs.length>1){category='review';reason='Hay varias referencias de solicitud en la conversación.';}
  else if(adjust.test(text)){category='adjustment';reason='Se detectó una petición de ajuste comercial.';}
  else if(sentEvidence&&quote.test(norm(context))){category='quoted';reason='Existe un envío posterior con texto de cotización y adjunto; verificar antes de descartar.';}
  else if(latestSent.length&&quote.test(norm(context))){category='review';reason='Existe una respuesta posterior, pero no confirma envío de cotización.';}
  else if(operation.test(text)&&!requestQuote.test(text)){category='operational';reason='Parece una coordinación operativa o documento de compra.';}
  else if(follow.test(text)&&(previous.some(x=>quote.test(norm(header(x,'Subject')+' '+clean(x.snippet,500))))||refs.length===1)){category='follow_up';reason='Posible actualización de una solicitud; revisar plazo y referencia.';}
  else if(quote.test(text)&&requestQuote.test(text)&&!operation.test(text)){category='quote_request';reason='El asunto o extracto contiene una petición de cotización.';}
  else if(quote.test(text)||follow.test(text)||operation.test(text)){category='review';reason='Hay indicios comerciales, pero el extracto no permite distinguir el caso con seguridad.';}
  const allAttachments=Array.from(new Map(incoming.flatMap(attachments).map(x=>[x.name+'\0'+x.mime,x])).values()).slice(0,50);
  const deadline=snippet.match(/(?:fecha l[ií]mite|plazo|hasta el|hasta la|vencimiento)[^.!?\n]{0,100}/i)?.[0]??null;
  return {thread_id:thread.id,message_id:m.id!,subject:subject||'Sin asunto',sender:header(m,'From'),received_at:new Date(Number(m.internalDate)).toISOString(),snippet,category,reason,reference:refs.length===1?refs[0]:null,deadline_hint:deadline,message_count:messages.length,attachments:allAttachments};
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
