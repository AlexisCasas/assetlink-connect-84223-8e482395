-- ROMAX R3/R4-A review hardening: tenant access, Gmail attachment identity,
-- and transactional analysis version creation. Does not modify existing data.

-- Commercial opportunities and analysis are restricted to commercial roles,
-- matching the sidebar and dashboard gates (ordinary members cannot read them).
DROP POLICY IF EXISTS romax_opportunities_read ON public.romax_opportunities;
CREATE POLICY romax_opportunities_read ON public.romax_opportunities
  FOR SELECT TO authenticated
  USING (public.has_organization_role(
    organization_id, ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]
  ));

DROP POLICY IF EXISTS romax_opportunity_attachments_read ON public.romax_opportunity_attachments;
CREATE POLICY romax_opportunity_attachments_read ON public.romax_opportunity_attachments
  FOR SELECT TO authenticated
  USING (public.has_organization_role(
    organization_id, ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]
  ));

DROP POLICY IF EXISTS romax_opportunity_analyses_read ON public.romax_opportunity_analyses;
CREATE POLICY romax_opportunity_analyses_read ON public.romax_opportunity_analyses
  FOR SELECT TO authenticated
  USING (public.has_organization_role(
    organization_id, ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]
  ));

DROP POLICY IF EXISTS romax_opportunity_analysis_items_read ON public.romax_opportunity_analysis_items;
CREATE POLICY romax_opportunity_analysis_items_read ON public.romax_opportunity_analysis_items
  FOR SELECT TO authenticated
  USING (public.has_organization_role(
    organization_id, ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]
  ));

-- Defense in depth: anonymous API access and hard deletion are not needed.
REVOKE ALL ON TABLE public.romax_opportunities,
  public.romax_opportunity_attachments,
  public.romax_opportunity_analyses,
  public.romax_opportunity_analysis_items FROM anon;
REVOKE DELETE ON TABLE public.romax_opportunities,
  public.romax_opportunity_attachments,
  public.romax_opportunity_analyses,
  public.romax_opportunity_analysis_items FROM authenticated;

-- Protect tenant linkage, origin identifiers, creator, and version audit from
-- client-side reassignment. R4-A changes produce a new version, never an
-- in-place rewrite of a prior analysis or its items.
REVOKE UPDATE ON TABLE public.romax_opportunities,
  public.romax_opportunity_attachments,
  public.romax_opportunity_analyses,
  public.romax_opportunity_analysis_items FROM authenticated;

GRANT UPDATE (
  status, classification, classification_confidence, classification_reason,
  commercial_client_id, commercial_site_id, commercial_contact_id,
  match_status, match_notes, suggested_match, subject, sender_email,
  received_at, snippet, internal_notes
) ON TABLE public.romax_opportunities TO authenticated;
GRANT UPDATE (
  processing_status, error_message, storage_path, checksum_sha256,
  filename, mime_type, size_bytes
) ON TABLE public.romax_opportunity_attachments TO authenticated;
GRANT UPDATE (status)
  ON TABLE public.romax_opportunity_analyses TO authenticated;

-- Gmail attachment identifiers are scoped to a message. Message+attachment
-- is the idempotency key, not an attachment ID on its own.
DROP INDEX IF EXISTS public.romax_opportunity_attachments_gmail_uidx;
CREATE UNIQUE INDEX romax_opportunity_attachments_gmail_uidx
  ON public.romax_opportunity_attachments (organization_id, source_message_id, source_attachment_id)
  WHERE source_system = 'gmail'
    AND source_message_id IS NOT NULL AND source_attachment_id IS NOT NULL;

-- Audit the actor of manually created opportunities by default, while
-- retaining the authenticated-actor checks enforced by the INSERT policy.
ALTER TABLE public.romax_opportunities
  ALTER COLUMN created_by SET DEFAULT auth.uid();

-- A site/contact cannot be confirmed without a commercial client.
ALTER TABLE public.romax_opportunities
  ADD CONSTRAINT romax_opportunities_linked_client_required_chk
  CHECK (commercial_client_id IS NOT NULL
    OR (commercial_site_id IS NULL AND commercial_contact_id IS NULL));

