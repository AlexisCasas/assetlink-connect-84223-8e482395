-- =========================================================================
-- Fase 1 · Punto 6B — Invitación productiva de usuarios.
--
-- Construido sobre 20260926203242_organization_access_hardening.sql: las
-- cinco tablas de organización ya no aceptan escritura directa desde
-- PostgREST. Toda transición de estado de aquí en adelante pasa por las
-- RPC SECURITY DEFINER de este archivo (create/resend/revoke/accept) o por
-- las Edge Functions admin-* (que ahora delegan en update_organization_member
-- usando el JWT del caller, no service_role, para no saltarse esta
-- autorización).
--
-- token_hash se mantiene como columna legacy/reservada: NO se usa en este
-- MVP. La seguridad de accept_organization_invitation no depende de la
-- posesión del enlace (el uuid de la invitación no es secreto) sino de una
-- sesión autenticada de Supabase Auth cuyo email coincide, confirmado. Ver
-- docs/USER_INVITATIONS.md.
--
-- Bloques:
--   A) organization_invitations: columnas nuevas + expires_at NOT NULL.
--   B) can_manage_organization_role — jerarquía de roles centralizada.
--   C) create_organization_invitation / resend_organization_invitation /
--      mark_invitation_sent (solo service_role) / revoke_organization_invitation.
--   D) accept_organization_invitation — operación crítica, transaccional.
--   E) get_my_organization_invitation / get_my_pending_invitations.
--   F) list_organization_access — lectura combinada miembros+invitaciones.
--   G) update_organization_member — sustituye la lógica inline de la Edge
--      Function admin-update-organization-member.
--   H) get_auth_user_state_by_email — solo service_role, sin listUsers.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A) organization_invitations: columnas nuevas + expires_at NOT NULL
-- -------------------------------------------------------------------------
ALTER TABLE public.organization_invitations
  ADD COLUMN IF NOT EXISTS invited_name text NULL,
  ADD COLUMN IF NOT EXISTS last_sent_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS last_send_attempt_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS send_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS revoked_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL;

-- Backfill: el remoto tiene 0 filas hoy (confirmado en el diagnóstico), pero
-- esto es correcto igual si alguna vez hay filas con expires_at NULL.
UPDATE public.organization_invitations SET expires_at = created_at + interval '7 days' WHERE expires_at IS NULL;
ALTER TABLE public.organization_invitations ALTER COLUMN expires_at SET DEFAULT (now() + interval '7 days');
ALTER TABLE public.organization_invitations ALTER COLUMN expires_at SET NOT NULL;

COMMENT ON COLUMN public.organization_invitations.token_hash IS
  'Reservado/no usado en este MVP. accept_organization_invitation no depende de un token propio: exige sesión autenticada de Supabase Auth con email confirmado coincidente con el de la invitación. Ver docs/USER_INVITATIONS.md.';

