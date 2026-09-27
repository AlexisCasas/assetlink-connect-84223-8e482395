-- =========================================================================
-- Fase 1 · Punto 8 — Alertas automáticas (parte 1: SQL, sin scheduler).
--
-- El scheduler (pg_cron) se habilita en la migración separada
-- 20260927150952_automatic_alerts_schedule.sql. Esta migración deja todo
-- lo necesario para que, una vez programado el cron, las alertas
-- dependientes del tiempo (OT, inspecciones, preventivo) se generen en
-- backend sin que nadie tenga la aplicación abierta.
--
-- Bloques:
--   A) Hardening de organization_notifications (UPDATE por columna +
--      trigger de protección ampliado).
--   B) notify_member: exige membership activa (aplica a TODOS los
--      eventos existentes, no solo a las alertas automáticas).
--   C) Helpers de conteo (notify_member_counted / notify_role_members_counted)
--      — nunca se tocan los retornos de notify_member/notify_role_members,
--      que usan ~15 funciones existentes.
--   D) Generadores internos (sin auth.uid(), sin grants a authenticated):
--      generate_operational_due_notifications_internal(),
--      generate_inspection_due_notifications_internal() (fija
--      TimeZone=UTC), generate_preventive_due_notifications() (nuevo).
--   E) automatic_alert_runs — observabilidad mínima.
--   F) run_automatic_alert_generation() — wrapper con advisory lock y
--      aislamiento de errores por generador.
--
-- Deuda temporal documentada (decisión explícita, ver docs/AUTOMATIC_ALERTS.md):
-- generate_operational_due_notifications() y
-- generate_inspection_due_notifications() (las funciones PÚBLICAS
-- existentes, con su propio auth.uid()) CONSERVAN su GRANT EXECUTE a
-- authenticated en esta migración. El frontend deja de llamarlas en este
-- mismo PR, pero el grant no se revoca todavía — eso queda para una
-- migración exclusiva posterior, después de verificar cron + frontend en
-- producción.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A) Hardening de organization_notifications
--
-- Hallazgo del diagnóstico: el trigger protect_organization_notification_update
-- ya impedía casi todo, pero NO recipient_member_id, priority ni metadata.
-- Verificado con una transacción de prueba (ROLLBACK): un miembro común
-- podía convertir su propia notificación dirigida en broadcast
-- (recipient_member_id = NULL, visible a toda la organización) y alterar
-- priority/metadata (esto último es lo que usa la navegación del centro de
-- notificaciones). Reasignar a OTRO miembro ya lo bloqueaba la RLS.
-- -------------------------------------------------------------------------
REVOKE UPDATE ON TABLE public.organization_notifications FROM authenticated;
GRANT UPDATE (is_read, read_at) ON TABLE public.organization_notifications TO authenticated;

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
    -- Ampliado en Fase 1 · Punto 8: sin esto, un miembro común podía
    -- convertir su notificación dirigida en broadcast, o alterar la
    -- prioridad/metadata que usa la navegación del centro de notificaciones.
    OR NEW.recipient_member_id IS DISTINCT FROM OLD.recipient_member_id
    OR NEW.priority IS DISTINCT FROM OLD.priority
    OR NEW.metadata IS DISTINCT FROM OLD.metadata
    OR NEW.is_read IS NOT TRUE THEN
    RAISE EXCEPTION 'Organization notifications can only be marked as read';
  END IF;

  IF OLD.is_read IS FALSE AND NEW.read_at IS NULL THEN
    NEW.read_at := now();
  END IF;

  RETURN NEW;
END;
$$;

