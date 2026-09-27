-- =========================================================================
-- Fase 1 · Punto 9A — Fundación backend de permisos delegados
-- Cliente -> Facility Manager.
--
-- Semántica (sin roles nuevos):
--   organization_relationships.source_organization_id = cliente
--   organization_relationships.target_organization_id = Facility Manager
--   relationship_type = 'facility_management'
-- La relación define QUÉ empresa FM fue delegada y con qué capacidades
-- (facility_management_permissions). Los roles internos del FM siguen
-- definiendo QUIÉN es cada miembro dentro de esa empresa.
--
-- Esta migración NO amplía todavía las RLS de ningún módulo funcional
-- (assets, requests, preventivo, inspecciones, avisos...). Eso se hará
-- módulo por módulo sobre has_facility_management_permission().
--
-- Tres capas: (1) relación empresa cliente -> empresa FM, (2) permisos
-- delegados a la empresa FM, (3) miembros concretos del FM asignados a la
-- relación. Solo un miembro asignado y activo obtiene acceso operativo.
--
-- Convención de SQLSTATE para errores funcionales deliberados (las pruebas
-- dependen del código, nunca del texto):
--   42501 insufficient_privilege          — no autenticado / no autorizado
--   22023 invalid_parameter_value         — organizaciones/relación inválidas
--   P0002 no_data_found                   — relación inexistente
--   55000 object_not_in_prerequisite_state — transición/estado no permitido
--   23514 check_violation                 — invariante de los triggers
--
-- Ver docs/FACILITY_MANAGER_DELEGATED_PERMISSIONS.md.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A) Catálogo cerrado de capacidades delegables
-- -------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.facility_management_permission AS ENUM (
    'assets.view',
    'assets.manage',
    'criticality.view',
    'criticality.manage',
    'inspections.view',
    'inspections.manage',
    'preventive_maintenance.view',
    'preventive_maintenance.manage',
    'maintenance_notices.view',
    'maintenance_notices.report',
    'maintenance_notices.manage',
    'requests.view',
    'requests.create',
    'requests.manage',
    'providers.manage',
    'quotes.view',
    'quotes.manage',
    'quotes.approve',
    'work_orders.view',
    'work_orders.manage',
    'reports.view'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- -------------------------------------------------------------------------
-- B) facility_management_permissions — cliente y FM se resuelven SIEMPRE
--    desde organization_relationships; no se duplican aquí.
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.facility_management_permissions (
  relationship_id uuid NOT NULL REFERENCES public.organization_relationships(id) ON DELETE CASCADE,
  permission public.facility_management_permission NOT NULL,
  granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, permission)
);

-- has_facility_management_permission() filtra por permiso y luego resuelve
-- la relación: el índice empieza por permission.
CREATE INDEX IF NOT EXISTS idx_facility_management_permissions_permission_relationship
  ON public.facility_management_permissions (permission, relationship_id);

ALTER TABLE public.facility_management_permissions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.facility_management_permissions FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.facility_management_permissions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.facility_management_permissions TO service_role;

DROP POLICY IF EXISTS "relationship members can view facility management permissions" ON public.facility_management_permissions;
CREATE POLICY "relationship members can view facility management permissions" ON public.facility_management_permissions
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR EXISTS (
      SELECT 1
      FROM public.organization_relationships rel
      WHERE rel.id = facility_management_permissions.relationship_id
        AND (
          public.is_organization_member(rel.source_organization_id)
          OR public.is_organization_member(rel.target_organization_id)
        )
    )
  );
-- Sin policies INSERT/UPDATE/DELETE: toda escritura cliente pasa por
-- set_facility_management_permissions / set_facility_management_relationship_status.

-- -------------------------------------------------------------------------
-- B.2) facility_management_relationship_members — tercera capa: QUÉ
--      personas concretas del FM atienden a ese cliente. La identidad no
--      cambia: siguen siendo miembros únicamente de su FM. No se duplican
--      cliente, FM, user_id ni role: todo se resuelve desde
--      organization_relationships / organization_members.
--
--      Superficie de lectura exclusivamente RPC (get_facility_management_members,
--      get_my_facility_management_portfolio): la tabla asocia personas con
--      clientes, así que authenticated no recibe ni SELECT directo. RLS
--      habilitado sin policies como defensa en profundidad.
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.facility_management_relationship_members (
  relationship_id uuid NOT NULL REFERENCES public.organization_relationships(id) ON DELETE CASCADE,
  organization_member_id uuid NOT NULL REFERENCES public.organization_members(id) ON DELETE CASCADE,
  assigned_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, organization_member_id)
);

