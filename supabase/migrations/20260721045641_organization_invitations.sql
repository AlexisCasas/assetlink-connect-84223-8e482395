DO $$ BEGIN
  CREATE TYPE public.organization_invitation_status AS ENUM (
    'pending', 'accepted', 'revoked', 'expired'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.organization_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  email text NOT NULL CHECK (email = lower(email)),
  role public.organization_member_role NOT NULL,
  status public.organization_invitation_status NOT NULL DEFAULT 'pending',
  invited_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  accepted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  token_hash text,
  expires_at timestamptz,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (status <> 'accepted' OR (accepted_by IS NOT NULL AND accepted_at IS NOT NULL))
    AND (status <> 'revoked' OR revoked_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_organization_invitations_pending_unique
  ON public.organization_invitations (organization_id, lower(email))
  WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_organization_invitations_organization_status
  ON public.organization_invitations (organization_id, status, created_at DESC);

ALTER TABLE public.organization_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "organization administrators can view invitations" ON public.organization_invitations;
CREATE POLICY "organization administrators can view invitations" ON public.organization_invitations
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(organization_id, ARRAY['owner', 'admin']::public.organization_member_role[]))
  );

DROP TRIGGER IF EXISTS trg_organization_invitations_updated_at ON public.organization_invitations;
CREATE TRIGGER trg_organization_invitations_updated_at
  BEFORE UPDATE ON public.organization_invitations
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
