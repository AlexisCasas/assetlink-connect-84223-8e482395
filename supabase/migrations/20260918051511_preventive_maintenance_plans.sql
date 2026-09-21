-- Preventive maintenance: cards -> plans -> occurrences.
-- All writes are RPC/trigger-only. Tables expose SELECT through tenant RLS.

-- =========================================================================
-- A) Core tables
-- =========================================================================
CREATE TABLE public.maintenance_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  description text NULL,
  category text NULL,
  estimated_hours numeric(10,2) NULL,
  procedure_notes text NULL,
  safety_notes text NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT maintenance_cards_code_check CHECK (TRIM(code) <> ''),
  CONSTRAINT maintenance_cards_name_check CHECK (TRIM(name) <> ''),
  CONSTRAINT maintenance_cards_hours_check CHECK (estimated_hours IS NULL OR estimated_hours >= 0)
);

CREATE UNIQUE INDEX uq_maintenance_cards_org_code
  ON public.maintenance_cards (organization_id, lower(code));
CREATE INDEX idx_maintenance_cards_org_active
  ON public.maintenance_cards (organization_id, is_active);
CREATE INDEX idx_maintenance_cards_org_name
  ON public.maintenance_cards (organization_id, lower(name));

CREATE TABLE public.maintenance_card_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id uuid NOT NULL REFERENCES public.maintenance_cards(id) ON DELETE CASCADE,
  sequence integer NOT NULL,
  title text NOT NULL,
  description text NULL,
  estimated_hours numeric(10,2) NULL,
  is_required boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT maintenance_card_tasks_sequence_check CHECK (sequence > 0),
  CONSTRAINT maintenance_card_tasks_title_check CHECK (TRIM(title) <> ''),
  CONSTRAINT maintenance_card_tasks_hours_check CHECK (estimated_hours IS NULL OR estimated_hours >= 0),
  CONSTRAINT maintenance_card_tasks_sequence_unique UNIQUE (card_id, sequence)
);

CREATE INDEX idx_maintenance_card_tasks_card ON public.maintenance_card_tasks (card_id);

CREATE TABLE public.maintenance_card_materials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id uuid NOT NULL REFERENCES public.maintenance_cards(id) ON DELETE CASCADE,
  sequence integer NOT NULL,
  material_id uuid NULL REFERENCES public.materials(id) ON DELETE SET NULL,
  description text NOT NULL,
  quantity numeric(14,3) NOT NULL,
  unit text NOT NULL,
  notes text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT maintenance_card_materials_sequence_check CHECK (sequence > 0),
  CONSTRAINT maintenance_card_materials_description_check CHECK (TRIM(description) <> ''),
  CONSTRAINT maintenance_card_materials_quantity_check CHECK (quantity > 0),
  CONSTRAINT maintenance_card_materials_unit_check CHECK (TRIM(unit) <> ''),
  CONSTRAINT maintenance_card_materials_sequence_unique UNIQUE (card_id, sequence)
);

CREATE INDEX idx_maintenance_card_materials_card ON public.maintenance_card_materials (card_id);
CREATE INDEX idx_maintenance_card_materials_material ON public.maintenance_card_materials (material_id);

CREATE TABLE public.asset_meters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES public.assets(id) ON DELETE RESTRICT,
  name text NOT NULL,
  unit text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  replaces_meter_id uuid NULL REFERENCES public.asset_meters(id) ON DELETE RESTRICT,
  retired_at timestamptz NULL,
  retirement_reason text NULL,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT asset_meters_name_check CHECK (TRIM(name) <> ''),
  CONSTRAINT asset_meters_unit_check CHECK (TRIM(unit) <> ''),
  CONSTRAINT asset_meters_not_self_replacement CHECK (replaces_meter_id IS NULL OR replaces_meter_id <> id),
  CONSTRAINT asset_meters_retired_check CHECK (
    (is_active AND retired_at IS NULL)
    OR (NOT is_active AND retired_at IS NOT NULL AND retirement_reason IS NOT NULL AND TRIM(retirement_reason) <> '')
  )
);

CREATE UNIQUE INDEX uq_asset_meters_active_name
  ON public.asset_meters (asset_id, lower(name)) WHERE is_active;
CREATE INDEX idx_asset_meters_org_asset ON public.asset_meters (organization_id, asset_id);
CREATE INDEX idx_asset_meters_replaces ON public.asset_meters (replaces_meter_id);

CREATE TABLE public.asset_meter_readings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meter_id uuid NOT NULL REFERENCES public.asset_meters(id) ON DELETE RESTRICT,
  value numeric(20,3) NOT NULL,
  recorded_at timestamptz NOT NULL,
  notes text NULL,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  supersedes_reading_id uuid NULL REFERENCES public.asset_meter_readings(id) ON DELETE RESTRICT,
  voided_at timestamptz NULL,
  voided_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  void_reason text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT asset_meter_readings_value_check CHECK (value >= 0),
  CONSTRAINT asset_meter_readings_not_self_supersede CHECK (supersedes_reading_id IS NULL OR supersedes_reading_id <> id),
  CONSTRAINT asset_meter_readings_void_check CHECK (
    (voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL)
    OR (voided_at IS NOT NULL AND void_reason IS NOT NULL AND TRIM(void_reason) <> '')
  )
);

CREATE UNIQUE INDEX uq_asset_meter_readings_effective_time
  ON public.asset_meter_readings (meter_id, recorded_at) WHERE voided_at IS NULL;
CREATE UNIQUE INDEX uq_asset_meter_readings_supersedes
  ON public.asset_meter_readings (supersedes_reading_id) WHERE supersedes_reading_id IS NOT NULL;
CREATE INDEX idx_asset_meter_readings_latest
  ON public.asset_meter_readings (meter_id, recorded_at DESC) WHERE voided_at IS NULL;

CREATE TABLE public.preventive_maintenance_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES public.assets(id) ON DELETE RESTRICT,
  card_id uuid NOT NULL REFERENCES public.maintenance_cards(id) ON DELETE RESTRICT,
  trigger_type text NOT NULL,
  priority text NOT NULL DEFAULT 'medium',
  default_request_type text NOT NULL DEFAULT 'internal',
  responsible_member_id uuid NULL REFERENCES public.organization_members(id) ON DELETE SET NULL,
  planning_lead_days integer NOT NULL DEFAULT 30,
  frequency text NULL,
  custom_interval integer NULL,
  custom_unit text NULL,
  first_due_at timestamptz NULL,
  meter_id uuid NULL REFERENCES public.asset_meters(id) ON DELETE RESTRICT,
  interval_value numeric(20,3) NULL,
  baseline_value numeric(20,3) NULL,
  baseline_reading_id uuid NULL REFERENCES public.asset_meter_readings(id) ON DELETE RESTRICT,
  meter_lead_value numeric(20,3) NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT preventive_plans_trigger_check CHECK (trigger_type IN ('calendar', 'meter')),
  CONSTRAINT preventive_plans_priority_check CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  CONSTRAINT preventive_plans_request_type_check CHECK (default_request_type IN ('internal', 'external')),
  CONSTRAINT preventive_plans_lead_days_check CHECK (planning_lead_days >= 0),
  CONSTRAINT preventive_plans_frequency_check CHECK (
    frequency IS NULL OR frequency IN ('weekly', 'monthly', 'quarterly', 'semiannual', 'annual', 'custom')
  ),
  CONSTRAINT preventive_plans_custom_check CHECK (
    (frequency = 'custom' AND custom_interval IS NOT NULL AND custom_interval > 0 AND custom_unit IN ('days', 'weeks', 'months', 'years'))
    OR (frequency IS DISTINCT FROM 'custom' AND custom_interval IS NULL AND custom_unit IS NULL)
  ),
  CONSTRAINT preventive_plans_mode_check CHECK (
    (trigger_type = 'calendar'
      AND frequency IS NOT NULL AND first_due_at IS NOT NULL
      AND meter_id IS NULL AND interval_value IS NULL AND baseline_value IS NULL
      AND baseline_reading_id IS NULL AND meter_lead_value IS NULL)
    OR
    (trigger_type = 'meter'
      AND frequency IS NULL AND custom_interval IS NULL AND custom_unit IS NULL AND first_due_at IS NULL
      AND meter_id IS NOT NULL AND interval_value IS NOT NULL AND interval_value > 0
      AND baseline_value IS NOT NULL AND baseline_value >= 0 AND baseline_reading_id IS NOT NULL
      AND meter_lead_value IS NOT NULL AND meter_lead_value >= 0 AND meter_lead_value < interval_value)
  )
);

CREATE INDEX idx_preventive_plans_org_active ON public.preventive_maintenance_plans (organization_id, is_active);
CREATE INDEX idx_preventive_plans_asset ON public.preventive_maintenance_plans (asset_id);
CREATE INDEX idx_preventive_plans_card ON public.preventive_maintenance_plans (card_id);
CREATE INDEX idx_preventive_plans_meter ON public.preventive_maintenance_plans (meter_id);
CREATE INDEX idx_preventive_plans_responsible ON public.preventive_maintenance_plans (responsible_member_id);