-- El helper y get_my_facility_management_clients parten de la membresía
-- del llamante.
CREATE INDEX IF NOT EXISTS idx_facility_management_relationship_members_member_relationship
  ON public.facility_management_relationship_members (organization_member_id, relationship_id);

ALTER TABLE public.facility_management_relationship_members ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.facility_management_relationship_members FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.facility_management_relationship_members TO service_role;

-- -------------------------------------------------------------------------
-- C) Invariantes de organization_relationships (solo facility_management)
--
-- No exige status='active' de las organizaciones: una organización puede
-- suspenderse después de creada la relación. La activación sí lo exige,
-- pero en la RPC de estado, no aquí.
--
-- Además de los tipos, para filas facility_management:
--   - INSERT nace en 'pending' (la delegación siempre empieza sin efecto);
--   - cliente/FM/tipo son inmutables (los permisos se concedieron a ESA
--     empresa FM para ESE cliente);
--   - las transiciones de status respetan la máquina de estados, sin
--     importar quién escriba (incluida la RPC legacy de homologación
--     set_provider_relationship_status, cuyas transiciones de UI ya caben
--     dentro de esta máquina).
-- Las relaciones provider/subcontracting no se tocan.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_facility_management_relationship()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_source_type public.organization_type;
  v_target_type public.organization_type;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.relationship_type = 'facility_management' THEN
    IF NEW.relationship_type IS DISTINCT FROM OLD.relationship_type
      OR NEW.source_organization_id IS DISTINCT FROM OLD.source_organization_id
      OR NEW.target_organization_id IS DISTINCT FROM OLD.target_organization_id THEN
      RAISE EXCEPTION 'A facility management relationship cannot change its organizations or type'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
      (OLD.status = 'pending' AND NEW.status IN ('active', 'suspended', 'ended'))
      OR (OLD.status = 'active' AND NEW.status IN ('suspended', 'ended'))
      OR (OLD.status = 'suspended' AND NEW.status IN ('active', 'ended'))
      OR (OLD.status = 'ended' AND NEW.status = 'pending')
    ) THEN
      RAISE EXCEPTION 'Invalid facility management relationship transition: % -> %', OLD.status, NEW.status
        USING ERRCODE = '55000';
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.relationship_type <> 'facility_management' THEN
    RETURN NEW;
  END IF;

  IF NEW.source_organization_id = NEW.target_organization_id THEN
    RAISE EXCEPTION 'A facility management relationship requires two different organizations'
      USING ERRCODE = '23514';
  END IF;

  SELECT o.organization_type INTO v_source_type FROM public.organizations o WHERE o.id = NEW.source_organization_id;
  SELECT o.organization_type INTO v_target_type FROM public.organizations o WHERE o.id = NEW.target_organization_id;

  IF v_source_type IS DISTINCT FROM 'client_company' THEN
    RAISE EXCEPTION 'The source of a facility management relationship must be a client_company'
      USING ERRCODE = '23514';
  END IF;

  IF v_target_type IS DISTINCT FROM 'facility_manager' THEN
    RAISE EXCEPTION 'The target of a facility management relationship must be a facility_manager'
      USING ERRCODE = '23514';
  END IF;

  -- Solo si la fila realmente es nueva: un INSERT ... ON CONFLICT DO UPDATE
  -- (la RPC legacy set_provider_relationship_status) dispara este BEFORE
  -- INSERT con el status propuesto aunque termine siendo un UPDATE; en ese
  -- caso la máquina de estados la aplica la rama UPDATE de este trigger.
  IF TG_OP = 'INSERT' AND NEW.status <> 'pending' AND NOT EXISTS (
    SELECT 1 FROM public.organization_relationships existing
    WHERE existing.source_organization_id = NEW.source_organization_id
      AND existing.target_organization_id = NEW.target_organization_id
      AND existing.relationship_type = NEW.relationship_type
  ) THEN
    RAISE EXCEPTION 'A facility management relationship must be created as pending'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_organization_relationships_check_facility_management ON public.organization_relationships;
