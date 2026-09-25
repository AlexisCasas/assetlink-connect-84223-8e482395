-- =========================================================================
-- Fase 1 · Punto 3 — Responsable predeterminado por activo.
--
-- Semántica: responsable de SEGUIMIENTO/GESTIÓN del activo (owner/admin/
-- manager). No es el técnico de una OT, ni el creador del activo, ni quien
-- reporta un aviso. Es un valor inicial para procesos NUEVOS: cada proceso
-- guarda después su propio responsable y nunca se sincroniza con el activo.
-- No hay herencia jerárquica: jamás se busca en parent_asset_id/ancestros.
--
-- No modifica migraciones anteriores. Cambios:
--   A) assets.default_responsible_member_id (FK ON DELETE SET NULL + índice),
--      sin backfill: todos los activos existentes quedan NULL.
--   B) is_eligible_follow_up_responsible — única regla de elegibilidad
--      (mismo tenant, activo, owner/admin/manager). Helper interno.
--   C) Trigger de integridad sobre assets: valida en INSERT o cuando cambia
--      el responsable u organization_id; un responsable histórico que luego
--      quedó inactivo NO bloquea editar otros campos del activo.
--   D) Auditoría server-side (asset_default_responsible_changed).
--   E) create_maintenance_notice (misma firma): hereda el responsable
--      elegible del activo y lo notifica (deduplicado por el índice único).
--   F) triage_maintenance_notice: nueva firma con p_clear_responsible (la
--      anterior de 4 argumentos se elimina) — corrige que "Sin asignar" no
--      desasignaba.
--   G) check_preventive_plan_consistency: el responsable se valida solo en
--      INSERT o cuando cambia (bug preexistente). Nada más cambia.
--   H) get_asset_integrated_history: solo añade la etiqueta del evento nuevo.
--
-- Seguridad: RLS de assets sin cambios; todos los helpers sin GRANT.
-- =========================================================================

-- =========================================================================
-- A) Columna
-- =========================================================================
ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS default_responsible_member_id uuid NULL
  REFERENCES public.organization_members(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_assets_default_responsible_member_id
  ON public.assets (default_responsible_member_id);

-- =========================================================================
-- B) Regla única de elegibilidad para un responsable de seguimiento.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.is_eligible_follow_up_responsible(
  p_member_id uuid,
  p_organization_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_member_id IS NOT NULL
    AND p_organization_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.id = p_member_id
        AND om.organization_id = p_organization_id
        AND om.is_active
        AND om.role IN ('owner', 'admin', 'manager')
    );
$$;

REVOKE ALL ON FUNCTION public.is_eligible_follow_up_responsible(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- C) Integridad: mismo tenant, activo y rol elegible — validado solo cuando
-- el valor se fija (INSERT) o cambia (responsable u organization_id). Un
-- UPDATE que no toca ninguno de los dos conserva la referencia histórica
-- aunque ese miembro haya quedado inactivo. Mensaje genérico: no revela si
-- el UUID existe en otro tenant.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.check_asset_default_responsible()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.default_responsible_member_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
    AND NEW.default_responsible_member_id IS NOT DISTINCT FROM OLD.default_responsible_member_id
    AND NEW.organization_id IS NOT DISTINCT FROM OLD.organization_id THEN
    RETURN NEW;
  END IF;

  IF NOT public.is_eligible_follow_up_responsible(NEW.default_responsible_member_id, NEW.organization_id) THEN
    RAISE EXCEPTION 'default_responsible_member_id must be an active owner/admin/manager of this organization';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.check_asset_default_responsible() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_assets_check_default_responsible ON public.assets;
CREATE TRIGGER trg_assets_check_default_responsible
BEFORE INSERT OR UPDATE OF default_responsible_member_id, organization_id ON public.assets
FOR EACH ROW EXECUTE FUNCTION public.check_asset_default_responsible();

-- =========================================================================
-- D) Auditoría server-side. Un evento por cambio REAL del valor. La
-- resolución de nombres es best-effort: si un miembro fue borrado o no se
-- puede resolver, el evento se registra igual con nombre NULL y nunca hace
-- fallar el UPDATE del activo.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.member_display_name(p_member_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name text;
BEGIN
  IF p_member_id IS NULL THEN
    RETURN NULL;
  END IF;
  BEGIN
    SELECT COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1))
      INTO v_name
      FROM public.organization_members om
      JOIN auth.users au ON au.id = om.user_id
     WHERE om.id = p_member_id;
  EXCEPTION WHEN OTHERS THEN
    v_name := NULL;
  END;
  RETURN v_name;
