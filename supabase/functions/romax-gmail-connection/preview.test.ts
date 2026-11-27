import { classifyThread, readPreview, DAY_MS } from './preview.ts';
function assert(v:unknown,msg='assertion failed'){if(!v)throw Error(msg);}
const to=Date.parse('2026-11-27T20:00:00Z'),from=to-7*DAY_MS;
const msg=(id:string,subject:string,snippet:string,offset=1000,labels=['INBOX'],file='')=>({id,internalDate:String(from+offset),labelIds:labels,snippet,payload:{headers:[{name:'Subject',value:subject},{name:'From',value:'pilot@example.test'}],parts:file?[{filename:file,mimeType:'application/pdf'}]:[]}});
const classify=(messages:ReturnType<typeof msg>[])=>classifyThread({id:'thread1',messages},from,to);
Deno.test('new request and attachment names, seven-day boundary',()=>{
  const c=classify([msg('old','Anterior','SC-999999',-1),msg('new','Solicitud de cotización SC-123456','Solicitamos cotizar el servicio',1000,['INBOX'],'tdr.pdf'),msg('spam','Otro','SC-888888',2000,['SPAM'])]);
  assert(c?.category==='quote_request'&&c.reference==='SC-123456'&&c.message_count===1&&c.attachments[0].supported);
  assert(classify([msg('sent','Cotización','Adjuntamos cotización',1000,['SENT'])])===null);
});
Deno.test('follow-up, ambiguity, adjustment, quote response and operational',()=>{
  const first=msg('a','Solicitud de cotización SC-123456','Solicitamos cotizar');
  assert(classify([first,msg('b','RE: SC-123456','Ampliación de plazo hasta el 30/11',2000)])?.category==='follow_up');
  assert(classify([first,msg('b','SC-765432','Solicitamos cotizar',2000)])?.category==='review');
  assert(classify([first,msg('b','Reajuste','Mejora de precio',2000)])?.category==='adjustment');
  assert(classify([first,msg('b','RE: cotización','Adjuntamos cotización',2000,['SENT'],'oferta.pdf')])?.category==='quoted');
  assert(classify([first,msg('b','RE: cotización','Gracias',2000,['SENT'])])?.category==='review');
  assert(classify([msg('b','Orden de compra','Coordinación de visita')])?.category==='operational');
  assert(classify([msg('b','Publicidad','Boletín')])?.category==='other');
});
Deno.test('read-only API, fixed query and page token, no attachment download',async()=>{
  const calls:URL[]=[];
  const mock:typeof fetch=async(input,init)=>{
    const url=new URL(String(input));calls.push(url);assert(init?.method==='GET');assert(url.hostname==='gmail.googleapis.com');
    if(url.pathname.endsWith('/threads'))return Response.json({threads:[{id:'one'},{id:'one'}],nextPageToken:'next',resultSizeEstimate:4});
    assert(url.pathname.endsWith('/threads/one')&&url.searchParams.get('format')==='full');
    assert(!url.searchParams.get('fields')?.includes('body'));
    return Response.json({id:'one',messages:[msg('m','Solicitud de cotización','Solicitamos cotizar')]});
  };
  const r=await readPreview(mock,'synthetic',from,to,'previous');
  assert(calls.length===2&&r.scanned===1&&r.next==='next'&&r.candidates.length===1);
  assert(calls[0].searchParams.get('pageToken')==='previous'&&calls[0].searchParams.get('q')?.includes('after:'+Math.floor(from/1000)));
});
Deno.test('failed page does not return a silently incomplete result',async()=>{
  const mock:typeof fetch=async(input)=>String(input).includes('/threads?')?Response.json({threads:[{id:'one'}]}):new Response('',{status:403});
  let rejected=false;try{await readPreview(mock,'synthetic',from,to);}catch{rejected=true;}assert(rejected);
});