-- -------------------------------------------------------------------------
-- B) notify_member: exige membership ACTIVA. Se aplica globalmente — toda
--    notificación dirigida (eventos existentes incluidos), no solo las
--    alertas automáticas de este punto. notify_role_members ya filtraba
--    por is_active; notify_member no lo hacía.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_member(
  p_member_id uuid, p_actor_user_id uuid, p_type text, p_title text, p_message text,
  p_entity_type text, p_entity_id uuid, p_priority text DEFAULT 'medium'::text, p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_organization_id uuid;
BEGIN
  SELECT om.organization_id INTO v_organization_id
  FROM public.organization_members om
  WHERE om.id = p_member_id AND om.is_active;
  IF v_organization_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM public.create_notification_once(
    v_organization_id, p_member_id, p_actor_user_id, p_type, p_title, p_message,
    p_entity_type, p_entity_id, p_priority, p_metadata
  );
END;
$$;

-- -------------------------------------------------------------------------
-- C) Helpers de conteo — nunca se tocan las firmas/retornos de
--    notify_member/notify_role_members (usadas por ~15 funciones
--    existentes). Estas son SOLO para que el wrapper pueda reportar cuántas
--    notificaciones insertó cada generador. Sin grants a ningún rol
--    cliente: solo las llaman los generadores internos (SECURITY DEFINER,
--    propiedad de postgres).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_member_counted(
  p_member_id uuid, p_actor_user_id uuid, p_type text, p_title text, p_message text,
  p_entity_type text, p_entity_id uuid, p_priority text DEFAULT 'medium'::text, p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organization_id uuid;
  v_id uuid;
BEGIN
  SELECT om.organization_id INTO v_organization_id
  FROM public.organization_members om
  WHERE om.id = p_member_id AND om.is_active;
  IF v_organization_id IS NULL THEN
    RETURN 0;
  END IF;

  v_id := public.create_notification_once(
    v_organization_id, p_member_id, p_actor_user_id, p_type, p_title, p_message,
    p_entity_type, p_entity_id, p_priority, p_metadata
  );
  RETURN CASE WHEN v_id IS NULL THEN 0 ELSE 1 END;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_role_members_counted(
  p_organization_id uuid, p_roles public.organization_member_role[], p_actor_user_id uuid, p_type text, p_title text, p_message text,
  p_entity_type text, p_entity_id uuid, p_priority text DEFAULT 'medium'::text, p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
  v_id uuid;
  v_count integer := 0;
BEGIN
  FOR v_member_id IN
    SELECT om.id FROM public.organization_members om
    WHERE om.organization_id = p_organization_id
      AND om.is_active
      AND om.role = ANY (p_roles)
  LOOP
    v_id := public.create_notification_once(
      p_organization_id, v_member_id, p_actor_user_id, p_type, p_title, p_message,
      p_entity_type, p_entity_id, p_priority, p_metadata
    );
    IF v_id IS NOT NULL THEN v_count := v_count + 1; END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

-- -------------------------------------------------------------------------
-- Índice parcial para las dos consultas de generate_operational_due_
-- notifications_internal() (due-soon y overdue). Evaluado con EXPLAIN
-- (ANALYZE, BUFFERS) real sobre 100,000 work_orders sintéticas (60,009 no
-- terminales, ventana due-soon=7,505 filas ~7.5%, ventana overdue=30,066
-- filas ~30%) en una transacción descartable (ROLLBACK, sin tocar datos
-- reales):
--   - due-soon: Seq Scan -> Bitmap Heap Scan, cost 4619->2424,
--     tiempo real ~19.4ms -> ~8.3ms.
--   - overdue:  Seq Scan -> Bitmap Heap Scan, cost 3928->3044,
--     tiempo real ~19.6ms -> ~12.9ms.
-- Mejora real y medible en ambos casos; el planner puede seguir eligiendo
-- Seq Scan por sí solo si la proporción de OTs vencidas/no-terminales
-- crece tanto que deje de convenir (auto-ajustable, sin downside).
-- -------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_work_orders_due_at_active
  ON public.work_orders (due_at)
  WHERE due_at IS NOT NULL AND status NOT IN ('completed', 'closed');

-- -------------------------------------------------------------------------
-- D.1) generate_operational_due_notifications_internal() — mismo criterio
--      que la función pública existente (due-soon <= 24h, overdue < now(),
--      excluye completed/closed), más organización activa y destinatario
--      activo (ya cubierto por notify_role_members_counted/notify_member_counted).
--      Sin auth.uid(): la invoca únicamente el wrapper (postgres).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_operational_due_notifications_internal()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wo record;
  v_count integer := 0;
BEGIN
  FOR v_wo IN
    SELECT wo.id, wo.work_order_number, wo.provider_organization_id, wo.assigned_member_id
    FROM public.work_orders wo
    JOIN public.organizations o ON o.id = wo.provider_organization_id
    WHERE wo.due_at IS NOT NULL
      AND wo.status NOT IN ('completed', 'closed')
      AND wo.due_at >= now()
      AND wo.due_at <= now() + interval '24 hours'
      AND o.status = 'active'
  LOOP
    v_count := v_count + public.notify_role_members_counted(
      v_wo.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL, 'work_order_due_soon', 'OT próxima a vencer',
      'La orden ' || v_wo.work_order_number || ' vence en menos de 24 horas.',
      'work_order', v_wo.id, 'high',
      jsonb_build_object('work_order_number', v_wo.work_order_number)
    );
    IF v_wo.assigned_member_id IS NOT NULL THEN
      v_count := v_count + public.notify_member_counted(
        v_wo.assigned_member_id, NULL, 'work_order_due_soon', 'OT próxima a vencer',
        'La orden ' || v_wo.work_order_number || ' vence en menos de 24 horas.',
        'work_order', v_wo.id, 'high',
        jsonb_build_object('work_order_number', v_wo.work_order_number)
      );
    END IF;
  END LOOP;

  FOR v_wo IN
    SELECT wo.id, wo.work_order_number, wo.provider_organization_id, wo.assigned_member_id
    FROM public.work_orders wo
    JOIN public.organizations o ON o.id = wo.provider_organization_id
    WHERE wo.due_at IS NOT NULL
      AND wo.status NOT IN ('completed', 'closed')
      AND wo.due_at < now()
      AND o.status = 'active'
  LOOP
    v_count := v_count + public.notify_role_members_counted(
      v_wo.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL, 'work_order_overdue', 'OT vencida',
      'La orden ' || v_wo.work_order_number || ' está vencida.',
      'work_order', v_wo.id, 'urgent',
      jsonb_build_object('work_order_number', v_wo.work_order_number)
    );
    IF v_wo.assigned_member_id IS NOT NULL THEN
      v_count := v_count + public.notify_member_counted(
        v_wo.assigned_member_id, NULL, 'work_order_overdue', 'OT vencida',
        'La orden ' || v_wo.work_order_number || ' está vencida.',
        'work_order', v_wo.id, 'urgent',
        jsonb_build_object('work_order_number', v_wo.work_order_number)
      );
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- -------------------------------------------------------------------------
-- D.2) generate_inspection_due_notifications_internal() — mismo criterio
--      que la función pública (before_due con múltiples umbrales, overdue,
--      entidad sintética md5(plan_id|rule_id|next_due_at::text)). Fija
--      TimeZone=UTC explícitamente: next_due_at::text (usado en el hash)
--      depende de la zona horaria de la sesión — verificado que hoy
--      coincide porque todo corre en UTC por defecto, pero un scheduler no
--      debe depender de eso implícitamente.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_inspection_due_notifications_internal()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET timezone = 'UTC'
AS $$
DECLARE
  v_row record;
  v_cycle_entity_id uuid;
  v_message text;
  v_metadata jsonb;
  v_count integer := 0;