-- Persist a complete manual technical analysis as one database transaction.
-- The caller's RLS is preserved (SECURITY INVOKER), with no service_role.
CREATE OR REPLACE FUNCTION public.romax_save_opportunity_analysis_v1(
  p_opportunity_id uuid,
  p_requested_service text,
  p_scope_of_work text,
  p_missing_information jsonb,
  p_technical_considerations jsonb,
  p_risks jsonb,
  p_items jsonb
)
RETURNS TABLE(analysis_id uuid, version_number integer)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_org_id uuid;
  v_new_id uuid;
  v_version integer;
  v_inserted integer;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT o.organization_id INTO v_org_id
  FROM public.romax_opportunities o WHERE o.id = p_opportunity_id;
  IF v_org_id IS NULL OR NOT public.has_organization_role(
    v_org_id, ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]
  ) THEN
    RAISE EXCEPTION 'Not authorized for this opportunity' USING ERRCODE = '42501';
  END IF;

  IF p_items IS NULL OR pg_catalog.jsonb_typeof(p_items) IS DISTINCT FROM 'array'
    OR pg_catalog.jsonb_array_length(p_items) > 100 THEN
    RAISE EXCEPTION 'Analysis items must be an array of at most 100 entries';
  END IF;
  IF pg_catalog.jsonb_typeof(p_missing_information) IS DISTINCT FROM 'array'
    OR pg_catalog.jsonb_typeof(p_technical_considerations) IS DISTINCT FROM 'array'
    OR pg_catalog.jsonb_typeof(p_risks) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Analysis notes must be arrays';
  END IF;
  IF pg_catalog.btrim(COALESCE(p_requested_service,'')) = ''
    AND pg_catalog.btrim(COALESCE(p_scope_of_work,'')) = ''
    AND pg_catalog.jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Analysis must contain service, scope, or items';
  END IF;

  -- Serialization of concurrent saves for a single opportunity prevents
  -- version conflicts and ensures the latest prior version is superseded.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_opportunity_id::text, 0)
  );
  SELECT COALESCE(MAX(a.version_number), 0) + 1
    INTO v_version
  FROM public.romax_opportunity_analyses a
  WHERE a.opportunity_id = p_opportunity_id AND a.organization_id = v_org_id;

  INSERT INTO public.romax_opportunity_analyses (
    organization_id, opportunity_id, version_number, status, source_type,
    requested_service, scope_of_work, missing_information,
    technical_considerations, risks, created_by
  ) VALUES (
    v_org_id, p_opportunity_id, v_version, 'draft', 'manual',
    NULLIF(pg_catalog.btrim(p_requested_service),''),
    NULLIF(pg_catalog.btrim(p_scope_of_work),''),
    p_missing_information, p_technical_considerations, p_risks, (SELECT auth.uid())
  ) RETURNING id INTO v_new_id;

  INSERT INTO public.romax_opportunity_analysis_items (
    organization_id, analysis_id, item_type, description, quantity, unit_code,
    technical_specification, suggested_cost_item_id
  )
  SELECT v_org_id, v_new_id, j.item_type, pg_catalog.btrim(j.description),
         j.quantity, NULLIF(pg_catalog.btrim(j.unit_code),''),
         NULLIF(pg_catalog.btrim(j.technical_specification),''),
         j.suggested_cost_item_id
  FROM pg_catalog.jsonb_to_recordset(p_items) AS j (
    item_type text, description text, quantity numeric,
    unit_code text, technical_specification text, suggested_cost_item_id uuid
  )
  WHERE NULLIF(pg_catalog.btrim(j.description),'') IS NOT NULL;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted <> pg_catalog.jsonb_array_length(p_items) THEN
    RAISE EXCEPTION 'Every analysis item requires a description';
  END IF;

  UPDATE public.romax_opportunity_analyses a
    SET status = 'superseded'
  WHERE a.organization_id = v_org_id AND a.opportunity_id = p_opportunity_id
    AND a.id <> v_new_id AND a.status <> 'superseded';

  RETURN QUERY SELECT v_new_id, v_version;
END;
$function$;

REVOKE ALL ON FUNCTION public.romax_save_opportunity_analysis_v1(
  uuid, text, text, jsonb, jsonb, jsonb, jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.romax_save_opportunity_analysis_v1(
  uuid, text, text, jsonb, jsonb, jsonb, jsonb
) TO authenticated;
