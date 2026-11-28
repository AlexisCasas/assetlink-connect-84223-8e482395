-- 4E.1 durable extraction contract only; no worker, file reads, scheduler or data backfill.
CREATE SCHEMA romax_extract_private;
REVOKE ALL ON SCHEMA romax_extract_private FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA romax_extract_private TO authenticated,service_role;

CREATE TABLE romax_extract_private.jobs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL, opportunity_id uuid NOT NULL, attachment_id uuid NOT NULL,
 source_attempt_id uuid NOT NULL REFERENCES romax_docs_private.download_attempts(id) ON DELETE RESTRICT,
 source_hash text NOT NULL CHECK(source_hash ~ '^[a-f0-9]{64}$'),
 source_size bigint NOT NULL CHECK(source_size BETWEEN 1 AND 10485760),
 source_mime text NOT NULL CHECK(source_mime IN ('application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')),
 parser_version text NOT NULL CHECK(parser_version ~ '^[a-zA-Z0-9._-]{1,80}$'),
 config_hash text NOT NULL CHECK(config_hash ~ '^[a-f0-9]{64}$'),
 generation integer NOT NULL CHECK(generation>0),
 requested_by uuid NOT NULL, acknowledged_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','running','succeeded','partial','unsupported','failed','cancelled')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 3),
 lease_token uuid, lease_until timestamptz, error_code text CHECK(error_code IN ('limit','no_text','unsupported_format','unsafe_structure','encrypted','timeout','worker_error','source_changed','cancelled','lease_expired')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), finished_at timestamptz,
 UNIQUE(organization_id,opportunity_id,attachment_id,id),
 UNIQUE(attachment_id,source_hash,parser_version,config_hash,generation),
 FOREIGN KEY(organization_id,opportunity_id,attachment_id) REFERENCES public.romax_opportunity_attachments(organization_id,opportunity_id,id) ON DELETE RESTRICT,
 CHECK((status='running')=(lease_token IS NOT NULL AND lease_until IS NOT NULL)),
 CHECK((status IN ('queued','running'))=(finished_at IS NULL))
);
CREATE UNIQUE INDEX romax_extract_active_document ON romax_extract_private.jobs(attachment_id) WHERE status IN ('queued','running');
CREATE INDEX romax_extract_job_scope ON romax_extract_private.jobs(organization_id,opportunity_id,created_at DESC,id);
CREATE TABLE romax_extract_private.runs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), job_id uuid NOT NULL UNIQUE REFERENCES romax_extract_private.jobs(id) ON DELETE RESTRICT,
 outcome text NOT NULL CHECK(outcome IN ('succeeded','partial','unsupported','failed','cancelled')),
 output_hash text NOT NULL CHECK(output_hash ~ '^[a-f0-9]{64}$'),
 completion_token uuid, reason text, created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE romax_extract_private.evidence_blocks(
 run_id uuid NOT NULL REFERENCES romax_extract_private.runs(id) ON DELETE RESTRICT,
 ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 1000),
 location jsonb NOT NULL CHECK(jsonb_typeof(location)='object' AND octet_length(location::text)<=1024),
 excerpt text NOT NULL CHECK(char_length(excerpt) BETWEEN 1 AND 4000),
 PRIMARY KEY(run_id,ordinal)
);
CREATE TABLE romax_extract_private.candidates(
 run_id uuid NOT NULL, ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 500),
 evidence_ordinal integer NOT NULL,
 kind text NOT NULL CHECK(kind IN ('requested_service','scope','technical_requirement','exclusion','risk','missing_information','deliverable','item','conflict')),
 proposal jsonb NOT NULL CHECK(jsonb_typeof(proposal)='object' AND octet_length(proposal::text)<=8192),
 PRIMARY KEY(run_id,ordinal),
 FOREIGN KEY(run_id,evidence_ordinal) REFERENCES romax_extract_private.evidence_blocks(run_id,ordinal) ON DELETE RESTRICT
);
CREATE TABLE romax_extract_private.review_events(
 run_id uuid NOT NULL, candidate_ordinal integer NOT NULL, revision integer NOT NULL CHECK(revision>0),
 actor_id uuid NOT NULL, decision text NOT NULL CHECK(decision IN ('accepted','corrected','rejected')),
 correction jsonb, partial_ack boolean NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(run_id,candidate_ordinal,revision),
 FOREIGN KEY(run_id,candidate_ordinal) REFERENCES romax_extract_private.candidates(run_id,ordinal) ON DELETE RESTRICT,
 CHECK((decision='corrected')=(correction IS NOT NULL))
);
CREATE TABLE romax_extract_private.receipts(
 organization_id uuid NOT NULL, opportunity_id uuid NOT NULL, actor_id uuid NOT NULL,
 request_id uuid NOT NULL, operation text NOT NULL CHECK(operation IN ('enqueue','review')),
 payload_hash text NOT NULL CHECK(payload_hash ~ '^[a-f0-9]{64}$'),
 response jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(organization_id,actor_id,request_id)
);
DO $$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['jobs','runs','evidence_blocks','candidates','review_events','receipts'] LOOP
  EXECUTE format('ALTER TABLE romax_extract_private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE romax_extract_private.%I FROM PUBLIC,anon,authenticated,service_role',t);
  IF t<>'jobs' THEN
   EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE OR TRUNCATE ON romax_extract_private.%I FOR EACH STATEMENT EXECUTE FUNCTION romax_docs_private.deny_event_mutation()',t);
  END IF;
 END LOOP;
