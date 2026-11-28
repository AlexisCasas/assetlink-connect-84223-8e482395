// Quarantine transport. Preliminary format checks are NOT an antivirus or parser verdict.
import type { AttachmentMetadata } from './attachments.ts';
export const QUARANTINE_BUCKET='romax-request-attachments';
const MAX_FILE=10485760,MAX_RESPONSE=4*Math.ceil(MAX_FILE/3)+4096;
export type Claim={id:string;attempt:string;path:string;thread:string;message:string;locator:string;filename:string;mime:string;size:number};
export class QuarantineError extends Error {
  constructor(readonly code:'source_changed'|'invalid_binary'|'remote_error'){super(code);}
}
export function matchesClaim(c:Claim,items:AttachmentMetadata[]){
  return items.some(x=>x.message_id===c.message&&x.locator_kind==='attachment_id'&&x.locator===c.locator&&
    x.filename===c.filename&&x.mime_type===c.mime&&x.size_bytes===c.size);
}
function preliminary(bytes:Uint8Array,mime:string){
  const starts=(prefix:number[])=>prefix.every((v,i)=>bytes[i]===v);
  switch(mime){
    case 'application/pdf':return starts([37,80,68,70,45]);
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
    case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':return starts([80,75,3,4]);
    case 'image/jpeg':return starts([255,216,255]);
    case 'image/png':return starts([137,80,78,71,13,10,26,10]);
    case 'text/plain':try{return !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return false;}
    default:return false;
  }
}
async function boundedJson(response:Response,signal:AbortSignal):Promise<unknown>{
  if(!response.ok)throw new QuarantineError('remote_error');
  const reader=response.body?.getReader();if(!reader)throw new QuarantineError('remote_error');
  const chunks:Uint8Array[]=[];let size=0;
  const abort=()=>{void reader.cancel().catch(()=>{});};
  signal.addEventListener('abort',abort,{once:true});
  try{
    while(true){signal.throwIfAborted();const {done,value}=await reader.read();signal.throwIfAborted();if(done)break;
      size+=value.byteLength;if(size>MAX_RESPONSE){await reader.cancel();throw new QuarantineError('invalid_binary');}chunks.push(value);}
  }finally{signal.removeEventListener('abort',abort);reader.releaseLock();}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{throw new QuarantineError('invalid_binary');}
}
export async function fetchQuarantineBytes(request:typeof fetch,token:string,claim:Claim,signal:AbortSignal){
  if(!/^[A-Za-z0-9_-]{1,128}$/.test(claim.message)||!claim.locator||claim.locator.length>2048||!/^[A-Za-z0-9_-]+$/.test(claim.locator)||
      !Number.isSafeInteger(claim.size)||claim.size<1||claim.size>MAX_FILE)throw new QuarantineError('source_changed');
  const url=new URL('https://gmail.googleapis.com/gmail/v1/users/me/messages/'+encodeURIComponent(claim.message)+'/attachments/'+encodeURIComponent(claim.locator));
  url.searchParams.set('fields','size,data');
  const data=await boundedJson(await request(url,{method:'GET',headers:{Authorization:'Bearer '+token},redirect:'error',signal}),signal) as {size?:number;data?:string};
  if(!data||data.size!==claim.size||typeof data.data!=='string'||data.data.length>4*Math.ceil(claim.size/3)||
     !/^[A-Za-z0-9_-]+={0,2}$/.test(data.data))throw new QuarantineError('invalid_binary');
  let bytes:Uint8Array<ArrayBuffer>;
  try{
    const raw=data.data.replace(/=+$/,'');
    if(raw.length%4===1||(data.data.includes('=')&&data.data.length%4!==0))throw new Error('padding');
    const canonical=raw.replace(/-/g,'+').replace(/_/g,'/');
    const decoded=atob(canonical.padEnd(Math.ceil(canonical.length/4)*4,'='));
    bytes=Uint8Array.from(decoded,c=>c.charCodeAt(0));
    if(btoa(decoded).replace(/=+$/,'').replace(/\+/g,'-').replace(/\//g,'_')!==raw)throw new Error('noncanonical');
  }catch{throw new QuarantineError('invalid_binary');}
  if(bytes.byteLength!==claim.size||!preliminary(bytes,claim.mime))throw new QuarantineError('invalid_binary');
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
  return {bytes,hash};
}
