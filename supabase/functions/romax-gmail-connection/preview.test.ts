import { classifyThread, parseDeadlineEvents, readPreview, DAY_MS } from './preview.ts';
function assert(v:unknown,msg='assertion failed'){if(!v)throw Error(msg);}
const to=Date.parse('2026-11-27T20:00:00Z'),from=to-7*DAY_MS;
const msg=(id:string,subject:string,snippet:string,offset=1000,labels=['INBOX'],file='',sender='Cliente <cliente@example.test>')=>({id,internalDate:String(from+offset),labelIds:labels,snippet,payload:{headers:[{name:'Subject',value:subject},{name:'From',value:sender}],parts:file?[{filename:file,mimeType:file.endsWith('.xlsx')?'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'application/pdf'}]:[]}});
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
Deno.test('internal ROMAX forward preserves the original external request once',()=>{
  const original=msg('external','LEVANTAMIENTO OBSERVACIONES PRE ITSE CASS PIURA','Estimado proveedor, por favor cotizar el TDR de Cassinelli Piura, deadline 30/11',1000,['INBOX'],'TDR.xlsx','Elmer <ebardales@cassinelli.com>');
  const forward=msg('forward','Fwd: LEVANTAMIENTO OBSERVACIONES PRE ITSE CASS PIURA','---------- Forwarded message ---------- De: Elmer Segundo <ebardales@cassinelli.com> Subject: LEVANTAMIENTO OBSERVACIONES PRE ITSE CASS PIURA Estimado proveedor, por favor cotizar el TDR, deadline 30/11',2000,['INBOX'],'TDR.xlsx','Planner ROMAX <planner.operaciones@romaxfm.com>');
  const c=classify([original,forward]);
  assert(c?.category==='quote_request'&&c.sender==='Elmer <ebardales@cassinelli.com>'&&c.message_count===2&&c.attachments.length===1);
  const forwardedOnly=classify([forward]);
  assert(forwardedOnly?.category==='quote_request'&&forwardedOnly.sender==='ebardales@cassinelli.com');
});
Deno.test('ROMAX aliases count as sent even without Gmail SENT label',()=>{
  const alias=msg('alias','COTIZACION ROMAX - MAKRO MOTOBOMBAS','Buen día, Se adjunta la cotización solicitada RMX-2026-7269. Quedo atenta.',1000,['INBOX'],'RMX-2026-7269.pdf','Ventas 3 ROMAX <ventas3@romaxfm.com>');
  const c=classify([alias]);
  assert(c?.category==='quoted'&&c.reference==='RMX-2026-7269'&&c.sender==='Ventas 3 ROMAX <ventas3@romaxfm.com>');
});
Deno.test('deadline extension preserves original and updated dates in Lima timezone',()=>{
  const update=msg('u','RV: UTP Lima Sur servicio de gasfitería SC-0000153027-2026','Se extiende plazo para entrega de propuesta hasta el día de mañana Sábado 28.11 a las 12pm. Deadline para envío de propuestas Martes 10/11 – 12 pm.',1000,['INBOX'],'','Elisa <ealvis@utp.edu.pe>');
  const c=classify([update]);
  assert(c?.category==='follow_up'&&c.deadline_events.length===2);
  assert(c.deadline_events[0].kind==='extension'&&c.deadline_events[0].date==='2026-11-28'&&c.deadline_events[0].time==='12:00'&&c.deadline_events[0].datetime==='2026-11-28T12:00:00-05:00');
  assert(c.deadline_events[1].kind==='stated'&&c.deadline_events[1].date==='2026-11-10'&&c.deadline_events[1].time==='12:00');
  assert(c.deadline_hint===c.deadline_events[0].raw);
});
Deno.test('weekday/date contradiction remains ambiguous and is not normalized',()=>{
  const update=msg('u','SOLICITUD DE COTIZACION UTP PIURA','Enviar propuesta hasta el viernes 26/11',1000,['INBOX'],'','UTP <cliente@utp.edu.pe>');
  const c=classify([update]);
  assert(c?.deadline_events.length===1&&c.deadline_events[0].status==='ambiguous'&&c.deadline_events[0].date===null);
});
Deno.test('Chiclayo deadline history keeps 27/11 and extension to 30/11',()=>{
  const first=msg('a','SC-0000154401-2026 UTP Chiclayo','Fecha límite para envío de propuestas: 27/11/2026',1000,['INBOX'],'','UTP <cliente@utp.edu.pe>');
  const update=msg('b','RV: SC-0000154401-2026 UTP Chiclayo','Se amplía plazo de entrega de propuesta hasta el 30/11/2026',2000,['INBOX'],'','UTP <cliente@utp.edu.pe>');
  const c=classify([first,update]);
  assert(c?.category==='follow_up'&&c.deadline_events.some(e=>e.date==='2026-11-27')&&c.deadline_events.some(e=>e.kind==='extension'&&e.date==='2026-11-30'));
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