-- -------------------------------------------------------------------------
-- B) Jerarquía de roles centralizada — nunca confiar en el frontend.
--    platform admin: cualquier rol (en una organización no platform_admin,
--    verificado por cada RPC llamante). owner: cualquier rol. admin:
--    cualquier rol excepto 'owner'. manager e inferiores: nada.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_manage_organization_role(
  p_organization_id uuid,
  p_role public.organization_member_role
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role public.organization_member_role;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  IF public.is_platform_admin() THEN RETURN true; END IF;

  SELECT role INTO v_caller_role
  FROM public.organization_members
  WHERE organization_id = p_organization_id AND user_id = auth.uid() AND is_active = true;

  IF v_caller_role = 'owner' THEN RETURN true; END IF;
  IF v_caller_role = 'admin' THEN RETURN p_role <> 'owner'; END IF;
  RETURN false;
END;
$$;

-- Si el correo invitado ya tiene una membership en la organización (sólo
-- puede estar inactiva: create_organization_invitation rechaza antes a un
-- miembro activo), aceptar la invitación la reactiva con otro rol. El
-- caller debe poder gestionar su rol actual. Sin membership previa → true.
CREATE OR REPLACE FUNCTION public.can_manage_invitation_target(
  p_organization_id uuid,
  p_email text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_role public.organization_member_role;
BEGIN
  SELECT om.role INTO v_existing_role
  FROM public.organization_members om
  JOIN auth.users u ON u.id = om.user_id
  WHERE om.organization_id = p_organization_id AND lower(u.email) = lower(trim(p_email))
  LIMIT 1;

  IF v_existing_role IS NULL THEN RETURN true; END IF;
  RETURN public.can_manage_organization_role(p_organization_id, v_existing_role);
END;
$$;

-- -------------------------------------------------------------------------
-- C) create_organization_invitation
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_organization_invitation(
  p_organization_id uuid,
  p_email text,
  p_role public.organization_member_role,
  p_invited_name text DEFAULT NULL
)
RETURNS public.organization_invitations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org public.organizations%ROWTYPE;
  v_email text;
  v_name text;
  v_existing public.organization_invitations%ROWTYPE;
  v_active_member_id uuid;
  v_invitation public.organization_invitations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;

  v_email := lower(trim(p_email));
  IF v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' THEN
    RAISE EXCEPTION 'El correo del invitado no es válido';
  END IF;
  v_name := NULLIF(trim(COALESCE(p_invited_name, '')), '');

  SELECT * INTO v_org FROM public.organizations WHERE id = p_organization_id;
  IF v_org.id IS NULL THEN RAISE EXCEPTION 'La organización no existe'; END IF;
  IF v_org.organization_type = 'platform_admin' THEN
    RAISE EXCEPTION 'Esta organización no admite invitaciones por este flujo';
  END IF;
  IF v_org.status <> 'active' THEN RAISE EXCEPTION 'La organización no está activa'; END IF;

  IF NOT public.can_manage_organization_role(p_organization_id, p_role) THEN
    RAISE EXCEPTION 'No autorizado para invitar con el rol solicitado';
  END IF;

  -- ¿Ya es miembro activo con ese correo? (join necesario porque la
  -- membresía se identifica por user_id, no por email).
  SELECT om.id INTO v_active_member_id
  FROM public.organization_members om
  JOIN auth.users u ON u.id = om.user_id
  WHERE om.organization_id = p_organization_id AND om.is_active AND lower(u.email) = v_email
  LIMIT 1;
  IF v_active_member_id IS NOT NULL THEN
    RAISE EXCEPTION 'Este correo ya pertenece a un miembro activo de la organización';
  END IF;

  -- Una membership INACTIVA existente se reactivará con el rol de esta
  -- invitación al aceptarla: invitar equivale a modificar esa membership.
  -- El caller debe poder gestionar también su rol ACTUAL — misma regla que
  -- update_organization_member (un admin nunca reescribe una membership
  -- owner, ni siquiera desactivada, vía invitación).
  IF NOT public.can_manage_invitation_target(p_organization_id, v_email) THEN
    RAISE EXCEPTION 'No autorizado para invitar a este usuario: su membresía existente tiene un rol que no puedes gestionar';
  END IF;

  -- Normalización oportunista: una invitación "pending" vencida no bloquea
  -- una nueva (el índice único parcial solo cubre pending efectivamente
  -- vigente desde la perspectiva de esta función).
  SELECT * INTO v_existing
  FROM public.organization_invitations
  WHERE organization_id = p_organization_id AND lower(email) = v_email AND status = 'pending'
  FOR UPDATE;

  IF v_existing.id IS NOT NULL THEN
    IF v_existing.expires_at > now() THEN
      RAISE EXCEPTION 'Ya existe una invitación pendiente para este correo';
    ELSE
      UPDATE public.organization_invitations SET status = 'expired' WHERE id = v_existing.id;
    END IF;
  END IF;

  INSERT INTO public.organization_invitations (
    organization_id, email, role, invited_name, invited_by, status, expires_at, last_send_attempt_at
  ) VALUES (
    -- last_send_attempt_at reserva el primer envío en la misma transacción
    -- de creación: un resend que llegue antes de que termine este envío ya
    -- ve el cooldown. send_count/last_sent_at siguen en 0/NULL hasta que
    -- mark_invitation_sent confirme el envío real.
    p_organization_id, v_email, p_role, v_name, auth.uid(), 'pending', now() + interval '7 days', now()
  ) RETURNING * INTO v_invitation;

  INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, entity_id, action, metadata)
  VALUES (p_organization_id, auth.uid(), 'organization_invitation', v_invitation.id, 'organization_invitation.created',
    jsonb_build_object('email', v_email, 'role', p_role));

  RETURN v_invitation;
