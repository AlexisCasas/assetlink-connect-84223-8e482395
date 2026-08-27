-- Minimal inventory + OT materials. Explicitly NOT SAP MM: no kardex, no
-- valuation, no purchase orders, no transfers, no complex reservations, no
-- lots, no average costing, no accounting movements, no automatic stock
-- deduction. Just: warehouses, materials with a simple stock number, and
-- materials planned/used per work order with a soft (non-blocking) warning
-- when stock looks insufficient. Same rule as work_order_activities before
-- it: materials hang off work_orders, no separate "internal"/"external"
-- materials module.
--
-- Every table alias is used consistently (wo/woa/wh/m/wom/cb/om) and every
-- write RPC is fully qualified — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for exactly
-- the class of bug (42702 ambiguous_column from RETURNS TABLE OUT
-- variables) this is deliberately avoiding from the start.

-- =========================================================================
-- A1) warehouses
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.warehouses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  branch_id uuid NULL REFERENCES public.client_branches(id) ON DELETE SET NULL,
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT warehouses_name_check CHECK (TRIM(name) <> '')
);

CREATE INDEX IF NOT EXISTS idx_warehouses_organization_id ON public.warehouses (organization_id);
CREATE INDEX IF NOT EXISTS idx_warehouses_branch_id ON public.warehouses (branch_id);
CREATE INDEX IF NOT EXISTS idx_warehouses_is_active ON public.warehouses (organization_id, is_active);

DROP TRIGGER IF EXISTS trg_warehouses_updated_at ON public.warehouses;
CREATE TRIGGER trg_warehouses_updated_at
BEFORE UPDATE ON public.warehouses
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Consistency guard: an optional branch must belong to the same
-- organization_id as the warehouse. SECURITY INVOKER on purpose — only
-- ever runs inside the SECURITY DEFINER RPCs below.
CREATE OR REPLACE FUNCTION public.check_warehouse_branch_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_branch_org uuid;
BEGIN
  IF NEW.branch_id IS NOT NULL THEN
    SELECT cb.organization_id INTO v_branch_org FROM public.client_branches cb WHERE cb.id = NEW.branch_id;
    IF v_branch_org IS NULL OR v_branch_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'branch_id must belong to the same organization_id';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_warehouses_check_branch ON public.warehouses;
CREATE TRIGGER trg_warehouses_check_branch
BEFORE INSERT OR UPDATE ON public.warehouses
FOR EACH ROW EXECUTE FUNCTION public.check_warehouse_branch_organization();

-- =========================================================================
-- A2) materials
-- Uniqueness decision: UNIQUE(organization_id, lower(code)) — a code is a
-- catalog-wide SKU for the organization, not per-warehouse. Two warehouses
-- cannot each have their own "ROD-001" meaning different things; if the
-- same material physically sits in two warehouses, that is out of scope
-- for this phase (would need a stock-per-warehouse model, i.e. real
-- kardex — explicitly not built here). See docs/MINIMAL_INVENTORY_MATERIALS.md.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.materials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  warehouse_id uuid NOT NULL REFERENCES public.warehouses(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  unit text NOT NULL,
  stock numeric(12, 2) NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT materials_code_check CHECK (TRIM(code) <> ''),
  CONSTRAINT materials_name_check CHECK (TRIM(name) <> ''),
  CONSTRAINT materials_unit_check CHECK (TRIM(unit) <> ''),
  CONSTRAINT materials_stock_check CHECK (stock >= 0)
);

CREATE INDEX IF NOT EXISTS idx_materials_organization_id ON public.materials (organization_id);
CREATE INDEX IF NOT EXISTS idx_materials_warehouse_id ON public.materials (warehouse_id);
CREATE INDEX IF NOT EXISTS idx_materials_code ON public.materials (code);
CREATE INDEX IF NOT EXISTS idx_materials_is_active ON public.materials (organization_id, is_active);
CREATE UNIQUE INDEX IF NOT EXISTS uq_materials_org_code ON public.materials (organization_id, lower(code));

DROP TRIGGER IF EXISTS trg_materials_updated_at ON public.materials;
CREATE TRIGGER trg_materials_updated_at
BEFORE UPDATE ON public.materials
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Consistency guard: the warehouse must belong to the same organization_id
-- as the material.
CREATE OR REPLACE FUNCTION public.check_material_warehouse_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_warehouse_org uuid;
BEGIN
  SELECT wh.organization_id INTO v_warehouse_org FROM public.warehouses wh WHERE wh.id = NEW.warehouse_id;
  IF v_warehouse_org IS NULL THEN
    RAISE EXCEPTION 'warehouse_id does not reference an existing warehouse';
  END IF;
  IF v_warehouse_org <> NEW.organization_id THEN
    RAISE EXCEPTION 'warehouse_id must belong to the same organization_id';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_materials_check_warehouse ON public.materials;
