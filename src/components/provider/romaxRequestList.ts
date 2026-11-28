// R3-SOL.1: presentation only. No new persistence or authorization.
export const statusLabels: Record<string,string> = {
  new:'Nueva', reviewing:'En revisión',ready_for_analysis:'Lista para análisis',
  in_analysis:'En análisis',quoted:'Cotizada',discarded:'Descartada',
};
export const classificationLabels: Record<string,string> = {
  quote_request:'Solicitud de cotización',follow_up:'Seguimiento',information_only:'Solo información',other:'Otro',unknown:'Sin clasificar',
};
export const matchLabels: Record<string,string> = {
  unmatched:'Sin vincular',suggested:'Coincidencia sugerida',confirmed:'Vinculada',ambiguous:'Requiere revisión',
};
export type Opportunity = {
  id:string;status:string;classification:string;classification_confidence:number|null;classification_reason:string|null;
  commercial_client_id:string|null;commercial_site_id:string|null;commercial_contact_id:string|null;
  match_status:string;subject:string|null;sender_email:string|null;received_at:string|null;snippet:string|null;
  source_system:string;created_at:string;updated_at:string;
};
export type Client={id:string;business_name:string;legal_name?:string|null;commercial_code?:string|null;is_active:boolean};
export type Site={id:string;commercial_client_id:string;site_name:string;site_code?:string|null;city?:string|null;is_active:boolean};
export type Contact={id:string;commercial_client_id:string;commercial_site_id:string|null;full_name:string;email:string|null;is_active:boolean};
export type Attachment={id:string;opportunity_id:string;filename:string;mime_type:string|null;size_bytes:number|null;processing_status:string;created_at:string};
export type Filters={search:string;status:string;client:string;source:string;match:string;classification:string;from:string;to:string};
export const emptyFilters:Filters={search:'',status:'all',client:'all',source:'all',match:'all',classification:'all',from:'',to:''};
export type ListMemory={filters:Filters;page:number;pageSize:number;scroll:number;enrichmentFilters?:{specialty:string;deadline:string;reference:string}};
export function createListMemory():ListMemory{return {filters:{...emptyFilters},page:1,pageSize:15,scroll:0};}
export const isOpportunityId=(v:string|undefined):v is string=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export const canViewRequests=(type:string|undefined,active:boolean,org:string,memberOrg:string|undefined,role:string|undefined)=>!!org&&type==='provider_company'&&active&&org===memberOrg&&['owner','admin','manager','quote_manager'].includes(role??'');
export const normalize=(s:string|null|undefined)=>(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
export function linkedLabel<T>(id:string|null,rows:T[],getId:(x:T)=>string,getLabel:(x:T)=>string):string {
  if(!id)return 'Sin vincular';
  const row=rows.find(x=>getId(x)===id);
  return row?getLabel(row):'Vínculo no disponible';
}
const limaDay=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'});
export function dateInLima(value:string|null):string|null {
  if(!value)return null;const d=new Date(value);if(!Number.isFinite(d.getTime()))return null;
  const parts=limaDay.formatToParts(d);return ['year','month','day'].map(k=>parts.find(p=>p.type===k)?.value).join('-');
}
export function dateLabel(value:string|null):string {
  if(!value||!dateInLima(value))return 'No informada';
  return new Date(value).toLocaleString('es-PE',{timeZone:'America/Lima',dateStyle:'short',timeStyle:'short'});
}
export function filterRows(rows:Opportunity[],f:Filters,clients:Client[],sites:Site[]):Opportunity[]{
  const q=normalize(f.search);
  return rows.filter(r=>{
    if(f.status!=='all'&&r.status!==f.status)return false;
    if(f.source!=='all'&&r.source_system!==f.source)return false;
    if(f.match!=='all'&&r.match_status!==f.match)return false;
    if(f.classification!=='all'&&r.classification!==f.classification)return false;
    if(f.client!=='all'&&(f.client==='none'?r.commercial_client_id!==null:r.commercial_client_id!==f.client))return false;
    const day=dateInLima(r.received_at);
    if((f.from||f.to)&&(!day||(f.from&&day<f.from)||(f.to&&day>f.to)))return false;
    if(!q)return true;
    const client=clients.find(c=>c.id===r.commercial_client_id);
    const site=sites.find(s=>s.id===r.commercial_site_id);
    return normalize([r.subject,r.snippet,r.sender_email,client?.business_name,site?.site_name].filter(Boolean).join(' ')).includes(q);
  });
}
export function metrics(rows:Opportunity[]){
  return {new:rows.filter(x=>x.status==='new').length,reviewing:rows.filter(x=>x.status==='reviewing').length,
    ready_for_analysis:rows.filter(x=>x.status==='ready_for_analysis').length,in_analysis:rows.filter(x=>x.status==='in_analysis').length,
    quoted:rows.filter(x=>x.status==='quoted').length,unmatched:rows.filter(x=>x.match_status==='unmatched').length};
}
export function paginate<T>(rows:T[],page:number,size:number){
  const pageCount=Math.max(1,Math.ceil(rows.length/size)), current=Math.min(Math.max(1,page),pageCount);
  return {rows:rows.slice((current-1)*size,current*size),page:current,pageCount,total:rows.length,start:rows.length?(current-1)*size+1:0,end:Math.min(current*size,rows.length)};
}
type PageResult<T>={data:T[]|null;count:number|null;error:{message:string}|null};
// Full authorized universe, never assume that an implicit PostgREST cap is the total.
// An unstable or incomplete scan fails explicitly; no partial metrics.
export async function collectPages<T extends {id:string}>(read:(from:number,to:number)=>PromiseLike<PageResult<T>>,signal:AbortSignal,batch=200):Promise<T[]>{
  const items:T[]=[], seen=new Set<string>();let expected:number|null=null;
  for(;;){
    if(signal.aborted)throw new Error('Consulta cancelada');
    const res=await read(items.length,items.length+batch-1);
    if(signal.aborted)throw new Error('Consulta cancelada');
    if(res.error)throw new Error(res.error.message);
    if(res.count===null||!Number.isSafeInteger(res.count)||res.count<0)throw new Error('No se pudo comprobar el total de registros');
    if(expected!==null&&expected!==res.count)throw new Error('Los registros cambiaron; actualiza nuevamente');
    expected=res.count;
    const page=res.data??[];
    for(const row of page){if(!row.id||seen.has(row.id))throw new Error('Los registros cambiaron; actualiza nuevamente');seen.add(row.id);items.push(row);}
    if(items.length===expected)return items;
    if(items.length>expected||!page.length)throw new Error('La consulta quedó incompleta; actualiza nuevamente');
  }
}
