-- Tenant-aware provider/facility-manager visibility. The legacy
-- request_providers table is keyed by providers.id and is not used for auth.
CREATE TABLE IF NOT EXISTS public.request_provider_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  provider_organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  access_type text NOT NULL DEFAULT 'invited'
    CHECK (access_type IN ('invited', 'marketplace', 'relationship')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'revoked')),
  invited_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, provider_organization_id)
);

CREATE INDEX IF NOT EXISTS idx_request_provider_access_request_id
  ON public.request_provider_access (request_id);
CREATE INDEX IF NOT EXISTS idx_request_provider_access_provider_status
  ON public.request_provider_access (provider_organization_id, status);

DROP TRIGGER IF EXISTS trg_request_provider_access_updated_at ON public.request_provider_access;
CREATE TRIGGER trg_request_provider_access_updated_at
  BEFORE UPDATE ON public.request_provider_access
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- These helpers are SECURITY DEFINER solely to avoid recursive RLS between
-- requests and request_provider_access. They evaluate auth.uid() and use a
-- fixed search_path; direct execution is limited to authenticated users.
CREATE OR REPLACE FUNCTION public.is_provider_facing_organization(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organizations organization
    WHERE organization.id = _organization_id
      AND organization.organization_type IN ('provider_company', 'facility_manager')
      AND organization.status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.can_user_manage_request_access(_request_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = _request_id
        AND request.organization_id IS NOT NULL
        AND public.has_organization_role(
          request.organization_id,
          ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
        )
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_user_read_request(_request_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = _request_id
        AND request.organization_id IS NOT NULL
        AND public.is_organization_member(request.organization_id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      INNER JOIN public.organization_members membership
        ON membership.user_id = auth.uid()
        AND membership.is_active
      INNER JOIN public.organizations provider_organization
        ON provider_organization.id = membership.organization_id
        AND provider_organization.organization_type IN ('provider_company', 'facility_manager')
        AND provider_organization.status = 'active'
      LEFT JOIN public.request_provider_access access
        ON access.request_id = request.id
        AND access.provider_organization_id = membership.organization_id
        AND access.status = 'active'
      WHERE request.id = _request_id
        AND request.status <> 'draft'
        AND (request.is_public IS TRUE OR access.id IS NOT NULL)
    )
  );
$$;

REVOKE ALL ON FUNCTION public.is_provider_facing_organization(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_user_manage_request_access(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_user_read_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_provider_facing_organization(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_manage_request_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_read_request(uuid) TO authenticated;

ALTER TABLE public.request_provider_access ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'request_provider_access'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.request_provider_access', policy_record.policyname);
  END LOOP;
END $$;

CREATE POLICY "authorized users can view request provider access" ON public.request_provider_access
  FOR SELECT TO authenticated
  USING (
    (SELECT public.can_user_manage_request_access(request_id))
    OR (
      (SELECT public.is_provider_facing_organization(provider_organization_id))
      AND (SELECT public.is_organization_member(provider_organization_id))
    )
  );

CREATE POLICY "request owners can create request provider access" ON public.request_provider_access
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.can_user_manage_request_access(request_id))
    AND (SELECT public.is_provider_facing_organization(provider_organization_id))
  );

CREATE POLICY "request owners can update request provider access" ON public.request_provider_access
  FOR UPDATE TO authenticated
  USING ((SELECT public.can_user_manage_request_access(request_id)))
  WITH CHECK (
    (SELECT public.can_user_manage_request_access(request_id))
    AND (SELECT public.is_provider_facing_organization(provider_organization_id))
  );

CREATE POLICY "request owners can delete request provider access" ON public.request_provider_access
  FOR DELETE TO authenticated
  USING ((SELECT public.can_user_manage_request_access(request_id)));

-- Extend request read access only. Client-side writes remain governed by the
-- existing owner-role policies.
DROP POLICY IF EXISTS "organization members can view requests" ON public.requests;
CREATE POLICY "authorized users can view requests" ON public.requests
  FOR SELECT TO authenticated
  USING ((SELECT public.can_user_read_request(id)));

DROP POLICY IF EXISTS "organization members can view request details" ON public.request_details;
CREATE POLICY "authorized users can view request details" ON public.request_details
  FOR SELECT TO authenticated
  USING ((SELECT public.can_user_read_request(request_id)));

DROP POLICY IF EXISTS "organization members can view request detail attachments" ON storage.objects;
CREATE POLICY "authorized users can view request detail attachments" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'request-detail-attachments'
    AND (SELECT public.can_user_read_request(public.storage_request_id_from_name(name)))
  );