END;
$$;

REVOKE ALL ON FUNCTION public.member_display_name(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.log_asset_default_responsible_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_previous_name text := public.member_display_name(OLD.default_responsible_member_id);
  v_new_name text := public.member_display_name(NEW.default_responsible_member_id);
BEGIN
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    NEW.organization_id,
    NEW.id,
    'asset_default_responsible_changed',
    'Responsable predeterminado: '
      || CASE
           WHEN OLD.default_responsible_member_id IS NULL THEN 'Sin responsable'
           ELSE COALESCE(v_previous_name, 'Miembro no disponible')
         END
      || ' → '
      || CASE
           WHEN NEW.default_responsible_member_id IS NULL THEN 'Sin responsable'
           ELSE COALESCE(v_new_name, 'Miembro no disponible')
         END,
    jsonb_build_object(
      'previous_member_id', OLD.default_responsible_member_id,
      'new_member_id', NEW.default_responsible_member_id,
      'previous_name', v_previous_name,
      'new_name', v_new_name
    ),
    auth.uid()
  );
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.log_asset_default_responsible_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_assets_log_default_responsible_change ON public.assets;
CREATE TRIGGER trg_assets_log_default_responsible_change
AFTER UPDATE OF default_responsible_member_id ON public.assets
FOR EACH ROW
WHEN (OLD.default_responsible_member_id IS DISTINCT FROM NEW.default_responsible_member_id)
EXECUTE FUNCTION public.log_asset_default_responsible_change();

