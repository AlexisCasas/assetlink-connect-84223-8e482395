-- =========================================================================
-- Fase 1 · Punto 10 — Fotos y documentos de activos sobre Cloudflare R2.
--
-- Convierte la foundation del Punto 7 (Edge Function `asset-files`,
-- authorize_asset_file_access, keys generadas en servidor, URLs firmadas de
-- 300 s) en funcionalidad de producto:
--
--   1. public.asset_documents pasa a ser la tabla de metadata de los
--      archivos R2 de un activo (backward-compatible: las filas legacy
--      siguen existiendo y no se tocan).
--   2. Invariantes server-side: kind, status, un único primary, storage_path
--      único y con forma coherente con organización/activo/kind, file_url
--      siempre NULL para R2 (nunca una URL firmada).
--   3. Sin escritura raw desde el navegador: se eliminan las policies de
--      INSERT/UPDATE de authenticated y se revoca DML. Toda mutación pasa
--      por `asset-files` (service role SOLO después de autorizar con el JWT
--      del caller) o por la RPC set_asset_primary_photo.
--   4. authorize_asset_file_access = acceso directo histórico (idéntico)
--      OR acceso delegado de Facility Manager con la matriz de 9C.1:
--        read:          assets.view,                 FM o/a/m/technician
--        write/delete:  assets.view + assets.manage, FM o/a/m
--   5. authorize_asset_file_operation(file_id, op): resuelve la fila y
--      autoriza sin revelar existencia entre tenants.
--   6. get_asset_files: listado minimizado (sin storage_path, file_url,
--      uploaded_by_user_id). El FM nunca lee asset_documents en crudo.
--   7. Lifecycle interno (solo service_role): marcar available con primary
--      automático, iniciar borrado (deleting + promoción del primary) y
--      cerrar borrado.
--
-- Fuera de alcance: adjuntos de solicitudes/inspecciones/OT, proveedores,
-- buckets legacy de Supabase Storage, 9C.5/9C.6/9C.7.
-- Ver docs/ASSET_FILES_R2_PRODUCTIZATION.md.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1) asset_documents: metadata de archivos R2 (backward-compatible)
-- -------------------------------------------------------------------------
-- `kind` NULL = fila legacy (anterior a Punto 10, p. ej. con file_url). Toda
-- fila R2 tiene kind. `document_type` se conserva como campo legacy /
-- clasificación futura; no sustituye a `kind`.
ALTER TABLE public.asset_documents
  ADD COLUMN kind text,
  ADD COLUMN content_type text,
  ADD COLUMN size_bytes bigint,
  ADD COLUMN etag text,
  ADD COLUMN status text NOT NULL DEFAULT 'available',
  ADD COLUMN is_primary boolean NOT NULL DEFAULT false,
  ADD COLUMN confirmed_at timestamptz,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.asset_documents
  ADD CONSTRAINT asset_documents_kind_check
    CHECK (kind IS NULL OR kind IN ('photo', 'document')),
  ADD CONSTRAINT asset_documents_status_check
    CHECK (status IN ('pending', 'available', 'deleting', 'failed')),
  ADD CONSTRAINT asset_documents_size_bytes_check
    CHECK (size_bytes IS NULL OR size_bytes >= 0),
  -- Solo una foto disponible puede ser la principal.
  ADD CONSTRAINT asset_documents_primary_photo_check
    CHECK (NOT is_primary OR (kind = 'photo' AND status = 'available')),
  -- Forma de una fila R2: key canónica coherente con org/activo/kind, sin
  -- URL persistida (nunca una URL firmada) y Content-Type conocido.
  ADD CONSTRAINT asset_documents_r2_shape_check
    CHECK (
      kind IS NULL
      OR (
        file_url IS NULL
        AND content_type IS NOT NULL
        AND storage_path IS NOT NULL
        AND storage_path LIKE (
          'organizations/' || organization_id::text || '/assets/' || asset_id::text || '/'
          || CASE kind WHEN 'photo' THEN 'photos/' ELSE 'documents/' END || '%'
        )
      )
    ),
  -- Un archivo R2 disponible siempre tiene tamaño real y fecha de confirmación.
  ADD CONSTRAINT asset_documents_available_confirmed_check
    CHECK (kind IS NULL OR status <> 'available' OR (size_bytes IS NOT NULL AND confirmed_at IS NOT NULL));

CREATE UNIQUE INDEX asset_documents_storage_path_key
  ON public.asset_documents (storage_path)
  WHERE storage_path IS NOT NULL;

