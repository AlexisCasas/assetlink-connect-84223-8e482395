-- Operational members/roles for internal execution: adds technician
-- assignment to work orders and a narrow, tenant-scoped way to list the
-- technicians a planner is allowed to assign. No new organization_member_role
-- value is introduced — 'technician' already existed; 'manager' is treated as
-- the functional "Planner / Gestor" role at the application layer only.

-- =========================================================================
-- A) work_orders.assigned_member_id
-- =========================================================================
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS assigned_member_id uuid NULL REFERENCES public.organization_members(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_work_orders_assigned_member_id ON public.work_orders (assigned_member_id);

-- Consistency guard: the assigned member must belong to the work order's own
-- provider_organization_id, be active, and hold the technician role. Runs as
-- SECURITY INVOKER on purpose: it only ever executes inside
-- assign_work_order_technician() below (a SECURITY DEFINER function whose
-- context it inherits), so no extra privilege escalation is introduced here.
CREATE OR REPLACE FUNCTION public.check_work_order_assigned_technician()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  member_org uuid;
  member_active boolean;
  member_role public.organization_member_role;
BEGIN
  IF NEW.assigned_member_id IS NOT NULL THEN
    SELECT organization_id, is_active, role
      INTO member_org, member_active, member_role
      FROM public.organization_members
      WHERE id = NEW.assigned_member_id;

    IF member_org IS NULL THEN
      RAISE EXCEPTION 'assigned_member_id does not reference an existing organization member';
    END IF;
    IF member_org <> NEW.provider_organization_id THEN
      RAISE EXCEPTION 'assigned_member_id must belong to the work order provider organization';
    END IF;
    IF NOT member_active THEN
      RAISE EXCEPTION 'assigned_member_id must be an active member';
    END IF;
    IF member_role <> 'technician' THEN
      RAISE EXCEPTION 'assigned_member_id must have the technician role';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_orders_check_assigned_technician ON public.work_orders;
CREATE TRIGGER trg_work_orders_check_assigned_technician
BEFORE INSERT OR UPDATE ON public.work_orders
FOR EACH ROW EXECUTE FUNCTION public.check_work_order_assigned_technician();

-- =========================================================================
-- B) public.assign_work_order_technician(uuid, uuid)
-- Narrow SECURITY DEFINER write path. work_orders still has no generic
-- UPDATE/INSERT/DELETE RLS policy (unchanged from the previous phase, which
-- intentionally deferred those) — this function is the only way to set
-- assigned_member_id, and it re-validates authorization on every call.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.assign_work_order_technician(
  target_work_order_id uuid,
  target_member_id uuid
)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_work_order public.work_orders%ROWTYPE;
  updated_work_order public.work_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO target_work_order FROM public.work_orders WHERE id = target_work_order_id;
  IF target_work_order.id IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      target_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to assign a technician for this work order';
  END IF;

  -- Row consistency (same organization, active, technician role) is enforced
  -- by trg_work_orders_check_assigned_technician on this UPDATE.
  UPDATE public.work_orders
  SET assigned_member_id = target_member_id
  WHERE id = target_work_order_id
  RETURNING * INTO updated_work_order;

  RETURN updated_work_order;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_work_order_technician(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_work_order_technician(uuid, uuid) TO authenticated;

-- =========================================================================
-- C) public.get_assignable_technicians(uuid)
-- Minimal SECURITY DEFINER read: lets a planner (owner/admin/manager) or
-- platform admin resolve the name/email of their own organization's active
-- technicians, without granting frontend direct SELECT on auth.users or
-- exposing organization_members across tenants.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_assignable_technicians(p_organization_id uuid)
RETURNS TABLE (
  member_id uuid,
  user_id uuid,
  name text,
  email text
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
    OR public.has_organization_role(
      p_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to list technicians for this organization';
  END IF;

  RETURN QUERY
  SELECT
    member.id AS member_id,
    member.user_id,
    COALESCE(NULLIF(TRIM(user_account.raw_user_meta_data->>'name'), ''), split_part(user_account.email, '@', 1)) AS name,
    user_account.email::text AS email
  FROM public.organization_members member
  INNER JOIN auth.users user_account ON user_account.id = member.user_id
  WHERE member.organization_id = p_organization_id
    AND member.is_active
    AND member.role = 'technician'
  ORDER BY 3;
END;
$$;

REVOKE ALL ON FUNCTION public.get_assignable_technicians(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_assignable_technicians(uuid) TO authenticated;