-- =========================================================================
-- E) create_maintenance_notice — MISMA firma y mismo comportamiento que en
-- 20260916120000, más:
--   - responsible_member_id = responsable predeterminado del activo SOLO si
--     sigue siendo elegible (revalidado aquí); si no, NULL;
--   - el aviso sigue naciendo 'open' y sin triaged_*;
--   - tras notify_role_members, notify_member al responsable heredado con el
--     MISMO type/entity_type/entity_id: el índice único de
--     organization_notifications deduplica si ya lo notificó por rol.
-- Aplica a avisos manuales y a los originados en una inspección.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.create_maintenance_notice(
  p_organization_id uuid,
  p_asset_id uuid,
  p_title text,
  p_description text,
  p_priority text DEFAULT 'medium',
  p_source_type text DEFAULT 'manual',
  p_source_id uuid DEFAULT NULL,
  p_source_item_id uuid DEFAULT NULL
)
RETURNS public.maintenance_notices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset public.assets%ROWTYPE;
  v_branch_id uuid;
  v_branch_name text;
  v_notice public.maintenance_notices%ROWTYPE;
  v_metadata jsonb := '{}'::jsonb;
  v_answer record;
  v_asset_label text;
  v_responsible_member_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.can_report_maintenance_notice(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to report maintenance notices for this organization';
  END IF;

  IF p_title IS NULL OR TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'El título del aviso es obligatorio';
  END IF;
  IF p_description IS NULL OR TRIM(p_description) = '' THEN
    RAISE EXCEPTION 'La descripción del aviso es obligatoria';
  END IF;
  IF p_priority IS NULL OR p_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'Prioridad inválida';
  END IF;
  IF p_source_type IS NULL OR p_source_type NOT IN ('manual', 'inspection_run') THEN
    RAISE EXCEPTION 'Origen inválido';
  END IF;

  SELECT a.* INTO v_asset FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset.id IS NULL THEN
    RAISE EXCEPTION 'El activo no existe';
  END IF;
  IF v_asset.organization_id <> p_organization_id THEN
    RAISE EXCEPTION 'El activo no pertenece a esta organización';
  END IF;

  IF p_source_type = 'inspection_run' THEN
    IF p_source_id IS NULL OR p_source_item_id IS NULL THEN
      RAISE EXCEPTION 'Un aviso originado en una inspección requiere la ejecución y el ítem';
    END IF;

    SELECT
      ira.is_failure,
      ira.item_question,
      ira.response_label,
      ir.organization_id AS run_organization_id,
      ct.name AS template_name
    INTO v_answer
    FROM public.inspection_run_answers ira
    INNER JOIN public.inspection_runs ir ON ir.id = ira.run_id
    INNER JOIN public.checklist_templates ct ON ct.id = ir.template_id
    WHERE ira.run_id = p_source_id AND ira.template_item_id = p_source_item_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se encontró la respuesta indicada en esa inspección';
    END IF;
    IF v_answer.run_organization_id <> p_organization_id THEN
      RAISE EXCEPTION 'La inspección no pertenece a esta organización';
    END IF;
    IF NOT v_answer.is_failure THEN
      RAISE EXCEPTION 'Solo se puede crear un aviso desde una respuesta marcada como no conformidad';
    END IF;

    v_metadata := jsonb_build_object(
      'template_name', v_answer.template_name,
      'item_id', p_source_item_id,
      'item_question', v_answer.item_question,
      'response_label', v_answer.response_label
    );
  END IF;

  v_branch_id := public.resolve_asset_branch(p_asset_id);
  SELECT cb.name INTO v_branch_name FROM public.client_branches cb WHERE cb.id = v_branch_id;

  -- Responsable predeterminado del PROPIO activo (sin herencia), solo si
  -- sigue siendo elegible en este momento.
  IF public.is_eligible_follow_up_responsible(v_asset.default_responsible_member_id, p_organization_id) THEN
    v_responsible_member_id := v_asset.default_responsible_member_id;
  END IF;

  INSERT INTO public.maintenance_notices AS mn (
    organization_id, notice_number, asset_id, title, description, priority, status,
    source_type, source_id, source_metadata,
    asset_name_snapshot, asset_code_snapshot, asset_path_snapshot,
    branch_id_snapshot, branch_name_snapshot,
    reported_by_user_id, responsible_member_id
  ) VALUES (
    p_organization_id,
    public.next_maintenance_notice_number(p_organization_id),
    p_asset_id,
    TRIM(p_title),
    TRIM(p_description),
    p_priority,
    'open',
    p_source_type,
    CASE WHEN p_source_type = 'manual' THEN NULL ELSE p_source_id END,
    v_metadata,
    v_asset.name,
    v_asset.code,
    public.resolve_asset_path(p_asset_id),
    v_branch_id,
    v_branch_name,
    auth.uid(),
    v_responsible_member_id
  ) RETURNING mn.* INTO v_notice;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    p_organization_id,
    p_asset_id,
    'maintenance_notice_created',
    v_notice.notice_number || ' — ' || v_notice.title,
    jsonb_build_object(
      'notice_id', v_notice.id,
      'notice_number', v_notice.notice_number,
      'priority', v_notice.priority
    ),
    auth.uid()
  );

  v_asset_label := COALESCE(NULLIF(TRIM(COALESCE(v_asset.code, '')), ''), v_asset.name);

  -- priority del aviso y de organization_notifications comparten exactamente
  -- los mismos 4 valores (low/medium/high/urgent): mapeo identidad, sin
  -- inventar ningún valor que el CHECK del schema no acepte.
  PERFORM public.notify_role_members(
    p_organization_id,
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
    auth.uid(),
    'maintenance_notice_created',
    'Nuevo aviso de avería',
    'Nuevo aviso ' || v_notice.notice_number || ' — ' || v_notice.title || ' en ' || v_asset_label || '.',
    'maintenance_notice',
    v_notice.id,
    v_notice.priority,
    jsonb_build_object(
      'notice_number', v_notice.notice_number,
      'priority', v_notice.priority,
      'asset_id', p_asset_id,
      'asset_name', v_asset.name,
      'asset_code', v_asset.code
    )
  );

  -- Mismo type/entity_type/entity_id que arriba: si el responsable ya fue
  -- notificado por su rol, idx_organization_notifications_targeted_dedup
  -- descarta este segundo insert (ON CONFLICT DO NOTHING).
  IF v_responsible_member_id IS NOT NULL THEN
    PERFORM public.notify_member(
      v_responsible_member_id,
      auth.uid(),
      'maintenance_notice_created',
      'Nuevo aviso de avería',
      'Nuevo aviso ' || v_notice.notice_number || ' — ' || v_notice.title || ' en ' || v_asset_label || '.',
      'maintenance_notice',
      v_notice.id,
      v_notice.priority,
      jsonb_build_object(
        'notice_number', v_notice.notice_number,
        'priority', v_notice.priority,
        'asset_id', p_asset_id,
        'asset_name', v_asset.name,
        'asset_code', v_asset.code
      )
    );
  END IF;

  RETURN v_notice;
END;
$$;

