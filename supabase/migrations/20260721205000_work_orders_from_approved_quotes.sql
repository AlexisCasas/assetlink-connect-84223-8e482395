-- Productive work orders are deliberately separate from the legacy
-- assignments table, whose ownership model is not tenant-aware.
CREATE TABLE public.work_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  quote_id uuid NOT NULL UNIQUE REFERENCES public.quotes(id) ON DELETE RESTRICT,
  client_organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  provider_organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'created',
  title text,
  description text,
  total_amount numeric,
  created_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz
);

CREATE INDEX idx_work_orders_request_id ON public.work_orders (request_id);
CREATE INDEX idx_work_orders_client_organization_id ON public.work_orders (client_organization_id);
CREATE INDEX idx_work_orders_provider_organization_id ON public.work_orders (provider_organization_id);
CREATE INDEX idx_work_orders_client_organization_status
  ON public.work_orders (client_organization_id, status);
CREATE INDEX idx_work_orders_provider_organization_status
  ON public.work_orders (provider_organization_id, status);

ALTER TABLE public.work_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant members can read work orders"
  ON public.work_orders
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(client_organization_id))
    OR (SELECT public.is_organization_member(provider_organization_id))
  );

-- Creation is available only through create_work_order_from_quote. Operational
-- status updates and deletion are intentionally deferred to later features.

CREATE TRIGGER trg_work_orders_updated_at
  BEFORE UPDATE ON public.work_orders
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE OR REPLACE FUNCTION public.create_work_order_from_quote(target_quote_id uuid)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  source_quote public.quotes%ROWTYPE;
  source_request public.requests%ROWTYPE;
  created_work_order public.work_orders%ROWTYPE;
  can_create boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT quote.* INTO source_quote
  FROM public.quotes quote
  WHERE quote.id = target_quote_id
  FOR UPDATE;

  IF source_quote.id IS NULL THEN
    RAISE EXCEPTION 'Quote not found';
  END IF;

  IF source_quote.status <> 'approved' THEN
    RAISE EXCEPTION 'A work order can only be created from an approved quote';
  END IF;

  IF source_quote.provider_organization_id IS NULL THEN
    RAISE EXCEPTION 'Approved quote has no provider organization';
  END IF;

  SELECT request.* INTO source_request
  FROM public.requests request
  WHERE request.id = source_quote.request_id;

  IF source_request.id IS NULL OR source_request.organization_id IS NULL THEN
    RAISE EXCEPTION 'Quote request has no client organization';
  END IF;

  can_create := public.is_platform_admin()
    OR public.has_organization_role(
      source_request.organization_id,
      ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
    );

  IF NOT can_create THEN
    RAISE EXCEPTION 'Not authorized to create a work order for this quote';
  END IF;

  INSERT INTO public.work_orders (
    request_id,
    quote_id,
    client_organization_id,
    provider_organization_id,
    title,
    description,
    total_amount,
    created_by_user_id
  ) VALUES (
    source_quote.request_id,
    source_quote.id,
    source_request.organization_id,
    source_quote.provider_organization_id,
    source_request.title,
    source_quote.description,
    source_quote.total_amount,
    auth.uid()
  )
  ON CONFLICT (quote_id) DO NOTHING
  RETURNING * INTO created_work_order;

  IF created_work_order.id IS NULL THEN
    SELECT work_order.* INTO created_work_order
    FROM public.work_orders work_order
    WHERE work_order.quote_id = source_quote.id;

    RETURN created_work_order;
  END IF;

  PERFORM public.create_organization_notification(
    source_quote.provider_organization_id,
    auth.uid(),
    'work_order_created',
    'Nueva orden de trabajo',
    'Se creo una orden de trabajo a partir de una cotizacion aprobada.',
    'work_order',
    created_work_order.id,
    source_quote.request_id,
    source_quote.id
  );

  RETURN created_work_order;
END;
$$;

REVOKE ALL ON FUNCTION public.create_work_order_from_quote(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_work_order_from_quote(uuid) TO authenticated;
