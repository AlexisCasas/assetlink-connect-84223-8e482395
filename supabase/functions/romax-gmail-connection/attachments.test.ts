import { discoverAttachments, registryPayload, currentDownloadLocator, type RegistryRow } from './attachments.ts';
function assert(x:unknown,label='Assertion failed'){if(!x)throw new Error(label);}
const date='1760000000000',thread='thread-1',mailbox='pilot@example.test';
const file=(partId='0',filename='TDR.pdf',attachmentId='attachment-1',size=1024)=>({partId,filename,mimeType:'application/pdf',body:{attachmentId,size}});
const msg=(id:string,parts:unknown[],labels:string[]=['INBOX'],from='client@example.test')=>({id,threadId:thread,internalDate:date,labelIds:labels,payload:{mimeType:'multipart/mixed',headers:[{name:'From',value:from}],parts}});
const request=(data:unknown):typeof fetch=>async(input,init)=>{
 const url=new URL(String(input)),fields=url.searchParams.get('fields')??'';
 assert(url.origin==='https://gmail.googleapis.com'&&url.pathname==='/gmail/v1/users/me/threads/'+thread);
 assert(init?.method==='GET'&&init.redirect==='error'&&fields.includes('body(size,attachmentId)')&&!fields.includes('data')&&!fields.includes('snippet'));
 return Response.json(data);
};
const discover=(messages:unknown[])=>discoverAttachments(request({id:thread,messages}),'synthetic',thread,mailbox);
async function rejects(fn:()=>Promise<unknown>){let rejected=false;try{await fn();}catch{rejected=true;}assert(rejected,'Expected rejection');}
Deno.test('4B metadata mask, nested MIME and equal filenames preserve distinct identity',async()=>{
 const r=await discover([msg('m1',[file(),{mimeType:'multipart/mixed',parts:[file('1.0','TDR.pdf','attachment-2')]}]),msg('m2',[file()])]);
 assert(r.items.length===3&&!r.partial&&r.items.every(x=>x.filename==='TDR.pdf'&&x.direction==='incoming'));
 assert(r.items.some(x=>x.message_id==='m2'));
});
Deno.test('4B inline signature, CID and link-only messages are not downloadable documents',async()=>{
 const r=await discover([msg('m1',[{...file(),headers:[{name:'Content-Disposition',value:'inline'}]},{...file('1','signature.png','a2'),mimeType:'image/png',headers:[{name:'Content-ID',value:'cid'}]},file('2','TDR.pdf','a3'),{mimeType:'text/html',body:{size:100}}])]);
 assert(r.items.length===1&&r.skipped_inline===2&&r.items[0].locator==='a3');
});
Deno.test('4B outgoing alias/SENT distinct from incoming; trash spam draft excluded',async()=>{
 const r=await discover([msg('m1',[file()],['SENT']),msg('m2',[file()],['INBOX'],'ventas@romaxfm.com'),msg('m3',[file()]),msg('m4',[file()],['TRASH']),msg('m5',[file()],['SPAM']),msg('m6',[file()],['DRAFT'])]);
 assert(r.items.length===3&&r.excluded_messages===3&&r.items.filter(x=>x.direction==='outgoing').length===2);
});
Deno.test('4B stable inline MIME part, unsafe controls/path skipped and unsupported MIME retained for SQL screening',async()=>{
 const r=await discover([msg('m1',[{partId:'1.2',filename:'real.txt',mimeType:'text/plain',body:{size:12}},{...file('3','bad\u202E.pdf','bad')},file('4','../file.pdf','bad2'),{...file('5','unsafe.exe','exe'),mimeType:'application/octet-stream'}])]);
 assert(r.items.length===2&&r.partial&&r.skipped_unsafe===2);
 assert(r.items.some(x=>x.locator_kind==='mime_part'&&x.locator==='1.2')&&r.items.some(x=>x.filename==='unsafe.exe'));
});
Deno.test('4B remote identity mismatch and conflicting duplicate parts fail closed',async()=>{
 await rejects(()=>discover([{...msg('m1',[file()]),threadId:'foreign'}]));
 await rejects(()=>discover([msg('m1',[file()]),msg('m1',[file()])]));
 await rejects(()=>discover([msg('m1',[file(),file('1','other.pdf')])]));
 await rejects(()=>discoverAttachments(request({id:'foreign',messages:[]}),'synthetic',thread,mailbox));
});
Deno.test('4B exact duplicate metadata and empty thread',async()=>{
 const r=await discover([msg('m1',[file(),file()])]);assert(r.items.length===1&&!r.partial);
 const e=await discover([]);assert(e.items.length===0&&!e.partial);
});
Deno.test('4B message and attachment caps return explicit partial',async()=>{
 const many=await discover(Array.from({length:81},(_,i)=>msg('m'+i,[])));
 assert(many.scanned_messages===80&&many.partial&&many.reasons.includes('message_limit'));
 const parts=await discover([msg('m1',Array.from({length:51},(_,i)=>file(String(i),'TDR.pdf','a'+i)))]);
 assert(parts.items.length===50&&parts.partial&&parts.reasons.includes('attachment_limit'));
 const exact=await discover([msg('m1',Array.from({length:50},(_,i)=>file(String(i),'TDR.pdf','a'+i)))]);
 assert(exact.items.length===50&&!exact.partial);
});
Deno.test('4B oversized body, invalid thread and HTTP failure reject without register',async()=>{
 await rejects(()=>discoverAttachments(request({id:thread,messages:[],padding:'x'.repeat(2*1024*1024)}),'synthetic',thread,mailbox));
 await rejects(()=>discoverAttachments(request({id:thread,messages:[]}),'synthetic','../wrong',mailbox));
 await rejects(()=>discoverAttachments(async()=>new Response('',{status:429}),'synthetic',thread,mailbox));
});
Deno.test('4B archived message without labels and unknown sender',async()=>{
 const m=msg('m1',[file()],[],'not-an-email');const {labelIds:_,...archived}=m;
 const r=await discover([archived]);assert(r.items.length===1&&r.items[0].direction==='unknown');
});

