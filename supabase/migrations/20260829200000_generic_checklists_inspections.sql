-- Generic checklist/inspection engine. ITSE is deliberately NOT a module —
-- it is just one checklist_template an organization can create ("Plantilla
-- ITSE"), the same way "Inspección de techos", "Inspección gerencial",
-- "Mantenimiento preventivo", "Auditoría interna" or "Inspección de luces
-- de emergencia" are all just other templates. Nothing in this schema or
-- in any RPC below hardcodes ITSE or any other specific checklist.
--
-- Flow: checklist_templates (+ items + response_options) → inspection_plans
-- (recurring schedule against a sede/área/activo) → inspection_runs (one
-- concrete execution, created from a plan) → inspection_run_answers/
-- inspection_run_evidences (frozen snapshot of what was actually answered).
--
-- Evidences are metadata/link only in this phase (file_name/file_url/
-- file_path/mime_type/size_bytes) — no real upload pipeline exists yet in
-- this codebase (same "prepared for later" note as
-- work_order_activity_report_evidences before it).
--
-- Every reference qualified with a short alias from the first line
-- (ct/cti/ctro/ip/ir/ira/ire/a/cb/om/au) — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the class
-- of bug this is deliberately avoiding.

-- =========================================================================
-- A1) checklist_templates
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.checklist_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text NULL,
  category text NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT checklist_templates_name_check CHECK (TRIM(name) <> '')
);

CREATE INDEX IF NOT EXISTS idx_checklist_templates_organization_id ON public.checklist_templates (organization_id);
CREATE INDEX IF NOT EXISTS idx_checklist_templates_is_active ON public.checklist_templates (organization_id, is_active);

DROP TRIGGER IF EXISTS trg_checklist_templates_updated_at ON public.checklist_templates;
CREATE TRIGGER trg_checklist_templates_updated_at
BEFORE UPDATE ON public.checklist_templates
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- =========================================================================
-- A2) checklist_template_items
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.checklist_template_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES public.checklist_templates(id) ON DELETE CASCADE,
  section text NULL,
  question text NOT NULL,
  help_text text NULL,
  sequence integer NOT NULL DEFAULT 1,
  is_required boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT checklist_template_items_question_check CHECK (TRIM(question) <> ''),
  CONSTRAINT checklist_template_items_sequence_check CHECK (sequence > 0)
);

CREATE INDEX IF NOT EXISTS idx_checklist_template_items_template_id ON public.checklist_template_items (template_id);
CREATE INDEX IF NOT EXISTS idx_checklist_template_items_is_active ON public.checklist_template_items (template_id, is_active);

DROP TRIGGER IF EXISTS trg_checklist_template_items_updated_at ON public.checklist_template_items;
CREATE TRIGGER trg_checklist_template_items_updated_at
BEFORE UPDATE ON public.checklist_template_items
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- =========================================================================
-- A3) checklist_template_response_options — e.g. Cumple / No cumple / No
-- aplica for a given template. is_failure marks which option(s) count as a
-- non-conformity for submit_inspection_run's result calculation; score is
-- reserved for future weighted scoring (not used to compute anything in
-- this MVP).
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.checklist_template_response_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES public.checklist_templates(id) ON DELETE CASCADE,
  label text NOT NULL,
  value text NOT NULL,
  score numeric(8, 2) NULL,
  is_failure boolean NOT NULL DEFAULT false,
  sequence integer NOT NULL DEFAULT 1,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT checklist_template_response_options_label_check CHECK (TRIM(label) <> ''),
  CONSTRAINT checklist_template_response_options_value_check CHECK (TRIM(value) <> ''),
  CONSTRAINT checklist_template_response_options_sequence_check CHECK (sequence > 0)
);

CREATE INDEX IF NOT EXISTS idx_checklist_template_response_options_template_id ON public.checklist_template_response_options (template_id);
CREATE INDEX IF NOT EXISTS idx_checklist_template_response_options_is_active ON public.checklist_template_response_options (template_id, is_active);

-- =========================================================================
-- A4) inspection_plans — a recurring schedule against a sede (client_branches)
-- and/or área (an assets row, typically node_type='area') and/or a specific
-- asset. At least one target is required (inspection_plans_target_check).
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.inspection_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES public.checklist_templates(id),
  branch_id uuid NULL REFERENCES public.client_branches(id),
  area_asset_id uuid NULL REFERENCES public.assets(id),
  asset_id uuid NULL REFERENCES public.assets(id),
  responsible_member_id uuid NULL REFERENCES public.organization_members(id),
  title text NOT NULL,
  description text NULL,
  frequency text NOT NULL DEFAULT 'one_time',
  start_date date NOT NULL DEFAULT current_date,
  next_due_at timestamptz NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inspection_plans_title_check CHECK (TRIM(title) <> ''),
  CONSTRAINT inspection_plans_frequency_check CHECK (frequency IN ('one_time', 'daily', 'weekly', 'monthly', 'quarterly', 'semiannual', 'annual')),
  CONSTRAINT inspection_plans_target_check CHECK (branch_id IS NOT NULL OR area_asset_id IS NOT NULL OR asset_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_inspection_plans_organization_id ON public.inspection_plans (organization_id);
CREATE INDEX IF NOT EXISTS idx_inspection_plans_template_id ON public.inspection_plans (template_id);
CREATE INDEX IF NOT EXISTS idx_inspection_plans_branch_id ON public.inspection_plans (branch_id);
CREATE INDEX IF NOT EXISTS idx_inspection_plans_area_asset_id ON public.inspection_plans (area_asset_id);
CREATE INDEX IF NOT EXISTS idx_inspection_plans_asset_id ON public.inspection_plans (asset_id);
CREATE INDEX IF NOT EXISTS idx_inspection_plans_responsible_member_id ON public.inspection_plans (responsible_member_id);
CREATE INDEX IF NOT EXISTS idx_inspection_plans_is_active ON public.inspection_plans (organization_id, is_active);

DROP TRIGGER IF EXISTS trg_inspection_plans_updated_at ON public.inspection_plans;
CREATE TRIGGER trg_inspection_plans_updated_at
BEFORE UPDATE ON public.inspection_plans
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Consistency guard: template/branch/área/activo/responsable must all
-- belong to the same organization_id as the plan. SECURITY INVOKER on
-- purpose — only ever runs inside the SECURITY DEFINER RPCs below, same
-- pattern as check_asset_consistency/check_warehouse_branch_organization.
CREATE OR REPLACE FUNCTION public.check_inspection_plan_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT ct.organization_id INTO v_org FROM public.checklist_templates ct WHERE ct.id = NEW.template_id;
  IF v_org IS NULL OR v_org <> NEW.organization_id THEN
    RAISE EXCEPTION 'template_id must belong to the same organization_id';
  END IF;

  IF NEW.branch_id IS NOT NULL THEN
    SELECT cb.organization_id INTO v_org FROM public.client_branches cb WHERE cb.id = NEW.branch_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'branch_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.area_asset_id IS NOT NULL THEN
    SELECT a.organization_id INTO v_org FROM public.assets a WHERE a.id = NEW.area_asset_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'area_asset_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.asset_id IS NOT NULL THEN
    SELECT a.organization_id INTO v_org FROM public.assets a WHERE a.id = NEW.asset_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'asset_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.responsible_member_id IS NOT NULL THEN
    SELECT om.organization_id INTO v_org FROM public.organization_members om WHERE om.id = NEW.responsible_member_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'responsible_member_id must belong to the same organization_id';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inspection_plans_check_org ON public.inspection_plans;
CREATE TRIGGER trg_inspection_plans_check_org
BEFORE INSERT OR UPDATE ON public.inspection_plans
FOR EACH ROW EXECUTE FUNCTION public.check_inspection_plan_organization();

-- =========================================================================
-- A5) inspection_runs — one concrete/historical execution.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.inspection_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  plan_id uuid NULL REFERENCES public.inspection_plans(id) ON DELETE SET NULL,
  template_id uuid NOT NULL REFERENCES public.checklist_templates(id),
  branch_id uuid NULL REFERENCES public.client_branches(id),
  area_asset_id uuid NULL REFERENCES public.assets(id),
  asset_id uuid NULL REFERENCES public.assets(id),
  responsible_member_id uuid NULL REFERENCES public.organization_members(id),
  scheduled_for timestamptz NULL,
  started_at timestamptz NULL,
  completed_at timestamptz NULL,
  status text NOT NULL DEFAULT 'scheduled',
  result text NULL,
  notes text NULL,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inspection_runs_status_check CHECK (status IN ('scheduled', 'in_progress', 'completed', 'cancelled', 'overdue')),
  CONSTRAINT inspection_runs_result_check CHECK (result IS NULL OR result IN ('passed', 'failed', 'not_applicable')),
  CONSTRAINT inspection_runs_completed_after_started_check CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE INDEX IF NOT EXISTS idx_inspection_runs_organization_id ON public.inspection_runs (organization_id);
