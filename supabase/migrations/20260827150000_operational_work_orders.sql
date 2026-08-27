-- Turns work_orders into one real operational OT entity shared by both
-- origins (external, from an approved quote; internal, from a direct
-- internal request) instead of two parallel modules. No new table replaces
-- work_orders; this migration only extends it plus two small lookup RPCs
-- and updates the two existing creation RPCs to populate the new fields.

-- =========================================================================
-- A1) Correlativo: work_order_number, generated server-side, never by the
-- frontend. Format OT-<created year>-<global sequence, zero-padded 6>. The
-- sequence is global (not reset per year) — numbers stay strictly unique
-- and monotonic without the extra complexity of a per-year counter table;
-- see docs/OPERATIONAL_WORK_ORDERS.md for the rationale.
-- =========================================================================
CREATE SEQUENCE IF NOT EXISTS public.work_order_number_seq;

ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS work_order_number text;

CREATE OR REPLACE FUNCTION public.set_work_order_number()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.work_order_number IS NULL THEN
    NEW.work_order_number := 'OT-' || to_char(now(), 'YYYY') || '-'
      || lpad(nextval('public.work_order_number_seq')::text, 6, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_orders_set_number ON public.work_orders;
CREATE TRIGGER trg_work_orders_set_number
BEFORE INSERT ON public.work_orders
FOR EACH ROW EXECUTE FUNCTION public.set_work_order_number();

-- Backfill any pre-existing row (ordered by created_at, so older orders keep
-- lower numbers) before the column becomes NOT NULL/UNIQUE.
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT id, created_at FROM public.work_orders
    WHERE work_order_number IS NULL ORDER BY created_at ASC
  LOOP
    UPDATE public.work_orders
    SET work_order_number = 'OT-' || to_char(rec.created_at, 'YYYY') || '-'
      || lpad(nextval('public.work_order_number_seq')::text, 6, '0')
    WHERE id = rec.id;
  END LOOP;
END $$;

ALTER TABLE public.work_orders ALTER COLUMN work_order_number SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_work_orders_number ON public.work_orders (work_order_number);

-- =========================================================================
-- A3) Activo: work_orders.asset_id, snapshot-relational (not editable later
-- via the operations RPC — origin fields are immutable once the OT exists).
-- request_id is NOT NULL on work_orders since its very first migration, so
-- every row always has a source request to backfill/validate against.
-- =========================================================================
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS asset_id uuid NULL REFERENCES public.assets(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_work_orders_asset_id ON public.work_orders (asset_id);

UPDATE public.work_orders wo
SET asset_id = r.asset_id
FROM public.requests r
WHERE wo.request_id = r.id AND wo.asset_id IS NULL AND r.asset_id IS NOT NULL;

-- Consistency guard: an asset belongs to a single organization_id (see
-- check_request_asset_organization, same pattern) — work_orders.
-- client_organization_id is always that same organization (both creation
-- RPCs set it from source_request.organization_id), so validating against
-- client_organization_id directly is equivalent to validating against the
-- source request and needs no extra join.
CREATE OR REPLACE FUNCTION public.check_work_order_asset_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  asset_org uuid;
BEGIN
  IF NEW.asset_id IS NOT NULL THEN
    SELECT organization_id INTO asset_org FROM public.assets WHERE id = NEW.asset_id;
    IF asset_org IS NULL OR asset_org <> NEW.client_organization_id THEN
      RAISE EXCEPTION 'asset_id must belong to the work order client organization';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_orders_check_asset_org ON public.work_orders;
CREATE TRIGGER trg_work_orders_check_asset_org
BEFORE INSERT OR UPDATE ON public.work_orders
FOR EACH ROW EXECUTE FUNCTION public.check_work_order_asset_organization();

-- =========================================================================
-- A4) Tipo: work_orders.work_order_type. Explicit column (not just derived
-- from quote_id IS NULL) for cheap, obvious UX filtering/badging, but a
-- CHECK ties it permanently to quote_id nullity so the two can never drift
-- apart — 'internal' rows always mean quote_id IS NULL and vice versa.
-- =========================================================================
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS work_order_type text;