CREATE TRIGGER trg_organization_relationships_check_facility_management
  BEFORE INSERT OR UPDATE ON public.organization_relationships
  FOR EACH ROW EXECUTE FUNCTION public.check_facility_management_relationship();

-- Una relación terminada nunca conserva permisos ni miembros asignados,
-- sin importar quién la termine (RPCs nuevas, RPC legacy de homologación o
-- service_role). ended -> pending no restaura nada: la relación reabierta
-- empieza completamente limpia. suspended conserva ambos (el acceso
-- efectivo ya es false porque el helper exige status = 'active').
CREATE OR REPLACE FUNCTION public.clear_ended_facility_management_delegation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.relationship_type = 'facility_management'
    AND NEW.status = 'ended'
    AND OLD.status IS DISTINCT FROM 'ended' THEN
    DELETE FROM public.facility_management_permissions fmp WHERE fmp.relationship_id = NEW.id;
    DELETE FROM public.facility_management_relationship_members fmrm WHERE fmrm.relationship_id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_organization_relationships_clear_ended_fm_delegation ON public.organization_relationships;
CREATE TRIGGER trg_organization_relationships_clear_ended_fm_delegation
  AFTER UPDATE OF status ON public.organization_relationships
  FOR EACH ROW EXECUTE FUNCTION public.clear_ended_facility_management_delegation();

-- Una asignación solo puede unir una relación facility_management no
-- terminada con un miembro ACTIVO de exactamente el FM target. La
-- actividad se exige solo al asignar: si la membresía se desactiva
-- después, la fila se conserva pero el acceso efectivo cae a false de
-- inmediato (el helper exige membership.is_active), y vuelve si se
-- reactiva. SECURITY INVOKER: todos los escritores legítimos (RPCs
-- SECURITY DEFINER, service_role) ya pueden leer las tablas consultadas.
CREATE OR REPLACE FUNCTION public.check_facility_management_relationship_member()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_relationship public.organization_relationships%ROWTYPE;
  v_target_type public.organization_type;
  v_member public.organization_members%ROWTYPE;
BEGIN
  SELECT * INTO v_relationship FROM public.organization_relationships rel WHERE rel.id = NEW.relationship_id;
  IF v_relationship.id IS NULL THEN
    RAISE EXCEPTION 'Relationship does not exist' USING ERRCODE = '23514';
  END IF;
  IF v_relationship.relationship_type <> 'facility_management' THEN
    RAISE EXCEPTION 'Members can only be assigned to a facility_management relationship' USING ERRCODE = '23514';
  END IF;
  IF v_relationship.status = 'ended' THEN
    RAISE EXCEPTION 'An ended facility management relationship cannot hold assigned members' USING ERRCODE = '23514';
  END IF;

  SELECT o.organization_type INTO v_target_type FROM public.organizations o WHERE o.id = v_relationship.target_organization_id;
  IF v_target_type IS DISTINCT FROM 'facility_manager' THEN
    RAISE EXCEPTION 'The relationship target must be a facility_manager' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_member FROM public.organization_members om WHERE om.id = NEW.organization_member_id;
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Organization member does not exist' USING ERRCODE = '23514';
  END IF;
  IF v_member.organization_id <> v_relationship.target_organization_id THEN
    RAISE EXCEPTION 'Only members of the facility manager can be assigned to this relationship' USING ERRCODE = '23514';
  END IF;
  IF NOT v_member.is_active THEN
    RAISE EXCEPTION 'Only active members can be assigned' USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_facility_management_relationship_members_check ON public.facility_management_relationship_members;
CREATE TRIGGER trg_facility_management_relationship_members_check
  BEFORE INSERT OR UPDATE ON public.facility_management_relationship_members
  FOR EACH ROW EXECUTE FUNCTION public.check_facility_management_relationship_member();

-- Un permiso solo puede colgar de una relación facility_management no
-- terminada.
CREATE OR REPLACE FUNCTION public.check_facility_management_permission_relationship()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_type public.organization_relationship_type;
  v_status public.organization_relationship_status;
