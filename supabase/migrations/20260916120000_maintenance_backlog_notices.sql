-- Fase 21 — Backlog de mantenimiento / Avisos de avería.
--
-- PRINCIPIO: un aviso NO es una solicitud y NO es una orden de trabajo.
-- Dominio propio (maintenance_notices); nunca se reutiliza
-- requests(status='backlog'). Un aviso puede terminar CONVERTIDO en una
-- solicitud (converted_request_id), y esa solicitud sigue su flujo normal
-- (interna -> OT directa, externa -> cotizaciones -> OT) sin cambios.
--
-- Reutiliza infraestructura existente en vez de duplicarla:
--   - check_asset_child_organization() (20260826234732) como guardia de
--     consistencia tenant activo<->aviso;
--   - resolve_asset_path() (20260828170000) para el snapshot de ruta;
--   - notify_role_members() (20260829150000) para avisar a owner/admin/manager;
--   - asset_events + get_asset_integrated_history (20260829110000 y
--     posteriores) para el historial del activo — SIN una segunda UNION,
--     así un aviso nunca aparece dos veces;
--   - inspection_run_answers (20260829200000), que ya congela
--     item_question/response_label/is_failure, como fuente de verdad del
--     origen "inspección".
--
-- No modifica ninguna migración histórica.

-- =========================================================================
-- A) Correlativo AV-<año>-<6 dígitos>, único por organización y año.
--
-- No se reutiliza el patrón de work_order_number (secuencia GLOBAL
-- `work_order_number_seq`): esa produce una única serie compartida por todos
-- los tenants, y aquí el requisito es una serie propia por organización y
-- año (UNIQUE(organization_id, notice_number)). La tabla contador con
-- INSERT ... ON CONFLICT DO UPDATE ... RETURNING es concurrency-safe: el
-- UPDATE del conflicto toma un lock de fila, así que dos transacciones
-- simultáneas de la misma organización se serializan sobre esa fila y nunca
-- obtienen el mismo número (a diferencia de COUNT(*)+1 o MAX()+1, que sí
-- pueden colisionar).
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.maintenance_notice_counters (
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  year integer NOT NULL,
  last_number integer NOT NULL DEFAULT 0,
  PRIMARY KEY (organization_id, year)
);

-- Sin RLS ni GRANT: solo la RPC SECURITY DEFINER de abajo la toca.
ALTER TABLE public.maintenance_notice_counters ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.next_maintenance_notice_number(p_organization_id uuid)
RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_year integer := EXTRACT(YEAR FROM now())::integer;
  v_next integer;
BEGIN
  INSERT INTO public.maintenance_notice_counters AS mnc (organization_id, year, last_number)
  VALUES (p_organization_id, v_year, 1)
  ON CONFLICT (organization_id, year)
  DO UPDATE SET last_number = mnc.last_number + 1
  RETURNING mnc.last_number INTO v_next;

  RETURN 'AV-' || v_year::text || '-' || lpad(v_next::text, 6, '0');
END;
$$;

REVOKE ALL ON FUNCTION public.next_maintenance_notice_number(uuid) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- B) resolve_asset_branch — sede efectiva de un activo: la del propio activo
-- o, si no tiene, la del ancestro más cercano que sí la tenga (los nodos
-- hijos del árbol suelen heredar la sede del nodo de sede/área superior).
-- Mismo patrón recursivo que resolve_asset_path. Helper interno, sin GRANT.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.resolve_asset_branch(p_asset_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH RECURSIVE ancestry AS (
    SELECT a.id, a.parent_asset_id, a.branch_id, 0 AS depth
    FROM public.assets a
    WHERE a.id = p_asset_id
    UNION ALL
    SELECT parent.id, parent.parent_asset_id, parent.branch_id, ancestry.depth + 1
    FROM public.assets parent
    INNER JOIN ancestry ON ancestry.parent_asset_id = parent.id
  )
  SELECT ancestry.branch_id
  FROM ancestry
  WHERE ancestry.branch_id IS NOT NULL
  ORDER BY ancestry.depth ASC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.resolve_asset_branch(uuid) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- C) maintenance_notices
