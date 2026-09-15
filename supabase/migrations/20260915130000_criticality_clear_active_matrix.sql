-- Fase 20b — "Nueva matriz en blanco": deja la organización sin parámetros
-- activos, sin tocar plantillas ni evaluaciones históricas.
--
-- Migración separada de 20260915120000_criticality_v2_templates_excel.sql a
-- propósito: esa migración ya fue aplicada al proyecto enlazado (su versión
-- quedó registrada en el historial de Supabase), así que editarla después de
-- aplicada dejaría el archivo local desincronizado de lo que el historial
-- remoto cree que se corrió. Mismo principio que ya rige para
-- 20260829190000_configurable_criticality_matrix.sql, aplicado aquí un paso
-- antes de mergear.
--
-- clear_active_criticality_matrix reutiliza EXACTAMENTE la lógica de
-- desactivación que ya vive dentro de replace_criticality_matrix (Bloque C
-- de la migración anterior) — desactivar opciones de los parámetros activos
-- de la organización, luego desactivar esos parámetros — sin la inserción
-- posterior de configuración nueva. Nunca DELETE, nunca toca
-- criticality_matrix_templates/_parameters/_options,
-- asset_criticality_assessments/_answers ni assets.criticality.
CREATE OR REPLACE FUNCTION public.clear_active_criticality_matrix(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deactivated_parameters integer;
  v_deactivated_options integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  -- Options first (their parameter_id must still resolve to an active
  -- parameter of this org when this runs), then the parameters themselves.
  -- One UPDATE per table — never N calls per row.
  WITH deactivated_options AS (
    UPDATE public.criticality_parameter_options cpo
    SET is_active = false
    WHERE cpo.is_active
      AND cpo.parameter_id IN (
        SELECT cp.id FROM public.criticality_parameters cp
        WHERE cp.organization_id = p_organization_id AND cp.is_active
      )
    RETURNING cpo.id
  )
  SELECT COUNT(*) INTO v_deactivated_options FROM deactivated_options;

  WITH deactivated_parameters AS (
    UPDATE public.criticality_parameters cp
    SET is_active = false
    WHERE cp.organization_id = p_organization_id AND cp.is_active
    RETURNING cp.id
  )
  SELECT COUNT(*) INTO v_deactivated_parameters FROM deactivated_parameters;

  -- No active parameters to begin with: idempotent, both counts are 0, no
  -- exception — matches "Si no hay parámetros activos: operación
  -- idempotente, no error."
  RETURN jsonb_build_object(
    'deactivated_parameters', v_deactivated_parameters,
    'deactivated_options', v_deactivated_options
  );
END;
$$;

REVOKE ALL ON FUNCTION public.clear_active_criticality_matrix(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_active_criticality_matrix(uuid) TO authenticated;
