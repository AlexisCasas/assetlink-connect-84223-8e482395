-- R3-GMAIL.3: service-only transactional import, append-only confirmation evidence.
CREATE TABLE public.romax_gmail_import_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  opportunity_id uuid NOT NULL UNIQUE REFERENCES public.romax_opportunities(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL,
  confirmation_hash text NOT NULL UNIQUE CHECK (confirmation_hash ~ '^[0-9a-f]{64}$'),
  candidate_digest text NOT NULL CHECK (candidate_digest ~ '^[0-9a-f]{64}$'),
  source_thread_id text NOT NULL,
  source_message_id text NOT NULL,
  connection_at timestamptz NOT NULL,
  confirmed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.romax_gmail_import_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.romax_gmail_import_audit FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT ON public.romax_gmail_import_audit TO service_role;

CREATE FUNCTION public.romax_guard_gmail_import_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  RAISE EXCEPTION 'Gmail import audit is immutable' USING ERRCODE='42501';
END; $$;
REVOKE ALL ON FUNCTION public.romax_guard_gmail_import_audit() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER romax_gmail_import_audit_immutable BEFORE UPDATE OR DELETE OR TRUNCATE
ON public.romax_gmail_import_audit FOR EACH STATEMENT EXECUTE FUNCTION public.romax_guard_gmail_import_audit();

CREATE FUNCTION public.romax_guard_gmail_provenance() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.source_system='gmail' AND current_user IN ('anon','authenticated') THEN
      RAISE EXCEPTION 'Gmail import requires authorized server confirmation' USING ERRCODE='42501';
    END IF;
  ELSIF TG_OP='UPDATE' THEN
    IF (OLD.source_system='gmail' OR NEW.source_system='gmail') AND
       (OLD.source_system,OLD.organization_id,OLD.source_thread_id,OLD.source_message_id)
       IS DISTINCT FROM (NEW.source_system,NEW.organization_id,NEW.source_thread_id,NEW.source_message_id) THEN
      RAISE EXCEPTION 'Gmail provenance is immutable' USING ERRCODE='42501';
    END IF;
  ELSIF TG_OP='DELETE' THEN
    IF OLD.source_system='gmail' THEN
      RAISE EXCEPTION 'Discard Gmail opportunities instead of deleting' USING ERRCODE='42501';
    END IF;
    RETURN OLD;
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.romax_guard_gmail_provenance() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER romax_gmail_provenance_guard BEFORE INSERT OR UPDATE OR DELETE ON public.romax_opportunities
FOR EACH ROW EXECUTE FUNCTION public.romax_guard_gmail_provenance();

-- Restrictive policy also prevents browser writes even when a permissive role policy grants insert.
CREATE POLICY romax_gmail_server_insert_only ON public.romax_opportunities AS RESTRICTIVE
FOR INSERT TO authenticated WITH CHECK (source_system <> 'gmail');
CREATE POLICY romax_gmail_attachment_server_insert_only ON public.romax_opportunity_attachments AS RESTRICTIVE
FOR INSERT TO authenticated WITH CHECK (source_system <> 'gmail');
CREATE POLICY romax_gmail_attachment_server_update_only ON public.romax_opportunity_attachments AS RESTRICTIVE
FOR UPDATE TO authenticated USING (source_system <> 'gmail') WITH CHECK (source_system <> 'gmail');

CREATE FUNCTION public.romax_confirm_gmail_import(
  p_org uuid,p_actor uuid,p_connected_at timestamptz,p_confirmation_hash text,p_digest text,
  p_expires_at timestamptz,p_thread text,p_message text,p_subject text,p_sender text,
  p_received_at timestamptz,p_snippet text,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE
  v_id uuid;
  v_status text;
  v_prior public.romax_gmail_import_audit%ROWTYPE;
BEGIN
  IF current_user <> 'service_role' THEN RAISE EXCEPTION 'Server only' USING ERRCODE='42501'; END IF;
  IF p_org IS NULL OR p_actor IS NULL OR p_connected_at IS NULL
    OR p_expires_at IS NULL OR p_expires_at<=clock_timestamp() OR p_expires_at>clock_timestamp()+interval '5 minutes'
    OR p_confirmation_hash IS NULL OR p_confirmation_hash !~ '^[a-f0-9]{64}$'
    OR p_digest IS NULL OR p_digest !~ '^[a-f0-9]{64}$'
    OR p_thread IS NULL OR p_thread !~ '^[A-Za-z0-9_-]{1,128}$'
    OR p_message IS NULL OR p_message !~ '^[A-Za-z0-9_-]{1,128}$'
    OR p_received_at IS NULL OR p_received_at>clock_timestamp() OR p_received_at<clock_timestamp()-interval '7 days 15 minutes'
    OR p_subject IS NULL OR length(p_subject)>500 OR length(coalesce(p_sender,''))>320
    OR length(coalesce(p_snippet,''))>500 OR length(coalesce(p_reason,''))>2000
  THEN RAISE EXCEPTION 'Invalid import confirmation' USING ERRCODE='22023'; END IF;
  -- Lock connection, membership and provider state until commit; serialize per mailbox.
  PERFORM 1 FROM public.romax_gmail_connections c WHERE c.organization_id=p_org AND c.status='connected' AND c.connected_at=p_connected_at FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Connection changed' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.organizations o WHERE o.id=p_org AND o.organization_type='provider_company' AND o.status='active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Provider inactive' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.organization_members m WHERE m.organization_id=p_org AND m.user_id=p_actor AND m.role='owner' AND m.is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Owner required' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_prior FROM public.romax_gmail_import_audit WHERE confirmation_hash=p_confirmation_hash;
  IF FOUND THEN
    IF (v_prior.organization_id,v_prior.actor_id,v_prior.source_thread_id,v_prior.source_message_id,v_prior.candidate_digest,v_prior.connection_at)
      IS DISTINCT FROM (p_org,p_actor,p_thread,p_message,p_digest,p_connected_at) THEN
      RAISE EXCEPTION 'Confirmation already used' USING ERRCODE='42501';
    END IF;
    RETURN jsonb_build_object('outcome','already_exists','opportunity_id',v_prior.opportunity_id);
  END IF;
  INSERT INTO public.romax_opportunities(organization_id,source_system,source_thread_id,source_message_id,
    subject,sender_email,received_at,snippet,classification,classification_reason,status,match_status,created_by)
  VALUES(p_org,'gmail',p_thread,p_message,p_subject,p_sender,p_received_at,p_snippet,'quote_request',p_reason,'new','unmatched',p_actor)
  ON CONFLICT DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT id,status INTO v_id,v_status FROM public.romax_opportunities WHERE organization_id=p_org AND source_system='gmail'
      AND source_thread_id=p_thread;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Gmail identity conflict' USING ERRCODE='23505'; END IF;
    RETURN jsonb_build_object('outcome','already_exists','opportunity_id',v_id,'status',v_status);
  END IF;
  INSERT INTO public.romax_gmail_import_audit(organization_id,opportunity_id,actor_id,confirmation_hash,candidate_digest,
    source_thread_id,source_message_id,connection_at)
  VALUES(p_org,v_id,p_actor,p_confirmation_hash,p_digest,p_thread,p_message,p_connected_at);
  RETURN jsonb_build_object('outcome','imported','opportunity_id',v_id,'status','new');
END; $$;
REVOKE ALL ON FUNCTION public.romax_confirm_gmail_import(uuid,uuid,timestamptz,text,text,timestamptz,text,text,text,text,timestamptz,text,text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.romax_confirm_gmail_import(uuid,uuid,timestamptz,text,text,timestamptz,text,text,text,text,timestamptz,text,text) TO service_role;
