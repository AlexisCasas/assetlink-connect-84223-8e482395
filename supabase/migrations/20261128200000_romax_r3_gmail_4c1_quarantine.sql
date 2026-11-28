-- R3-GMAIL.4C.1: quarantine only. No clean verdict, public access or object release.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('romax-request-attachments','romax-request-attachments',false,10485760,ARRAY['application/octet-stream']::text[]);
CREATE POLICY romax_docs_storage_deny_client ON storage.objects AS RESTRICTIVE FOR ALL TO anon,authenticated
USING(bucket_id<>'romax-request-attachments') WITH CHECK(bucket_id<>'romax-request-attachments');

CREATE TABLE romax_docs_private.download_attempts(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL, opportunity_id uuid NOT NULL, attachment_id uuid NOT NULL,
  actor_id uuid NOT NULL, connection_at timestamptz NOT NULL,
  lease_until timestamptz NOT NULL, object_path text NOT NULL UNIQUE,
  state text NOT NULL DEFAULT 'leased' CHECK(state IN ('leased','quarantined','failed','expired')),
  checksum_sha256 text CHECK(checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes bigint CHECK(size_bytes IS NULL OR size_bytes BETWEEN 1 AND 10485760),
  error_code text CHECK(error_code IS NULL OR error_code IN ('source_changed','invalid_binary','storage_uncertain','remote_error','lease_expired')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(), finished_at timestamptz,
  FOREIGN KEY(organization_id,opportunity_id,attachment_id)
    REFERENCES public.romax_opportunity_attachments(organization_id,opportunity_id,id) ON DELETE RESTRICT,
  CHECK(object_path='quarantine/'||organization_id::text||'/'||opportunity_id::text||'/'||attachment_id::text||'/'||id::text),
  CHECK(state<>'quarantined' OR (checksum_sha256 IS NOT NULL AND size_bytes IS NOT NULL AND finished_at IS NOT NULL))
);
CREATE UNIQUE INDEX romax_docs_one_active_attempt ON romax_docs_private.download_attempts(attachment_id) WHERE state='leased';
ALTER TABLE romax_docs_private.download_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON romax_docs_private.download_attempts FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX romax_docs_attempt_document_idx ON romax_docs_private.download_attempts(organization_id,opportunity_id,attachment_id,created_at);

-- Only trusted Edge calls. The actor is derived from authenticated user, never a browser field.
CREATE FUNCTION romax_docs_private.assert_download_access(p_org uuid,p_opportunity uuid,p_actor uuid,p_connection_at timestamptz)
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE v_thread text;
BEGIN
  IF p_org IS NULL OR p_opportunity IS NULL OR p_actor IS NULL OR p_connection_at IS NULL THEN
    RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.romax_gmail_connections WHERE organization_id=p_org AND status='connected' AND connected_at=p_connection_at FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.organizations WHERE id=p_org AND status='active' AND organization_type='provider_company' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.organization_members WHERE organization_id=p_org AND user_id=p_actor AND role='owner' AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT source_thread_id INTO v_thread FROM public.romax_opportunities WHERE id=p_opportunity AND organization_id=p_org AND source_system='gmail' FOR UPDATE;
  IF NOT FOUND OR v_thread IS NULL THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  RETURN v_thread;
END; $$;
REVOKE ALL ON FUNCTION romax_docs_private.assert_download_access(uuid,uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION romax_docs_private.claim_downloads(p_org uuid,p_opportunity uuid,p_actor uuid,p_connection_at timestamptz,p_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_thread text; v_doc public.romax_opportunity_attachments%ROWTYPE; v_attempt uuid; v_path text;
  v_total bigint; v_count integer; v_claims jsonb:='[]'::jsonb; v_skip integer:=0; v_now timestamptz;
BEGIN
  IF p_ids IS NULL OR cardinality(p_ids) NOT BETWEEN 1 AND 5 OR array_position(p_ids,NULL) IS NOT NULL
     OR (SELECT count(DISTINCT x) FROM unnest(p_ids) x)<>cardinality(p_ids)
  THEN RAISE EXCEPTION 'Invalid download selection' USING ERRCODE='22023'; END IF;
  v_thread:=romax_docs_private.assert_download_access(p_org,p_opportunity,p_actor,p_connection_at);
  SELECT count(*),coalesce(sum(size_bytes),0) INTO v_count,v_total FROM public.romax_opportunity_attachments
    WHERE organization_id=p_org AND opportunity_id=p_opportunity AND id=ANY(p_ids) AND source_system='gmail'
      AND source_locator_kind='attachment_id' AND size_bytes BETWEEN 1 AND 10485760
      AND restriction_code IS NULL AND availability_status IN ('metadata_only','queued','failed','quarantined','available');
  IF v_count<>cardinality(p_ids) OR v_total>26214400 THEN RAISE EXCEPTION 'Invalid or ineligible download selection' USING ERRCODE='22023'; END IF;
  FOR v_doc IN SELECT * FROM public.romax_opportunity_attachments WHERE organization_id=p_org AND opportunity_id=p_opportunity AND id=ANY(p_ids)
     ORDER BY id FOR UPDATE LOOP
    IF v_doc.availability_status IN ('quarantined','available') THEN v_skip:=v_skip+1; CONTINUE; END IF;
    v_now:=clock_timestamp();
    IF EXISTS(SELECT 1 FROM romax_docs_private.download_attempts WHERE attachment_id=v_doc.id AND state='leased' AND lease_until>v_now)
      THEN RAISE EXCEPTION 'Download already reserved' USING ERRCODE='40001'; END IF;
    UPDATE romax_docs_private.download_attempts SET state='expired',error_code='lease_expired',finished_at=v_now
      WHERE attachment_id=v_doc.id AND state='leased';
    v_attempt:=gen_random_uuid();
    v_path:='quarantine/'||p_org::text||'/'||p_opportunity::text||'/'||v_doc.id::text||'/'||v_attempt::text;
    INSERT INTO romax_docs_private.download_attempts(id,organization_id,opportunity_id,attachment_id,actor_id,connection_at,lease_until,object_path)
      VALUES(v_attempt,p_org,p_opportunity,v_doc.id,p_actor,p_connection_at,v_now+interval '180 seconds',v_path);
    UPDATE public.romax_opportunity_attachments SET availability_status='queued',processing_status='queued',scan_status='not_scanned'
      WHERE id=v_doc.id;
    INSERT INTO romax_docs_private.attachment_events(organization_id,opportunity_id,attachment_id,actor_id,operation,previous_state,next_state)
      VALUES(p_org,p_opportunity,v_doc.id,p_actor,'state_changed',v_doc.availability_status,'queued');
    v_claims:=v_claims||jsonb_build_array(jsonb_build_object('id',v_doc.id,'attempt',v_attempt,'path',v_path,'thread',v_thread,
      'message',v_doc.source_message_id,'locator',v_doc.source_attachment_id,'filename',v_doc.filename,'mime',v_doc.mime_type,'size',v_doc.size_bytes));
  END LOOP;
  RETURN jsonb_build_object('claims',v_claims,'skipped',v_skip);
END; $$;
REVOKE ALL ON FUNCTION romax_docs_private.claim_downloads(uuid,uuid,uuid,timestamptz,uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION romax_docs_private.claim_downloads(uuid,uuid,uuid,timestamptz,uuid[]) TO service_role;
CREATE FUNCTION public.romax_claim_attachment_downloads(p_org uuid,p_opportunity uuid,p_actor uuid,p_connection_at timestamptz,p_ids uuid[])
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT romax_docs_private.claim_downloads(p_org,p_opportunity,p_actor,p_connection_at,p_ids);
$$;
REVOKE ALL ON FUNCTION public.romax_claim_attachment_downloads(uuid,uuid,uuid,timestamptz,uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_claim_attachment_downloads(uuid,uuid,uuid,timestamptz,uuid[]) TO service_role;

CREATE FUNCTION romax_docs_private.finish_download(p_org uuid,p_opportunity uuid,p_actor uuid,p_connection_at timestamptz,
  p_attachment uuid,p_attempt uuid,p_hash text,p_size bigint,p_error text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_doc public.romax_opportunity_attachments%ROWTYPE; v_attempt romax_docs_private.download_attempts%ROWTYPE; v_state text;
BEGIN
  PERFORM romax_docs_private.assert_download_access(p_org,p_opportunity,p_actor,p_connection_at);
  SELECT * INTO v_doc FROM public.romax_opportunity_attachments WHERE organization_id=p_org AND opportunity_id=p_opportunity AND id=p_attachment FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_attempt FROM romax_docs_private.download_attempts WHERE id=p_attempt AND organization_id=p_org AND opportunity_id=p_opportunity
    AND attachment_id=p_attachment AND actor_id=p_actor AND connection_at=p_connection_at FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  -- Exact successful replay is read-only; never accepts a different hash/size.
  IF v_attempt.state='quarantined' AND p_error IS NULL AND v_attempt.checksum_sha256=p_hash AND v_attempt.size_bytes=p_size THEN
    RETURN jsonb_build_object('status','quarantined','unchanged',true);
  END IF;
  IF v_attempt.state<>'leased' OR v_attempt.lease_until<=clock_timestamp() OR v_doc.availability_status<>'queued'
    THEN RAISE EXCEPTION 'Download reservation expired or superseded' USING ERRCODE='40001'; END IF;
  IF p_error IS NULL THEN
    IF p_hash IS NULL OR p_hash !~ '^[0-9a-f]{64}$' OR p_size IS NULL OR p_size<>v_doc.size_bytes
       OR (v_doc.checksum_sha256 IS NOT NULL AND v_doc.checksum_sha256<>p_hash)
       OR NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='romax-request-attachments' AND o.name=v_attempt.object_path
         AND o.metadata->>'size'=p_size::text)
    THEN RAISE EXCEPTION 'Quarantine object not verified' USING ERRCODE='22023'; END IF;
    UPDATE romax_docs_private.download_attempts SET state='quarantined',checksum_sha256=p_hash,size_bytes=p_size,finished_at=clock_timestamp() WHERE id=p_attempt;
    UPDATE public.romax_opportunity_attachments SET availability_status='quarantined',processing_status='downloaded',scan_status='pending',
      checksum_sha256=p_hash WHERE id=p_attachment;
    v_state:='quarantined';
  ELSE
    IF p_error NOT IN ('source_changed','invalid_binary','storage_uncertain','remote_error') OR p_hash IS NOT NULL OR p_size IS NOT NULL
      THEN RAISE EXCEPTION 'Invalid download failure' USING ERRCODE='22023'; END IF;
    UPDATE romax_docs_private.download_attempts SET state='failed',error_code=p_error,finished_at=clock_timestamp() WHERE id=p_attempt;
    UPDATE public.romax_opportunity_attachments SET availability_status='failed',processing_status='failed',scan_status='not_scanned'
      WHERE id=p_attachment;
    v_state:='failed';
  END IF;
  INSERT INTO romax_docs_private.attachment_events(organization_id,opportunity_id,attachment_id,actor_id,operation,previous_state,next_state,reason_code)
    VALUES(p_org,p_opportunity,p_attachment,p_actor,'state_changed','queued',v_state,p_error);
  RETURN jsonb_build_object('status',v_state,'unchanged',false);
END; $$;
REVOKE ALL ON FUNCTION romax_docs_private.finish_download(uuid,uuid,uuid,timestamptz,uuid,uuid,text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION romax_docs_private.finish_download(uuid,uuid,uuid,timestamptz,uuid,uuid,text,bigint,text) TO service_role;
CREATE FUNCTION public.romax_finish_attachment_download(p_org uuid,p_opportunity uuid,p_actor uuid,p_connection_at timestamptz,
  p_attachment uuid,p_attempt uuid,p_hash text,p_size bigint,p_error text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT romax_docs_private.finish_download(p_org,p_opportunity,p_actor,p_connection_at,p_attachment,p_attempt,p_hash,p_size,p_error);
$$;
REVOKE ALL ON FUNCTION public.romax_finish_attachment_download(uuid,uuid,uuid,timestamptz,uuid,uuid,text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_finish_attachment_download(uuid,uuid,uuid,timestamptz,uuid,uuid,text,bigint,text) TO service_role;