BEGIN
  SELECT rel.relationship_type, rel.status INTO v_type, v_status
  FROM public.organization_relationships rel
  WHERE rel.id = NEW.relationship_id;

  IF v_type IS DISTINCT FROM 'facility_management' THEN
    RAISE EXCEPTION 'Facility management permissions require a facility_management relationship'
      USING ERRCODE = '23514';
  END IF;

  IF v_status = 'ended' THEN
    RAISE EXCEPTION 'An ended facility management relationship cannot hold permissions'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_facility_management_permissions_check_relationship ON public.facility_management_permissions;
CREATE TRIGGER trg_facility_management_permissions_check_relationship
  BEFORE INSERT OR UPDATE ON public.facility_management_permissions
  FOR EACH ROW EXECUTE FUNCTION public.check_facility_management_permission_relationship();

-- -------------------------------------------------------------------------
-- D) Hardening de organization_relationships: ACL explícito + sin
--    policies de escritura directa (se conserva la de lectura).
-- -------------------------------------------------------------------------
REVOKE ALL ON TABLE public.organization_relationships FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.organization_relationships TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.organization_relationships TO service_role;

DROP POLICY IF EXISTS "source organization administrators can create relationships" ON public.organization_relationships;
DROP POLICY IF EXISTS "source organization administrators can update relationships" ON public.organization_relationships;
DROP POLICY IF EXISTS "source organization administrators can delete relationships" ON public.organization_relationships;

-- -------------------------------------------------------------------------
-- E.1) has_facility_management_permission — el helper que usarán las RLS
--      de cada módulo. Solo auth.uid(); nunca recibe user_id, FM id ni
--      membership id. Responde únicamente: "¿este usuario concreto está
--      ASIGNADO a una relación activa con este cliente y su FM recibió este
--      permiso?". No evalúa el rol interno (eso lo combina cada módulo), y
--      no concede nada por ser owner/admin del FM ni platform_admin.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_facility_management_permission(
  _client_organization_id uuid,
  _permission public.facility_management_permission
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.organizations client
    JOIN public.organization_relationships rel
      ON rel.source_organization_id = client.id
     AND rel.relationship_type = 'facility_management'
     AND rel.status = 'active'
    JOIN public.organizations fm
      ON fm.id = rel.target_organization_id
     AND fm.organization_type = 'facility_manager'
     AND fm.status = 'active'
    JOIN public.organization_members membership
      ON membership.organization_id = fm.id
     AND membership.user_id = auth.uid()
     AND membership.is_active
    JOIN public.facility_management_relationship_members assignment
      ON assignment.relationship_id = rel.id
     AND assignment.organization_member_id = membership.id
    JOIN public.facility_management_permissions fmp
      ON fmp.relationship_id = rel.id
     AND fmp.permission = _permission
    WHERE client.id = _client_organization_id
      AND client.organization_type = 'client_company'
      AND client.status = 'active'
  );
$$;

-- -------------------------------------------------------------------------
-- E.2) create_facility_management_relationship — owner/admin del cliente o
--      platform_admin. Idempotente: si ya existe devuelve su id sin tocar
--      su status (nunca reactiva silenciosamente suspended/ended).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_facility_management_relationship(
  _client_organization_id uuid,
  _facility_manager_organization_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_relationship_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(_client_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to delegate this organization to a facility manager' USING ERRCODE = '42501';
  END IF;

  IF _client_organization_id IS NULL OR _facility_manager_organization_id IS NULL
    OR _client_organization_id = _facility_manager_organization_id THEN
    RAISE EXCEPTION 'Client and facility manager must be two different organizations' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organizations o
    WHERE o.id = _client_organization_id AND o.organization_type = 'client_company' AND o.status = 'active'
  ) THEN
    RAISE EXCEPTION '_client_organization_id must reference an active client company' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organizations o
    WHERE o.id = _facility_manager_organization_id AND o.organization_type = 'facility_manager' AND o.status = 'active'
  ) THEN
    RAISE EXCEPTION '_facility_manager_organization_id must reference an active facility manager' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.organization_relationships (
    source_organization_id, target_organization_id, relationship_type, status, created_by
  ) VALUES (
    _client_organization_id, _facility_manager_organization_id, 'facility_management', 'pending', v_actor
  )
  ON CONFLICT (source_organization_id, target_organization_id, relationship_type) DO NOTHING
  RETURNING id INTO v_relationship_id;

  IF v_relationship_id IS NULL THEN
    SELECT rel.id INTO v_relationship_id
    FROM public.organization_relationships rel
    WHERE rel.source_organization_id = _client_organization_id
      AND rel.target_organization_id = _facility_manager_organization_id
      AND rel.relationship_type = 'facility_management';
    RETURN v_relationship_id;
  END IF;

  INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, old_data, new_data)
  VALUES (
    _client_organization_id, v_actor, 'organization_relationships', v_relationship_id,
    'facility_management.relationship_created', NULL,
    jsonb_build_object(
      'client_organization_id', _client_organization_id,
      'facility_manager_organization_id', _facility_manager_organization_id,
      'status', 'pending'
    )
  );

  RETURN v_relationship_id;
