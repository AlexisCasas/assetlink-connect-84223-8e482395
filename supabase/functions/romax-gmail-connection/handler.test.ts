import { createHandler } from './handler.ts';
import { READ_SCOPE } from './crypto.ts';
const organization='11111111-1111-4111-8111-111111111111', origin='https://example.test', mailbox='pilot@example.test';
type Row=Record<string,unknown>;
function assert(value:unknown, label='Assertion failed') { if(!value) throw new Error(label); }
function fixture() {
  let row:Row|null=null, profile=mailbox, scope=READ_SCOPE, exchangeCount=0, revokeCount=0, threadReads=0;
  const owners=new Set(['owner','owner2']);
  const variables:Record<string,string>={ROMAX_GMAIL_ORGANIZATION_ID:organization,ROMAX_GMAIL_EXPECTED_EMAIL:mailbox,ROMAX_GMAIL_APP_ORIGIN:origin,ROMAX_GMAIL_CLIENT_ID:'synthetic-client',ROMAX_GMAIL_CLIENT_SECRET:'synthetic-secret',ROMAX_GMAIL_ENCRYPTION_KEY:btoa('k'.repeat(32))};
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
        const data=[{organization_id:organization,source_system:'gmail',source_thread_id:'thread1',status:'in_analysis'},{organization_id:'another',source_system:'gmail',source_thread_id:'thread2',status:'quoted'}].filter(r=>this.filters.every(f=>f(r)));
        return {data,error:null};
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
    if(url.startsWith('https://gmail.googleapis.com/gmail/v1/users/me/threads')){
      assert(init?.method==='GET');
      const u=new URL(url);threadReads++;
      if(u.pathname.endsWith('/threads'))return Response.json(u.searchParams.has('pageToken')?{threads:[{id:'thread2'}]}:{threads:[{id:'thread1'}],nextPageToken:'opaque-page'});
      const id=u.pathname.split('/').pop();
      return Response.json({id,messages:[{id:'msg'+id,internalDate:String(Date.now()-60000),labelIds:['INBOX'],snippet:'Solicitamos cotizar',payload:{headers:[{name:'Subject',value:'Solicitud de cotización'},{name:'From',value:'client@example.test'}]}}]});
    }
    if(url==='https://oauth2.googleapis.com/revoke'){revokeCount++;assert(values.get('token')==='refresh-secret');return new Response('',{status:200});}
    throw new Error('Unexpected outbound request');
  };
  const handler=createHandler({authenticate:async req=>{const id=req.headers.get('Authorization')?.replace('Bearer ','');if(!id)throw new Error('Unauthorized');return {id};},service:()=>({from:(name:string)=>new Query(name)}) as never,request,readEnv:name=>variables[name]??''});
  const call=async(action:string,extra:Row={},user='owner',requestOrigin=origin)=>{
    const response=await handler(new Request(origin+'/function',{method:'POST',headers:{Origin:requestOrigin,Authorization:user?'Bearer '+user:'','Content-Type':'application/json'},body:JSON.stringify({action,organization_id:organization,...extra})}));
    return {code:response.status,body:await response.json()};
  };
  return {call,get row(){return row;},get exchanges(){return exchangeCount;},get revokes(){return revokeCount;},get threadReads(){return threadReads;},setProfile:(v:string)=>{profile=v;},setScope:(v:string)=>{scope=v;},expire:()=>{if(row)row.attempt_expires_at=new Date(Date.now()-1000).toISOString();},deactivate:(v:string)=>owners.delete(v)};
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
  assert(p.code===200&&p.body.candidates.length===1&&p.body.candidates[0].existing_status==='in_analysis');
  assert(p.body.next_cursor&&!p.body.next_cursor.includes('opaque-page'));
  assert(JSON.stringify(f.row)===before,'preview must not mutate connection');
  const reads=f.threadReads;
  assert((await f.call('preview',{cursor:p.body.next_cursor},'owner2')).code===400);
  assert((await f.call('preview',{cursor:'invalid'})).code===400&&f.threadReads===reads);
  const next=await f.call('preview',{cursor:p.body.next_cursor});
  assert(next.code===200&&next.body.candidates[0].thread_id==='thread2'&&next.body.candidates[0].existing_status===null);
  assert(next.body.window_start===p.body.window_start&&next.body.window_end===p.body.window_end&&!next.body.next_cursor);
  assert(JSON.stringify(f.row)===before);
  await f.call('disconnect');assert((await f.call('preview',{cursor:p.body.next_cursor})).code===409);
});