UPDATE public.work_orders
SET work_order_type = CASE WHEN quote_id IS NULL THEN 'internal' ELSE 'external' END
WHERE work_order_type IS NULL;

ALTER TABLE public.work_orders ALTER COLUMN work_order_type SET NOT NULL;
ALTER TABLE public.work_orders ALTER COLUMN work_order_type SET DEFAULT 'external';

DO $$ BEGIN
  ALTER TABLE public.work_orders ADD CONSTRAINT work_orders_type_check
    CHECK (work_order_type IN ('internal', 'external'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.work_orders ADD CONSTRAINT work_orders_type_quote_consistency
    CHECK (
      (work_order_type = 'internal' AND quote_id IS NULL)
      OR (work_order_type = 'external' AND quote_id IS NOT NULL)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =========================================================================
-- A5) Planner: work_orders.planner_member_id. "Organización operadora" is
-- provider_organization_id for both origins — for an internal OT that
-- column already equals client_organization_id (see
-- create_internal_work_order_from_request), so this single column/trigger
-- covers both flows without branching.
-- =========================================================================
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS planner_member_id uuid NULL REFERENCES public.organization_members(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_work_orders_planner_member_id ON public.work_orders (planner_member_id);

-- Same pattern/rationale as check_work_order_assigned_technician: SECURITY
-- INVOKER, only ever runs inside a SECURITY DEFINER RPC.
CREATE OR REPLACE FUNCTION public.check_work_order_planner()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  member_org uuid;
  member_active boolean;
  member_role public.organization_member_role;
BEGIN
  IF NEW.planner_member_id IS NOT NULL THEN
    SELECT organization_id, is_active, role
      INTO member_org, member_active, member_role
      FROM public.organization_members
      WHERE id = NEW.planner_member_id;

    IF member_org IS NULL THEN
      RAISE EXCEPTION 'planner_member_id does not reference an existing organization member';
    END IF;
    IF member_org <> NEW.provider_organization_id THEN
      RAISE EXCEPTION 'planner_member_id must belong to the work order provider organization';
    END IF;
    IF NOT member_active THEN
      RAISE EXCEPTION 'planner_member_id must be an active member';
    END IF;
    IF member_role NOT IN ('owner', 'admin', 'manager') THEN
      RAISE EXCEPTION 'planner_member_id must have owner, admin or manager role';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_orders_check_planner ON public.work_orders;
CREATE TRIGGER trg_work_orders_check_planner
BEFORE INSERT OR UPDATE ON public.work_orders
FOR EACH ROW EXECUTE FUNCTION public.check_work_order_planner();

-- =========================================================================
-- A6) Técnico(s): assigned_member_id already exists (previous phase) and
-- stays the single principal technician. A work_order_technicians bridge
-- table for multiple technicians is explicitly deferred — see
-- docs/OPERATIONAL_WORK_ORDERS.md §7 (Pendiente).
-- =========================================================================

-- =========================================================================
-- A7/A8) Fechas: scheduled_at / due_at as timestamptz, matching the
-- project's existing convention for operational dates (requests.deadline,
-- quotes timestamps, etc. are all timestamptz — no plain `date` column
-- exists anywhere else in this schema for a similar concept).
-- =========================================================================
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS scheduled_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS due_at timestamptz NULL;

UPDATE public.work_orders wo
SET due_at = r.deadline
FROM public.requests r
WHERE wo.request_id = r.id AND wo.due_at IS NULL;