END;
$$;

-- -------------------------------------------------------------------------
-- E.3) set_facility_management_permissions — reemplazo atómico del set.
--      Solo owner/admin del cliente (source) o platform_admin; el FM nunca
--      se concede permisos a sí mismo.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_facility_management_permissions(
  _relationship_id uuid,
  _permissions public.facility_management_permission[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_relationship public.organization_relationships%ROWTYPE;
  v_old public.facility_management_permission[];
  v_new public.facility_management_permission[];
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;

  -- FOR UPDATE: serializa con cambios de status concurrentes (p. ej. un
  -- ended en paralelo no puede dejar permisos huérfanos).
  SELECT * INTO v_relationship
  FROM public.organization_relationships rel
  WHERE rel.id = _relationship_id
  FOR UPDATE;

  IF v_relationship.id IS NULL THEN
    RAISE EXCEPTION 'Relationship not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_relationship.source_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to configure this facility management relationship' USING ERRCODE = '42501';
  END IF;

  IF v_relationship.relationship_type <> 'facility_management' THEN
    RAISE EXCEPTION 'Permissions can only be configured on a facility_management relationship' USING ERRCODE = '22023';
  END IF;

  IF v_relationship.status = 'ended' THEN
    RAISE EXCEPTION 'An ended relationship must be moved back to pending before configuring permissions' USING ERRCODE = '55000';
  END IF;

  SELECT COALESCE(array_agg(fmp.permission ORDER BY fmp.permission), '{}')
  INTO v_old
  FROM public.facility_management_permissions fmp
  WHERE fmp.relationship_id = _relationship_id;

  DELETE FROM public.facility_management_permissions fmp WHERE fmp.relationship_id = _relationship_id;

  INSERT INTO public.facility_management_permissions (relationship_id, permission, granted_by)
  SELECT DISTINCT _relationship_id, requested.permission, v_actor
  FROM unnest(COALESCE(_permissions, '{}'::public.facility_management_permission[])) AS requested(permission)
  WHERE requested.permission IS NOT NULL;

  SELECT COALESCE(array_agg(fmp.permission ORDER BY fmp.permission), '{}')
  INTO v_new
  FROM public.facility_management_permissions fmp
  WHERE fmp.relationship_id = _relationship_id;

  INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, old_data, new_data)
  VALUES (
    v_relationship.source_organization_id, v_actor, 'facility_management_permissions', _relationship_id,
    'facility_management.permissions_replaced',
    jsonb_build_object('permissions', to_jsonb(v_old)),
    jsonb_build_object('permissions', to_jsonb(v_new))
  );
END;
$$;

-- -------------------------------------------------------------------------
-- E.4) set_facility_management_relationship_status — máquina de estados:
--        pending   -> active | suspended | ended
--        active    -> suspended | ended
--        suspended -> active | ended
--        ended     -> pending
--      Mismo status = no-op. Activar exige cliente y FM activos. ended
--      borra los permisos (trigger); ended -> pending no los restaura.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_facility_management_relationship_status(
  _relationship_id uuid,
  _status public.organization_relationship_status
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_relationship public.organization_relationships%ROWTYPE;
  v_removed public.facility_management_permission[];
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_relationship
  FROM public.organization_relationships rel
  WHERE rel.id = _relationship_id
  FOR UPDATE;

  IF v_relationship.id IS NULL THEN
    RAISE EXCEPTION 'Relationship not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_relationship.source_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to change this facility management relationship' USING ERRCODE = '42501';
  END IF;

  IF v_relationship.relationship_type <> 'facility_management' THEN
    RAISE EXCEPTION 'Only facility_management relationships are managed here' USING ERRCODE = '22023';
  END IF;

  IF _status IS NULL THEN
    RAISE EXCEPTION 'A target status is required' USING ERRCODE = '22023';
  END IF;

  IF _status = v_relationship.status THEN
    RETURN;
  END IF;

  IF NOT (
    (v_relationship.status = 'pending' AND _status IN ('active', 'suspended', 'ended'))
    OR (v_relationship.status = 'active' AND _status IN ('suspended', 'ended'))
    OR (v_relationship.status = 'suspended' AND _status IN ('active', 'ended'))
    OR (v_relationship.status = 'ended' AND _status = 'pending')
  ) THEN
    RAISE EXCEPTION 'Invalid facility management relationship transition: % -> %', v_relationship.status, _status
      USING ERRCODE = '55000';
  END IF;

  IF _status = 'active' AND NOT (
    EXISTS (SELECT 1 FROM public.organizations o WHERE o.id = v_relationship.source_organization_id AND o.status = 'active')
    AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id = v_relationship.target_organization_id AND o.status = 'active')
  ) THEN
    RAISE EXCEPTION 'Both the client and the facility manager must be active to activate the relationship'
      USING ERRCODE = '55000';
  END IF;

  IF _status = 'ended' THEN
    SELECT COALESCE(array_agg(fmp.permission ORDER BY fmp.permission), '{}')
    INTO v_removed
    FROM public.facility_management_permissions fmp
    WHERE fmp.relationship_id = _relationship_id;
  END IF;

  UPDATE public.organization_relationships rel
  SET status = _status
  WHERE rel.id = _relationship_id;

  INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, old_data, new_data)
  VALUES (
    v_relationship.source_organization_id, v_actor, 'organization_relationships', _relationship_id,
    'facility_management.status_changed',
    jsonb_build_object('status', v_relationship.status),
    CASE WHEN _status = 'ended'
      THEN jsonb_build_object('status', _status, 'removed_permissions', to_jsonb(v_removed))
      ELSE jsonb_build_object('status', _status)
    END
  );
