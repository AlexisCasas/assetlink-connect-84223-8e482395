-- Multi-tenant foundation. Organization provisioning and membership invitations
-- are intentionally performed by a trusted backend / Edge Function, not clients.

DO $$ BEGIN
  CREATE TYPE public.organization_type AS ENUM (
    'client_company', 'provider_company', 'facility_manager',
    'subcontractor_company', 'platform_admin'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.organization_member_role AS ENUM (
    'owner', 'admin', 'manager', 'requester', 'quote_manager',
    'technician', 'operator', 'viewer'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.organization_relationship_type AS ENUM (
    'provider', 'facility_management', 'subcontracting'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.organization_relationship_status AS ENUM (
    'pending', 'active', 'suspended', 'ended'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  legal_name text,
  organization_type public.organization_type NOT NULL,
  tax_id text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.organization_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.organization_member_role NOT NULL DEFAULT 'viewer',
  is_active boolean NOT NULL DEFAULT true,
  invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.organization_relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  target_organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  relationship_type public.organization_relationship_type NOT NULL,
  status public.organization_relationship_status NOT NULL DEFAULT 'pending',
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (source_organization_id <> target_organization_id),
  UNIQUE (source_organization_id, target_organization_id, relationship_type)
);

CREATE TABLE IF NOT EXISTS public.activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  action text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  table_name text NOT NULL,
  record_id uuid,
  action text NOT NULL,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE IF EXISTS public.providers
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE IF EXISTS public.client_branches
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE IF EXISTS public.requests
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE IF EXISTS public.quotes
  ADD COLUMN IF NOT EXISTS provider_organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_organizations_type_status
  ON public.organizations (organization_type, status);
CREATE INDEX IF NOT EXISTS idx_organization_members_user_organization
  ON public.organization_members (user_id, organization_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_organization_relationships_source
  ON public.organization_relationships (source_organization_id, status);
CREATE INDEX IF NOT EXISTS idx_organization_relationships_target
  ON public.organization_relationships (target_organization_id, status);
CREATE INDEX IF NOT EXISTS idx_activity_logs_organization_created_at
  ON public.activity_logs (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_organization_created_at
  ON public.audit_logs (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_providers_organization_id
  ON public.providers (organization_id);
CREATE INDEX IF NOT EXISTS idx_client_branches_organization_id
  ON public.client_branches (organization_id);
CREATE INDEX IF NOT EXISTS idx_requests_organization_status_created_at
  ON public.requests (organization_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_quotes_provider_organization_id
  ON public.quotes (provider_organization_id);

CREATE OR REPLACE FUNCTION public.is_organization_member(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.organization_members membership
    WHERE membership.organization_id = _organization_id
      AND membership.user_id = auth.uid()
      AND membership.is_active
  );
$$;

CREATE OR REPLACE FUNCTION public.has_organization_role(
  _organization_id uuid,
  _roles public.organization_member_role[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.organization_members membership
    WHERE membership.organization_id = _organization_id
      AND membership.user_id = auth.uid()
      AND membership.is_active
      AND membership.role = ANY (_roles)
  );
$$;

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.organization_members membership
    INNER JOIN public.organizations organization ON organization.id = membership.organization_id
    WHERE membership.user_id = auth.uid()
      AND membership.is_active
      AND membership.role IN ('owner', 'admin')
      AND organization.organization_type = 'platform_admin'
      AND organization.status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.get_user_organizations()
RETURNS SETOF public.organizations
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT organization.*
  FROM public.organizations organization
  INNER JOIN public.organization_members membership ON membership.organization_id = organization.id
  WHERE membership.user_id = auth.uid()
    AND membership.is_active
  ORDER BY organization.name;
$$;

REVOKE ALL ON FUNCTION public.is_organization_member(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.has_organization_role(uuid, public.organization_member_role[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_organizations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_organization_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_organization_role(uuid, public.organization_member_role[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_organizations() TO authenticated;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members can view organizations" ON public.organizations;
CREATE POLICY "members can view organizations" ON public.organizations
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(id)) OR (SELECT public.is_platform_admin()));
DROP POLICY IF EXISTS "organization administrators can update organizations" ON public.organizations;
CREATE POLICY "organization administrators can update organizations" ON public.organizations
  FOR UPDATE TO authenticated
  USING ((SELECT public.has_organization_role(id, ARRAY['owner', 'admin']::public.organization_member_role[])))
  WITH CHECK ((SELECT public.has_organization_role(id, ARRAY['owner', 'admin']::public.organization_member_role[])));

DROP POLICY IF EXISTS "members can view organization memberships" ON public.organization_members;
CREATE POLICY "members can view organization memberships" ON public.organization_members
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(organization_id)) OR (SELECT public.is_platform_admin()));
DROP POLICY IF EXISTS "organization administrators can add memberships" ON public.organization_members;
CREATE POLICY "organization administrators can add memberships" ON public.organization_members
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_organization_role(organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])));
DROP POLICY IF EXISTS "organization administrators can update memberships" ON public.organization_members;
CREATE POLICY "organization administrators can update memberships" ON public.organization_members
  FOR UPDATE TO authenticated
  USING ((SELECT public.has_organization_role(organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])))
  WITH CHECK ((SELECT public.has_organization_role(organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])));
DROP POLICY IF EXISTS "organization administrators can remove memberships" ON public.organization_members;
CREATE POLICY "organization administrators can remove memberships" ON public.organization_members
  FOR DELETE TO authenticated
  USING ((SELECT public.has_organization_role(organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])));

DROP POLICY IF EXISTS "members can view organization relationships" ON public.organization_relationships;
CREATE POLICY "members can view organization relationships" ON public.organization_relationships
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_organization_member(source_organization_id))
    OR (SELECT public.is_organization_member(target_organization_id))
    OR (SELECT public.is_platform_admin())
  );
DROP POLICY IF EXISTS "source organization administrators can create relationships" ON public.organization_relationships;
CREATE POLICY "source organization administrators can create relationships" ON public.organization_relationships
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_organization_role(source_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])));
DROP POLICY IF EXISTS "source organization administrators can update relationships" ON public.organization_relationships;
CREATE POLICY "source organization administrators can update relationships" ON public.organization_relationships
  FOR UPDATE TO authenticated
  USING ((SELECT public.has_organization_role(source_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])))
  WITH CHECK ((SELECT public.has_organization_role(source_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])));
