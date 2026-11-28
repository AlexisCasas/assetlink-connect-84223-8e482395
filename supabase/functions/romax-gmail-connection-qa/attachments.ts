// Directed discovery only: no body.data, snippets, attachment GETs, external URLs or binary reads.
export type AttachmentMetadata = {
  message_id:string; locator:string; locator_kind:'attachment_id'|'mime_part';
  filename:string; mime_type:string; size_bytes:number|null; received_at:string;
  direction:'incoming'|'outgoing'|'unknown';
  part_id?:string;
};
type Header={name?:string;value?:string};
type Part={partId?:string; filename?:string;mimeType?:string;headers?:Header[];
  body?:{size?:number;attachmentId?:string};parts?:Part[]};
type Message={id?:string;threadId?:string;internalDate?:string;labelIds?:string[];payload?:Part};
const ROOT='https://gmail.googleapis.com/gmail/v1/users/me/threads/';
const MAX_BYTES=2*1024*1024, MAX_MESSAGES=80, MAX_FILES=50, MAX_DEPTH=6, MAX_NODES=2000;
const validId=(x:unknown):x is string=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(x);
const header=(p:Part,name:string)=>{const h=Array.isArray(p.headers)?p.headers.find(h=>h&&typeof h.name==='string'&&h.name.toLowerCase()===name):undefined;return typeof h?.value==='string'?h.value:'';};
// Registry keys are not Gmail download tokens. Root is distinct from part 0.
export const stablePartKey=(part:string|undefined)=>part==='root'?'r4f_part_v1_root':typeof part==='string'&&part.length<=128&&/^\d+(?:\.\d+)*$/.test(part)?'r4f_part_v1_'+part.replaceAll('.','_'):null;
export const isStablePartKey=(key:string)=>/^r4f_part_v1_(?:root|\d+(?:_\d+)*)$/.test(key);
const unsafeName=/[\p{Cc}\p{Cf}\p{Cs}\/\\]/u;
function fields(depth:number):string {
  return 'partId,filename,mimeType,headers(name,value),body(size,attachmentId),parts('+
    (depth>0?fields(depth-1):'partId')+')';
}
async function boundedJson(response:Response,signal:AbortSignal):Promise<unknown>{
  if(!response.ok)throw new Error('Gmail metadata unavailable');
  const reader=response.body?.getReader();if(!reader)throw new Error('Empty metadata');
  const chunks:Uint8Array[]=[];let size=0;
  const abort=()=>{void reader.cancel().catch(()=>{});};
  signal.addEventListener('abort',abort,{once:true});
  try{
    while(true){signal.throwIfAborted();const {done,value}=await reader.read();signal.throwIfAborted();if(done)break;
      size+=value.byteLength;if(size>MAX_BYTES){await reader.cancel();throw new Error('Metadata response limit');}
      chunks.push(value);}
  }finally{signal.removeEventListener('abort',abort);reader.releaseLock();}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
export async function discoverAttachments(request:typeof fetch,token:string,thread:string,mailbox:string,signal=AbortSignal.timeout(25000)){
  if(!validId(thread))throw new Error('Invalid thread identity');
  const url=new URL(ROOT+encodeURIComponent(thread));
  url.search=new URLSearchParams({format:'full',fields:'id,messages(id,threadId,internalDate,labelIds,payload('+fields(MAX_DEPTH)+'))'}).toString();
  const response=await request(url,{method:'GET',headers:{Authorization:'Bearer '+token},redirect:'error',signal});
  const data=await boundedJson(response,signal) as {id?:string;messages?:Message[]};
  if(!data||data.id!==thread||!Array.isArray(data.messages))throw new Error('Thread identity mismatch');
  // Verify all message identities before selecting a bounded subset, even if older or excluded.
  const ids=new Set<string>();
  for(const m of data.messages){
    if(!m||m.threadId!==thread||!validId(m.id)||ids.has(m.id))throw new Error('Message identity mismatch');
    ids.add(m.id);
    if((m.labelIds!==undefined&&(!Array.isArray(m.labelIds)||m.labelIds.some(l=>typeof l!=='string')))||typeof m.internalDate!=='string'||!/^\d{1,15}$/.test(m.internalDate)||
      !Number.isSafeInteger(Number(m.internalDate))||Number(m.internalDate)<=0||!Number.isFinite(new Date(Number(m.internalDate)).getTime()))
      throw new Error('Invalid message metadata');
  }
  const eligible=data.messages.filter(m=>!(m.labelIds??[]).some(l=>['SPAM','TRASH','DRAFT'].includes(l)));
  eligible.sort((a,b)=>Number(b.internalDate)-Number(a.internalDate)||a.id!.localeCompare(b.id!));
  const items:AttachmentMetadata[]=[];const seen=new Map<string,string>();
  const reasons=new Set<string>();let inlineSkipped=0,unsafeSkipped=0,excludedMessages=data.messages.length-eligible.length,nodes=0;
  if(eligible.length>MAX_MESSAGES)reasons.add('message_limit');
  for(const m of eligible.slice(0,MAX_MESSAGES)){
    signal.throwIfAborted();
    if(!m.payload){reasons.add('missing_payload');continue;}
    const from=header(m.payload,'from').trim().toLowerCase();
    const address=from.match(/<([^<>]+)>$/)?.[1]??from;
    const direction:AttachmentMetadata['direction']=(m.labelIds??[]).includes('SENT')||
      /^[^\s@]+@romaxfm\.com$/.test(address)||address===mailbox.toLowerCase()?'outgoing':
      /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)?'incoming':'unknown';
    const walk=(p:Part,depth:number)=>{
      if(!p||typeof p!=='object'){reasons.add('invalid_part');return;}
      if(++nodes>MAX_NODES){reasons.add('part_limit');return;}
      if(depth>MAX_DEPTH){reasons.add('depth_limit');return;}
      const disposition=header(p,'content-disposition').trim().toLowerCase();
      const explicitlyAttached=/^attachment(?:\s*;|$)/.test(disposition);
      const inline=/^inline(?:\s*;|$)/.test(disposition)||(!explicitlyAttached&&!!header(p,'content-id'));
      const name=typeof p.filename==='string'?p.filename.normalize('NFC').trim():'';
      const mime=typeof p.mimeType==='string'?p.mimeType.trim().toLowerCase():'';
      if(name||explicitlyAttached){
        if(inline){inlineSkipped++;}
        else if(!name||name.length>250||name==='.'||name==='..'||unsafeName.test(name)||!mime||mime.length>120||!/^[a-z0-9.+_-]+\/[a-z0-9.+_-]+$/.test(mime)){
          unsafeSkipped++;reasons.add('unsafe_metadata');
        }else{
          const aid=p.body?.attachmentId;
          const pid=p.partId;
          const kind=typeof aid==='string'&&aid.length>0&&aid.length<=2048&&/^[A-Za-z0-9_-]+$/.test(aid)?'attachment_id':'mime_part';
          const locator=kind==='attachment_id'?aid!:aid!==undefined?'':typeof pid==='string'&&pid.length<=128&&/^\d+(?:\.\d+)*$/.test(pid)?pid:depth===0&&pid===''&&!p.parts?.length?'0':'';
          const part=typeof pid==='string'&&pid.length<=128&&/^\d+(?:\.\d+)*$/.test(pid)?pid:depth===0&&pid===''&&!p.parts?.length?'root':undefined;
          const size=p.body?.size;
          if(!locator||(kind==='attachment_id'&&!stablePartKey(part))||!(size===undefined||size===null||Number.isSafeInteger(size)&&size>=0&&size<=9999999999999)){unsafeSkipped++;reasons.add('invalid_locator_or_size');}
          else{
            const item:AttachmentMetadata={message_id:m.id!,locator,locator_kind:kind,filename:name,mime_type:mime,size_bytes:size??null,
              received_at:new Date(Number(m.internalDate)).toISOString(),direction,part_id:part};
            const identity=JSON.stringify([item.message_id,kind,part??locator]),payload=JSON.stringify(item);
            const tokenKey=JSON.stringify([item.message_id,'token',locator]);
            if(seen.has(tokenKey)&&seen.get(tokenKey)!==identity)throw new Error('Conflicting attachment token');
            seen.set(tokenKey,identity);
            if(seen.has(identity)){if(seen.get(identity)!==payload)throw new Error('Conflicting MIME identity');}
            else if(items.length>=MAX_FILES){reasons.add('attachment_limit');}
            else{seen.set(identity,payload);items.push(item);}
          }
        }
      }
      // Do not recurse into attached mail or another attachment container.
      if(name||explicitlyAttached||mime==='message/rfc822')return;
      if(p.parts!==undefined&&!Array.isArray(p.parts)){reasons.add('invalid_part');return;}
      for(const child of p.parts??[]){if(nodes>=MAX_NODES){reasons.add('part_limit');break;}walk(child,depth+1);}
    };
    walk(m.payload,0);
  }
  return {items,scanned_messages:Math.min(eligible.length,MAX_MESSAGES),excluded_messages:excludedMessages,
    skipped_inline:inlineSkipped,skipped_unsafe:unsafeSkipped,partial:reasons.size>0,reasons:[...reasons].sort()};
}

