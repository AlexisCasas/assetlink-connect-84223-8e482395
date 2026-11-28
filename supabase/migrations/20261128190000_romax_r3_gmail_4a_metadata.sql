-- R3-GMAIL.4A: document metadata and access boundary only.
-- No binary access, bucket, backfill, network calls or change to prior migrations.
-- The existing Gmail identity index is intentionally retained (stronger than per-opportunity).
CREATE SCHEMA romax_docs_private;
REVOKE ALL ON SCHEMA romax_docs_private FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA romax_docs_private TO service_role;

ALTER TABLE public.romax_opportunity_attachments
  ADD COLUMN source_locator_kind text,
  ADD COLUMN source_received_at timestamptz,
  ADD COLUMN source_direction text NOT NULL DEFAULT 'unknown',
  ADD COLUMN discovered_by uuid,
  ADD COLUMN availability_status text NOT NULL DEFAULT 'metadata_only',
  ADD COLUMN scan_status text NOT NULL DEFAULT 'not_scanned',
  ADD COLUMN review_status text NOT NULL DEFAULT 'not_reviewed',
  ADD COLUMN restriction_code text,
  ADD CONSTRAINT romax_docs_tenant_op_fk FOREIGN KEY(organization_id,opportunity_id)
    REFERENCES public.romax_opportunities(organization_id,id) ON DELETE RESTRICT,
  ADD CONSTRAINT romax_docs_tenant_document_unique UNIQUE(organization_id,opportunity_id,id),
  ADD CONSTRAINT romax_docs_direction_ck CHECK(source_direction IN ('incoming','outgoing','unknown')),
  ADD CONSTRAINT romax_docs_locator_ck CHECK(source_locator_kind IS NULL OR
    (source_system='gmail' AND source_locator_kind IN ('attachment_id','mime_part')
      AND discovered_by IS NOT NULL AND source_received_at IS NOT NULL
      AND source_message_id IS NOT NULL AND source_attachment_id IS NOT NULL)),
  ADD CONSTRAINT romax_docs_availability_ck CHECK(availability_status IN ('metadata_only','queued','quarantined','available','blocked','failed')),
  ADD CONSTRAINT romax_docs_scan_ck CHECK(scan_status IN ('not_scanned','pending','clean','infected','error')),
  ADD CONSTRAINT romax_docs_review_ck CHECK(review_status IN ('not_reviewed','pending','reviewed','rejected')),
  ADD CONSTRAINT romax_docs_restriction_ck CHECK(restriction_code IS NULL OR restriction_code IN
    ('unsupported_format','missing_size','empty_file','size_limit','unsafe_file','scan_required','processing_error')),
  ADD CONSTRAINT romax_docs_ready_ck CHECK(availability_status <> 'available' OR
    (scan_status='clean' AND storage_path IS NOT NULL
      AND storage_path=organization_id::text||'/'||opportunity_id::text||'/'||id::text
      AND checksum_sha256 IS NOT NULL AND checksum_sha256 ~ '^[0-9a-f]{64}$'
      AND size_bytes IS NOT NULL AND size_bytes BETWEEN 1 AND 10485760
      AND processing_status IN ('downloaded','processed') AND restriction_code IS NULL));

-- Legacy rows are retained and not declared available just because a path exists.
CREATE TABLE romax_docs_private.attachment_events(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  opportunity_id uuid NOT NULL,
  attachment_id uuid NOT NULL,
  actor_id uuid,
  operation text NOT NULL CHECK(operation IN ('registered','state_changed')),
  previous_state text,
  next_state text NOT NULL,
  reason_code text,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(organization_id,opportunity_id,attachment_id)
    REFERENCES public.romax_opportunity_attachments(organization_id,opportunity_id,id) ON DELETE RESTRICT
);
ALTER TABLE romax_docs_private.attachment_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON romax_docs_private.attachment_events FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX romax_docs_events_document_idx ON romax_docs_private.attachment_events(organization_id,opportunity_id,attachment_id,recorded_at);

CREATE FUNCTION romax_docs_private.deny_event_mutation() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  RAISE EXCEPTION 'Document audit is immutable' USING ERRCODE='42501';
END; $$;
REVOKE ALL ON FUNCTION romax_docs_private.deny_event_mutation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER romax_docs_events_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON romax_docs_private.attachment_events
FOR EACH STATEMENT EXECUTE FUNCTION romax_docs_private.deny_event_mutation();