END;
$$;

-- -------------------------------------------------------------------------
-- E.5) get_facility_management_relationships — vista del cliente
--      (owner/admin) o de platform_admin.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_facility_management_relationships(
  _client_organization_id uuid
)
RETURNS TABLE (
  relationship_id uuid,
  client_organization_id uuid,
  client_organization_name text,
  facility_manager_organization_id uuid,
  facility_manager_organization_name text,
  relationship_status public.organization_relationship_status,
  permissions public.facility_management_permission[],
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(_client_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this organization''s facility managers' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    rel.id,
    client.id,
    client.name,
    fm.id,
    fm.name,
    rel.status,
    COALESCE(
      (SELECT array_agg(fmp.permission ORDER BY fmp.permission)
       FROM public.facility_management_permissions fmp
       WHERE fmp.relationship_id = rel.id),
      '{}'::public.facility_management_permission[]
    ),
    rel.created_at,
    rel.updated_at
  FROM public.organization_relationships rel
  JOIN public.organizations client ON client.id = rel.source_organization_id
  JOIN public.organizations fm ON fm.id = rel.target_organization_id
  WHERE rel.source_organization_id = _client_organization_id
    AND rel.relationship_type = 'facility_management'
  ORDER BY fm.name, rel.id;
END;
$$;

-- -------------------------------------------------------------------------
-- E.6) get_my_facility_management_clients — clientes OPERATIVOS del
--      usuario (no la cartera de su empresa): solo relaciones activas a
--      las que ESA membresía está asignada. Sin parámetros: nunca confía
--      en el tenant seleccionado en el frontend.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_facility_management_clients()
RETURNS TABLE (
  relationship_id uuid,
  client_organization_id uuid,
  client_organization_name text,
  facility_manager_organization_id uuid,
  facility_manager_organization_name text,
  membership_role public.organization_member_role,
  permissions public.facility_management_permission[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    rel.id,
    client.id,
    client.name,
    fm.id,
    fm.name,
    membership.role,
    COALESCE(
      (SELECT array_agg(fmp.permission ORDER BY fmp.permission)
       FROM public.facility_management_permissions fmp
       WHERE fmp.relationship_id = rel.id),
      '{}'::public.facility_management_permission[]
    )
  FROM public.organization_relationships rel
  JOIN public.organizations client
    ON client.id = rel.source_organization_id
   AND client.organization_type = 'client_company'
   AND client.status = 'active'
  JOIN public.organizations fm
    ON fm.id = rel.target_organization_id
   AND fm.organization_type = 'facility_manager'
   AND fm.status = 'active'
  JOIN public.organization_members membership
    ON membership.organization_id = fm.id
   AND membership.user_id = auth.uid()
   AND membership.is_active
  JOIN public.facility_management_relationship_members assignment
    ON assignment.relationship_id = rel.id
   AND assignment.organization_member_id = membership.id
  WHERE auth.uid() IS NOT NULL
    AND rel.relationship_type = 'facility_management'
    AND rel.status = 'active'
  ORDER BY client.name, fm.name, rel.id;
$$;

-- -------------------------------------------------------------------------
-- E.7) set_facility_management_members — el FM decide qué personas de SU
--      organización atienden a cada cliente. Solo owner/admin activos del
--      FM target o platform_admin. El cliente NO administra el roster del
--      FM (conserva suspender/terminar toda la relación para cortar acceso).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_facility_management_members(
  _relationship_id uuid,
  _organization_member_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_relationship public.organization_relationships%ROWTYPE;
  v_requested uuid[];
  v_old uuid[];
  v_new uuid[];
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_relationship
  FROM public.organization_relationships rel
  WHERE rel.id = _relationship_id
  FOR UPDATE;

  IF v_relationship.id IS NULL THEN
    RAISE EXCEPTION 'Relationship not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_relationship.target_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to assign members to this facility management relationship' USING ERRCODE = '42501';
  END IF;

  IF v_relationship.relationship_type <> 'facility_management' THEN
    RAISE EXCEPTION 'Members can only be assigned to a facility_management relationship' USING ERRCODE = '22023';
  END IF;

  IF v_relationship.status = 'ended' THEN
    RAISE EXCEPTION 'An ended relationship must be moved back to pending before assigning members' USING ERRCODE = '55000';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT requested.member_id ORDER BY requested.member_id), '{}')
  INTO v_requested
  FROM unnest(COALESCE(_organization_member_ids, '{}'::uuid[])) AS requested(member_id)
  WHERE requested.member_id IS NOT NULL;

  IF EXISTS (
    SELECT 1 FROM unnest(v_requested) AS requested(member_id)
    WHERE NOT EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.id = requested.member_id
        AND om.organization_id = v_relationship.target_organization_id
        AND om.is_active
    )
  ) THEN
    RAISE EXCEPTION 'Every assigned member must be an active member of the facility manager' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(array_agg(fmrm.organization_member_id ORDER BY fmrm.organization_member_id), '{}')
  INTO v_old
  FROM public.facility_management_relationship_members fmrm
  WHERE fmrm.relationship_id = _relationship_id;

  DELETE FROM public.facility_management_relationship_members fmrm WHERE fmrm.relationship_id = _relationship_id;

  INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id, assigned_by)
  SELECT _relationship_id, requested.member_id, v_actor
  FROM unnest(v_requested) AS requested(member_id);

  v_new := v_requested;

  INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, old_data, new_data)
  VALUES (
    v_relationship.source_organization_id, v_actor, 'facility_management_relationship_members', _relationship_id,
    'facility_management.members_replaced',
    jsonb_build_object('organization_member_ids', to_jsonb(v_old)),
    jsonb_build_object('organization_member_ids', to_jsonb(v_new))
  );