END $$;

CREATE FUNCTION romax_extract_private.guard_job() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP<>'UPDATE' THEN RAISE EXCEPTION 'Extraction history is immutable' USING ERRCODE='42501'; END IF;
 IF OLD.finished_at IS NOT NULL OR (to_jsonb(OLD)-ARRAY['status','attempts','lease_token','lease_until','error_code','finished_at']) IS DISTINCT FROM
  (to_jsonb(NEW)-ARRAY['status','attempts','lease_token','lease_until','error_code','finished_at'])
 THEN RAISE EXCEPTION 'Extraction identity is immutable' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER guard_job BEFORE UPDATE OR DELETE ON romax_extract_private.jobs FOR EACH ROW EXECUTE FUNCTION romax_extract_private.guard_job();
CREATE TRIGGER guard_job_truncate BEFORE TRUNCATE ON romax_extract_private.jobs FOR EACH STATEMENT EXECUTE FUNCTION romax_docs_private.deny_event_mutation();

CREATE FUNCTION romax_extract_private.digest(p jsonb) RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path='' AS $$
 SELECT encode(sha256(convert_to(p::text,'UTF8')),'hex')
$$;
-- Authorization is checked at every transition, not just at enqueue. The service actor is
-- derived by the future authenticated broker, never accepted from an untrusted browser.
CREATE FUNCTION romax_extract_private.assert_scope(p_org uuid,p_op uuid,p_actor uuid,p_owner boolean)
RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM public.organizations WHERE id=p_org AND status='active' AND organization_type='provider_company' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.organization_members WHERE organization_id=p_org AND user_id=p_actor AND is_active
 AND (role='owner' OR (NOT p_owner AND role IN ('admin','manager','quote_manager'))) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.romax_opportunities WHERE organization_id=p_org AND id=p_op FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