CREATE FUNCTION romax_docs_private.guard_attachment() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF TG_OP<>'UPDATE' THEN RAISE EXCEPTION 'Document removal is not enabled' USING ERRCODE='42501'; END IF;
  IF (OLD.id,OLD.organization_id,OLD.opportunity_id,OLD.source_system,OLD.source_message_id,OLD.source_attachment_id,
      OLD.source_locator_kind,OLD.source_received_at,OLD.source_direction,OLD.discovered_by,OLD.filename,OLD.mime_type,OLD.created_at)
    IS DISTINCT FROM (NEW.id,NEW.organization_id,NEW.opportunity_id,NEW.source_system,NEW.source_message_id,NEW.source_attachment_id,
      NEW.source_locator_kind,NEW.source_received_at,NEW.source_direction,NEW.discovered_by,NEW.filename,NEW.mime_type,NEW.created_at)
     OR (OLD.storage_path IS NOT NULL AND OLD.storage_path IS DISTINCT FROM NEW.storage_path)
     OR (OLD.checksum_sha256 IS NOT NULL AND OLD.checksum_sha256 IS DISTINCT FROM NEW.checksum_sha256)
     OR (OLD.storage_path IS NOT NULL AND OLD.size_bytes IS DISTINCT FROM NEW.size_bytes)
  THEN RAISE EXCEPTION 'Original document identity/content is immutable' USING ERRCODE='42501'; END IF;
  -- No update lifecycle RPC in 4A: future state transitions must be introduced with audited fencing in 4C.
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION romax_docs_private.guard_attachment() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER romax_docs_guard_identity BEFORE UPDATE OR DELETE ON public.romax_opportunity_attachments
FOR EACH ROW EXECUTE FUNCTION romax_docs_private.guard_attachment();
CREATE TRIGGER romax_docs_guard_truncate BEFORE TRUNCATE ON public.romax_opportunity_attachments
FOR EACH STATEMENT EXECUTE FUNCTION romax_docs_private.guard_attachment();

CREATE FUNCTION romax_docs_private.audit_registration() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  INSERT INTO romax_docs_private.attachment_events(organization_id,opportunity_id,attachment_id,actor_id,operation,next_state,reason_code)
  VALUES(NEW.organization_id,NEW.opportunity_id,NEW.id,coalesce(NEW.discovered_by,auth.uid()),'registered',NEW.availability_status,NEW.restriction_code);
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION romax_docs_private.audit_registration() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER romax_docs_register_audit AFTER INSERT ON public.romax_opportunity_attachments
FOR EACH ROW EXECUTE FUNCTION romax_docs_private.audit_registration();

-- Keep the exact existing frontend select list and manual metadata INSERT, not unrestricted table access.
REVOKE ALL ON public.romax_opportunity_attachments FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL (id,organization_id,opportunity_id,source_system,source_message_id,source_attachment_id,filename,mime_type,size_bytes,
  storage_path,checksum_sha256,processing_status,error_message,created_at,updated_at,source_locator_kind,source_received_at,source_direction,
  discovered_by,availability_status,scan_status,review_status,restriction_code)
ON public.romax_opportunity_attachments FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT(id,organization_id,opportunity_id,source_system,filename,mime_type,size_bytes,processing_status,created_at,updated_at,
  source_received_at,source_direction,availability_status,scan_status,review_status,restriction_code)
ON public.romax_opportunity_attachments TO authenticated;
GRANT INSERT(id,organization_id,opportunity_id,source_system,filename,mime_type,size_bytes)
ON public.romax_opportunity_attachments TO authenticated;
GRANT SELECT ON public.romax_opportunity_attachments TO service_role;
ALTER TABLE public.romax_opportunity_attachments ENABLE ROW LEVEL SECURITY;
-- Restrictive gates compose with existing commercial role policies.
CREATE POLICY romax_docs_active_provider_read ON public.romax_opportunity_attachments AS RESTRICTIVE FOR SELECT TO authenticated
USING(EXISTS(SELECT 1 FROM public.organizations o WHERE o.id=romax_opportunity_attachments.organization_id
  AND o.status='active' AND o.organization_type='provider_company'));
CREATE POLICY romax_docs_active_provider_insert ON public.romax_opportunity_attachments AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(source_system='manual' AND source_message_id IS NULL AND source_attachment_id IS NULL
  AND storage_path IS NULL AND checksum_sha256 IS NULL AND error_message IS NULL
  AND processing_status='detected' AND availability_status='metadata_only' AND scan_status='not_scanned'
  AND review_status='not_reviewed' AND source_locator_kind IS NULL AND discovered_by IS NULL
  AND EXISTS(SELECT 1 FROM public.organizations o WHERE o.id=romax_opportunity_attachments.organization_id
    AND o.status='active' AND o.organization_type='provider_company'));