--
-- Los *_snapshot congelan cómo se veía el activo cuando se reportó el aviso
-- (nombre, código, ruta y SEDE). El snapshot de sede es indispensable: con
-- solo assets.branch_id, un aviso histórico "se mudaría" de sede al mover el
-- activo, y el backlog filtra justamente por sucursal. La criticidad NO se
-- congela a propósito: el backlog la muestra como contexto VIGENTE del
-- activo (se lee en vivo desde assets.criticality en get_maintenance_notices).
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.maintenance_notices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  notice_number text NOT NULL,

  asset_id uuid NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,

  title text NOT NULL,
  description text NOT NULL,

  priority text NOT NULL DEFAULT 'medium',
  status text NOT NULL DEFAULT 'open',

  source_type text NOT NULL DEFAULT 'manual',
  source_id uuid NULL,
  source_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  asset_name_snapshot text NULL,
  asset_code_snapshot text NULL,
  asset_path_snapshot text NULL,
  branch_id_snapshot uuid NULL REFERENCES public.client_branches(id) ON DELETE SET NULL,
  branch_name_snapshot text NULL,

  reported_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reported_at timestamptz NOT NULL DEFAULT now(),

  responsible_member_id uuid NULL REFERENCES public.organization_members(id) ON DELETE SET NULL,

  triage_notes text NULL,
  triaged_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  triaged_at timestamptz NULL,

  -- NO ACTION (no SET NULL): con SET NULL, borrar una solicitud dejaría el
  -- aviso en status='converted' sin converted_request_id y violaría
  -- maintenance_notices_converted_check. NO ACTION además se verifica al
  -- final de la sentencia, así que el CASCADE por borrado de organización
  -- (que elimina solicitudes y avisos juntos) sigue funcionando.
  converted_request_id uuid NULL REFERENCES public.requests(id) ON DELETE NO ACTION,
  converted_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  converted_at timestamptz NULL,

  dismissal_reason text NULL,
  dismissed_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  dismissed_at timestamptz NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT maintenance_notices_title_check CHECK (TRIM(title) <> ''),
  CONSTRAINT maintenance_notices_description_check CHECK (TRIM(description) <> ''),
  CONSTRAINT maintenance_notices_priority_check CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  CONSTRAINT maintenance_notices_status_check CHECK (status IN ('open', 'triaged', 'converted', 'dismissed')),
  CONSTRAINT maintenance_notices_source_type_check CHECK (source_type IN ('manual', 'inspection_run')),
  -- Un aviso convertido siempre apunta a su solicitud, y solo un aviso
  -- convertido lo hace. Descartado siempre lleva motivo.
  CONSTRAINT maintenance_notices_converted_check CHECK (
    (status = 'converted' AND converted_request_id IS NOT NULL)
    OR (status <> 'converted' AND converted_request_id IS NULL)
  ),
  CONSTRAINT maintenance_notices_dismissed_check CHECK (
    status <> 'dismissed' OR (dismissal_reason IS NOT NULL AND TRIM(dismissal_reason) <> '')
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_maintenance_notices_org_number
  ON public.maintenance_notices (organization_id, notice_number);

-- Consolidar varios avisos en una sola solicitud está fuera de alcance en
-- este MVP: la relación es 1 aviso <-> 1 solicitud, y este índice parcial la
-- impone a nivel de base (no solo en la RPC).
CREATE UNIQUE INDEX IF NOT EXISTS uq_maintenance_notices_converted_request
  ON public.maintenance_notices (converted_request_id)
  WHERE converted_request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_maintenance_notices_org_status
  ON public.maintenance_notices (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_maintenance_notices_org_priority
  ON public.maintenance_notices (organization_id, priority);
CREATE INDEX IF NOT EXISTS idx_maintenance_notices_reported_at
  ON public.maintenance_notices (organization_id, reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_maintenance_notices_asset_id
  ON public.maintenance_notices (asset_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_notices_branch_snapshot
  ON public.maintenance_notices (organization_id, branch_id_snapshot);

DROP TRIGGER IF EXISTS trg_maintenance_notices_updated_at ON public.maintenance_notices;
CREATE TRIGGER trg_maintenance_notices_updated_at
BEFORE UPDATE ON public.maintenance_notices
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Mismo guardia genérico que ya usan asset_documents/asset_events/
-- asset_criticality_assessments: organization_id debe coincidir con la
-- organización del asset_id. No hace falta una función nueva.
DROP TRIGGER IF EXISTS trg_maintenance_notices_check_org ON public.maintenance_notices;
CREATE TRIGGER trg_maintenance_notices_check_org
BEFORE INSERT OR UPDATE ON public.maintenance_notices
FOR EACH ROW EXECUTE FUNCTION public.check_asset_child_organization();

-- =========================================================================
-- D) RLS. Solo SELECT por policy; toda escritura pasa por las RPC
-- SECURITY DEFINER de abajo (mismo patrón que criticidad, inventario,
-- inspecciones). Cualquier miembro activo de la organización lee el backlog
-- (owner/admin/manager/technician/requester/viewer); un proveedor externo o
-- Cliente B no ven nada, ni conociendo el UUID.
-- =========================================================================
ALTER TABLE public.maintenance_notices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "organization members can view maintenance notices" ON public.maintenance_notices;
CREATE POLICY "organization members can view maintenance notices" ON public.maintenance_notices
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

GRANT SELECT ON TABLE public.maintenance_notices TO authenticated;

-- =========================================================================
-- E) can_report_maintenance_notice / can_manage_maintenance_notice —
-- los dos niveles de permiso del dominio, en un solo lugar para que las 4
-- RPC no repitan la regla.
--
--   reportar (crear): owner/admin/manager/technician/requester  (viewer NO)
--   gestionar (triage/descartar/convertir): owner/admin/manager
--
-- Ambos exigen además que la organización sea client_company: el backlog es
-- exclusivamente del cliente dueño de los activos.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.can_report_maintenance_notice(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.organizations o
      WHERE o.id = p_organization_id
        AND o.organization_type = 'client_company'
        AND o.status = 'active'
    )
    AND (
      public.is_platform_admin()
      OR public.has_organization_role(
        p_organization_id,
        ARRAY['owner', 'admin', 'manager', 'technician', 'requester']::public.organization_member_role[]
      )
    );
$$;

REVOKE ALL ON FUNCTION public.can_report_maintenance_notice(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.can_manage_maintenance_notice(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.organizations o
      WHERE o.id = p_organization_id
        AND o.organization_type = 'client_company'
        AND o.status = 'active'
    )
    AND (
      public.is_platform_admin()
      OR public.has_organization_role(
        p_organization_id,
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
      )
    );
$$;

REVOKE ALL ON FUNCTION public.can_manage_maintenance_notice(uuid) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- F) create_maintenance_notice
--
-- Los snapshots (nombre/código/ruta/sede) y la metadata de origen se
-- resuelven SIEMPRE desde la base, nunca desde strings enviados por React:
-- el frontend solo aporta ids y el texto del problema.
--
-- Para source_type='inspection_run', p_source_id es la ejecución y
-- p_source_item_id el ítem del checklist. Se valida contra
-- inspection_run_answers que la respuesta guardada de ESE ítem en ESA
-- ejecución sea realmente is_failure — no se confía en que el cliente diga
-- que lo era, y no se crean avisos automáticamente en ningún caso: esta RPC
-- solo corre cuando el usuario pulsa "Crear aviso".
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

  INSERT INTO public.maintenance_notices AS mn (
    organization_id, notice_number, asset_id, title, description, priority, status,
    source_type, source_id, source_metadata,
    asset_name_snapshot, asset_code_snapshot, asset_path_snapshot,
    branch_id_snapshot, branch_name_snapshot,
    reported_by_user_id
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
    auth.uid()
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

  RETURN v_notice;
END;
$$;

REVOKE ALL ON FUNCTION public.create_maintenance_notice(uuid, uuid, text, text, text, text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_maintenance_notice(uuid, uuid, text, text, text, text, uuid, uuid) TO authenticated;

-- =========================================================================
-- G) triage_maintenance_notice — revisar/priorizar. owner/admin/manager.
-- Parámetros NULL = "no cambiar ese campo". Re-triage de un aviso ya
-- triaged está permitido (actualiza y refresca triaged_by/at); un aviso
-- convertido o descartado ya no se puede triagear.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.triage_maintenance_notice(
  p_notice_id uuid,
  p_priority text DEFAULT NULL,
  p_triage_notes text DEFAULT NULL,
  p_responsible_member_id uuid DEFAULT NULL
)
RETURNS public.maintenance_notices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notice public.maintenance_notices%ROWTYPE;
  v_saved public.maintenance_notices%ROWTYPE;
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

  IF p_responsible_member_id IS NOT NULL THEN
    -- Mismo directorio real que ya usa get_assignable_planners para
    -- "responsable de seguimiento": owner/admin/manager activos del tenant.
    IF NOT EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.id = p_responsible_member_id
        AND om.organization_id = v_notice.organization_id
        AND om.is_active
        AND om.role IN ('owner', 'admin', 'manager')
    ) THEN
      RAISE EXCEPTION 'El responsable indicado no es un miembro activo con rol de seguimiento en esta organización';
    END IF;
  END IF;

  UPDATE public.maintenance_notices mn
  SET priority = COALESCE(p_priority, mn.priority),
      triage_notes = COALESCE(NULLIF(TRIM(COALESCE(p_triage_notes, '')), ''), mn.triage_notes),
      responsible_member_id = COALESCE(p_responsible_member_id, mn.responsible_member_id),
      status = 'triaged',
      triaged_by_user_id = auth.uid(),
      triaged_at = now()
  WHERE mn.id = p_notice_id
  RETURNING mn.* INTO v_saved;

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.triage_maintenance_notice(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.triage_maintenance_notice(uuid, text, text, uuid) TO authenticated;

-- =========================================================================
-- H) dismiss_maintenance_notice — descartar con motivo obligatorio (texto
-- libre, nunca un enum cerrado). Nunca DELETE. Idempotente: descartar un
-- aviso ya descartado devuelve la fila tal cual, sin corromper estado ni
-- reabrir nada.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.dismiss_maintenance_notice(
  p_notice_id uuid,
  p_reason text
)
RETURNS public.maintenance_notices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notice public.maintenance_notices%ROWTYPE;
  v_saved public.maintenance_notices%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT mn.* INTO v_notice FROM public.maintenance_notices mn WHERE mn.id = p_notice_id;
  IF v_notice.id IS NULL THEN
    RAISE EXCEPTION 'El aviso no existe';
  END IF;

  IF NOT public.can_manage_maintenance_notice(v_notice.organization_id) THEN
    RAISE EXCEPTION 'Not authorized to dismiss maintenance notices for this organization';
  END IF;

  IF v_notice.status = 'dismissed' THEN
    RETURN v_notice;
  END IF;

  IF v_notice.status = 'converted' THEN
    RAISE EXCEPTION 'Un aviso ya convertido en solicitud no puede descartarse';
  END IF;

  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'El motivo del descarte es obligatorio';
  END IF;

  UPDATE public.maintenance_notices mn
  SET status = 'dismissed',
      dismissal_reason = TRIM(p_reason),
      dismissed_by_user_id = auth.uid(),
      dismissed_at = now()
  WHERE mn.id = p_notice_id
  RETURNING mn.* INTO v_saved;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_saved.organization_id,
    v_saved.asset_id,
    'maintenance_notice_dismissed',
    v_saved.notice_number || ' — descartado: ' || v_saved.dismissal_reason,
    jsonb_build_object(
      'notice_id', v_saved.id,
      'notice_number', v_saved.notice_number,
      'priority', v_saved.priority,
      'dismissal_reason', v_saved.dismissal_reason
    ),
    auth.uid()
  );

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.dismiss_maintenance_notice(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dismiss_maintenance_notice(uuid, text) TO authenticated;

-- =========================================================================
-- I) convert_maintenance_notice — vincula un aviso con la solicitud que ya
-- fue guardada por el flujo normal de solicitudes. Esta RPC NO crea la
-- solicitud: el frontend reutiliza exactamente la misma persistencia que
-- RequestList (requests + request_details + set_request_audience + promoción
-- a 'sent') y solo después llama aquí.
--
-- IDEMPOTENTE a propósito: si la solicitud se guardó bien pero esta llamada
-- falló por red, reintentarla con el MISMO request_id devuelve la fila sin
-- error (no-op) — así el usuario nunca necesita crear una segunda solicitud.
-- Con un request_id distinto, en cambio, falla: un aviso se convierte una
-- sola vez.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.convert_maintenance_notice(
  p_notice_id uuid,
  p_request_id uuid
)
RETURNS public.maintenance_notices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notice public.maintenance_notices%ROWTYPE;
  v_request public.requests%ROWTYPE;
  v_saved public.maintenance_notices%ROWTYPE;
  v_other_notice_number text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT mn.* INTO v_notice FROM public.maintenance_notices mn WHERE mn.id = p_notice_id FOR UPDATE;
  IF v_notice.id IS NULL THEN
    RAISE EXCEPTION 'El aviso no existe';
  END IF;

  IF NOT public.can_manage_maintenance_notice(v_notice.organization_id) THEN
    RAISE EXCEPTION 'Not authorized to convert maintenance notices for this organization';
  END IF;

  -- Reintento seguro de la MISMA conversión: no-op exitoso.
  IF v_notice.status = 'converted' THEN
    IF v_notice.converted_request_id = p_request_id THEN
      RETURN v_notice;
    END IF;
    RAISE EXCEPTION 'Este aviso ya fue convertido en otra solicitud';
  END IF;

  IF v_notice.status <> 'open' AND v_notice.status <> 'triaged' THEN
    RAISE EXCEPTION 'Solo un aviso pendiente puede convertirse (estado actual: %)', v_notice.status;
  END IF;

  SELECT r.* INTO v_request FROM public.requests r WHERE r.id = p_request_id;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'La solicitud no existe';
  END IF;
  IF v_request.organization_id IS DISTINCT FROM v_notice.organization_id THEN
    RAISE EXCEPTION 'La solicitud pertenece a otra organización';
  END IF;
  IF v_request.asset_id IS DISTINCT FROM v_notice.asset_id THEN
    RAISE EXCEPTION 'La solicitud debe referirse al mismo activo del aviso';
  END IF;
  IF v_request.status = 'anulado' THEN
    RAISE EXCEPTION 'La solicitud está anulada';
  END IF;

  -- 1 aviso <-> 1 solicitud (consolidar varios avisos está fuera de alcance).
  SELECT mn.notice_number INTO v_other_notice_number
  FROM public.maintenance_notices mn
  WHERE mn.converted_request_id = p_request_id AND mn.id <> p_notice_id;

  IF v_other_notice_number IS NOT NULL THEN
    RAISE EXCEPTION 'Esa solicitud ya está vinculada al aviso %', v_other_notice_number;
  END IF;

  UPDATE public.maintenance_notices mn
  SET status = 'converted',
      converted_request_id = p_request_id,
      converted_by_user_id = auth.uid(),
      converted_at = now()
  WHERE mn.id = p_notice_id
  RETURNING mn.* INTO v_saved;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_saved.organization_id,
    v_saved.asset_id,
    'maintenance_notice_converted',
    v_saved.notice_number || ' — convertido en ' || COALESCE(v_request.request_number, 'solicitud'),
    jsonb_build_object(
      'notice_id', v_saved.id,
      'notice_number', v_saved.notice_number,
      'priority', v_saved.priority,
      'request_id', p_request_id,
      'request_number', v_request.request_number
    ),
    auth.uid()
  );

  RETURN v_saved;