END;
$$;

-- -------------------------------------------------------------------------
-- resend_organization_invitation — reutiliza la misma fila (ver diagnóstico:
-- el uuid no es secreto, así que revocar+recrear no aporta seguridad y
-- rompería el id estable que usa la UI). Reserva el intento
-- (last_send_attempt_at) pero no toca send_count/last_sent_at: eso solo lo
-- hace mark_invitation_sent, tras un envío confirmado.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resend_organization_invitation(p_invitation_id uuid)
RETURNS public.organization_invitations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invitation public.organization_invitations%ROWTYPE;
  v_org public.organizations%ROWTYPE;
  v_effective text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;

  SELECT * INTO v_invitation FROM public.organization_invitations WHERE id = p_invitation_id FOR UPDATE;
  IF v_invitation.id IS NULL THEN RAISE EXCEPTION 'La invitación no existe'; END IF;

  SELECT * INTO v_org FROM public.organizations WHERE id = v_invitation.organization_id;
  IF v_org.id IS NULL OR v_org.status <> 'active' THEN
    RAISE EXCEPTION 'La organización no está activa';
  END IF;

  IF NOT public.can_manage_organization_role(v_invitation.organization_id, v_invitation.role)
     OR NOT public.can_manage_invitation_target(v_invitation.organization_id, v_invitation.email) THEN
    RAISE EXCEPTION 'No autorizado para reenviar esta invitación';
  END IF;

  v_effective := CASE WHEN v_invitation.status = 'pending' AND v_invitation.expires_at <= now()
    THEN 'expired' ELSE v_invitation.status::text END;
  IF v_effective NOT IN ('pending', 'expired') THEN
    RAISE EXCEPTION 'Solo se pueden reenviar invitaciones pendientes o vencidas';
  END IF;

  -- Cooldown evaluado DENTRO del lock (SELECT ... FOR UPDATE arriba) contra
  -- el intento más reciente, no solo contra el último envío confirmado:
  -- last_sent_at se fija fuera de esta transacción (mark_invitation_sent,
  -- tras el correo), así que por sí solo no protegía de dos reenvíos
  -- concurrentes (ambos pasaban el chequeo y ambos enviaban). Ahora el
  -- segundo request espera el lock, relee la fila ya actualizada (READ
  -- COMMITTED re-evalúa la fila bloqueada) y ve el intento recién
  -- reservado. GREATEST ignora NULLs. Un fallo de envío NO libera el
  -- cooldown (last_send_attempt_at nunca vuelve a NULL): evita retry storms.
  IF GREATEST(v_invitation.last_send_attempt_at, v_invitation.last_sent_at) > now() - interval '1 minute' THEN
    RAISE EXCEPTION 'Espera un minuto antes de volver a reenviar esta invitación';
  END IF;

  UPDATE public.organization_invitations
  SET status = 'pending', expires_at = now() + interval '7 days', last_send_attempt_at = now()
  WHERE id = v_invitation.id
  RETURNING * INTO v_invitation;

  RETURN v_invitation;
END;
$$;

