-- Configurable inspection scheduling and alerts, on top of the generic
-- checklist/inspection engine from 20260829200000_generic_checklists_inspections.sql
-- (already merged — this migration only adds columns/tables/functions on
-- top of it, never edits that file). ITSE stays exactly what it already
-- was: a checklist_templates row, never a module — nothing here is
-- ITSE-specific; these alert rules work identically for "luces de
-- emergencia", "techos", "auditoría interna", "mantenimiento preventivo",
-- or any other template's plan.
--
-- Two changes to inspection_plans (custom_interval/custom_unit, and the
-- 'custom' frequency value) plus a new inspection_plan_alert_rules table
-- replace the old hardcoded "always warn exactly 7 days before" window in
-- generate_inspection_due_notifications() with per-plan configurable rules
-- (e.g. ITSE's own 90/60/30-days-before + vencido).
--
-- Every reference qualified with a short alias from the first line
-- (ip/ipar/ir/ct/om/au) — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the class
-- of bug this is deliberately avoiding.

-- =========================================================================
-- A1) inspection_plans: add custom_interval/custom_unit, extend frequency.
-- 'daily' is kept in the allowed values for backward compatibility with
-- any pre-existing row (the MVP UI never offers it as a choice going
-- forward — see docs/INSPECTION_SCHEDULING_ALERTS.md).
-- =========================================================================
ALTER TABLE public.inspection_plans
  ADD COLUMN IF NOT EXISTS custom_interval integer NULL,
  ADD COLUMN IF NOT EXISTS custom_unit text NULL;

ALTER TABLE public.inspection_plans DROP CONSTRAINT IF EXISTS inspection_plans_frequency_check;
ALTER TABLE public.inspection_plans ADD CONSTRAINT inspection_plans_frequency_check
  CHECK (frequency IN ('one_time', 'daily', 'weekly', 'monthly', 'quarterly', 'semiannual', 'annual', 'custom'));

