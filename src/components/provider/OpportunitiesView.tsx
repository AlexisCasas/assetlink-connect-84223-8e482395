import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { BriefcaseBusiness, Plus, RefreshCw, Search, Mail, Eye, ChevronLeft, ChevronRight } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { navigateToEntity } from '@/lib/entityNavigation';
import { useToast } from '@/hooks/use-toast';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import GmailConnectionPanel from './GmailConnectionPanel';
import RequestDetail from './RequestDetail';
import RequestDocuments from './RequestDocuments';
import RequestEnrichment from './RequestEnrichment';
import {deadlineStatus,specialties,type Review} from './romaxEnrichment';
import { collectPages, canViewRequests, createListMemory, dateLabel, emptyFilters, filterRows, isOpportunityId, linkedLabel, metrics, paginate, statusLabels, classificationLabels, matchLabels, type Opportunity, type Client, type Site, type Contact, type Attachment, type Filters, type ListMemory } from './romaxRequestList';

const emptyForm={subject:'',sender_email:'',received_at:'',snippet:'',classification:'quote_request',commercial_client_id:'',commercial_site_id:'',commercial_contact_id:''};
type Dataset={documentsReady:boolean;reviews:Review[]|null;opportunities:Opportunity[];clients:Client[];sites:Site[];contacts:Contact[];attachments:Attachment[]};
type Props={focusOpportunityId?:string;memory?:ListMemory};
// ROMAX tables are not yet in the generated client types; preserve the existing adapter.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const db=supabase as any;
const ROMAX='a76fb740-78cf-4ed5-97dd-1e1e24fcab68';
const selectClass='h-10 min-w-0 max-w-full rounded-md border bg-background px-2 text-sm';
const statusName=(v:string)=>statusLabels[v]??'Estado desconocido';
const matchName=(v:string)=>matchLabels[v]??'Vinculación desconocida';
const originName=(v:string)=>v==='gmail'?'Gmail':v==='manual'?'Manual':'No informado';
const fieldList='id,status,classification,classification_confidence,classification_reason,commercial_client_id,commercial_site_id,commercial_contact_id,match_status,subject,sender_email,received_at,snippet,source_system,created_at,updated_at';