END;
$$;

-- -------------------------------------------------------------------------
-- E.8) get_facility_management_members — equipo asignado a una relación.
--      owner/admin del cliente (lo ve, no lo administra), owner/admin del
--      FM (lo administra) o platform_admin. Nombre/email con el mismo
--      criterio que el resto de RPCs (nombre de user_metadata o prefijo
--      del email); nunca metadata cruda, y solo de miembros ya asignados.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_facility_management_members(
  _relationship_id uuid
)
RETURNS TABLE (
  relationship_id uuid,
  organization_member_id uuid,
  user_id uuid,
  member_name text,
  member_email text,
  membership_role public.organization_member_role,
  membership_is_active boolean,
  assigned_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_relationship public.organization_relationships%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_relationship FROM public.organization_relationships rel WHERE rel.id = _relationship_id;
  IF v_relationship.id IS NULL THEN
    RAISE EXCEPTION 'Relationship not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_relationship.source_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
    OR public.has_organization_role(v_relationship.target_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to view the team of this facility management relationship' USING ERRCODE = '42501';
  END IF;

  IF v_relationship.relationship_type <> 'facility_management' THEN
    RAISE EXCEPTION 'Only facility_management relationships have assigned members' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT
    fmrm.relationship_id,
    om.id,
    om.user_id,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data ->> 'name'), ''), split_part(au.email, '@', 1))::text,
    au.email::text,
    om.role,
    om.is_active,
    fmrm.assigned_at
  FROM public.facility_management_relationship_members fmrm
  JOIN public.organization_members om
    ON om.id = fmrm.organization_member_id
   AND om.organization_id = v_relationship.target_organization_id
  JOIN auth.users au ON au.id = om.user_id
  WHERE fmrm.relationship_id = _relationship_id
  ORDER BY om.role, 4, 5;