-- -------------------------------------------------------------------------
-- mark_invitation_sent — SOLO service_role. Se llama tras confirmar que
-- Supabase Auth aceptó enviar el correo (inviteUserByEmail/signInWithOtp
-- sin error). Si el envío falla, esta función nunca se invoca: send_count
-- y last_sent_at no avanzan, y la fila queda intacta para reintentar.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_invitation_sent(p_invitation_id uuid)
RETURNS public.organization_invitations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invitation public.organization_invitations%ROWTYPE;
  v_action text;
BEGIN
  SELECT * INTO v_invitation FROM public.organization_invitations WHERE id = p_invitation_id FOR UPDATE;
  IF v_invitation.id IS NULL THEN RAISE EXCEPTION 'La invitación no existe'; END IF;

  v_action := CASE WHEN v_invitation.send_count = 0 THEN 'organization_invitation.sent' ELSE 'organization_invitation.resent' END;

  UPDATE public.organization_invitations
  SET last_sent_at = now(), send_count = send_count + 1
  WHERE id = v_invitation.id
  RETURNING * INTO v_invitation;

  INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, entity_id, action, metadata)
  VALUES (v_invitation.organization_id, v_invitation.invited_by, 'organization_invitation', v_invitation.id, v_action,
    jsonb_build_object('email', v_invitation.email, 'send_count', v_invitation.send_count));

  RETURN v_invitation;
END;
$$;

-- -------------------------------------------------------------------------
-- revoke_organization_invitation
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revoke_organization_invitation(p_invitation_id uuid)
RETURNS public.organization_invitations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invitation public.organization_invitations%ROWTYPE;
  v_effective text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;

  SELECT * INTO v_invitation FROM public.organization_invitations WHERE id = p_invitation_id FOR UPDATE;
  IF v_invitation.id IS NULL THEN RAISE EXCEPTION 'La invitación no existe'; END IF;

  IF NOT public.can_manage_organization_role(v_invitation.organization_id, v_invitation.role) THEN
    RAISE EXCEPTION 'No autorizado para cancelar esta invitación';
  END IF;

  v_effective := CASE WHEN v_invitation.status = 'pending' AND v_invitation.expires_at <= now()
    THEN 'expired' ELSE v_invitation.status::text END;
  IF v_effective NOT IN ('pending', 'expired') THEN
    RAISE EXCEPTION 'Solo se pueden cancelar invitaciones pendientes o vencidas';
  END IF;

  UPDATE public.organization_invitations
  SET status = 'revoked', revoked_at = now(), revoked_by = auth.uid()
  WHERE id = v_invitation.id
  RETURNING * INTO v_invitation;

  INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, entity_id, action, metadata)
  VALUES (v_invitation.organization_id, auth.uid(), 'organization_invitation', v_invitation.id, 'organization_invitation.revoked',
    jsonb_build_object('email', v_invitation.email));

  RETURN v_invitation;
END;
$$;

