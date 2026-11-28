import { fetchQuarantineBytes, matchesClaim, type Claim } from './quarantine.ts';
function assert(v:unknown,label='Assertion failed'){if(!v)throw new Error(label);}
const raw='%PDF-1.7\nsynthetic\n%%EOF';
const c:Claim={id:'id',attempt:'attempt',path:'private',thread:'thread',message:'msg',locator:'attachment',filename:'test.pdf',mime:'application/pdf',size:raw.length};
const encode=(x:string)=>btoa(x).replace(/\+/g,'-').replace(/\//g,'_');
const fake=(data:unknown):typeof fetch=>async(input,init)=>{
 const u=new URL(String(input));assert(u.origin==='https://gmail.googleapis.com'&&u.pathname==='/gmail/v1/users/me/messages/msg/attachments/attachment'&&u.searchParams.get('fields')==='size,data'&&init?.method==='GET'&&init.redirect==='error');
 return Response.json(data);
};
async function reject(data:unknown,claim=c){let failed=false;try{await fetchQuarantineBytes(fake(data),'mock',claim,AbortSignal.timeout(5000));}catch{failed=true;}assert(failed);}
Deno.test('4C.1 external selected bytes exact length and SHA-256',async()=>{
 const x=await fetchQuarantineBytes(fake({size:raw.length,data:encode(raw)}),'mock',c,AbortSignal.timeout(5000));
 assert(new TextDecoder().decode(x.bytes)===raw&&/^[a-f0-9]{64}$/.test(x.hash));
 const y=await fetchQuarantineBytes(fake({size:raw.length,data:encode(raw).replace(/=+$/,'')}),'mock',c,AbortSignal.timeout(5000));assert(x.hash===y.hash);
});
Deno.test('4C.1 rejects forged size, invalid base64 and wrong format',async()=>{
 await reject({size:raw.length+1,data:encode(raw)});
 await reject({size:raw.length,data:'%%%invalid'});
 await reject({size:raw.length,data:encode('x'.repeat(raw.length))});
 await reject({size:raw.length,data:encode(raw)},{...c,mime:'text/html'});
 await reject({size:raw.length,data:encode(raw)},{...c,size:10485761});
});
Deno.test('4C.1 revalidate metadata identity before transport',()=>{
 const item={message_id:'msg',locator:'attachment',locator_kind:'attachment_id' as const,filename:c.filename,mime_type:c.mime,size_bytes:c.size,received_at:'2026-01-01T00:00:00Z',direction:'incoming' as const};
 assert(matchesClaim(c,[item])&&!matchesClaim(c,[{...item,message_id:'another'}])&&!matchesClaim(c,[{...item,size_bytes:1}])&&!matchesClaim(c,[{...item,locator_kind:'mime_part'}]));
});