END $$;
-- This first contract supports the current quarantine-backed pilot originals only.
-- No Storage reads: verify the persisted attempt and object metadata; broker must hash actual bytes.
CREATE FUNCTION romax_extract_private.source(p_org uuid,p_op uuid,p_doc uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE d public.romax_opportunity_attachments%ROWTYPE; a romax_docs_private.download_attempts%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.romax_opportunity_attachments WHERE organization_id=p_org AND opportunity_id=p_op AND id=p_doc FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 IF d.source_system<>'gmail' OR d.availability_status NOT IN ('quarantined','released_unscanned') OR d.scan_status<>'pending'
 OR d.processing_status<>'downloaded' OR d.restriction_code IS NOT NULL OR d.storage_path IS NOT NULL
 OR d.checksum_sha256 IS NULL OR d.size_bytes IS NULL OR d.size_bytes NOT BETWEEN 1 AND 10485760
 OR d.mime_type IS NULL OR d.mime_type NOT IN ('application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
 THEN RAISE EXCEPTION 'Source not eligible' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM romax_docs_private.download_attempts WHERE organization_id=p_org AND opportunity_id=p_op AND attachment_id=p_doc
 AND state='quarantined' AND checksum_sha256=d.checksum_sha256 AND size_bytes=d.size_bytes ORDER BY created_at DESC,id LIMIT 1 FOR SHARE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='romax-request-attachments' AND name=a.object_path AND metadata->>'size'=d.size_bytes::text)
 THEN RAISE EXCEPTION 'Source not available' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('attempt',a.id,'hash',d.checksum_sha256,'size',d.size_bytes,'mime',d.mime_type,'path',a.object_path);
END $$;
CREATE FUNCTION romax_extract_private.assert_source(j romax_extract_private.jobs) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE s jsonb;
BEGIN
 s:=romax_extract_private.source(j.organization_id,j.opportunity_id,j.attachment_id);
 IF s->>'attempt'<>j.source_attempt_id::text OR s->>'hash'<>j.source_hash OR (s->>'size')::bigint<>j.source_size OR s->>'mime'<>j.source_mime
 THEN RAISE EXCEPTION 'Source changed' USING ERRCODE='40001'; END IF;
 RETURN s;
END $$;

CREATE FUNCTION romax_extract_private.enqueue(p_org uuid,p_op uuid,p_actor uuid,p_doc uuid,p_parser text,p_config text,p_request uuid,p_ack boolean,p_reprocess boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j romax_extract_private.jobs%ROWTYPE; r romax_extract_private.receipts%ROWTYPE; s jsonb; h text; result jsonb; g integer;
BEGIN
 IF p_ack IS DISTINCT FROM true OR p_reprocess IS NULL OR p_request IS NULL OR p_parser IS NULL OR p_parser !~ '^[a-zA-Z0-9._-]{1,80}$' OR p_config IS NULL OR p_config !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'Invalid extraction request' USING ERRCODE='22023'; END IF;
 -- A small pilot uses one transaction lock for state transitions; no I/O under lock.
 PERFORM pg_advisory_xact_lock(734812946::bigint);
 PERFORM romax_extract_private.assert_scope(p_org,p_op,p_actor,true);
 s:=romax_extract_private.source(p_org,p_op,p_doc);
 h:=romax_extract_private.digest(jsonb_build_array('enqueue',p_op,p_doc,p_parser,p_config,p_ack,p_reprocess,s->>'hash'));
 SELECT * INTO r FROM romax_extract_private.receipts WHERE organization_id=p_org AND actor_id=p_actor AND request_id=p_request;
 IF FOUND THEN
  IF r.operation<>'enqueue' OR r.payload_hash<>h THEN RAISE EXCEPTION 'Request identity conflict' USING ERRCODE='22023'; END IF;
  RETURN r.response;
 END IF;
 SELECT * INTO j FROM romax_extract_private.jobs WHERE attachment_id=p_doc AND status IN ('queued','running');
 IF FOUND THEN
  IF p_reprocess OR j.source_hash<>s->>'hash' OR j.parser_version<>p_parser OR j.config_hash<>p_config
  THEN RAISE EXCEPTION 'Extraction already active' USING ERRCODE='40001'; END IF;
 ELSE
  SELECT * INTO j FROM romax_extract_private.jobs WHERE attachment_id=p_doc AND source_hash=s->>'hash' AND parser_version=p_parser AND config_hash=p_config ORDER BY generation DESC LIMIT 1;
  IF NOT FOUND OR p_reprocess THEN
   SELECT coalesce(max(generation),0)+1 INTO g FROM romax_extract_private.jobs WHERE attachment_id=p_doc AND source_hash=s->>'hash' AND parser_version=p_parser AND config_hash=p_config;
   -- Bound pending work; active jobs and per-document uniqueness are also enforced at claim.
   IF (SELECT count(*) FROM romax_extract_private.jobs WHERE organization_id=p_org AND status IN ('queued','running'))>=10
   OR (SELECT count(*) FROM romax_extract_private.jobs WHERE status IN ('queued','running'))>=100
   THEN RAISE EXCEPTION 'Extraction queue limit' USING ERRCODE='40001'; END IF;
   INSERT INTO romax_extract_private.jobs(organization_id,opportunity_id,attachment_id,source_attempt_id,source_hash,source_size,source_mime,parser_version,config_hash,generation,requested_by)
   VALUES(p_org,p_op,p_doc,(s->>'attempt')::uuid,s->>'hash',(s->>'size')::bigint,s->>'mime',p_parser,p_config,g,p_actor) RETURNING * INTO j;
  END IF;
 END IF;
 result:=jsonb_build_object('job_id',j.id,'generation',j.generation,'status',j.status);
 INSERT INTO romax_extract_private.receipts(organization_id,opportunity_id,actor_id,request_id,operation,payload_hash,response) VALUES(p_org,p_op,p_actor,p_request,'enqueue',h,result);
 RETURN result;
END $$;

CREATE FUNCTION romax_extract_private.claim(p_org uuid,p_op uuid,p_job uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j romax_extract_private.jobs%ROWTYPE; s jsonb; token uuid; now_at timestamptz;
BEGIN
 PERFORM pg_advisory_xact_lock(734812946::bigint);
 SELECT * INTO j FROM romax_extract_private.jobs WHERE id=p_job AND organization_id=p_org AND opportunity_id=p_op FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 PERFORM romax_extract_private.assert_scope(p_org,p_op,j.requested_by,true);
 s:=romax_extract_private.assert_source(j);
 now_at:=clock_timestamp();
 IF j.status NOT IN ('queued','running') OR (j.status='running' AND j.lease_until>now_at)
 THEN RAISE EXCEPTION 'Job not claimable' USING ERRCODE='40001'; END IF;
 IF j.attempts>=3 THEN
  UPDATE romax_extract_private.jobs SET status='failed',error_code='lease_expired',lease_token=NULL,lease_until=NULL,finished_at=now_at WHERE id=j.id;
  INSERT INTO romax_extract_private.runs(job_id,outcome,output_hash,reason) VALUES(j.id,'failed',romax_extract_private.digest(jsonb_build_array('failed','lease_expired')),'lease_expired');
  RETURN jsonb_build_object('status','failed');
 END IF;
 IF (SELECT count(*) FROM romax_extract_private.jobs WHERE id<>j.id AND organization_id=p_org AND status='running' AND lease_until>now_at)>=1
 OR (SELECT count(*) FROM romax_extract_private.jobs WHERE id<>j.id AND status='running' AND lease_until>now_at)>=2
 THEN RAISE EXCEPTION 'Worker concurrency limit' USING ERRCODE='40001'; END IF;
 token:=gen_random_uuid();
 UPDATE romax_extract_private.jobs SET status='running',attempts=attempts+1,lease_token=token,lease_until=now_at+interval '120 seconds',error_code=NULL WHERE id=j.id;
 RETURN jsonb_build_object('status','running','job_id',j.id,'lease',token,'source',s,'parser',j.parser_version,'config',j.config_hash);
END $$;

-- Strict, bounded evidence location and proposal contract. No arbitrary JSON fields or executable content.
CREATE FUNCTION romax_extract_private.validate_proposal(p jsonb) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR octet_length(p::text)>8192
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN ('description','quantity_raw','quantity','unit_raw','code_raw','specification','flags'))
 OR jsonb_typeof(p->'description') IS DISTINCT FROM 'string' OR char_length(btrim(p->>'description')) NOT BETWEEN 1 AND 2000
 OR EXISTS(SELECT 1 FROM jsonb_each(p) e WHERE e.key NOT IN ('flags','description') AND jsonb_typeof(e.value) NOT IN ('string','null'))
 OR coalesce(char_length(p->>'quantity_raw'),0)>100 OR coalesce(char_length(p->>'unit_raw'),0)>100
 OR coalesce(char_length(p->>'code_raw'),0)>100 OR coalesce(char_length(p->>'specification'),0)>2000
 OR (p->>'quantity' IS NOT NULL AND p->>'quantity' !~ '^[0-9]{1,12}(\.[0-9]{1,8})?$')
 THEN RAISE EXCEPTION 'Invalid candidate proposal' USING ERRCODE='22023'; END IF;
 IF p ? 'flags' THEN
  IF jsonb_typeof(p->'flags') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid flags' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(p->'flags')>12 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p->'flags') f WHERE jsonb_typeof(f)<>'string' OR f#>>'{}' NOT IN ('ambiguous_number','cached_formula','missing_formula_cache','hidden_row','merged_cell','subtotal','header','hierarchy','uncertain_table','conflict','missing_unit','partial'))
  THEN RAISE EXCEPTION 'Invalid flags' USING ERRCODE='22023'; END IF;
 END IF;
END $$;

CREATE FUNCTION romax_extract_private.finish(p_org uuid,p_op uuid,p_job uuid,p_lease uuid,p_source_hash text,p_status text,p_reason text,p_evidence jsonb,p_candidates jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j romax_extract_private.jobs%ROWTYPE; r romax_extract_private.runs%ROWTYPE; h text; e jsonb; c jsonb; loc jsonb; n integer; k integer; total integer;
BEGIN
 IF p_lease IS NULL OR p_source_hash IS NULL OR p_status IS NULL OR p_status NOT IN ('succeeded','partial','unsupported','failed','retry')
 OR (p_status='succeeded' AND p_reason IS NOT NULL) OR (p_status<>'succeeded' AND (p_reason IS NULL OR p_reason NOT IN ('limit','no_text','unsupported_format','unsafe_structure','encrypted','timeout','worker_error','source_changed')))
 OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'array' OR jsonb_typeof(p_candidates) IS DISTINCT FROM 'array'
 OR octet_length(p_evidence::text)+octet_length(p_candidates::text)>2097152
 THEN RAISE EXCEPTION 'Invalid extraction result' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_evidence)>1000 OR jsonb_array_length(p_candidates)>500
 OR (p_status NOT IN ('succeeded','partial') AND (p_evidence<>'[]'::jsonb OR p_candidates<>'[]'::jsonb))
 OR (p_status='succeeded' AND jsonb_array_length(p_evidence)=0)
 OR (p_status='retry' AND p_reason NOT IN ('timeout','worker_error'))
 THEN RAISE EXCEPTION 'Invalid extraction result' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(734812946::bigint);
 SELECT * INTO j FROM romax_extract_private.jobs WHERE id=p_job AND organization_id=p_org AND opportunity_id=p_op FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 PERFORM romax_extract_private.assert_scope(p_org,p_op,j.requested_by,true);
 PERFORM romax_extract_private.assert_source(j);
 IF p_source_hash<>j.source_hash THEN RAISE EXCEPTION 'Source hash mismatch' USING ERRCODE='40001'; END IF;
 h:=romax_extract_private.digest(jsonb_build_array(p_status,p_reason,p_evidence,p_candidates));
 SELECT * INTO r FROM romax_extract_private.runs WHERE job_id=j.id;
 IF FOUND AND r.completion_token=p_lease AND r.output_hash=h THEN RETURN jsonb_build_object('run_id',r.id,'status',r.outcome,'unchanged',true); END IF;
 IF j.status<>'running' OR j.lease_token IS DISTINCT FROM p_lease OR j.lease_until<=clock_timestamp()
 THEN RAISE EXCEPTION 'Stale extraction lease' USING ERRCODE='40001'; END IF;
 IF p_status='retry' AND j.attempts<3 THEN
  UPDATE romax_extract_private.jobs SET status='queued',lease_token=NULL,lease_until=NULL,error_code=p_reason WHERE id=j.id;
  RETURN jsonb_build_object('status','queued');
 END IF;
 IF p_status='retry' THEN p_status:='failed'; END IF;
 total:=0;
 FOR e IN SELECT value FROM jsonb_array_elements(p_evidence) LOOP
  IF jsonb_typeof(e)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(e) x WHERE x NOT IN ('location','excerpt'))
   OR jsonb_typeof(e->'excerpt') IS DISTINCT FROM 'string' OR char_length(e->>'excerpt') NOT BETWEEN 1 AND 4000
   OR jsonb_typeof(e->'location') IS DISTINCT FROM 'object' OR octet_length((e->'location')::text)>1024
  THEN RAISE EXCEPTION 'Invalid evidence' USING ERRCODE='22023'; END IF;
  loc:=e->'location';total:=total+char_length(e->>'excerpt');
  IF j.source_mime='application/pdf' THEN
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(loc) x WHERE x NOT IN ('page','block'))
   OR jsonb_typeof(loc->'page') IS DISTINCT FROM 'number' OR (loc->>'page') !~ '^[1-9][0-9]{0,2}$' OR (loc->>'page')::int>100
   OR jsonb_typeof(loc->'block') IS DISTINCT FROM 'number' OR (loc->>'block') !~ '^[1-9][0-9]{0,5}$'
   THEN RAISE EXCEPTION 'Invalid PDF location' USING ERRCODE='22023'; END IF;
  ELSE
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(loc) x WHERE x NOT IN ('sheet','sheet_index','cells'))
   OR jsonb_typeof(loc->'sheet') IS DISTINCT FROM 'string' OR char_length(loc->>'sheet') NOT BETWEEN 1 AND 31
   OR jsonb_typeof(loc->'sheet_index') IS DISTINCT FROM 'number' OR (loc->>'sheet_index') !~ '^[1-9][0-9]?$' OR (loc->>'sheet_index')::int>20
   OR jsonb_typeof(loc->'cells') IS DISTINCT FROM 'string' OR (loc->>'cells') !~ '^[A-Z]{1,3}[1-9][0-9]{0,6}(:[A-Z]{1,3}[1-9][0-9]{0,6})?$'
   THEN RAISE EXCEPTION 'Invalid XLSX location' USING ERRCODE='22023'; END IF;
  END IF;
 END LOOP;
 IF total>200000 THEN RAISE EXCEPTION 'Evidence text limit' USING ERRCODE='22023'; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(p_candidates) LOOP
  IF jsonb_typeof(c)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(c) x WHERE x NOT IN ('kind','evidence_ordinal','proposal'))
   OR c->>'kind' IS NULL OR c->>'kind' NOT IN ('requested_service','scope','technical_requirement','exclusion','risk','missing_information','deliverable','item','conflict')
   OR jsonb_typeof(c->'evidence_ordinal') IS DISTINCT FROM 'number' OR (c->>'evidence_ordinal') !~ '^[1-9][0-9]{0,3}$'
   OR (c->>'evidence_ordinal')::int>jsonb_array_length(p_evidence)
  THEN RAISE EXCEPTION 'Invalid candidate evidence' USING ERRCODE='22023'; END IF;
  PERFORM romax_extract_private.validate_proposal(c->'proposal');
 END LOOP;
 INSERT INTO romax_extract_private.runs(job_id,outcome,output_hash,completion_token,reason) VALUES(j.id,p_status,h,p_lease,p_reason) RETURNING * INTO r;
 n:=0;FOR e IN SELECT value FROM jsonb_array_elements(p_evidence) LOOP n:=n+1;INSERT INTO romax_extract_private.evidence_blocks VALUES(r.id,n,e->'location',e->>'excerpt');END LOOP;
 k:=0;FOR c IN SELECT value FROM jsonb_array_elements(p_candidates) LOOP k:=k+1;INSERT INTO romax_extract_private.candidates VALUES(r.id,k,(c->>'evidence_ordinal')::int,c->>'kind',c->'proposal');END LOOP;
 UPDATE romax_extract_private.jobs SET status=p_status,error_code=p_reason,lease_token=NULL,lease_until=NULL,finished_at=clock_timestamp() WHERE id=j.id;
 RETURN jsonb_build_object('run_id',r.id,'status',r.outcome,'unchanged',false);
