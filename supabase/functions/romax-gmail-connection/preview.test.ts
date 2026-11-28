import { classifyThread, parseDeadlineEvents, readPreview, extractMessageText, importPolicy, DAY_MS } from './preview.ts';
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
  if(!c)throw new Error('Expected a classified deadline update');
  assert(c.category==='follow_up'&&c.deadline_events.length===2);
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
    if(url.pathname.endsWith('/messages/m')){assert(url.searchParams.get('fields')?.includes('body(size,data,attachmentId)'));return Response.json({id:'m',payload:{mimeType:'text/plain',body:{data:btoa('Solicitamos cotizar el servicio')}}});}
    assert(url.pathname.endsWith('/threads/one')&&url.searchParams.get('format')==='full');
    assert(!url.searchParams.get('fields')?.includes('body'));
    return Response.json({id:'one',messages:[msg('m','Solicitud de cotización','Solicitamos cotizar')]});
  };
  const r=await readPreview(mock,'synthetic',from,to,'previous');
  assert(calls.length===3&&r.scanned===1&&r.next==='next'&&r.candidates.length===1);
  assert(calls[0].searchParams.get('pageToken')==='previous'&&calls[0].searchParams.get('q')?.includes('after:'+Math.floor(from/1000))&&calls[0].searchParams.get('q')?.includes('-category:promotions'));
});
Deno.test('failed page does not return a silently incomplete result',async()=>{
  const mock:typeof fetch=async(input)=>String(input).includes('/threads?')?Response.json({threads:[{id:'one'}]}):new Response('',{status:403});
  let rejected=false;try{await readPreview(mock,'synthetic',from,to);}catch{rejected=true;}assert(rejected);
});

Deno.test('platform support notifications are not commercial opportunities',()=>{
  const c=classify([msg('support','Consulta sobre notificaciones de invitaciones y asignación de servicios – Plataforma Supplayer','Invitaciones a cotizar: notificaciones sobre nuevas solicitudes. Solicitamos revisar la cuenta.')]);
  assert(c?.category==='other');
});
Deno.test('proposal-only requests and SST execution updates are distinguished',()=>{
  const request=classify([msg('request','CASS Trujillo Larco - Mantenimiento de letrero luminoso','Favor apoyo con el envío de su propuesta de acuerdo al TDR.')]);
  const operational=classify([msg('ops','HMC SJL Jardines - Observaciones PRE ITSE','Se solicita enviar los documentos SST para ingreso a tienda e inicio de trabajo el lunes 30.')]);
  assert(request?.category==='quote_request');
  assert(operational?.category==='operational');
});

Deno.test('ISO proposal deadline is normalized to Lima local date',()=>{
  const events=parseDeadlineEvents([{snippet:'Fecha de envío de propuesta: 2026-12-01',internalDate:String(to)}]);
  assert(events.length===1&&events[0].date==='2026-12-01'&&events[0].status==='confirmed');
});

Deno.test('an original request with a stated deadline is not misclassified as a follow-up',()=>{
  const c=classify([msg('new','SC-0000154401-2026 UTP Chiclayo','Estimado proveedor, lo invitamos a cotizar. Fecha límite para envío de propuestas: 27/11/2026')]);
  assert(c?.category==='quote_request'&&c.deadline_events.length===1&&c.deadline_events[0].kind==='stated');
});

Deno.test('quoted client history inside an internal quote is not mistaken for a forwarded request',()=>{
  const alias=msg('alias','COTIZACION ROMAX - CASSINELLI','Se adjunta la cotización solicitada. De: Cliente <cliente@cassinelli.com>',1000,['INBOX'],'RMX-2026-7269.pdf','Ventas 3 ROMAX <ventas3@romaxfm.com>');
  const c=classify([alias]);
  assert(c?.category==='quoted'&&c.reference==='RMX-2026-7269');
});

