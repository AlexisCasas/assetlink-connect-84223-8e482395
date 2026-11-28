import {issueConfirmation,openConfirmation,candidateDigest,IMPORT_TTL_MS,senderEmail} from './import.ts';
import {importKey} from './crypto.ts';
import type {Candidate} from './preview.ts';
function assert(v:unknown){if(!v)throw new Error('Assertion failed');}
async function rejects(f:()=>Promise<unknown>){let failed=false;try{await f();}catch{failed=true;}assert(failed);}
const now=Date.now(),from=now-7*86400000;
const c:Candidate={thread_id:'synthetic-thread',message_id:'synthetic-message',subject:'Request',sender:'Test <client@example.test>',received_at:new Date(now-1000).toISOString(),snippet:'request',category:'quote_request',reason:'synthetic',reference:null,deadline_hint:null,deadline_events:[],message_count:1,attachments:[],text_source:'body',body_limited:false,import_policy:'new_candidate'};
Deno.test('confirmation is authenticated, expires and binds candidate data',async()=>{
  const key=await importKey(btoa('k'.repeat(32)));const token=await issueConfirmation(key,'org:owner:connection:origin',c,from,now);
  const decoded=await openConfirmation(key,'org:owner:connection:origin',token,now);
  assert(decoded.thread===c.thread_id&&decoded.message===c.message_id&&decoded.digest===await candidateDigest(c));
  await rejects(()=>openConfirmation(key,'org:other:connection:origin',token,now));
  await rejects(()=>openConfirmation(key,'org:owner:other:origin',token,now));
  await rejects(()=>openConfirmation(key,'org:owner:connection:origin',token,now+IMPORT_TTL_MS));
  await rejects(()=>openConfirmation(key,'org:owner:connection:origin',token+'x',now));
  await rejects(()=>issueConfirmation(key,'context',{...c,import_policy:'review_required'},from,now));
  assert(await candidateDigest({...c,subject:'changed'})!==decoded.digest);
  assert(senderEmail(c.sender)==='client@example.test');
});