Deno.test('4F hotfix: stable part keys survive token rotation and distinguish identical filenames/size',async()=>{
 const a=await discover([msg('m1',[file('0','TDR.pdf','token-a'),file('1','TDR.pdf','token-b')])]);
 const b=await discover([msg('m1',[file('0','TDR.pdf','rotated-a'),file('1','TDR.pdf','rotated-b')])]);
 const rows=registryPayload(a.items,[],false);
 assert(rows.length===2&&rows[0].locator==='r4f_part_v1_0'&&rows[1].locator==='r4f_part_v1_1'&&!('part_id' in rows[0]));
 const existing:RegistryRow[]=rows.map(x=>({source_message_id:x.message_id,source_attachment_id:x.locator,source_locator_kind:x.locator_kind,filename:x.filename,mime_type:x.mime_type,size_bytes:x.size_bytes,source_received_at:x.received_at,source_direction:x.direction}));
 assert(JSON.stringify(rows)===JSON.stringify(registryPayload(b.items,existing,false)));
 const claim={message:'m1',locator:rows[1].locator,filename:'TDR.pdf',mime:'application/pdf',size:1024};
 assert(currentDownloadLocator(claim,b.items,existing,false)==='rotated-b');
 assert(currentDownloadLocator({...claim,message:'foreign'},b.items,existing,false)===null);
});
Deno.test('4F hotfix: legacy unique metadata preserves original registry key and resolves current token; ambiguity fails closed',async()=>{
 const b=await discover([msg('m1',[file('0','TDR.pdf','fresh')])]);
 const x=b.items[0];const legacy:RegistryRow={source_message_id:x.message_id,source_attachment_id:'old-token',source_locator_kind:x.locator_kind,filename:x.filename,mime_type:x.mime_type,size_bytes:x.size_bytes,source_received_at:x.received_at,source_direction:x.direction};
 const c={message:x.message_id,locator:legacy.source_attachment_id,filename:x.filename,mime:x.mime_type,size:1024};
 assert(registryPayload(b.items,[legacy],false)[0].locator==='old-token');
 assert(currentDownloadLocator(c,b.items,[legacy],false)==='fresh');
 assert(currentDownloadLocator(c,b.items,[legacy],true)===null);
 const amb=await discover([msg('m1',[file('0','TDR.pdf','fresh'),file('1','TDR.pdf','other')])]);
 assert(currentDownloadLocator(c,amb.items,[legacy],false)===null);
 await rejects(async()=>registryPayload(amb.items,[legacy],false));
 assert(currentDownloadLocator(c,b.items,[legacy,{...legacy,source_attachment_id:'another-old'}],false)===null);
});