const withBody=(m:ReturnType<typeof msg>,bodyText:string)=>({...m,bodyText});
const utf8b64=(s:string)=>btoa(String.fromCharCode(...new TextEncoder().encode(s))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
Deno.test('audited UTP Chiclayo: identical snippets and changed deadline without extension words',()=>{
  const snippet='Estimado proveedor, lo invitamos a participar en el proceso de cotización';
  const a=withBody(msg('a','SC-0000154401-2026 UTP Chiclayo',snippet,1000),snippet+'\nFECHA PARA VISITAS TÉCNICAS: 24/11/2026 (4:00 pm)\nFECHA LÍMITE PARA ENVÍO DE PROPUESTAS: 27/11/2026');
  const b=withBody(msg('b','SC-0000154401-2026 UTP Chiclayo',snippet,2000),snippet+'\nFECHA LÍMITE PARA ENVÍO DE PROPUESTAS: 30/11/2026');
  const c=classifyThread({id:'test',messages:[a,b]},from,to);
  assert(c?.category==='follow_up'&&c.import_policy==='review_required'&&c.deadline_events.length===2&&c.deadline_events[1].date==='2026-11-30'&&c.deadline_events[1].kind==='extension');
});
Deno.test('audited UTP Lima Sur: body preserves historical date and excludes visits and envelope',()=>{
  const m=withBody(msg('a','SC-0000153027-2026 UTP Lima Sur','Se extiende plazo hasta el sábado 28.11 a las 12pm'), 'Se extiende plazo para entrega de propuesta hasta el día de\nmañana Sábado 28.11 a las 12pm.\nSaludos.\nDe: Cliente\nEnviado el: viernes 06/11/2026\nFecha para la visita técnica: Sábado 07.11 – 10am a 11am o Lunes 09.11 – 10am\nDeadline para envío de propuestas Martes 10/11 – 12 pm.');
  const c=classifyThread({id:'test',messages:[m]},from,to);
  assert(c?.category==='follow_up'&&c.deadline_events.length===2&&c.deadline_events.some(e=>e.date==='2026-11-10'&&e.time==='12:00')&&c.deadline_events.some(e=>e.date==='2026-11-28'&&e.kind==='extension'));
});
Deno.test('audited Cass Trujillo: proposal deadline after excerpt and access instructions',()=>{
  const m=withBody(msg('a','CASS Trujillo Larco - mantenimiento','Favor su apoyo con el envío de su propuesta'), 'Favor su apoyo con el envío de su propuesta de acuerdo al TDR. Confirmar visita a tienda enviando el SCTR.\nFecha de visita: Viernes 27/11 10am a 4pm\nFecha de envío de propuesta: 2026-12-01');
  const c=classifyThread({id:'test',messages:[m]},from,to);
  assert(c?.category==='quote_request'&&c.deadline_events.length===1&&c.deadline_events[0].date==='2026-12-01');
});
Deno.test('audited FEN: invitation phrasing and deadline in body',()=>{
  const m=withBody(msg('a','UTP contratos marco FEN','Los invitamos a participar en el proceso de cotización'), 'Los invitamos a participar en el proceso de cotización para técnicos de mantenimiento.\nAgradeceremos el envío de su propuesta hasta el día de mañana 27/11 hasta las 12:00 pm.');
  const c=classifyThread({id:'test',messages:[m]},from,to);
  assert(c?.category==='quote_request'&&c.deadline_events[0].date==='2026-11-27'&&c.deadline_events[0].time==='12:00');
});
Deno.test('promotion excluded, orphan follow-up cannot be a new import candidate',()=>{
  assert(classify([msg('promo','Cupón Black Friday','Descuento exclusivo de 50%',1000,['CATEGORY_PROMOTIONS'])])===null);
  const c=classify([msg('a','HMC Chiclayo','Amable recordatorio: favor enviar propuestas')]);
  assert(c?.category==='follow_up'&&c.import_policy==='review_required'&&importPolicy({...c,existing_status:'in_analysis'})==='link_existing');
});
Deno.test('MIME text only, plain preferred, attachment and HTML script ignored',()=>{
  const p={mimeType:'multipart/mixed',parts:[{mimeType:'multipart/alternative',parts:[{mimeType:'text/plain',body:{data:utf8b64('Propuesta válida')}},{mimeType:'text/html',body:{data:utf8b64('<p>otra</p>')}}]},{mimeType:'text/plain',filename:'secret.txt',body:{data:utf8b64('ATTACHMENT SECRET')}},{mimeType:'image/png',body:{data:'invalid'}}]};
  const decoded=extractMessageText(p);
  assert(decoded.text==='Propuesta válida'&&!decoded.limited);
  const html=extractMessageText({mimeType:'text/html',body:{data:utf8b64('<p>Fecha de envío de propuesta: 2026-12-01</p><script>ignored()</script>')}});
  assert(html.text.includes('2026-12-01')&&!html.text.includes('ignored'));
  assert(extractMessageText({mimeType:'text/plain',body:{attachmentId:'separate'}}).limited);
});
Deno.test('older message body never requested and full body never returned',async()=>{
  const urls:string[]=[];
  const mock:typeof fetch=async(input)=>{
    const url=new URL(String(input));urls.push(url.pathname);
    if(url.pathname.endsWith('/threads'))return Response.json({threads:[{id:'one'}]});
    if(url.pathname.endsWith('/threads/one'))return Response.json({id:'one',messages:[msg('old','Earlier','Old',-1),msg('new','Solicitud','Favor cotizar')]});
    assert(url.pathname.endsWith('/messages/new')&&!url.pathname.includes('attachments'));
    return Response.json({id:'new',payload:{mimeType:'text/plain',body:{data:utf8b64('Favor cotizar\nPRIVATE BODY MARKER')}}});
  };
  const r=await readPreview(mock,'synthetic',from,to);
  assert(urls.length===3&&r.candidates[0].text_source==='body'&&!JSON.stringify(r).includes('PRIVATE BODY MARKER'));
});

Deno.test('retail offer without promotions label is not an adjustment',()=>{
  assert(classify([msg('a','Cupón Black Friday','Descuento exclusivo de 50%')])?.category==='other');
});
Deno.test('proposed work start and SST are not a commercial proposal',()=>{
  const c=classify([msg('a','HMC SJL Jardines PRE ITSE','Se solicita enviar documentos SST para ingreso a tienda, fecha propuesta de inicio de trabajo es lunes 30')]);
  assert(c?.category==='operational'&&c.import_policy==='not_importable');
});


Deno.test('Makro alias quote uses full message MIME to identify attachment and RMX reference',async()=>{
  const alias=msg('alias','COTIZACIÓN ROMAX - MAKRO VARIAS SEDES - SUMINISTRO DE MOTOBOMBAS PORTÁTILES 5.5 HP','Buen día, estimados, Se adjunta la cotización solicitada. RMX-2026-7269 MK VARIOS - SUMINISTRO DE MOTOBOMBAS PORTÁTILES 5.5 HP Quedo atenta a sus comentarios.',1000,['INBOX'],'','Ventas 3 ROMAX FM <ventas3@romaxfm.com>');
  const calls:string[]=[];
  const mock:typeof fetch=async(input)=>{
    const url=new URL(String(input));calls.push(url.pathname);
    if(url.pathname.endsWith('/threads'))return Response.json({threads:[{id:'makro'}]});
    if(url.pathname.endsWith('/threads/makro'))return Response.json({id:'makro',messages:[alias]});
    assert(url.pathname.endsWith('/messages/alias'));
    return Response.json({id:'alias',payload:{mimeType:'multipart/mixed',headers:alias.payload.headers,parts:[
      {mimeType:'text/plain',body:{data:utf8b64('Buen día, estimados,\n\nSe adjunta la cotización solicitada.\n\nRMX-2026-7269 MK VARIOS - SUMINISTRO DE MOTOBOMBAS PORTÁTILES 5.5 HP\n\nQuedo atenta a sus comentarios.')}},
      {filename:'RMX-2026-7269 MK VARIOS - SUMINISTRO DE MOTOBOMBAS PORTÁTILES 5.5 HP.pdf',mimeType:'application/pdf',body:{attachmentId:'pdf'}}
    ]}});
  };
  const result=await readPreview(mock,'synthetic',from,to);
  const c=result.candidates[0];
  assert(c?.category==='quoted'&&c.reference==='RMX-2026-7269'&&c.sender.includes('ventas3@romaxfm.com'));
  assert(c.attachments.length===1&&c.attachments[0].name.endsWith('.pdf')&&c.import_policy==='not_importable');
  assert(calls.some(x=>x==='/messages/alias'));
});
Deno.test('Cassinelli Outlook multipart HTML table keeps proposal deadline and both attachments',async()=>{
  const incoming=msg('cass','CASS Trujillo Larco - MANTENIMIENTO DE LETRERO LUMINOSO Y EMISION DE CERTIFICADO DE ESTRUCTURA ITSE','Estimados buenas tardes, Favor su apoyo con el envío de su propuesta de acuerdo al TDR según requerimiento de Tienda.',1000,['INBOX'],'','procesos <procesos@cassinelli.com>');
  const html='<html><body><div>Estimados buenas tardes,</div><div>Favor su apoyo con el envío de su propuesta de acuerdo al TDR según requerimiento de Tienda. Confirmar visita a tienda enviando el SCTR.</div><table><tr><td>Fecha de visita:</td><td>Viernes 27/11 10am a 4pm</td></tr><tr><td>Fecha de envío de propuesta:</td><td>2026-12-01</td></tr></table></body></html>';
  const mock:typeof fetch=async(input)=>{
    const url=new URL(String(input));
    if(url.pathname.endsWith('/threads'))return Response.json({threads:[{id:'cass'}]});
    if(url.pathname.endsWith('/threads/cass'))return Response.json({id:'cass',messages:[incoming]});
    assert(url.pathname.endsWith('/messages/cass'));
    return Response.json({id:'cass',payload:{mimeType:'multipart/mixed',headers:incoming.payload.headers,parts:[
      {mimeType:'multipart/alternative',parts:[{mimeType:'text/html',body:{data:utf8b64(html)}}]},
      {filename:'TDR-2026-295_ILUMINACION_INTERIOR.xlsx',mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',body:{attachmentId:'xlsx'}},
      {filename:'TDR_CASS_TRUJILLO_LARCO_MANTENIMIENTO_ESTRUCTURA.pdf',mimeType:'application/pdf',body:{attachmentId:'pdf'}}
    ]}});
  };
  const result=await readPreview(mock,'synthetic',from,to);
  const c=result.candidates[0];
  assert(c?.category==='quote_request'&&c.deadline_events.some(e=>e.date==='2026-12-01'&&e.status==='confirmed'));
  assert(c.attachments.length===2&&c.attachments.some(x=>x.name.endsWith('.xlsx'))&&c.attachments.some(x=>x.name.endsWith('.pdf')));
});
Deno.test('Samsung Black Friday with List-Unsubscribe is excluded even without Gmail promotion label',()=>{
  const promo=msg('samsung','🖤 Hoy es Black Friday. Lo mejor está en secreto','Genera tu código y accede a nuestras mejores ofertas.',1000,['INBOX'],'','Samsung <samsunglatam@pe.email.samsung.com>');
  promo.payload.headers.push({name:'List-Unsubscribe',value:'<https://example.test/unsubscribe>, <mailto:unsubscribe@example.test>'});
  assert(classify([promo])===null);
  const gmailCategory=msg('samsung2','Black Friday Samsung','Ofertas exclusivas',1000,['INBOX','CATEGORY_PROMOTIONS']);
  assert(classify([gmailCategory])===null);
});