-- -------------------------------------------------------------------------
-- D) accept_organization_invitation — la operación crítica. Transaccional
--    (una sola llamada, un solo COMMIT implícito de la función). Nunca
--    recibe el rol: siempre se toma de la invitación ya validada.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.accept_organization_invitation(p_invitation_id uuid)
RETURNS TABLE(status text, organization_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
-- RETURNS TABLE(status text, organization_id uuid) implicitly declares
-- `organization_id` as a PL/pgSQL variable in this function's scope, which
-- collides with organization_members.organization_id — most sharply in
-- `ON CONFLICT (organization_id, user_id)` below, a column-name position
-- that cannot be table-qualified. This pragma makes every such bare
-- reference resolve to the table column, never the OUT parameter; the
-- function only ever returns via `v_invitation.organization_id`
-- (explicitly qualified), so the OUT variable itself is never read bare.
DECLARE
  v_invitation public.organization_invitations%ROWTYPE;
  v_org public.organizations%ROWTYPE;
  v_user record;
  v_existing_member public.organization_members%ROWTYPE;
  v_membership_action text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;

  SELECT id, email, email_confirmed_at INTO v_user FROM auth.users WHERE id = auth.uid();
  IF v_user.id IS NULL THEN RAISE EXCEPTION 'Usuario no encontrado'; END IF;

  SELECT * INTO v_invitation FROM public.organization_invitations WHERE id = p_invitation_id FOR UPDATE;
  IF v_invitation.id IS NULL THEN RAISE EXCEPTION 'La invitación no existe'; END IF;

  -- Idempotencia primero: si este mismo usuario ya la aceptó, nunca falla.
  IF v_invitation.status = 'accepted' AND v_invitation.accepted_by = auth.uid() THEN
    RETURN QUERY SELECT 'already_accepted'::text, v_invitation.organization_id;
    RETURN;
  END IF;

  IF lower(v_user.email) IS DISTINCT FROM v_invitation.email THEN
    RAISE EXCEPTION 'Esta invitación no corresponde a la cuenta con la que iniciaste sesión';
  END IF;

  IF v_user.email_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'Debes confirmar tu correo antes de aceptar esta invitación';
  END IF;

  IF v_invitation.status = 'revoked' THEN
    RAISE EXCEPTION 'Esta invitación fue cancelada';
  END IF;

  IF v_invitation.status = 'accepted' THEN
    RAISE EXCEPTION 'Esta invitación ya fue aceptada por otra cuenta';
  END IF;

  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Esta invitación ya no está disponible';
  END IF;

  IF v_invitation.expires_at <= now() THEN
    -- Deliberately does NOT persist status='expired' here: any write made
    -- before a RAISE EXCEPTION inside the same statement is rolled back
    -- together with it (Postgres subtransaction semantics — a caller like
    -- pgTAP's throws_matching, or any PL/pgSQL EXCEPTION handler, catches
    -- the error via an implicit SAVEPOINT and unwinds everything since).
    -- The row simply stays 'pending' physically; every reader (this
    -- function, list_organization_access, get_my_pending_invitations)
    -- already computes the effective 'expired' status the same way, so
    -- nothing depends on this column being normalized eagerly. create_/
    -- resend_organization_invitation DO persist the normalization
    -- successfully, because they update-then-RETURN rather than
    -- update-then-RAISE.
    RAISE EXCEPTION 'Esta invitación venció';
  END IF;

  SELECT * INTO v_org FROM public.organizations WHERE id = v_invitation.organization_id;
  IF v_org.id IS NULL OR v_org.status <> 'active' OR v_org.organization_type = 'platform_admin' THEN
    RAISE EXCEPTION 'La organización no está disponible';
  END IF;

  -- Table alias required: RETURNS TABLE(status text, organization_id uuid)
  -- makes `organization_id` an implicit PL/pgSQL variable in this
  -- function's scope, which would otherwise collide with (and make
  -- ambiguous) organization_members.organization_id in an unqualified
  -- WHERE clause.
  SELECT * INTO v_existing_member
  FROM public.organization_members om
  WHERE om.organization_id = v_invitation.organization_id AND om.user_id = auth.uid();
  v_membership_action := CASE WHEN v_existing_member.id IS NULL
    THEN 'organization_member.created' ELSE 'organization_member.reactivated' END;

  INSERT INTO public.organization_members (organization_id, user_id, role, invited_by, is_active)
  VALUES (v_invitation.organization_id, auth.uid(), v_invitation.role, v_invitation.invited_by, true)
  ON CONFLICT (organization_id, user_id) DO UPDATE
    SET role = EXCLUDED.role, is_active = true, invited_by = EXCLUDED.invited_by;

  UPDATE public.organization_invitations
  SET status = 'accepted', accepted_by = auth.uid(), accepted_at = now()
  WHERE id = v_invitation.id;

  INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, entity_id, action, metadata)
  VALUES (v_invitation.organization_id, auth.uid(), 'organization_invitation', v_invitation.id, 'organization_invitation.accepted',
    jsonb_build_object('role', v_invitation.role));
  INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, entity_id, action, metadata)
  VALUES (v_invitation.organization_id, auth.uid(), 'organization_member', v_invitation.id, v_membership_action,
    jsonb_build_object('role', v_invitation.role));

  RETURN QUERY SELECT 'accepted'::text, v_invitation.organization_id;
