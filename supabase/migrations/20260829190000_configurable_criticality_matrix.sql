-- Configurable criticality matrix per organization. Evolves the existing
-- manual assets.criticality field — does NOT remove or replace it:
--   - assets.criticality stays the single "criticality" column an asset has
--     always had (manual fallback, editable exactly as before via
--     upsert through useAssets.ts).
--   - When an organization configures a matrix (weighted parameters +
--     scored options) and runs an evaluation via calculate_asset_criticality,
--     the result REPLACES assets.criticality with the calculated value —
--     that single column remains the one "effective" criticality shown
--     everywhere in the app (AssetTree, AssetDetail summary, etc.), so no
--     existing read path needs to change.
--   - If an organization never configures a matrix, assets.criticality
--     keeps behaving exactly as it does today: pure manual field, nothing
--     in this migration touches that flow.
--   - Each evaluation is still frozen historically in
--     asset_criticality_assessments/_answers (score, calculated result, and
--     a manual_criticality snapshot of what assets.criticality was right
--     before this evaluation ran) even though assets.criticality itself
--     only ever holds the latest value. See docs/CONFIGURABLE_CRITICALITY_MATRIX.md.
--
-- No configurable thresholds table in this MVP (score<25 low / <50 medium /
-- <75 high / >=75 critical, fixed) — deliberately kept out to not risk
-- scope, documented as next step.
--
-- Every reference qualified with a short alias from the first line
-- (cp/cpo/aca/acaa/a/om/au) — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the class
-- of bug this is deliberately avoiding.

-- =========================================================================
-- A) criticality_parameters
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.criticality_parameters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text NULL,
  weight numeric(5, 2) NOT NULL DEFAULT 0,
  sequence integer NOT NULL DEFAULT 1,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT criticality_parameters_name_check CHECK (TRIM(name) <> ''),
  CONSTRAINT criticality_parameters_weight_check CHECK (weight >= 0),
  CONSTRAINT criticality_parameters_sequence_check CHECK (sequence > 0)
);

CREATE INDEX IF NOT EXISTS idx_criticality_parameters_organization_id ON public.criticality_parameters (organization_id);
CREATE INDEX IF NOT EXISTS idx_criticality_parameters_is_active ON public.criticality_parameters (organization_id, is_active);

DROP TRIGGER IF EXISTS trg_criticality_parameters_updated_at ON public.criticality_parameters;
CREATE TRIGGER trg_criticality_parameters_updated_at
BEFORE UPDATE ON public.criticality_parameters
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- =========================================================================
-- B) criticality_parameter_options
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.criticality_parameter_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parameter_id uuid NOT NULL REFERENCES public.criticality_parameters(id) ON DELETE CASCADE,
  label text NOT NULL,
  score numeric(8, 2) NOT NULL DEFAULT 0,
  sequence integer NOT NULL DEFAULT 1,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT criticality_parameter_options_label_check CHECK (TRIM(label) <> ''),
  CONSTRAINT criticality_parameter_options_score_check CHECK (score >= 0),
  CONSTRAINT criticality_parameter_options_sequence_check CHECK (sequence > 0)
);

CREATE INDEX IF NOT EXISTS idx_criticality_parameter_options_parameter_id ON public.criticality_parameter_options (parameter_id);
CREATE INDEX IF NOT EXISTS idx_criticality_parameter_options_is_active ON public.criticality_parameter_options (parameter_id, is_active);

DROP TRIGGER IF EXISTS trg_criticality_parameter_options_updated_at ON public.criticality_parameter_options;
CREATE TRIGGER trg_criticality_parameter_options_updated_at
BEFORE UPDATE ON public.criticality_parameter_options
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- =========================================================================
-- C) asset_criticality_assessments
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.asset_criticality_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id uuid NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  score numeric(10, 2) NOT NULL DEFAULT 0,
  calculated_criticality text NOT NULL,
  manual_criticality text NULL,
  effective_criticality text NOT NULL,
  notes text NULL,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT asset_criticality_assessments_calculated_check CHECK (calculated_criticality IN ('low', 'medium', 'high', 'critical')),
  CONSTRAINT asset_criticality_assessments_manual_check CHECK (manual_criticality IS NULL OR manual_criticality IN ('low', 'medium', 'high', 'critical')),
  CONSTRAINT asset_criticality_assessments_effective_check CHECK (effective_criticality IN ('low', 'medium', 'high', 'critical'))
);

