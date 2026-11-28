import {test} from 'node:test';
import assert from 'node:assert/strict';
import {canConfirmGmailImport} from '../src/components/provider/gmailImportPolicy.ts';
const candidate={category:'quote_request',import_policy:'new_candidate',confirmation_token:'synthetic'};
test('only eligible candidate with server confirmation may open review',()=>{
  assert.equal(canConfirmGmailImport(candidate),true);
  for(const import_policy of ['link_existing','review_required','not_importable',undefined])assert.equal(canConfirmGmailImport({...candidate,import_policy}),false);
  assert.equal(canConfirmGmailImport({...candidate,confirmation_token:null}),false);
  assert.equal(canConfirmGmailImport({...candidate,category:'quoted'}),false);
  assert.equal(canConfirmGmailImport({...candidate,existing_status:'new'}),false);
  assert.equal(canConfirmGmailImport({...candidate,body_limited:true}),false);
  assert.equal(canConfirmGmailImport({...candidate,deadline_events:[{status:'ambiguous'}]}),false);
});
