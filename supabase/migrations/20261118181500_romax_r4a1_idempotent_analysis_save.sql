-- ROMAX R4-A.1: atomic, idempotent technical analysis saves and opportunity progress.
-- Keep v1 for compatibility; new frontend explicitly calls v2. No existing data rewritten.
-- The returned created_new flag distinguishes a new revision from a true no-op.
CREATE OR REPLACE FUNCTION public.romax_save_opportunity_analysis_v2(
  p_opportunity_id uuid,
  p_requested_service text,
  p_scope_of_work text,
  p_missing_information jsonb,
  p_technical_considerations jsonb,
  p_risks jsonb,
  p_items jsonb
)
RETURNS TABLE(analysis_id uuid, version_number integer, created_new boolean)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_org_id uuid;
  v_old public.romax_opportunity_analyses%ROWTYPE;
  v_new_id uuid;
  v_version integer;
  v_inserted integer;
  v_invalid integer;
  v_input_items jsonb;
  v_old_items jsonb;
  v_service text := NULLIF(pg_catalog.btrim(p_requested_service), '');
  v_scope text := NULLIF(pg_catalog.btrim(p_scope_of_work), '');
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT organization_id INTO v_org_id
  FROM public.romax_opportunities
  WHERE id = p_opportunity_id;
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
  IF v_service IS NULL AND v_scope IS NULL
    AND pg_catalog.jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Analysis must contain service, scope, or items';
  END IF;

  SELECT count(*) INTO v_invalid
  FROM pg_catalog.jsonb_to_recordset(p_items) AS j(description text)
  WHERE NULLIF(pg_catalog.btrim(j.description), '') IS NULL;
  IF v_invalid <> 0 THEN
    RAISE EXCEPTION 'Every analysis item requires a description';
  END IF;

  -- Compare normalized multisets, not client item UUIDs or display order.
  -- This also prevents two concurrent identical saves from creating revisions.
  SELECT COALESCE(pg_catalog.jsonb_agg(t.item ORDER BY t.item::text), '[]'::jsonb)
    INTO v_input_items
  FROM (
    SELECT pg_catalog.jsonb_build_object(
      'item_type', j.item_type,
      'description', pg_catalog.btrim(j.description),
      'quantity', j.quantity,
      'unit_code', NULLIF(pg_catalog.btrim(j.unit_code), ''),
      'technical_specification', NULLIF(pg_catalog.btrim(j.technical_specification), ''),
      'suggested_cost_item_id', j.suggested_cost_item_id
    ) AS item
    FROM pg_catalog.jsonb_to_recordset(p_items) AS j(
      item_type text, description text, quantity numeric, unit_code text,
      technical_specification text, suggested_cost_item_id uuid
    )
  ) AS t;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_opportunity_id::text, 0)
  );
  SELECT * INTO v_old
  FROM public.romax_opportunity_analyses
  WHERE opportunity_id = p_opportunity_id AND organization_id = v_org_id
  ORDER BY version_number DESC
  LIMIT 1;

  IF v_old.id IS NOT NULL THEN
    SELECT COALESCE(pg_catalog.jsonb_agg(t.item ORDER BY t.item::text), '[]'::jsonb)
      INTO v_old_items
    FROM (
      SELECT pg_catalog.jsonb_build_object(
        'item_type', i.item_type,
        'description', i.description,
        'quantity', i.quantity,
        'unit_code', i.unit_code,
        'technical_specification', i.technical_specification,
        'suggested_cost_item_id', i.suggested_cost_item_id
      ) AS item
      FROM public.romax_opportunity_analysis_items i
      WHERE i.organization_id = v_org_id AND i.analysis_id = v_old.id
    ) AS t;

    IF v_old.source_type = 'manual'
      AND v_old.requested_service IS NOT DISTINCT FROM v_service
      AND v_old.scope_of_work IS NOT DISTINCT FROM v_scope
      AND v_old.missing_information = p_missing_information
      AND v_old.technical_considerations = p_technical_considerations
      AND v_old.risks = p_risks
      AND v_old_items = v_input_items THEN
      -- Existing opportunities created before R4-A.1 also progress on a no-op.
      UPDATE public.romax_opportunities
        SET status = 'in_analysis'
      WHERE id = p_opportunity_id AND organization_id = v_org_id
        AND status IN ('new', 'reviewing', 'ready_for_analysis');
      RETURN QUERY SELECT v_old.id, v_old.version_number, false;
      RETURN;
    END IF;
  END IF;

  v_version := COALESCE(v_old.version_number, 0) + 1;
  INSERT INTO public.romax_opportunity_analyses (
    organization_id, opportunity_id, version_number, status, source_type,
    requested_service, scope_of_work, missing_information,
    technical_considerations, risks, created_by
  ) VALUES (
    v_org_id, p_opportunity_id, v_version, 'draft', 'manual',
    v_service, v_scope, p_missing_information,
    p_technical_considerations, p_risks, (SELECT auth.uid())
  ) RETURNING id INTO v_new_id;

  INSERT INTO public.romax_opportunity_analysis_items (
    organization_id, analysis_id, item_type, description, quantity, unit_code,
    technical_specification, suggested_cost_item_id
  )
  SELECT v_org_id, v_new_id, j.item_type, pg_catalog.btrim(j.description),
         j.quantity, NULLIF(pg_catalog.btrim(j.unit_code), ''),
         NULLIF(pg_catalog.btrim(j.technical_specification), ''),
         j.suggested_cost_item_id
  FROM pg_catalog.jsonb_to_recordset(p_items) AS j(
    item_type text, description text, quantity numeric, unit_code text,
    technical_specification text, suggested_cost_item_id uuid
  );
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted <> pg_catalog.jsonb_array_length(p_items) THEN
    RAISE EXCEPTION 'Incomplete analysis items';
  END IF;

  UPDATE public.romax_opportunity_analyses
    SET status = 'superseded'
  WHERE organization_id = v_org_id AND opportunity_id = p_opportunity_id
    AND id <> v_new_id AND status <> 'superseded';

  -- Do not regress quoted or discarded opportunities.
  UPDATE public.romax_opportunities
    SET status = 'in_analysis'
  WHERE id = p_opportunity_id AND organization_id = v_org_id
    AND status IN ('new', 'reviewing', 'ready_for_analysis');

  RETURN QUERY SELECT v_new_id, v_version, true;
END;
$function$;

REVOKE ALL ON FUNCTION public.romax_save_opportunity_analysis_v2(
  uuid, text, text, jsonb, jsonb, jsonb, jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.romax_save_opportunity_analysis_v2(
  uuid, text, text, jsonb, jsonb, jsonb, jsonb
) TO authenticated;