DO $$ BEGIN
  ALTER TABLE public.inspection_plans ADD CONSTRAINT inspection_plans_custom_interval_check
    CHECK (
      (frequency = 'custom' AND custom_interval IS NOT NULL AND custom_interval > 0)
      OR (frequency <> 'custom' AND custom_interval IS NULL)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.inspection_plans ADD CONSTRAINT inspection_plans_custom_unit_check
    CHECK (
      (frequency = 'custom' AND custom_unit IN ('days', 'weeks', 'months', 'years'))
      OR (frequency <> 'custom' AND custom_unit IS NULL)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =========================================================================
-- A2) inspection_plan_alert_rules — configurable "avisar N días antes" /
-- "avisar cuando esté vencido" rules per plan. Never referenced by any
-- historical/frozen data elsewhere (unlike checklist items, which are
-- snapshotted into inspection_run_answers) — replace_inspection_plan_alert_rules
-- below hard-deletes and reinserts the full set on every save, which is
-- safe precisely because nothing else points at a specific rule row.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.inspection_plan_alert_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES public.inspection_plans(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  alert_type text NOT NULL,
  days_before integer NULL,
  label text NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inspection_plan_alert_rules_type_check CHECK (alert_type IN ('before_due', 'overdue')),
  CONSTRAINT inspection_plan_alert_rules_days_before_check CHECK (
    (alert_type = 'before_due' AND days_before IS NOT NULL AND days_before >= 0)
    OR (alert_type = 'overdue' AND days_before IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_inspection_plan_alert_rules_plan_id ON public.inspection_plan_alert_rules (plan_id);
CREATE INDEX IF NOT EXISTS idx_inspection_plan_alert_rules_is_active ON public.inspection_plan_alert_rules (plan_id, is_active);

-- Two partial unique indexes (mirrors the criticality-matrix/notifications
-- pattern for "NULL never equals NULL"): before_due rules are unique per
-- (plan, days_before); at most one overdue rule per plan (days_before is
-- always NULL there, so it can't be part of a meaningful uniqueness key).
CREATE UNIQUE INDEX IF NOT EXISTS uq_inspection_plan_alert_rules_before_due
  ON public.inspection_plan_alert_rules (plan_id, days_before)
  WHERE alert_type = 'before_due';

CREATE UNIQUE INDEX IF NOT EXISTS uq_inspection_plan_alert_rules_overdue
  ON public.inspection_plan_alert_rules (plan_id)
  WHERE alert_type = 'overdue';

DROP TRIGGER IF EXISTS trg_inspection_plan_alert_rules_updated_at ON public.inspection_plan_alert_rules;
CREATE TRIGGER trg_inspection_plan_alert_rules_updated_at
BEFORE UPDATE ON public.inspection_plan_alert_rules
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Consistency guard: organization_id must equal the owning plan's own
-- organization_id — same shape as check_inspection_plan_organization.
CREATE OR REPLACE FUNCTION public.check_inspection_plan_alert_rule_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT ip.organization_id INTO v_org FROM public.inspection_plans ip WHERE ip.id = NEW.plan_id;
  IF v_org IS NULL OR v_org <> NEW.organization_id THEN
    RAISE EXCEPTION 'organization_id must match the organization_id of plan_id';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inspection_plan_alert_rules_check_org ON public.inspection_plan_alert_rules;
CREATE TRIGGER trg_inspection_plan_alert_rules_check_org
BEFORE INSERT OR UPDATE ON public.inspection_plan_alert_rules
FOR EACH ROW EXECUTE FUNCTION public.check_inspection_plan_alert_rule_organization();

-- =========================================================================
-- RLS. Same tightest pattern as the rest of the inspections engine: any
-- active organization member (or platform_admin) can read; every write
-- goes exclusively through the SECURITY DEFINER RPCs below.
-- =========================================================================
ALTER TABLE public.inspection_plan_alert_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organization members can view inspection plan alert rules" ON public.inspection_plan_alert_rules
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

GRANT SELECT ON TABLE public.inspection_plan_alert_rules TO authenticated;

-- =========================================================================
-- B1) get_inspection_plan_alert_rules
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_inspection_plan_alert_rules(p_plan_id uuid)
RETURNS TABLE (
  id uuid,
  plan_id uuid,
  alert_type text,
  days_before integer,
  label text,
  is_active boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organization_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ip.organization_id INTO v_organization_id FROM public.inspection_plans ip WHERE ip.id = p_plan_id;
  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Plan not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(v_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view alert rules for this plan';
  END IF;

  RETURN QUERY
  SELECT ipar.id, ipar.plan_id, ipar.alert_type, ipar.days_before, ipar.label, ipar.is_active
  FROM public.inspection_plan_alert_rules ipar
  WHERE ipar.plan_id = p_plan_id AND ipar.is_active
  ORDER BY ipar.alert_type, ipar.days_before DESC NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.get_inspection_plan_alert_rules(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_inspection_plan_alert_rules(uuid) TO authenticated;

-- =========================================================================
-- B2) upsert_inspection_plan_alert_rule
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_inspection_plan_alert_rule(
  p_plan_id uuid,
  p_alert_type text,
  p_days_before integer DEFAULT NULL,
  p_label text DEFAULT NULL,
  p_rule_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.inspection_plan_alert_rules
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.inspection_plans%ROWTYPE;
  v_saved public.inspection_plan_alert_rules%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ip.* INTO v_plan FROM public.inspection_plans ip WHERE ip.id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RAISE EXCEPTION 'Plan not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_plan.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage alert rules for this plan';
  END IF;

  IF p_alert_type NOT IN ('before_due', 'overdue') THEN
    RAISE EXCEPTION 'Invalid alert_type value';
  END IF;
  IF p_alert_type = 'before_due' AND (p_days_before IS NULL OR p_days_before < 0) THEN
    RAISE EXCEPTION 'days_before is required and must be >= 0 for a before_due alert';
  END IF;
  IF p_alert_type = 'overdue' AND p_days_before IS NOT NULL THEN
    RAISE EXCEPTION 'days_before must be null for an overdue alert';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.inspection_plan_alert_rules ipar
    WHERE ipar.plan_id = p_plan_id
      AND ipar.alert_type = p_alert_type
      AND ipar.days_before IS NOT DISTINCT FROM p_days_before
      AND (p_rule_id IS NULL OR ipar.id <> p_rule_id)
  ) THEN
    RAISE EXCEPTION 'A rule with this alert_type/days_before already exists for this plan';
  END IF;

  IF p_rule_id IS NOT NULL THEN
    UPDATE public.inspection_plan_alert_rules ipar
    SET alert_type = p_alert_type,
        days_before = p_days_before,
        label = NULLIF(TRIM(COALESCE(p_label, '')), ''),
        is_active = p_is_active
    WHERE ipar.id = p_rule_id AND ipar.plan_id = p_plan_id
    RETURNING ipar.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Alert rule not found for this plan';
    END IF;
  ELSE
    INSERT INTO public.inspection_plan_alert_rules AS ipar (plan_id, organization_id, alert_type, days_before, label, is_active)
    VALUES (p_plan_id, v_plan.organization_id, p_alert_type, p_days_before, NULLIF(TRIM(COALESCE(p_label, '')), ''), p_is_active)
    RETURNING ipar.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_inspection_plan_alert_rule(uuid, text, integer, text, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_inspection_plan_alert_rule(uuid, text, integer, text, uuid, boolean) TO authenticated;

-- =========================================================================
-- B3) set_inspection_plan_alert_rule_active
-- =========================================================================
CREATE OR REPLACE FUNCTION public.set_inspection_plan_alert_rule_active(p_rule_id uuid, p_is_active boolean)
RETURNS public.inspection_plan_alert_rules
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organization_id uuid;
  v_saved public.inspection_plan_alert_rules%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ipar.organization_id INTO v_organization_id
  FROM public.inspection_plan_alert_rules ipar
  WHERE ipar.id = p_rule_id;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Alert rule not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this alert rule';
  END IF;

  UPDATE public.inspection_plan_alert_rules ipar
  SET is_active = p_is_active
  WHERE ipar.id = p_rule_id
  RETURNING ipar.* INTO v_saved;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.set_inspection_plan_alert_rule_active(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_inspection_plan_alert_rule_active(uuid, boolean) TO authenticated;

-- =========================================================================
-- B4) replace_inspection_plan_alert_rules — the RPC the plan form actually
-- uses: replaces the plan's entire rule set in one call, keeping the
-- dialog simple (no per-rule add/remove round trips). Hard-deletes the
-- previous rules and inserts the new set — safe because no other table
-- references a specific rule row (see the table's own header comment).
-- Implicitly transactional: everything below runs inside the single
-- transaction PostgreSQL already wraps around this function call.
--
-- p_rules example:
--   [ { "alert_type": "before_due", "days_before": 90, "label": "90 días antes" },
--     { "alert_type": "before_due", "days_before": 60, "label": "60 días antes" },
--     { "alert_type": "before_due", "days_before": 30, "label": "30 días antes" },
--     { "alert_type": "overdue", "label": "Vencido" } ]
-- =========================================================================
CREATE OR REPLACE FUNCTION public.replace_inspection_plan_alert_rules(p_plan_id uuid, p_rules jsonb)
RETURNS SETOF public.inspection_plan_alert_rules
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.inspection_plans%ROWTYPE;
  v_rule jsonb;
  v_alert_type text;
  v_days_before integer;
  v_seen_keys text[] := ARRAY[]::text[];
  v_key text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ip.* INTO v_plan FROM public.inspection_plans ip WHERE ip.id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RAISE EXCEPTION 'Plan not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_plan.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage alert rules for this plan';
  END IF;

  IF p_rules IS NULL OR jsonb_typeof(p_rules) <> 'array' THEN
    RAISE EXCEPTION 'p_rules must be a JSON array';
  END IF;

  -- Validate every rule (and check for in-payload duplicates) before
  -- touching any row.
  FOR v_rule IN SELECT * FROM jsonb_array_elements(p_rules) LOOP
    v_alert_type := v_rule->>'alert_type';
    v_days_before := NULLIF(v_rule->>'days_before', '')::integer;

    IF v_alert_type NOT IN ('before_due', 'overdue') THEN
      RAISE EXCEPTION 'Invalid alert_type value: %', v_alert_type;
    END IF;
    IF v_alert_type = 'before_due' AND (v_days_before IS NULL OR v_days_before < 0) THEN
      RAISE EXCEPTION 'days_before is required and must be >= 0 for a before_due alert';
    END IF;
    IF v_alert_type = 'overdue' AND v_days_before IS NOT NULL THEN
      RAISE EXCEPTION 'days_before must be null for an overdue alert';
    END IF;

    v_key := v_alert_type || ':' || COALESCE(v_days_before::text, 'null');
    IF v_key = ANY (v_seen_keys) THEN
      RAISE EXCEPTION 'Duplicate alert rule in payload: %', v_key;
    END IF;
    v_seen_keys := array_append(v_seen_keys, v_key);
  END LOOP;

  DELETE FROM public.inspection_plan_alert_rules ipar WHERE ipar.plan_id = p_plan_id;

  FOR v_rule IN SELECT * FROM jsonb_array_elements(p_rules) LOOP
    INSERT INTO public.inspection_plan_alert_rules (plan_id, organization_id, alert_type, days_before, label, is_active)
    VALUES (
      p_plan_id,
      v_plan.organization_id,
      v_rule->>'alert_type',
      NULLIF(v_rule->>'days_before', '')::integer,
      NULLIF(TRIM(COALESCE(v_rule->>'label', '')), ''),
      true
    );
  END LOOP;

  RETURN QUERY
  SELECT ipar.* FROM public.inspection_plan_alert_rules ipar
  WHERE ipar.plan_id = p_plan_id
  ORDER BY ipar.alert_type, ipar.days_before DESC NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.replace_inspection_plan_alert_rules(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.replace_inspection_plan_alert_rules(uuid, jsonb) TO authenticated;

-- =========================================================================
-- B5) upsert_inspection_plan — two new trailing parameters
-- (p_custom_interval, p_custom_unit). Correction to this migration's own
-- first draft: appending parameters to an *already-deployed* function is
-- NOT safe via plain CREATE OR REPLACE the way it was for
-- get_criticality_matrix's p_include_inactive — that RPC had no prior
-- narrower version (it was introduced with that parameter already present
-- in its very first migration). Here, Postgres identifies a function by
-- (name, argument-type-list): a 13-arg and a 15-arg signature are two
-- *different* functions, so CREATE OR REPLACE alone would leave the old
-- 13-arg overload in place alongside the new 15-arg one — and PostgREST's
-- named-argument calling convention then can't disambiguate a call that
-- only supplies the original 13 names, raising
-- "function ... is not unique". DROP the old signature first.
-- =========================================================================
DROP FUNCTION IF EXISTS public.upsert_inspection_plan(uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, date, timestamptz, uuid, boolean);

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
  p_is_active boolean DEFAULT true,
  p_custom_interval integer DEFAULT NULL,
  p_custom_unit text DEFAULT NULL
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
  IF p_frequency NOT IN ('one_time', 'daily', 'weekly', 'monthly', 'quarterly', 'semiannual', 'annual', 'custom') THEN
    RAISE EXCEPTION 'Invalid frequency value';
  END IF;
  IF p_frequency = 'custom' THEN
    IF p_custom_interval IS NULL OR p_custom_interval <= 0 THEN
      RAISE EXCEPTION 'custom_interval must be > 0 when frequency is custom';
    END IF;
    IF p_custom_unit IS NULL OR p_custom_unit NOT IN ('days', 'weeks', 'months', 'years') THEN
      RAISE EXCEPTION 'custom_unit must be one of days/weeks/months/years when frequency is custom';
    END IF;
  ELSE
    -- Never persist stray custom_interval/custom_unit for a non-custom
    -- frequency, regardless of what the caller passed — keeps the two
    -- columns meaningful only together with frequency = 'custom'.
    p_custom_interval := NULL;
    p_custom_unit := NULL;
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
        is_active = p_is_active,
        custom_interval = p_custom_interval,
        custom_unit = p_custom_unit
    WHERE ip.id = p_plan_id AND ip.organization_id = p_organization_id
    RETURNING ip.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Plan not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.inspection_plans AS ip (
      organization_id, template_id, branch_id, area_asset_id, asset_id, responsible_member_id,
      title, description, frequency, start_date, next_due_at, is_active, created_by_user_id,
      custom_interval, custom_unit
    ) VALUES (
      p_organization_id, p_template_id, p_branch_id, p_area_asset_id, p_asset_id, p_responsible_member_id,
      TRIM(p_title), NULLIF(TRIM(COALESCE(p_description, '')), ''), p_frequency, p_start_date, p_next_due_at, p_is_active, auth.uid(),
      p_custom_interval, p_custom_unit
    )
    RETURNING ip.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_inspection_plan(uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, date, timestamptz, uuid, boolean, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_inspection_plan(uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, date, timestamptz, uuid, boolean, integer, text) TO authenticated;

-- =========================================================================
-- B6) get_inspection_plans — the set of OUT columns changes (custom_interval/
-- custom_unit/alert_rules added), which CREATE OR REPLACE cannot do for a
-- RETURNS TABLE function (Postgres error 42P13, same class of restriction
-- as a parameter rename — see 20260827170000_fix_work_order_activities_rpc_ambiguity.sql).
-- DROP FUNCTION first is required here.
-- =========================================================================
DROP FUNCTION IF EXISTS public.get_inspection_plans(uuid, boolean);

CREATE FUNCTION public.get_inspection_plans(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
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
  custom_interval integer,
  custom_unit text,
  start_date date,
  next_due_at timestamptz,
  is_active boolean,
  created_at timestamptz,
  alert_rules jsonb
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
    ip.custom_interval,
    ip.custom_unit,
    ip.start_date,
    ip.next_due_at,
    ip.is_active,
    ip.created_at,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ipar.id,
        'alert_type', ipar.alert_type,
        'days_before', ipar.days_before,
        'label', ipar.label,
        'is_active', ipar.is_active
      ) ORDER BY ipar.alert_type, ipar.days_before DESC NULLS LAST)
      FROM public.inspection_plan_alert_rules ipar
      WHERE ipar.plan_id = ip.id AND ipar.is_active
    ), '[]'::jsonb) AS alert_rules
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
-- B7) submit_inspection_run — next_due_at recalculation extended with
-- weekly/quarterly/semiannual/annual (already handled) plus 'custom'
-- (custom_interval/custom_unit). Same RETURNS type as before
-- (public.inspection_runs), so plain CREATE OR REPLACE is enough — no
-- DROP needed. Still anchored on completed_at, never on the previous
-- next_due_at, so a late inspection never compounds drift into the next
-- cycle.
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

  IF (
    SELECT COUNT(*) FROM public.checklist_template_items cti
    WHERE cti.template_id = v_run.template_id AND cti.is_active AND cti.is_required
      AND cti.id = ANY (v_answered_item_ids)
  ) <> v_required_count THEN
    RAISE EXCEPTION 'All required items of this template must be answered';
  END IF;

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

  -- Advance the originating plan's next_due_at from the completion time
  -- (never from the previous next_due_at), so a late inspection never
  -- compounds drift into the following cycle. one_time plans are left
  -- as-is (a single occurrence has no "next").
  IF v_saved.plan_id IS NOT NULL THEN
    SELECT CASE
      WHEN ip.frequency = 'daily' THEN interval '1 day'
      WHEN ip.frequency = 'weekly' THEN interval '7 days'
      WHEN ip.frequency = 'monthly' THEN interval '1 month'
      WHEN ip.frequency = 'quarterly' THEN interval '3 months'
      WHEN ip.frequency = 'semiannual' THEN interval '6 months'
      WHEN ip.frequency = 'annual' THEN interval '1 year'
      WHEN ip.frequency = 'custom' AND ip.custom_interval IS NOT NULL AND ip.custom_unit IS NOT NULL THEN
        CASE ip.custom_unit
          WHEN 'days' THEN make_interval(days => ip.custom_interval)
          WHEN 'weeks' THEN make_interval(weeks => ip.custom_interval)
          WHEN 'months' THEN make_interval(months => ip.custom_interval)
          WHEN 'years' THEN make_interval(years => ip.custom_interval)
          ELSE NULL
        END
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
-- B8) generate_inspection_due_notifications — replaces the old hardcoded
-- "always exactly 7 days before" window with the plan's own configured
-- inspection_plan_alert_rules. A plan with no active rules simply never
-- notifies anymore (no implicit default window) — see
-- docs/INSPECTION_SCHEDULING_ALERTS.md for why, and for the frontend
-- default (30 días antes + Vencido) offered when creating a new plan.
--
-- Per-cycle-per-rule idempotency: entity_id is now
-- md5(plan_id || rule_id || next_due_at)::uuid — including rule_id (not
-- just plan_id + next_due_at as in the previous phase) so two different
-- rules on the same plan/cycle (e.g. "90 días antes" and "60 días antes")
-- never collide into a single dedup slot and both get to notify
-- independently, while still never re-notifying for the same
-- plan+rule+cycle twice.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.generate_inspection_due_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_cycle_entity_id uuid;
  v_message text;
  v_metadata jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  FOR v_row IN
    SELECT
      ip.id AS plan_id, ip.title AS plan_title, ip.organization_id, ip.responsible_member_id,
      ip.next_due_at, ip.frequency, ip.custom_interval, ip.custom_unit, ct.name AS template_name,
      ipar.id AS rule_id, ipar.days_before, ipar.label
    FROM public.inspection_plans ip
    INNER JOIN public.checklist_templates ct ON ct.id = ip.template_id
    INNER JOIN public.inspection_plan_alert_rules ipar
      ON ipar.plan_id = ip.id AND ipar.is_active AND ipar.alert_type = 'before_due'
    WHERE ip.is_active
      AND ip.next_due_at IS NOT NULL
      AND now() >= (ip.next_due_at - make_interval(days => ipar.days_before))
      AND now() < ip.next_due_at
  LOOP
    v_cycle_entity_id := md5(v_row.plan_id::text || '|' || v_row.rule_id::text || '|' || v_row.next_due_at::text)::uuid;
    v_message := 'La inspección "' || v_row.plan_title || '" vence en ' || COALESCE(v_row.label, v_row.days_before || ' días') || '.';
    v_metadata := jsonb_build_object(
      'plan_id', v_row.plan_id,
      'plan_title', v_row.plan_title,
      'template_name', v_row.template_name,
      'next_due_at', v_row.next_due_at,
      'alert_type', 'before_due',
      'days_before', v_row.days_before,
      'frequency', v_row.frequency,
      'custom_interval', v_row.custom_interval,
      'custom_unit', v_row.custom_unit
    );

    PERFORM public.notify_role_members(
      v_row.organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL,
      'inspection_due_soon_future',
      'Inspección próxima a vencer',
      v_message,
      'inspection_plan',
      v_cycle_entity_id,
      'medium',
      v_metadata
    );
    IF v_row.responsible_member_id IS NOT NULL THEN
      PERFORM public.notify_member(
        v_row.responsible_member_id,
        NULL,
        'inspection_due_soon_future',
        'Inspección próxima a vencer',
        v_message,
        'inspection_plan',
        v_cycle_entity_id,
        'medium',
        v_metadata
      );
    END IF;
  END LOOP;

  FOR v_row IN
    SELECT
      ip.id AS plan_id, ip.title AS plan_title, ip.organization_id, ip.responsible_member_id,
      ip.next_due_at, ip.frequency, ip.custom_interval, ip.custom_unit, ct.name AS template_name,
      ipar.id AS rule_id, ipar.label
    FROM public.inspection_plans ip
    INNER JOIN public.checklist_templates ct ON ct.id = ip.template_id
    INNER JOIN public.inspection_plan_alert_rules ipar
      ON ipar.plan_id = ip.id AND ipar.is_active AND ipar.alert_type = 'overdue'
    WHERE ip.is_active
      AND ip.next_due_at IS NOT NULL
      AND ip.next_due_at < now()
  LOOP
    v_cycle_entity_id := md5(v_row.plan_id::text || '|' || v_row.rule_id::text || '|' || v_row.next_due_at::text)::uuid;
    v_message := 'La inspección "' || v_row.plan_title || '" está vencida.';
    v_metadata := jsonb_build_object(
      'plan_id', v_row.plan_id,
      'plan_title', v_row.plan_title,
      'template_name', v_row.template_name,
      'next_due_at', v_row.next_due_at,
      'alert_type', 'overdue',
      'days_before', NULL,
      'frequency', v_row.frequency,
      'custom_interval', v_row.custom_interval,
      'custom_unit', v_row.custom_unit
    );

    PERFORM public.notify_role_members(
      v_row.organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL,
      'inspection_overdue_future',
      'Inspección vencida',
      v_message,
      'inspection_plan',
      v_cycle_entity_id,
      'urgent',
      v_metadata
    );
    IF v_row.responsible_member_id IS NOT NULL THEN
      PERFORM public.notify_member(
        v_row.responsible_member_id,
        NULL,
        'inspection_overdue_future',
        'Inspección vencida',
        v_message,
        'inspection_plan',
        v_cycle_entity_id,
        'urgent',
        v_metadata
      );
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_inspection_due_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_inspection_due_notifications() TO authenticated;