CREATE INDEX IF NOT EXISTS idx_inspection_runs_plan_id ON public.inspection_runs (plan_id);
CREATE INDEX IF NOT EXISTS idx_inspection_runs_template_id ON public.inspection_runs (template_id);
CREATE INDEX IF NOT EXISTS idx_inspection_runs_asset_id ON public.inspection_runs (asset_id);
CREATE INDEX IF NOT EXISTS idx_inspection_runs_responsible_member_id ON public.inspection_runs (responsible_member_id);
CREATE INDEX IF NOT EXISTS idx_inspection_runs_status ON public.inspection_runs (organization_id, status);

DROP TRIGGER IF EXISTS trg_inspection_runs_updated_at ON public.inspection_runs;
CREATE TRIGGER trg_inspection_runs_updated_at
BEFORE UPDATE ON public.inspection_runs
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Same shape as check_inspection_plan_organization, plus plan_id (when set)
-- must itself belong to the same organization.
CREATE OR REPLACE FUNCTION public.check_inspection_run_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT ct.organization_id INTO v_org FROM public.checklist_templates ct WHERE ct.id = NEW.template_id;
  IF v_org IS NULL OR v_org <> NEW.organization_id THEN
    RAISE EXCEPTION 'template_id must belong to the same organization_id';
  END IF;

  IF NEW.plan_id IS NOT NULL THEN
    SELECT ip.organization_id INTO v_org FROM public.inspection_plans ip WHERE ip.id = NEW.plan_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'plan_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.branch_id IS NOT NULL THEN
    SELECT cb.organization_id INTO v_org FROM public.client_branches cb WHERE cb.id = NEW.branch_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'branch_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.area_asset_id IS NOT NULL THEN
    SELECT a.organization_id INTO v_org FROM public.assets a WHERE a.id = NEW.area_asset_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'area_asset_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.asset_id IS NOT NULL THEN
    SELECT a.organization_id INTO v_org FROM public.assets a WHERE a.id = NEW.asset_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'asset_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.responsible_member_id IS NOT NULL THEN
    SELECT om.organization_id INTO v_org FROM public.organization_members om WHERE om.id = NEW.responsible_member_id;
    IF v_org IS NULL OR v_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'responsible_member_id must belong to the same organization_id';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inspection_runs_check_org ON public.inspection_runs;
CREATE TRIGGER trg_inspection_runs_check_org
BEFORE INSERT OR UPDATE ON public.inspection_runs
FOR EACH ROW EXECUTE FUNCTION public.check_inspection_run_organization();

-- =========================================================================
-- A6) inspection_run_answers — frozen snapshot per answered item (question/
-- option label/value copied in, not looked up live), same reasoning as
-- asset_criticality_assessment_answers: a later edit to the template must
-- never rewrite a historical run. Written only by submit_inspection_run
-- (SECURITY DEFINER), which already validates run/template/item/option
-- consistency in PL/pgSQL — no separate trigger needed here.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.inspection_run_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES public.inspection_runs(id) ON DELETE CASCADE,
  template_item_id uuid NOT NULL REFERENCES public.checklist_template_items(id),
  response_option_id uuid NULL REFERENCES public.checklist_template_response_options(id),
  item_question text NOT NULL,
  response_label text NULL,
  response_value text NULL,
  is_failure boolean NOT NULL DEFAULT false,
  observations text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inspection_run_answers_run_item_unique UNIQUE (run_id, template_item_id)
);

CREATE INDEX IF NOT EXISTS idx_inspection_run_answers_run_id ON public.inspection_run_answers (run_id);

-- =========================================================================
-- A7) inspection_run_evidences — metadata/link only, no real upload
-- pipeline in this phase (see file header note).
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.inspection_run_evidences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES public.inspection_runs(id) ON DELETE CASCADE,
  answer_id uuid NULL REFERENCES public.inspection_run_answers(id) ON DELETE CASCADE,
  file_name text NOT NULL,
  file_url text NULL,
  file_path text NULL,
  mime_type text NULL,
  size_bytes bigint NULL,
  notes text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inspection_run_evidences_file_name_check CHECK (TRIM(file_name) <> '')
);

