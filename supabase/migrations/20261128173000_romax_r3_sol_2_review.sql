-- R3-SOL.2A: immutable reviewed versions; canonical links remain on opportunity.
-- No backfill; existing records and import audit untouched.
CREATE SCHEMA romax_sol2_private;
REVOKE ALL ON SCHEMA romax_sol2_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA romax_sol2_private TO authenticated,service_role;
ALTER TABLE public.romax_opportunities ADD CONSTRAINT romax_sol2_opportunity_tenant_unique UNIQUE(organization_id,id);

CREATE TABLE public.romax_request_revisions (
  organization_id uuid NOT NULL,
  opportunity_id uuid NOT NULL,
  revision integer NOT NULL CHECK(revision>0),
  actor_id uuid NOT NULL,
  reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object' AND octet_length(snapshot::text)<=32768),
  PRIMARY KEY(organization_id,opportunity_id,revision),
  FOREIGN KEY(organization_id,opportunity_id) REFERENCES public.romax_opportunities(organization_id,id) ON DELETE RESTRICT
);
ALTER TABLE public.romax_request_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.romax_request_revisions FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.romax_request_revisions TO authenticated,service_role;
CREATE POLICY romax_request_revision_read ON public.romax_request_revisions FOR SELECT TO authenticated
USING(public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]));
CREATE TRIGGER romax_request_revision_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON public.romax_request_revisions
FOR EACH STATEMENT EXECUTE FUNCTION public.romax_guard_gmail_import_audit();

CREATE TABLE romax_sol2_private.receipts(
  organization_id uuid NOT NULL, opportunity_id uuid NOT NULL, actor_id uuid NOT NULL,
  request_id uuid NOT NULL, expected_revision integer NOT NULL, payload jsonb NOT NULL,
  result jsonb NOT NULL,
  PRIMARY KEY(organization_id,opportunity_id,actor_id,request_id),
  FOREIGN KEY(organization_id,opportunity_id) REFERENCES public.romax_opportunities(organization_id,id) ON DELETE RESTRICT
);
ALTER TABLE romax_sol2_private.receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON romax_sol2_private.receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE romax_sol2_private.review_evidence(
  organization_id uuid NOT NULL, opportunity_id uuid NOT NULL, revision integer NOT NULL,
  evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object' AND octet_length(evidence::text)<=32768),
  PRIMARY KEY(organization_id,opportunity_id,revision),
  FOREIGN KEY(organization_id,opportunity_id,revision) REFERENCES public.romax_request_revisions(organization_id,opportunity_id,revision) ON DELETE RESTRICT
);
ALTER TABLE romax_sol2_private.review_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON romax_sol2_private.review_evidence FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER romax_sol2_evidence_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON romax_sol2_private.review_evidence
FOR EACH STATEMENT EXECUTE FUNCTION public.romax_guard_gmail_import_audit();

CREATE VIEW public.romax_request_current WITH(security_invoker=true) AS
SELECT DISTINCT ON (organization_id,opportunity_id) organization_id,opportunity_id,revision,actor_id,reviewed_at,snapshot
FROM public.romax_request_revisions ORDER BY organization_id,opportunity_id,revision DESC;
REVOKE ALL ON public.romax_request_current FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.romax_request_current TO authenticated,service_role;

-- Keep existing manual INSERT and analysis status transitions; reviewed link changes use RPC.
CREATE FUNCTION romax_sol2_private.guard_source_and_links() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF current_user IN ('authenticated','anon') AND
      (OLD.commercial_client_id,OLD.commercial_site_id,OLD.commercial_contact_id,OLD.match_status,OLD.match_notes,OLD.suggested_match)
      IS DISTINCT FROM (NEW.commercial_client_id,NEW.commercial_site_id,NEW.commercial_contact_id,NEW.match_status,NEW.match_notes,NEW.suggested_match) THEN
    RAISE EXCEPTION 'Review commercial links through the request review RPC' USING ERRCODE='42501';
  END IF;
  IF OLD.source_system='gmail' AND
      (OLD.subject,OLD.sender_email,OLD.received_at,OLD.snippet,OLD.created_by)
      IS DISTINCT FROM (NEW.subject,NEW.sender_email,NEW.received_at,NEW.snippet,NEW.created_by) THEN
    RAISE EXCEPTION 'Original Gmail evidence is immutable' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION romax_sol2_private.guard_source_and_links() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER romax_sol2_guard_source_links BEFORE UPDATE ON public.romax_opportunities