END;
$$;

REVOKE ALL ON FUNCTION public.convert_maintenance_notice(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.convert_maintenance_notice(uuid, uuid) TO authenticated;

-- =========================================================================
-- J) get_maintenance_notices — el backlog completo de una organización, con
-- todo lo que la tabla necesita resuelto de una sola vez (nombres de
-- usuarios/responsable, número de la solicitud convertida y la criticidad
-- VIGENTE del activo como contexto). Orden: urgent > high > medium > low y,
-- dentro de cada prioridad, el más antiguo primero.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_maintenance_notices(p_organization_id uuid)
RETURNS TABLE (
  id uuid,
  organization_id uuid,
  notice_number text,
  asset_id uuid,
  title text,
  description text,
  priority text,
  status text,
  source_type text,
  source_id uuid,
  source_metadata jsonb,
  asset_name_snapshot text,
  asset_code_snapshot text,
  asset_path_snapshot text,
  branch_id_snapshot uuid,
  branch_name_snapshot text,
  asset_current_criticality text,
  reported_by_user_id uuid,
  reported_by_name text,
  reported_at timestamptz,
  responsible_member_id uuid,
  responsible_name text,
  triage_notes text,
  triaged_by_name text,
  triaged_at timestamptz,
  converted_request_id uuid,
  converted_request_number text,
  converted_by_name text,
  converted_at timestamptz,
  dismissal_reason text,
  dismissed_by_name text,
  dismissed_at timestamptz,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view the maintenance backlog for this organization';
  END IF;

  RETURN QUERY
  SELECT
    mn.id,
    mn.organization_id,
    mn.notice_number,
    mn.asset_id,
    mn.title,
    mn.description,
    mn.priority,
    mn.status,
    mn.source_type,
    mn.source_id,
    mn.source_metadata,
    mn.asset_name_snapshot,
    mn.asset_code_snapshot,
    mn.asset_path_snapshot,
    mn.branch_id_snapshot,
    mn.branch_name_snapshot,
    a.criticality AS asset_current_criticality,
    mn.reported_by_user_id,
    COALESCE(NULLIF(TRIM(reporter.raw_user_meta_data->>'name'), ''), split_part(reporter.email, '@', 1)) AS reported_by_name,
    mn.reported_at,
    mn.responsible_member_id,
    COALESCE(NULLIF(TRIM(responsible_user.raw_user_meta_data->>'name'), ''), split_part(responsible_user.email, '@', 1)) AS responsible_name,
    mn.triage_notes,
    COALESCE(NULLIF(TRIM(triager.raw_user_meta_data->>'name'), ''), split_part(triager.email, '@', 1)) AS triaged_by_name,
    mn.triaged_at,
    mn.converted_request_id,
    r.request_number AS converted_request_number,
    COALESCE(NULLIF(TRIM(converter.raw_user_meta_data->>'name'), ''), split_part(converter.email, '@', 1)) AS converted_by_name,
    mn.converted_at,
    mn.dismissal_reason,
    COALESCE(NULLIF(TRIM(dismisser.raw_user_meta_data->>'name'), ''), split_part(dismisser.email, '@', 1)) AS dismissed_by_name,
    mn.dismissed_at,
    mn.created_at
  FROM public.maintenance_notices mn
  INNER JOIN public.assets a ON a.id = mn.asset_id
  LEFT JOIN auth.users reporter ON reporter.id = mn.reported_by_user_id
  LEFT JOIN auth.users triager ON triager.id = mn.triaged_by_user_id
  LEFT JOIN auth.users converter ON converter.id = mn.converted_by_user_id
  LEFT JOIN auth.users dismisser ON dismisser.id = mn.dismissed_by_user_id
  LEFT JOIN public.organization_members responsible_member ON responsible_member.id = mn.responsible_member_id
  LEFT JOIN auth.users responsible_user ON responsible_user.id = responsible_member.user_id
  LEFT JOIN public.requests r ON r.id = mn.converted_request_id
  WHERE mn.organization_id = p_organization_id
  ORDER BY
    CASE mn.priority
      WHEN 'urgent' THEN 1
      WHEN 'high' THEN 2
      WHEN 'medium' THEN 3
      ELSE 4
    END,
    mn.reported_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_maintenance_notices(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_maintenance_notices(uuid) TO authenticated;

-- =========================================================================
-- K) get_asset_integrated_history: los avisos de avería entran al historial
-- del activo por el MISMO camino que criticidad e inspecciones — la rama
-- genérica de asset_events que ya existe. NO se agrega una UNION nueva
-- leyendo maintenance_notices: eso mostraría cada aviso dos veces (una por
-- la fila de asset_events que insertan las RPC de arriba y otra por la
-- tabla). Lo único que cambia respecto de la definición de
-- 20260829200000_generic_checklists_inspections.sql son las tres etiquetas
-- nuevas del CASE; todas las demás ramas quedan idénticas.
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
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset_org uuid;
  v_is_owner_or_platform_admin boolean;
  v_is_operating_provider boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.organization_id INTO v_asset_org FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset_org IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  v_is_owner_or_platform_admin := public.is_platform_admin() OR public.is_organization_member(v_asset_org);

  v_is_operating_provider := EXISTS (
    SELECT 1 FROM public.work_orders wo
    WHERE wo.asset_id = p_asset_id AND public.is_organization_member(wo.provider_organization_id)
  );

  IF NOT (v_is_owner_or_platform_admin OR v_is_operating_provider) THEN
    RAISE EXCEPTION 'Not authorized to view this asset history';
  END IF;

  RETURN QUERY

  SELECT
    'asset-created-' || a.id::text AS id,
    'asset_created'::text AS event_type,
    'Creación del activo'::text AS event_label,
    a.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'assets'::text AS source_table,
    a.id AS source_id,
    'Activo creado: ' || a.name AS title,
    a.description AS description,
    a.status::text AS status,
    jsonb_build_object('node_type', a.node_type, 'code', a.code) AS metadata
  FROM public.assets a
  LEFT JOIN auth.users au ON au.id = a.created_by_user_id
  WHERE a.id = p_asset_id
    AND v_is_owner_or_platform_admin
    AND NOT EXISTS (
      SELECT 1 FROM public.asset_events ae WHERE ae.asset_id = a.id AND ae.event_type = 'created'
    )

  UNION ALL

  SELECT
    'asset-event-' || ae.id::text AS id,
    'asset_event'::text AS event_type,
    (CASE ae.event_type
      WHEN 'created' THEN 'Activo creado'
      WHEN 'updated' THEN 'Activo actualizado'
      WHEN 'archived' THEN 'Activo archivado'
      WHEN 'restored' THEN 'Activo restaurado'
      WHEN 'criticality_assessed' THEN 'Criticidad evaluada'
      WHEN 'inspection_completed' THEN 'Inspección completada'
      WHEN 'maintenance_notice_created' THEN 'Aviso de avería creado'
      WHEN 'maintenance_notice_converted' THEN 'Aviso convertido en solicitud'
      WHEN 'maintenance_notice_dismissed' THEN 'Aviso descartado'
      ELSE INITCAP(REPLACE(ae.event_type, '_', ' '))
    END)::text AS event_label,
    ae.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'asset_events'::text AS source_table,
    ae.id AS source_id,
    (CASE ae.event_type
      WHEN 'created' THEN 'Activo creado'
      WHEN 'updated' THEN 'Activo actualizado'
      WHEN 'archived' THEN 'Activo archivado'
      WHEN 'restored' THEN 'Activo restaurado'
      WHEN 'criticality_assessed' THEN 'Criticidad evaluada'
      WHEN 'inspection_completed' THEN 'Inspección completada'
      WHEN 'maintenance_notice_created' THEN 'Aviso de avería creado'
      WHEN 'maintenance_notice_converted' THEN 'Aviso convertido en solicitud'
      WHEN 'maintenance_notice_dismissed' THEN 'Aviso descartado'
      ELSE INITCAP(REPLACE(ae.event_type, '_', ' '))
    END)::text AS title,
    ae.description AS description,
    NULL::text AS status,
    ae.payload AS metadata
  FROM public.asset_events ae
  LEFT JOIN auth.users au ON au.id = ae.created_by_user_id
  WHERE ae.asset_id = p_asset_id
    AND v_is_owner_or_platform_admin

  UNION ALL

  SELECT
    'request-' || r.id::text AS id,
    'request_created'::text AS event_type,
    'Solicitud creada'::text AS event_label,
    r.created_at AS event_date,
    r.created_by_name AS actor_name,
    r.created_by_email AS actor_email,
    'requests'::text AS source_table,
    r.id AS source_id,
    COALESCE(r.title, r.request_number) AS title,
    r.description AS description,
    r.status::text AS status,
    jsonb_build_object('request_number', r.request_number, 'request_type', r.request_type, 'priority', r.priority) AS metadata
  FROM public.requests r
  WHERE r.asset_id = p_asset_id
    AND v_is_owner_or_platform_admin

  UNION ALL

  SELECT
    'work-order-' || wo.id::text AS id,
    'work_order_created'::text AS event_type,
    'Orden de trabajo generada'::text AS event_label,
    wo.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_orders'::text AS source_table,
    wo.id AS source_id,
    wo.work_order_number || COALESCE(' — ' || wo.title, '') AS title,
    wo.description AS description,
    wo.status AS status,
    jsonb_build_object('work_order_number', wo.work_order_number, 'work_order_type', wo.work_order_type, 'priority', wo.priority) AS metadata
  FROM public.work_orders wo
  LEFT JOIN auth.users au ON au.id = wo.created_by_user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  SELECT
    'activity-' || woa.id::text AS id,
    'activity_created'::text AS event_type,
    'Actividad registrada'::text AS event_label,
    woa.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activities'::text AS source_table,
    woa.id AS source_id,
    woa.description AS title,
    NULL::text AS description,
    woa.status AS status,
    jsonb_build_object('estimated_hours', woa.estimated_hours, 'sequence', woa.sequence, 'work_order_number', wo.work_order_number) AS metadata
  FROM public.work_order_activities woa
  INNER JOIN public.work_orders wo ON wo.id = woa.work_order_id
  LEFT JOIN auth.users au ON au.id = woa.created_by_user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  SELECT
    'report-' || woar.id::text AS id,
    'technician_report'::text AS event_type,
    'Intervención de técnico'::text AS event_label,
    woar.started_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_reports'::text AS source_table,
    woar.id AS source_id,
    woa.description AS title,
    woar.observations AS description,
    woar.final_status AS status,
    jsonb_build_object(
      'work_order_number', wo.work_order_number,
      'activity_description', woa.description,
      'started_at', woar.started_at,
      'finished_at', woar.finished_at,
      'actual_hours', woar.actual_hours,
      'estimated_hours', woa.estimated_hours
    ) AS metadata
  FROM public.work_order_activity_reports woar
  INNER JOIN public.work_order_activities woa ON woa.id = woar.activity_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  SELECT
    'report-material-' || woarm.id::text AS id,
    'material_used'::text AS event_type,
    'Material utilizado'::text AS event_label,
    woarm.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_report_materials'::text AS source_table,
    woarm.id AS source_id,
    m.code || ' — ' || m.name AS title,
    woarm.notes AS description,
    NULL::text AS status,
    jsonb_build_object('quantity_used', woarm.quantity_used, 'unit', woarm.unit, 'material_code', m.code, 'material_name', m.name) AS metadata
  FROM public.work_order_activity_report_materials woarm
  INNER JOIN public.work_order_activity_reports woar ON woar.id = woarm.report_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.materials m ON m.id = woarm.material_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  SELECT
    'report-evidence-' || woare.id::text AS id,
    'evidence_added'::text AS event_type,
    'Evidencia registrada'::text AS event_label,
    woare.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_report_evidences'::text AS source_table,
    woare.id AS source_id,
    woare.file_name AS title,
    woare.notes AS description,
    NULL::text AS status,
    jsonb_build_object('file_name', woare.file_name, 'file_url', woare.file_url, 'mime_type', woare.mime_type) AS metadata
  FROM public.work_order_activity_report_evidences woare
  INNER JOIN public.work_order_activity_reports woar ON woar.id = woare.report_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  ORDER BY event_date DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_asset_integrated_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_asset_integrated_history(uuid) TO authenticated;