CREATE INDEX IF NOT EXISTS idx_inspection_run_evidences_run_id ON public.inspection_run_evidences (run_id);
CREATE INDEX IF NOT EXISTS idx_inspection_run_evidences_answer_id ON public.inspection_run_evidences (answer_id);

-- =========================================================================
-- RLS. Read-only for everyone via policy: any active organization member
-- (including technician — they need to see their assigned runs) or
-- platform_admin can read. Every write goes exclusively through the
-- SECURITY DEFINER RPCs below — no INSERT/UPDATE/DELETE policy on any of
-- the 7 tables, same tightest pattern already used for
-- warehouses/materials and the criticality matrix tables. "Delete" a
-- template/item/option/plan is always logical (is_active = false), never a
-- real DELETE.
-- =========================================================================
ALTER TABLE public.checklist_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.checklist_template_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.checklist_template_response_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_run_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_run_evidences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organization members can view checklist templates" ON public.checklist_templates
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization members can view checklist template items" ON public.checklist_template_items
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1 FROM public.checklist_templates ct
      WHERE ct.id = checklist_template_items.template_id
        AND public.is_organization_member(ct.organization_id)
    )
  );

CREATE POLICY "organization members can view checklist response options" ON public.checklist_template_response_options
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1 FROM public.checklist_templates ct
      WHERE ct.id = checklist_template_response_options.template_id
        AND public.is_organization_member(ct.organization_id)
    )
  );

CREATE POLICY "organization members can view inspection plans" ON public.inspection_plans
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization members can view inspection runs" ON public.inspection_runs
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization members can view inspection run answers" ON public.inspection_run_answers
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1 FROM public.inspection_runs ir
      WHERE ir.id = inspection_run_answers.run_id
        AND public.is_organization_member(ir.organization_id)
    )
  );

CREATE POLICY "organization members can view inspection run evidences" ON public.inspection_run_evidences
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1 FROM public.inspection_runs ir
      WHERE ir.id = inspection_run_evidences.run_id
        AND public.is_organization_member(ir.organization_id)
    )
  );

GRANT SELECT ON TABLE public.checklist_templates TO authenticated;
GRANT SELECT ON TABLE public.checklist_template_items TO authenticated;
GRANT SELECT ON TABLE public.checklist_template_response_options TO authenticated;
GRANT SELECT ON TABLE public.inspection_plans TO authenticated;
GRANT SELECT ON TABLE public.inspection_runs TO authenticated;
GRANT SELECT ON TABLE public.inspection_run_answers TO authenticated;
GRANT SELECT ON TABLE public.inspection_run_evidences TO authenticated;