END $$;

CREATE FUNCTION romax_extract_private.cancel(p_org uuid,p_op uuid,p_actor uuid,p_job uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j romax_extract_private.jobs%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(734812946::bigint);
 PERFORM romax_extract_private.assert_scope(p_org,p_op,p_actor,true);
 SELECT * INTO j FROM romax_extract_private.jobs WHERE id=p_job AND organization_id=p_org AND opportunity_id=p_op FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 IF j.status='cancelled' THEN RETURN jsonb_build_object('status','cancelled'); END IF;
 IF j.status NOT IN ('queued','running') THEN RAISE EXCEPTION 'Job already terminal' USING ERRCODE='40001'; END IF;
 INSERT INTO romax_extract_private.runs(job_id,outcome,output_hash,reason) VALUES(j.id,'cancelled',romax_extract_private.digest(jsonb_build_array('cancelled',p_actor)),'cancelled');
 UPDATE romax_extract_private.jobs SET status='cancelled',error_code='cancelled',lease_token=NULL,lease_until=NULL,finished_at=clock_timestamp() WHERE id=j.id;
 RETURN jsonb_build_object('status','cancelled');
END $$;

CREATE FUNCTION romax_extract_private.review(p_org uuid,p_op uuid,p_actor uuid,p_run uuid,p_candidate integer,p_expected integer,p_request uuid,p_decision text,p_correction jsonb,p_partial_ack boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j romax_extract_private.jobs%ROWTYPE; r romax_extract_private.receipts%ROWTYPE; current_rev integer; h text; result jsonb;
BEGIN
 IF p_request IS NULL OR p_expected IS NULL OR p_expected<0 OR p_partial_ack IS NULL OR p_decision IS NULL OR p_decision NOT IN ('accepted','corrected','rejected')
 OR ((p_decision='corrected') IS DISTINCT FROM (p_correction IS NOT NULL)) THEN RAISE EXCEPTION 'Invalid review' USING ERRCODE='22023'; END IF;
 IF p_decision='corrected' THEN PERFORM romax_extract_private.validate_proposal(p_correction); END IF;
 PERFORM pg_advisory_xact_lock(734812946::bigint);
 PERFORM romax_extract_private.assert_scope(p_org,p_op,p_actor,false);
 SELECT x.* INTO j FROM romax_extract_private.jobs x JOIN romax_extract_private.runs y ON y.job_id=x.id WHERE y.id=p_run AND x.organization_id=p_org AND x.opportunity_id=p_op;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 IF j.status NOT IN ('succeeded','partial') OR (j.status='partial' AND NOT p_partial_ack)
 THEN RAISE EXCEPTION 'Review not eligible' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM romax_extract_private.candidates WHERE run_id=p_run AND ordinal=p_candidate;
 IF NOT FOUND THEN RAISE EXCEPTION 'Candidate unavailable' USING ERRCODE='22023'; END IF;
 h:=romax_extract_private.digest(jsonb_build_array('review',p_op,p_run,p_candidate,p_expected,p_decision,p_correction,p_partial_ack));
 SELECT * INTO r FROM romax_extract_private.receipts WHERE organization_id=p_org AND actor_id=p_actor AND request_id=p_request;
 IF FOUND THEN
  IF r.operation<>'review' OR r.payload_hash<>h THEN RAISE EXCEPTION 'Request identity conflict' USING ERRCODE='22023'; END IF;
  RETURN r.response;
 END IF;
 SELECT coalesce(max(revision),0) INTO current_rev FROM romax_extract_private.review_events WHERE run_id=p_run AND candidate_ordinal=p_candidate;
 IF current_rev<>p_expected THEN RAISE EXCEPTION 'Review version conflict' USING ERRCODE='40001'; END IF;
 IF EXISTS(SELECT 1 FROM romax_extract_private.review_events WHERE run_id=p_run AND candidate_ordinal=p_candidate AND revision=current_rev AND decision=p_decision AND correction IS NOT DISTINCT FROM p_correction AND partial_ack=p_partial_ack)
 THEN result:=jsonb_build_object('revision',current_rev,'unchanged',true);
 ELSE
  INSERT INTO romax_extract_private.review_events(run_id,candidate_ordinal,revision,actor_id,decision,correction,partial_ack) VALUES(p_run,p_candidate,current_rev+1,p_actor,p_decision,p_correction,p_partial_ack);
  result:=jsonb_build_object('revision',current_rev+1,'unchanged',false);
 END IF;
 INSERT INTO romax_extract_private.receipts(organization_id,opportunity_id,actor_id,request_id,operation,payload_hash,response) VALUES(p_org,p_op,p_actor,p_request,'review',h,result);
 RETURN result;
END $$;

-- Read-only projections use auth.uid, never trust an actor argument. No paths, leases, remote IDs.
CREATE FUNCTION romax_extract_private.read_jobs(p_org uuid,p_op uuid,p_offset integer,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM romax_extract_private.assert_scope(p_org,p_op,auth.uid(),false);
 IF p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Invalid page' USING ERRCODE='22023'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC,t.job_id),'[]'::jsonb) FROM
 (SELECT j.id job_id,j.attachment_id,j.generation,j.status,j.parser_version,j.source_hash,j.attempts,j.created_at,j.finished_at,j.error_code,r.id run_id
 FROM romax_extract_private.jobs j LEFT JOIN romax_extract_private.runs r ON r.job_id=j.id WHERE j.organization_id=p_org AND j.opportunity_id=p_op
 ORDER BY j.created_at DESC,j.id OFFSET p_offset LIMIT p_limit) t);
END $$;
CREATE FUNCTION romax_extract_private.read_candidates(p_org uuid,p_op uuid,p_run uuid,p_after integer,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM romax_extract_private.assert_scope(p_org,p_op,auth.uid(),false);
 IF p_after IS NULL OR p_after NOT BETWEEN 0 AND 500 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Invalid page' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM romax_extract_private.jobs j JOIN romax_extract_private.runs r ON r.job_id=j.id WHERE r.id=p_run AND j.organization_id=p_org AND j.opportunity_id=p_op)
 THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.ordinal),'[]'::jsonb) FROM
 (SELECT c.ordinal,c.kind,c.proposal,e.location,e.excerpt,coalesce(v.revision,0) revision,coalesce(v.decision,'pending') decision,v.correction
 FROM romax_extract_private.candidates c JOIN romax_extract_private.evidence_blocks e ON e.run_id=c.run_id AND e.ordinal=c.evidence_ordinal
 LEFT JOIN LATERAL (SELECT revision,decision,correction FROM romax_extract_private.review_events v WHERE v.run_id=c.run_id AND v.candidate_ordinal=c.ordinal ORDER BY revision DESC LIMIT 1) v ON true
 WHERE c.run_id=p_run AND c.ordinal>p_after ORDER BY c.ordinal LIMIT p_limit) t);
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA romax_extract_private FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION romax_extract_private.enqueue(uuid,uuid,uuid,uuid,text,text,uuid,boolean,boolean) TO service_role;
CREATE FUNCTION public.romax_extract_enqueue(p_org uuid,p_op uuid,p_actor uuid,p_doc uuid,p_parser text,p_config text,p_request uuid,p_ack boolean,p_reprocess boolean) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT romax_extract_private.enqueue(p_org,p_op,p_actor,p_doc,p_parser,p_config,p_request,p_ack,p_reprocess) $$;
REVOKE ALL ON FUNCTION public.romax_extract_enqueue(uuid,uuid,uuid,uuid,text,text,uuid,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_extract_enqueue(uuid,uuid,uuid,uuid,text,text,uuid,boolean,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION romax_extract_private.claim(uuid,uuid,uuid) TO service_role;
CREATE FUNCTION public.romax_extract_claim(p_org uuid,p_op uuid,p_job uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT romax_extract_private.claim(p_org,p_op,p_job) $$;
REVOKE ALL ON FUNCTION public.romax_extract_claim(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_extract_claim(uuid,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION romax_extract_private.finish(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb) TO service_role;
CREATE FUNCTION public.romax_extract_finish(p_org uuid,p_op uuid,p_job uuid,p_lease uuid,p_source_hash text,p_status text,p_reason text,p_evidence jsonb,p_candidates jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT romax_extract_private.finish(p_org,p_op,p_job,p_lease,p_source_hash,p_status,p_reason,p_evidence,p_candidates) $$;
REVOKE ALL ON FUNCTION public.romax_extract_finish(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_extract_finish(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION romax_extract_private.cancel(uuid,uuid,uuid,uuid) TO service_role;
CREATE FUNCTION public.romax_extract_cancel(p_org uuid,p_op uuid,p_actor uuid,p_job uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT romax_extract_private.cancel(p_org,p_op,p_actor,p_job) $$;
REVOKE ALL ON FUNCTION public.romax_extract_cancel(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_extract_cancel(uuid,uuid,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION romax_extract_private.review(uuid,uuid,uuid,uuid,integer,integer,uuid,text,jsonb,boolean) TO service_role;
CREATE FUNCTION public.romax_extract_review(p_org uuid,p_op uuid,p_actor uuid,p_run uuid,p_candidate integer,p_expected integer,p_request uuid,p_decision text,p_correction jsonb,p_partial_ack boolean) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT romax_extract_private.review(p_org,p_op,p_actor,p_run,p_candidate,p_expected,p_request,p_decision,p_correction,p_partial_ack) $$;
REVOKE ALL ON FUNCTION public.romax_extract_review(uuid,uuid,uuid,uuid,integer,integer,uuid,text,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_extract_review(uuid,uuid,uuid,uuid,integer,integer,uuid,text,jsonb,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION romax_extract_private.read_jobs(uuid,uuid,integer,integer) TO authenticated;
CREATE FUNCTION public.romax_extract_read_jobs(p_org uuid,p_op uuid,p_offset integer,p_limit integer) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT romax_extract_private.read_jobs(p_org,p_op,p_offset,p_limit) $$;
REVOKE ALL ON FUNCTION public.romax_extract_read_jobs(uuid,uuid,integer,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_extract_read_jobs(uuid,uuid,integer,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION romax_extract_private.read_candidates(uuid,uuid,uuid,integer,integer) TO authenticated;
CREATE FUNCTION public.romax_extract_read_candidates(p_org uuid,p_op uuid,p_run uuid,p_after integer,p_limit integer) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT romax_extract_private.read_candidates(p_org,p_op,p_run,p_after,p_limit) $$;
REVOKE ALL ON FUNCTION public.romax_extract_read_candidates(uuid,uuid,uuid,integer,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_extract_read_candidates(uuid,uuid,uuid,integer,integer) TO authenticated;
