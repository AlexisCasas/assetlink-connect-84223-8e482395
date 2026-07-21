-- Request details inherit tenant access from the parent request.
ALTER TABLE public.request_details
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_request_details_request_id
  ON public.request_details (request_id);

DROP TRIGGER IF EXISTS trg_request_details_updated_at ON public.request_details;
CREATE TRIGGER trg_request_details_updated_at
  BEFORE UPDATE ON public.request_details
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.request_details ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'request_details'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.request_details', policy_record.policyname);
  END LOOP;
END $$;

CREATE POLICY "organization members can view request details" ON public.request_details
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = request_details.request_id
        AND request.organization_id IS NOT NULL
        AND (SELECT public.is_organization_member(request.organization_id))
    )
  );

CREATE POLICY "request members can create request details" ON public.request_details
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = request_details.request_id
        AND request.organization_id IS NOT NULL
        AND (SELECT public.has_organization_role(
          request.organization_id,
          ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
        ))
    )
  );

CREATE POLICY "request members can update request details" ON public.request_details
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = request_details.request_id
        AND request.organization_id IS NOT NULL
        AND (SELECT public.has_organization_role(
          request.organization_id,
          ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
        ))
    )
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = request_details.request_id
        AND request.organization_id IS NOT NULL
        AND (SELECT public.has_organization_role(
          request.organization_id,
          ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
        ))
    )
  );

CREATE POLICY "request members can delete request details" ON public.request_details
  FOR DELETE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = request_details.request_id
        AND request.organization_id IS NOT NULL
        AND (SELECT public.has_organization_role(
          request.organization_id,
          ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
        ))
    )
  );