function FilterSelect({label,value,onChange,options}:{label:string;value:string;onChange:(v:string)=>void;options:[string,string][]}){
  return <label className="grid min-w-0 gap-1 text-xs text-muted-foreground">{label}<select className={selectClass} value={value} onChange={e=>onChange(e.target.value)}>{options.map(([v,t])=><option key={v} value={v}>{t}</option>)}</select></label>;
}
function ScopedView({focusOpportunityId,memory,organizationId,gmailAllowed}:{focusOpportunityId?:string;memory:ListMemory;organizationId:string;gmailAllowed:boolean}){
  const {toast}=useToast();
  const [data,setData]=useState<Dataset|null>(null);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState('');
  const [filters,setFilters]=useState<Filters>(()=>({...memory.filters}));
  const [page,setPage]=useState(memory.page);
  const [pageSize,setPageSize]=useState(memory.pageSize);
  const [tab,setTab]=useState('registered');
  const [form,setForm]=useState(emptyForm);
  const [manualOpen,setManualOpen]=useState(false);
  const [saving,setSaving]=useState(false);
  const [notice,setNotice]=useState('');
  const [specialtyFilter,setSpecialtyFilter]=useState(memory.enrichmentFilters?.specialty??'all'),[deadlineFilter,setDeadlineFilter]=useState(memory.enrichmentFilters?.deadline??'all'),[referenceFilter,setReferenceFilter]=useState(memory.enrichmentFilters?.reference??'');
  useEffect(()=>{memory.enrichmentFilters={specialty:specialtyFilter,deadline:deadlineFilter,reference:referenceFilter};},[memory,specialtyFilter,deadlineFilter,referenceFilter]);
  const root=useRef<HTMLDivElement>(null);
  const opener=useRef<HTMLElement|null>(null);
  const abortRef=useRef<AbortController|null>(null);
  const mounted=useRef(true);
  const savingRef=useRef(false);
  const restored=useRef(false);
  const loadData=useCallback(async()=>{
    abortRef.current?.abort();
    const controller=new AbortController();abortRef.current=controller;
    const signal=controller.signal;
    setLoading(true);setError('');
    try{
      const read=<T extends {id:string}>(table:string,columns:string,ordered=false)=>collectPages<T>((from,to)=>{
        let query=db.from(table).select(columns,{count:'exact'}).eq('organization_id',organizationId);
        if(ordered)query=query.order('received_at',{ascending:false,nullsFirst:false}).order('created_at',{ascending:false});
        return query.order('id',{ascending:true}).range(from,to).abortSignal(signal);
      },signal);
      const [opportunities,clients,sites,contacts,legacyAttachments]=await Promise.all([
        read<Opportunity>('romax_opportunities',fieldList,true),
        read<Client>('commercial_clients','id,business_name,legal_name,commercial_code,is_active'),
        read<Site>('commercial_client_sites','id,commercial_client_id,site_name,site_code,city,is_active'),
        read<Contact>('commercial_client_contacts','id,commercial_client_id,commercial_site_id,full_name,email,is_active'),
        read<Attachment>('romax_opportunity_attachments','id,opportunity_id,filename,mime_type,size_bytes,processing_status,created_at'),
      ]);
      let attachments=legacyAttachments,documentsReady=false;
      try{attachments=await read<Attachment>('romax_attachment_metadata','id,opportunity_id,filename,mime_type,size_bytes,processing_status,created_at,source_system,source_direction,source_received_at,availability_status,scan_status,restriction_code,source_locator_kind');documentsReady=true;}catch{/* pre-migration Preview retains read-only legacy list */}
      let reviews:Review[]|null=null;
      try{reviews=await collectPages<Review & {id:string}>((from,to)=>db.from('romax_request_current').select('id:opportunity_id,organization_id,opportunity_id,revision,reviewed_at,snapshot',{count:'exact'}).eq('organization_id',organizationId).order('opportunity_id').range(from,to).abortSignal(signal),signal);}catch{/* pre-migration Preview: preserve base inbox, explicitly disable enrichment */}
      if(signal.aborted)return;
      setData({opportunities,clients,sites,contacts,attachments,reviews,documentsReady});
      return true;
    }catch{
      if(!signal.aborted){setError('No se pudo cargar la lista completa. Actualiza para volver a intentarlo.');setData(null);}
      return false;
    }finally{if(!signal.aborted)setLoading(false);}
  },[organizationId]);
  useEffect(()=>{mounted.current=true;void loadData();return ()=>{mounted.current=false;abortRef.current?.abort();};},[loadData]);
  useEffect(()=>{if(data&&!loading&&!restored.current){restored.current=true;const main=root.current?.closest('main');if(main)main.scrollTop=memory.scroll;}},[data,loading,memory]);
  useEffect(()=>{memory.filters={...filters};memory.page=page;memory.pageSize=pageSize;},[filters,page,pageSize,memory]);
  const opportunities=useMemo(()=>data?.opportunities??[],[data]);
  const clients=useMemo(()=>data?.clients??[],[data]);
  const sites=useMemo(()=>data?.sites??[],[data]);
  const contacts=useMemo(()=>data?.contacts??[],[data]);
  const attachments=useMemo(()=>data?.attachments??[],[data]);
  const attachmentCounts=useMemo(()=>{const result=new Map<string,number>();for(const a of attachments)result.set(a.opportunity_id,(result.get(a.opportunity_id)??0)+1);return result;},[attachments]);
  const filteredSites=useMemo(()=>sites.filter(s=>s.is_active&&(!form.commercial_client_id||s.commercial_client_id===form.commercial_client_id)),[sites,form.commercial_client_id]);
  const filteredContacts=useMemo(()=>contacts.filter(c=>c.is_active&&(!form.commercial_client_id||c.commercial_client_id===form.commercial_client_id)&&(!form.commercial_site_id||!c.commercial_site_id||c.commercial_site_id===form.commercial_site_id)),[contacts,form.commercial_client_id,form.commercial_site_id]);
  const clientName=(id:string|null)=>linkedLabel(id,clients,x=>x.id,x=>x.business_name+(x.is_active?'':' (inactivo)'));
  const siteName=(id:string|null)=>linkedLabel(id,sites,x=>x.id,x=>x.site_name+(x.is_active?'':' (inactiva)'));
  const contactName=(id:string|null)=>linkedLabel(id,contacts,x=>x.id,x=>x.full_name+(x.is_active?'':' (inactivo)'));
  const reviews=useMemo(()=>new Map((data?.reviews??[]).map(r=>[r.opportunity_id,r])),[data]);
  const alerts=useMemo(()=>opportunities.map(o=>deadlineStatus(o,reviews.get(o.id)?.snapshot)),[opportunities,reviews]);
  const filtered=useMemo(()=>filterRows(opportunities,filters,clients,sites).filter(o=>{const s=reviews.get(o.id)?.snapshot;return data?.reviews===null||((specialtyFilter==='all'||(s?.specialty??'none')===specialtyFilter)&&(deadlineFilter==='all'||deadlineStatus(o,s)===deadlineFilter)&&(!referenceFilter||!!s?.reference?.toLowerCase().includes(referenceFilter.toLowerCase())));}),[opportunities,filters,clients,sites,reviews,specialtyFilter,deadlineFilter,referenceFilter,data?.reviews]);
  const counts=useMemo(()=>metrics(opportunities),[opportunities]);
  const paging=paginate(filtered,page,pageSize);
  useEffect(()=>{if(data&&!loading&&page!==paging.page)setPage(paging.page);},[data,loading,page,paging.page]);
  const updateFilter=(key:keyof Filters,value:string)=>{setFilters(f=>({...f,[key]:value}));setPage(1);};
  const resetForm=()=>setForm(emptyForm);
  const rememberScroll=()=>{memory.scroll=root.current?.closest('main')?.scrollTop??0;};
  const openDetail=(id:string)=>{
    if(!isOpportunityId(id))return;
    rememberScroll();opener.current=document.activeElement instanceof HTMLElement?document.activeElement:null;
    setTab('registered');navigateToEntity({view:'opportunities',opportunityId:id});
    if(!opportunities.some(o=>o.id===id))void loadData();
  };
  const closeDetail=()=>{navigateToEntity({view:'opportunities'});};
  const openAnalysis=(id:string)=>{rememberScroll();navigateToEntity({view:'opportunity-analysis',opportunityId:id});};
  const onImported=async()=>{const ok=await loadData();if(mounted.current)setNotice(ok?'Bandeja actualizada. Los filtros se conservan; si no ves la solicitud, revisa los filtros activos.':'La importación respondió; vuelve a cargar las solicitudes para consultar el resultado.');};
  const createOpportunity=async(event:React.FormEvent<HTMLFormElement>)=>{
    event.preventDefault();
    if(!mounted.current||savingRef.current||!data)return;
    savingRef.current=true;setSaving(true);
    try{
      const payload={organization_id:organizationId,status:'new',classification:form.classification,
        commercial_client_id:form.commercial_client_id||null,commercial_site_id:form.commercial_site_id||null,
        commercial_contact_id:form.commercial_contact_id||null,match_status:form.commercial_client_id?'confirmed':'unmatched',
        subject:form.subject.trim()||null,sender_email:form.sender_email.trim()||null,
        received_at:form.received_at?new Date(form.received_at+'-05:00').toISOString():null,snippet:form.snippet.trim()||null,source_system:'manual'};
      const {error:writeError}=await db.from('romax_opportunities').insert(payload);
      if(writeError)throw writeError;
      if(!mounted.current)return;
      resetForm();setManualOpen(false);setNotice('Solicitud registrada. Los filtros se conservan.');
      toast({title:'Oportunidad registrada',description:'La solicitud quedó disponible para revisión.'});await loadData();
    }catch{if(mounted.current)toast({title:'No se pudo registrar la oportunidad',description:'Revisa los datos y vuelve a intentarlo.',variant:'destructive'});}
    finally{savingRef.current=false;if(mounted.current)setSaving(false);}
  };
  const selected=isOpportunityId(focusOpportunityId)?opportunities.find(o=>o.id===focusOpportunityId):undefined;
  const activeFilters=specialtyFilter!=='all'||deadlineFilter!=='all'||!!referenceFilter||Object.entries(filters).some(([k,v])=>['search','from','to'].includes(k)?!!v:v!=='all');
  const badDates=!!filters.from&&!!filters.to&&filters.from>filters.to;
  const filtersList:[string,string][]=[['all','Todos'],...Object.entries(statusLabels)];
  const kpis:[keyof typeof counts,string][]=[['new','Nuevas'],['reviewing','En revisión'],['ready_for_analysis','Listas para análisis'],['in_analysis','En análisis'],['quoted','Cotizadas'],['unmatched','Sin vincular']];
  return <div ref={root} className="min-w-0 space-y-4 p-3 sm:p-6">
    <header className="flex flex-wrap items-start justify-between gap-3">
      <div className="min-w-0"><h1 tabIndex={-1} className="flex items-center gap-2 text-xl font-semibold sm:text-2xl"><BriefcaseBusiness className="h-6 w-6 shrink-0"/>Solicitudes comerciales</h1><p className="mt-1 text-sm text-muted-foreground">Centralizador de oportunidades y cotizaciones.</p></div>
      <div className="flex flex-wrap gap-2"><Button variant="outline" disabled={loading} onClick={()=>void loadData()}><RefreshCw className="mr-2 h-4 w-4"/>Actualizar</Button><Button disabled={!data||!!error} onClick={()=>{resetForm();setManualOpen(true);}}><Plus className="mr-2 h-4 w-4"/>Nueva solicitud</Button></div>
    </header>
    <Tabs value={tab} onValueChange={setTab}>
      <TabsList className="h-auto max-w-full flex-wrap justify-start"><TabsTrigger value="registered">Solicitudes registradas</TabsTrigger>{gmailAllowed&&<TabsTrigger value="gmail"><Mail className="mr-2 h-4 w-4"/>Bandeja Gmail</TabsTrigger>}</TabsList>
      <TabsContent value="registered" forceMount className={tab==='registered'?'space-y-4':'hidden'}>
        {notice&&<p role="status" className="text-sm text-muted-foreground">{notice}</p>}
        {loading&&<p role="status" className="text-sm text-muted-foreground">{data?'Actualizando solicitudes…':'Cargando solicitudes…'}</p>}
        {error&&<div role="alert" className="flex flex-wrap items-center gap-2 rounded-md border p-3 text-sm">{error}<Button variant="outline" size="sm" onClick={()=>void loadData()}>Reintentar</Button></div>}
        {data&&<>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 xl:grid-cols-6">
            {kpis.map(([k,title])=><button type="button" key={k} aria-pressed={k==='unmatched'?filters.match===k:filters.status===k} onClick={()=>updateFilter(k==='unmatched'?'match':'status',(k==='unmatched'?filters.match:filters.status)===k?'all':k)} className="min-w-0 rounded-lg border bg-card p-3 text-left hover:bg-muted/50 focus-visible:ring-2 focus-visible:ring-ring aria-pressed:border-primary"><span className="block text-xs text-muted-foreground">{title}</span><span className="block text-2xl font-semibold">{counts[k]}</span></button>)}
          </div>
          {data.reviews!==null?<div className="grid grid-cols-3 gap-2">{([['near','Por vencer'],['overdue','Vencidas'],['none','Sin plazo confirmado']] as const).map(([key,label])=><button type="button" aria-pressed={deadlineFilter===key} key={key} className="rounded border p-2 text-left text-sm" onClick={()=>{setDeadlineFilter(deadlineFilter===key?'all':key);setPage(1);}}>{label}<strong className="block text-lg">{alerts.filter(x=>x===key).length}</strong></button>)}</div>:<p role="status" className="text-sm text-muted-foreground">Enriquecimiento no disponible en este ambiente. La bandeja original sigue operativa.</p>}
          <p className="text-xs text-muted-foreground">Indicadores de todas las solicitudes autorizadas{error?' (última lectura disponible)':''}. Sin vincular es independiente del estado.</p>
          <div className="space-y-3 rounded-lg border p-3">
            <label className="block space-y-1 text-xs text-muted-foreground">Buscar solicitud<div className="relative"><Search className="absolute left-3 top-3 h-4 w-4"/><Input value={filters.search} onChange={e=>updateFilter('search',e.target.value)} className="pl-9" placeholder="Asunto, extracto, remitente, cliente o sede"/></div></label>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
              <FilterSelect label="Estado" value={filters.status} onChange={v=>updateFilter('status',v)} options={filtersList}/>
              <FilterSelect label="Cliente" value={filters.client} onChange={v=>updateFilter('client',v)} options={ [['all','Todos'],['none','Sin vincular'],...clients.map(c=>[c.id,clientName(c.id)] as [string,string]).sort((a,b)=>a[1].localeCompare(b[1],'es'))] }/>
              <FilterSelect label="Origen" value={filters.source} onChange={v=>updateFilter('source',v)} options={ [['all','Todos'],['gmail','Gmail'],['manual','Manual']] }/>
              <FilterSelect label="Vinculación" value={filters.match} onChange={v=>updateFilter('match',v)} options={ [['all','Todas'],...Object.entries(matchLabels)] }/>
              <FilterSelect label="Clasificación" value={filters.classification} onChange={v=>updateFilter('classification',v)} options={ [['all','Todas'],...Object.entries(classificationLabels)] }/>
              <label className="grid min-w-0 gap-1 text-xs text-muted-foreground">Recibida desde (Lima)<Input className="min-w-0" type="date" value={filters.from} onChange={e=>updateFilter('from',e.target.value)}/></label>
              <label className="grid min-w-0 gap-1 text-xs text-muted-foreground">Recibida hasta (Lima)<Input className="min-w-0" type="date" value={filters.to} onChange={e=>updateFilter('to',e.target.value)}/></label>
              {data.reviews!==null&&<><FilterSelect label="Especialidad" value={specialtyFilter} onChange={v=>{setSpecialtyFilter(v);setPage(1);}} options={ [['all','Todas'],['none','Por determinar'],...Object.entries(specialties)] }/><FilterSelect label="Plazo" value={deadlineFilter} onChange={v=>{setDeadlineFilter(v);setPage(1);}} options={ [['all','Todos'],['near','Por vencer'],['overdue','Vencidas'],['none','Sin plazo confirmado'],['later','Vigentes'],['closed','Cerradas']] }/><label className="grid gap-1 text-xs">Referencia externa<Input value={referenceFilter} onChange={e=>{setReferenceFilter(e.target.value);setPage(1);}}/></label></>}
              <div className="flex items-end"><Button variant="outline" disabled={!activeFilters} onClick={()=>{setFilters({...emptyFilters});setSpecialtyFilter('all');setDeadlineFilter('all');setReferenceFilter('');setPage(1);}}>Limpiar filtros</Button></div>
            </div>
            {badDates&&<p role="alert" className="text-sm text-destructive">El inicio del rango no puede ser posterior al final.</p>}
          </div>
          {paging.total===0?<Card><CardContent className="p-6 text-center"><p className="font-medium">{opportunities.length?'No hay solicitudes con estos filtros.':'Todavía no hay solicitudes registradas.'}</p><p className="mt-1 text-sm text-muted-foreground">{opportunities.length?'Ajusta los filtros para ampliar la búsqueda.':'Registra una solicitud manual o revisa la bandeja Gmail si tienes autorización.'}</p></CardContent></Card>:<>
            <div className="hidden overflow-x-auto rounded-lg border xl:block">
              <table className="w-full table-fixed text-left text-sm"><thead className="border-b bg-muted/50 text-xs text-muted-foreground"><tr>{[['Recepción', 'w-[12%]'],['Solicitud','w-[24%]'],['Cliente / sede','w-[18%]'],['Origen','w-[8%]'],['Estado','w-[12%]'],['Vinculación','w-[11%]'],['Docs.','w-[5%]'],['Acción','w-[10%]']].map(([name,width])=><th key={name} scope="col" className={'p-2 font-medium '+width}>{name}</th>)}</tr></thead><tbody>
                {paging.rows.map(o=><tr key={o.id} className="border-b align-top last:border-b-0 hover:bg-muted/30"><td className="break-words p-2 text-xs">{dateLabel(o.received_at)}</td><td className="break-words p-2 font-medium">{reviews.get(o.id)?.snapshot.title||o.subject||'Solicitud sin asunto'}{reviews.get(o.id)&&<div className="text-xs font-normal text-muted-foreground">{specialties[reviews.get(o.id)?.snapshot.specialty??'']??'Por determinar'} · {reviews.get(o.id)?.snapshot.deadline_date??'Sin plazo'}</div>}</td><td className="break-words p-2">{clientName(o.commercial_client_id)}<div className="text-xs text-muted-foreground">{siteName(o.commercial_site_id)}</div></td><td className="p-2">{originName(o.source_system)}</td><td className="break-words p-2">{statusName(o.status)}</td><td className="break-words p-2 text-xs">{matchName(o.match_status)}</td><td className="p-2" title="Documentos registrados, no adjuntos detectados en Gmail">{attachmentCounts.get(o.id)??0}</td><td className="p-2"><Button size="sm" variant="outline" aria-label={'Ver solicitud: '+(o.subject||'Sin asunto')} onClick={()=>openDetail(o.id)}><Eye className="mr-1 h-4 w-4"/>Ver</Button></td></tr>)}
              </tbody></table>
            </div>
            <div className="space-y-2 xl:hidden">{paging.rows.map(o=><Card key={o.id}><CardContent className="space-y-2 p-3"><div className="break-words font-medium">{reviews.get(o.id)?.snapshot.title||o.subject||'Solicitud sin asunto'}</div>{reviews.get(o.id)&&<div className="text-xs text-muted-foreground">{specialties[reviews.get(o.id)?.snapshot.specialty??'']??'Por determinar'} · {reviews.get(o.id)?.snapshot.deadline_date??'Sin plazo'}</div>}<div className="flex flex-wrap gap-2"><Badge variant="secondary">{statusName(o.status)}</Badge><Badge variant="outline">{originName(o.source_system)}</Badge><Badge variant="outline">{matchName(o.match_status)}</Badge></div><div className="break-words text-sm">{clientName(o.commercial_client_id)} · {siteName(o.commercial_site_id)}</div><div className="text-xs text-muted-foreground">{dateLabel(o.received_at)} · {attachmentCounts.get(o.id)??0} documentos registrados</div><Button variant="outline" size="sm" onClick={()=>openDetail(o.id)}><Eye className="mr-1 h-4 w-4"/>Ver solicitud</Button></CardContent></Card>)}</div>
            <div className="flex flex-wrap items-center justify-between gap-2 text-sm"><span>Mostrando {paging.start}–{paging.end} de {paging.total}</span><div className="flex flex-wrap items-center gap-2"><label className="text-xs">Por página <select className="rounded border bg-background p-1" value={pageSize} onChange={e=>{setPageSize(Number(e.target.value));setPage(1);}}>{[15,30,50].map(n=><option key={n}>{n}</option>)}</select></label><Button variant="outline" size="icon" aria-label="Página anterior" disabled={paging.page<=1} onClick={()=>setPage(paging.page-1)}><ChevronLeft className="h-4 w-4"/></Button><span>{paging.page} / {paging.pageCount}</span><Button variant="outline" size="icon" aria-label="Página siguiente" disabled={paging.page>=paging.pageCount} onClick={()=>setPage(paging.page+1)}><ChevronRight className="h-4 w-4"/></Button></div></div>
          </>}
        </>}
      </TabsContent>
      {gmailAllowed&&<TabsContent value="gmail" forceMount className={tab==='gmail'?'space-y-3':'hidden'}><GmailConnectionPanel organizationId={organizationId} onImported={onImported} onOpenOpportunity={openDetail}/></TabsContent>}
    </Tabs>
    <Dialog open={manualOpen} onOpenChange={v=>{if(!savingRef.current){setManualOpen(v);if(!v)resetForm();}}}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-xl"><DialogHeader><DialogTitle>Nueva solicitud</DialogTitle><DialogDescription>Registro manual. La fecha de recepción se interpreta en horario de Lima.</DialogDescription></DialogHeader>
      <form className="space-y-3" onSubmit={createOpportunity}>
              <div className="space-y-1.5"><Label htmlFor="opportunity-subject">Asunto</Label><Input id="opportunity-subject" value={form.subject} onChange={(event) => setForm({ ...form, subject: event.target.value })} maxLength={300} /></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-sender">Remitente</Label><Input id="opportunity-sender" type="email" value={form.sender_email} onChange={(event) => setForm({ ...form, sender_email: event.target.value })} maxLength={320} /></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-received">Fecha de recepción</Label><Input id="opportunity-received" type="datetime-local" value={form.received_at} onChange={(event) => setForm({ ...form, received_at: event.target.value })} /></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-classification">Clasificación</Label><select id="opportunity-classification" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.classification} onChange={(event) => setForm({ ...form, classification: event.target.value })}>{Object.entries(classificationLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-client">Cliente</Label><select id="opportunity-client" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.commercial_client_id} onChange={(event) => setForm({ ...form, commercial_client_id: event.target.value, commercial_site_id: '', commercial_contact_id: '' })}><option value="">Sin vincular</option>{clients.filter(client=>client.is_active).map((client) => <option key={client.id} value={client.id}>{client.business_name}</option>)}</select></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-site">Sede</Label><select id="opportunity-site" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.commercial_site_id} onChange={(event) => setForm({ ...form, commercial_site_id: event.target.value, commercial_contact_id: '' })} disabled={!form.commercial_client_id}><option value="">Sin vincular</option>{filteredSites.map((site) => <option key={site.id} value={site.id}>{site.site_name}</option>)}</select></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-contact">Contacto</Label><select id="opportunity-contact" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.commercial_contact_id} onChange={(event) => setForm({ ...form, commercial_contact_id: event.target.value })} disabled={!form.commercial_client_id}><option value="">Sin vincular</option>{filteredContacts.map((contact) => <option key={contact.id} value={contact.id}>{contact.full_name}{contact.email ? ` · ${contact.email}` : ''}</option>)}</select></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-snippet">Resumen / contenido inicial</Label><Textarea id="opportunity-snippet" value={form.snippet} onChange={(event) => setForm({ ...form, snippet: event.target.value })} rows={5} placeholder="Pega aquí temporalmente el resumen de la solicitud." /></div>
              <Button type="submit" className="w-full" disabled={saving}><Plus className="mr-2 h-4 w-4" />{saving ? 'Registrando…' : 'Registrar oportunidad'}</Button>
            </form>
      </DialogContent>
    </Dialog>
    <RequestDetail documents={selected&&data?.documentsReady?<RequestDocuments key={selected.id} organizationId={organizationId} opportunity={selected} attachments={attachments.filter(a=>a.opportunity_id===selected.id)} gmailAllowed={gmailAllowed} onChanged={async()=>{await loadData();}}/>:undefined} enrichment={selected&&data?.reviews!==null&&data?<RequestEnrichment key={selected.id} organizationId={organizationId} opportunity={selected} review={reviews.get(selected.id)} clients={clients} sites={sites} contacts={contacts} gmailAllowed={gmailAllowed} onSaved={async()=>{await loadData();}}/>:undefined} open={!!focusOpportunityId} loading={loading&&!data} error={!!error&&!data} opportunity={selected} attachments={selected?attachments.filter(a=>a.opportunity_id===selected.id):[]} clientName={selected?clientName(selected.commercial_client_id):''} siteName={selected?siteName(selected.commercial_site_id):''} contactName={selected?contactName(selected.commercial_contact_id):''} onClose={closeDetail} onAnalyze={openAnalysis} onRetry={async()=>{await loadData();}} returnFocus={()=>{if(opener.current?.isConnected&&opener.current.getClientRects().length)opener.current.focus();else root.current?.querySelector<HTMLElement>('h1')?.focus();}}/>
  </div>;
}
export default function OpportunitiesView({focusOpportunityId,memory}:Props){
  const {user,currentOrganization,currentMembership}=useAuth();
  const ownMemory=useMemo(createListMemory,[user?.id,currentOrganization?.id,currentMembership?.role,currentMembership?.isActive,currentOrganization?.status]);
  const organizationId=currentOrganization?.id??'';
  const authorized=!!user&&currentOrganization?.status==='active'&&canViewRequests(currentOrganization.organizationType,!!currentMembership?.isActive,organizationId,currentMembership?.organizationId,currentMembership?.role);
  if(!authorized)return <div className="p-8 text-center"><p className="font-semibold">Acceso restringido</p><p className="text-sm text-muted-foreground">Disponible únicamente para miembros autorizados de organizaciones proveedoras.</p></div>;
  return <ScopedView key={user.id+':'+organizationId+':'+currentMembership?.role} focusOpportunityId={focusOpportunityId} memory={memory??ownMemory} organizationId={organizationId} gmailAllowed={currentMembership?.role==='owner'&&organizationId===ROMAX}/>;
}