REVOKE ALL ON FUNCTION public.create_maintenance_notice(uuid, uuid, text, text, text, text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_maintenance_notice(uuid, uuid, text, text, text, text, uuid, uuid) TO authenticated;

-- =========================================================================
-- F) triage_maintenance_notice — nueva firma. La versión de 4 argumentos se
-- elimina explícitamente para que no coexistan dos sobrecargas.
--   p_clear_responsible = true        -> responsible_member_id = NULL
--   p_responsible_member_id = UUID    -> se valida (si cambia) y se asigna
--   ninguno de los dos                -> se conserva el actual, SIN
--                                        revalidarlo (un responsable que luego
--                                        quedó inactivo no bloquea el triage)
-- El resto (prioridad, notas, estados permitidos, permisos) no cambia.
-- =========================================================================
DROP FUNCTION IF EXISTS public.triage_maintenance_notice(uuid, text, text, uuid);

CREATE FUNCTION public.triage_maintenance_notice(
  p_notice_id uuid,
  p_priority text DEFAULT NULL,
  p_triage_notes text DEFAULT NULL,
  p_responsible_member_id uuid DEFAULT NULL,
  p_clear_responsible boolean DEFAULT false
)
RETURNS public.maintenance_notices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notice public.maintenance_notices%ROWTYPE;
  v_saved public.maintenance_notices%ROWTYPE;
  v_clear boolean := COALESCE(p_clear_responsible, false);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT mn.* INTO v_notice FROM public.maintenance_notices mn WHERE mn.id = p_notice_id;
  IF v_notice.id IS NULL THEN
    RAISE EXCEPTION 'El aviso no existe';
  END IF;

  IF NOT public.can_manage_maintenance_notice(v_notice.organization_id) THEN
    RAISE EXCEPTION 'Not authorized to triage maintenance notices for this organization';
  END IF;

  IF v_notice.status NOT IN ('open', 'triaged') THEN
    RAISE EXCEPTION 'Solo se puede revisar un aviso pendiente (estado actual: %)', v_notice.status;
  END IF;

  IF p_priority IS NOT NULL AND p_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'Prioridad inválida';
  END IF;

  IF v_clear AND p_responsible_member_id IS NOT NULL THEN
    RAISE EXCEPTION 'Indica un responsable o desasígnalo, pero no ambas cosas';
  END IF;

  -- Solo se valida un responsable que CAMBIA; conservar el actual no lo
  -- revalida. Mismo directorio que get_assignable_planners.
  IF p_responsible_member_id IS NOT NULL
    AND p_responsible_member_id IS DISTINCT FROM v_notice.responsible_member_id
    AND NOT public.is_eligible_follow_up_responsible(p_responsible_member_id, v_notice.organization_id) THEN
    RAISE EXCEPTION 'El responsable indicado no es un miembro activo con rol de seguimiento en esta organización';
  END IF;

  UPDATE public.maintenance_notices mn
  SET priority = COALESCE(p_priority, mn.priority),
      triage_notes = COALESCE(NULLIF(TRIM(COALESCE(p_triage_notes, '')), ''), mn.triage_notes),
      responsible_member_id = CASE
        WHEN v_clear THEN NULL
        WHEN p_responsible_member_id IS NOT NULL THEN p_responsible_member_id
        ELSE mn.responsible_member_id
      END,
      status = 'triaged',
      triaged_by_user_id = auth.uid(),
      triaged_at = now()
  WHERE mn.id = p_notice_id
  RETURNING mn.* INTO v_saved;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.triage_maintenance_notice(uuid, text, text, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.triage_maintenance_notice(uuid, text, text, uuid, boolean) TO authenticated;

-- =========================================================================
-- G) check_preventive_plan_consistency — idéntica a 20260918051511 salvo el
-- bloque del responsable: ahora se valida solo en INSERT o cuando cambian
-- responsible_member_id u organization_id. Un responsable que luego quedó
-- inactivo ya no impide desactivar/reactivar ni editar otros campos del
-- plan. Organización, activo, ficha, medidor y baseline se validan igual que
-- antes.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.check_preventive_plan_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_org_type public.organization_type;
  v_reading public.asset_meter_readings%ROWTYPE;
