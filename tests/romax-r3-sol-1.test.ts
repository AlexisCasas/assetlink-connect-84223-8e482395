import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {collectPages,canViewRequests,createListMemory,dateInLima,dateLabel,emptyFilters,filterRows,isOpportunityId,linkedLabel,metrics,paginate,type Opportunity,type Client,type Site} from '../src/components/provider/romaxRequestList.ts';
const row=(n:number,patch:Partial<Opportunity>={}):Opportunity=>({id:'id-'+n,status:'new',classification:'quote_request',classification_confidence:null,classification_reason:null,commercial_client_id:null,commercial_site_id:null,commercial_contact_id:null,match_status:'unmatched',subject:'Solicitud '+n,sender_email:'sender@example.test',received_at:'2026-11-28T05:00:00Z',snippet:null,source_system:'gmail',created_at:'2026-11-28T05:01:00Z',updated_at:'2026-11-28T05:01:00Z',...patch});
const clients:Client[]=[{id:'c',business_name:'Compañía Ejemplo',is_active:true},{id:'inactive',business_name:'Inactivo',is_active:false}];
const sites:Site[]=[{id:'s',commercial_client_id:'c',site_name:'Sede Norte',is_active:true}];
const rows=[row(1,{subject:'Instalación eléctrica',snippet:'Acometidas',commercial_client_id:'c',commercial_site_id:'s',match_status:'confirmed'}),row(2,{status:'in_analysis',source_system:'manual',received_at:null,classification:'follow_up'}),row(3,{status:'quoted',received_at:'2026-11-29T04:59:59Z'}),row(4,{status:'discarded',received_at:'2026-11-29T05:00:00Z'})];
test('S01/S02: metrics count entire authorized dataset, dimensions separate',()=>{
  const data=Array.from({length:63},(_,i)=>row(i,{status:i===62?'quoted':'new'}));assert.equal(metrics(data).new,62);assert.equal(metrics(data).quoted,1);assert.equal(metrics(data).unmatched,63);assert.equal(paginate(data,1,15).rows.length,15);
});
test('S03: search subject, snippet, sender, client, site, accents and combined filters',()=>{
  for(const search of ['instalacion electrica','acometidas','compania ejemplo','sede norte'])assert.deepEqual(filterRows(rows,{...emptyFilters,search},clients,sites).map(r=>r.id),['id-1']);
  assert.equal(filterRows(rows,{...emptyFilters,search:'sender@example.test'},clients,sites).length,4);
  assert.deepEqual(filterRows(rows,{...emptyFilters,status:'in_analysis',source:'manual',classification:'follow_up',client:'none'},clients,sites).map(r=>r.id),['id-2']);
  assert.deepEqual(filterRows(rows,{...emptyFilters,client:'c',match:'confirmed'},clients,sites).map(r=>r.id),['id-1']);
});
test('S04: Lima dates inclusive and missing receipt not fabricated',()=>{
  assert.equal(dateInLima('2026-11-28T04:59:59Z'),'2026-11-27');assert.equal(dateInLima('2026-11-28T05:00:00Z'),'2026-11-28');assert.equal(dateLabel(null),'No informada');
  assert.deepEqual(filterRows(rows,{...emptyFilters,from:'2026-11-28',to:'2026-11-28'},clients,sites).map(r=>r.id),['id-1','id-3']);assert.equal(filterRows(rows,{...emptyFilters,from:'2026-11-29',to:'2026-11-28'},clients,sites).length,0);
});
test('S05/S06: pages clamp and empty is not a false page',()=>{const all=Array.from({length:31},(_,i)=>row(i));assert.equal(paginate(all,3,15).rows[0].id,'id-30');assert.deepEqual(paginate([],3,15),{rows:[],page:1,pageCount:1,total:0,start:0,end:0});assert.equal(paginate(all,9,15).page,3);});
test('S02/S05: exact scan crosses API row cap and counts all pages',async()=>{
  const all=Array.from({length:1203},(_,i)=>row(i));const calls:number[]=[];
  const output=await collectPages((from,to)=>{calls.push(from);return Promise.resolve({data:all.slice(from,Math.min(to+1,from+73)),count:all.length,error:null});},new AbortController().signal);
  assert.equal(output.length,1203);assert.equal(new Set(output.map(x=>x.id)).size,1203);assert.ok(calls.length>16);
});
test('S07: changing counts, duplicate rows, missing counts and partial pages fail closed',async()=>{
  const s=new AbortController().signal;
  await assert.rejects(collectPages(()=>Promise.resolve({data:[row(1)],count:null,error:null}),s));
  await assert.rejects(collectPages(()=>Promise.resolve({data:[],count:2,error:null}),s));
  await assert.rejects(collectPages(()=>Promise.resolve({data:[row(1)],count:2,error:null}),s));
  await assert.rejects(collectPages((from)=>Promise.resolve({data:[row(from)],count:from?3:2,error:null}),s));
  await assert.rejects(collectPages(()=>Promise.resolve({data:null,count:null,error:{message:'denied'}}),s));
});
test('S09: distinguish missing link, inactive master and unavailable link',()=>{
  const label=(id:string|null)=>linkedLabel(id,clients,x=>x.id,x=>x.business_name+(x.is_active?'':' (inactivo)'));
  assert.equal(label(null),'Sin vincular');assert.equal(label('missing'),'Vínculo no disponible');assert.equal(label('inactive'),'Inactivo (inactivo)');
});
test('S11/S12: validate UUID without accepting arbitrary hash text',()=>{
  assert.equal(isOpportunityId('a0000000-0000-4000-8000-000000000001'),true);for(const id of [undefined,'bad','https://example.test','id-1',''])assert.equal(isOpportunityId(id),false);
});
test('S13: UI role/tenant gate does not grant viewer or outsider',()=>{
  for(const role of ['owner','admin','manager','quote_manager'])assert.equal(canViewRequests('provider_company',true,'org','org',role),true);
  for(const role of ['viewer','technician',undefined])assert.equal(canViewRequests('provider_company',true,'org','org',role),false);
  assert.equal(canViewRequests('provider_company',false,'org','org','owner'),false);assert.equal(canViewRequests('provider_company',true,'org','other','owner'),false);assert.equal(canViewRequests('client_company',true,'org','org','owner'),false);
});
test('S14: an aborted old-tenant query cannot complete and preference objects are isolated',async()=>{
  const ctrl=new AbortController();const pending=collectPages(()=>{ctrl.abort();return Promise.resolve({data:[row(1)],count:1,error:null});},ctrl.signal);
  await assert.rejects(pending);const a=createListMemory(),b=createListMemory();a.filters.search='private search';a.page=3;assert.equal(b.filters.search,'');assert.equal(b.page,1);
});
test('S08/S10/S15/S16/S19/S20/S23: source contract guards (browser QA remains separate)',()=>{
  const root='src/components/provider/';const view=readFileSync(root+'OpportunitiesView.tsx','utf8'),detail=readFileSync(root+'RequestDetail.tsx','utf8'),gmail=readFileSync(root+'GmailConnectionPanel.tsx','utf8'),dash=readFileSync('src/pages/Dashboard.tsx','utf8'),analysis=readFileSync(root+'OpportunityAnalysisView.tsx','utf8');
  assert.match(view,/eq\('organization_id',organizationId\)/);assert.match(view,/abortSignal\(signal\)/);assert.match(view,/key=\{user.id\+':'\+organizationId/);
  assert.match(view,/source_system:'manual'/);assert.equal((view.match(/\.insert\(/g)||[]).length,1);assert.doesNotMatch(view,/\.rpc\(|\.update\(|\.delete\(/);
  assert.match(view,/useState\('registered'\)/);assert.match(view,/gmailAllowed=\{currentMembership\?\.role==='owner'/);assert.match(view,/memory.filters=\{\.\.\.filters\}/);
  assert.match(detail,/Extracto almacenado/);assert.match(detail,/No hay documentos registrados/);assert.doesNotMatch(detail,/source_thread_id|confirmation_token|storage_path|service_role/);
  assert.match(gmail,/onOpenOpportunity\(c.existing_opportunity_id!/);assert.match(gmail,/confirmed:true,confirmation_token:/);
  assert.match(dash,/focusOpportunityId=\{focus.opportunityId\}/);assert.match(analysis,/navigateToEntity\(\{ view: 'opportunities', opportunityId \}\)/);
});
