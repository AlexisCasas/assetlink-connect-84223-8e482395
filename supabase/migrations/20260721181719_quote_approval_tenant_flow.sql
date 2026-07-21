-- A client decision is represented separately from the provider-owned quote
-- content. Legacy approval_reason is retained and is not repurposed here.
ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejected_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rejection_reason text;

CREATE INDEX IF NOT EXISTS idx_quotes_request_status
  ON public.quotes (request_id, status);
CREATE INDEX IF NOT EXISTS idx_quotes_approved_by_user_id
  ON public.quotes (approved_by_user_id);
CREATE INDEX IF NOT EXISTS idx_quotes_rejected_by_user_id
  ON public.quotes (rejected_by_user_id);

-- These functions intentionally bypass the provider-only UPDATE policy. They
-- perform their own tenant and role checks and never update economic/technical
-- columns, so a client cannot turn a generic table update into a quote edit.
CREATE OR REPLACE FUNCTION public.approve_quote(target_quote_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  quote_request_id uuid;
  client_organization_id uuid;
  request_status public.request_status;
  is_authorized boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT quote.request_id, request.organization_id, request.status
  INTO quote_request_id, client_organization_id, request_status
  FROM public.quotes quote
  INNER JOIN public.requests request ON request.id = quote.request_id
  WHERE quote.id = target_quote_id;

  IF quote_request_id IS NULL THEN
    RAISE EXCEPTION 'Quote not found';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.organizations organization
    WHERE organization.id = client_organization_id
      AND organization.organization_type = 'client_company'
      AND organization.status = 'active'
      AND public.has_organization_role(
        client_organization_id,
        ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
      )
  ) INTO is_authorized;

  IF NOT public.is_platform_admin() AND NOT is_authorized THEN
    RAISE EXCEPTION 'Not authorized to approve this quote';
  END IF;

  IF request_status NOT IN ('sent', 'quoted') THEN
    RAISE EXCEPTION 'Request status does not allow quote approval';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.quotes quote
    WHERE quote.id = target_quote_id AND quote.status = 'submitted'
  ) THEN
    RAISE EXCEPTION 'Only submitted quotes can be approved';
  END IF;

  UPDATE public.quotes
  SET status = 'approved',
      approved_at = now(),
      approved_by_user_id = auth.uid(),
      rejected_at = NULL,
      rejected_by_user_id = NULL,
      rejection_reason = NULL
  WHERE id = target_quote_id;

  -- There can be one selected quote per request. Submitted alternatives are
  -- recorded as rejected without touching their commercial content.
  UPDATE public.quotes
  SET status = 'rejected',
      rejected_at = now(),
      rejected_by_user_id = auth.uid(),
      rejection_reason = COALESCE(rejection_reason, 'Not selected')
  WHERE request_id = quote_request_id
    AND id <> target_quote_id
    AND status = 'submitted';
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_quote(
  target_quote_id uuid,
  reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  client_organization_id uuid;
  request_status public.request_status;
  is_authorized boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT request.organization_id, request.status
  INTO client_organization_id, request_status
  FROM public.quotes quote
  INNER JOIN public.requests request ON request.id = quote.request_id
  WHERE quote.id = target_quote_id;

  IF client_organization_id IS NULL THEN
    RAISE EXCEPTION 'Quote not found';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.organizations organization
    WHERE organization.id = client_organization_id
      AND organization.organization_type = 'client_company'
      AND organization.status = 'active'
      AND public.has_organization_role(
        client_organization_id,
        ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
      )
  ) INTO is_authorized;

  IF NOT public.is_platform_admin() AND NOT is_authorized THEN
    RAISE EXCEPTION 'Not authorized to reject this quote';
  END IF;

  IF request_status NOT IN ('sent', 'quoted') THEN
    RAISE EXCEPTION 'Request status does not allow quote rejection';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.quotes quote
    WHERE quote.id = target_quote_id AND quote.status = 'submitted'
  ) THEN
    RAISE EXCEPTION 'Only submitted quotes can be rejected';
  END IF;

  UPDATE public.quotes
  SET status = 'rejected',
      rejected_at = now(),
      rejected_by_user_id = auth.uid(),
      rejection_reason = NULLIF(btrim(reason), '')
  WHERE id = target_quote_id;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_quote(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_quote(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_quote(uuid, text) TO authenticated;