CREATE INDEX IF NOT EXISTS idx_asset_criticality_assessments_asset_id ON public.asset_criticality_assessments (asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_criticality_assessments_organization_id ON public.asset_criticality_assessments (organization_id);

-- Reuses the same tenant-consistency guard already defined for
-- asset_documents/asset_events in 20260826234732_assets_tenant_aware_foundation.sql:
-- organization_id must equal the organization_id of asset_id. No new
-- trigger function needed.
DROP TRIGGER IF EXISTS trg_asset_criticality_assessments_check_org ON public.asset_criticality_assessments;
CREATE TRIGGER trg_asset_criticality_assessments_check_org
BEFORE INSERT OR UPDATE ON public.asset_criticality_assessments
FOR EACH ROW EXECUTE FUNCTION public.check_asset_child_organization();

-- =========================================================================
-- D) asset_criticality_assessment_answers — frozen snapshot of the matrix
-- at evaluation time (parameter_name/option_label/weight/option_score
-- copied in, not looked up live), so a later edit to
-- criticality_parameters/_options never rewrites historical evaluations.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.asset_criticality_assessment_answers (
  assessment_id uuid NOT NULL REFERENCES public.asset_criticality_assessments(id) ON DELETE CASCADE,
  parameter_id uuid NOT NULL REFERENCES public.criticality_parameters(id),
  option_id uuid NULL REFERENCES public.criticality_parameter_options(id),
  parameter_name text NOT NULL,
  option_label text NULL,
  weight numeric(5, 2) NOT NULL,
  option_score numeric(8, 2) NOT NULL DEFAULT 0,
  weighted_score numeric(10, 2) NOT NULL DEFAULT 0,
  PRIMARY KEY (assessment_id, parameter_id)
);

CREATE INDEX IF NOT EXISTS idx_asset_criticality_assessment_answers_parameter_id ON public.asset_criticality_assessment_answers (parameter_id);

-- =========================================================================
-- RLS. Read-only for everyone via policy: any active organization member
-- (or platform_admin) can read the matrix and its evaluations. Every write
-- goes exclusively through the SECURITY DEFINER RPCs below — no
-- INSERT/UPDATE/DELETE policy on any of the 4 tables, same tightest
-- pattern already used for warehouses/materials in
-- 20260828120000_minimal_inventory_materials.sql. "Delete" a
-- parameter/option is always logical (is_active = false) via
-- set_criticality_parameter_active/set_criticality_option_active, never a
-- real DELETE — matches this codebase's existing convention for reference
-- data (asset_categories, warehouses, materials all work the same way).
-- =========================================================================
ALTER TABLE public.criticality_parameters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.criticality_parameter_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_criticality_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_criticality_assessment_answers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organization members can view criticality parameters" ON public.criticality_parameters
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization members can view criticality parameter options" ON public.criticality_parameter_options
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1 FROM public.criticality_parameters cp
      WHERE cp.id = criticality_parameter_options.parameter_id
        AND public.is_organization_member(cp.organization_id)
    )
  );

CREATE POLICY "organization members can view criticality assessments" ON public.asset_criticality_assessments
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization members can view criticality assessment answers" ON public.asset_criticality_assessment_answers
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1 FROM public.asset_criticality_assessments aca
      WHERE aca.id = asset_criticality_assessment_answers.assessment_id
        AND public.is_organization_member(aca.organization_id)
    )
  );

GRANT SELECT ON TABLE public.criticality_parameters TO authenticated;
GRANT SELECT ON TABLE public.criticality_parameter_options TO authenticated;
GRANT SELECT ON TABLE public.asset_criticality_assessments TO authenticated;
GRANT SELECT ON TABLE public.asset_criticality_assessment_answers TO authenticated;

