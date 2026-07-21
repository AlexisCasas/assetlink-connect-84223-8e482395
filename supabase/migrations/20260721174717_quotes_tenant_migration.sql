-- Tenant-aware quotes. Legacy provider_id and team_member_id are retained for
-- display/backfill compatibility only; new quotes are owned by an organization.
ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS provider_organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.quotes
  ALTER COLUMN provider_id DROP NOT NULL,
  ALTER COLUMN team_member_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_quotes_request_id ON public.quotes (request_id);
CREATE INDEX IF NOT EXISTS idx_quotes_provider_organization_id ON public.quotes (provider_organization_id);
CREATE INDEX IF NOT EXISTS idx_quotes_request_provider_organization ON public.quotes (request_id, provider_organization_id);
CREATE INDEX IF NOT EXISTS idx_quotes_provider_organization_status ON public.quotes (provider_organization_id, status);

CREATE OR REPLACE FUNCTION public.can_provider_quote_request(
  target_request_id uuid,
  target_provider_organization_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND public.is_provider_facing_organization(target_provider_organization_id)
    AND public.has_organization_role(
      target_provider_organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    )
    AND EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = target_request_id
        AND request.status <> 'draft'
        AND COALESCE(request.quotes_closed, false) IS FALSE
        AND (
          request.is_public IS TRUE
          OR EXISTS (
            SELECT 1
            FROM public.request_provider_access access
            WHERE access.request_id = request.id
              AND access.provider_organization_id = target_provider_organization_id
              AND access.status = 'active'
          )
        )
    );
$$;

-- SECURITY DEFINER prevents self-recursion while inspecting a quote and its
-- parent request; execution remains restricted to authenticated users.
CREATE OR REPLACE FUNCTION public.can_user_read_quote(target_quote_id uuid)
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
      FROM public.quotes quote
      INNER JOIN public.requests request ON request.id = quote.request_id
      WHERE quote.id = target_quote_id
        AND request.organization_id IS NOT NULL
        AND public.is_organization_member(request.organization_id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.quotes quote
      WHERE quote.id = target_quote_id
        AND quote.provider_organization_id IS NOT NULL
        AND public.is_organization_member(quote.provider_organization_id)
    )
  );
$$;

REVOKE ALL ON FUNCTION public.can_provider_quote_request(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_user_read_quote(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_provider_quote_request(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_read_quote(uuid) TO authenticated;

ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;

-- Replace every legacy/open policy attached only to quotes.
DO $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'quotes'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.quotes', policy_record.policyname);
  END LOOP;
END $$;

CREATE POLICY "authorized users can view quotes" ON public.quotes
  FOR SELECT TO authenticated
  USING ((SELECT public.can_user_read_quote(id)));

CREATE POLICY "authorized providers can create quotes" ON public.quotes
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (
      provider_organization_id IS NOT NULL
      AND created_by_user_id = (SELECT auth.uid())
      AND (SELECT public.can_provider_quote_request(request_id, provider_organization_id))
    )
  );

CREATE POLICY "authorized providers can update their organization quotes" ON public.quotes
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (
      provider_organization_id IS NOT NULL
      AND (SELECT public.is_organization_member(provider_organization_id))
      AND (SELECT public.has_organization_role(
        provider_organization_id,
        ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
      ))
    )
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (
      provider_organization_id IS NOT NULL
      AND (SELECT public.can_provider_quote_request(request_id, provider_organization_id))
    )
  );

CREATE POLICY "authorized providers can delete their organization quotes" ON public.quotes
  FOR DELETE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (
      provider_organization_id IS NOT NULL
      AND (SELECT public.can_provider_quote_request(request_id, provider_organization_id))
    )
  );