BEGIN
  FOR v_row IN
    SELECT
      ip.id AS plan_id, ip.title AS plan_title, ip.organization_id, ip.responsible_member_id,
      ip.next_due_at, ip.frequency, ip.custom_interval, ip.custom_unit, ct.name AS template_name,
      ipar.id AS rule_id, ipar.days_before, ipar.label
    FROM public.inspection_plans ip
    INNER JOIN public.checklist_templates ct ON ct.id = ip.template_id
    INNER JOIN public.inspection_plan_alert_rules ipar
      ON ipar.plan_id = ip.id AND ipar.is_active AND ipar.alert_type = 'before_due'
    JOIN public.organizations o ON o.id = ip.organization_id
    WHERE ip.is_active
      AND ip.next_due_at IS NOT NULL
      AND now() >= (ip.next_due_at - make_interval(days => ipar.days_before))
      AND now() < ip.next_due_at
      AND o.status = 'active'
  LOOP
    v_cycle_entity_id := md5(v_row.plan_id::text || '|' || v_row.rule_id::text || '|' || v_row.next_due_at::text)::uuid;
    v_message := 'La inspección "' || v_row.plan_title || '" vence en ' || COALESCE(v_row.label, v_row.days_before || ' días') || '.';
    v_metadata := jsonb_build_object(
      'plan_id', v_row.plan_id, 'plan_title', v_row.plan_title, 'template_name', v_row.template_name,
      'next_due_at', v_row.next_due_at, 'alert_type', 'before_due', 'days_before', v_row.days_before,
      'frequency', v_row.frequency, 'custom_interval', v_row.custom_interval, 'custom_unit', v_row.custom_unit
    );

    v_count := v_count + public.notify_role_members_counted(
      v_row.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL, 'inspection_due_soon_future', 'Inspección próxima a vencer', v_message,
      'inspection_plan', v_cycle_entity_id, 'medium', v_metadata
    );
    IF v_row.responsible_member_id IS NOT NULL THEN
      v_count := v_count + public.notify_member_counted(
        v_row.responsible_member_id, NULL, 'inspection_due_soon_future', 'Inspección próxima a vencer', v_message,
        'inspection_plan', v_cycle_entity_id, 'medium', v_metadata
      );
    END IF;
  END LOOP;

  FOR v_row IN
    SELECT
      ip.id AS plan_id, ip.title AS plan_title, ip.organization_id, ip.responsible_member_id,
      ip.next_due_at, ip.frequency, ip.custom_interval, ip.custom_unit, ct.name AS template_name,
      ipar.id AS rule_id, ipar.label
    FROM public.inspection_plans ip
    INNER JOIN public.checklist_templates ct ON ct.id = ip.template_id
    INNER JOIN public.inspection_plan_alert_rules ipar
      ON ipar.plan_id = ip.id AND ipar.is_active AND ipar.alert_type = 'overdue'
    JOIN public.organizations o ON o.id = ip.organization_id
    WHERE ip.is_active
      AND ip.next_due_at IS NOT NULL
      AND ip.next_due_at < now()
      AND o.status = 'active'
  LOOP
    v_cycle_entity_id := md5(v_row.plan_id::text || '|' || v_row.rule_id::text || '|' || v_row.next_due_at::text)::uuid;
    v_message := 'La inspección "' || v_row.plan_title || '" está vencida.';
    v_metadata := jsonb_build_object(
      'plan_id', v_row.plan_id, 'plan_title', v_row.plan_title, 'template_name', v_row.template_name,
      'next_due_at', v_row.next_due_at, 'alert_type', 'overdue', 'days_before', NULL,
      'frequency', v_row.frequency, 'custom_interval', v_row.custom_interval, 'custom_unit', v_row.custom_unit
    );

    v_count := v_count + public.notify_role_members_counted(
      v_row.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL, 'inspection_overdue_future', 'Inspección vencida', v_message,
      'inspection_plan', v_cycle_entity_id, 'urgent', v_metadata
    );
    IF v_row.responsible_member_id IS NOT NULL THEN
      v_count := v_count + public.notify_member_counted(
        v_row.responsible_member_id, NULL, 'inspection_overdue_future', 'Inspección vencida', v_message,
        'inspection_plan', v_cycle_entity_id, 'urgent', v_metadata
      );
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- -------------------------------------------------------------------------
-- D.3) generate_preventive_due_notifications() — NUEVO. Replica el mismo
--      timing_status que ya usa get_preventive_maintenance_plans (calendario:
--      due_at - planning_lead_days <= now <= due_at; medidor: última lectura
--      efectiva entre due_meter_value - meter_lead_value y due_meter_value).
--      entity_id = occurrence.id: una alerta 'due' y una 'overdue' como
--      máximo por destinatario y ocurrencia — nunca duplicados del mismo
--      estado (dedup ya existente en organization_notifications). Al
--      completarse una ocurrencia, la siguiente tiene otro id y vuelve a
--      poder alertar.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_preventive_due_notifications()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_message text;
  v_metadata jsonb;
  v_count integer := 0;
