-- Tenant-aware requests. Legacy requests without an organization remain
-- inaccessible to ordinary members until they are assigned during backfill.
ALTER TABLE IF EXISTS public.requests
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_by_user_id uuid,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_requests_organization_id
  ON public.requests (organization_id);
CREATE INDEX IF NOT EXISTS idx_requests_organization_status_created_at
  ON public.requests (organization_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_requests_created_by_user_id
  ON public.requests (created_by_user_id);

DROP TRIGGER IF EXISTS trg_requests_updated_at ON public.requests;
CREATE TRIGGER trg_requests_updated_at
  BEFORE UPDATE ON public.requests
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;

-- Replace only policies attached to requests. Earlier mockup policies granted
-- broad authenticated access and must not be retained alongside tenant RLS.
DO $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'requests'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.requests', policy_record.policyname);
  END LOOP;
END $$;

CREATE POLICY "organization members can view requests" ON public.requests
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (
      organization_id IS NOT NULL
      AND (SELECT public.is_organization_member(organization_id))
    )
  );

CREATE POLICY "request creators can create organization requests" ON public.requests
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by_user_id = (SELECT auth.uid())
    AND (
      (SELECT public.is_platform_admin())
      OR (
        organization_id IS NOT NULL
        AND (SELECT public.has_organization_role(
          organization_id,
          ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
        ))
      )
    )
  );

CREATE POLICY "request managers can update organization requests" ON public.requests
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (
      organization_id IS NOT NULL
      AND (SELECT public.has_organization_role(
        organization_id,
        ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
      ))
    )
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (
      organization_id IS NOT NULL
      AND (SELECT public.has_organization_role(
        organization_id,
        ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
      ))
    )
  );

CREATE POLICY "request administrators can delete organization requests" ON public.requests
  FOR DELETE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (
      organization_id IS NOT NULL
      AND (SELECT public.has_organization_role(
        organization_id,
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
      ))
    )
  );