-- =========================================================================
-- B1) get_checklist_templates: templates (+ nested items, + nested
-- response_options) for one organization, single jsonb round trip. Same
-- p_include_inactive convention as get_criticality_matrix — default false
-- (only what an execution flow needs), true for the management view so
-- deactivated items/options can be reactivated.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_checklist_templates(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
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
    RAISE EXCEPTION 'Not authorized to view checklist templates for this organization';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', ct.id,
    'name', ct.name,
    'description', ct.description,
    'category', ct.category,
    'is_active', ct.is_active,
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cti.id,
        'section', cti.section,
        'question', cti.question,
        'help_text', cti.help_text,
        'sequence', cti.sequence,
        'is_required', cti.is_required,
        'is_active', cti.is_active
      ) ORDER BY cti.sequence, cti.question)
      FROM public.checklist_template_items cti
      WHERE cti.template_id = ct.id AND (p_include_inactive OR cti.is_active)
    ), '[]'::jsonb),
    'response_options', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ctro.id,
        'label', ctro.label,
        'value', ctro.value,
        'score', ctro.score,
        'is_failure', ctro.is_failure,
        'sequence', ctro.sequence,
        'is_active', ctro.is_active
      ) ORDER BY ctro.sequence, ctro.label)
      FROM public.checklist_template_response_options ctro
      WHERE ctro.template_id = ct.id AND (p_include_inactive OR ctro.is_active)
    ), '[]'::jsonb)
  ) ORDER BY ct.name), '[]'::jsonb)
  INTO v_result
  FROM public.checklist_templates ct
  WHERE ct.organization_id = p_organization_id AND (p_include_inactive OR ct.is_active);

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_checklist_templates(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_checklist_templates(uuid, boolean) TO authenticated;

-- =========================================================================
-- B2) upsert_checklist_template
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_checklist_template(
  p_organization_id uuid,
  p_name text,
  p_description text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_template_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.checklist_templates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_saved public.checklist_templates%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage checklist templates for this organization';
  END IF;

  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RAISE EXCEPTION 'name is required';
  END IF;

  IF p_template_id IS NOT NULL THEN
    UPDATE public.checklist_templates ct
    SET name = TRIM(p_name),
        description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
        category = NULLIF(TRIM(COALESCE(p_category, '')), ''),
        is_active = p_is_active
    WHERE ct.id = p_template_id AND ct.organization_id = p_organization_id
    RETURNING ct.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Template not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.checklist_templates AS ct (organization_id, name, description, category, is_active, created_by_user_id)
    VALUES (p_organization_id, TRIM(p_name), NULLIF(TRIM(COALESCE(p_description, '')), ''), NULLIF(TRIM(COALESCE(p_category, '')), ''), p_is_active, auth.uid())
    RETURNING ct.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_checklist_template(uuid, text, text, text, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_checklist_template(uuid, text, text, text, uuid, boolean) TO authenticated;

-- =========================================================================
-- B3) upsert_checklist_template_item
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_checklist_template_item(
  p_template_id uuid,
  p_question text,
  p_section text DEFAULT NULL,
  p_help_text text DEFAULT NULL,
  p_sequence integer DEFAULT 1,
  p_is_required boolean DEFAULT true,
  p_item_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.checklist_template_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template public.checklist_templates%ROWTYPE;
  v_saved public.checklist_template_items%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ct.* INTO v_template FROM public.checklist_templates ct WHERE ct.id = p_template_id;
  IF v_template.id IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_template.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this template''s items';
  END IF;

  IF p_question IS NULL OR TRIM(p_question) = '' THEN
    RAISE EXCEPTION 'question is required';
  END IF;
  IF p_sequence IS NULL OR p_sequence <= 0 THEN
    RAISE EXCEPTION 'sequence must be > 0';
  END IF;

  IF p_item_id IS NOT NULL THEN
    UPDATE public.checklist_template_items cti
    SET question = TRIM(p_question),
        section = NULLIF(TRIM(COALESCE(p_section, '')), ''),
        help_text = NULLIF(TRIM(COALESCE(p_help_text, '')), ''),
        sequence = p_sequence,
        is_required = p_is_required,
        is_active = p_is_active
    WHERE cti.id = p_item_id AND cti.template_id = p_template_id
    RETURNING cti.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Item not found for this template';
    END IF;
  ELSE
    INSERT INTO public.checklist_template_items AS cti (template_id, section, question, help_text, sequence, is_required, is_active)
    VALUES (p_template_id, NULLIF(TRIM(COALESCE(p_section, '')), ''), TRIM(p_question), NULLIF(TRIM(COALESCE(p_help_text, '')), ''), p_sequence, p_is_required, p_is_active)
    RETURNING cti.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_checklist_template_item(uuid, text, text, text, integer, boolean, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_checklist_template_item(uuid, text, text, text, integer, boolean, uuid, boolean) TO authenticated;

-- =========================================================================
-- B4) set_checklist_template_item_active
-- =========================================================================
CREATE OR REPLACE FUNCTION public.set_checklist_template_item_active(p_item_id uuid, p_is_active boolean)
RETURNS public.checklist_template_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organization_id uuid;
  v_saved public.checklist_template_items%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ct.organization_id INTO v_organization_id
  FROM public.checklist_template_items cti
  INNER JOIN public.checklist_templates ct ON ct.id = cti.template_id
  WHERE cti.id = p_item_id;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this template''s items';
  END IF;

  UPDATE public.checklist_template_items cti
  SET is_active = p_is_active
  WHERE cti.id = p_item_id
  RETURNING cti.* INTO v_saved;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.set_checklist_template_item_active(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_checklist_template_item_active(uuid, boolean) TO authenticated;

-- =========================================================================
-- B5) upsert_checklist_response_option
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_checklist_response_option(
  p_template_id uuid,
  p_label text,
  p_value text,
  p_score numeric DEFAULT NULL,
  p_is_failure boolean DEFAULT false,
  p_sequence integer DEFAULT 1,
  p_option_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.checklist_template_response_options
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template public.checklist_templates%ROWTYPE;
  v_saved public.checklist_template_response_options%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ct.* INTO v_template FROM public.checklist_templates ct WHERE ct.id = p_template_id;
  IF v_template.id IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_template.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this template''s response options';
  END IF;

  IF p_label IS NULL OR TRIM(p_label) = '' THEN
    RAISE EXCEPTION 'label is required';
  END IF;
  IF p_value IS NULL OR TRIM(p_value) = '' THEN
    RAISE EXCEPTION 'value is required';
  END IF;
  IF p_sequence IS NULL OR p_sequence <= 0 THEN
    RAISE EXCEPTION 'sequence must be > 0';
  END IF;

  IF p_option_id IS NOT NULL THEN
    UPDATE public.checklist_template_response_options ctro
    SET label = TRIM(p_label),
        value = TRIM(p_value),
        score = p_score,
        is_failure = p_is_failure,
        sequence = p_sequence,
        is_active = p_is_active
    WHERE ctro.id = p_option_id AND ctro.template_id = p_template_id
    RETURNING ctro.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Response option not found for this template';
    END IF;
  ELSE
    INSERT INTO public.checklist_template_response_options AS ctro (template_id, label, value, score, is_failure, sequence, is_active)
    VALUES (p_template_id, TRIM(p_label), TRIM(p_value), p_score, p_is_failure, p_sequence, p_is_active)
    RETURNING ctro.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_checklist_response_option(uuid, text, text, numeric, boolean, integer, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_checklist_response_option(uuid, text, text, numeric, boolean, integer, uuid, boolean) TO authenticated;

-- =========================================================================
-- B6) set_checklist_response_option_active
-- =========================================================================
CREATE OR REPLACE FUNCTION public.set_checklist_response_option_active(p_option_id uuid, p_is_active boolean)
RETURNS public.checklist_template_response_options
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organization_id uuid;
  v_saved public.checklist_template_response_options%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ct.organization_id INTO v_organization_id
  FROM public.checklist_template_response_options ctro
  INNER JOIN public.checklist_templates ct ON ct.id = ctro.template_id
  WHERE ctro.id = p_option_id;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Response option not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this template''s response options';
  END IF;

  UPDATE public.checklist_template_response_options ctro
  SET is_active = p_is_active
  WHERE ctro.id = p_option_id
  RETURNING ctro.* INTO v_saved;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.set_checklist_response_option_active(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_checklist_response_option_active(uuid, boolean) TO authenticated;

-- =========================================================================
-- B7) upsert_inspection_plan
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_inspection_plan(
  p_organization_id uuid,
  p_template_id uuid,
  p_title text,
  p_branch_id uuid DEFAULT NULL,
  p_area_asset_id uuid DEFAULT NULL,
  p_asset_id uuid DEFAULT NULL,
  p_responsible_member_id uuid DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_frequency text DEFAULT 'one_time',
  p_start_date date DEFAULT CURRENT_DATE,
  p_next_due_at timestamptz DEFAULT NULL,
  p_plan_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.inspection_plans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_saved public.inspection_plans%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage inspection plans for this organization';
  END IF;

  IF p_title IS NULL OR TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'title is required';
  END IF;
  IF p_frequency NOT IN ('one_time', 'daily', 'weekly', 'monthly', 'quarterly', 'semiannual', 'annual') THEN
    RAISE EXCEPTION 'Invalid frequency value';
  END IF;
  IF p_branch_id IS NULL AND p_area_asset_id IS NULL AND p_asset_id IS NULL THEN
    RAISE EXCEPTION 'At least one of branch_id, area_asset_id or asset_id is required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.checklist_templates ct WHERE ct.id = p_template_id AND ct.organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'template_id must belong to this organization';
  END IF;
  IF p_branch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.client_branches cb WHERE cb.id = p_branch_id AND cb.organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'branch_id must belong to this organization';
  END IF;
  IF p_area_asset_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.assets a WHERE a.id = p_area_asset_id AND a.organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'area_asset_id must belong to this organization';
  END IF;
  IF p_asset_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.assets a WHERE a.id = p_asset_id AND a.organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'asset_id must belong to this organization';
  END IF;
  -- responsible must be an active member of THIS organization, in a role
  -- that can plausibly own an inspection (technician/manager/admin/owner —
  -- not requester/quote_manager/operator/viewer).
  IF p_responsible_member_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.id = p_responsible_member_id
      AND om.organization_id = p_organization_id
      AND om.is_active
      AND om.role IN ('owner', 'admin', 'manager', 'technician')
  ) THEN
    RAISE EXCEPTION 'responsible_member_id must be an active owner/admin/manager/technician of this organization';
  END IF;

  IF p_plan_id IS NOT NULL THEN
    UPDATE public.inspection_plans ip
    SET template_id = p_template_id,
        branch_id = p_branch_id,
        area_asset_id = p_area_asset_id,
        asset_id = p_asset_id,
        responsible_member_id = p_responsible_member_id,
        title = TRIM(p_title),
        description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
        frequency = p_frequency,
        start_date = p_start_date,
        next_due_at = p_next_due_at,
        is_active = p_is_active
    WHERE ip.id = p_plan_id AND ip.organization_id = p_organization_id
    RETURNING ip.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Plan not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.inspection_plans AS ip (
      organization_id, template_id, branch_id, area_asset_id, asset_id, responsible_member_id,
      title, description, frequency, start_date, next_due_at, is_active, created_by_user_id
    ) VALUES (
      p_organization_id, p_template_id, p_branch_id, p_area_asset_id, p_asset_id, p_responsible_member_id,
      TRIM(p_title), NULLIF(TRIM(COALESCE(p_description, '')), ''), p_frequency, p_start_date, p_next_due_at, p_is_active, auth.uid()
    )
    RETURNING ip.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_inspection_plan(uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, date, timestamptz, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_inspection_plan(uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, date, timestamptz, uuid, boolean) TO authenticated;

-- =========================================================================
-- B8) get_inspection_plans: flat rows with template/target/responsible
-- names already resolved, ready for a list view — no client-side joins.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_inspection_plans(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
RETURNS TABLE (
  id uuid,
  template_id uuid,
  template_name text,
  branch_id uuid,
  branch_name text,
  area_asset_id uuid,
  area_asset_name text,
  asset_id uuid,
  asset_name text,
  responsible_member_id uuid,
  responsible_name text,
  title text,
  description text,
  frequency text,
  start_date date,
  next_due_at timestamptz,
  is_active boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view inspection plans for this organization';
  END IF;

  RETURN QUERY
  SELECT
    ip.id,
    ip.template_id,
    ct.name AS template_name,
    ip.branch_id,
    cb.name AS branch_name,
    ip.area_asset_id,
    area_a.name AS area_asset_name,
    ip.asset_id,
    a.name AS asset_name,
    ip.responsible_member_id,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS responsible_name,
    ip.title,
    ip.description,
    ip.frequency,
    ip.start_date,
    ip.next_due_at,
    ip.is_active,
    ip.created_at
  FROM public.inspection_plans ip
  INNER JOIN public.checklist_templates ct ON ct.id = ip.template_id
  LEFT JOIN public.client_branches cb ON cb.id = ip.branch_id
  LEFT JOIN public.assets area_a ON area_a.id = ip.area_asset_id
  LEFT JOIN public.assets a ON a.id = ip.asset_id
  LEFT JOIN public.organization_members om ON om.id = ip.responsible_member_id
  LEFT JOIN auth.users au ON au.id = om.user_id
  WHERE ip.organization_id = p_organization_id AND (p_include_inactive OR ip.is_active)
  ORDER BY ip.next_due_at NULLS LAST, ip.title;
END;
$$;

REVOKE ALL ON FUNCTION public.get_inspection_plans(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_inspection_plans(uuid, boolean) TO authenticated;

-- =========================================================================
-- B8b) get_inspection_runs — not in the original numbered RPC list, added
-- because the "Ejecuciones / Historial" list view has no other clean way
-- to read inspection_runs with its target/responsible names resolved:
-- inspection_runs has two separate FKs into assets (area_asset_id and
-- asset_id), so a plain PostgREST embedded-resource select would be
-- ambiguous, and the responsible member's display name needs a second
-- join into auth.users besides. Same flat-row shape and
-- p_include_inactive-style optional filter convention as
-- get_inspection_plans.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_inspection_runs(p_organization_id uuid, p_status text DEFAULT NULL)
RETURNS TABLE (
  id uuid,
  organization_id uuid,
  plan_id uuid,
  template_id uuid,
  template_name text,
  branch_name text,
  area_asset_name text,
  asset_name text,
  responsible_member_id uuid,
  responsible_name text,
  scheduled_for timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  status text,
  result text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view inspection runs for this organization';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('scheduled', 'in_progress', 'completed', 'cancelled', 'overdue') THEN
    RAISE EXCEPTION 'Invalid status value';
  END IF;

  RETURN QUERY
  SELECT
    ir.id,
    ir.organization_id,
    ir.plan_id,
    ir.template_id,
    ct.name AS template_name,
    cb.name AS branch_name,
    area_a.name AS area_asset_name,
    a.name AS asset_name,
    ir.responsible_member_id,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS responsible_name,
    ir.scheduled_for,
    ir.started_at,
    ir.completed_at,
    ir.status,
    ir.result
  FROM public.inspection_runs ir
  INNER JOIN public.checklist_templates ct ON ct.id = ir.template_id
  LEFT JOIN public.client_branches cb ON cb.id = ir.branch_id
  LEFT JOIN public.assets area_a ON area_a.id = ir.area_asset_id
  LEFT JOIN public.assets a ON a.id = ir.asset_id
  LEFT JOIN public.organization_members om ON om.id = ir.responsible_member_id
  LEFT JOIN auth.users au ON au.id = om.user_id
  WHERE ir.organization_id = p_organization_id AND (p_status IS NULL OR ir.status = p_status)
  ORDER BY COALESCE(ir.scheduled_for, ir.created_at) DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_inspection_runs(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_inspection_runs(uuid, text) TO authenticated;

-- =========================================================================
-- B9) create_inspection_run_from_plan: snapshots plan/template into a new
-- scheduled run. Callable by the plan's own responsible member (so a
-- technician can start their own assigned inspection) as well as
-- owner/admin/manager/platform_admin.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.create_inspection_run_from_plan(p_plan_id uuid)
RETURNS public.inspection_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.inspection_plans%ROWTYPE;
  v_is_responsible boolean;
  v_saved public.inspection_runs%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ip.* INTO v_plan FROM public.inspection_plans ip WHERE ip.id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RAISE EXCEPTION 'Plan not found';
  END IF;

  -- om.organization_id = v_plan.organization_id is redundant with the
  -- write-time guarantee in upsert_inspection_plan (a plan's
  -- responsible_member_id can never belong to another organization), but
  -- kept explicit here so this authorization check is self-contained and
  -- does not silently depend on that other function's behavior.
  v_is_responsible := v_plan.responsible_member_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.id = v_plan.responsible_member_id
      AND om.user_id = auth.uid()
      AND om.organization_id = v_plan.organization_id
      AND om.is_active
  );

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_plan.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
    OR v_is_responsible
  ) THEN
    RAISE EXCEPTION 'Not authorized to create a run for this plan';
  END IF;

  INSERT INTO public.inspection_runs AS ir (
    organization_id, plan_id, template_id, branch_id, area_asset_id, asset_id, responsible_member_id,
    scheduled_for, status, created_by_user_id
  ) VALUES (
    v_plan.organization_id, v_plan.id, v_plan.template_id, v_plan.branch_id, v_plan.area_asset_id, v_plan.asset_id, v_plan.responsible_member_id,
    v_plan.next_due_at, 'scheduled', auth.uid()
  )
  RETURNING ir.* INTO v_saved;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.create_inspection_run_from_plan(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_inspection_run_from_plan(uuid) TO authenticated;

-- =========================================================================
-- B10) get_inspection_run_detail: run header (with resolved target/
-- responsible/template names) + active template items + active response
-- options + any answers already saved for this run, bundled as one jsonb
-- object — everything InspectionRunDialog needs in a single round trip.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_inspection_run_detail(p_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_run public.inspection_runs%ROWTYPE;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ir.* INTO v_run FROM public.inspection_runs ir WHERE ir.id = p_run_id;
  IF v_run.id IS NULL THEN
    RAISE EXCEPTION 'Run not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(v_run.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this inspection run';
  END IF;

  SELECT jsonb_build_object(
    'id', ir.id,
    'organization_id', ir.organization_id,
    'plan_id', ir.plan_id,
    'template_id', ir.template_id,
    'template_name', ct.name,
    'branch_id', ir.branch_id,
    'branch_name', cb.name,
    'area_asset_id', ir.area_asset_id,
    'area_asset_name', area_a.name,
    'asset_id', ir.asset_id,
    'asset_name', a.name,
    'responsible_member_id', ir.responsible_member_id,
    'responsible_name', COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)),
    'scheduled_for', ir.scheduled_for,
    'started_at', ir.started_at,
    'completed_at', ir.completed_at,
    'status', ir.status,
    'result', ir.result,
    'notes', ir.notes,
    'created_at', ir.created_at,
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cti.id,
        'section', cti.section,
        'question', cti.question,
        'help_text', cti.help_text,
        'sequence', cti.sequence,
        'is_required', cti.is_required
      ) ORDER BY cti.sequence, cti.question)
      FROM public.checklist_template_items cti
      WHERE cti.template_id = ir.template_id AND cti.is_active
    ), '[]'::jsonb),
    'response_options', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ctro.id,
        'label', ctro.label,
        'value', ctro.value,
        'is_failure', ctro.is_failure,
        'sequence', ctro.sequence
      ) ORDER BY ctro.sequence, ctro.label)
      FROM public.checklist_template_response_options ctro
      WHERE ctro.template_id = ir.template_id AND ctro.is_active
    ), '[]'::jsonb),
    'answers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ira.id,
        'template_item_id', ira.template_item_id,
        'response_option_id', ira.response_option_id,
        'item_question', ira.item_question,
        'response_label', ira.response_label,
        'response_value', ira.response_value,
        'is_failure', ira.is_failure,
        'observations', ira.observations
      ))
      FROM public.inspection_run_answers ira
      WHERE ira.run_id = ir.id
    ), '[]'::jsonb),
    'evidences', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ire.id,
        'answer_id', ire.answer_id,
        'file_name', ire.file_name,
        'file_url', ire.file_url,
        'file_path', ire.file_path,
        'mime_type', ire.mime_type,
        'size_bytes', ire.size_bytes,
        'notes', ire.notes
      ))
      FROM public.inspection_run_evidences ire
      WHERE ire.run_id = ir.id
    ), '[]'::jsonb)
  ) INTO v_result
  FROM public.inspection_runs ir
  INNER JOIN public.checklist_templates ct ON ct.id = ir.template_id
  LEFT JOIN public.client_branches cb ON cb.id = ir.branch_id
  LEFT JOIN public.assets area_a ON area_a.id = ir.area_asset_id
  LEFT JOIN public.assets a ON a.id = ir.asset_id
  LEFT JOIN public.organization_members om ON om.id = ir.responsible_member_id
  LEFT JOIN auth.users au ON au.id = om.user_id
  WHERE ir.id = p_run_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_inspection_run_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_inspection_run_detail(uuid) TO authenticated;