BEGIN
  -- Calendario · due
  FOR v_row IN
    SELECT o.id AS occurrence_id, o.organization_id, o.asset_id, o.sequence,
      p.id AS plan_id, p.priority, p.responsible_member_id
    FROM public.preventive_maintenance_occurrences o
    JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
    JOIN public.organizations org ON org.id = o.organization_id
    JOIN public.assets a ON a.id = o.asset_id
    WHERE o.status IN ('open', 'planned')
      AND p.is_active
      AND p.trigger_type = 'calendar'
      AND o.due_at IS NOT NULL
      AND now() >= o.due_at - make_interval(days => p.planning_lead_days)
      AND now() <= o.due_at
      AND org.status = 'active'
      AND a.status <> 'archived'
  LOOP
    v_message := 'El mantenimiento preventivo #' || v_row.sequence || ' vence pronto.';
    v_metadata := jsonb_build_object('plan_id', v_row.plan_id, 'occurrence_id', v_row.occurrence_id, 'occurrence_sequence', v_row.sequence, 'asset_id', v_row.asset_id);
    IF v_row.responsible_member_id IS NOT NULL THEN
      v_count := v_count + public.notify_member_counted(
        v_row.responsible_member_id, NULL, 'preventive_maintenance_due', 'Mantenimiento preventivo próximo', v_message,
        'preventive_maintenance_occurrence', v_row.occurrence_id, v_row.priority, v_metadata
      );
    END IF;
    v_count := v_count + public.notify_role_members_counted(
      v_row.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL, 'preventive_maintenance_due', 'Mantenimiento preventivo próximo', v_message,
      'preventive_maintenance_occurrence', v_row.occurrence_id, v_row.priority, v_metadata
    );
  END LOOP;

  -- Calendario · overdue
  FOR v_row IN
    SELECT o.id AS occurrence_id, o.organization_id, o.asset_id, o.sequence,
      p.id AS plan_id, p.responsible_member_id
    FROM public.preventive_maintenance_occurrences o
    JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
    JOIN public.organizations org ON org.id = o.organization_id
    JOIN public.assets a ON a.id = o.asset_id
    WHERE o.status IN ('open', 'planned')
      AND p.is_active
      AND p.trigger_type = 'calendar'
      AND o.due_at IS NOT NULL
      AND now() > o.due_at
      AND org.status = 'active'
      AND a.status <> 'archived'
  LOOP
    v_message := 'El mantenimiento preventivo #' || v_row.sequence || ' está vencido.';
    v_metadata := jsonb_build_object('plan_id', v_row.plan_id, 'occurrence_id', v_row.occurrence_id, 'occurrence_sequence', v_row.sequence, 'asset_id', v_row.asset_id);
    IF v_row.responsible_member_id IS NOT NULL THEN
      v_count := v_count + public.notify_member_counted(
        v_row.responsible_member_id, NULL, 'preventive_maintenance_overdue', 'Mantenimiento preventivo vencido', v_message,
        'preventive_maintenance_occurrence', v_row.occurrence_id, 'urgent', v_metadata
      );
    END IF;
    v_count := v_count + public.notify_role_members_counted(
      v_row.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL, 'preventive_maintenance_overdue', 'Mantenimiento preventivo vencido', v_message,
      'preventive_maintenance_occurrence', v_row.occurrence_id, 'urgent', v_metadata
    );
  END LOOP;

  -- Medidor · due — última lectura EFECTIVA (voided_at IS NULL, la más
  -- reciente por recorded_at). Una corrección anula la original y crea
  -- otra: este filtro ya la sigue automáticamente.
  FOR v_row IN
    SELECT o.id AS occurrence_id, o.organization_id, o.asset_id, o.sequence,
      p.id AS plan_id, p.priority, p.responsible_member_id
    FROM public.preventive_maintenance_occurrences o
    JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
    JOIN public.organizations org ON org.id = o.organization_id
    JOIN public.assets a ON a.id = o.asset_id
    JOIN public.asset_meters m ON m.id = p.meter_id
    JOIN LATERAL (
      SELECT r.value FROM public.asset_meter_readings r
      WHERE r.meter_id = p.meter_id AND r.voided_at IS NULL
      ORDER BY r.recorded_at DESC LIMIT 1
    ) lr ON true
    WHERE o.status IN ('open', 'planned')
      AND p.is_active
      AND p.trigger_type = 'meter'
      AND o.due_meter_value IS NOT NULL
      AND m.is_active
      AND org.status = 'active'
      AND a.status <> 'archived'
      AND lr.value >= o.due_meter_value - p.meter_lead_value
      AND lr.value <= o.due_meter_value
  LOOP
    v_message := 'El mantenimiento preventivo #' || v_row.sequence || ' vence pronto.';
    v_metadata := jsonb_build_object('plan_id', v_row.plan_id, 'occurrence_id', v_row.occurrence_id, 'occurrence_sequence', v_row.sequence, 'asset_id', v_row.asset_id);
    IF v_row.responsible_member_id IS NOT NULL THEN
      v_count := v_count + public.notify_member_counted(
        v_row.responsible_member_id, NULL, 'preventive_maintenance_due', 'Mantenimiento preventivo próximo', v_message,
        'preventive_maintenance_occurrence', v_row.occurrence_id, v_row.priority, v_metadata
      );
    END IF;
    v_count := v_count + public.notify_role_members_counted(
      v_row.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL, 'preventive_maintenance_due', 'Mantenimiento preventivo próximo', v_message,
      'preventive_maintenance_occurrence', v_row.occurrence_id, v_row.priority, v_metadata
    );
  END LOOP;

  -- Medidor · overdue
  FOR v_row IN
    SELECT o.id AS occurrence_id, o.organization_id, o.asset_id, o.sequence,
      p.id AS plan_id, p.responsible_member_id
    FROM public.preventive_maintenance_occurrences o
    JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
    JOIN public.organizations org ON org.id = o.organization_id
    JOIN public.assets a ON a.id = o.asset_id
    JOIN public.asset_meters m ON m.id = p.meter_id
    JOIN LATERAL (
      SELECT r.value FROM public.asset_meter_readings r
      WHERE r.meter_id = p.meter_id AND r.voided_at IS NULL
      ORDER BY r.recorded_at DESC LIMIT 1
    ) lr ON true
    WHERE o.status IN ('open', 'planned')
      AND p.is_active
      AND p.trigger_type = 'meter'
      AND o.due_meter_value IS NOT NULL
      AND m.is_active
      AND org.status = 'active'
      AND a.status <> 'archived'
      AND lr.value > o.due_meter_value
  LOOP
    v_message := 'El mantenimiento preventivo #' || v_row.sequence || ' está vencido.';
    v_metadata := jsonb_build_object('plan_id', v_row.plan_id, 'occurrence_id', v_row.occurrence_id, 'occurrence_sequence', v_row.sequence, 'asset_id', v_row.asset_id);
    IF v_row.responsible_member_id IS NOT NULL THEN
      v_count := v_count + public.notify_member_counted(
        v_row.responsible_member_id, NULL, 'preventive_maintenance_overdue', 'Mantenimiento preventivo vencido', v_message,
        'preventive_maintenance_occurrence', v_row.occurrence_id, 'urgent', v_metadata
      );
    END IF;
    v_count := v_count + public.notify_role_members_counted(
      v_row.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL, 'preventive_maintenance_overdue', 'Mantenimiento preventivo vencido', v_message,
      'preventive_maintenance_occurrence', v_row.occurrence_id, 'urgent', v_metadata
    );
  END LOOP;

  RETURN v_count;