CREATE POLICY romax_docs_no_direct_update ON public.romax_opportunity_attachments AS RESTRICTIVE FOR UPDATE TO authenticated USING(false) WITH CHECK(false);
CREATE POLICY romax_docs_no_direct_delete ON public.romax_opportunity_attachments AS RESTRICTIVE FOR DELETE TO authenticated USING(false);

CREATE VIEW public.romax_attachment_metadata WITH(security_invoker=true) AS
SELECT id,organization_id,opportunity_id,source_system,filename,mime_type,size_bytes,processing_status,created_at,updated_at,
  source_received_at,source_direction,availability_status,scan_status,review_status,restriction_code
FROM public.romax_opportunity_attachments;
REVOKE ALL ON public.romax_attachment_metadata FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.romax_attachment_metadata TO authenticated,service_role;

-- Trusted service registration only. 4B must independently prove each part belongs to the fetched thread.
-- No browser-provided Gmail IDs accepted by any browser callable RPC.
CREATE FUNCTION romax_docs_private.register_gmail_metadata(p_org uuid,p_opportunity uuid,p_actor uuid,p_connection_at timestamptz,p_thread text,p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_item jsonb; v_op public.romax_opportunities%ROWTYPE; v_existing public.romax_opportunity_attachments%ROWTYPE;
  v_message text; v_locator text; v_kind text; v_filename text; v_mime text; v_size bigint; v_received timestamptz; v_direction text;
  v_reason text; v_id uuid; v_added integer:=0; v_unchanged integer:=0; v_keys text[]:=ARRAY['message_id','locator','locator_kind','filename','mime_type','size_bytes','received_at','direction'];
BEGIN
  IF p_org IS NULL OR p_opportunity IS NULL OR p_actor IS NULL OR p_connection_at IS NULL OR p_thread IS NULL
     OR p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR octet_length(p_items::text)>262144 THEN
    RAISE EXCEPTION 'Invalid attachment discovery' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(p_items)>50 THEN RAISE EXCEPTION 'Discovery limit exceeded' USING ERRCODE='22023'; END IF;
  PERFORM 1 FROM public.romax_gmail_connections WHERE organization_id=p_org AND status='connected' AND connected_at=p_connection_at FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied or connection changed' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.organizations WHERE id=p_org AND status='active' AND organization_type='provider_company' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied or connection changed' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.organization_members WHERE organization_id=p_org AND user_id=p_actor AND role='owner' AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied or connection changed' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_op FROM public.romax_opportunities WHERE organization_id=p_org AND id=p_opportunity AND source_system='gmail' FOR UPDATE;
  IF NOT FOUND OR v_op.source_thread_id IS DISTINCT FROM p_thread THEN RAISE EXCEPTION 'Access denied or source changed' USING ERRCODE='42501'; END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF jsonb_typeof(v_item)<>'object' OR NOT(v_item ?& v_keys) OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_item) k WHERE NOT(k=ANY(v_keys)))
       OR EXISTS(SELECT 1 FROM unnest(v_keys) k WHERE k<>'size_bytes' AND jsonb_typeof(v_item->k)<>'string')
       OR jsonb_typeof(v_item->'size_bytes') NOT IN ('number','null')
    THEN RAISE EXCEPTION 'Invalid attachment metadata' USING ERRCODE='22023'; END IF;
    v_message:=v_item->>'message_id'; v_locator:=v_item->>'locator'; v_kind:=v_item->>'locator_kind'; v_filename:=v_item->>'filename';
    v_mime:=lower(v_item->>'mime_type'); v_direction:=v_item->>'direction';
    IF v_message !~ '^[A-Za-z0-9_-]{1,128}$' OR v_kind NOT IN ('attachment_id','mime_part')
       OR (v_kind='attachment_id' AND (length(v_locator)>2048 OR v_locator !~ '^[A-Za-z0-9_-]+$'))
       OR (v_kind='mime_part' AND (length(v_locator)>128 OR v_locator !~ '^[0-9]+([.][0-9]+)*$'))
       OR length(v_filename) NOT BETWEEN 1 AND 250 OR btrim(v_filename)='' OR v_filename IN ('.','..')
       OR v_filename ~ '[[:cntrl:]]' OR position('/' in v_filename)>0 OR position(chr(92) in v_filename)>0
       OR length(v_mime) NOT BETWEEN 1 AND 120 OR v_mime !~ '^[a-z0-9.+_-]+/[a-z0-9.+_-]+$'
       OR v_direction NOT IN ('incoming','outgoing','unknown')
       OR (v_item->>'received_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z$'
       OR (v_item->>'size_bytes' IS NOT NULL AND (v_item->>'size_bytes') !~ '^[0-9]{1,13}$')
    THEN RAISE EXCEPTION 'Invalid attachment metadata' USING ERRCODE='22023'; END IF;
    v_received:=(v_item->>'received_at')::timestamptz; v_size:=(v_item->>'size_bytes')::bigint;
    IF v_kind='mime_part' THEN v_locator:='part:'||v_locator; END IF;
    v_reason:=CASE WHEN v_size IS NULL THEN 'missing_size' WHEN v_size=0 THEN 'empty_file' WHEN v_size>10485760 THEN 'size_limit'
      WHEN NOT ((v_mime='application/pdf' AND lower(v_filename) LIKE '%.pdf')
        OR (v_mime='application/vnd.openxmlformats-officedocument.wordprocessingml.document' AND lower(v_filename) LIKE '%.docx')
        OR (v_mime='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' AND lower(v_filename) LIKE '%.xlsx')
        OR (v_mime='image/jpeg' AND (lower(v_filename) LIKE '%.jpg' OR lower(v_filename) LIKE '%.jpeg'))
        OR (v_mime='image/png' AND lower(v_filename) LIKE '%.png') OR (v_mime='text/plain' AND lower(v_filename) LIKE '%.txt'))
      THEN 'unsupported_format' ELSE NULL END;
    INSERT INTO public.romax_opportunity_attachments(organization_id,opportunity_id,source_system,source_message_id,source_attachment_id,source_locator_kind,
      source_received_at,source_direction,discovered_by,filename,mime_type,size_bytes,processing_status,availability_status,restriction_code)
    VALUES(p_org,p_opportunity,'gmail',v_message,v_locator,v_kind,v_received,v_direction,p_actor,v_filename,v_mime,v_size,
      CASE WHEN v_reason IS NULL THEN 'detected' ELSE 'unsupported' END,
      CASE WHEN v_reason IS NULL THEN 'metadata_only' ELSE 'blocked' END,v_reason)
    ON CONFLICT (organization_id,source_message_id,source_attachment_id) WHERE source_system='gmail' AND source_message_id IS NOT NULL AND source_attachment_id IS NOT NULL
      DO NOTHING RETURNING id INTO v_id;
    IF FOUND THEN v_added:=v_added+1;
    ELSE
      SELECT * INTO v_existing FROM public.romax_opportunity_attachments WHERE organization_id=p_org
        AND source_system='gmail' AND source_message_id=v_message AND source_attachment_id=v_locator;
      IF NOT FOUND OR v_existing.opportunity_id IS DISTINCT FROM p_opportunity
         OR (v_existing.filename,v_existing.mime_type,v_existing.size_bytes,v_existing.source_locator_kind,v_existing.source_received_at,v_existing.source_direction)
         IS DISTINCT FROM (v_filename,v_mime,v_size,v_kind,v_received,v_direction)
      THEN RAISE EXCEPTION 'Attachment identity conflict' USING ERRCODE='23505'; END IF;
      v_unchanged:=v_unchanged+1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('registered',v_added,'unchanged',v_unchanged);
END; $$;
REVOKE ALL ON FUNCTION romax_docs_private.register_gmail_metadata(uuid,uuid,uuid,timestamptz,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION romax_docs_private.register_gmail_metadata(uuid,uuid,uuid,timestamptz,text,jsonb) TO service_role;
CREATE FUNCTION public.romax_register_gmail_attachment_metadata(p_org uuid,p_opportunity uuid,p_actor uuid,p_connection_at timestamptz,p_thread text,p_items jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT romax_docs_private.register_gmail_metadata(p_org,p_opportunity,p_actor,p_connection_at,p_thread,p_items);
$$;
REVOKE ALL ON FUNCTION public.romax_register_gmail_attachment_metadata(uuid,uuid,uuid,timestamptz,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_register_gmail_attachment_metadata(uuid,uuid,uuid,timestamptz,text,jsonb) TO service_role;