-- =========================================================================
-- B11) submit_inspection_run
--
-- p_answers shape: [{ "template_item_id": "...", "response_option_id":
-- "...", "observations": "..." }, ...]. Every active+required item of the
-- run's template must be present exactly once (extra/optional items may be
-- included or omitted freely) — validated in a first pass with no writes,
-- same two-pass shape as calculate_asset_criticality, before pass two
-- wipes and reinserts this run's answers (same "delete then reinsert"
-- pattern already used for work_order_activity_technicians).
--
-- result: 'failed' if any answered option has is_failure = true; else
-- 'not_applicable' if every answered option's value = 'not_applicable';
-- else 'passed'. No automatic work order is created on failure yet — see
-- docs/GENERIC_CHECKLISTS_INSPECTIONS.md "Próximos pasos".
-- =========================================================================
CREATE OR REPLACE FUNCTION public.submit_inspection_run(
  p_run_id uuid,
  p_started_at timestamptz,
  p_completed_at timestamptz,
  p_answers jsonb,
  p_evidences jsonb DEFAULT '[]'::jsonb,
  p_notes text DEFAULT NULL
)
RETURNS public.inspection_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_run public.inspection_runs%ROWTYPE;
  v_is_responsible boolean;
  v_answer jsonb;
  v_evidence jsonb;
  v_item_id uuid;
  v_option_id uuid;
  v_item public.checklist_template_items%ROWTYPE;
  v_option public.checklist_template_response_options%ROWTYPE;
  v_required_count integer;
  v_answered_item_ids uuid[] := ARRAY[]::uuid[];
  v_distinct_answered_count integer;
  v_any_failure boolean := false;
  v_all_not_applicable boolean := true;
  v_answered_count integer := 0;
  v_result text;
  v_saved public.inspection_runs%ROWTYPE;
  v_answer_id uuid;
  v_frequency_interval interval;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ir.* INTO v_run FROM public.inspection_runs ir WHERE ir.id = p_run_id;
  IF v_run.id IS NULL THEN
    RAISE EXCEPTION 'Run not found';
  END IF;

  -- Same explicit organization_id check as create_inspection_run_from_plan
  -- above, for the same self-containment reason.
  v_is_responsible := v_run.responsible_member_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.id = v_run.responsible_member_id
      AND om.user_id = auth.uid()
      AND om.organization_id = v_run.organization_id
      AND om.is_active
  );

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_run.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
    OR v_is_responsible
  ) THEN
    RAISE EXCEPTION 'Not authorized to submit this inspection run';
  END IF;

  IF p_started_at IS NULL OR p_completed_at IS NULL THEN
    RAISE EXCEPTION 'started_at and completed_at are required';
  END IF;
  IF p_completed_at < p_started_at THEN
    RAISE EXCEPTION 'completed_at must not be before started_at';
  END IF;
  IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'array' OR jsonb_array_length(p_answers) = 0 THEN
    RAISE EXCEPTION 'p_answers must be a non-empty JSON array';
  END IF;

  SELECT COUNT(*) INTO v_required_count
  FROM public.checklist_template_items cti
  WHERE cti.template_id = v_run.template_id AND cti.is_active AND cti.is_required;

  -- Pass 1: validate every answer, never write.
  FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
    v_item_id := NULLIF(v_answer->>'template_item_id', '')::uuid;
    v_option_id := NULLIF(v_answer->>'response_option_id', '')::uuid;

    IF v_item_id IS NULL THEN
      RAISE EXCEPTION 'Each answer requires a template_item_id';
    END IF;

    SELECT cti.* INTO v_item FROM public.checklist_template_items cti
      WHERE cti.id = v_item_id AND cti.template_id = v_run.template_id;
    IF v_item.id IS NULL THEN
      RAISE EXCEPTION 'template_item_id % does not belong to this run''s template', v_item_id;
    END IF;

    IF v_option_id IS NOT NULL THEN
      SELECT ctro.* INTO v_option FROM public.checklist_template_response_options ctro
        WHERE ctro.id = v_option_id AND ctro.template_id = v_run.template_id AND ctro.is_active;
      IF v_option.id IS NULL THEN
        RAISE EXCEPTION 'response_option_id % is not an active option of this run''s template', v_option_id;
      END IF;
    END IF;

    v_answered_item_ids := array_append(v_answered_item_ids, v_item_id);
  END LOOP;

  SELECT COUNT(DISTINCT x) INTO v_distinct_answered_count FROM unnest(v_answered_item_ids) AS x;
  IF v_distinct_answered_count <> array_length(v_answered_item_ids, 1) THEN
    RAISE EXCEPTION 'p_answers contains a duplicate template_item_id';
  END IF;

  -- Every active+required item must be answered (optional/inactive items
  -- may be included or omitted freely).
  IF (
    SELECT COUNT(*) FROM public.checklist_template_items cti
    WHERE cti.template_id = v_run.template_id AND cti.is_active AND cti.is_required
      AND cti.id = ANY (v_answered_item_ids)
  ) <> v_required_count THEN
    RAISE EXCEPTION 'All required items of this template must be answered';
  END IF;

  -- Pass 2: wipe and reinsert this run's answers, computing the result as
  -- we go (an unanswered response_option_id — item skipped as
  -- not-applicable-without-a-selection — never counts as a failure and
  -- never counts as "all not_applicable" either).
  DELETE FROM public.inspection_run_answers ira WHERE ira.run_id = p_run_id;

  FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
    v_item_id := (v_answer->>'template_item_id')::uuid;
    v_option_id := NULLIF(v_answer->>'response_option_id', '')::uuid;

    SELECT cti.* INTO v_item FROM public.checklist_template_items cti WHERE cti.id = v_item_id;

    IF v_option_id IS NOT NULL THEN
      SELECT ctro.* INTO v_option FROM public.checklist_template_response_options ctro WHERE ctro.id = v_option_id;
      v_answered_count := v_answered_count + 1;
      IF v_option.is_failure THEN v_any_failure := true; END IF;
      IF v_option.value <> 'not_applicable' THEN v_all_not_applicable := false; END IF;
    ELSE
      v_option := NULL;
      v_all_not_applicable := false;
    END IF;

    INSERT INTO public.inspection_run_answers AS ira (
      run_id, template_item_id, response_option_id, item_question, response_label, response_value, is_failure, observations
    ) VALUES (
      p_run_id, v_item_id, v_option_id, v_item.question,
      CASE WHEN v_option_id IS NOT NULL THEN v_option.label ELSE NULL END,
      CASE WHEN v_option_id IS NOT NULL THEN v_option.value ELSE NULL END,
      CASE WHEN v_option_id IS NOT NULL THEN v_option.is_failure ELSE false END,
      NULLIF(TRIM(COALESCE(v_answer->>'observations', '')), '')
    )
    RETURNING ira.id INTO v_answer_id;

    IF p_evidences IS NOT NULL THEN
      FOR v_evidence IN
        SELECT e.value FROM jsonb_array_elements(p_evidences) AS e(value)
        WHERE (e.value->>'template_item_id')::uuid = v_item_id
      LOOP
        INSERT INTO public.inspection_run_evidences (run_id, answer_id, file_name, file_url, file_path, mime_type, size_bytes, notes)
        VALUES (
          p_run_id, v_answer_id, v_evidence->>'file_name', NULLIF(v_evidence->>'file_url', ''),
          NULLIF(v_evidence->>'file_path', ''), NULLIF(v_evidence->>'mime_type', ''),
          NULLIF(v_evidence->>'size_bytes', '')::bigint, NULLIF(v_evidence->>'notes', '')
        );
      END LOOP;
    END IF;
  END LOOP;

  -- Evidences not tied to any specific item (no template_item_id in the
  -- payload) attach to the run as a whole (answer_id NULL).
  IF p_evidences IS NOT NULL THEN
    FOR v_evidence IN
      SELECT e.value FROM jsonb_array_elements(p_evidences) AS e(value)
      WHERE NULLIF(e.value->>'template_item_id', '') IS NULL
    LOOP
      INSERT INTO public.inspection_run_evidences (run_id, answer_id, file_name, file_url, file_path, mime_type, size_bytes, notes)
      VALUES (
        p_run_id, NULL, v_evidence->>'file_name', NULLIF(v_evidence->>'file_url', ''),
        NULLIF(v_evidence->>'file_path', ''), NULLIF(v_evidence->>'mime_type', ''),
        NULLIF(v_evidence->>'size_bytes', '')::bigint, NULLIF(v_evidence->>'notes', '')
      );
    END LOOP;
  END IF;

  v_result := CASE
    WHEN v_any_failure THEN 'failed'
    WHEN v_answered_count > 0 AND v_all_not_applicable THEN 'not_applicable'
    ELSE 'passed'
  END;

  UPDATE public.inspection_runs ir
  SET started_at = p_started_at,
      completed_at = p_completed_at,
      status = 'completed',
      result = v_result,
      notes = NULLIF(TRIM(COALESCE(p_notes, '')), '')
  WHERE ir.id = p_run_id
  RETURNING ir.* INTO v_saved;

  -- Advance the originating plan's next_due_at from the completion time,
  -- so a late inspection does not compound drift into the following cycle.
  -- one_time plans are left as-is (a single occurrence has no "next").
  IF v_saved.plan_id IS NOT NULL THEN
    SELECT CASE
      WHEN ip.frequency = 'daily' THEN interval '1 day'
      WHEN ip.frequency = 'weekly' THEN interval '7 days'
      WHEN ip.frequency = 'monthly' THEN interval '1 month'
      WHEN ip.frequency = 'quarterly' THEN interval '3 months'
      WHEN ip.frequency = 'semiannual' THEN interval '6 months'
      WHEN ip.frequency = 'annual' THEN interval '1 year'
      ELSE NULL
    END INTO v_frequency_interval
    FROM public.inspection_plans ip
    WHERE ip.id = v_saved.plan_id AND ip.is_active;

    IF v_frequency_interval IS NOT NULL THEN
      UPDATE public.inspection_plans ip
      SET next_due_at = v_saved.completed_at + v_frequency_interval
      WHERE ip.id = v_saved.plan_id;
    END IF;
  END IF;

  IF v_saved.asset_id IS NOT NULL THEN
    INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
    SELECT
      v_saved.organization_id,
      v_saved.asset_id,
      'inspection_completed',
      'Inspección completada: ' || ct.name || ' (' || v_result || ')',
      jsonb_build_object('result', v_result, 'template_id', v_saved.template_id, 'template_name', ct.name, 'run_id', v_saved.id),
      auth.uid()
    FROM public.checklist_templates ct
    WHERE ct.id = v_saved.template_id;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_inspection_run(uuid, timestamptz, timestamptz, jsonb, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_inspection_run(uuid, timestamptz, timestamptz, jsonb, jsonb, text) TO authenticated;

-- =========================================================================
-- B12) generate_inspection_due_notifications — same "no cron, called
-- best-effort from the frontend" shape as generate_operational_due_notifications.
--
-- Per-cycle idempotency: unlike a work order (one due_at it reaches once),
-- the SAME inspection_plans.id recurs across many cycles, each with its
-- own next_due_at. create_notification_once's dedup key is only
-- (organization, type, entity_type, entity_id) — reusing plan.id as
-- entity_id verbatim would mean a plan only ever gets ONE "due soon" (and
-- one "overdue") notification for its entire lifetime, silently going
-- quiet after the first cycle. To keep create_notification_once unchanged
-- (it is shared with the OT notifications) while still notifying once per
-- cycle, entity_id here is a deterministic hash of
-- (plan_id, next_due_at) — a fresh value every time next_due_at moves
-- forward (e.g. after submit_inspection_run advances it), so each cycle
-- naturally gets its own dedup slot. This id does not reference a real
-- row anywhere; entity_id already has no FK constraint in
-- organization_notifications.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.generate_inspection_due_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan record;
  v_cycle_entity_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  FOR v_plan IN
    SELECT ip.id, ip.title, ip.organization_id, ip.responsible_member_id, ip.next_due_at
    FROM public.inspection_plans ip
    WHERE ip.is_active
      AND ip.next_due_at IS NOT NULL
      AND ip.next_due_at >= now()
      AND ip.next_due_at <= now() + interval '7 days'
  LOOP
    v_cycle_entity_id := md5(v_plan.id::text || '|due_soon|' || v_plan.next_due_at::text)::uuid;

    PERFORM public.notify_role_members(
      v_plan.organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL,
      'inspection_due_soon_future',
      'Inspección próxima a vencer',
      'La inspección "' || v_plan.title || '" vence en menos de 7 días.',
      'inspection_plan',
      v_cycle_entity_id,
      'medium',
      jsonb_build_object('plan_id', v_plan.id, 'title', v_plan.title, 'next_due_at', v_plan.next_due_at)
    );
    IF v_plan.responsible_member_id IS NOT NULL THEN
      PERFORM public.notify_member(
        v_plan.responsible_member_id,
        NULL,
        'inspection_due_soon_future',
        'Inspección próxima a vencer',
        'La inspección "' || v_plan.title || '" vence en menos de 7 días.',
        'inspection_plan',
        v_cycle_entity_id,
        'medium',
        jsonb_build_object('plan_id', v_plan.id, 'title', v_plan.title, 'next_due_at', v_plan.next_due_at)
      );
    END IF;
  END LOOP;

  FOR v_plan IN
    SELECT ip.id, ip.title, ip.organization_id, ip.responsible_member_id, ip.next_due_at
    FROM public.inspection_plans ip
    WHERE ip.is_active
      AND ip.next_due_at IS NOT NULL
      AND ip.next_due_at < now()
  LOOP
    v_cycle_entity_id := md5(v_plan.id::text || '|overdue|' || v_plan.next_due_at::text)::uuid;

    PERFORM public.notify_role_members(
      v_plan.organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL,
      'inspection_overdue_future',
      'Inspección vencida',
      'La inspección "' || v_plan.title || '" está vencida.',
      'inspection_plan',
      v_cycle_entity_id,
      'urgent',
      jsonb_build_object('plan_id', v_plan.id, 'title', v_plan.title, 'next_due_at', v_plan.next_due_at)
    );
    IF v_plan.responsible_member_id IS NOT NULL THEN
      PERFORM public.notify_member(
        v_plan.responsible_member_id,
        NULL,
        'inspection_overdue_future',
        'Inspección vencida',
        'La inspección "' || v_plan.title || '" está vencida.',
        'inspection_plan',
        v_cycle_entity_id,
        'urgent',
        jsonb_build_object('plan_id', v_plan.id, 'title', v_plan.title, 'next_due_at', v_plan.next_due_at)
      );
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_inspection_due_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_inspection_due_notifications() TO authenticated;

-- =========================================================================
-- C) get_asset_integrated_history: teach the existing "asset_event" branch
-- to render a readable Spanish label for event_type = 'inspection_completed'
-- (inserted by submit_inspection_run above), same CASE/ELSE fallback shape
-- already extended once for 'criticality_assessed'. No other branch of
-- this function changes.
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
      WHEN 'inspection_completed' THEN 'Inspección completada'
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
      WHEN 'inspection_completed' THEN 'Inspección completada'
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
