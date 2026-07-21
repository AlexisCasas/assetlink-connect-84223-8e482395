-- Tenant-aware client branches. client_email remains as a temporary legacy field.
ALTER TABLE IF EXISTS public.client_branches
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;
ALTER TABLE public.client_branches
  ALTER COLUMN client_email DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_client_branches_organization_id
  ON public.client_branches (organization_id);
CREATE INDEX IF NOT EXISTS idx_client_branches_organization_active
  ON public.client_branches (organization_id, is_active);

ALTER TABLE public.client_branches ENABLE ROW LEVEL SECURITY;

-- Remove only policies attached to client_branches; legacy policies authorize by
-- email or expose all branches to authenticated users.
DO $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'client_branches'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.client_branches', policy_record.policyname);
  END LOOP;
END $$;

CREATE POLICY "organization members can view client branches" ON public.client_branches
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (organization_id IS NOT NULL AND (SELECT public.is_organization_member(organization_id)))
  );

CREATE POLICY "branch managers can create client branches" ON public.client_branches
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (
      organization_id IS NOT NULL
      AND (SELECT public.has_organization_role(
        organization_id,
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
      ))
    )
  );

CREATE POLICY "branch managers can update client branches" ON public.client_branches
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (
      organization_id IS NOT NULL
      AND (SELECT public.has_organization_role(
        organization_id,
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
      ))
    )
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (
      organization_id IS NOT NULL
      AND (SELECT public.has_organization_role(
        organization_id,
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
      ))
    )
  );

CREATE POLICY "branch managers can delete client branches" ON public.client_branches
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
