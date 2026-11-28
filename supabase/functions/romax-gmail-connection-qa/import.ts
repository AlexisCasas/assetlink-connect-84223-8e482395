import { hashState, randomToken, seal, unseal } from './crypto.ts';
import type { Candidate } from './preview.ts';

export const IMPORT_TTL_MS=5*60*1000;
const validId=(v:unknown):v is string=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
export type Confirmation={thread:string;message:string;from:number;expires:number;nonce:string;digest:string};
export const candidateDigest=(c:Candidate)=>hashState(JSON.stringify([
  c.thread_id,c.message_id,c.subject,c.sender,c.received_at,c.snippet,c.category,c.reason,
  c.reference,c.deadline_events,c.message_count,c.attachments,c.text_source,c.body_limited
]));
export async function issueConfirmation(key:CryptoKey,context:string,c:Candidate,from:number,now=Date.now()){
  if(c.import_policy!=='new_candidate'||c.category!=='quote_request'||c.body_limited)throw new Error('Ineligible candidate');
  const value:Confirmation={thread:c.thread_id,message:c.message_id,from,expires:now+IMPORT_TTL_MS,nonce:randomToken(),digest:await candidateDigest(c)};
  return await seal(key,JSON.stringify(value),context);
}
export async function openConfirmation(key:CryptoKey,context:string,token:unknown,now=Date.now()):Promise<Confirmation>{
  if(typeof token!=='string'||token.length>4096)throw new Error('Invalid confirmation');
  const c=JSON.parse(await unseal(key,token,context));
  if(!validId(c.thread)||!validId(c.message)||!Number.isSafeInteger(c.from)||!Number.isSafeInteger(c.expires)||
    c.from>now||c.from<now-7*86400000-15*60000||c.expires<=now||c.expires>now+IMPORT_TTL_MS||
    typeof c.nonce!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(c.nonce)||
    typeof c.digest!=='string'||!/^[a-f0-9]{64}$/.test(c.digest))throw new Error('Expired or invalid confirmation');
  return c;
}
export function senderEmail(value:string):string|null {
  return (value.match(/<([^<>\s]+@[^<>\s]+)>/)?.[1]??value.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)?.[0]??null)?.toLowerCase()??null;
}