CREATE TRIGGER trg_materials_check_warehouse
BEFORE INSERT OR UPDATE ON public.materials
FOR EACH ROW EXECUTE FUNCTION public.check_material_warehouse_organization();

-- =========================================================================
-- A3) work_order_materials — planned/used materials per OT. Deliberately
-- NOT a stock movement: stock_snapshot freezes materials.stock at the
-- moment the line is created (or the material is swapped on an existing
-- line); materials.stock itself is never decremented automatically by
-- anything in this migration.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.work_order_materials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id uuid NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  material_id uuid NOT NULL REFERENCES public.materials(id) ON DELETE RESTRICT,
  planned_quantity numeric(12, 2) NOT NULL DEFAULT 0,
  used_quantity numeric(12, 2) NOT NULL DEFAULT 0,
  stock_snapshot numeric(12, 2) NOT NULL DEFAULT 0,
  notes text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT work_order_materials_planned_check CHECK (planned_quantity >= 0),
  CONSTRAINT work_order_materials_used_check CHECK (used_quantity >= 0)
);

CREATE INDEX IF NOT EXISTS idx_work_order_materials_work_order_id ON public.work_order_materials (work_order_id);
CREATE INDEX IF NOT EXISTS idx_work_order_materials_organization_id ON public.work_order_materials (organization_id);
CREATE INDEX IF NOT EXISTS idx_work_order_materials_material_id ON public.work_order_materials (material_id);

DROP TRIGGER IF EXISTS trg_work_order_materials_updated_at ON public.work_order_materials;
CREATE TRIGGER trg_work_order_materials_updated_at
BEFORE UPDATE ON public.work_order_materials
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Consistency guard: organization_id must equal the OT's own operating
-- organization (work_orders.provider_organization_id — same anchor used by
-- work_order_activities.organization_id), and the material must belong to
-- that same organization too.
CREATE OR REPLACE FUNCTION public.check_work_order_material_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_operating_org uuid;
  v_material_org uuid;
BEGIN
  SELECT wo.provider_organization_id INTO v_operating_org FROM public.work_orders wo WHERE wo.id = NEW.work_order_id;
  IF v_operating_org IS NULL THEN
    RAISE EXCEPTION 'work_order_id does not reference an existing work order';
  END IF;
  IF NEW.organization_id <> v_operating_org THEN
    RAISE EXCEPTION 'organization_id must match the work order operating organization';
  END IF;

  SELECT m.organization_id INTO v_material_org FROM public.materials m WHERE m.id = NEW.material_id;
  IF v_material_org IS NULL THEN
    RAISE EXCEPTION 'material_id does not reference an existing material';
  END IF;
  IF v_material_org <> v_operating_org THEN
    RAISE EXCEPTION 'material_id must belong to the work order operating organization';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_materials_check_org ON public.work_order_materials;
CREATE TRIGGER trg_work_order_materials_check_org
BEFORE INSERT OR UPDATE ON public.work_order_materials
FOR EACH ROW EXECUTE FUNCTION public.check_work_order_material_organization();

-- =========================================================================
-- RLS. warehouses/materials: any active member of the organization can
-- read the catalog (it is organization-wide reference data). work_order_materials:
-- same restrictive "operating organization only" visibility as
-- work_order_activities — the client side of an external OT does not see
-- material planning detail, only the OT it belongs to does; for an
-- internal OT the two coincide. No INSERT/UPDATE/DELETE policy on any of
-- the three tables — the RPCs below (SECURITY DEFINER) remain the only
-- write path, and "delete" for warehouses/materials is always logical
-- (is_active = false) via upsert_warehouse/upsert_material, never a real
-- DELETE.
-- =========================================================================
ALTER TABLE public.warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_order_materials ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organization members can view warehouses" ON public.warehouses
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization members can view materials" ON public.materials
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "operating organization members can view work order materials" ON public.work_order_materials
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

GRANT SELECT ON TABLE public.warehouses TO authenticated;
GRANT SELECT ON TABLE public.materials TO authenticated;
GRANT SELECT ON TABLE public.work_order_materials TO authenticated;