BEGIN
  SELECT o.organization_type INTO v_org_type FROM public.organizations o WHERE o.id = NEW.organization_id;
  IF v_org_type IS DISTINCT FROM 'client_company'::public.organization_type THEN
    RAISE EXCEPTION 'Preventive maintenance is only available to client_company organizations';
  END IF;
  SELECT a.organization_id INTO v_org FROM public.assets a WHERE a.id = NEW.asset_id;
  IF v_org IS NULL OR v_org <> NEW.organization_id THEN RAISE EXCEPTION 'asset_id must belong to this organization'; END IF;
  SELECT mc.organization_id INTO v_org FROM public.maintenance_cards mc WHERE mc.id = NEW.card_id;
  IF v_org IS NULL OR v_org <> NEW.organization_id THEN RAISE EXCEPTION 'card_id must belong to this organization'; END IF;
  IF NEW.responsible_member_id IS NOT NULL
    AND (
      TG_OP = 'INSERT'
      OR NEW.responsible_member_id IS DISTINCT FROM OLD.responsible_member_id
      OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
    )
    AND NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.id = NEW.responsible_member_id AND om.organization_id = NEW.organization_id
      AND om.is_active AND om.role IN ('owner', 'admin', 'manager')
  ) THEN
    RAISE EXCEPTION 'responsible_member_id must be an active owner/admin/manager of this organization';
  END IF;
  IF NEW.trigger_type = 'meter' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.asset_meters am
      WHERE am.id = NEW.meter_id AND am.organization_id = NEW.organization_id
        AND am.asset_id = NEW.asset_id AND am.is_active
    ) THEN RAISE EXCEPTION 'meter_id must be an active meter for this asset'; END IF;
    -- The baseline is resolved from an effective reading when the plan is
    -- created (or when a privileged direct write tries to replace it). A
    -- later correction deliberately voids that historical reading; it must
    -- not make unrelated mutable plan edits impossible afterwards.
    IF TG_OP = 'INSERT'
      OR NEW.baseline_reading_id IS DISTINCT FROM OLD.baseline_reading_id
      OR NEW.meter_id IS DISTINCT FROM OLD.meter_id THEN
      SELECT amr.* INTO v_reading FROM public.asset_meter_readings amr
      WHERE amr.id = NEW.baseline_reading_id AND amr.meter_id = NEW.meter_id AND amr.voided_at IS NULL;
      IF v_reading.id IS NULL THEN RAISE EXCEPTION 'baseline_reading_id must be an effective reading of this meter'; END IF;
      NEW.baseline_value := v_reading.value;
    ELSE
      NEW.baseline_value := OLD.baseline_value;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- =========================================================================
-- H) get_asset_integrated_history — definición más reciente
-- (20260918051511, wrapper sobre get_asset_integrated_history_before_preventive)
-- conservada exactamente; solo se añade la etiqueta del evento nuevo.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_asset_integrated_history(p_asset_id uuid)
RETURNS TABLE (
  id text,
  event_type text,
  event_label text,
  event_date timestamptz,
  actor_name text,
  actor_email text,
  source_table text,
  source_id uuid,
  title text,
  description text,
  status text,
  metadata jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    h.id,
    h.event_type,
    CASE ae.event_type
      WHEN 'preventive_plan_created' THEN 'Plan preventivo creado'
      WHEN 'meter_reading_recorded' THEN 'Lectura de medidor registrada'
      WHEN 'preventive_maintenance_planned' THEN 'Mantenimiento preventivo planificado'
      WHEN 'preventive_maintenance_completed' THEN 'Mantenimiento preventivo completado'
      WHEN 'preventive_maintenance_skipped' THEN 'Mantenimiento preventivo omitido'
      WHEN 'asset_default_responsible_changed' THEN 'Responsable predeterminado actualizado'
      ELSE h.event_label
    END,
    h.event_date,
    h.actor_name,
    h.actor_email,
    h.source_table,
    h.source_id,
    CASE ae.event_type
      WHEN 'preventive_plan_created' THEN 'Plan preventivo creado'
      WHEN 'meter_reading_recorded' THEN 'Lectura de medidor registrada'
      WHEN 'preventive_maintenance_planned' THEN 'Mantenimiento preventivo planificado'
      WHEN 'preventive_maintenance_completed' THEN 'Mantenimiento preventivo completado'
      WHEN 'preventive_maintenance_skipped' THEN 'Mantenimiento preventivo omitido'
      WHEN 'asset_default_responsible_changed' THEN 'Responsable predeterminado actualizado'
      ELSE h.title
    END,
    h.description,
    h.status,
    h.metadata
  FROM public.get_asset_integrated_history_before_preventive(p_asset_id) h
  LEFT JOIN public.asset_events ae
    ON h.source_table = 'asset_events' AND ae.id = h.source_id
  ORDER BY h.event_date DESC;
$$;

REVOKE ALL ON FUNCTION public.get_asset_integrated_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_asset_integrated_history(uuid) TO authenticated;
