-- =========================================================================
-- Fase 1 · Punto 7 — Cloudflare R2 Foundation: authorize_asset_file_access.
--
-- Única pieza de esquema de esta rama. La Edge Function `asset-files`
-- (service_role para R2, JWT del caller para esta RPC — mismo patrón que
-- Fase 1 · Punto 6B) llama esta función ANTES de firmar cualquier URL o
-- ejecutar cualquier operación server-side sobre R2. No toca
-- asset_documents ni assets.image_url — eso es Punto 10.
--
-- Replica exactamente las reglas RLS ya existentes de `assets`
-- (20260826234732_assets_tenant_aware_foundation.sql):
--   lectura:  is_platform_admin() OR is_organization_member(organization_id)
--   escritura: is_platform_admin() OR has_organization_role(organization_id,
--              ['owner','admin','manager'])
-- así que un lector nunca ve un permiso distinto entre gestionar el activo
-- en la UI y subir/leer/borrar un archivo de ese mismo activo.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.authorize_asset_file_access(
  p_asset_id uuid,
  p_operation text
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset record;
  v_org public.organizations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF p_operation NOT IN ('read', 'write', 'delete') THEN
    RAISE EXCEPTION 'Invalid operation: %', p_operation;
  END IF;

  SELECT id, organization_id, status INTO v_asset
  FROM public.assets
  WHERE id = p_asset_id;

  IF v_asset.id IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  SELECT * INTO v_org FROM public.organizations WHERE id = v_asset.organization_id;
  IF v_org.id IS NULL OR v_org.status <> 'active' OR v_org.organization_type = 'platform_admin' THEN
    RAISE EXCEPTION 'Organization is not available';
  END IF;

  IF p_operation = 'read' THEN
    -- Igual que "organization members can view assets": cualquier miembro
    -- activo, sin importar rol, o platform admin. Un activo archivado
    -- sigue siendo legible — solo se bloquea la escritura/borrado.
    IF NOT (
      public.is_platform_admin()
      OR public.is_organization_member(v_asset.organization_id)
    ) THEN
      RAISE EXCEPTION 'Not authorized to read files for this asset';
    END IF;
  ELSE
    -- write/delete: igual que "organization managers can update/create
    -- assets". Un activo archivado nunca admite escritura ni borrado,
    -- aunque el caller tenga el rol correcto — mismo criterio que el resto
    -- del producto (un activo archivado ya no se edita).
    IF v_asset.status = 'archived' THEN
      RAISE EXCEPTION 'Cannot % files on an archived asset', p_operation;
    END IF;
    IF NOT (
      public.is_platform_admin()
      OR public.has_organization_role(
        v_asset.organization_id,
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