CREATE TABLE public.preventive_maintenance_occurrences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  plan_id uuid NOT NULL REFERENCES public.preventive_maintenance_plans(id) ON DELETE RESTRICT,
  asset_id uuid NOT NULL REFERENCES public.assets(id) ON DELETE RESTRICT,
  sequence integer NOT NULL,
  due_at timestamptz NULL,
  due_meter_value numeric(20,3) NULL,
  status text NOT NULL DEFAULT 'open',
  request_creation_id uuid NOT NULL DEFAULT gen_random_uuid(),
  request_id uuid NULL REFERENCES public.requests(id) ON DELETE RESTRICT,
  work_order_id uuid NULL REFERENCES public.work_orders(id) ON DELETE RESTRICT,
  scope_snapshot jsonb NOT NULL,
  planned_at timestamptz NULL,
  completed_at timestamptz NULL,
  completion_meter_reading_id uuid NULL REFERENCES public.asset_meter_readings(id) ON DELETE RESTRICT,
  completion_meter_value numeric(20,3) NULL,
  skipped_at timestamptz NULL,
  skip_reason text NULL,
  cancelled_at timestamptz NULL,
  cancel_reason text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT preventive_occurrences_sequence_check CHECK (sequence > 0),
  CONSTRAINT preventive_occurrences_status_check CHECK (status IN ('open', 'planned', 'completed', 'skipped', 'cancelled')),
  CONSTRAINT preventive_occurrences_due_check CHECK (
    (due_at IS NOT NULL AND due_meter_value IS NULL)
    OR (due_at IS NULL AND due_meter_value IS NOT NULL)
  ),
  CONSTRAINT preventive_occurrences_snapshot_check CHECK (
    jsonb_typeof(scope_snapshot) = 'object' AND scope_snapshot ? 'schema_version'
  ),
  CONSTRAINT preventive_occurrences_state_check CHECK (
    (status = 'open' AND request_id IS NULL AND work_order_id IS NULL AND planned_at IS NULL
      AND completed_at IS NULL AND skipped_at IS NULL AND cancelled_at IS NULL)
    OR
    (status = 'planned' AND request_id IS NOT NULL AND planned_at IS NOT NULL
      AND completed_at IS NULL AND skipped_at IS NULL AND cancelled_at IS NULL)
    OR
    (status = 'completed' AND request_id IS NOT NULL AND work_order_id IS NOT NULL AND planned_at IS NOT NULL
      AND completed_at IS NOT NULL AND skipped_at IS NULL AND cancelled_at IS NULL)
    OR
    (status = 'skipped' AND request_id IS NULL AND work_order_id IS NULL AND completed_at IS NULL
      AND skipped_at IS NOT NULL AND skip_reason IS NOT NULL AND TRIM(skip_reason) <> '' AND cancelled_at IS NULL)
    OR
    (status = 'cancelled' AND completed_at IS NULL AND skipped_at IS NULL
      AND cancelled_at IS NOT NULL AND cancel_reason IS NOT NULL AND TRIM(cancel_reason) <> '')
  ),
  CONSTRAINT preventive_occurrences_plan_sequence_unique UNIQUE (plan_id, sequence),
  CONSTRAINT preventive_occurrences_request_creation_unique UNIQUE (request_creation_id)
);

CREATE UNIQUE INDEX uq_preventive_occurrences_one_current
  ON public.preventive_maintenance_occurrences (plan_id) WHERE status IN ('open', 'planned');
CREATE UNIQUE INDEX uq_preventive_occurrences_request
  ON public.preventive_maintenance_occurrences (request_id) WHERE request_id IS NOT NULL;
CREATE UNIQUE INDEX uq_preventive_occurrences_work_order
  ON public.preventive_maintenance_occurrences (work_order_id) WHERE work_order_id IS NOT NULL;
CREATE INDEX idx_preventive_occurrences_org_status_due
  ON public.preventive_maintenance_occurrences (organization_id, status, due_at);
CREATE INDEX idx_preventive_occurrences_org_status_meter
  ON public.preventive_maintenance_occurrences (organization_id, status, due_meter_value);
CREATE INDEX idx_preventive_occurrences_asset_status
  ON public.preventive_maintenance_occurrences (asset_id, status);

-- Internal work orders are one-per-request. External work orders keep their
-- existing quote_id uniqueness and are unaffected by this partial index.
CREATE UNIQUE INDEX uq_work_orders_internal_request
  ON public.work_orders (request_id) WHERE quote_id IS NULL;

-- =========================================================================
-- B) Updated-at and structural guards
-- =========================================================================
CREATE TRIGGER trg_maintenance_cards_updated_at
BEFORE UPDATE ON public.maintenance_cards
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TRIGGER trg_asset_meters_updated_at
BEFORE UPDATE ON public.asset_meters
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TRIGGER trg_preventive_plans_updated_at
BEFORE UPDATE ON public.preventive_maintenance_plans
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TRIGGER trg_preventive_occurrences_updated_at
BEFORE UPDATE ON public.preventive_maintenance_occurrences
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE OR REPLACE FUNCTION public.check_asset_meter_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_asset_org uuid;
  v_replaced public.asset_meters%ROWTYPE;
BEGIN
  SELECT a.organization_id INTO v_asset_org FROM public.assets a WHERE a.id = NEW.asset_id;
  IF v_asset_org IS NULL OR v_asset_org <> NEW.organization_id THEN
    RAISE EXCEPTION 'asset_id must belong to the meter organization';
  END IF;
  IF NEW.replaces_meter_id IS NOT NULL THEN
    SELECT am.* INTO v_replaced FROM public.asset_meters am WHERE am.id = NEW.replaces_meter_id;
    IF v_replaced.id IS NULL OR v_replaced.organization_id <> NEW.organization_id OR v_replaced.asset_id <> NEW.asset_id THEN
      RAISE EXCEPTION 'replaces_meter_id must belong to the same organization and asset';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_asset_meters_consistency
BEFORE INSERT OR UPDATE ON public.asset_meters
FOR EACH ROW EXECUTE FUNCTION public.check_asset_meter_consistency();

CREATE OR REPLACE FUNCTION public.check_preventive_plan_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_org_type public.organization_type;
  v_reading public.asset_meter_readings%ROWTYPE;
BEGIN
  SELECT o.organization_type INTO v_org_type FROM public.organizations o WHERE o.id = NEW.organization_id;
  IF v_org_type IS DISTINCT FROM 'client_company'::public.organization_type THEN
    RAISE EXCEPTION 'Preventive maintenance is only available to client_company organizations';
  END IF;
  SELECT a.organization_id INTO v_org FROM public.assets a WHERE a.id = NEW.asset_id;
  IF v_org IS NULL OR v_org <> NEW.organization_id THEN RAISE EXCEPTION 'asset_id must belong to this organization'; END IF;
  SELECT mc.organization_id INTO v_org FROM public.maintenance_cards mc WHERE mc.id = NEW.card_id;
  IF v_org IS NULL OR v_org <> NEW.organization_id THEN RAISE EXCEPTION 'card_id must belong to this organization'; END IF;
  IF NEW.responsible_member_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.id = NEW.responsible_member_id AND om.organization_id = NEW.organization_id
      AND om.is_active AND om.role IN ('owner', 'admin', 'manager')
  ) THEN
    RAISE EXCEPTION 'responsible_member_id must be an active owner/admin/manager of this organization';
  END IF;
  IF NEW.trigger_type = 'meter' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.asset_meters am
      WHERE am.id = NEW.meter_id AND am.organization_id = NEW.organization_id
        AND am.asset_id = NEW.asset_id AND am.is_active
    ) THEN RAISE EXCEPTION 'meter_id must be an active meter for this asset'; END IF;
    -- The baseline is resolved from an effective reading when the plan is
    -- created (or when a privileged direct write tries to replace it). A
    -- later correction deliberately voids that historical reading; it must
    -- not make unrelated mutable plan edits impossible afterwards.
    IF TG_OP = 'INSERT'
      OR NEW.baseline_reading_id IS DISTINCT FROM OLD.baseline_reading_id
      OR NEW.meter_id IS DISTINCT FROM OLD.meter_id THEN
      SELECT amr.* INTO v_reading FROM public.asset_meter_readings amr
      WHERE amr.id = NEW.baseline_reading_id AND amr.meter_id = NEW.meter_id AND amr.voided_at IS NULL;
      IF v_reading.id IS NULL THEN RAISE EXCEPTION 'baseline_reading_id must be an effective reading of this meter'; END IF;
      NEW.baseline_value := v_reading.value;
    ELSE
      NEW.baseline_value := OLD.baseline_value;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_preventive_plans_consistency
BEFORE INSERT OR UPDATE ON public.preventive_maintenance_plans
FOR EACH ROW EXECUTE FUNCTION public.check_preventive_plan_consistency();

