-- INSERT ... RETURNING evaluates the quotes SELECT policy for the inserted
-- row. Keep that policy row-based so it does not self-read public.quotes via
-- can_user_read_quote while the row is being returned by PostgREST.
DROP POLICY IF EXISTS "authorized users can view quotes" ON public.quotes;

CREATE POLICY "authorized users can view quotes" ON public.quotes
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = quotes.request_id
        AND request.organization_id IS NOT NULL
        AND (SELECT public.is_organization_member(request.organization_id))
    )
    OR (
      quotes.provider_organization_id IS NOT NULL
      AND (SELECT public.is_organization_member(quotes.provider_organization_id))
    )
  );