DROP POLICY IF EXISTS "source organization administrators can delete relationships" ON public.organization_relationships;
CREATE POLICY "source organization administrators can delete relationships" ON public.organization_relationships
  FOR DELETE TO authenticated
  USING ((SELECT public.has_organization_role(source_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])));

DROP POLICY IF EXISTS "members can view activity logs" ON public.activity_logs;
CREATE POLICY "members can view activity logs" ON public.activity_logs
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(organization_id)) OR (SELECT public.is_platform_admin()));
DROP POLICY IF EXISTS "members can write their own activity logs" ON public.activity_logs;
CREATE POLICY "members can write their own activity logs" ON public.activity_logs
  FOR INSERT TO authenticated
  WITH CHECK (
    actor_user_id = auth.uid()
    AND (SELECT public.is_organization_member(organization_id))
  );

DROP POLICY IF EXISTS "administrators can view audit logs" ON public.audit_logs;
CREATE POLICY "administrators can view audit logs" ON public.audit_logs
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (organization_id IS NOT NULL AND (SELECT public.has_organization_role(organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])))
  );

DROP TRIGGER IF EXISTS trg_organizations_updated_at ON public.organizations;
CREATE TRIGGER trg_organizations_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_organization_members_updated_at ON public.organization_members;
CREATE TRIGGER trg_organization_members_updated_at
  BEFORE UPDATE ON public.organization_members
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_organization_relationships_updated_at ON public.organization_relationships;
CREATE TRIGGER trg_organization_relationships_updated_at
  BEFORE UPDATE ON public.organization_relationships
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