-- =========================================================================
-- B1) get_inventory_catalog: active warehouses + active materials for one
-- organization, bundled as a single jsonb object (one round trip).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_inventory_catalog(p_organization_id uuid)
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
    RAISE EXCEPTION 'Not authorized to view inventory for this organization';
  END IF;

  SELECT jsonb_build_object(
    'warehouses', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', wh.id,
        'name', wh.name,
        'branch_id', wh.branch_id,
        'is_active', wh.is_active
      ) ORDER BY wh.name)
      FROM public.warehouses wh
      WHERE wh.organization_id = p_organization_id AND wh.is_active
    ), '[]'::jsonb),
    'materials', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', m.id,
        'warehouse_id', m.warehouse_id,
        'warehouse_name', wh.name,
        'code', m.code,
        'name', m.name,
        'unit', m.unit,
        'stock', m.stock,
        'is_active', m.is_active
      ) ORDER BY m.code)
      FROM public.materials m
      INNER JOIN public.warehouses wh ON wh.id = m.warehouse_id
      WHERE m.organization_id = p_organization_id AND m.is_active
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_inventory_catalog(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_inventory_catalog(uuid) TO authenticated;

-- =========================================================================
-- B2) upsert_warehouse
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_warehouse(
  p_organization_id uuid,
  p_name text,
  p_warehouse_id uuid DEFAULT NULL,
  p_branch_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.warehouses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_saved public.warehouses%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage warehouses for this organization';
  END IF;

  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RAISE EXCEPTION 'name is required';
  END IF;

  IF p_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.client_branches cb WHERE cb.id = p_branch_id AND cb.organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'branch_id must belong to the same organization';
  END IF;

  IF p_warehouse_id IS NOT NULL THEN
    UPDATE public.warehouses wh
    SET name = TRIM(p_name),
        branch_id = p_branch_id,
        is_active = p_is_active
    WHERE wh.id = p_warehouse_id AND wh.organization_id = p_organization_id
    RETURNING wh.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Warehouse not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.warehouses AS wh (organization_id, branch_id, name, is_active)
    VALUES (p_organization_id, p_branch_id, TRIM(p_name), p_is_active)
    RETURNING wh.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_warehouse(uuid, text, uuid, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_warehouse(uuid, text, uuid, uuid, boolean) TO authenticated;

-- =========================================================================
-- B3) upsert_material
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_material(
  p_organization_id uuid,
  p_warehouse_id uuid,
  p_code text,
  p_name text,
  p_unit text,
  p_material_id uuid DEFAULT NULL,
  p_stock numeric DEFAULT 0,
  p_is_active boolean DEFAULT true
)
RETURNS public.materials
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_saved public.materials%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage materials for this organization';
  END IF;

  IF p_code IS NULL OR TRIM(p_code) = '' THEN
    RAISE EXCEPTION 'code is required';
  END IF;
  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RAISE EXCEPTION 'name is required';
  END IF;
  IF p_unit IS NULL OR TRIM(p_unit) = '' THEN
    RAISE EXCEPTION 'unit is required';
  END IF;
  IF p_stock IS NULL OR p_stock < 0 THEN
    RAISE EXCEPTION 'stock must be >= 0';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.warehouses wh WHERE wh.id = p_warehouse_id AND wh.organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'warehouse_id must belong to the same organization';
  END IF;

  IF p_material_id IS NOT NULL THEN
    UPDATE public.materials m
    SET warehouse_id = p_warehouse_id,
        code = TRIM(p_code),
        name = TRIM(p_name),
        unit = TRIM(p_unit),
        stock = p_stock,
        is_active = p_is_active
    WHERE m.id = p_material_id AND m.organization_id = p_organization_id
    RETURNING m.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Material not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.materials AS m (organization_id, warehouse_id, code, name, unit, stock, is_active)
    VALUES (p_organization_id, p_warehouse_id, TRIM(p_code), TRIM(p_name), TRIM(p_unit), p_stock, p_is_active)
    RETURNING m.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_material(uuid, uuid, text, text, text, uuid, numeric, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_material(uuid, uuid, text, text, text, uuid, numeric, boolean) TO authenticated;

-- =========================================================================
-- B4) get_work_order_materials: warning_status is computed here, once,
-- server-side — the frontend never re-derives the ok/no_stock/
-- insufficient_stock rule itself, so the "advertencia, no bloqueo" logic
-- lives in exactly one place.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_work_order_materials(p_work_order_id uuid)
RETURNS TABLE (
  id uuid,
  material_id uuid,
  material_code text,
  material_name text,
  material_unit text,
  warehouse_id uuid,
  warehouse_name text,
  planned_quantity numeric,
  used_quantity numeric,
  stock_snapshot numeric,
  current_stock numeric,
  warning_status text,
  notes text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_operating_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT wo.provider_organization_id INTO v_operating_org
    FROM public.work_orders wo
    WHERE wo.id = p_work_order_id;

  IF v_operating_org IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(v_operating_org)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view materials for this work order';
  END IF;

  RETURN QUERY
  SELECT
    wom.id,
    wom.material_id,
    m.code,
    m.name,
    m.unit,
    m.warehouse_id,
    wh.name,
    wom.planned_quantity,
    wom.used_quantity,
    wom.stock_snapshot,
    m.stock,
    CASE
      WHEN m.stock = 0 AND wom.planned_quantity > 0 THEN 'no_stock'
      WHEN m.stock < wom.planned_quantity THEN 'insufficient_stock'
      ELSE 'ok'
    END,
    wom.notes,
    wom.created_at,
    wom.updated_at
  FROM public.work_order_materials wom
  INNER JOIN public.materials m ON m.id = wom.material_id
  INNER JOIN public.warehouses wh ON wh.id = m.warehouse_id
  WHERE wom.work_order_id = p_work_order_id
  ORDER BY wom.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.get_work_order_materials(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_work_order_materials(uuid) TO authenticated;

-- =========================================================================
-- B5) upsert_work_order_material. Never blocks on insufficient stock — the
-- warning is purely informational, computed by get_work_order_materials.
-- stock_snapshot is refreshed only when the line is new or the material
-- itself changes; editing quantities on the same material preserves the
-- original snapshot (it is a "stock at planning time" marker, not a live
-- value — current_stock from get_work_order_materials is the live one).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_work_order_material(
  p_work_order_id uuid,
  p_material_id uuid,
  p_work_order_material_id uuid DEFAULT NULL,
  p_planned_quantity numeric DEFAULT 0,
  p_used_quantity numeric DEFAULT 0,
  p_notes text DEFAULT NULL
)
RETURNS public.work_order_materials
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_work_order public.work_orders%ROWTYPE;
  v_material public.materials%ROWTYPE;
  v_existing public.work_order_materials%ROWTYPE;
  v_saved public.work_order_materials%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT wo.* INTO v_work_order FROM public.work_orders wo WHERE wo.id = p_work_order_id;
  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_work_order.provider_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage materials for this work order';
  END IF;

  IF p_planned_quantity IS NULL OR p_planned_quantity < 0 THEN
    RAISE EXCEPTION 'planned_quantity must be >= 0';
  END IF;
  IF p_used_quantity IS NULL OR p_used_quantity < 0 THEN
    RAISE EXCEPTION 'used_quantity must be >= 0';
  END IF;

  SELECT m.* INTO v_material FROM public.materials m WHERE m.id = p_material_id;
  IF v_material.id IS NULL THEN
    RAISE EXCEPTION 'Material not found';
  END IF;
  IF v_material.organization_id <> v_work_order.provider_organization_id THEN
    RAISE EXCEPTION 'material_id must belong to the work order operating organization';
  END IF;

  IF p_work_order_material_id IS NOT NULL THEN
    SELECT wom.* INTO v_existing FROM public.work_order_materials wom WHERE wom.id = p_work_order_material_id;
    IF v_existing.id IS NULL OR v_existing.work_order_id <> p_work_order_id THEN
      RAISE EXCEPTION 'Material line not found for this work order';
    END IF;

    UPDATE public.work_order_materials wom
    SET material_id = p_material_id,
        planned_quantity = p_planned_quantity,
        used_quantity = p_used_quantity,
        stock_snapshot = CASE WHEN v_existing.material_id <> p_material_id THEN v_material.stock ELSE wom.stock_snapshot END,
        notes = p_notes
    WHERE wom.id = p_work_order_material_id
    RETURNING wom.* INTO v_saved;
  ELSE
    INSERT INTO public.work_order_materials AS wom (
      work_order_id, organization_id, material_id, planned_quantity, used_quantity, stock_snapshot, notes
    ) VALUES (
      p_work_order_id, v_work_order.provider_organization_id, p_material_id, p_planned_quantity, p_used_quantity, v_material.stock, p_notes
    )
    RETURNING wom.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_work_order_material(uuid, uuid, uuid, numeric, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_work_order_material(uuid, uuid, uuid, numeric, numeric, text) TO authenticated;

-- =========================================================================
-- B6) delete_work_order_material: only the planning line, never the
-- material master (materials has no delete RPC at all — only
-- upsert_material with is_active = false).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.delete_work_order_material(p_work_order_material_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.work_order_materials%ROWTYPE;
  v_work_order public.work_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT wom.* INTO v_existing FROM public.work_order_materials wom WHERE wom.id = p_work_order_material_id;
  IF v_existing.id IS NULL THEN
    RAISE EXCEPTION 'Material line not found';
  END IF;

  SELECT wo.* INTO v_work_order FROM public.work_orders wo WHERE wo.id = v_existing.work_order_id;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_work_order.provider_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to delete this material line';
  END IF;

  DELETE FROM public.work_order_materials wom WHERE wom.id = p_work_order_material_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_work_order_material(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_work_order_material(uuid) TO authenticated;