CREATE OR REPLACE FUNCTION public.protect_preventive_occurrence_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.scope_snapshot IS DISTINCT FROM OLD.scope_snapshot
    OR NEW.plan_id IS DISTINCT FROM OLD.plan_id
    OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.asset_id IS DISTINCT FROM OLD.asset_id
    OR NEW.sequence IS DISTINCT FROM OLD.sequence
    OR NEW.due_at IS DISTINCT FROM OLD.due_at
    OR NEW.due_meter_value IS DISTINCT FROM OLD.due_meter_value
    OR NEW.request_creation_id IS DISTINCT FROM OLD.request_creation_id THEN
    RAISE EXCEPTION 'Occurrence identity, due values and scope snapshot are immutable';
  END IF;
  IF OLD.status IN ('completed', 'skipped', 'cancelled') AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Terminal preventive maintenance occurrences are immutable';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_preventive_occurrences_protect
BEFORE UPDATE ON public.preventive_maintenance_occurrences
FOR EACH ROW EXECUTE FUNCTION public.protect_preventive_occurrence_snapshot();

-- =========================================================================
-- C) RLS: read-only tables, writes only through SECURITY DEFINER RPCs.
-- =========================================================================
ALTER TABLE public.maintenance_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_card_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_card_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_meters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_meter_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.preventive_maintenance_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.preventive_maintenance_occurrences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organization members view maintenance cards" ON public.maintenance_cards
FOR SELECT TO authenticated USING (
  (SELECT public.is_platform_admin()) OR (SELECT public.is_organization_member(organization_id))
);
CREATE POLICY "organization members view maintenance card tasks" ON public.maintenance_card_tasks
FOR SELECT TO authenticated USING (
  (SELECT public.is_platform_admin()) OR EXISTS (
    SELECT 1 FROM public.maintenance_cards mc
    WHERE mc.id = maintenance_card_tasks.card_id AND public.is_organization_member(mc.organization_id)
  )
);
CREATE POLICY "organization members view maintenance card materials" ON public.maintenance_card_materials
FOR SELECT TO authenticated USING (
  (SELECT public.is_platform_admin()) OR EXISTS (
    SELECT 1 FROM public.maintenance_cards mc
    WHERE mc.id = maintenance_card_materials.card_id AND public.is_organization_member(mc.organization_id)
  )
);
CREATE POLICY "organization members view asset meters" ON public.asset_meters
FOR SELECT TO authenticated USING (
  (SELECT public.is_platform_admin()) OR (SELECT public.is_organization_member(organization_id))
);
CREATE POLICY "organization members view asset meter readings" ON public.asset_meter_readings
FOR SELECT TO authenticated USING (
  (SELECT public.is_platform_admin()) OR EXISTS (
    SELECT 1 FROM public.asset_meters am
    WHERE am.id = asset_meter_readings.meter_id AND public.is_organization_member(am.organization_id)
  )
);
CREATE POLICY "organization members view preventive plans" ON public.preventive_maintenance_plans
FOR SELECT TO authenticated USING (
  (SELECT public.is_platform_admin()) OR (SELECT public.is_organization_member(organization_id))
);
CREATE POLICY "organization members view preventive occurrences" ON public.preventive_maintenance_occurrences
FOR SELECT TO authenticated USING (
  (SELECT public.is_platform_admin()) OR (SELECT public.is_organization_member(organization_id))
);

REVOKE ALL ON TABLE public.maintenance_cards, public.maintenance_card_tasks,
  public.maintenance_card_materials, public.asset_meters, public.asset_meter_readings,
  public.preventive_maintenance_plans, public.preventive_maintenance_occurrences
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.maintenance_cards, public.maintenance_card_tasks,
  public.maintenance_card_materials, public.asset_meters, public.asset_meter_readings,
  public.preventive_maintenance_plans, public.preventive_maintenance_occurrences
TO authenticated;

REVOKE ALL ON FUNCTION public.check_asset_meter_consistency() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.check_preventive_plan_consistency() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.protect_preventive_occurrence_snapshot() FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- D) Authorization and cadence helpers (internal only)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.can_manage_preventive_maintenance(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.organizations o
      WHERE o.id = p_organization_id AND o.organization_type = 'client_company'::public.organization_type
        AND o.status = 'active'
    )
    AND (
      public.is_platform_admin()
      OR public.has_organization_role(
        p_organization_id,
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_record_asset_meter_reading(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.organizations o
      WHERE o.id = p_organization_id AND o.organization_type = 'client_company'::public.organization_type
        AND o.status = 'active'
    )
    AND (
      public.is_platform_admin()
      OR public.has_organization_role(
        p_organization_id,
        ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[]
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.preventive_frequency_interval(
  p_frequency text,
  p_custom_interval integer DEFAULT NULL,
  p_custom_unit text DEFAULT NULL
)
RETURNS interval
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  RETURN CASE p_frequency
    WHEN 'weekly' THEN interval '1 week'
    WHEN 'monthly' THEN interval '1 month'
    WHEN 'quarterly' THEN interval '3 months'
    WHEN 'semiannual' THEN interval '6 months'
    WHEN 'annual' THEN interval '1 year'
    WHEN 'custom' THEN CASE p_custom_unit
      WHEN 'days' THEN make_interval(days => p_custom_interval)
      WHEN 'weeks' THEN make_interval(days => p_custom_interval * 7)
      WHEN 'months' THEN make_interval(months => p_custom_interval)
      WHEN 'years' THEN make_interval(years => p_custom_interval)
      ELSE NULL
    END
    ELSE NULL
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.build_preventive_scope_snapshot(p_plan_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_card public.maintenance_cards%ROWTYPE;
  v_asset public.assets%ROWTYPE;
  v_branch_id uuid;
  v_branch_name text;
  v_meter jsonb;
  v_responsible jsonb;
BEGIN
  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = p_plan_id;
  IF v_plan.id IS NULL THEN RAISE EXCEPTION 'Preventive maintenance plan not found'; END IF;
  SELECT * INTO v_card FROM public.maintenance_cards WHERE id = v_plan.card_id;
  SELECT * INTO v_asset FROM public.assets WHERE id = v_plan.asset_id;
  v_branch_id := public.resolve_asset_branch(v_plan.asset_id);
  SELECT cb.name INTO v_branch_name FROM public.client_branches cb WHERE cb.id = v_branch_id;

  IF v_plan.meter_id IS NOT NULL THEN
    SELECT jsonb_build_object('id', am.id, 'name', am.name, 'unit', am.unit)
      INTO v_meter FROM public.asset_meters am WHERE am.id = v_plan.meter_id;
  END IF;
  IF v_plan.responsible_member_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'membership_id', om.id,
      'name', COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)),
      'role', om.role
    ) INTO v_responsible
    FROM public.organization_members om
    JOIN auth.users au ON au.id = om.user_id
    WHERE om.id = v_plan.responsible_member_id;
  END IF;

  RETURN jsonb_build_object(
    'schema_version', 1,
    'captured_at', now(),
    'asset', jsonb_build_object(
      'id', v_asset.id, 'code', v_asset.code, 'name', v_asset.name,
      'path', public.resolve_asset_path(v_asset.id),
      'branch_id', v_branch_id, 'branch_name', v_branch_name
    ),
    'card', jsonb_build_object(
      'id', v_card.id, 'code', v_card.code, 'name', v_card.name,
      'description', v_card.description, 'category', v_card.category,
      'estimated_hours', v_card.estimated_hours,
      'procedure_notes', v_card.procedure_notes, 'safety_notes', v_card.safety_notes,
      'tasks', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', t.id, 'sequence', t.sequence, 'title', t.title, 'description', t.description,
          'estimated_hours', t.estimated_hours, 'is_required', t.is_required
        ) ORDER BY t.sequence)
        FROM public.maintenance_card_tasks t WHERE t.card_id = v_card.id
      ), '[]'::jsonb),
      'materials', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', cm.id, 'sequence', cm.sequence, 'material_id', cm.material_id,
          'code', m.code, 'name', m.name,
          'description', cm.description, 'quantity', cm.quantity,
          'unit', cm.unit, 'notes', cm.notes
        ) ORDER BY cm.sequence)
        FROM public.maintenance_card_materials cm
        LEFT JOIN public.materials m ON m.id = cm.material_id
        WHERE cm.card_id = v_card.id
      ), '[]'::jsonb)
    ),
    'plan', jsonb_build_object(
      'id', v_plan.id, 'trigger_type', v_plan.trigger_type,
      'priority', v_plan.priority, 'default_request_type', v_plan.default_request_type,
      'planning_lead_days', v_plan.planning_lead_days, 'frequency', v_plan.frequency,
      'custom_interval', v_plan.custom_interval, 'custom_unit', v_plan.custom_unit,
      'meter', v_meter, 'interval_value', v_plan.interval_value,
      'meter_lead_value', v_plan.meter_lead_value,
      'responsible', v_responsible
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_preventive_occurrence_locked(
  p_plan_id uuid,
  p_due_at timestamptz,
  p_due_meter_value numeric
)
RETURNS public.preventive_maintenance_occurrences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occurrence public.preventive_maintenance_occurrences%ROWTYPE;
  v_sequence integer;
BEGIN
  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = p_plan_id FOR UPDATE;
  IF v_plan.id IS NULL THEN RAISE EXCEPTION 'Preventive maintenance plan not found'; END IF;
  IF (v_plan.trigger_type = 'calendar' AND (p_due_at IS NULL OR p_due_meter_value IS NOT NULL))
    OR (v_plan.trigger_type = 'meter' AND (p_due_at IS NOT NULL OR p_due_meter_value IS NULL)) THEN
    RAISE EXCEPTION 'Occurrence due value does not match plan trigger type';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.preventive_maintenance_occurrences o
    WHERE o.plan_id = p_plan_id AND o.status IN ('open', 'planned')
  ) THEN RAISE EXCEPTION 'Plan already has a current occurrence'; END IF;

  SELECT COALESCE(MAX(o.sequence), 0) + 1 INTO v_sequence
  FROM public.preventive_maintenance_occurrences o WHERE o.plan_id = p_plan_id;

  INSERT INTO public.preventive_maintenance_occurrences (
    organization_id, plan_id, asset_id, sequence, due_at, due_meter_value, scope_snapshot
  ) VALUES (
    v_plan.organization_id, v_plan.id, v_plan.asset_id, v_sequence,
    p_due_at, p_due_meter_value,
    public.build_preventive_scope_snapshot(v_plan.id) || jsonb_build_object(
      'due_at', p_due_at,
      'due_meter_value', p_due_meter_value
    )
  ) RETURNING * INTO v_occurrence;
  RETURN v_occurrence;
