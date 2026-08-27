-- Internal requests: a request can now be executed directly by the client's
-- own organization (request_type = 'internal') instead of always going
-- through providers/quotes/marketplace (request_type = 'external', the
-- default and the only kind that existed before this migration — every
-- existing row backfills to 'external' automatically via the NOT NULL
-- DEFAULT below, so legacy data needs no special-casing in the app).

-- =========================================================================
-- A) requests.request_type
-- =========================================================================
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS request_type text NOT NULL DEFAULT 'external';

DO $$ BEGIN
  ALTER TABLE public.requests
    ADD CONSTRAINT requests_request_type_check CHECK (request_type IN ('external', 'internal'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_requests_request_type ON public.requests (organization_id, request_type);

-- =========================================================================
-- B) requests.internal_responsible_member_id (optional)
-- =========================================================================
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS internal_responsible_member_id uuid NULL REFERENCES public.organization_members(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_requests_internal_responsible_member_id ON public.requests (internal_responsible_member_id);

-- Consistency guard, same pattern as work_orders' assigned-technician trigger
-- from the previous phase: the responsible member must belong to the
-- request's own organization_id, be active, and be a technician. Runs as
-- SECURITY INVOKER — the caller (owner/admin/manager/requester creating or
-- editing their own organization's request) already has read access to that
-- organization's own members via existing RLS, so no privilege escalation.
CREATE OR REPLACE FUNCTION public.check_request_internal_responsible()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  member_org uuid;
  member_active boolean;
  member_role public.organization_member_role;
BEGIN
  IF NEW.internal_responsible_member_id IS NOT NULL THEN
    SELECT organization_id, is_active, role
      INTO member_org, member_active, member_role
      FROM public.organization_members
      WHERE id = NEW.internal_responsible_member_id;

    IF member_org IS NULL THEN
      RAISE EXCEPTION 'internal_responsible_member_id does not reference an existing organization member';
    END IF;
    IF NEW.organization_id IS NULL OR member_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'internal_responsible_member_id must belong to the request organization';
    END IF;
    IF NOT member_active THEN
      RAISE EXCEPTION 'internal_responsible_member_id must be an active member';
    END IF;
    IF member_role <> 'technician' THEN
      RAISE EXCEPTION 'internal_responsible_member_id must have the technician role';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_requests_check_internal_responsible ON public.requests;
CREATE TRIGGER trg_requests_check_internal_responsible
BEFORE INSERT OR UPDATE ON public.requests
FOR EACH ROW EXECUTE FUNCTION public.check_request_internal_responsible();

-- =========================================================================
-- C) work_orders.quote_id becomes optional (internal work orders have none)
-- request_id was already NOT NULL since the very first work_orders
-- migration — nothing to add there, trazability already exists.
-- =========================================================================
ALTER TABLE public.work_orders ALTER COLUMN quote_id DROP NOT NULL;
-- quote_id keeps its UNIQUE constraint; Postgres allows multiple NULLs under
-- a UNIQUE constraint, so many internal work orders can coexist.

-- =========================================================================
-- D) public.create_internal_work_order_from_request(uuid, uuid)
-- Narrow SECURITY DEFINER write path, same family as create_work_order_from_quote
-- and assign_work_order_technician. No new INSERT/UPDATE policy is added to
-- work_orders (it still has none beyond SELECT) — this function is the only
-- way to create a work order directly from an internal request.
-- =========================================================================
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

  -- Avoid duplicates: an internal work order (quote_id IS NULL) already
  -- linked to this request is returned as-is instead of creating a second
  -- one. External work orders (quote_id set) for the same request, if any,
  -- are a separate concern and untouched.
  SELECT * INTO existing_work_order
    FROM public.work_orders
    WHERE request_id = target_request_id AND quote_id IS NULL;

  IF existing_work_order.id IS NOT NULL THEN
    RETURN existing_work_order;
  END IF;

  -- Internal work has no external provider: the requesting organization is
  -- both client and executor. Setting provider_organization_id =
  -- organization_id (rather than leaving it null, which the column doesn't
  -- allow) keeps the existing work_orders SELECT policy
  -- (is_organization_member(client_organization_id) OR
  -- is_organization_member(provider_organization_id)) correct with zero RLS
  -- changes, and lets the existing trg_work_orders_check_assigned_technician
  -- trigger validate target_assigned_member_id against this same
  -- organization's own technicians for free.
  INSERT INTO public.work_orders (
    request_id,
    quote_id,
    client_organization_id,
    provider_organization_id,
    status,
    title,
    description,
    assigned_member_id,
    created_by_user_id
  ) VALUES (
    target_request_id,
    NULL,
    source_request.organization_id,
    source_request.organization_id,
    'created',
    source_request.title,
    source_request.description,
    target_assigned_member_id,
    auth.uid()
  )
  RETURNING * INTO created_work_order;

  RETURN created_work_order;
END;
$$;

REVOKE ALL ON FUNCTION public.create_internal_work_order_from_request(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_internal_work_order_from_request(uuid, uuid) TO authenticated;