-- A lo sumo una foto principal por activo.
CREATE UNIQUE INDEX asset_documents_one_primary_photo
  ON public.asset_documents (asset_id)
  WHERE kind = 'photo' AND is_primary;

CREATE INDEX idx_asset_documents_asset_kind_status
  ON public.asset_documents (asset_id, kind, status);

CREATE TRIGGER trg_asset_documents_updated_at
  BEFORE UPDATE ON public.asset_documents
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- -------------------------------------------------------------------------
-- 2) Sin escritura raw: el navegador no puede forjar status, storage_path,
--    etag, tamaño ni is_primary. Se conserva la lectura directa histórica
--    (policy SELECT de miembros del cliente); el FM delegado nunca lee la
--    tabla en crudo (usa get_asset_files).
-- -------------------------------------------------------------------------
DROP POLICY "organization managers can create asset documents" ON public.asset_documents;
DROP POLICY "organization managers can update asset documents" ON public.asset_documents;
REVOKE INSERT, UPDATE, DELETE ON public.asset_documents FROM anon, authenticated;

-- `asset-files` (service_role, SOLO después de autorizar el JWT del caller)
-- lee la fila interna y crea la fila `pending`. Privilegios explícitos y
-- mínimos: el ACL por defecto de tablas varía por entorno (en una base
-- local recién reseteada service_role no tiene DML sobre esta tabla). Las
-- transiciones de estado siguen pasando por las funciones del bloque 7.
-- SELECT en assets: el trigger histórico check_asset_child_organization
-- (SECURITY INVOKER, BEFORE INSERT) lee el activo para validar la
-- organización de la fila nueva.
GRANT SELECT, INSERT ON public.asset_documents TO service_role;
GRANT SELECT ON public.assets TO service_role;