END;
$$;

-- -------------------------------------------------------------------------
-- E) Lecturas propias del usuario invitado — nunca exponen el email
--    objetivo, token_hash ni ids internos innecesarios. Responden vacío
--    (no error) cuando la invitación no le pertenece, para no revelar a
--    quién iba dirigida.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_organization_invitation(p_invitation_id uuid)
RETURNS TABLE(
  invitation_id uuid,
  organization_id uuid,
  organization_name text,
  role public.organization_member_role,
  effective_status text,
  expires_at timestamptz,
  invited_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  SELECT lower(email) INTO v_email FROM auth.users WHERE id = auth.uid();
  IF v_email IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT oi.id, oi.organization_id, o.name,
    oi.role,
    CASE WHEN oi.status = 'pending' AND oi.expires_at <= now() THEN 'expired' ELSE oi.status::text END,
    oi.expires_at,
    oi.invited_name
  FROM public.organization_invitations oi
  JOIN public.organizations o ON o.id = oi.organization_id
  WHERE oi.id = p_invitation_id AND oi.email = v_email;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_pending_invitations()
RETURNS TABLE(
  invitation_id uuid,
  organization_id uuid,
  organization_name text,
  role public.organization_member_role,
  invited_name text,
  expires_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
  v_confirmed timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  SELECT lower(email), email_confirmed_at INTO v_email, v_confirmed FROM auth.users WHERE id = auth.uid();
  IF v_email IS NULL OR v_confirmed IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT oi.id, oi.organization_id, o.name, oi.role, oi.invited_name, oi.expires_at
  FROM public.organization_invitations oi
  JOIN public.organizations o ON o.id = oi.organization_id
  WHERE oi.email = v_email AND oi.status = 'pending' AND oi.expires_at > now()
    AND o.status = 'active' AND o.organization_type <> 'platform_admin'
  ORDER BY oi.created_at DESC;
END;
$$;

-- -------------------------------------------------------------------------
-- F) list_organization_access — evita el N+1 de admin-list-organization-members
--    y añade las invitaciones en la misma lectura. Revocadas: solo últimos
--    30 días. Aceptadas: no se listan como invitación (ya son miembro).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_organization_access(p_organization_id uuid)
RETURNS TABLE(
  kind text,
  id uuid,
  user_id uuid,
  name text,
  email text,
  role public.organization_member_role,
  is_active boolean,
  joined_at timestamptz,
  invited_name text,
  effective_status text,
  created_at timestamptz,
  expires_at timestamptz,
  accepted_at timestamptz,
  revoked_at timestamptz,
  last_sent_at timestamptz,
  send_count integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
-- Same RETURNS TABLE / bare-identifier collision as
-- accept_organization_invitation ("kind" is both an OUT parameter and an
-- output column in the CTE's ORDER BY below).
BEGIN
  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to list this organization''s access';
  END IF;

  RETURN QUERY
  WITH combined AS (
    SELECT 'member'::text AS kind, om.id, om.user_id,
      COALESCE(u.raw_user_meta_data->>'name', '') AS name, u.email::text,
      om.role, om.is_active, om.joined_at,
      NULL::text AS invited_name, NULL::text AS effective_status,
      NULL::timestamptz AS created_at, NULL::timestamptz AS expires_at, NULL::timestamptz AS accepted_at,
      NULL::timestamptz AS revoked_at, NULL::timestamptz AS last_sent_at, NULL::integer AS send_count,
      om.joined_at AS sort_at
    FROM public.organization_members om
    JOIN auth.users u ON u.id = om.user_id
    WHERE om.organization_id = p_organization_id

    UNION ALL

    SELECT 'invitation'::text, oi.id, NULL::uuid,
      COALESCE(oi.invited_name, ''), oi.email,
      oi.role, NULL::boolean, NULL::timestamptz,
      oi.invited_name,
      CASE WHEN oi.status = 'pending' AND oi.expires_at <= now() THEN 'expired' ELSE oi.status::text END,
      oi.created_at, oi.expires_at, oi.accepted_at, oi.revoked_at, oi.last_sent_at, oi.send_count,
      oi.created_at AS sort_at
    FROM public.organization_invitations oi
    WHERE oi.organization_id = p_organization_id
      AND oi.status <> 'accepted'
      AND (oi.status <> 'revoked' OR oi.revoked_at > now() - interval '30 days')
  )
  SELECT kind, id, user_id, name, email, role, is_active, joined_at, invited_name, effective_status,
    created_at, expires_at, accepted_at, revoked_at, last_sent_at, send_count
  FROM combined
  ORDER BY (kind = 'member') DESC, sort_at DESC NULLS LAST;
END;
$$;

-- -------------------------------------------------------------------------
-- G) update_organization_member — sustituye la lógica inline (y su
--    protección de último owner no atómica) de la Edge Function. Aplica la
--    jerarquía completa del punto 4: admin no toca a un owner ni promueve a
--    owner, admin no se modifica a sí mismo, owner protegido si es el
--    último activo, con lock transaccional real.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_organization_member(
  p_membership_id uuid,
  p_role public.organization_member_role DEFAULT NULL,
  p_is_active boolean DEFAULT NULL
)
RETURNS public.organization_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member public.organization_members%ROWTYPE;
  v_org public.organizations%ROWTYPE;
  v_caller_role public.organization_member_role;
  v_platform boolean;
  v_owner_count integer;
  v_old_role public.organization_member_role;
  v_old_active boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF p_role IS NULL AND p_is_active IS NULL THEN RAISE EXCEPTION 'No changes provided'; END IF;

  SELECT * INTO v_member FROM public.organization_members WHERE id = p_membership_id FOR UPDATE;
  IF v_member.id IS NULL THEN RAISE EXCEPTION 'Membership not found'; END IF;

  SELECT * INTO v_org FROM public.organizations WHERE id = v_member.organization_id;
  IF v_org.id IS NULL THEN RAISE EXCEPTION 'Organization not found'; END IF;

  v_platform := public.is_platform_admin();
  IF v_org.organization_type = 'platform_admin' AND NOT v_platform THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF NOT (v_platform OR public.has_organization_role(v_org.id, ARRAY['owner', 'admin']::public.organization_member_role[])) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- El caller debe poder gestionar tanto el rol ACTUAL del miembro (un admin
  -- no toca a un owner) como el rol NUEVO, si cambia (un admin no promueve).
  IF NOT public.can_manage_organization_role(v_org.id, v_member.role) THEN
    RAISE EXCEPTION 'No autorizado para modificar un miembro con este rol';
  END IF;
  IF p_role IS NOT NULL AND NOT public.can_manage_organization_role(v_org.id, p_role) THEN
    RAISE EXCEPTION 'No autorizado para asignar este rol';
  END IF;

  IF v_member.user_id = auth.uid() AND NOT v_platform THEN
    SELECT role INTO v_caller_role
    FROM public.organization_members
    WHERE organization_id = v_org.id AND user_id = auth.uid() AND is_active = true;
    IF v_caller_role = 'admin' THEN
      RAISE EXCEPTION 'No puedes modificar tu propia membresía';
    END IF;
  END IF;

  -- Último owner activo: lock real sobre las filas antes de contar, para
  -- que dos degradaciones concurrentes no puedan dejar la organización sin
  -- ningún owner activo.
  IF v_member.role = 'owner' AND v_member.is_active
     AND ((p_role IS NOT NULL AND p_role <> 'owner') OR p_is_active IS FALSE) THEN
    PERFORM 1 FROM public.organization_members
      WHERE organization_id = v_org.id AND role = 'owner' AND is_active = true
      FOR UPDATE;
    SELECT count(*) INTO v_owner_count FROM public.organization_members
      WHERE organization_id = v_org.id AND role = 'owner' AND is_active = true;
    IF v_owner_count <= 1 THEN
      RAISE EXCEPTION 'No se puede modificar o desactivar al último propietario activo';
    END IF;
  END IF;

  v_old_role := v_member.role;
  v_old_active := v_member.is_active;

  UPDATE public.organization_members
  SET role = COALESCE(p_role, role), is_active = COALESCE(p_is_active, is_active)
  WHERE id = p_membership_id
  RETURNING * INTO v_member;

  IF p_role IS NOT NULL AND p_role IS DISTINCT FROM v_old_role THEN
    INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, entity_id, action, metadata)
    VALUES (v_org.id, auth.uid(), 'organization_member', v_member.id, 'organization_member.role_changed',
      jsonb_build_object('old_role', v_old_role, 'new_role', p_role));
  END IF;
  IF p_is_active IS NOT NULL AND p_is_active IS DISTINCT FROM v_old_active THEN
    INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, entity_id, action, metadata)
    VALUES (v_org.id, auth.uid(), 'organization_member', v_member.id,
      CASE WHEN p_is_active THEN 'organization_member.activated' ELSE 'organization_member.deactivated' END,
      '{}'::jsonb);
  END IF;

  RETURN v_member;
