import { createHandler } from './handler.ts';
import { READ_SCOPE, importKey, seal, unseal } from './crypto.ts';
const organization='11111111-1111-4111-8111-111111111111', origin='https://example.test', mailbox='pilot@example.test';
type Row=Record<string,unknown>;
function assert(value:unknown, label='Assertion failed') { if(!value) throw new Error(label); }
function fixture(allowedActions?: ReadonlySet<string>, importEnabled=false, enrichmentEnabled=false, oldThread=false, discoveryEnabled=false, quarantineEnabled=false) {
  const received=Date.now()-(oldThread?30*86400000:60000);
  let uploads=0, binaryReads=0, quarantineDone=false, storageFailure=false; const attachmentId='cccccccc-cccc-4ccc-8ccc-cccccccccccc',attemptId='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  let rpcCalls=0, changed=false, discoveryWrites=0, wrongThread=false, revokeDuringRead=false, disconnectDuringRead=false; let reviewReceipt:{args:Row;result:Row}|null=null;
  let row:Row|null=null, profile=mailbox, scope=READ_SCOPE, exchangeCount=0, revokeCount=0, threadReads=0;
  const owners=new Set(['owner','owner2']);
  const variables:Record<string,string>={ROMAX_GMAIL_ATTACHMENT_QUARANTINE_ENABLED:quarantineEnabled?'true':'false',ROMAX_GMAIL_ATTACHMENT_DISCOVERY_ENABLED:discoveryEnabled?'true':'false',ROMAX_GMAIL_ENRICHMENT_ENABLED:enrichmentEnabled?'true':'false',ROMAX_GMAIL_IMPORT_ENABLED:importEnabled?'true':'false',ROMAX_GMAIL_ORGANIZATION_ID:organization,ROMAX_GMAIL_EXPECTED_EMAIL:mailbox,ROMAX_GMAIL_APP_ORIGIN:origin,ROMAX_GMAIL_CLIENT_ID:'synthetic-client',ROMAX_GMAIL_CLIENT_SECRET:'synthetic-secret',ROMAX_GMAIL_ENCRYPTION_KEY:btoa('k'.repeat(32))};
  class Query {
    private filters:((record:Row)=>boolean)[]=[];
    private changes:Row|null=null;
    constructor(private name:string){}
    select(){return this;}
    eq(key:string,value:unknown){this.filters.push(r=>r[key]===value);return this;}
    is(key:string,value:unknown){this.filters.push(r=>r[key]===value);return this;}
    gt(key:string,value:string){this.filters.push(r=>String(r[key])>value);return this;}
    in(key:string,values:unknown[]){this.filters.push(r=>values.includes(r[key]));return this;}
    limit(){return this;}
    update(values:Row){this.changes=values;return this;}
    upsert(values:Row){if(!row) row={...values,status:'disconnected',attempt_hash:null,attempt_expires_at:null};return Promise.resolve({data:null,error:null});}
    private execute(single:boolean){
      if(this.name==='organization_members'){
        const data=[...owners].map(user_id=>({id:user_id,organization_id:organization,user_id,role:'owner',is_active:true,'organizations.organization_type':'provider_company','organizations.status':'active'})).filter(r=>this.filters.every(f=>f(r)));
        return {data,error:null};
      }
      if(this.name==='romax_opportunities'){
        assert(!this.changes,'Preview must not write opportunities');
        const data=[{id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',organization_id:organization,source_system:'gmail',source_thread_id:'thread1',status:'in_analysis'},{id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',organization_id:'another',source_system:'gmail',source_thread_id:'thread2',status:'quoted'}].filter(r=>this.filters.every(f=>f(r)));
        return {data:single?(data[0]??null):data,error:null};
      }
      if(!row || !this.filters.every(f=>f(row!)))return {data:single?null:[],error:null};
      if(this.changes)row={...row,...this.changes};
      return {data:single?{...row}:[{...row}],error:null};
    }
    maybeSingle(){return Promise.resolve(this.execute(true));}
    then(resolve:(value:unknown)=>unknown,reject:(reason:unknown)=>unknown){return Promise.resolve(this.execute(false)).then(resolve,reject);}
  }
  const request:typeof fetch=async(input,init)=>{
    const url=String(input), values=new URLSearchParams(String(init?.body??''));
    if(url==='https://oauth2.googleapis.com/token'){
      assert(values.get('client_secret')==='synthetic-secret');
      if(values.get('grant_type')==='authorization_code'){
        exchangeCount++;assert(values.get('code_verifier')?.length===43);assert(values.get('redirect_uri')===origin+'/gmail/callback');
        return Response.json({access_token:'access',refresh_token:'refresh-secret',scope});
      }
      assert(values.get('grant_type')==='refresh_token' && values.get('refresh_token')==='refresh-secret');
      return Response.json({access_token:'access',scope});
    }
    if(url==='https://gmail.googleapis.com/gmail/v1/users/me/profile')return Response.json({emailAddress:profile});
    if(url.startsWith('https://gmail.googleapis.com/gmail/v1/users/me/messages/')&&url.includes('/attachments/')){
      assert(quarantineEnabled&&init?.method==='GET'&&url.includes('/msgthread1/attachments/test-attachment'));
      binaryReads++;const raw='%PDF-'+ 'x'.repeat(1019);
      return Response.json({size:1024,data:btoa(raw).replace(/\+/g,'-').replace(/\//g,'_')});
    }
    if(url.startsWith('https://gmail.googleapis.com/gmail/v1/users/me/messages/')){
      assert(init?.method==='GET'&&!url.includes('/attachments/'));const id=new URL(url).pathname.split('/').pop();
      return Response.json({id,payload:{mimeType:'text/plain',headers:[{name:'Subject',value:changed?'Solicitud modificada':'Solicitud de cotización'},{name:'From',value:'client@example.test'}],body:{data:btoa('Solicitamos cotizar el servicio')}}});
    }
    if(url.startsWith('https://gmail.googleapis.com/gmail/v1/users/me/threads')){
      assert(init?.method==='GET');
      const u=new URL(url);threadReads++;
      if(u.pathname.endsWith('/threads'))return Response.json(u.searchParams.has('pageToken')?{threads:[{id:'thread2'}]}:{threads:[{id:'thread1'}],nextPageToken:'opaque-page'});
      const id=u.pathname.split('/').pop();
      if(u.searchParams.get('fields')?.includes('partId')){
        assert(!u.searchParams.get('fields')?.includes('data')&&id==='thread1');
        if(revokeDuringRead)owners.delete('owner');
        if(disconnectDuringRead&&row)row.status='disconnected';
        return Response.json({id,messages:[{id:'msgthread1',threadId:wrongThread?'another':id,internalDate:String(received),labelIds:['INBOX'],payload:{headers:[{name:'From',value:'client@example.test'}],mimeType:'multipart/mixed',parts:[{partId:'0',filename:'test.pdf',mimeType:'application/pdf',body:{size:1024,attachmentId:'test-attachment'}}]}}]});
      }
      return Response.json({id,messages:[{id:'msg'+id,internalDate:String(received),labelIds:['INBOX'],snippet:'Solicitamos cotizar',payload:{headers:[{name:'Subject',value:changed?'Solicitud modificada':'Solicitud de cotización'},{name:'From',value:'client@example.test'}]}}]});
    }
    if(url==='https://oauth2.googleapis.com/revoke'){revokeCount++;assert(values.get('token')==='refresh-secret');return new Response('',{status:200});}
    throw new Error('Unexpected outbound request');
  };
  const handler=createHandler({authenticate:async req=>{const id=req.headers.get('Authorization')?.replace('Bearer ','');if(!id)throw new Error('Unauthorized');return {id};},service:()=>({from:(name:string)=>new Query(name),storage:{from:(bucket:string)=>({upload:(path:string,blob:Blob,options:Row)=>{
      assert(bucket==='romax-request-attachments'&&path==='quarantine/'+organization+'/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/'+attachmentId+'/'+attemptId);
      assert(blob.size===1024&&options.upsert===false);uploads++;return Promise.resolve({error:storageFailure?{message:'synthetic'}:null});
    }})},rpc:(name:string,args:Row)=>{
    if(name==='romax_claim_attachment_downloads'){
      assert(args.p_actor==='owner'&&args.p_org===organization&&args.p_connection_at===row?.connected_at);
      assert(JSON.stringify(args.p_ids)===JSON.stringify([attachmentId]));
      if(quarantineDone)return Promise.resolve({data:{claims:[],skipped:1},error:null});
      return Promise.resolve({data:{claims:[{id:attachmentId,attempt:attemptId,path:'quarantine/'+organization+'/'+args.p_opportunity+'/'+attachmentId+'/'+attemptId,thread:'thread1',message:'msgthread1',locator:'test-attachment',filename:'test.pdf',mime:'application/pdf',size:1024}],skipped:0},error:null});
    }
    if(name==='romax_finish_attachment_download'){
      assert(args.p_actor==='owner'&&args.p_attempt===attemptId&&args.p_attachment===attachmentId);
      if(args.p_error===null){assert(typeof args.p_hash==='string'&&args.p_hash.length===64&&args.p_size===1024);quarantineDone=true;return Promise.resolve({data:{status:'quarantined'},error:null});}
      assert(args.p_hash===null&&args.p_size===null);return Promise.resolve({data:{status:'failed'},error:null});
    }
    if(name==='romax_register_gmail_attachment_metadata'){
      assert(args.p_org===organization&&args.p_actor==='owner'&&args.p_thread==='thread1'&&args.p_connection_at===row?.connected_at);
      const items=args.p_items as Row[];assert(items.length===1&&items[0].message_id==='msgthread1'&&items[0].locator==='test-attachment');
      rpcCalls++;const registered=discoveryWrites++===0?1:0;return Promise.resolve({data:{registered,unchanged:1-registered},error:null});
    }
    if(name==='romax_find_request_review_receipt'){
      if(!reviewReceipt||args.p_actor!==reviewReceipt.args.p_actor||args.p_request!==reviewReceipt.args.p_request||args.p_opportunity!==reviewReceipt.args.p_opportunity)return Promise.resolve({data:null,error:null});
      if(args.p_expected!==reviewReceipt.args.p_expected||JSON.stringify(args.p_snapshot)!==JSON.stringify(reviewReceipt.args.p_snapshot))return Promise.resolve({data:null,error:{code:'22023'}});
      return Promise.resolve({data:reviewReceipt.result,error:null});
    }
    if(name==='romax_save_request_review_verified'){
      assert(args.p_org===organization&&args.p_actor==='owner');
      const proof=args.p_verified as {fields:Record<string,{value:string;message_id:string}>};
      assert(proof.fields.title?.value==='Solicitud de cotización'&&proof.fields.title?.message_id==='msgthread1');
      rpcCalls++;reviewReceipt={args,result:{outcome:'saved',revision:1}};return Promise.resolve({data:reviewReceipt.result,error:null});
    }
    assert(name==='romax_confirm_gmail_import'&&args.p_org===organization&&args.p_actor==='owner'&&args.p_thread==='thread2'&&args.p_subject==='Solicitud de cotización');rpcCalls++;return Promise.resolve({data:{outcome:'imported',opportunity_id:'synthetic'},error:null});}}) as never,request,readEnv:name=>variables[name]??''},allowedActions);
  const call=async(action:string,extra:Row={},user='owner',requestOrigin=origin)=>{
    const response=await handler(new Request(origin+'/function',{method:'POST',headers:{Origin:requestOrigin,Authorization:user?'Bearer '+user:'','Content-Type':'application/json'},body:JSON.stringify({action,organization_id:organization,...extra})}));
    return {code:response.status,body:await response.json()};
  };
  return {call,get uploads(){return uploads;},get binaryReads(){return binaryReads;},storageFailure:()=>{storageFailure=true;},wrongThread:()=>{wrongThread=true;},revokeDuringRead:()=>{revokeDuringRead=true;},disconnectDuringRead:()=>{disconnectDuringRead=true;},get rpcCalls(){return rpcCalls;},change:()=>{changed=true;},get row(){return row;},get exchanges(){return exchangeCount;},get revokes(){return revokeCount;},get threadReads(){return threadReads;},setProfile:(v:string)=>{profile=v;},setScope:(v:string)=>{scope=v;},expire:()=>{if(row)row.attempt_expires_at=new Date(Date.now()-1000).toISOString();},deactivate:(v:string)=>owners.delete(v)};
}
Deno.test('rejects missing authentication, wrong origin, tenant and non-owner',async()=>{
  const f=fixture();
  assert((await f.call('start',{},'')).code===401);
  assert((await f.call('start',{},'owner','https://evil.test')).code===403);
  assert((await f.call('start',{organization_id:'wrong'})).code===403);
  assert((await f.call('start',{},'outsider')).code===403);
  assert(f.row===null && f.exchanges===0);
});
Deno.test('OAuth attempt is scoped, expires, bound to owner and consumed once',async()=>{
  const f=fixture();
  const start=await f.call('start');assert(start.code===200);
  const url=new URL(start.body.authorization_url);
  assert(url.origin==='https://accounts.google.com' && url.searchParams.get('scope')===READ_SCOPE && url.searchParams.get('code_challenge_method')==='S256');
  assert(f.row?.attempt_hash!==start.body.state && !JSON.stringify(f.row).includes(start.body.state));
  assert((await f.call('complete',{state:start.body.state,code:'code'},'owner2')).code===409);
  assert((await f.call('complete',{state:'a'.repeat(43),code:'code'})).code===409);
  f.expire();assert((await f.call('complete',{state:start.body.state,code:'code'})).code===409);
  assert(f.exchanges===0);
  const second=await f.call('start');assert(second.code===200);
  const responses=await Promise.all([f.call('complete',{state:second.body.state,code:'code'}),f.call('complete',{state:second.body.state,code:'code'})]);
  assert(responses.filter(r=>r.code===200).length===1 && responses.filter(r=>r.code===409).length===1);
  assert(f.exchanges===1 && f.row?.status==='connected' && f.row.attempt_hash===null);
  assert(!JSON.stringify(f.row).includes('refresh-secret'));
  const status=await f.call('status');assert(status.body.mailbox===mailbox && !JSON.stringify(status).includes('refresh'));
  assert((await f.call('verify')).body.verified===true);
  assert((await f.call('disconnect')).body.status==='disconnected' && f.revokes===1 && f.row?.refresh_ciphertext===null);
  assert((await f.call('verify')).code===409);
});
Deno.test('wrong mailbox, excess scope and deactivated owner cannot connect',async()=>{
  const f=fixture();
  let start=await f.call('start');f.setProfile('other@example.test');
  assert((await f.call('complete',{state:start.body.state,code:'code'})).code===403 && f.row?.status==='disconnected');
  f.setProfile(mailbox);f.setScope(READ_SCOPE+' https://www.googleapis.com/auth/gmail.modify');
  start=await f.call('start');
  assert((await f.call('complete',{state:start.body.state,code:'code'})).code===409 && f.row?.status==='disconnected');
  f.setScope(READ_SCOPE);start=await f.call('start');f.deactivate('owner');
  assert((await f.call('complete',{state:start.body.state,code:'code'})).code===403 && f.row?.refresh_ciphertext===null);
});

Deno.test('preview is read-only, tenant-bound, paginated and requires live connection',async()=>{
  const f=fixture();
  assert((await f.call('preview')).code===409&&f.threadReads===0);
  assert((await f.call('preview',{},'outsider')).code===403&&f.threadReads===0);
  const start=await f.call('start');
  assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
  const before=JSON.stringify(f.row);
  const p=await f.call('preview');
  assert(p.code===200&&p.body.candidates.length===1&&p.body.candidates[0].existing_status==='in_analysis'&&p.body.candidates[0].import_policy==='link_existing');
  assert(p.body.next_cursor&&!p.body.next_cursor.includes('opaque-page'));
  assert(JSON.stringify(f.row)===before,'preview must not mutate connection');
  const reads=f.threadReads;
  assert((await f.call('preview',{cursor:p.body.next_cursor},'owner2')).code===400);
  assert((await f.call('preview',{cursor:'invalid'})).code===400&&f.threadReads===reads);
  const next=await f.call('preview',{cursor:p.body.next_cursor});
  assert(next.code===200&&next.body.candidates[0].thread_id==='thread2'&&next.body.candidates[0].existing_status===null&&next.body.candidates[0].import_policy==='new_candidate');
  assert(next.body.window_start===p.body.window_start&&next.body.window_end===p.body.window_end&&!next.body.next_cursor);
  assert(JSON.stringify(f.row)===before);
  await f.call('disconnect');assert((await f.call('preview',{cursor:p.body.next_cursor})).code===409);
});

Deno.test('QA handler permits only status and preview; all OAuth lifecycle actions are denied',async()=>{
  const f=fixture(new Set(['status','preview']));
  assert((await f.call('status')).code===200);
  assert((await f.call('preview')).code===409 && f.threadReads===0);
  for (const action of ['start','complete','verify','disconnect']) assert((await f.call(action,{state:'a'.repeat(43),code:'code'})).code===403, action+' must be denied');
  assert(f.row===null && f.exchanges===0 && f.revokes===0 && f.threadReads===0,'QA actions must not write or contact Google');
});

Deno.test('import gate, encrypted confirmation, server reread and owner binding',async()=>{
  const off=fixture();
  assert((await off.call('confirm_import',{confirmed:true,confirmation_token:'forged'})).code===403);
  const f=fixture(undefined,true);
  const start=await f.call('start');assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
  const p=await f.call('preview');assert(p.body.candidates[0].confirmation_token===null);
  const next=await f.call('preview',{cursor:p.body.next_cursor});const token=next.body.candidates[0].confirmation_token;
  assert(typeof token==='string'&&token.startsWith('v1.')&&!token.includes('thread2'));
  assert((await f.call('confirm_import',{confirmed:false,confirmation_token:token})).code===409);
  assert((await f.call('confirm_import',{confirmed:true,confirmation_token:token},'owner2')).code===409);
  assert((await f.call('confirm_import',{confirmed:true,confirmation_token:'forged'})).code===409);
  assert(f.rpcCalls===0);
  const result=await f.call('confirm_import',{confirmed:true,confirmation_token:token,subject:'untrusted'});
  assert(result.code===200&&result.body.outcome==='imported'&&f.rpcCalls===1);
  f.change();
  assert((await f.call('confirm_import',{confirmed:true,confirmation_token:token})).code===409&&f.rpcCalls===1);
  f.deactivate('owner');
  assert((await f.call('confirm_import',{confirmed:true,confirmation_token:token})).code===403);
});

Deno.test('enrichment: directed old thread, owner only, no write or technical IDs',async()=>{
 const f=fixture(undefined,false,true,true);
 const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 assert((await f.call('enrichment_preview',{opportunity_id:id})).code===409);
 const start=await f.call('start');assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
 const before=JSON.stringify(f.row),reads=f.threadReads;
 assert((await f.call('enrichment_preview',{opportunity_id:id},'outsider')).code===403);
 assert((await f.call('enrichment_preview',{opportunity_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'})).code===404);
 assert(f.threadReads===reads);
 const response=await f.call('enrichment_preview',{opportunity_id:id,thread_id:'attacker'});
 assert(response.code===200&&response.body.enrichment.subject==='Solicitud de cotización'&&typeof response.body.enrichment.proof==='string');
 assert(f.threadReads===reads+1&&f.rpcCalls===0&&JSON.stringify(f.row)===before);
 assert(!JSON.stringify(response.body).includes('thread1')&&!JSON.stringify(response.body).includes('msgthread1'));
 assert((await f.call('save_enrichment',{confirmed:true,opportunity_id:id,request_id:id,expected_revision:0,snapshot:{},proof:response.body.enrichment.proof},'owner2')).code===409);
 assert((await fixture().call('enrichment_preview',{opportunity_id:id})).code===403);
});

Deno.test('SEC12: confirmed Edge save, lost-response recovery after expiry/disconnect, changed payload and actor denied',async()=>{
 const f=fixture(undefined,false,true,true),id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',requestId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
 const start=await f.call('start');assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
 const p=await f.call('enrichment_preview',{opportunity_id:id});assert(p.code===200);
 const proof=p.body.enrichment.proof;
 const snapshot={title:'Solicitud de cotización',provenance:{title:{source:'gmail_reviewed',evidence:'Solicitud de cotización'}}};
 const args={confirmed:true,opportunity_id:id,request_id:requestId,expected_revision:0,snapshot,proof};
 const ctx=organization+':enrichment:owner:'+f.row?.connected_at+':'+origin+':'+id;
 const k=await importKey(btoa('k'.repeat(32))),decoded=JSON.parse(await unseal(k,proof,ctx));
 const expired=await seal(k,JSON.stringify({...decoded,expires:Date.now()-1}),ctx);
 assert((await f.call('save_enrichment',{...args,confirmed:false})).code===400);
 assert((await f.call('save_enrichment',{...args,proof:expired})).code===409&&f.rpcCalls===0);
 const saved=await f.call('save_enrichment',args);assert(saved.code===200&&saved.body.review.revision===1&&f.rpcCalls===1);
 const recovered=await f.call('save_enrichment',{...args,proof:expired});assert(recovered.code===200&&recovered.body.recovered===true&&f.rpcCalls===1);
 assert((await f.call('save_enrichment',{...args,snapshot:{...snapshot,title:'changed'}})).code===409&&f.rpcCalls===1);
 assert((await f.call('save_enrichment',args,'owner2')).code===409&&f.rpcCalls===1);
 assert((await f.call('disconnect')).code===200);
 assert((await f.call('save_enrichment',{...args,proof:expired})).body.recovered===true&&f.rpcCalls===1);
 f.deactivate('owner');assert((await f.call('save_enrichment',args)).code===403);
});

Deno.test('4B: explicit discovery disabled by default, denied actors and browser supplied IDs never read Gmail',async()=>{
 const off=fixture(),id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',args={opportunity_id:id,confirmed:true};
 assert((await off.call('discover_attachments',args)).code===403&&off.threadReads===0);
 const f=fixture(undefined,false,false,true,true);
 assert((await f.call('discover_attachments',args,'outsider')).code===403);
 assert((await f.call('discover_attachments',{...args,thread_id:'evil'})).code===400);
 assert((await f.call('discover_attachments',{...args,confirmed:false})).code===400);
 assert((await f.call('discover_attachments',args)).code===409&&f.threadReads===0);
 const start=await f.call('start');assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
 assert((await f.call('discover_attachments',{...args,opportunity_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'})).code===404);
 assert(f.threadReads===0&&f.rpcCalls===0);
});
Deno.test('4B: old stored thread only, metadata RPC and idempotent rescan, no raw IDs returned',async()=>{
 const f=fixture(undefined,false,false,true,true),args={opportunity_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',confirmed:true};
 const start=await f.call('start');assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
 const a=await f.call('discover_attachments',args);assert(a.code===200&&a.body.discovery.registered===1&&a.body.discovery.detected===1);
 const b=await f.call('discover_attachments',args);assert(b.code===200&&b.body.discovery.unchanged===1&&f.rpcCalls===2);
 assert(!JSON.stringify(a.body).includes('test-attachment')&&!JSON.stringify(a.body).includes('msgthread1')&&!JSON.stringify(a.body).includes('test.pdf'));
 assert(f.threadReads===2);
});
Deno.test('4B: remote thread mismatch, revoked owner and disconnected mailbox never register',async()=>{
 const args={opportunity_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',confirmed:true};
 for(const mode of ['wrongThread','revokeDuringRead','disconnectDuringRead'] as const){
  const f=fixture(undefined,false,false,false,true);
  const start=await f.call('start');assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
  f[mode]();const r=await f.call('discover_attachments',args);
  assert(r.code===(mode==='revokeDuringRead'?403:409)&&f.rpcCalls===0);
 }
});

Deno.test('4C.1 quarantine disabled by default and explicit selection required',async()=>{
 const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',doc='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
 const args={opportunity_id:id,attachment_ids:[doc],confirmed:true};
 assert((await fixture().call('quarantine_attachments',args)).code===403);
 const f=fixture(undefined,false,false,false,false,true);
 assert((await f.call('quarantine_attachments',{...args,attachment_ids:[doc,doc]})).code===400);
 assert((await f.call('quarantine_attachments',{...args,locator:'forged'})).code===400);
 assert((await f.call('quarantine_attachments',args,'outsider')).code===403);
 assert(f.binaryReads===0&&f.uploads===0);
});
Deno.test('4C.1 authorized selected binary quarantined, no release or path, replay does not download',async()=>{
 const f=fixture(undefined,false,false,false,false,true),args={opportunity_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',attachment_ids:['cccccccc-cccc-4ccc-8ccc-cccccccccccc'],confirmed:true};
 const start=await f.call('start');assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
 const q=await f.call('quarantine_attachments',args);
 assert(q.code===200&&q.body.quarantine.results[0].status==='quarantined'&&q.body.quarantine.available===0&&q.body.quarantine.scan_required);
 assert(!JSON.stringify(q.body).includes('test-attachment')&&!JSON.stringify(q.body).includes('dddddddd')&&!JSON.stringify(q.body).includes('quarantine/'));
 const retry=await f.call('quarantine_attachments',args);assert(retry.code===200&&retry.body.quarantine.skipped===1&&f.binaryReads===1&&f.uploads===1);
});
Deno.test('4C.1 remote mismatch never downloads; storage failure never releases',async()=>{
 const args={opportunity_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',attachment_ids:['cccccccc-cccc-4ccc-8ccc-cccccccccccc'],confirmed:true};
 for(const mode of ['wrongThread','storageFailure'] as const){
  const f=fixture(undefined,false,false,false,false,true);
  const start=await f.call('start');assert((await f.call('complete',{state:start.body.state,code:'code'})).code===200);
  f[mode]();const q=await f.call('quarantine_attachments',args);assert(q.code===200&&q.body.quarantine.results[0].status==='failed'&&q.body.quarantine.available===0);
  assert(mode==='wrongThread'?f.binaryReads===0&&f.uploads===0:f.binaryReads===1&&f.uploads===1);
 }
});