-- =========================================================================
-- A9) Prioridad: work_orders.priority, backfilled from requests.priority
-- (1 = emergencia..4 = proyecto, see RequestForm.tsx's priorityMap) via a
-- small reusable mapping function — used here and by both creation RPCs
-- below, so the mapping lives in exactly one place.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.map_request_priority_to_work_order_priority(request_priority integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN request_priority = 1 THEN 'urgent'
    WHEN request_priority = 2 THEN 'high'
    WHEN request_priority = 3 THEN 'medium'
    WHEN request_priority = 4 THEN 'low'
    ELSE 'medium'
  END;
$$;

ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS priority text;

UPDATE public.work_orders wo
SET priority = public.map_request_priority_to_work_order_priority(r.priority)
FROM public.requests r
WHERE wo.request_id = r.id AND wo.priority IS NULL;

UPDATE public.work_orders SET priority = 'medium' WHERE priority IS NULL;

ALTER TABLE public.work_orders ALTER COLUMN priority SET NOT NULL;
ALTER TABLE public.work_orders ALTER COLUMN priority SET DEFAULT 'medium';

DO $$ BEGIN
  ALTER TABLE public.work_orders ADD CONSTRAINT work_orders_priority_check
    CHECK (priority IN ('low', 'medium', 'high', 'urgent'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =========================================================================
-- A10) Estado: extend the operational lifecycle. The only status value ever
-- written anywhere in the app is the column default 'created' (grep across
-- migrations and src/ confirms no RPC/UI ever set another value), so the
-- backfill below is exhaustive — no legacy value needs to remain valid.
-- =========================================================================
UPDATE public.work_orders
SET status = CASE WHEN assigned_member_id IS NOT NULL THEN 'assigned' ELSE 'pending' END
WHERE status = 'created';

ALTER TABLE public.work_orders ALTER COLUMN status SET DEFAULT 'pending';

DO $$ BEGIN
  ALTER TABLE public.work_orders ADD CONSTRAINT work_orders_status_check
    CHECK (status IN ('pending', 'assigned', 'in_progress', 'completed', 'closed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =========================================================================
-- A11) Observaciones
-- =========================================================================
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS observations text NULL;

-- =========================================================================
-- B) Resolve the calling user's own planner-eligible membership in a given
-- organization, or NULL if none. Used by both creation RPCs below to set
-- planner_member_id "si se puede resolver de forma segura; si no, null" —
-- never trusts a client-supplied member id for this field.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.resolve_caller_planner_member(p_organization_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT member.id
  FROM public.organization_members member
  WHERE member.organization_id = p_organization_id
    AND member.user_id = auth.uid()
    AND member.is_active
    AND member.role IN ('owner', 'admin', 'manager')
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.resolve_caller_planner_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_caller_planner_member(uuid) TO authenticated;

-- =========================================================================
-- get_assignable_planners: mirrors get_assignable_technicians exactly, but
-- for the owner/admin/manager ("Planner / Gestor") role set instead of
-- technician. Same authorization, same auth.users join, same non-leak
-- guarantees.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_assignable_planners(p_organization_id uuid)
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
    RAISE EXCEPTION 'Not authorized to list planners for this organization';
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
    AND member.role IN ('owner', 'admin', 'manager')
  ORDER BY 3;
END;
$$;

REVOKE ALL ON FUNCTION public.get_assignable_planners(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_assignable_planners(uuid) TO authenticated;

-- =========================================================================
-- update_work_order_operations: the only way to edit the operational fields
-- of an existing OT (planner, technician, dates, priority, status,
-- observations). Origin fields (request_id, quote_id, asset_id,
-- work_order_type, client/provider_organization_id) are immutable here by
-- design — they describe where the OT came from, not how it's being run.
-- Full-replace semantics (frontend always sends the complete current state
-- of every editable field), same convention as assign_work_order_technician
-- — no partial-patch/"clear" flags needed. No generic UPDATE policy is
-- added to work_orders; this remains the only write path for these fields.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.update_work_order_operations(
  target_work_order_id uuid,
  target_planner_member_id uuid,
  target_assigned_member_id uuid,
  target_scheduled_at timestamptz,
  target_due_at timestamptz,
  target_priority text,
  target_status text,
  target_observations text
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

  -- Only owner/admin/manager of the operating organization (provider_organization_id
  -- — for internal OTs this is the same organization as the client) or a
  -- platform admin may edit. Technicians can view but not edit in this phase.
  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      target_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to edit this work order';
  END IF;

  IF target_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'Invalid priority value';
  END IF;
  IF target_status NOT IN ('pending', 'assigned', 'in_progress', 'completed', 'closed') THEN
    RAISE EXCEPTION 'Invalid status value';
  END IF;

  -- planner_member_id / assigned_member_id row consistency (organization,
  -- active, role) is enforced by trg_work_orders_check_planner and
  -- trg_work_orders_check_assigned_technician on this UPDATE.
  UPDATE public.work_orders
  SET planner_member_id = target_planner_member_id,
      assigned_member_id = target_assigned_member_id,
      scheduled_at = target_scheduled_at,
      due_at = target_due_at,
      priority = target_priority,
      status = target_status,
      observations = target_observations
  WHERE id = target_work_order_id
  RETURNING * INTO updated_work_order;

  RETURN updated_work_order;
END;
$$;

REVOKE ALL ON FUNCTION public.update_work_order_operations(uuid, uuid, uuid, timestamptz, timestamptz, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_work_order_operations(uuid, uuid, uuid, timestamptz, timestamptz, text, text, text) TO authenticated;

-- =========================================================================
-- assign_work_order_technician: unchanged authorization/validation, but now
-- also nudges status between the two "obvious" states around an assignment
-- (pending -> assigned when a technician is set; assigned -> pending when
-- cleared), so an OT can't get stuck showing "pending" right after a
-- technician was assigned. Never touches in_progress/completed/closed —
-- those are deliberate planner decisions made via update_work_order_operations.
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

  UPDATE public.work_orders
  SET assigned_member_id = target_member_id,
      status = CASE
        WHEN target_member_id IS NOT NULL AND status = 'pending' THEN 'assigned'
        WHEN target_member_id IS NULL AND status = 'assigned' THEN 'pending'
        ELSE status
      END
  WHERE id = target_work_order_id
  RETURNING * INTO updated_work_order;

  RETURN updated_work_order;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_work_order_technician(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_work_order_technician(uuid, uuid) TO authenticated;

-- =========================================================================
-- C) Creation RPCs updated to populate the new operational fields.
-- =========================================================================

-- External: from an approved quote. work_order_type is left to its column
-- DEFAULT 'external' (still listed explicitly below for readability).
CREATE OR REPLACE FUNCTION public.create_work_order_from_quote(target_quote_id uuid)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  source_quote public.quotes%ROWTYPE;
  source_request public.requests%ROWTYPE;
  created_work_order public.work_orders%ROWTYPE;
  can_create boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT quote.* INTO source_quote
  FROM public.quotes quote
  WHERE quote.id = target_quote_id
  FOR UPDATE;

  IF source_quote.id IS NULL THEN
    RAISE EXCEPTION 'Quote not found';
  END IF;

  IF source_quote.status <> 'approved' THEN
    RAISE EXCEPTION 'A work order can only be created from an approved quote';
  END IF;

  IF source_quote.provider_organization_id IS NULL THEN
    RAISE EXCEPTION 'Approved quote has no provider organization';
  END IF;

  SELECT request.* INTO source_request
  FROM public.requests request
  WHERE request.id = source_quote.request_id;

  IF source_request.id IS NULL OR source_request.organization_id IS NULL THEN
    RAISE EXCEPTION 'Quote request has no client organization';
  END IF;

  can_create := public.is_platform_admin()
    OR public.has_organization_role(
      source_request.organization_id,
      ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
    );

  IF NOT can_create THEN
    RAISE EXCEPTION 'Not authorized to create a work order for this quote';
  END IF;

  INSERT INTO public.work_orders (
    request_id,
    quote_id,
    client_organization_id,
    provider_organization_id,
    work_order_type,
    asset_id,
    priority,
    due_at,
    planner_member_id,
    status,
    title,
    description,
    total_amount,
    created_by_user_id
  ) VALUES (
    source_quote.request_id,
    source_quote.id,
    source_request.organization_id,
    source_quote.provider_organization_id,
    'external',
    source_request.asset_id,
    public.map_request_priority_to_work_order_priority(source_request.priority),
    source_request.deadline,
    public.resolve_caller_planner_member(source_quote.provider_organization_id),
    'pending',
    source_request.title,
    source_quote.description,
    source_quote.total_amount,
    auth.uid()
  )
  ON CONFLICT (quote_id) DO NOTHING
  RETURNING * INTO created_work_order;

  IF created_work_order.id IS NULL THEN
    SELECT work_order.* INTO created_work_order
    FROM public.work_orders work_order
    WHERE work_order.quote_id = source_quote.id;

    RETURN created_work_order;
  END IF;

  PERFORM public.create_organization_notification(
    source_quote.provider_organization_id,
    auth.uid(),
    'work_order_created',
    'Nueva orden de trabajo',
    'Se creo una orden de trabajo a partir de una cotizacion aprobada.',
    'work_order',
    created_work_order.id,
    source_quote.request_id,
    source_quote.id
  );

  RETURN created_work_order;
END;
$$;

REVOKE ALL ON FUNCTION public.create_work_order_from_quote(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_work_order_from_quote(uuid) TO authenticated;

-- Internal: from a direct internal request. work_order_type is left to
-- 'external' DEFAULT? No — explicit 'internal' below (quote_id stays NULL,
-- satisfying work_orders_type_quote_consistency).
CREATE OR REPLACE FUNCTION public.create_internal_work_order_from_request(
  target_request_id uuid,
  target_assigned_member_id uuid DEFAULT NULL
)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  source_request public.requests%ROWTYPE;
  existing_work_order public.work_orders%ROWTYPE;
  created_work_order public.work_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO source_request FROM public.requests WHERE id = target_request_id;
  IF source_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  IF source_request.request_type <> 'internal' THEN
    RAISE EXCEPTION 'Only internal requests can generate a direct work order';
  END IF;

  IF source_request.organization_id IS NULL THEN
    RAISE EXCEPTION 'Request has no client organization';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organizations organization
    WHERE organization.id = source_request.organization_id
      AND organization.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Request organization is not active';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      source_request.organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to generate a work order for this request';
  END IF;

  SELECT * INTO existing_work_order
    FROM public.work_orders
    WHERE request_id = target_request_id AND quote_id IS NULL;

  IF existing_work_order.id IS NOT NULL THEN
    RETURN existing_work_order;
  END IF;

  INSERT INTO public.work_orders (
    request_id,
    quote_id,
    client_organization_id,
    provider_organization_id,
    work_order_type,
    asset_id,
    priority,
    due_at,
    planner_member_id,
    assigned_member_id,
    status,
    title,
    description,
    created_by_user_id
  ) VALUES (
    target_request_id,
    NULL,
    source_request.organization_id,
    source_request.organization_id,
    'internal',
    source_request.asset_id,
    public.map_request_priority_to_work_order_priority(source_request.priority),
    source_request.deadline,
    public.resolve_caller_planner_member(source_request.organization_id),
    target_assigned_member_id,
    CASE WHEN target_assigned_member_id IS NOT NULL THEN 'assigned' ELSE 'pending' END,
    source_request.title,
    source_request.description,
    auth.uid()
  )
  RETURNING * INTO created_work_order;

  RETURN created_work_order;
END;
$$;

REVOKE ALL ON FUNCTION public.create_internal_work_order_from_request(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_internal_work_order_from_request(uuid, uuid) TO authenticated;