END;
$$;

-- -------------------------------------------------------------------------
-- H) get_auth_user_state_by_email — solo service_role. Sustituye
--    auth.admin.listUsers({perPage:1000}) (se cortaba en 1000 usuarios) y
--    evita que un owner/admin de tenant pueda enumerar cuentas de toda la
--    plataforma: no se expone a authenticated bajo ningún motivo. Incluye
--    user_id (no solo exists_flag) porque admin-create-user-and-add-member
--    también reemplaza su propio listUsers({perPage:1000}) con esta misma
--    función — de nuevo, sin exponer el id a nadie más que service_role.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_auth_user_state_by_email(p_email text)
RETURNS TABLE(exists_flag boolean, email_confirmed boolean, user_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text := lower(trim(p_email));
  v_user record;
BEGIN
  SELECT id, email_confirmed_at INTO v_user FROM auth.users WHERE lower(email) = v_email LIMIT 1;
  IF v_user.id IS NULL THEN
    RETURN QUERY SELECT false, false, NULL::uuid;
  ELSE
    RETURN QUERY SELECT true, v_user.email_confirmed_at IS NOT NULL, v_user.id;
  END IF;
END;
$$;

-- -------------------------------------------------------------------------
-- Grants — cada función nueva declara su propio EXECUTE explícito, porque
-- 20260831100000_function_acl_hardening.sql revocó el default de PUBLIC/
-- anon/authenticated para toda función futura creada por postgres.
-- -------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.can_manage_organization_role(uuid, public.organization_member_role) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_manage_invitation_target(uuid, text) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.create_organization_invitation(uuid, text, public.organization_member_role, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_organization_invitation(uuid, text, public.organization_member_role, text) TO authenticated;

REVOKE ALL ON FUNCTION public.resend_organization_invitation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resend_organization_invitation(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.mark_invitation_sent(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_invitation_sent(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.revoke_organization_invitation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_organization_invitation(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.accept_organization_invitation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_organization_invitation(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.get_my_organization_invitation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_organization_invitation(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.get_my_pending_invitations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_pending_invitations() TO authenticated;

REVOKE ALL ON FUNCTION public.list_organization_access(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_organization_access(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.update_organization_member(uuid, public.organization_member_role, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_organization_member(uuid, public.organization_member_role, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.get_auth_user_state_by_email(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_user_state_by_email(text) TO service_role;