FOR EACH ROW EXECUTE FUNCTION romax_sol2_private.guard_source_and_links();

-- Private privileged transaction; public wrapper remains invoker.
-- All authorization comes from auth.uid(), not caller-provided actor or JWT metadata.
CREATE FUNCTION romax_sol2_private.save_review_core(p_org uuid,p_opportunity uuid,p_expected integer,p_request uuid,p_snapshot jsonb,p_actor uuid,p_verified jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_actor uuid:=p_actor; v_op public.romax_opportunities%ROWTYPE;
  v_old public.romax_request_revisions%ROWTYPE; v_receipt romax_sol2_private.receipts%ROWTYPE;
  v_current integer; v_snapshot jsonb; v_old_proofs jsonb:='{}'; v_proofs jsonb:='{}'; v_proof jsonb; v_result jsonb; v_client uuid; v_site uuid; v_contact uuid;
  v_additional uuid[]; v_id uuid; v_key text; v_value jsonb; v_deadline date; v_time time;
  v_keys text[]:=ARRAY['title','summary','scope','restrictions','reference','reference_kind','specialty','deadline_date','deadline_time','deadline_note','client_id','site_id','contact_id','additional_contacts','provenance'];
BEGIN
  IF v_actor IS NULL OR p_org IS NULL OR p_opportunity IS NULL OR p_request IS NULL OR p_expected IS NULL OR p_expected<0 THEN
    RAISE EXCEPTION 'Invalid review' USING ERRCODE='22023';
  END IF;
  IF p_verified IS NOT NULL THEN
    IF jsonb_typeof(p_verified)<>'object' OR jsonb_typeof(p_verified->'fields')<>'object' OR octet_length(p_verified::text)>32768 THEN
      RAISE EXCEPTION 'Invalid server evidence' USING ERRCODE='22023';
    END IF;
    PERFORM 1 FROM public.romax_gmail_connections WHERE organization_id=p_org AND status='connected'
      AND connected_at=(p_verified->>'connection_at')::timestamptz FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Connection changed' USING ERRCODE='42501'; END IF;
  END IF;
  PERFORM 1 FROM public.organizations WHERE id=p_org AND organization_type='provider_company' AND status='active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.organization_members WHERE organization_id=p_org AND user_id=v_actor AND is_active AND role IN ('owner','admin','manager','quote_manager') AND (p_verified IS NULL OR role='owner') FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_op FROM public.romax_opportunities WHERE organization_id=p_org AND id=p_opportunity FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot)<>'object' OR octet_length(p_snapshot::text)>32768
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_snapshot) k WHERE NOT(k=ANY(v_keys)))
    OR NOT(p_snapshot ?& v_keys) THEN RAISE EXCEPTION 'Invalid snapshot' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_receipt FROM romax_sol2_private.receipts WHERE organization_id=p_org AND opportunity_id=p_opportunity AND actor_id=v_actor AND request_id=p_request;
  IF FOUND THEN
    IF v_receipt.expected_revision<>p_expected OR v_receipt.payload<>p_snapshot THEN RAISE EXCEPTION 'Idempotency key reused' USING ERRCODE='22023'; END IF;
    RETURN v_receipt.result;
  END IF;
  SELECT * INTO v_old FROM public.romax_request_revisions WHERE organization_id=p_org AND opportunity_id=p_opportunity ORDER BY revision DESC LIMIT 1;
  v_current:=coalesce(v_old.revision,0);
  IF v_current<>p_expected THEN RAISE EXCEPTION 'Review revision conflict' USING ERRCODE='40001'; END IF;
  FOREACH v_key IN ARRAY ARRAY['title','summary','scope','restrictions','reference','reference_kind','specialty','deadline_date','deadline_time','deadline_note','client_id','site_id','contact_id'] LOOP
    v_value:=p_snapshot->v_key;
    IF jsonb_typeof(v_value) NOT IN ('string','null') OR length(coalesce(p_snapshot->>v_key,''))>
      CASE v_key WHEN 'scope' THEN 8000 WHEN 'summary' THEN 2000 WHEN 'restrictions' THEN 4000 WHEN 'deadline_note' THEN 500 ELSE 300 END
      THEN RAISE EXCEPTION 'Invalid field: %',v_key USING ERRCODE='22023'; END IF;
  END LOOP;
  IF (p_snapshot->>'reference_kind') IS NOT NULL AND (p_snapshot->>'reference_kind') NOT IN ('client_request','unknown') THEN RAISE EXCEPTION 'Invalid reference type' USING ERRCODE='22023'; END IF;
  IF ((p_snapshot->>'reference') IS NULL) <> ((p_snapshot->>'reference_kind') IS NULL) THEN RAISE EXCEPTION 'Reference and type required together' USING ERRCODE='22023'; END IF;
  IF (p_snapshot->>'specialty') IS NOT NULL AND (p_snapshot->>'specialty') NOT IN ('civil','electrical','sanitary','hvac','electromechanical','safety','multi','other') THEN RAISE EXCEPTION 'Invalid specialty' USING ERRCODE='22023'; END IF;
  IF p_snapshot->>'deadline_date' IS NOT NULL THEN
    IF p_snapshot->>'deadline_date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'Invalid date' USING ERRCODE='22023'; END IF;
    v_deadline:=(p_snapshot->>'deadline_date')::date;
  END IF;
  IF p_snapshot->>'deadline_time' IS NOT NULL THEN
    IF v_deadline IS NULL OR p_snapshot->>'deadline_time' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'Invalid deadline time' USING ERRCODE='22023'; END IF;
    v_time:=(p_snapshot->>'deadline_time')::time;
  END IF;
  v_client:=(p_snapshot->>'client_id')::uuid;v_site:=(p_snapshot->>'site_id')::uuid;v_contact:=(p_snapshot->>'contact_id')::uuid;
  IF jsonb_typeof(p_snapshot->'additional_contacts')<>'array' OR jsonb_array_length(p_snapshot->'additional_contacts')>20
    THEN RAISE EXCEPTION 'Invalid contacts' USING ERRCODE='22023'; END IF;
  SELECT coalesce(array_agg(DISTINCT x::uuid ORDER BY x::uuid),'{}'::uuid[]) INTO v_additional FROM jsonb_array_elements_text(p_snapshot->'additional_contacts') x;
  IF cardinality(v_additional)<>jsonb_array_length(p_snapshot->'additional_contacts') OR array_position(v_additional,NULL) IS NOT NULL
    OR (v_contact IS NOT NULL AND v_contact=ANY(v_additional)) THEN RAISE EXCEPTION 'Duplicate contacts' USING ERRCODE='22023'; END IF;
  IF v_client IS NULL AND (v_site IS NOT NULL OR v_contact IS NOT NULL OR cardinality(v_additional)>0) THEN RAISE EXCEPTION 'Client required for links' USING ERRCODE='22023'; END IF;
  IF v_client IS NOT NULL THEN
    PERFORM 1 FROM public.commercial_clients WHERE organization_id=p_org AND id=v_client AND is_active FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid client' USING ERRCODE='22023'; END IF;
  END IF;
  IF v_site IS NOT NULL THEN
    PERFORM 1 FROM public.commercial_client_sites WHERE organization_id=p_org AND id=v_site AND commercial_client_id=v_client AND is_active FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid site' USING ERRCODE='22023'; END IF;
  END IF;
  FOREACH v_id IN ARRAY (CASE WHEN v_contact IS NULL THEN v_additional ELSE array_append(v_additional,v_contact) END) LOOP
    PERFORM 1 FROM public.commercial_client_contacts WHERE organization_id=p_org AND id=v_id AND commercial_client_id=v_client AND is_active
      AND (commercial_site_id IS NULL OR commercial_site_id=v_site) FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid contact' USING ERRCODE='22023'; END IF;
  END LOOP;
  SELECT evidence INTO v_old_proofs FROM romax_sol2_private.review_evidence WHERE organization_id=p_org AND opportunity_id=p_opportunity AND revision=v_current;
  v_old_proofs:=coalesce(v_old_proofs,'{}'::jsonb);
  -- Gmail claims must match either previous immutable evidence or the trusted server proposal.
  IF jsonb_typeof(p_snapshot->'provenance')<>'object' THEN RAISE EXCEPTION 'Invalid provenance' USING ERRCODE='22023'; END IF;
  FOR v_key,v_value IN SELECT key,value FROM jsonb_each(p_snapshot->'provenance') LOOP
    IF NOT(v_key=ANY(v_keys)) OR v_key='provenance' OR jsonb_typeof(v_value)<>'object'
       OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_value) k WHERE k NOT IN ('source','evidence'))
       OR coalesce(v_value->>'source','') NOT IN ('manual','gmail_reviewed','master_reviewed')
       OR (v_value ? 'evidence' AND jsonb_typeof(v_value->'evidence')<>'string')
       OR length(coalesce(v_value->>'evidence',''))>500
       OR (v_value->>'source'='gmail_reviewed' AND v_op.source_system<>'gmail')
       THEN RAISE EXCEPTION 'Invalid field provenance' USING ERRCODE='22023'; END IF;
    IF v_value->>'source'='gmail_reviewed' THEN
      IF v_old.snapshot->v_key=p_snapshot->v_key AND v_old.snapshot->'provenance'->v_key=v_value AND v_old_proofs ? v_key THEN
        v_proof:=v_old_proofs->v_key;
      ELSE
        v_proof:=p_verified->'fields'->v_key;
        IF v_proof IS NULL OR v_proof->'value' IS DISTINCT FROM p_snapshot->v_key
           OR v_proof->>'evidence' IS DISTINCT FROM v_value->>'evidence'
           OR coalesce(v_proof->>'message_id','') !~ '^[A-Za-z0-9_-]{1,128}
  v_snapshot:=p_snapshot||jsonb_build_object('additional_contacts',to_jsonb(v_additional));
  -- Existing/blank fields without an explicit source are manual, not inferred from Gmail.
  FOREACH v_key IN ARRAY v_keys LOOP
    IF v_key<>'provenance' AND jsonb_typeof(v_snapshot->v_key)<>'null' AND NOT(v_snapshot->'provenance' ? v_key) THEN
      v_snapshot:=jsonb_set(v_snapshot,ARRAY['provenance',v_key],jsonb_build_object('source','manual'),true);
    END IF;
  END LOOP;
  IF v_old.snapshot=v_snapshot AND (v_op.commercial_client_id,v_op.commercial_site_id,v_op.commercial_contact_id)
      IS NOT DISTINCT FROM (v_client,v_site,v_contact) THEN
    v_result:=jsonb_build_object('outcome','unchanged','revision',v_current);
  ELSE
    UPDATE public.romax_opportunities SET commercial_client_id=v_client,commercial_site_id=v_site,commercial_contact_id=v_contact,
      match_status=CASE WHEN v_client IS NULL THEN 'unmatched' ELSE 'confirmed' END
    WHERE organization_id=p_org AND id=p_opportunity;
    INSERT INTO public.romax_request_revisions(organization_id,opportunity_id,revision,actor_id,snapshot)
      VALUES(p_org,p_opportunity,v_current+1,v_actor,v_snapshot);
    IF v_proofs<>'{}'::jsonb THEN INSERT INTO romax_sol2_private.review_evidence VALUES(p_org,p_opportunity,v_current+1,v_proofs); END IF;
    v_result:=jsonb_build_object('outcome','saved','revision',v_current+1);
  END IF;
  INSERT INTO romax_sol2_private.receipts VALUES(p_org,p_opportunity,v_actor,p_request,p_expected,p_snapshot,v_result);
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION romax_sol2_private.save_review_core(uuid,uuid,integer,uuid,jsonb,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION romax_sol2_private.save_review_core(uuid,uuid,integer,uuid,jsonb,uuid,jsonb) TO service_role;
CREATE FUNCTION romax_sol2_private.save_review(p_org uuid,p_opportunity uuid,p_expected integer,p_request uuid,p_snapshot jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $
  SELECT romax_sol2_private.save_review_core(p_org,p_opportunity,p_expected,p_request,p_snapshot,auth.uid(),NULL);
$;
REVOKE ALL ON FUNCTION romax_sol2_private.save_review(uuid,uuid,integer,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION romax_sol2_private.save_review(uuid,uuid,integer,uuid,jsonb) TO authenticated;
CREATE FUNCTION public.romax_save_request_review(p_org uuid,p_opportunity uuid,p_expected integer,p_request uuid,p_snapshot jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT romax_sol2_private.save_review(p_org,p_opportunity,p_expected,p_request,p_snapshot);
$$;
REVOKE ALL ON FUNCTION public.romax_save_request_review(uuid,uuid,integer,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_save_request_review(uuid,uuid,integer,uuid,jsonb) TO authenticated;

           OR coalesce(v_proof->>'parser','')<>'romax-r3-gmail-2.2'
           OR v_proof->>'received_at' IS NULL THEN
          RAISE EXCEPTION 'Gmail source requires verified proposal' USING ERRCODE='42501';
        END IF;
      END IF;
      v_proofs:=v_proofs||jsonb_build_object(v_key,v_proof);
    END IF;
  END LOOP;
  v_snapshot:=p_snapshot||jsonb_build_object('additional_contacts',to_jsonb(v_additional));
  IF v_old.snapshot=v_snapshot AND (v_op.commercial_client_id,v_op.commercial_site_id,v_op.commercial_contact_id)
      IS NOT DISTINCT FROM (v_client,v_site,v_contact) THEN
    v_result:=jsonb_build_object('outcome','unchanged','revision',v_current);
  ELSE
    UPDATE public.romax_opportunities SET commercial_client_id=v_client,commercial_site_id=v_site,commercial_contact_id=v_contact,
      match_status=CASE WHEN v_client IS NULL THEN 'unmatched' ELSE 'confirmed' END
    WHERE organization_id=p_org AND id=p_opportunity;
    INSERT INTO public.romax_request_revisions(organization_id,opportunity_id,revision,actor_id,snapshot)
      VALUES(p_org,p_opportunity,v_current+1,v_actor,v_snapshot);
    v_result:=jsonb_build_object('outcome','saved','revision',v_current+1);
  END IF;
  INSERT INTO romax_sol2_private.receipts VALUES(p_org,p_opportunity,v_actor,p_request,p_expected,p_snapshot,v_result);
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION romax_sol2_private.save_review(uuid,uuid,integer,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION romax_sol2_private.save_review(uuid,uuid,integer,uuid,jsonb) TO authenticated;
CREATE FUNCTION public.romax_save_request_review(p_org uuid,p_opportunity uuid,p_expected integer,p_request uuid,p_snapshot jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT romax_sol2_private.save_review(p_org,p_opportunity,p_expected,p_request,p_snapshot);
$$;
REVOKE ALL ON FUNCTION public.romax_save_request_review(uuid,uuid,integer,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_save_request_review(uuid,uuid,integer,uuid,jsonb) TO authenticated;

CREATE FUNCTION public.romax_save_request_review_verified(p_org uuid,p_opportunity uuid,p_expected integer,p_request uuid,p_snapshot jsonb,p_actor uuid,p_verified jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT romax_sol2_private.save_review_core(p_org,p_opportunity,p_expected,p_request,p_snapshot,p_actor,p_verified);
$$;
REVOKE ALL ON FUNCTION public.romax_save_request_review_verified(uuid,uuid,integer,uuid,jsonb,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.romax_save_request_review_verified(uuid,uuid,integer,uuid,jsonb,uuid,jsonb) TO service_role;