END;
$$;

-- -------------------------------------------------------------------------
-- E) automatic_alert_runs — observabilidad mínima. Sin grants a
--    anon/authenticated: se consulta desde el SQL Editor o service_role.
--    RLS habilitado sin policies (cero filas visibles salvo BYPASSRLS).
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.automatic_alert_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at timestamptz NOT NULL,
  finished_at timestamptz NOT NULL,
  duration_ms integer NOT NULL,
  result jsonb NOT NULL,
  had_errors boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_automatic_alert_runs_created_at ON public.automatic_alert_runs (created_at DESC);

ALTER TABLE public.automatic_alert_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.automatic_alert_runs FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- F) run_automatic_alert_generation() — wrapper. Un único scheduler lo
--    llama cada hora. pg_try_advisory_xact_lock: si dos ejecuciones se
--    solapan (dos cron ticks, o un run manual durante el de cron), la
--    segunda no hace nada y devuelve {"skipped":"already_running"} — el
--    lock se libera solo al terminar la transacción, así que nunca queda
--    "pegado". Cada generador corre en su propio bloque BEGIN/EXCEPTION
--    (equivale a un savepoint): un fallo en inspecciones no impide que OT
--    o preventivo se hayan insertado. Nunca captura query/stack/JWT — solo
--    SQLSTATE y un mensaje acotado a 500 caracteres.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_automatic_alert_generation()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Constante arbitraria y distintiva (no colisiona con ningún otro
  -- advisory lock del proyecto — no hay ninguno más hoy).
  v_lock_key bigint := 728471001;
  v_started_at timestamptz := clock_timestamp();
  v_finished_at timestamptz;
  v_had_errors boolean := false;
  v_operational jsonb;
  v_inspection jsonb;
  v_preventive jsonb;
  v_count integer;
  v_result jsonb;