// Preserve legacy registry rows; new external attachments use stable part identity.
// Raw remote tokens live only in the current server request.
export type RegistryRow={source_message_id:string;source_attachment_id:string;source_locator_kind:string;filename:string;mime_type:string;size_bytes:number|null;source_received_at:string;source_direction:string};
const tuple=(x:AttachmentMetadata,r:RegistryRow)=>x.message_id===r.source_message_id&&x.filename===r.filename&&x.mime_type===r.mime_type&&x.size_bytes===r.size_bytes&&
  Date.parse(x.received_at)===Date.parse(r.source_received_at)&&x.direction===r.source_direction&&x.locator_kind===r.source_locator_kind;
export function registryPayload(items:AttachmentMetadata[],existing:RegistryRow[],partial:boolean){
  const output:AttachmentMetadata[]=[]; const used=new Set<string>();
  for(const x of items){
    const {part_id,...base}=x;
    if(x.locator_kind!=='attachment_id'){output.push(base);continue;}
    const stable=stablePartKey(part_id);if(!stable)throw new Error('Missing stable part');
    const same=existing.filter(r=>r.source_message_id===x.message_id&&r.source_locator_kind==='attachment_id');
    const keyed=same.filter(r=>r.source_attachment_id===stable);
    const legacy=same.filter(r=>!isStablePartKey(r.source_attachment_id)&&tuple(x,r));
    let locator=stable;
    if(keyed.length){
      if(keyed.length!==1||!tuple(x,keyed[0])||legacy.length)throw new Error('Registry identity conflict');
    }else if(legacy.length){
      if(partial||legacy.length!==1||items.filter(y=>tuple(y,legacy[0])).length!==1)throw new Error('Ambiguous legacy identity');
      locator=legacy[0].source_attachment_id;
    }
    const key=JSON.stringify([x.message_id,locator]);if(used.has(key))throw new Error('Registry identity conflict');
    used.add(key);output.push({...base,locator});
  }
  return output;
}
export function currentDownloadLocator(c:{message:string;locator:string;filename:string;mime:string;size:number},items:AttachmentMetadata[],existing:RegistryRow[],partial:boolean){
  const rows=existing.filter(r=>r.source_message_id===c.message&&r.source_attachment_id===c.locator&&r.source_locator_kind==='attachment_id'&&r.filename===c.filename&&r.mime_type===c.mime&&r.size_bytes===c.size);
  if(rows.length!==1)return null;
  const row=rows[0];
  const matches=items.filter(x=>tuple(x,row));
  if(isStablePartKey(c.locator)){
    const exact=matches.filter(x=>stablePartKey(x.part_id)===c.locator);
    return exact.length===1?exact[0].locator:null;
  }
  // Historical raw token: require unique metadata in both registry and complete current scan.
  if(partial||matches.length!==1||existing.filter(r=>tuple(matches[0],r)).length!==1)return null;
  return matches[0].locator;
}