END;
$$;

REVOKE ALL ON FUNCTION public.can_manage_preventive_maintenance(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_record_asset_meter_reading(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.preventive_frequency_interval(text, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.build_preventive_scope_snapshot(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_preventive_occurrence_locked(uuid, timestamptz, numeric) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- E) Maintenance card RPCs
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_maintenance_cards(
  p_organization_id uuid,
  p_include_inactive boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.is_platform_admin() OR public.is_organization_member(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized to view maintenance cards';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'organization_id', c.organization_id, 'code', c.code, 'name', c.name,
      'description', c.description, 'category', c.category, 'estimated_hours', c.estimated_hours,
      'procedure_notes', c.procedure_notes, 'safety_notes', c.safety_notes,
      'is_active', c.is_active, 'created_at', c.created_at, 'updated_at', c.updated_at,
      'tasks', COALESCE((SELECT jsonb_agg(to_jsonb(t) - 'card_id' ORDER BY t.sequence)
        FROM public.maintenance_card_tasks t WHERE t.card_id = c.id), '[]'::jsonb),
      'materials', COALESCE((SELECT jsonb_agg(
        (to_jsonb(cm) - 'card_id') || jsonb_build_object(
          'material_code', m.code, 'material_name', m.name, 'current_stock', m.stock,
          'material_is_active', m.is_active
        ) ORDER BY cm.sequence)
        FROM public.maintenance_card_materials cm
        LEFT JOIN public.materials m ON m.id = cm.material_id
        WHERE cm.card_id = c.id), '[]'::jsonb)
    ) ORDER BY c.is_active DESC, lower(c.code))
    FROM public.maintenance_cards c
    WHERE c.organization_id = p_organization_id AND (p_include_inactive OR c.is_active)
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.save_maintenance_card(
  p_organization_id uuid,
  p_code text,
  p_name text,
  p_description text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_estimated_hours numeric DEFAULT NULL,
  p_procedure_notes text DEFAULT NULL,
  p_safety_notes text DEFAULT NULL,
  p_tasks jsonb DEFAULT '[]'::jsonb,
  p_materials jsonb DEFAULT '[]'::jsonb,
  p_card_id uuid DEFAULT NULL
)
RETURNS public.maintenance_cards
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_card public.maintenance_cards%ROWTYPE;
  v_item jsonb;
  v_sequence integer;
  v_material_org uuid;
BEGIN
  IF NOT public.can_manage_preventive_maintenance(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to manage maintenance cards';
  END IF;
  IF TRIM(COALESCE(p_code, '')) = '' OR TRIM(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'Code and name are required';
  END IF;
  IF jsonb_typeof(COALESCE(p_tasks, '[]'::jsonb)) <> 'array'
    OR jsonb_typeof(COALESCE(p_materials, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Tasks and materials must be JSON arrays';
  END IF;

  IF p_card_id IS NULL THEN
    INSERT INTO public.maintenance_cards (
      organization_id, code, name, description, category, estimated_hours,
      procedure_notes, safety_notes, created_by_user_id
    ) VALUES (
      p_organization_id, TRIM(p_code), TRIM(p_name), NULLIF(TRIM(p_description), ''),
      NULLIF(TRIM(p_category), ''), p_estimated_hours, NULLIF(TRIM(p_procedure_notes), ''),
      NULLIF(TRIM(p_safety_notes), ''), auth.uid()
    ) RETURNING * INTO v_card;
  ELSE
    SELECT * INTO v_card FROM public.maintenance_cards WHERE id = p_card_id FOR UPDATE;
    IF v_card.id IS NULL OR v_card.organization_id <> p_organization_id THEN
      RAISE EXCEPTION 'Maintenance card not found in this organization';
    END IF;
    UPDATE public.maintenance_cards SET
      code = TRIM(p_code), name = TRIM(p_name), description = NULLIF(TRIM(p_description), ''),
      category = NULLIF(TRIM(p_category), ''), estimated_hours = p_estimated_hours,
      procedure_notes = NULLIF(TRIM(p_procedure_notes), ''), safety_notes = NULLIF(TRIM(p_safety_notes), '')
    WHERE id = p_card_id RETURNING * INTO v_card;
    DELETE FROM public.maintenance_card_tasks WHERE card_id = p_card_id;
    DELETE FROM public.maintenance_card_materials WHERE card_id = p_card_id;
  END IF;

  v_sequence := 0;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_tasks, '[]'::jsonb)) LOOP
    v_sequence := v_sequence + 1;
    INSERT INTO public.maintenance_card_tasks (card_id, sequence, title, description, estimated_hours, is_required)
    VALUES (
      v_card.id, v_sequence, TRIM(v_item->>'title'), NULLIF(TRIM(v_item->>'description'), ''),
      NULLIF(v_item->>'estimated_hours', '')::numeric, COALESCE((v_item->>'is_required')::boolean, true)
    );
  END LOOP;

  v_sequence := 0;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_materials, '[]'::jsonb)) LOOP
    v_sequence := v_sequence + 1;
    IF NULLIF(v_item->>'material_id', '') IS NOT NULL THEN
      SELECT m.organization_id INTO v_material_org FROM public.materials m
      WHERE m.id = (v_item->>'material_id')::uuid;
      IF v_material_org IS NULL OR v_material_org <> p_organization_id THEN
        RAISE EXCEPTION 'Linked material must belong to this organization';
      END IF;
    END IF;
    INSERT INTO public.maintenance_card_materials (card_id, sequence, material_id, description, quantity, unit, notes)
    VALUES (
      v_card.id, v_sequence, NULLIF(v_item->>'material_id', '')::uuid,
      TRIM(v_item->>'description'), (v_item->>'quantity')::numeric,
      TRIM(v_item->>'unit'), NULLIF(TRIM(v_item->>'notes'), '')
    );
  END LOOP;
  RETURN v_card;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_maintenance_card_active(p_card_id uuid, p_is_active boolean)
RETURNS public.maintenance_cards
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_card public.maintenance_cards%ROWTYPE;
BEGIN
  SELECT * INTO v_card FROM public.maintenance_cards WHERE id = p_card_id FOR UPDATE;
  IF v_card.id IS NULL THEN RAISE EXCEPTION 'Maintenance card not found'; END IF;
  IF NOT public.can_manage_preventive_maintenance(v_card.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT p_is_active AND EXISTS (
    SELECT 1 FROM public.preventive_maintenance_plans p WHERE p.card_id = p_card_id AND p.is_active
  ) THEN RAISE EXCEPTION 'Cannot deactivate a card used by an active preventive maintenance plan'; END IF;
  UPDATE public.maintenance_cards SET is_active = p_is_active WHERE id = p_card_id RETURNING * INTO v_card;
  RETURN v_card;
END;
$$;

REVOKE ALL ON FUNCTION public.get_maintenance_cards(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_maintenance_cards(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.save_maintenance_card(uuid, text, text, text, text, numeric, text, text, jsonb, jsonb, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_maintenance_card(uuid, text, text, text, text, numeric, text, text, jsonb, jsonb, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.set_maintenance_card_active(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_maintenance_card_active(uuid, boolean) TO authenticated;

-- =========================================================================
-- F) Asset meter RPCs. Effective readings are immutable; corrections void
-- the original and insert one replacement at the same effective timestamp.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_asset_meters(
  p_asset_id uuid,
  p_include_inactive boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_org uuid;
BEGIN
  SELECT a.organization_id INTO v_org FROM public.assets a WHERE a.id = p_asset_id;
  IF v_org IS NULL THEN RAISE EXCEPTION 'Asset not found'; END IF;
  IF auth.uid() IS NULL OR NOT (public.is_platform_admin() OR public.is_organization_member(v_org)) THEN
    RAISE EXCEPTION 'Not authorized to view asset meters';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', m.id, 'organization_id', m.organization_id, 'asset_id', m.asset_id,
      'name', m.name, 'unit', m.unit, 'is_active', m.is_active,
      'replaces_meter_id', m.replaces_meter_id, 'retired_at', m.retired_at,
      'retirement_reason', m.retirement_reason, 'created_at', m.created_at,
      'readings', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', r.id, 'value', r.value, 'recorded_at', r.recorded_at, 'notes', r.notes,
          'supersedes_reading_id', r.supersedes_reading_id, 'created_at', r.created_at
        ) ORDER BY r.recorded_at DESC)
        FROM public.asset_meter_readings r WHERE r.meter_id = m.id AND r.voided_at IS NULL
      ), '[]'::jsonb)
    ) ORDER BY m.is_active DESC, lower(m.name))
    FROM public.asset_meters m
    WHERE m.asset_id = p_asset_id AND (p_include_inactive OR m.is_active)
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_asset_meter(
  p_organization_id uuid,
  p_asset_id uuid,
  p_name text,
  p_unit text,
  p_initial_value numeric DEFAULT NULL,
  p_recorded_at timestamptz DEFAULT now(),
  p_notes text DEFAULT NULL
)
RETURNS public.asset_meters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_meter public.asset_meters%ROWTYPE;
BEGIN
  IF NOT public.can_manage_preventive_maintenance(p_organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  INSERT INTO public.asset_meters (organization_id, asset_id, name, unit, created_by_user_id)
  VALUES (p_organization_id, p_asset_id, TRIM(p_name), TRIM(p_unit), auth.uid()) RETURNING * INTO v_meter;
  IF p_initial_value IS NOT NULL THEN
    PERFORM public.record_asset_meter_reading(v_meter.id, p_initial_value, p_recorded_at, p_notes);
  END IF;
  RETURN v_meter;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_asset_meter_reading(
  p_meter_id uuid,
  p_value numeric,
  p_recorded_at timestamptz DEFAULT now(),
  p_notes text DEFAULT NULL
)
RETURNS public.asset_meter_readings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_meter public.asset_meters%ROWTYPE;
  v_reading public.asset_meter_readings%ROWTYPE;
  v_previous numeric;
  v_next numeric;
BEGIN
  SELECT * INTO v_meter FROM public.asset_meters WHERE id = p_meter_id FOR UPDATE;
  IF v_meter.id IS NULL THEN RAISE EXCEPTION 'Asset meter not found'; END IF;
  IF NOT public.can_record_asset_meter_reading(v_meter.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT v_meter.is_active THEN RAISE EXCEPTION 'Cannot record a reading on a retired meter'; END IF;
  IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'Meter reading must be non-negative'; END IF;

  SELECT r.value INTO v_previous FROM public.asset_meter_readings r
  WHERE r.meter_id = p_meter_id AND r.voided_at IS NULL AND r.recorded_at < p_recorded_at
  ORDER BY r.recorded_at DESC LIMIT 1;
  SELECT r.value INTO v_next FROM public.asset_meter_readings r
  WHERE r.meter_id = p_meter_id AND r.voided_at IS NULL AND r.recorded_at > p_recorded_at
  ORDER BY r.recorded_at ASC LIMIT 1;
  IF v_previous IS NOT NULL AND p_value < v_previous THEN
    RAISE EXCEPTION 'Reading cannot be lower than the previous effective reading (%)', v_previous;
  END IF;
  IF v_next IS NOT NULL AND p_value > v_next THEN
    RAISE EXCEPTION 'Reading cannot be higher than the next effective reading (%)', v_next;
  END IF;

  INSERT INTO public.asset_meter_readings (meter_id, value, recorded_at, notes, created_by_user_id)
  VALUES (p_meter_id, p_value, p_recorded_at, NULLIF(TRIM(p_notes), ''), auth.uid()) RETURNING * INTO v_reading;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_meter.organization_id, v_meter.asset_id, 'meter_reading_recorded',
    'Lectura de medidor registrada: ' || v_meter.name || ' = ' || p_value::text || ' ' || v_meter.unit,
    jsonb_build_object('meter_id', v_meter.id, 'reading_id', v_reading.id, 'value', p_value,
      'unit', v_meter.unit, 'recorded_at', p_recorded_at), auth.uid()
  );
  RETURN v_reading;
END;
$$;

CREATE OR REPLACE FUNCTION public.correct_asset_meter_reading(
  p_reading_id uuid,
  p_value numeric,
  p_reason text,
  p_notes text DEFAULT NULL
)
RETURNS public.asset_meter_readings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_original public.asset_meter_readings%ROWTYPE;
  v_meter public.asset_meters%ROWTYPE;
  v_replacement public.asset_meter_readings%ROWTYPE;
  v_previous numeric;
  v_next numeric;
BEGIN
  SELECT r.* INTO v_original FROM public.asset_meter_readings r WHERE r.id = p_reading_id;
  IF v_original.id IS NULL THEN RAISE EXCEPTION 'Meter reading not found'; END IF;
  SELECT * INTO v_meter FROM public.asset_meters WHERE id = v_original.meter_id FOR UPDATE;
  SELECT r.* INTO v_original FROM public.asset_meter_readings r WHERE r.id = p_reading_id FOR UPDATE;
  IF NOT public.can_manage_preventive_maintenance(v_meter.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF v_original.voided_at IS NOT NULL THEN RAISE EXCEPTION 'Only an effective reading can be corrected'; END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A correction reason is required'; END IF;
  IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'Meter reading must be non-negative'; END IF;

  SELECT r.value INTO v_previous FROM public.asset_meter_readings r
  WHERE r.meter_id = v_meter.id AND r.voided_at IS NULL AND r.id <> v_original.id
    AND r.recorded_at < v_original.recorded_at ORDER BY r.recorded_at DESC LIMIT 1;
  SELECT r.value INTO v_next FROM public.asset_meter_readings r
  WHERE r.meter_id = v_meter.id AND r.voided_at IS NULL AND r.id <> v_original.id
    AND r.recorded_at > v_original.recorded_at ORDER BY r.recorded_at ASC LIMIT 1;
  IF v_previous IS NOT NULL AND p_value < v_previous THEN RAISE EXCEPTION 'Corrected reading violates monotonic history'; END IF;
  IF v_next IS NOT NULL AND p_value > v_next THEN RAISE EXCEPTION 'Corrected reading violates monotonic history'; END IF;

  UPDATE public.asset_meter_readings SET voided_at = now(), voided_by_user_id = auth.uid(), void_reason = TRIM(p_reason)
  WHERE id = v_original.id;
  INSERT INTO public.asset_meter_readings (
    meter_id, value, recorded_at, notes, created_by_user_id, supersedes_reading_id
  ) VALUES (
    v_meter.id, p_value, v_original.recorded_at, COALESCE(NULLIF(TRIM(p_notes), ''), v_original.notes),
    auth.uid(), v_original.id
  ) RETURNING * INTO v_replacement;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_meter.organization_id, v_meter.asset_id, 'meter_reading_recorded',
    'Lectura de medidor corregida: ' || v_meter.name || ' = ' || p_value::text || ' ' || v_meter.unit,
    jsonb_build_object('meter_id', v_meter.id, 'reading_id', v_replacement.id,
      'supersedes_reading_id', v_original.id, 'value', p_value, 'unit', v_meter.unit,
      'recorded_at', v_original.recorded_at, 'correction_reason', TRIM(p_reason)), auth.uid()
  );
  RETURN v_replacement;
END;
$$;

CREATE OR REPLACE FUNCTION public.retire_asset_meter(p_meter_id uuid, p_reason text)
RETURNS public.asset_meters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_meter public.asset_meters%ROWTYPE;
BEGIN
  SELECT * INTO v_meter FROM public.asset_meters WHERE id = p_meter_id FOR UPDATE;
  IF v_meter.id IS NULL THEN RAISE EXCEPTION 'Asset meter not found'; END IF;
  IF NOT public.can_manage_preventive_maintenance(v_meter.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT v_meter.is_active THEN RETURN v_meter; END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A retirement reason is required'; END IF;
  IF EXISTS (SELECT 1 FROM public.preventive_maintenance_plans p WHERE p.meter_id = p_meter_id AND p.is_active) THEN
    RAISE EXCEPTION 'Deactivate active preventive plans before retiring their meter';
  END IF;
  UPDATE public.asset_meters SET is_active = false, retired_at = now(), retirement_reason = TRIM(p_reason)
  WHERE id = p_meter_id RETURNING * INTO v_meter;
  RETURN v_meter;
END;
$$;

CREATE OR REPLACE FUNCTION public.replace_asset_meter(
  p_meter_id uuid,
  p_name text,
  p_unit text,
  p_initial_value numeric,
  p_recorded_at timestamptz,
  p_reason text,
  p_notes text DEFAULT NULL
)
RETURNS public.asset_meters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_old public.asset_meters%ROWTYPE; v_new public.asset_meters%ROWTYPE;
BEGIN
  SELECT * INTO v_old FROM public.asset_meters WHERE id = p_meter_id FOR UPDATE;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Asset meter not found'; END IF;
  IF NOT public.can_manage_preventive_maintenance(v_old.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT v_old.is_active THEN RAISE EXCEPTION 'Only an active meter can be replaced'; END IF;
  IF EXISTS (SELECT 1 FROM public.preventive_maintenance_plans p WHERE p.meter_id = p_meter_id AND p.is_active) THEN
    RAISE EXCEPTION 'Deactivate active preventive plans before replacing their meter';
  END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A replacement reason is required'; END IF;
  UPDATE public.asset_meters SET is_active = false, retired_at = now(), retirement_reason = TRIM(p_reason)
  WHERE id = v_old.id;
  INSERT INTO public.asset_meters (
    organization_id, asset_id, name, unit, replaces_meter_id, created_by_user_id
  ) VALUES (
    v_old.organization_id, v_old.asset_id, TRIM(p_name), TRIM(p_unit), v_old.id, auth.uid()
  ) RETURNING * INTO v_new;
  PERFORM public.record_asset_meter_reading(v_new.id, p_initial_value, p_recorded_at, p_notes);
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.get_asset_meters(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_asset_meters(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.create_asset_meter(uuid, uuid, text, text, numeric, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_asset_meter(uuid, uuid, text, text, numeric, timestamptz, text) TO authenticated;
REVOKE ALL ON FUNCTION public.record_asset_meter_reading(uuid, numeric, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_asset_meter_reading(uuid, numeric, timestamptz, text) TO authenticated;
REVOKE ALL ON FUNCTION public.correct_asset_meter_reading(uuid, numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.correct_asset_meter_reading(uuid, numeric, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.retire_asset_meter(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retire_asset_meter(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.replace_asset_meter(uuid, text, text, numeric, timestamptz, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_asset_meter(uuid, text, text, numeric, timestamptz, text, text) TO authenticated;

-- =========================================================================
-- G) Plan lifecycle and read models
-- =========================================================================
CREATE OR REPLACE FUNCTION public.notify_preventive_occurrence(
  p_occurrence_id uuid,
  p_event_type text,
  p_title text,
  p_message text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_occ public.preventive_maintenance_occurrences%ROWTYPE; v_plan public.preventive_maintenance_plans%ROWTYPE;
BEGIN
  SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences WHERE id = p_occurrence_id;
  IF v_occ.id IS NULL THEN RETURN; END IF;
  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = v_occ.plan_id;
  IF v_plan.responsible_member_id IS NOT NULL THEN
    PERFORM public.notify_member(
      v_plan.responsible_member_id, auth.uid(), p_event_type, p_title, p_message,
      'preventive_maintenance_occurrence', v_occ.id, v_plan.priority,
      jsonb_build_object('plan_id', v_plan.id, 'occurrence_id', v_occ.id, 'occurrence_sequence', v_occ.sequence, 'asset_id', v_occ.asset_id)
    );
  END IF;
  PERFORM public.notify_role_members(
    v_occ.organization_id,
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
    auth.uid(), p_event_type, p_title, p_message,
    'preventive_maintenance_occurrence', v_occ.id, v_plan.priority,
    jsonb_build_object('plan_id', v_plan.id, 'occurrence_id', v_occ.id, 'occurrence_sequence', v_occ.sequence, 'asset_id', v_occ.asset_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.save_preventive_maintenance_plan(
  p_organization_id uuid,
  p_asset_id uuid,
  p_card_id uuid,
  p_trigger_type text,
  p_priority text DEFAULT 'medium',
  p_default_request_type text DEFAULT 'internal',
  p_responsible_member_id uuid DEFAULT NULL,
  p_planning_lead_days integer DEFAULT 30,
  p_frequency text DEFAULT NULL,
  p_custom_interval integer DEFAULT NULL,
  p_custom_unit text DEFAULT NULL,
  p_first_due_at timestamptz DEFAULT NULL,
  p_meter_id uuid DEFAULT NULL,
  p_interval_value numeric DEFAULT NULL,
  p_baseline_reading_id uuid DEFAULT NULL,
  p_meter_lead_value numeric DEFAULT NULL,
  p_plan_id uuid DEFAULT NULL
)
RETURNS public.preventive_maintenance_plans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
  v_baseline numeric;
BEGIN
  IF NOT public.can_manage_preventive_maintenance(p_organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_trigger_type = 'meter' AND p_plan_id IS NULL THEN
    SELECT r.value INTO v_baseline FROM public.asset_meter_readings r
    WHERE r.id = p_baseline_reading_id AND r.meter_id = p_meter_id AND r.voided_at IS NULL;
    IF v_baseline IS NULL THEN RAISE EXCEPTION 'A valid baseline reading is required'; END IF;
  END IF;

  IF p_plan_id IS NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.maintenance_cards c WHERE c.id = p_card_id AND c.is_active) THEN
      RAISE EXCEPTION 'An active maintenance card is required';
    END IF;
    INSERT INTO public.preventive_maintenance_plans (
      organization_id, asset_id, card_id, trigger_type, priority, default_request_type,
      responsible_member_id, planning_lead_days, frequency, custom_interval, custom_unit,
      first_due_at, meter_id, interval_value, baseline_value, baseline_reading_id,
      meter_lead_value, created_by_user_id
    ) VALUES (
      p_organization_id, p_asset_id, p_card_id, p_trigger_type, p_priority, p_default_request_type,
      p_responsible_member_id, p_planning_lead_days, p_frequency, p_custom_interval, p_custom_unit,
      p_first_due_at, p_meter_id, p_interval_value, v_baseline, p_baseline_reading_id,
      p_meter_lead_value, auth.uid()
    ) RETURNING * INTO v_plan;

    IF v_plan.trigger_type = 'calendar' THEN
      v_occ := public.create_preventive_occurrence_locked(v_plan.id, v_plan.first_due_at, NULL);
    ELSE
      v_occ := public.create_preventive_occurrence_locked(v_plan.id, NULL, v_plan.baseline_value + v_plan.interval_value);
    END IF;
    INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
    VALUES (
      v_plan.organization_id, v_plan.asset_id, 'preventive_plan_created',
      'Plan de mantenimiento preventivo creado',
      jsonb_build_object('plan_id', v_plan.id, 'occurrence_id', v_occ.id, 'card_id', v_plan.card_id,
        'trigger_type', v_plan.trigger_type), auth.uid()
    );
  ELSE
    SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = p_plan_id FOR UPDATE;
    IF v_plan.id IS NULL OR v_plan.organization_id <> p_organization_id THEN RAISE EXCEPTION 'Plan not found'; END IF;
    IF v_plan.asset_id <> p_asset_id OR v_plan.card_id <> p_card_id
      OR v_plan.trigger_type <> p_trigger_type OR v_plan.meter_id IS DISTINCT FROM p_meter_id THEN
      RAISE EXCEPTION 'Asset, card, trigger type and meter are immutable';
    END IF;
    IF v_plan.baseline_reading_id IS DISTINCT FROM p_baseline_reading_id THEN
      RAISE EXCEPTION 'The meter baseline is immutable';
    END IF;
    UPDATE public.preventive_maintenance_plans SET
      priority = p_priority, default_request_type = p_default_request_type,
      responsible_member_id = p_responsible_member_id, planning_lead_days = p_planning_lead_days,
      frequency = p_frequency, custom_interval = p_custom_interval, custom_unit = p_custom_unit,
      first_due_at = p_first_due_at, interval_value = p_interval_value,
      meter_lead_value = p_meter_lead_value
    WHERE id = p_plan_id RETURNING * INTO v_plan;
  END IF;
  RETURN v_plan;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_preventive_maintenance_plan_active(
  p_plan_id uuid,
  p_is_active boolean,
  p_reason text DEFAULT NULL
)
RETURNS public.preventive_maintenance_plans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
  v_latest numeric;
BEGIN
  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = p_plan_id FOR UPDATE;
  IF v_plan.id IS NULL THEN RAISE EXCEPTION 'Plan not found'; END IF;
  IF NOT public.can_manage_preventive_maintenance(v_plan.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF v_plan.is_active = p_is_active THEN RETURN v_plan; END IF;

  IF NOT p_is_active THEN
    IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A deactivation reason is required'; END IF;
    SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences o
    WHERE o.plan_id = p_plan_id AND o.status IN ('open', 'planned') FOR UPDATE;
    IF v_occ.status = 'open' THEN
      UPDATE public.preventive_maintenance_occurrences SET
        status = 'cancelled', cancelled_at = now(), cancel_reason = TRIM(p_reason)
      WHERE id = v_occ.id;
    END IF;
    UPDATE public.preventive_maintenance_plans SET is_active = false WHERE id = p_plan_id RETURNING * INTO v_plan;
  ELSE
    UPDATE public.preventive_maintenance_plans SET is_active = true WHERE id = p_plan_id RETURNING * INTO v_plan;
    IF NOT EXISTS (
      SELECT 1 FROM public.preventive_maintenance_occurrences o
      WHERE o.plan_id = p_plan_id AND o.status IN ('open', 'planned')
    ) THEN
      IF v_plan.trigger_type = 'calendar' THEN
        v_occ := public.create_preventive_occurrence_locked(
          v_plan.id, now() + public.preventive_frequency_interval(v_plan.frequency, v_plan.custom_interval, v_plan.custom_unit), NULL
        );
      ELSE
        SELECT r.value INTO v_latest FROM public.asset_meter_readings r
        WHERE r.meter_id = v_plan.meter_id AND r.voided_at IS NULL ORDER BY r.recorded_at DESC LIMIT 1;
        IF v_latest IS NULL THEN RAISE EXCEPTION 'Cannot reactivate a meter plan without an effective reading'; END IF;
        v_occ := public.create_preventive_occurrence_locked(v_plan.id, NULL, v_latest + v_plan.interval_value);
      END IF;
    END IF;
  END IF;
  RETURN v_plan;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_preventive_maintenance_plans(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.is_platform_admin() OR public.is_organization_member(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', p.id, 'organization_id', p.organization_id, 'asset_id', p.asset_id,
      'asset_name', a.name, 'asset_code', a.code, 'asset_path', public.resolve_asset_path(a.id),
      'card_id', p.card_id, 'card_code', c.code, 'card_name', c.name,
      'trigger_type', p.trigger_type, 'priority', p.priority,
      'default_request_type', p.default_request_type, 'responsible_member_id', p.responsible_member_id,
      'planning_lead_days', p.planning_lead_days, 'frequency', p.frequency,
      'custom_interval', p.custom_interval, 'custom_unit', p.custom_unit,
      'first_due_at', p.first_due_at, 'meter_id', p.meter_id, 'meter_name', m.name,
      'meter_unit', m.unit, 'interval_value', p.interval_value, 'baseline_value', p.baseline_value,
      'baseline_reading_id', p.baseline_reading_id, 'meter_lead_value', p.meter_lead_value,
      'is_active', p.is_active, 'created_at', p.created_at, 'updated_at', p.updated_at,
      'latest_meter_value', lr.value, 'latest_meter_recorded_at', lr.recorded_at,
      'current_occurrence', CASE WHEN o.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', o.id, 'sequence', o.sequence, 'status', o.status, 'due_at', o.due_at,
        'due_meter_value', o.due_meter_value, 'request_creation_id', o.request_creation_id,
        'request_id', o.request_id, 'work_order_id', o.work_order_id,
        'scope_snapshot', o.scope_snapshot, 'planned_at', o.planned_at
      ) END,
      'timing_status', CASE
        WHEN o.id IS NULL THEN NULL
        WHEN p.trigger_type = 'calendar' AND now() > o.due_at THEN 'overdue'
        WHEN p.trigger_type = 'calendar' AND now() >= o.due_at - make_interval(days => p.planning_lead_days) THEN 'due'
        WHEN p.trigger_type = 'calendar' THEN 'upcoming'
        WHEN lr.value IS NULL THEN 'no_reading'
        WHEN lr.value > o.due_meter_value THEN 'overdue'
        WHEN lr.value >= o.due_meter_value - p.meter_lead_value THEN 'due'
        ELSE 'upcoming'
      END,
      'meter_remaining_value', CASE
        WHEN p.trigger_type = 'meter' AND lr.value IS NOT NULL
          THEN o.due_meter_value - lr.value
        ELSE NULL
      END
    ) ORDER BY p.is_active DESC, lower(a.name), lower(c.code))
    FROM public.preventive_maintenance_plans p
    JOIN public.assets a ON a.id = p.asset_id
    JOIN public.maintenance_cards c ON c.id = p.card_id
    LEFT JOIN public.asset_meters m ON m.id = p.meter_id
    LEFT JOIN LATERAL (
      SELECT r.value, r.recorded_at FROM public.asset_meter_readings r
      WHERE r.meter_id = p.meter_id AND r.voided_at IS NULL ORDER BY r.recorded_at DESC LIMIT 1
    ) lr ON true
    LEFT JOIN public.preventive_maintenance_occurrences o
      ON o.plan_id = p.id AND o.status IN ('open', 'planned')
    WHERE p.organization_id = p_organization_id
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_preventive_maintenance_occurrences(
  p_organization_id uuid,
  p_asset_id uuid DEFAULT NULL,
  p_status text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.is_platform_admin() OR public.is_organization_member(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(o) || jsonb_build_object(
      'card_code', c.code, 'card_name', c.name, 'trigger_type', p.trigger_type,
      'priority', p.priority, 'asset_name', a.name, 'asset_code', a.code
    ) ORDER BY o.created_at DESC)
    FROM public.preventive_maintenance_occurrences o
    JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
    JOIN public.maintenance_cards c ON c.id = p.card_id
    JOIN public.assets a ON a.id = o.asset_id
    WHERE o.organization_id = p_organization_id
      AND (p_asset_id IS NULL OR o.asset_id = p_asset_id)
      AND (p_status IS NULL OR o.status = p_status)
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.notify_preventive_occurrence(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_preventive_maintenance_plan(uuid, uuid, uuid, text, text, text, uuid, integer, text, integer, text, timestamptz, uuid, numeric, uuid, numeric, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_preventive_maintenance_plan(uuid, uuid, uuid, text, text, text, uuid, integer, text, integer, text, timestamptz, uuid, numeric, uuid, numeric, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.set_preventive_maintenance_plan_active(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_preventive_maintenance_plan_active(uuid, boolean, text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_preventive_maintenance_plans(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_preventive_maintenance_plans(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_preventive_maintenance_occurrences(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_preventive_maintenance_occurrences(uuid, uuid, text) TO authenticated;

-- =========================================================================
-- H) Planning, skipping and work-order lifecycle integration
-- =========================================================================
CREATE OR REPLACE FUNCTION public.plan_preventive_maintenance_occurrence(
  p_occurrence_id uuid,
  p_request_id uuid
)
RETURNS public.preventive_maintenance_occurrences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan_id uuid;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
  v_request public.requests%ROWTYPE;
BEGIN
  SELECT o.plan_id INTO v_plan_id FROM public.preventive_maintenance_occurrences o WHERE o.id = p_occurrence_id;
  IF v_plan_id IS NULL THEN RAISE EXCEPTION 'Preventive maintenance occurrence not found'; END IF;
  PERFORM p.id FROM public.preventive_maintenance_plans p WHERE p.id = v_plan_id FOR UPDATE;
  SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences WHERE id = p_occurrence_id FOR UPDATE;
  IF NOT public.can_manage_preventive_maintenance(v_occ.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF v_occ.status = 'planned' AND v_occ.request_id = p_request_id THEN RETURN v_occ; END IF;
  IF v_occ.status <> 'open' THEN RAISE EXCEPTION 'Only an open occurrence can be planned'; END IF;
  IF p_request_id <> v_occ.request_creation_id THEN
    RAISE EXCEPTION 'The request id must equal the occurrence request_creation_id';
  END IF;
  SELECT * INTO v_request FROM public.requests WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_request.organization_id IS DISTINCT FROM v_occ.organization_id
    OR v_request.asset_id IS DISTINCT FROM v_occ.asset_id
    OR v_request.service_type::text <> 'preventivo' THEN
    RAISE EXCEPTION 'Request tenant, asset and service type must match the occurrence';
  END IF;
  IF v_request.status::text NOT IN ('draft', 'sent', 'quoted') THEN
    RAISE EXCEPTION 'Request status cannot be linked to preventive maintenance';
  END IF;

  UPDATE public.preventive_maintenance_occurrences SET
    status = 'planned', request_id = v_request.id, planned_at = now()
  WHERE id = v_occ.id RETURNING * INTO v_occ;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_occ.organization_id, v_occ.asset_id, 'preventive_maintenance_planned',
    'Mantenimiento preventivo planificado en una solicitud',
    jsonb_build_object('plan_id', v_occ.plan_id, 'occurrence_id', v_occ.id,
      'request_id', v_request.id, 'sequence', v_occ.sequence), auth.uid()
  );
  PERFORM public.notify_preventive_occurrence(
    v_occ.id, 'preventive_maintenance_planned', 'Mantenimiento preventivo planificado',
    'La ocurrencia preventiva #' || v_occ.sequence::text || ' fue vinculada a una solicitud.'
  );
  RETURN v_occ;
END;
$$;

CREATE OR REPLACE FUNCTION public.skip_preventive_maintenance_occurrence(
  p_occurrence_id uuid,
  p_reason text
)
RETURNS public.preventive_maintenance_occurrences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan_id uuid;
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
BEGIN
  SELECT o.plan_id INTO v_plan_id FROM public.preventive_maintenance_occurrences o WHERE o.id = p_occurrence_id;
  IF v_plan_id IS NULL THEN RAISE EXCEPTION 'Preventive maintenance occurrence not found'; END IF;
  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = v_plan_id FOR UPDATE;
  SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences WHERE id = p_occurrence_id FOR UPDATE;
  IF NOT public.can_manage_preventive_maintenance(v_occ.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF v_occ.status = 'skipped' THEN RETURN v_occ; END IF;
  IF v_occ.status <> 'open' THEN RAISE EXCEPTION 'Only an open occurrence can be skipped'; END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A skip reason is required'; END IF;

  UPDATE public.preventive_maintenance_occurrences SET
    status = 'skipped', skipped_at = now(), skip_reason = TRIM(p_reason)
  WHERE id = v_occ.id RETURNING * INTO v_occ;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_occ.organization_id, v_occ.asset_id, 'preventive_maintenance_skipped',
    'Mantenimiento preventivo omitido: ' || TRIM(p_reason),
    jsonb_build_object('plan_id', v_occ.plan_id, 'occurrence_id', v_occ.id,
      'sequence', v_occ.sequence, 'reason', TRIM(p_reason)), auth.uid()
  );
  PERFORM public.notify_preventive_occurrence(
    v_occ.id, 'preventive_maintenance_skipped', 'Mantenimiento preventivo omitido',
    'La ocurrencia preventiva #' || v_occ.sequence::text || ' fue omitida: ' || TRIM(p_reason)
  );
  IF v_plan.is_active THEN
    IF v_plan.trigger_type = 'calendar' THEN
      PERFORM public.create_preventive_occurrence_locked(
        v_plan.id,
        v_occ.due_at + public.preventive_frequency_interval(v_plan.frequency, v_plan.custom_interval, v_plan.custom_unit),
        NULL
      );
    ELSE
      PERFORM public.create_preventive_occurrence_locked(v_plan.id, NULL, v_occ.due_meter_value + v_plan.interval_value);
    END IF;
  END IF;
  RETURN v_occ;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_work_order_lifecycle_timestamps()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.status = 'in_progress' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'in_progress') THEN
    NEW.started_at := COALESCE(NEW.started_at, now());
  END IF;
  IF NEW.status IN ('completed', 'closed') AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('completed', 'closed')) THEN
    NEW.started_at := COALESCE(NEW.started_at, now());
    NEW.completed_at := COALESCE(NEW.completed_at, now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_orders_lifecycle_timestamps ON public.work_orders;
CREATE TRIGGER trg_work_orders_lifecycle_timestamps
BEFORE INSERT OR UPDATE OF status ON public.work_orders
FOR EACH ROW EXECUTE FUNCTION public.set_work_order_lifecycle_timestamps();

CREATE OR REPLACE FUNCTION public.sync_preventive_occurrence_from_work_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan_id uuid;
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
  v_reading public.asset_meter_readings%ROWTYPE;
  v_next public.preventive_maintenance_occurrences%ROWTYPE;
  v_terminal_transition boolean;
  v_meter_name text;
BEGIN
  v_terminal_transition := NEW.status IN ('completed', 'closed')
    AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('completed', 'closed'));

  SELECT o.plan_id INTO v_plan_id FROM public.preventive_maintenance_occurrences o
  WHERE o.work_order_id = NEW.id OR (o.request_id = NEW.request_id AND o.status = 'planned')
  ORDER BY (o.work_order_id = NEW.id) DESC LIMIT 1;
  IF v_plan_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = v_plan_id FOR UPDATE;
  SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences o
  WHERE o.plan_id = v_plan_id AND (o.work_order_id = NEW.id OR o.request_id = NEW.request_id)
  ORDER BY (o.work_order_id = NEW.id) DESC LIMIT 1 FOR UPDATE;

  IF v_occ.organization_id IS DISTINCT FROM NEW.client_organization_id
    OR v_occ.asset_id IS DISTINCT FROM NEW.asset_id THEN
    RAISE EXCEPTION 'Work order tenant and asset must match the preventive occurrence';
  END IF;
  IF v_occ.request_id IS DISTINCT FROM NEW.request_id THEN
    RAISE EXCEPTION 'Work order request must match the preventive occurrence request';
  END IF;
  IF v_occ.work_order_id IS NULL THEN
    IF v_occ.status <> 'planned' THEN RAISE EXCEPTION 'Only a planned occurrence can attach a work order'; END IF;
    UPDATE public.preventive_maintenance_occurrences SET work_order_id = NEW.id
    WHERE id = v_occ.id RETURNING * INTO v_occ;
  ELSIF v_occ.work_order_id <> NEW.id THEN
    RAISE EXCEPTION 'Preventive occurrence is already attached to a different work order';
  END IF;

  IF NOT v_terminal_transition OR v_occ.status = 'completed' THEN RETURN NEW; END IF;
  IF v_occ.status <> 'planned' THEN RAISE EXCEPTION 'Only a planned occurrence can be completed'; END IF;

  IF v_plan.trigger_type = 'meter' THEN
    SELECT am.name INTO v_meter_name FROM public.asset_meters am WHERE am.id = v_plan.meter_id;
    SELECT r.* INTO v_reading FROM public.asset_meter_readings r
    WHERE r.meter_id = v_plan.meter_id AND r.voided_at IS NULL
      AND r.recorded_at <= NEW.completed_at
    ORDER BY r.recorded_at DESC LIMIT 1;
    IF v_reading.id IS NULL THEN
      RAISE EXCEPTION 'Registra una lectura actual del medidor % antes de completar esta orden.', COALESCE(v_meter_name, 'del plan');
    END IF;
  END IF;

  UPDATE public.preventive_maintenance_occurrences SET
    status = 'completed', completed_at = NEW.completed_at,
    completion_meter_reading_id = CASE WHEN v_plan.trigger_type = 'meter' THEN v_reading.id ELSE NULL END,
    completion_meter_value = CASE WHEN v_plan.trigger_type = 'meter' THEN v_reading.value ELSE NULL END
  WHERE id = v_occ.id RETURNING * INTO v_occ;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_occ.organization_id, v_occ.asset_id, 'preventive_maintenance_completed',
    'Mantenimiento preventivo completado',
    jsonb_build_object('plan_id', v_occ.plan_id, 'occurrence_id', v_occ.id,
      'work_order_id', NEW.id, 'sequence', v_occ.sequence,
      'completion_meter_value', v_occ.completion_meter_value), auth.uid()
  );
  PERFORM public.notify_preventive_occurrence(
    v_occ.id, 'preventive_maintenance_completed', 'Mantenimiento preventivo completado',
    'La ocurrencia preventiva #' || v_occ.sequence::text || ' fue completada.'
  );

  IF v_plan.is_active THEN
    IF v_plan.trigger_type = 'calendar' THEN
      v_next := public.create_preventive_occurrence_locked(
        v_plan.id,
        NEW.completed_at + public.preventive_frequency_interval(v_plan.frequency, v_plan.custom_interval, v_plan.custom_unit),
        NULL
      );
    ELSE
      v_next := public.create_preventive_occurrence_locked(v_plan.id, NULL, v_reading.value + v_plan.interval_value);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_orders_sync_preventive_occurrence ON public.work_orders;
CREATE TRIGGER trg_work_orders_sync_preventive_occurrence
AFTER INSERT OR UPDATE OF status, request_id, asset_id ON public.work_orders
FOR EACH ROW EXECUTE FUNCTION public.sync_preventive_occurrence_from_work_order();

REVOKE ALL ON FUNCTION public.plan_preventive_maintenance_occurrence(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plan_preventive_maintenance_occurrence(uuid, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.skip_preventive_maintenance_occurrence(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.skip_preventive_maintenance_occurrence(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.set_work_order_lifecycle_timestamps() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_preventive_occurrence_from_work_order() FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- I) Integrated asset history labels. Keep the established history UNION in
-- one place and decorate its generic asset-event branch without duplicating
-- any source rows.
-- =========================================================================
ALTER FUNCTION public.get_asset_integrated_history(uuid)
  RENAME TO get_asset_integrated_history_before_preventive;

REVOKE ALL ON FUNCTION public.get_asset_integrated_history_before_preventive(uuid)
FROM PUBLIC, anon, authenticated;

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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    h.id,
    h.event_type,
    CASE ae.event_type
      WHEN 'preventive_plan_created' THEN 'Plan preventivo creado'
      WHEN 'meter_reading_recorded' THEN 'Lectura de medidor registrada'
      WHEN 'preventive_maintenance_planned' THEN 'Mantenimiento preventivo planificado'
      WHEN 'preventive_maintenance_completed' THEN 'Mantenimiento preventivo completado'
      WHEN 'preventive_maintenance_skipped' THEN 'Mantenimiento preventivo omitido'
      ELSE h.event_label
    END,
    h.event_date,
    h.actor_name,
    h.actor_email,
    h.source_table,
    h.source_id,
    CASE ae.event_type
      WHEN 'preventive_plan_created' THEN 'Plan preventivo creado'
      WHEN 'meter_reading_recorded' THEN 'Lectura de medidor registrada'
      WHEN 'preventive_maintenance_planned' THEN 'Mantenimiento preventivo planificado'
      WHEN 'preventive_maintenance_completed' THEN 'Mantenimiento preventivo completado'
      WHEN 'preventive_maintenance_skipped' THEN 'Mantenimiento preventivo omitido'
      ELSE h.title
    END,
    h.description,
    h.status,
    h.metadata
  FROM public.get_asset_integrated_history_before_preventive(p_asset_id) h
  LEFT JOIN public.asset_events ae
    ON h.source_table = 'asset_events' AND ae.id = h.source_id
  ORDER BY h.event_date DESC;
$$;

REVOKE ALL ON FUNCTION public.get_asset_integrated_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_asset_integrated_history(uuid) TO authenticated;