BEGIN
  IF NOT pg_try_advisory_xact_lock(v_lock_key) THEN
    RETURN jsonb_build_object('skipped', 'already_running');
  END IF;

  BEGIN
    v_count := public.generate_operational_due_notifications_internal();
    v_operational := jsonb_build_object('status', 'ok', 'inserted', v_count);
  EXCEPTION WHEN OTHERS THEN
    v_had_errors := true;
    v_operational := jsonb_build_object('status', 'error', 'sqlstate', SQLSTATE, 'error', left(SQLERRM, 500));
  END;

  BEGIN
    v_count := public.generate_inspection_due_notifications_internal();
    v_inspection := jsonb_build_object('status', 'ok', 'inserted', v_count);
  EXCEPTION WHEN OTHERS THEN
    v_had_errors := true;
    v_inspection := jsonb_build_object('status', 'error', 'sqlstate', SQLSTATE, 'error', left(SQLERRM, 500));
  END;

  BEGIN
    v_count := public.generate_preventive_due_notifications();
    v_preventive := jsonb_build_object('status', 'ok', 'inserted', v_count);
  EXCEPTION WHEN OTHERS THEN
    v_had_errors := true;
    v_preventive := jsonb_build_object('status', 'error', 'sqlstate', SQLSTATE, 'error', left(SQLERRM, 500));
  END;

  v_finished_at := clock_timestamp();
  v_result := jsonb_build_object(
    'started_at', v_started_at,
    'finished_at', v_finished_at,
    'duration_ms', round(extract(epoch FROM (v_finished_at - v_started_at)) * 1000),
    'generators', jsonb_build_object('operational', v_operational, 'inspection', v_inspection, 'preventive', v_preventive)
  );

  INSERT INTO public.automatic_alert_runs (started_at, finished_at, duration_ms, result, had_errors)
  VALUES (v_started_at, v_finished_at, round(extract(epoch FROM (v_finished_at - v_started_at)) * 1000)::integer, v_result, v_had_errors);

  RETURN v_result;
END;
$$;

-- -------------------------------------------------------------------------
-- Grants — cada función nueva declara el suyo explícito (convención del
-- repo desde 20260831100000_function_acl_hardening.sql: una función nueva
-- de postgres no hereda EXECUTE por defecto).
-- -------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.notify_member_counted(uuid, uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_role_members_counted(uuid, public.organization_member_role[], uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.generate_operational_due_notifications_internal() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.generate_inspection_due_notifications_internal() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.generate_preventive_due_notifications() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.run_automatic_alert_generation() FROM PUBLIC, anon, authenticated;

-- Deuda temporal explícita (ver docs/AUTOMATIC_ALERTS.md): las funciones
-- PÚBLICAS existentes (con su propio auth.uid()) conservan su grant a
-- authenticated en esta migración — no se tocan aquí a propósito.
--   generate_operational_due_notifications()  -> sigue GRANT EXECUTE authenticated
--   generate_inspection_due_notifications()   -> sigue GRANT EXECUTE authenticated
