import test from 'node:test';
import assert from 'node:assert/strict';
import {canRetain,canDownloadUnscanned,documentStatus,documentFilename,selectionWithinLimit} from '../src/components/provider/romaxDocuments.ts';
import type {Attachment} from '../src/components/provider/romaxRequestList.ts';
const base:Attachment={id:'a',opportunity_id:'op',filename:'TDR.pdf',mime_type:'application/pdf',size_bytes:1024,processing_status:'detected',created_at:'2026-11-28',source_system:'gmail',source_locator_kind:'attachment_id',availability_status:'metadata_only',scan_status:'not_scanned'};
test('4D only eligible selected external documents can be retained',()=>{
 assert.equal(canRetain(base),true);assert.equal(canRetain({...base,source_locator_kind:'mime_part'}),false);assert.equal(canRetain({...base,restriction_code:'size_limit'}),false);
 assert.equal(selectionWithinLimit([base,base]),false);assert.equal(selectionWithinLimit([]),false);
 assert.equal(selectionWithinLimit(Array.from({length:3},(_,i)=>({...base,id:String(i),size_bytes:10485760}))),false);
 assert.equal(selectionWithinLimit([base]),true);
});
test('4D quarantine/release remains unscanned, Office and failed documents denied',()=>{
 const q={...base,availability_status:'quarantined',scan_status:'pending',processing_status:'downloaded'};
 assert.equal(canDownloadUnscanned(q),true);assert.equal(canDownloadUnscanned({...q,availability_status:'released_unscanned'}),true);
 assert.equal(canDownloadUnscanned({...q,mime_type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}),false);
 assert.equal(canDownloadUnscanned({...q,availability_status:'failed'}),false);
 assert.match(documentStatus({...q,availability_status:'released_unscanned'}),/sin escaneo/);
});
test('4D filename is forced to expected safe extension and strips path controls',()=>{
 assert.equal(documentFilename({...base,filename:'../evil\u202e.exe'}),'.._evil_.pdf');
 assert.equal(documentFilename({...base,filename:'TDR.pdf'}),'TDR.pdf');
 assert.equal(documentFilename({...base,filename:'folder\\nested/file.pdf'}),'folder_nested_file.pdf');
});