-- -------------------------------------------------------------------------
-- 3) authorize_asset_file_access: directo histórico OR delegado FM
-- -------------------------------------------------------------------------
-- Mismos mensajes que Punto 7 (asset-files los traduce a 401/403/404/400).
-- search_path vacío y referencias calificadas.
CREATE OR REPLACE FUNCTION public.authorize_asset_file_access(
  p_asset_id uuid,
  p_operation text
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_asset record;
  v_org public.organizations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF p_operation IS NULL OR p_operation NOT IN ('read', 'write', 'delete') THEN
    RAISE EXCEPTION 'Invalid operation: %', p_operation;
  END IF;

  SELECT a.id, a.organization_id, a.status INTO v_asset
  FROM public.assets a
  WHERE a.id = p_asset_id;

  IF v_asset.id IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  SELECT o.* INTO v_org FROM public.organizations o WHERE o.id = v_asset.organization_id;
  IF v_org.id IS NULL OR v_org.status <> 'active' OR v_org.organization_type = 'platform_admin' THEN
    RAISE EXCEPTION 'Organization is not available';
  END IF;

  IF p_operation = 'read' THEN
    -- Directo (sin cambios): cualquier miembro activo o platform admin.
    -- Delegado (9C.1): assets.view, FM owner/admin/manager/technician.
    -- Un activo archivado sigue siendo legible.
    IF NOT (
      public.is_platform_admin()
      OR public.is_organization_member(v_asset.organization_id)
      OR public.has_facility_management_operational_access_all(
        v_asset.organization_id,
        ARRAY['assets.view']::public.facility_management_permission[],
        ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[]
      )
    ) THEN
      RAISE EXCEPTION 'Not authorized to read files for this asset';
    END IF;
  ELSE
    -- Un activo archivado nunca admite escritura ni borrado, para nadie.
    IF v_asset.status = 'archived' THEN
      RAISE EXCEPTION 'Cannot % files on an archived asset', p_operation;
    END IF;
    -- Directo (sin cambios): owner/admin/manager o platform admin.
    -- Delegado (9C.1): assets.view + assets.manage, FM owner/admin/manager.
    IF NOT (
      public.is_platform_admin()
      OR public.has_organization_role(
        v_asset.organization_id,
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
      )
      OR public.has_facility_management_operational_access_all(
        v_asset.organization_id,
        ARRAY['assets.view', 'assets.manage']::public.facility_management_permission[],
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
      )
    ) THEN
      RAISE EXCEPTION 'Not authorized to % files for this asset', p_operation;
    END IF;
  END IF;

  RETURN v_asset.organization_id;
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_asset_file_access(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.authorize_asset_file_access(uuid, text) TO authenticated;

-- ¿Puede el caller operar sobre este activo? Sin excepción (interna).
CREATE OR REPLACE FUNCTION public.can_access_asset_files(p_asset_id uuid, p_operation text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.authorize_asset_file_access(p_asset_id, p_operation);
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_asset_files(uuid, text) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 4) authorize_asset_file_operation(file_id, op): contrato por file_id.
--    Un archivo inexistente o de un activo que el caller no puede leer
--    responde igual ('File not found'): sin enumeración entre tenants.
--    Devuelve el organization_id del archivo (nunca storage_path).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.authorize_asset_file_operation(
  p_file_id uuid,
  p_operation text
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_file record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;
  IF p_operation IS NULL OR p_operation NOT IN ('read', 'write', 'delete') THEN
    RAISE EXCEPTION 'Invalid operation: %', p_operation;
  END IF;

  SELECT d.id, d.asset_id, d.organization_id INTO v_file
  FROM public.asset_documents d
  WHERE d.id = p_file_id AND d.kind IS NOT NULL;

  IF v_file.id IS NULL OR NOT public.can_access_asset_files(v_file.asset_id, 'read') THEN
    RAISE EXCEPTION 'File not found';
  END IF;

  -- Ya puede leer el activo: el resto de rechazos (rol, archivado) puede
  -- explicarse sin revelar nada de otro tenant.
  RETURN public.authorize_asset_file_access(v_file.asset_id, p_operation);
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_asset_file_operation(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.authorize_asset_file_operation(uuid, text) TO authenticated;

-- -------------------------------------------------------------------------
-- 5) get_asset_files: listado minimizado, para cliente directo y FM.
--    Todos ven los archivos `available`. Quien puede escribir en el activo
--    (y el activo no está archivado) ve además pending/failed/deleting para
--    poder gestionarlos. Nunca storage_path, file_url ni uploaded_by.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_asset_files(p_asset_id uuid)
RETURNS TABLE (
  id uuid,
  kind text,
  name text,
  content_type text,
  size_bytes bigint,
  status text,
  is_primary boolean,
  created_at timestamptz,
  confirmed_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_can_manage boolean;
BEGIN
  PERFORM public.authorize_asset_file_access(p_asset_id, 'read');
  v_can_manage := public.can_access_asset_files(p_asset_id, 'write');

  RETURN QUERY
  SELECT d.id, d.kind, d.name, d.content_type, d.size_bytes, d.status, d.is_primary, d.created_at, d.confirmed_at
  FROM public.asset_documents d
  WHERE d.asset_id = p_asset_id
    AND d.kind IS NOT NULL
    AND (d.status = 'available' OR v_can_manage)
  ORDER BY d.kind, d.is_primary DESC, d.created_at, d.id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_asset_files(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_asset_files(uuid) TO authenticated;

-- -------------------------------------------------------------------------
-- 6) set_asset_primary_photo: la única escritura directa desde el
--    navegador, y solo sobre is_primary, con la misma autorización write.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_asset_primary_photo(p_file_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_file public.asset_documents%ROWTYPE;
BEGIN
  PERFORM public.authorize_asset_file_operation(p_file_id, 'write');

  SELECT d.* INTO v_file FROM public.asset_documents d WHERE d.id = p_file_id;
  -- Serializa las decisiones de primary del mismo activo.
  PERFORM 1 FROM public.assets a WHERE a.id = v_file.asset_id FOR UPDATE;
  SELECT d.* INTO v_file FROM public.asset_documents d WHERE d.id = p_file_id FOR UPDATE;

  IF v_file.kind IS DISTINCT FROM 'photo' OR v_file.status <> 'available' THEN
    RAISE EXCEPTION 'Only an available photo can be the primary photo' USING ERRCODE = '22023';
  END IF;
  IF v_file.is_primary THEN
    RETURN;
  END IF;

  UPDATE public.asset_documents d SET is_primary = false
  WHERE d.asset_id = v_file.asset_id AND d.kind = 'photo' AND d.is_primary;
  UPDATE public.asset_documents d SET is_primary = true WHERE d.id = v_file.id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_asset_primary_photo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_asset_primary_photo(uuid) TO authenticated;

-- -------------------------------------------------------------------------
-- 7) Lifecycle interno, SOLO service_role. `asset-files` las llama después
--    de autorizar al caller con su propio JWT; nunca deciden autorización.
-- -------------------------------------------------------------------------

-- pending -> available con el tamaño/tipo/etag REALES del HEAD de R2. La
-- primera foto disponible de un activo sin principal pasa a ser principal.
-- Idempotente si ya está available.
CREATE OR REPLACE FUNCTION public.asset_file_mark_available(
  p_file_id uuid,
  p_size_bytes bigint,
  p_content_type text,
  p_etag text
)
RETURNS public.asset_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_file public.asset_documents%ROWTYPE;
  v_has_primary boolean;
BEGIN
  SELECT d.* INTO v_file FROM public.asset_documents d WHERE d.id = p_file_id;
  IF v_file.id IS NULL OR v_file.kind IS NULL THEN
    RAISE EXCEPTION 'File not found';
  END IF;
  PERFORM 1 FROM public.assets a WHERE a.id = v_file.asset_id FOR UPDATE;
  SELECT d.* INTO v_file FROM public.asset_documents d WHERE d.id = p_file_id FOR UPDATE;

  IF v_file.status = 'available' THEN
    RETURN v_file;
  END IF;
  IF v_file.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending file can be confirmed (status: %)', v_file.status USING ERRCODE = '55000';
  END IF;
  IF p_content_type IS DISTINCT FROM v_file.content_type THEN
    RAISE EXCEPTION 'Confirmed Content-Type does not match the upload intent' USING ERRCODE = '22023';
  END IF;

  v_has_primary := EXISTS (
    SELECT 1 FROM public.asset_documents d
    WHERE d.asset_id = v_file.asset_id AND d.kind = 'photo' AND d.is_primary
  );

  UPDATE public.asset_documents d SET
    status = 'available',
    size_bytes = p_size_bytes,
    etag = p_etag,
    confirmed_at = now(),
    is_primary = (v_file.kind = 'photo' AND NOT v_has_primary)
  WHERE d.id = p_file_id
  RETURNING d.* INTO v_file;
  RETURN v_file;
END;
$$;

-- Inicia el borrado: status `deleting` (fuera de la galería, reintentable)
-- y, si era la principal, promueve la foto disponible más antigua
-- (created_at, id). Devuelve la fila (con storage_path) para que
-- asset-files borre el objeto real. Idempotente sobre `deleting`.
CREATE OR REPLACE FUNCTION public.asset_file_begin_delete(p_file_id uuid)
RETURNS public.asset_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_file public.asset_documents%ROWTYPE;
  v_was_primary boolean;
  v_next uuid;
BEGIN
  SELECT d.* INTO v_file FROM public.asset_documents d WHERE d.id = p_file_id;
  IF v_file.id IS NULL OR v_file.kind IS NULL THEN
    RAISE EXCEPTION 'File not found';
  END IF;
  PERFORM 1 FROM public.assets a WHERE a.id = v_file.asset_id FOR UPDATE;
  SELECT d.* INTO v_file FROM public.asset_documents d WHERE d.id = p_file_id FOR UPDATE;

  IF v_file.status = 'deleting' THEN
    RETURN v_file;
  END IF;

  v_was_primary := v_file.is_primary;
  UPDATE public.asset_documents d SET status = 'deleting', is_primary = false
  WHERE d.id = p_file_id
  RETURNING d.* INTO v_file;

  IF v_was_primary THEN
    SELECT d.id INTO v_next
    FROM public.asset_documents d
    WHERE d.asset_id = v_file.asset_id AND d.kind = 'photo' AND d.status = 'available' AND d.id <> p_file_id
    ORDER BY d.created_at, d.id
    LIMIT 1;
    IF v_next IS NOT NULL THEN
      UPDATE public.asset_documents d SET is_primary = true WHERE d.id = v_next;
    END IF;
  END IF;

  RETURN v_file;
END;
$$;

-- Cierra el borrado cuando el objeto ya no existe en R2 (borrado o ya
-- ausente): elimina la metadata. Solo desde `deleting`.
CREATE OR REPLACE FUNCTION public.asset_file_finish_delete(p_file_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  DELETE FROM public.asset_documents d
  WHERE d.id = p_file_id AND d.kind IS NOT NULL AND d.status = 'deleting';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only a file being deleted can be removed' USING ERRCODE = '55000';
  END IF;
END;
$$;

-- pending -> failed (firma fallida o validación real rechazada). Nunca
-- toca un archivo available.
CREATE OR REPLACE FUNCTION public.asset_file_mark_failed(p_file_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.asset_documents d SET status = 'failed', is_primary = false
  WHERE d.id = p_file_id AND d.kind IS NOT NULL AND d.status = 'pending';
END;
$$;

REVOKE ALL ON FUNCTION public.asset_file_mark_available(uuid, bigint, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.asset_file_begin_delete(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.asset_file_finish_delete(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.asset_file_mark_failed(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.asset_file_mark_available(uuid, bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.asset_file_begin_delete(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.asset_file_finish_delete(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.asset_file_mark_failed(uuid) TO service_role;
