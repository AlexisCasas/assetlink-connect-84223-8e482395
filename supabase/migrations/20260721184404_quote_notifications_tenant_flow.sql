-- Internal, tenant-scoped notifications. This is intentionally separate from
-- the legacy email-based notifications table.
CREATE TABLE public.organization_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  type text NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  entity_type text,
  entity_id uuid,
  related_request_id uuid REFERENCES public.requests(id) ON DELETE SET NULL,
  related_quote_id uuid REFERENCES public.quotes(id) ON DELETE SET NULL,
  is_read boolean NOT NULL DEFAULT false,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_organization_notifications_organization_created_at
  ON public.organization_notifications (organization_id, created_at DESC);
CREATE INDEX idx_organization_notifications_organization_unread
  ON public.organization_notifications (organization_id, is_read);
CREATE INDEX idx_organization_notifications_request
  ON public.organization_notifications (related_request_id, type);
CREATE INDEX idx_organization_notifications_quote
  ON public.organization_notifications (related_quote_id, type);

-- A quote state transition must only create one notification for its target
-- organization, even if an application retries a transaction.
CREATE UNIQUE INDEX idx_organization_notifications_quote_type_unique
  ON public.organization_notifications (organization_id, related_quote_id, type)
  WHERE related_quote_id IS NOT NULL;

ALTER TABLE public.organization_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organization members can read organization notifications"
  ON public.organization_notifications
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization members can mark organization notifications read"
  ON public.organization_notifications
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

-- RLS allows members to reach their organization rows; this guard limits their
-- update to the read state and prevents changing the notification payload.
CREATE OR REPLACE FUNCTION public.protect_organization_notification_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF public.is_platform_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.actor_user_id IS DISTINCT FROM OLD.actor_user_id
    OR NEW.type IS DISTINCT FROM OLD.type
    OR NEW.title IS DISTINCT FROM OLD.title
    OR NEW.message IS DISTINCT FROM OLD.message
    OR NEW.entity_type IS DISTINCT FROM OLD.entity_type
    OR NEW.entity_id IS DISTINCT FROM OLD.entity_id
    OR NEW.related_request_id IS DISTINCT FROM OLD.related_request_id
    OR NEW.related_quote_id IS DISTINCT FROM OLD.related_quote_id
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
    OR NEW.is_read IS NOT TRUE THEN
    RAISE EXCEPTION 'Organization notifications can only be marked as read';
  END IF;

  IF OLD.is_read IS FALSE AND NEW.read_at IS NULL THEN
    NEW.read_at := now();
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER protect_organization_notification_update
  BEFORE UPDATE ON public.organization_notifications
  FOR EACH ROW EXECUTE FUNCTION public.protect_organization_notification_update();

-- This helper is not callable by application roles. Quote triggers below use
-- it so notification creation stays server-side and independent from the UI.
CREATE OR REPLACE FUNCTION public.create_organization_notification(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_type text,
  target_title text,
  target_message text,
  target_entity_type text,
  target_entity_id uuid,
  target_request_id uuid,
  target_quote_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  notification_id uuid;
BEGIN
  INSERT INTO public.organization_notifications (
    organization_id,
    actor_user_id,
    type,
    title,
    message,
    entity_type,
    entity_id,
    related_request_id,
    related_quote_id
  ) VALUES (
    target_organization_id,
    target_actor_user_id,
    target_type,
    target_title,
    target_message,
    target_entity_type,
    target_entity_id,
    target_request_id,
    target_quote_id
  )
  ON CONFLICT (organization_id, related_quote_id, type)
    WHERE related_quote_id IS NOT NULL DO NOTHING
  RETURNING id INTO notification_id;

  RETURN notification_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_organization_notification(uuid, uuid, text, text, text, text, uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_organization_notification(uuid, uuid, text, text, text, text, uuid, uuid, uuid) FROM authenticated;

CREATE OR REPLACE FUNCTION public.notify_quote_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_organization_id uuid;
  notification_actor_id uuid;
  notification_type text;
  notification_title text;
  notification_message text;
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'submitted' THEN
    SELECT organization_id INTO target_organization_id
    FROM public.requests
    WHERE id = NEW.request_id;

    notification_actor_id := NEW.created_by_user_id;
    notification_type := 'quote_submitted';
    notification_title := 'Nueva cotizacion recibida';
    notification_message := 'Se recibio una nueva cotizacion para tu solicitud.';
  ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'submitted' THEN
    SELECT organization_id INTO target_organization_id
    FROM public.requests
    WHERE id = NEW.request_id;

    notification_actor_id := NEW.created_by_user_id;
    notification_type := 'quote_submitted';
    notification_title := 'Nueva cotizacion recibida';
    notification_message := 'Se recibio una nueva cotizacion para tu solicitud.';
  ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'approved' THEN
    target_organization_id := NEW.provider_organization_id;
    notification_actor_id := NEW.approved_by_user_id;
    notification_type := 'quote_approved';
    notification_title := 'Cotizacion aprobada';
    notification_message := 'Tu cotizacion fue aprobada por el cliente.';
  ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'rejected' THEN
    target_organization_id := NEW.provider_organization_id;
    notification_actor_id := NEW.rejected_by_user_id;
    notification_type := 'quote_rejected';
    notification_title := 'Cotizacion no seleccionada';
    notification_message := 'Tu cotizacion no fue seleccionada para esta solicitud.';
  ELSE
    RETURN NEW;
  END IF;

  IF target_organization_id IS NOT NULL THEN
    PERFORM public.create_organization_notification(
      target_organization_id,
      notification_actor_id,
      notification_type,
      notification_title,
      notification_message,
      'quote',
      NEW.id,
      NEW.request_id,
      NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER notify_quote_status_change
  AFTER INSERT OR UPDATE OF status ON public.quotes
  FOR EACH ROW EXECUTE FUNCTION public.notify_quote_status_change();

REVOKE ALL ON FUNCTION public.notify_quote_status_change() FROM PUBLIC;
