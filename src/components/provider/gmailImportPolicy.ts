// Presentation guard only. The server repeats authorization and eligibility checks.
export function canConfirmGmailImport(candidate: {import_policy?:string;category:string;confirmation_token?:string|null;body_limited?:boolean;existing_status?:string|null;deadline_events?:{status:string}[]}):boolean {
  return candidate.import_policy==='new_candidate'&&candidate.category==='quote_request'&&
    !candidate.body_limited&&!candidate.existing_status&&!candidate.deadline_events?.some(x=>x.status==='ambiguous')&&
    typeof candidate.confirmation_token==='string'&&candidate.confirmation_token.length>0;
}
