import type { Attachment } from './romaxRequestList';
const max=10485760;
const extensions:Record<string,string>={'application/pdf':'.pdf','image/jpeg':'.jpg','image/png':'.png','text/plain':'.txt'};
export const canRetain=(a:Attachment)=>a.source_system==='gmail'&&a.source_locator_kind==='attachment_id'&&['metadata_only','failed','queued'].includes(a.availability_status??'')&&!a.restriction_code&&typeof a.size_bytes==='number'&&a.size_bytes>0&&a.size_bytes<=max;
export const canDownloadUnscanned=(a:Attachment)=>a.source_system==='gmail'&&['quarantined','released_unscanned'].includes(a.availability_status??'')&&a.scan_status==='pending'&&a.processing_status==='downloaded'&&!a.restriction_code&&Object.hasOwn(extensions,a.mime_type??'');
export const selectionWithinLimit=(rows:Attachment[])=>rows.length>=1&&rows.length<=5&&new Set(rows.map(a=>a.id)).size===rows.length&&rows.every(canRetain)&&rows.reduce((n,a)=>n+(a.size_bytes??0),0)<=26214400;
export function documentFilename(a:Attachment){const ext=extensions[a.mime_type??'']??'.bin';const name=a.filename.normalize('NFC').replace(/[\p{Cc}\p{Cf}\p{Cs}\/\\:*?"<>|]/gu,'_').trim().replace(/\.[^.]+$/,'').slice(0,180).replace(/[. ]+$/,'');return (name||'documento')+ext;}
export function documentStatus(a:Attachment){return ({metadata_only:'Detectado',queued:'En cola / reintento',quarantined:'Conservado · sin escaneo',released_unscanned:'Descargable · sin escaneo',available:'Disponible',blocked:'Bloqueado',failed:'Error / reintentar'} as Record<string,string>)[a.availability_status??'']??'Estado anterior';}