END;
$$;

-- -------------------------------------------------------------------------
-- E.9) get_my_facility_management_portfolio — cartera ADMINISTRATIVA del
--      FM: todas sus relaciones (pending/active/suspended/ended) para
--      owner/admin activos de un FM activo, estén o no asignados. No otorga
--      acceso operativo a ningún módulo.
--
--      Decisión: exclusiva de owner/admin del FM. platform_admin no la usa
--      (sin parámetros sería una cartera global ambigua y no debe requerir
--      una membresía ficticia); administra por relationship_id con las
--      demás RPCs.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_facility_management_portfolio()
RETURNS TABLE (
  relationship_id uuid,
  client_organization_id uuid,
  client_organization_name text,
  client_organization_status text,
  facility_manager_organization_id uuid,
  facility_manager_organization_name text,
  relationship_status public.organization_relationship_status,
  permissions public.facility_management_permission[],
  assigned_member_count bigint,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    rel.id,
    client.id,
    client.name,
    client.status,
    fm.id,
    fm.name,
    rel.status,
    COALESCE(
      (SELECT array_agg(fmp.permission ORDER BY fmp.permission)
       FROM public.facility_management_permissions fmp
       WHERE fmp.relationship_id = rel.id),
      '{}'::public.facility_management_permission[]
    ),
    (SELECT count(*) FROM public.facility_management_relationship_members fmrm WHERE fmrm.relationship_id = rel.id),
    rel.created_at,
    rel.updated_at
  FROM public.organization_relationships rel
  JOIN public.organizations fm
    ON fm.id = rel.target_organization_id
   AND fm.organization_type = 'facility_manager'
   AND fm.status = 'active'
  JOIN public.organization_members membership
    ON membership.organization_id = fm.id
   AND membership.user_id = auth.uid()
   AND membership.is_active
   AND membership.role IN ('owner', 'admin')
  JOIN public.organizations client ON client.id = rel.source_organization_id
  WHERE auth.uid() IS NOT NULL
    AND rel.relationship_type = 'facility_management'
  ORDER BY client.name, rel.id;
$$;

-- -------------------------------------------------------------------------
-- Grants de funciones (convención desde 20260831100000_function_acl_hardening.sql)
-- -------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.check_facility_management_relationship() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clear_ended_facility_management_delegation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.check_facility_management_permission_relationship() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.check_facility_management_relationship_member() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.has_facility_management_permission(uuid, public.facility_management_permission) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_facility_management_relationship(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_facility_management_permissions(uuid, public.facility_management_permission[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_facility_management_relationship_status(uuid, public.organization_relationship_status) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_relationships(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_facility_management_clients() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_facility_management_members(uuid, uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_members(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_facility_management_portfolio() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.has_facility_management_permission(uuid, public.facility_management_permission) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_facility_management_relationship(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_facility_management_permissions(uuid, public.facility_management_permission[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_facility_management_relationship_status(uuid, public.organization_relationship_status) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_relationships(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_facility_management_clients() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_facility_management_members(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_facility_management_portfolio() TO authenticated;
