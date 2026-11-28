import {dateInLima,normalize,type Opportunity,type Client,type Site,type Contact} from './romaxRequestList.ts';
export const specialties:Record<string,string>={civil:'Civil',electrical:'Eléctrica',sanitary:'Sanitaria',hvac:'Mecánica / HVAC',electromechanical:'Electromecánica',safety:'Seguridad / PDR',multi:'Multiservicio',other:'Otra'};
export type Provenance={source:'manual'|'gmail_reviewed'|'master_reviewed';evidence?:string};
export type DeadlineObservation={key:string;raw:string;date:string|null;time:string|null;kind:string;ambiguous:boolean};
export type DeadlineDecision=DeadlineObservation & {decision:'pending'|'accepted'|'rejected'};
export type Snapshot={title:string|null;summary:string|null;scope:string|null;restrictions:string|null;reference:string|null;reference_kind:string|null;specialty:string|null;deadline_date:string|null;deadline_time:string|null;deadline_note:string|null;client_id:string|null;site_id:string|null;contact_id:string|null;additional_contacts:string[];deadline_observations:DeadlineDecision[];provenance:Record<string,Provenance>};
export type Review={organization_id:string;opportunity_id:string;revision:number;reviewed_at:string;snapshot:Snapshot};
export type Proposal={subject:string;sender:string|null;excerpt:string;reference:string|null;reference_kind:string;reference_verified:boolean;deadlines:DeadlineObservation[];source_received_at:string;parser:string;category:string;proof:string};
export function initialSnapshot(o:Opportunity,review?:Review):Snapshot {
 return review?{...review.snapshot,client_id:o.commercial_client_id,site_id:o.commercial_site_id,contact_id:o.commercial_contact_id,additional_contacts:[...review.snapshot.additional_contacts],deadline_observations:[...(review.snapshot.deadline_observations??[])],provenance:{...review.snapshot.provenance}}:
 {title:null,summary:null,scope:null,restrictions:null,reference:null,reference_kind:null,specialty:null,deadline_date:null,deadline_time:null,deadline_note:null,client_id:o.commercial_client_id,site_id:o.commercial_site_id,contact_id:o.commercial_contact_id,additional_contacts:[],deadline_observations:[],provenance:{}};
}
export function changeField<K extends keyof Snapshot>(s:Snapshot,key:K,value:Snapshot[K],source:Provenance={source:'manual'}):Snapshot {
 const next={...s,[key]:value,provenance:{...s.provenance,[key]:source}};
 if(key==='client_id'&&s.client_id!==value){next.site_id=null;next.contact_id=null;next.additional_contacts=[];for(const k of ['site_id','contact_id','additional_contacts'])next.provenance[k]={source:'manual'};}
 if(key==='contact_id'&&typeof value==='string'&&next.additional_contacts.includes(value)){next.additional_contacts=next.additional_contacts.filter(id=>id!==value);next.provenance.additional_contacts={source:'manual'};}
 if(key==='site_id'&&s.site_id!==value){next.contact_id=null;next.additional_contacts=[];for(const k of ['contact_id','additional_contacts'])next.provenance[k]={source:'manual'};}
 if(['deadline_date','deadline_time','deadline_note'].includes(key)&&source.source!=='gmail_reviewed'){for(const field of ['deadline_date','deadline_time','deadline_note'])next.provenance[field]={source:'manual'};}
 if(key==='deadline_date'&&!value){next.deadline_time=null;next.provenance.deadline_time={source:'manual'};}
 if(key==='reference'&&!value){next.reference_kind=null;next.provenance.reference_kind={source:'manual'};}
 return next;
}
export function recordDeadlineDecision(s:Snapshot,event:DeadlineObservation,decision:DeadlineDecision['decision']):Snapshot{
 if(decision==='accepted'&&(event.ambiguous||!event.date))return s;
 if(s.deadline_observations.some(x=>x.key===event.key&&x.decision===decision))return s;
 return {...s,deadline_observations:[...s.deadline_observations,{...event,decision}]};
}
export const deadlineStatus=(o:Opportunity,s:Snapshot|undefined,now=new Date()):'none'|'near'|'overdue'|'later'|'closed'=>{
 if(['quoted','discarded'].includes(o.status))return 'closed';
 if(!s?.deadline_date)return 'none';
 const day=dateInLima(now.toISOString())!;
 if(s.deadline_time?Date.parse(s.deadline_date+'T'+s.deadline_time+':00-05:00')<now.getTime():s.deadline_date<day)return 'overdue';
 const limit=new Date(day+'T00:00:00Z');limit.setUTCDate(limit.getUTCDate()+3);
 return s.deadline_date<=limit.toISOString().slice(0,10)?'near':'later';
};
const terms=(s:string)=>normalize(s).replace(/[^a-z0-9]+/g,' ').trim();
const phrase=(hay:string,needle:string)=>needle.length>=3&&(' '+terms(hay)+' ').includes(' '+needle+' ');
export function matchSuggestions(text:string,sender:string|null,clients:Client[],sites:Site[],contacts:Contact[],clientId:string|null){
 const email=normalize(sender);const emailContacts=contacts.filter(c=>c.is_active&&email&&normalize(c.email)===email);
 const clientMatches=clients.filter(c=>c.is_active&&([c.business_name,c.legal_name,c.commercial_code].some(x=>!!x&&phrase(text,terms(x)))||emailContacts.some(x=>x.commercial_client_id===c.id)));
 return {clients:clientMatches,sites:sites.filter(s=>s.is_active&&s.commercial_client_id===clientId&&[s.site_name,s.site_code].some(x=>!!x&&phrase(text,terms(x)))),
 contacts:emailContacts.filter(c=>c.commercial_client_id===clientId)};
}
export function deadlineHistory(reviews:Review[]){
 const result:Review[]=[];let prior='';
 for(const review of [...reviews].sort((a,b)=>a.revision-b.revision)){
 const s=review.snapshot;const current=JSON.stringify([s.deadline_date,s.deadline_time,s.deadline_note]);
 if(current!==prior&&(s.deadline_date||s.deadline_note||result.length))result.push(review);prior=current;
 }return result;
}