-- =========================================================================
-- E1) get_criticality_matrix: parameters (+ nested options) for one
-- organization, bundled as a single jsonb object. p_include_inactive is a
-- small, deliberate addition beyond the literal spec (which only asked for
-- "active parameters with active options") so the management view
-- (CriticalityMatrixView) can also list deactivated parameters/options in
-- order to reactivate them — without a second near-identical RPC. Default
-- stays false, matching exactly the spec's own description, so every other
-- caller (the assessment dialog) is unaffected.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_criticality_matrix(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view the criticality matrix for this organization';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cp.id,
    'name', cp.name,
    'description', cp.description,
    'weight', cp.weight,
    'sequence', cp.sequence,
    'is_active', cp.is_active,
    'options', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cpo.id,
        'label', cpo.label,
        'score', cpo.score,
        'sequence', cpo.sequence,
        'is_active', cpo.is_active
      ) ORDER BY cpo.sequence, cpo.label)
      FROM public.criticality_parameter_options cpo
      WHERE cpo.parameter_id = cp.id AND (p_include_inactive OR cpo.is_active)
    ), '[]'::jsonb)
  ) ORDER BY cp.sequence, cp.name), '[]'::jsonb)
  INTO v_result
  FROM public.criticality_parameters cp
  WHERE cp.organization_id = p_organization_id AND (p_include_inactive OR cp.is_active);

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_criticality_matrix(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_criticality_matrix(uuid, boolean) TO authenticated;

-- =========================================================================
-- E2) upsert_criticality_parameter
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_criticality_parameter(
  p_organization_id uuid,
  p_name text,
  p_description text DEFAULT NULL,
  p_weight numeric DEFAULT 0,
  p_sequence integer DEFAULT 1,
  p_parameter_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.criticality_parameters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_saved public.criticality_parameters%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RAISE EXCEPTION 'name is required';
  END IF;
  IF p_weight IS NULL OR p_weight < 0 THEN
    RAISE EXCEPTION 'weight must be >= 0';
  END IF;
  IF p_sequence IS NULL OR p_sequence <= 0 THEN
    RAISE EXCEPTION 'sequence must be > 0';
  END IF;

  IF p_parameter_id IS NOT NULL THEN
    UPDATE public.criticality_parameters cp
    SET name = TRIM(p_name),
        description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
        weight = p_weight,
        sequence = p_sequence,
        is_active = p_is_active
    WHERE cp.id = p_parameter_id AND cp.organization_id = p_organization_id
    RETURNING cp.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Parameter not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.criticality_parameters AS cp (organization_id, name, description, weight, sequence, is_active)
    VALUES (p_organization_id, TRIM(p_name), NULLIF(TRIM(COALESCE(p_description, '')), ''), p_weight, p_sequence, p_is_active)
    RETURNING cp.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_criticality_parameter(uuid, text, text, numeric, integer, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_criticality_parameter(uuid, text, text, numeric, integer, uuid, boolean) TO authenticated;

-- =========================================================================
-- E3) upsert_criticality_option
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_criticality_option(
  p_parameter_id uuid,
  p_label text,
  p_score numeric DEFAULT 0,
  p_sequence integer DEFAULT 1,
  p_option_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.criticality_parameter_options
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parameter public.criticality_parameters%ROWTYPE;
  v_saved public.criticality_parameter_options%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT cp.* INTO v_parameter FROM public.criticality_parameters cp WHERE cp.id = p_parameter_id;
  IF v_parameter.id IS NULL THEN
    RAISE EXCEPTION 'Parameter not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_parameter.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this parameter''s options';
  END IF;

  IF p_label IS NULL OR TRIM(p_label) = '' THEN
    RAISE EXCEPTION 'label is required';
  END IF;
  IF p_score IS NULL OR p_score < 0 THEN
    RAISE EXCEPTION 'score must be >= 0';
  END IF;
  IF p_sequence IS NULL OR p_sequence <= 0 THEN
    RAISE EXCEPTION 'sequence must be > 0';
  END IF;

  IF p_option_id IS NOT NULL THEN
    UPDATE public.criticality_parameter_options cpo
    SET label = TRIM(p_label),
        score = p_score,
        sequence = p_sequence,
        is_active = p_is_active
    WHERE cpo.id = p_option_id AND cpo.parameter_id = p_parameter_id
    RETURNING cpo.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Option not found for this parameter';
    END IF;
  ELSE
    INSERT INTO public.criticality_parameter_options AS cpo (parameter_id, label, score, sequence, is_active)
    VALUES (p_parameter_id, TRIM(p_label), p_score, p_sequence, p_is_active)
    RETURNING cpo.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_criticality_option(uuid, text, numeric, integer, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_criticality_option(uuid, text, numeric, integer, uuid, boolean) TO authenticated;

-- =========================================================================
-- E4) set_criticality_parameter_active
-- =========================================================================
CREATE OR REPLACE FUNCTION public.set_criticality_parameter_active(p_parameter_id uuid, p_is_active boolean)
RETURNS public.criticality_parameters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parameter public.criticality_parameters%ROWTYPE;
  v_saved public.criticality_parameters%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT cp.* INTO v_parameter FROM public.criticality_parameters cp WHERE cp.id = p_parameter_id;
  IF v_parameter.id IS NULL THEN
    RAISE EXCEPTION 'Parameter not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_parameter.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  UPDATE public.criticality_parameters cp
  SET is_active = p_is_active
  WHERE cp.id = p_parameter_id
  RETURNING cp.* INTO v_saved;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.set_criticality_parameter_active(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_criticality_parameter_active(uuid, boolean) TO authenticated;

-- =========================================================================
-- E5) set_criticality_option_active
-- =========================================================================
CREATE OR REPLACE FUNCTION public.set_criticality_option_active(p_option_id uuid, p_is_active boolean)
RETURNS public.criticality_parameter_options
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organization_id uuid;
  v_saved public.criticality_parameter_options%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT cp.organization_id INTO v_organization_id
  FROM public.criticality_parameter_options cpo
  INNER JOIN public.criticality_parameters cp ON cp.id = cpo.parameter_id
  WHERE cpo.id = p_option_id;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Option not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this parameter''s options';
  END IF;

  UPDATE public.criticality_parameter_options cpo
  SET is_active = p_is_active
  WHERE cpo.id = p_option_id
  RETURNING cpo.* INTO v_saved;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.set_criticality_option_active(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_criticality_option_active(uuid, boolean) TO authenticated;

-- =========================================================================
-- E6) calculate_asset_criticality
--
-- Two passes over p_answers on purpose: pass 1 validates every answer and
-- accumulates the score WITHOUT writing anything (so an invalid payload
-- never leaves a partial assessment row behind); only once the full
-- payload is known-valid does pass 2 insert the assessment header (with
-- its final score/calculated_criticality already known) followed by the
-- frozen per-parameter answers.
--
-- Every currently active parameter of the asset's organization must be
-- present exactly once in p_answers — enforced by comparing counts. This
-- keeps every stored assessment internally consistent (never a partial
-- evaluation silently mixed into a "final" score) and keeps this RPC the
-- single place the "no divide by a missing parameter" rule lives.
--
-- effective_criticality = calculated_criticality always in this MVP — no
-- manual override of a calculated assessment result is exposed yet (see
-- docs/CONFIGURABLE_CRITICALITY_MATRIX.md for the "next steps" note on
-- this). assets.criticality is updated to the calculated result, which is
-- what makes it "the effective criticality" the rest of the app already
-- reads (AssetTree, AssetDetail, etc. never need to change) — a planner
-- can still manually overwrite assets.criticality afterward via the
-- existing edit-asset flow exactly as before; that is a plain 'updated'
-- asset_event, not a new assessment.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.calculate_asset_criticality(
  p_asset_id uuid,
  p_answers jsonb,
  p_notes text DEFAULT NULL
)
RETURNS public.asset_criticality_assessments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset public.assets%ROWTYPE;
  v_answer jsonb;
  v_parameter_id uuid;
  v_option_id uuid;
  v_parameter public.criticality_parameters%ROWTYPE;
  v_option public.criticality_parameter_options%ROWTYPE;
  v_score numeric(10, 2) := 0;
  v_calculated_criticality text;
  v_assessment public.asset_criticality_assessments%ROWTYPE;
  v_active_parameter_count integer;
  v_answered_parameter_ids uuid[] := ARRAY[]::uuid[];
  v_distinct_answered_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.* INTO v_asset FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset.id IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_asset.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to evaluate criticality for this asset';
  END IF;

  IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'array' OR jsonb_array_length(p_answers) = 0 THEN
    RAISE EXCEPTION 'p_answers must be a non-empty JSON array';
  END IF;

  SELECT COUNT(*) INTO v_active_parameter_count
  FROM public.criticality_parameters cp
  WHERE cp.organization_id = v_asset.organization_id AND cp.is_active;

  IF v_active_parameter_count = 0 THEN
    RAISE EXCEPTION 'No active criticality parameters configured for this organization';
  END IF;

  -- Pass 1: validate every answer, accumulate the score, never write.
  FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
    v_parameter_id := NULLIF(v_answer->>'parameter_id', '')::uuid;
    v_option_id := NULLIF(v_answer->>'option_id', '')::uuid;

    IF v_parameter_id IS NULL THEN
      RAISE EXCEPTION 'Each answer requires a parameter_id';
    END IF;

    SELECT cp.* INTO v_parameter FROM public.criticality_parameters cp
      WHERE cp.id = v_parameter_id AND cp.organization_id = v_asset.organization_id AND cp.is_active;
    IF v_parameter.id IS NULL THEN
      RAISE EXCEPTION 'parameter_id % is not an active parameter of this organization', v_parameter_id;
    END IF;

    IF v_option_id IS NULL THEN
      RAISE EXCEPTION 'An option must be selected for parameter "%"', v_parameter.name;
    END IF;

    SELECT cpo.* INTO v_option FROM public.criticality_parameter_options cpo
      WHERE cpo.id = v_option_id AND cpo.parameter_id = v_parameter_id AND cpo.is_active;
    IF v_option.id IS NULL THEN
      RAISE EXCEPTION 'option_id % is not an active option of parameter "%"', v_option_id, v_parameter.name;
    END IF;

    v_score := v_score + ROUND(v_option.score * v_parameter.weight / 100, 2);
    v_answered_parameter_ids := array_append(v_answered_parameter_ids, v_parameter_id);
  END LOOP;

  SELECT COUNT(DISTINCT x) INTO v_distinct_answered_count FROM unnest(v_answered_parameter_ids) AS x;
  IF v_distinct_answered_count <> array_length(v_answered_parameter_ids, 1) THEN
    RAISE EXCEPTION 'p_answers contains a duplicate parameter_id';
  END IF;
  IF v_distinct_answered_count <> v_active_parameter_count THEN
    RAISE EXCEPTION 'All active parameters must be answered (expected %, received %)', v_active_parameter_count, v_distinct_answered_count;
  END IF;

  v_calculated_criticality := CASE
    WHEN v_score < 25 THEN 'low'
    WHEN v_score < 50 THEN 'medium'
    WHEN v_score < 75 THEN 'high'
    ELSE 'critical'
  END;

  -- Pass 2: now that the payload is known-valid, insert the header (with
  -- its final score already known) then the frozen per-parameter answers.
  INSERT INTO public.asset_criticality_assessments AS aca (
    asset_id, organization_id, score, calculated_criticality, manual_criticality, effective_criticality, notes, created_by_user_id
  ) VALUES (
    p_asset_id, v_asset.organization_id, v_score, v_calculated_criticality, v_asset.criticality, v_calculated_criticality, p_notes, auth.uid()
  ) RETURNING aca.* INTO v_assessment;

  FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
    v_parameter_id := (v_answer->>'parameter_id')::uuid;
    v_option_id := (v_answer->>'option_id')::uuid;

    SELECT cp.* INTO v_parameter FROM public.criticality_parameters cp WHERE cp.id = v_parameter_id;
    SELECT cpo.* INTO v_option FROM public.criticality_parameter_options cpo WHERE cpo.id = v_option_id;

    INSERT INTO public.asset_criticality_assessment_answers (
      assessment_id, parameter_id, option_id, parameter_name, option_label, weight, option_score, weighted_score
    ) VALUES (
      v_assessment.id, v_parameter.id, v_option.id, v_parameter.name, v_option.label, v_parameter.weight, v_option.score,
      ROUND(v_option.score * v_parameter.weight / 100, 2)
    );
  END LOOP;

  UPDATE public.assets a SET criticality = v_calculated_criticality WHERE a.id = p_asset_id;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_asset.organization_id,
    p_asset_id,
    'criticality_assessed',
    'Criticidad evaluada: ' || v_calculated_criticality || ' (score ' || v_score || ')',
    jsonb_build_object('score', v_score, 'calculated_criticality', v_calculated_criticality, 'assessment_id', v_assessment.id),
    auth.uid()
  );

  RETURN v_assessment;
END;
$$;

REVOKE ALL ON FUNCTION public.calculate_asset_criticality(uuid, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.calculate_asset_criticality(uuid, jsonb, text) TO authenticated;

-- =========================================================================
-- E7) get_asset_criticality_assessments — evaluation history for one
-- asset, each row carrying its own frozen answers as a nested jsonb array
-- (no separate round trip needed to show the breakdown of a past score).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_asset_criticality_assessments(p_asset_id uuid)
RETURNS TABLE (
  id uuid,
  asset_id uuid,
  organization_id uuid,
  score numeric,
  calculated_criticality text,
  manual_criticality text,
  effective_criticality text,
  notes text,
  created_by_user_id uuid,
  created_by_name text,
  created_at timestamptz,
  answers jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.organization_id INTO v_asset_org FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset_org IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(v_asset_org)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view criticality assessments for this asset';
  END IF;

  RETURN QUERY
  SELECT
    aca.id,
    aca.asset_id,
    aca.organization_id,
    aca.score,
    aca.calculated_criticality,
    aca.manual_criticality,
    aca.effective_criticality,
    aca.notes,
    aca.created_by_user_id,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS created_by_name,
    aca.created_at,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'parameter_id', acaa.parameter_id,
        'parameter_name', acaa.parameter_name,
        'option_id', acaa.option_id,
        'option_label', acaa.option_label,
        'weight', acaa.weight,
        'option_score', acaa.option_score,
        'weighted_score', acaa.weighted_score
      ) ORDER BY acaa.parameter_name)
      FROM public.asset_criticality_assessment_answers acaa
      WHERE acaa.assessment_id = aca.id
    ), '[]'::jsonb) AS answers
  FROM public.asset_criticality_assessments aca
  LEFT JOIN auth.users au ON au.id = aca.created_by_user_id
  WHERE aca.asset_id = p_asset_id
  ORDER BY aca.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_asset_criticality_assessments(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_asset_criticality_assessments(uuid) TO authenticated;

-- =========================================================================
-- F) get_asset_integrated_history: teach the existing "asset_event" branch
-- to render a readable Spanish label for event_type = 'criticality_assessed'
-- (inserted by calculate_asset_criticality above), same CASE/ELSE fallback
-- shape already used for created/updated/archived/restored. No other
-- branch of this function changes.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_asset_integrated_history(p_asset_id uuid)
RETURNS TABLE (
  id text,
  event_type text,
  event_label text,
  event_date timestamptz,
  actor_name text,
  actor_email text,
  source_table text,
  source_id uuid,
  title text,
  description text,
  status text,
  metadata jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset_org uuid;
  v_is_owner_or_platform_admin boolean;
  v_is_operating_provider boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.organization_id INTO v_asset_org FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset_org IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  v_is_owner_or_platform_admin := public.is_platform_admin() OR public.is_organization_member(v_asset_org);

  v_is_operating_provider := EXISTS (
    SELECT 1 FROM public.work_orders wo
    WHERE wo.asset_id = p_asset_id AND public.is_organization_member(wo.provider_organization_id)
  );

  IF NOT (v_is_owner_or_platform_admin OR v_is_operating_provider) THEN
    RAISE EXCEPTION 'Not authorized to view this asset history';
  END IF;

  RETURN QUERY

  SELECT
    'asset-created-' || a.id::text AS id,
    'asset_created'::text AS event_type,
    'Creación del activo'::text AS event_label,
    a.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'assets'::text AS source_table,
    a.id AS source_id,
    'Activo creado: ' || a.name AS title,
    a.description AS description,
    a.status::text AS status,
    jsonb_build_object('node_type', a.node_type, 'code', a.code) AS metadata
  FROM public.assets a
  LEFT JOIN auth.users au ON au.id = a.created_by_user_id
  WHERE a.id = p_asset_id
    AND v_is_owner_or_platform_admin
    AND NOT EXISTS (
      SELECT 1 FROM public.asset_events ae WHERE ae.asset_id = a.id AND ae.event_type = 'created'
    )

  UNION ALL

  SELECT
    'asset-event-' || ae.id::text AS id,
    'asset_event'::text AS event_type,
    (CASE ae.event_type
      WHEN 'created' THEN 'Activo creado'
      WHEN 'updated' THEN 'Activo actualizado'
      WHEN 'archived' THEN 'Activo archivado'
      WHEN 'restored' THEN 'Activo restaurado'
      WHEN 'criticality_assessed' THEN 'Criticidad evaluada'
      ELSE INITCAP(REPLACE(ae.event_type, '_', ' '))
    END)::text AS event_label,
    ae.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'asset_events'::text AS source_table,
    ae.id AS source_id,
    (CASE ae.event_type
      WHEN 'created' THEN 'Activo creado'
      WHEN 'updated' THEN 'Activo actualizado'
      WHEN 'archived' THEN 'Activo archivado'
      WHEN 'restored' THEN 'Activo restaurado'
      WHEN 'criticality_assessed' THEN 'Criticidad evaluada'
      ELSE INITCAP(REPLACE(ae.event_type, '_', ' '))
    END)::text AS title,
    ae.description AS description,
    NULL::text AS status,
    ae.payload AS metadata
  FROM public.asset_events ae
  LEFT JOIN auth.users au ON au.id = ae.created_by_user_id
  WHERE ae.asset_id = p_asset_id
    AND v_is_owner_or_platform_admin

  UNION ALL

  SELECT
    'request-' || r.id::text AS id,
    'request_created'::text AS event_type,
    'Solicitud creada'::text AS event_label,
    r.created_at AS event_date,
    r.created_by_name AS actor_name,
    r.created_by_email AS actor_email,
    'requests'::text AS source_table,
    r.id AS source_id,
    COALESCE(r.title, r.request_number) AS title,
    r.description AS description,
    r.status::text AS status,
    jsonb_build_object('request_number', r.request_number, 'request_type', r.request_type, 'priority', r.priority) AS metadata
  FROM public.requests r
  WHERE r.asset_id = p_asset_id
    AND v_is_owner_or_platform_admin

  UNION ALL

  SELECT
    'work-order-' || wo.id::text AS id,
    'work_order_created'::text AS event_type,
    'Orden de trabajo generada'::text AS event_label,
    wo.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_orders'::text AS source_table,
    wo.id AS source_id,
    wo.work_order_number || COALESCE(' — ' || wo.title, '') AS title,
    wo.description AS description,
    wo.status AS status,
    jsonb_build_object('work_order_number', wo.work_order_number, 'work_order_type', wo.work_order_type, 'priority', wo.priority) AS metadata
  FROM public.work_orders wo
  LEFT JOIN auth.users au ON au.id = wo.created_by_user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  SELECT
    'activity-' || woa.id::text AS id,
    'activity_created'::text AS event_type,
    'Actividad registrada'::text AS event_label,
    woa.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activities'::text AS source_table,
    woa.id AS source_id,
    woa.description AS title,
    NULL::text AS description,
    woa.status AS status,
    jsonb_build_object('estimated_hours', woa.estimated_hours, 'sequence', woa.sequence, 'work_order_number', wo.work_order_number) AS metadata
  FROM public.work_order_activities woa
  INNER JOIN public.work_orders wo ON wo.id = woa.work_order_id
  LEFT JOIN auth.users au ON au.id = woa.created_by_user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  SELECT
    'report-' || woar.id::text AS id,
    'technician_report'::text AS event_type,
    'Intervención de técnico'::text AS event_label,
    woar.started_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_reports'::text AS source_table,
    woar.id AS source_id,
    woa.description AS title,
    woar.observations AS description,
    woar.final_status AS status,
    jsonb_build_object(
      'work_order_number', wo.work_order_number,
      'activity_description', woa.description,
      'started_at', woar.started_at,
      'finished_at', woar.finished_at,
      'actual_hours', woar.actual_hours,
      'estimated_hours', woa.estimated_hours
    ) AS metadata
  FROM public.work_order_activity_reports woar
  INNER JOIN public.work_order_activities woa ON woa.id = woar.activity_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  SELECT
    'report-material-' || woarm.id::text AS id,
    'material_used'::text AS event_type,
    'Material utilizado'::text AS event_label,
    woarm.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_report_materials'::text AS source_table,
    woarm.id AS source_id,
    m.code || ' — ' || m.name AS title,
    woarm.notes AS description,
    NULL::text AS status,
    jsonb_build_object('quantity_used', woarm.quantity_used, 'unit', woarm.unit, 'material_code', m.code, 'material_name', m.name) AS metadata
  FROM public.work_order_activity_report_materials woarm
  INNER JOIN public.work_order_activity_reports woar ON woar.id = woarm.report_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.materials m ON m.id = woarm.material_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  SELECT
    'report-evidence-' || woare.id::text AS id,
    'evidence_added'::text AS event_type,
    'Evidencia registrada'::text AS event_label,
    woare.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_report_evidences'::text AS source_table,
    woare.id AS source_id,
    woare.file_name AS title,
    woare.notes AS description,
    NULL::text AS status,
    jsonb_build_object('file_name', woare.file_name, 'file_url', woare.file_url, 'mime_type', woare.mime_type) AS metadata
  FROM public.work_order_activity_report_evidences woare
  INNER JOIN public.work_order_activity_reports woar ON woar.id = woare.report_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  ORDER BY event_date DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_asset_integrated_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_asset_integrated_history(uuid) TO authenticated;
