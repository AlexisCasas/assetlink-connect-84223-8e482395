-- =========================================================================
-- Fase 1 · Punto 2 — Umbrales de criticidad configurables por organización.
--
-- Evoluciona el motor de 20260829190000_configurable_criticality_matrix.sql
-- y 20260915120000_criticality_v2_templates_excel.sql SIN modificarlos: todo
-- lo que cambia se hace con CREATE OR REPLACE de MISMA firma, salvo
-- get_asset_criticality_assessments (DROP + CREATE porque su RETURNS TABLE
-- gana 3 columnas; sus argumentos no cambian, así que ningún llamador se
-- rompe).
--
-- Qué NO cambia:
--   - La fórmula: score = Σ ROUND(option.score * weight / 100, 2).
--   - Las cuatro categorías internas: low / medium / high / critical (sin
--     enum nuevo; en la interfaz critical se muestra como "Muy Alta").
--   - Peso total != 100 sigue siendo advertencia, nunca error.
--   - replace_criticality_matrix mantiene su contrato exacto.
--
-- Qué cambia:
--   A) criticality_thresholds: medium_min / high_min / critical_min por
--      organización. Sin fila = 25 / 50 / 75, exactamente el comportamiento
--      anterior. is_default se decide por VALORES (25/50/75), no por la
--      existencia de la fila.
--   B) Helpers internos (sin GRANT): valores por defecto, umbrales efectivos,
--      clasificación, validación, rango de score posible.
--   C) validate_and_score_asset_criticality clasifica con los umbrales
--      efectivos de la organización del activo. Sigue siendo el ÚNICO lugar
--      que puntúa y clasifica — calculate, preview_bulk y bulk heredan el
--      cambio sin tocarse.
--   D) Snapshot histórico: cada evaluación guarda los umbrales usados.
--      Backfill 25/50/75 exacto: calculate_asset_criticality es el único
--      escritor de evaluaciones (no hay policy de INSERT) y siempre usó esos
--      valores fijos.
--   E) Eventos nuevos: descripción en español y umbrales en el payload. Los
--      eventos históricos NO se modifican.
--   F) Plantillas: guardan los umbrales efectivos; aplicarlas establece
--      matriz + umbrales en la misma transacción; plantillas legacy (NULL)
--      conservan los umbrales actuales.
--   G) replace_criticality_configuration: matriz + umbrales atómicos para el
--      Excel de configuración (hoja "Configuración").
--
-- Seguridad: mismo modelo del módulo. RLS solo SELECT; toda escritura por
-- RPC SECURITY DEFINER; lectura para miembros activos o platform_admin;
-- escritura owner/admin/manager o platform_admin.
-- =========================================================================

-- =========================================================================
-- A) criticality_thresholds
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.criticality_thresholds (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  medium_min numeric(10, 2) NOT NULL,
  high_min numeric(10, 2) NOT NULL,
  critical_min numeric(10, 2) NOT NULL,
  updated_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT criticality_thresholds_order_check
    CHECK (medium_min >= 0 AND medium_min < high_min AND high_min < critical_min)
);

DROP TRIGGER IF EXISTS trg_criticality_thresholds_updated_at ON public.criticality_thresholds;
CREATE TRIGGER trg_criticality_thresholds_updated_at
BEFORE UPDATE ON public.criticality_thresholds
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.criticality_thresholds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "organization members can view criticality thresholds" ON public.criticality_thresholds;
CREATE POLICY "organization members can view criticality thresholds" ON public.criticality_thresholds
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

REVOKE ALL ON TABLE public.criticality_thresholds FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.criticality_thresholds TO authenticated;

-- =========================================================================
-- B) Helpers internos. Ninguno tiene GRANT: solo los invocan las RPC
-- SECURITY DEFINER de este módulo (mismo patrón que
-- validate_and_score_asset_criticality / resolve_asset_path).
-- =========================================================================

-- B1) Valores por defecto — el ÚNICO lugar donde existe 25/50/75.
CREATE OR REPLACE FUNCTION public.criticality_default_thresholds()
RETURNS TABLE (medium_min numeric, high_min numeric, critical_min numeric)
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT 25::numeric(10, 2), 50::numeric(10, 2), 75::numeric(10, 2);
$$;

REVOKE ALL ON FUNCTION public.criticality_default_thresholds() FROM PUBLIC, anon, authenticated;

-- B2) Umbrales efectivos: la fila de la organización o los valores por
-- defecto. is_default compara VALORES, así que una fila explícita 25/50/75
-- ("Restablecer") también es "por defecto".
CREATE OR REPLACE FUNCTION public.get_effective_criticality_thresholds(p_organization_id uuid)
RETURNS TABLE (medium_min numeric, high_min numeric, critical_min numeric, is_default boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COALESCE(ct.medium_min, d.medium_min),
    COALESCE(ct.high_min, d.high_min),
    COALESCE(ct.critical_min, d.critical_min),
    (
      COALESCE(ct.medium_min, d.medium_min) = d.medium_min
      AND COALESCE(ct.high_min, d.high_min) = d.high_min
      AND COALESCE(ct.critical_min, d.critical_min) = d.critical_min
    )
  FROM public.criticality_default_thresholds() AS d
  LEFT JOIN public.criticality_thresholds AS ct ON ct.organization_id = p_organization_id;
$$;

REVOKE ALL ON FUNCTION public.get_effective_criticality_thresholds(uuid) FROM PUBLIC, anon, authenticated;

-- B3) Clasificación — el ÚNICO CASE de clasificación del sistema. Límite
-- inferior inclusivo, igual que el CASE fijo anterior.
CREATE OR REPLACE FUNCTION public.classify_criticality_score(
  p_score numeric,
  p_medium_min numeric,
  p_high_min numeric,
  p_critical_min numeric
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_score < p_medium_min THEN 'low'
    WHEN p_score < p_high_min THEN 'medium'
    WHEN p_score < p_critical_min THEN 'high'
    ELSE 'critical'
  END;
$$;

REVOKE ALL ON FUNCTION public.classify_criticality_score(numeric, numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;

-- B4) Etiqueta en español para textos generados en base de datos (eventos).
CREATE OR REPLACE FUNCTION public.criticality_label_es(p_criticality text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE p_criticality
    WHEN 'low' THEN 'Baja'
    WHEN 'medium' THEN 'Media'
    WHEN 'high' THEN 'Alta'
    WHEN 'critical' THEN 'Muy Alta'
    ELSE p_criticality
  END;
$$;

REVOKE ALL ON FUNCTION public.criticality_label_es(text) FROM PUBLIC, anon, authenticated;

-- B5) Validación de umbrales. Rechaza en vez de redondear: numeric(10,2)
-- redondearía 1.005 a 1.01 en silencio y el límite guardado no sería el
-- introducido. El rango superior también descarta NaN e Infinity (ambos
-- ordenan por encima de cualquier número en PostgreSQL).
CREATE OR REPLACE FUNCTION public.assert_valid_criticality_thresholds(
  p_medium_min numeric,
  p_high_min numeric,
  p_critical_min numeric
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p_medium_min IS NULL OR p_high_min IS NULL OR p_critical_min IS NULL THEN
    RAISE EXCEPTION 'Los tres umbrales (Media, Alta y Muy Alta) son obligatorios.';
  END IF;

  IF p_medium_min < 0 OR p_high_min < 0 OR p_critical_min < 0 THEN
    RAISE EXCEPTION 'Los umbrales deben ser mayores o iguales a 0.';
  END IF;

  IF p_medium_min > 99999999.99 OR p_high_min > 99999999.99 OR p_critical_min > 99999999.99 THEN
    RAISE EXCEPTION 'Los umbrales deben ser números menores a 100000000.';
  END IF;

  IF p_medium_min <> ROUND(p_medium_min, 2)
    OR p_high_min <> ROUND(p_high_min, 2)
    OR p_critical_min <> ROUND(p_critical_min, 2) THEN
    RAISE EXCEPTION 'Los umbrales admiten como máximo 2 decimales.';
  END IF;

  IF NOT (p_medium_min < p_high_min AND p_high_min < p_critical_min) THEN
    RAISE EXCEPTION 'Los umbrales deben ser estrictamente ascendentes: Media < Alta < Muy Alta.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_valid_criticality_thresholds(numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;

-- B6) Lee umbrales desde jsonb ({medium_min, high_min, critical_min}),
-- exigiendo números JSON reales (no strings) y validándolos.
CREATE OR REPLACE FUNCTION public.criticality_thresholds_from_jsonb(p_thresholds jsonb)
RETURNS TABLE (medium_min numeric, high_min numeric, critical_min numeric)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_key text;
  v_label text;
BEGIN
  IF p_thresholds IS NULL OR jsonb_typeof(p_thresholds) <> 'object' THEN
    RAISE EXCEPTION 'Los umbrales deben enviarse como objeto {medium_min, high_min, critical_min}.';
  END IF;

  FOREACH v_key IN ARRAY ARRAY['medium_min', 'high_min', 'critical_min'] LOOP
    v_label := CASE v_key
      WHEN 'medium_min' THEN 'Media desde'
      WHEN 'high_min' THEN 'Alta desde'
      ELSE 'Muy Alta desde'
    END;
    IF NOT (p_thresholds ? v_key) OR jsonb_typeof(p_thresholds->v_key) <> 'number' THEN
      RAISE EXCEPTION 'El umbral "%" es obligatorio y debe ser numérico.', v_label;
    END IF;
  END LOOP;

  medium_min := (p_thresholds->>'medium_min')::numeric;
  high_min := (p_thresholds->>'high_min')::numeric;
  critical_min := (p_thresholds->>'critical_min')::numeric;

  PERFORM public.assert_valid_criticality_thresholds(medium_min, high_min, critical_min);
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.criticality_thresholds_from_jsonb(jsonb) FROM PUBLIC, anon, authenticated;

-- B7) Escritura interna (sin chequeo de rol: lo hace la RPC llamadora).
CREATE OR REPLACE FUNCTION public.write_criticality_thresholds(
  p_organization_id uuid,
  p_medium_min numeric,
  p_high_min numeric,
  p_critical_min numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_valid_criticality_thresholds(p_medium_min, p_high_min, p_critical_min);

  INSERT INTO public.criticality_thresholds AS ct (
    organization_id, medium_min, high_min, critical_min, updated_by_user_id
  ) VALUES (
    p_organization_id, p_medium_min, p_high_min, p_critical_min, auth.uid()
  )
  ON CONFLICT (organization_id) DO UPDATE
  SET medium_min = EXCLUDED.medium_min,
      high_min = EXCLUDED.high_min,
      critical_min = EXCLUDED.critical_min,
      updated_by_user_id = EXCLUDED.updated_by_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.write_criticality_thresholds(uuid, numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;

-- B8) Categorías inalcanzables dado un rango de score posible [min, max].
-- Se calcula aquí para que la interfaz solo renderice, sin comparar
-- scores contra umbrales en JavaScript.
CREATE OR REPLACE FUNCTION public.criticality_unreachable_categories(
  p_min_score numeric,
  p_max_score numeric,
  p_medium_min numeric,
  p_high_min numeric,
  p_critical_min numeric
)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_min_score IS NULL OR p_max_score IS NULL THEN ARRAY[]::text[]
    ELSE ARRAY_REMOVE(ARRAY[
      CASE WHEN p_min_score >= p_medium_min THEN 'low' END,
      CASE WHEN p_max_score < p_medium_min OR p_min_score >= p_high_min THEN 'medium' END,
      CASE WHEN p_max_score < p_high_min OR p_min_score >= p_critical_min THEN 'high' END,
      CASE WHEN p_max_score < p_critical_min THEN 'critical' END
    ], NULL)
  END;
$$;

REVOKE ALL ON FUNCTION public.criticality_unreachable_categories(numeric, numeric, numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;

-- B9) Rango de score posible de la matriz ACTIVA, con la misma fórmula
-- (ROUND por respuesta; ROUND es monótono, así que min/max por parámetro
-- se preservan). Un parámetro activo sin opciones activas no aporta.
CREATE OR REPLACE FUNCTION public.criticality_active_score_range(p_organization_id uuid)
RETURNS TABLE (parameter_count integer, min_possible_score numeric, max_possible_score numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0 THEN NULL ELSE COALESCE(SUM(per.min_contribution), 0) END,
    CASE WHEN COUNT(*) = 0 THEN NULL ELSE COALESCE(SUM(per.max_contribution), 0) END
  FROM (
    SELECT
      (SELECT ROUND(MIN(cpo.score) * cp.weight / 100, 2)
         FROM public.criticality_parameter_options cpo
        WHERE cpo.parameter_id = cp.id AND cpo.is_active) AS min_contribution,
      (SELECT ROUND(MAX(cpo.score) * cp.weight / 100, 2)
         FROM public.criticality_parameter_options cpo
        WHERE cpo.parameter_id = cp.id AND cpo.is_active) AS max_contribution
    FROM public.criticality_parameters cp
    WHERE cp.organization_id = p_organization_id AND cp.is_active
  ) AS per;
$$;

REVOKE ALL ON FUNCTION public.criticality_active_score_range(uuid) FROM PUBLIC, anon, authenticated;

-- B10) Payload común de get/set/replace_configuration.
CREATE OR REPLACE FUNCTION public.criticality_thresholds_payload(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_effective record;
  v_defaults record;
  v_range record;
  v_row public.criticality_thresholds%ROWTYPE;
  v_updated_by_name text;
BEGIN
  SELECT e.* INTO v_effective FROM public.get_effective_criticality_thresholds(p_organization_id) AS e;
  SELECT d.* INTO v_defaults FROM public.criticality_default_thresholds() AS d;
  SELECT r.* INTO v_range FROM public.criticality_active_score_range(p_organization_id) AS r;
  SELECT ct.* INTO v_row FROM public.criticality_thresholds ct WHERE ct.organization_id = p_organization_id;

  IF v_row.updated_by_user_id IS NOT NULL THEN
    SELECT COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1))
      INTO v_updated_by_name
      FROM auth.users au WHERE au.id = v_row.updated_by_user_id;
  END IF;

  RETURN jsonb_build_object(
    'organization_id', p_organization_id,
    'medium_min', v_effective.medium_min,
    'high_min', v_effective.high_min,
    'critical_min', v_effective.critical_min,
    'is_default', v_effective.is_default,
    'defaults', jsonb_build_object(
      'medium_min', v_defaults.medium_min,
      'high_min', v_defaults.high_min,
      'critical_min', v_defaults.critical_min
    ),
    'updated_at', v_row.updated_at,
    'updated_by_name', v_updated_by_name,
    'active_matrix', jsonb_build_object(
      'parameter_count', COALESCE(v_range.parameter_count, 0),
      'min_possible_score', v_range.min_possible_score,
      'max_possible_score', v_range.max_possible_score
    ),
    'unreachable_categories', to_jsonb(public.criticality_unreachable_categories(
      v_range.min_possible_score, v_range.max_possible_score,
      v_effective.medium_min, v_effective.high_min, v_effective.critical_min
    ))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.criticality_thresholds_payload(uuid) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- RPC públicas de umbrales.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_criticality_thresholds(p_organization_id uuid)
RETURNS jsonb
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
    RAISE EXCEPTION 'Not authorized to view the criticality thresholds for this organization';
  END IF;

  RETURN public.criticality_thresholds_payload(p_organization_id);
END;
$$;

REVOKE ALL ON FUNCTION public.get_criticality_thresholds(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_criticality_thresholds(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_criticality_thresholds(
  p_organization_id uuid,
  p_medium_min numeric,
  p_high_min numeric,
  p_critical_min numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality thresholds for this organization';
  END IF;

  PERFORM public.write_criticality_thresholds(p_organization_id, p_medium_min, p_high_min, p_critical_min);

  RETURN public.criticality_thresholds_payload(p_organization_id);
END;
$$;

REVOKE ALL ON FUNCTION public.set_criticality_thresholds(uuid, numeric, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_criticality_thresholds(uuid, numeric, numeric, numeric) TO authenticated;

-- =========================================================================
-- C) validate_and_score_asset_criticality — MISMA firma y misma lógica que
-- 20260915120000; solo cambia la clasificación (umbrales efectivos de la
-- organización del activo, vía classify_criticality_score) y el resultado
-- válido incluye `thresholds`.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.validate_and_score_asset_criticality(
  p_asset_id uuid,
  p_answers jsonb,
  p_expected_organization_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset public.assets%ROWTYPE;
  v_answer jsonb;
  v_parameter_id uuid;
  v_option_id uuid;
  v_parameter public.criticality_parameters%ROWTYPE;
  v_option public.criticality_parameter_options%ROWTYPE;
  v_score numeric(10, 2) := 0;
  v_errors text[] := ARRAY[]::text[];
  v_warnings text[] := ARRAY[]::text[];
  v_resolved jsonb := '[]'::jsonb;
  v_answered_ids uuid[] := ARRAY[]::uuid[];
  v_active_count integer;
  v_missing text;
  v_thresholds record;
BEGIN
  SELECT a.* INTO v_asset FROM public.assets a WHERE a.id = p_asset_id;

  IF v_asset.id IS NULL THEN
    RETURN jsonb_build_object(
      'valid', false, 'asset_id', p_asset_id, 'asset_code', NULL, 'asset_name', NULL,
      'organization_id', NULL, 'score', NULL, 'calculated_criticality', NULL,
      'errors', to_jsonb(ARRAY['El activo no existe o no tienes acceso.']), 'warnings', '[]'::jsonb,
      'answers', '[]'::jsonb
    );
  END IF;

  IF p_expected_organization_id IS NOT NULL AND v_asset.organization_id <> p_expected_organization_id THEN
    RETURN jsonb_build_object(
      'valid', false, 'asset_id', p_asset_id, 'asset_code', NULL, 'asset_name', NULL,
      'organization_id', NULL, 'score', NULL, 'calculated_criticality', NULL,
      'errors', to_jsonb(ARRAY['El activo no pertenece a esta organización.']), 'warnings', '[]'::jsonb,
      'answers', '[]'::jsonb
    );
  END IF;

  SELECT COUNT(*) INTO v_active_count
  FROM public.criticality_parameters cp
  WHERE cp.organization_id = v_asset.organization_id AND cp.is_active;

  IF v_active_count = 0 THEN
    v_errors := array_append(v_errors, 'La organización no tiene parámetros de criticidad activos.');
  END IF;

  IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'array' OR jsonb_array_length(p_answers) = 0 THEN
    v_errors := array_append(v_errors, 'No se recibió ninguna respuesta.');
  ELSE
    FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
      v_parameter_id := NULLIF(v_answer->>'parameter_id', '')::uuid;
      v_option_id := NULLIF(v_answer->>'option_id', '')::uuid;

      IF v_parameter_id IS NULL THEN
        v_errors := array_append(v_errors, 'Cada respuesta requiere un parameter_id.');
        CONTINUE;
      END IF;

      SELECT cp.* INTO v_parameter FROM public.criticality_parameters cp
       WHERE cp.id = v_parameter_id AND cp.organization_id = v_asset.organization_id AND cp.is_active;

      IF v_parameter.id IS NULL THEN
        v_errors := array_append(v_errors, format('El parámetro %s no es un parámetro activo de esta organización.', v_parameter_id));
        CONTINUE;
      END IF;

      IF v_parameter_id = ANY (v_answered_ids) THEN
        v_errors := array_append(v_errors, format('El parámetro "%s" está repetido.', v_parameter.name));
        CONTINUE;
      END IF;
      v_answered_ids := array_append(v_answered_ids, v_parameter_id);

      IF v_option_id IS NULL THEN
        v_errors := array_append(v_errors, format('Falta %s', v_parameter.name));
        CONTINUE;
      END IF;

      SELECT cpo.* INTO v_option FROM public.criticality_parameter_options cpo
       WHERE cpo.id = v_option_id AND cpo.parameter_id = v_parameter_id AND cpo.is_active;

      IF v_option.id IS NULL THEN
        v_errors := array_append(v_errors, format('La opción indicada no es una opción activa de "%s".', v_parameter.name));
        CONTINUE;
      END IF;

      v_score := v_score + ROUND(v_option.score * v_parameter.weight / 100, 2);
      v_resolved := v_resolved || jsonb_build_object(
        'parameter_id', v_parameter.id,
        'parameter_name', v_parameter.name,
        'option_id', v_option.id,
        'option_label', v_option.label,
        'weight', v_parameter.weight,
        'option_score', v_option.score,
        'weighted_score', ROUND(v_option.score * v_parameter.weight / 100, 2)
      );
    END LOOP;
  END IF;

  IF v_active_count > 0 THEN
    FOR v_missing IN
      SELECT cp.name FROM public.criticality_parameters cp
      WHERE cp.organization_id = v_asset.organization_id
        AND cp.is_active
        AND NOT (cp.id = ANY (v_answered_ids))
      ORDER BY cp.sequence, cp.name
    LOOP
      v_errors := array_append(v_errors, format('Falta %s', v_missing));
    END LOOP;
  END IF;

  IF array_length(v_errors, 1) IS NOT NULL THEN
    RETURN jsonb_build_object(
      'valid', false,
      'asset_id', v_asset.id, 'asset_code', v_asset.code, 'asset_name', v_asset.name,
      'organization_id', v_asset.organization_id,
      'score', NULL, 'calculated_criticality', NULL,
      'errors', to_jsonb(v_errors), 'warnings', to_jsonb(v_warnings),
      'answers', '[]'::jsonb
    );
  END IF;

  IF v_asset.status = 'archived' THEN
    v_warnings := array_append(v_warnings, 'El activo está archivado.');
  END IF;

  SELECT e.* INTO v_thresholds FROM public.get_effective_criticality_thresholds(v_asset.organization_id) AS e;

  RETURN jsonb_build_object(
    'valid', true,
    'asset_id', v_asset.id, 'asset_code', v_asset.code, 'asset_name', v_asset.name,
    'organization_id', v_asset.organization_id,
    'score', v_score,
    'calculated_criticality', public.classify_criticality_score(
      v_score, v_thresholds.medium_min, v_thresholds.high_min, v_thresholds.critical_min
    ),
    'thresholds', jsonb_build_object(
      'medium_min', v_thresholds.medium_min,
      'high_min', v_thresholds.high_min,
      'critical_min', v_thresholds.critical_min
    ),
    'errors', '[]'::jsonb, 'warnings', to_jsonb(v_warnings),
    'answers', v_resolved
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validate_and_score_asset_criticality(uuid, jsonb, uuid) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- D) Snapshot histórico de umbrales en cada evaluación.
-- =========================================================================
ALTER TABLE public.asset_criticality_assessments
  ADD COLUMN IF NOT EXISTS threshold_medium_min numeric(10, 2),
  ADD COLUMN IF NOT EXISTS threshold_high_min numeric(10, 2),
  ADD COLUMN IF NOT EXISTS threshold_critical_min numeric(10, 2);

-- Backfill exacto: toda evaluación previa se calculó con 25/50/75 fijos
-- (calculate_asset_criticality es el único escritor; no hay policy INSERT).
-- Solo se rellenan los umbrales: score y criticidad calculada no se tocan.
UPDATE public.asset_criticality_assessments aca
SET threshold_medium_min = 25,
    threshold_high_min = 50,
    threshold_critical_min = 75
WHERE aca.threshold_medium_min IS NULL
   OR aca.threshold_high_min IS NULL
   OR aca.threshold_critical_min IS NULL;

ALTER TABLE public.asset_criticality_assessments
  ALTER COLUMN threshold_medium_min SET NOT NULL,
  ALTER COLUMN threshold_high_min SET NOT NULL,
  ALTER COLUMN threshold_critical_min SET NOT NULL;

ALTER TABLE public.asset_criticality_assessments
  DROP CONSTRAINT IF EXISTS asset_criticality_assessments_thresholds_check;
ALTER TABLE public.asset_criticality_assessments
  ADD CONSTRAINT asset_criticality_assessments_thresholds_check
  CHECK (
    threshold_medium_min >= 0
    AND threshold_medium_min < threshold_high_min
    AND threshold_high_min < threshold_critical_min
  );

-- =========================================================================
-- E) calculate_asset_criticality — MISMA firma y API pública. Cambios:
-- guarda el snapshot de umbrales; el evento nuevo lleva descripción en
-- español ("Muy Alta") y los umbrales en su payload. Eventos anteriores no
-- se tocan.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.calculate_asset_criticality(
  p_asset_id uuid,
  p_answers jsonb,
  p_notes text DEFAULT NULL
)
RETURNS public.asset_criticality_assessments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset public.assets%ROWTYPE;
  v_result jsonb;
  v_answer jsonb;
  v_score numeric(10, 2);
  v_calculated text;
  v_thresholds jsonb;
  v_assessment public.asset_criticality_assessments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.* INTO v_asset FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset.id IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_asset.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to evaluate criticality for this asset';
  END IF;

  v_result := public.validate_and_score_asset_criticality(p_asset_id, p_answers, NULL);

  IF NOT (v_result->>'valid')::boolean THEN
    RAISE EXCEPTION '%', array_to_string(
      ARRAY(SELECT jsonb_array_elements_text(v_result->'errors')), '; '
    );
  END IF;

  v_score := (v_result->>'score')::numeric;
  v_calculated := v_result->>'calculated_criticality';
  v_thresholds := v_result->'thresholds';

  INSERT INTO public.asset_criticality_assessments AS aca (
    asset_id, organization_id, score, calculated_criticality, manual_criticality, effective_criticality, notes, created_by_user_id,
    threshold_medium_min, threshold_high_min, threshold_critical_min
  ) VALUES (
    p_asset_id, v_asset.organization_id, v_score, v_calculated, v_asset.criticality, v_calculated, p_notes, auth.uid(),
    (v_thresholds->>'medium_min')::numeric, (v_thresholds->>'high_min')::numeric, (v_thresholds->>'critical_min')::numeric
  ) RETURNING aca.* INTO v_assessment;

  FOR v_answer IN SELECT * FROM jsonb_array_elements(v_result->'answers') LOOP
    INSERT INTO public.asset_criticality_assessment_answers (
      assessment_id, parameter_id, option_id, parameter_name, option_label, weight, option_score, weighted_score
    ) VALUES (
      v_assessment.id,
      (v_answer->>'parameter_id')::uuid,
      (v_answer->>'option_id')::uuid,
      v_answer->>'parameter_name',
      v_answer->>'option_label',
      (v_answer->>'weight')::numeric,
      (v_answer->>'option_score')::numeric,
      (v_answer->>'weighted_score')::numeric
    );
  END LOOP;

  UPDATE public.assets a SET criticality = v_calculated WHERE a.id = p_asset_id;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_asset.organization_id,
    p_asset_id,
    'criticality_assessed',
    'Criticidad evaluada: ' || public.criticality_label_es(v_calculated) || ' (score ' || v_score || ')',
    jsonb_build_object(
      'score', v_score,
      'calculated_criticality', v_calculated,
      'assessment_id', v_assessment.id,
      'thresholds', v_thresholds
    ),
    auth.uid()
  );

  RETURN v_assessment;
END;
$$;

REVOKE ALL ON FUNCTION public.calculate_asset_criticality(uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_asset_criticality(uuid, jsonb, text) TO authenticated;

-- =========================================================================
-- D2) get_asset_criticality_assessments — mismos argumentos, RETURNS TABLE
-- con los 3 umbrales del snapshot. DROP + CREATE es obligatorio para cambiar
-- las columnas de salida; se reaplican REVOKE/GRANT (los privilegios por
-- defecto de 20260831100000 ya no conceden EXECUTE automáticamente).
-- =========================================================================
DROP FUNCTION IF EXISTS public.get_asset_criticality_assessments(uuid);

CREATE FUNCTION public.get_asset_criticality_assessments(p_asset_id uuid)
RETURNS TABLE (
  id uuid,
  asset_id uuid,
  organization_id uuid,
  score numeric,
  calculated_criticality text,
  manual_criticality text,
  effective_criticality text,
  notes text,
  created_by_user_id uuid,
  created_by_name text,
  created_at timestamptz,
  answers jsonb,
  threshold_medium_min numeric,
  threshold_high_min numeric,
  threshold_critical_min numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.organization_id INTO v_asset_org FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset_org IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(v_asset_org)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view criticality assessments for this asset';
  END IF;

  RETURN QUERY
  SELECT
    aca.id,
    aca.asset_id,
    aca.organization_id,
    aca.score,
    aca.calculated_criticality,
    aca.manual_criticality,
    aca.effective_criticality,
    aca.notes,
    aca.created_by_user_id,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS created_by_name,
    aca.created_at,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'parameter_id', acaa.parameter_id,
        'parameter_name', acaa.parameter_name,
        'option_id', acaa.option_id,
        'option_label', acaa.option_label,
        'weight', acaa.weight,
        'option_score', acaa.option_score,
        'weighted_score', acaa.weighted_score
      ) ORDER BY acaa.parameter_name)
      FROM public.asset_criticality_assessment_answers acaa
      WHERE acaa.assessment_id = aca.id
    ), '[]'::jsonb) AS answers,
    aca.threshold_medium_min::numeric,
    aca.threshold_high_min::numeric,
    aca.threshold_critical_min::numeric
  FROM public.asset_criticality_assessments aca
  LEFT JOIN auth.users au ON au.id = aca.created_by_user_id
  WHERE aca.asset_id = p_asset_id
  ORDER BY aca.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_asset_criticality_assessments(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_asset_criticality_assessments(uuid) TO authenticated;

-- =========================================================================
-- F) Plantillas: umbrales opcionales (NULL = plantilla legacy).
-- =========================================================================
ALTER TABLE public.criticality_matrix_templates
  ADD COLUMN IF NOT EXISTS medium_min numeric(10, 2),
  ADD COLUMN IF NOT EXISTS high_min numeric(10, 2),
  ADD COLUMN IF NOT EXISTS critical_min numeric(10, 2);

ALTER TABLE public.criticality_matrix_templates
  DROP CONSTRAINT IF EXISTS criticality_matrix_templates_thresholds_check;
ALTER TABLE public.criticality_matrix_templates
  ADD CONSTRAINT criticality_matrix_templates_thresholds_check
  CHECK (
    (medium_min IS NULL AND high_min IS NULL AND critical_min IS NULL)
    OR (
      medium_min IS NOT NULL AND high_min IS NOT NULL AND critical_min IS NOT NULL
      AND medium_min >= 0 AND medium_min < high_min AND high_min < critical_min
    )
  );

-- F1) get_criticality_template — misma firma; añade `thresholds` (NULL en
-- legacy), el rango de score posible de la plantilla y las categorías
-- inalcanzables con los umbrales de la propia plantilla.
CREATE OR REPLACE FUNCTION public.get_criticality_template(p_template_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template public.criticality_matrix_templates%ROWTYPE;
  v_min numeric;
  v_max numeric;
  v_param_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT cmt.* INTO v_template FROM public.criticality_matrix_templates cmt WHERE cmt.id = p_template_id;
  IF v_template.id IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  IF NOT public.can_access_criticality_template(p_template_id) THEN
    RAISE EXCEPTION 'Not authorized to view this criticality template';
  END IF;

  SELECT
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0 THEN NULL ELSE COALESCE(SUM(per.min_contribution), 0) END,
    CASE WHEN COUNT(*) = 0 THEN NULL ELSE COALESCE(SUM(per.max_contribution), 0) END
  INTO v_param_count, v_min, v_max
  FROM (
    SELECT
      (SELECT ROUND(MIN(cto.score) * ctp.weight / 100, 2)
         FROM public.criticality_template_options cto
        WHERE cto.template_parameter_id = ctp.id AND cto.is_active) AS min_contribution,
      (SELECT ROUND(MAX(cto.score) * ctp.weight / 100, 2)
         FROM public.criticality_template_options cto
        WHERE cto.template_parameter_id = ctp.id AND cto.is_active) AS max_contribution
    FROM public.criticality_template_parameters ctp
    WHERE ctp.template_id = v_template.id AND ctp.is_active
  ) AS per;

  RETURN jsonb_build_object(
    'id', v_template.id,
    'organization_id', v_template.organization_id,
    'scope', v_template.scope,
    'name', v_template.name,
    'description', v_template.description,
    'category', v_template.category,
    'is_active', v_template.is_active,
    'created_at', v_template.created_at,
    'thresholds', CASE
      WHEN v_template.medium_min IS NULL THEN NULL
      ELSE jsonb_build_object(
        'medium_min', v_template.medium_min,
        'high_min', v_template.high_min,
        'critical_min', v_template.critical_min
      )
    END,
    'min_possible_score', v_min,
    'max_possible_score', v_max,
    'unreachable_categories', CASE
      WHEN v_template.medium_min IS NULL THEN '[]'::jsonb
      ELSE to_jsonb(public.criticality_unreachable_categories(
        v_min, v_max, v_template.medium_min, v_template.high_min, v_template.critical_min
      ))
    END,
    'parameters', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ctp.id,
        'code', ctp.code,
        'name', ctp.name,
        'description', ctp.description,
        'weight', ctp.weight,
        'sequence', ctp.sequence,
        'is_active', ctp.is_active,
        'options', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', cto.id,
            'code', cto.code,
            'label', cto.label,
            'score', cto.score,
            'sequence', cto.sequence,
            'is_active', cto.is_active
          ) ORDER BY cto.sequence, cto.label)
          FROM public.criticality_template_options cto
          WHERE cto.template_parameter_id = ctp.id AND cto.is_active
        ), '[]'::jsonb)
      ) ORDER BY ctp.sequence, ctp.name)
      FROM public.criticality_template_parameters ctp
      WHERE ctp.template_id = v_template.id AND ctp.is_active
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_criticality_template(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_criticality_template(uuid) TO authenticated;

-- F2) apply_criticality_template — misma firma. Reemplaza la matriz (vía
-- replace_criticality_matrix, sin cambios) y, si la plantilla trae umbrales,
-- los establece en la MISMA transacción. Plantilla legacy (NULL): conserva
-- los umbrales actuales de la organización.
CREATE OR REPLACE FUNCTION public.apply_criticality_template(
  p_organization_id uuid,
  p_template_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template public.criticality_matrix_templates%ROWTYPE;
  v_payload jsonb;
  v_result jsonb;
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

  SELECT cmt.* INTO v_template FROM public.criticality_matrix_templates cmt WHERE cmt.id = p_template_id;
  IF v_template.id IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  IF NOT public.can_access_criticality_template(p_template_id) THEN
    RAISE EXCEPTION 'Not authorized to use this criticality template';
  END IF;

  SELECT jsonb_build_object('parameters', COALESCE(jsonb_agg(parameter_payload ORDER BY sequence, code), '[]'::jsonb))
  INTO v_payload
  FROM (
    SELECT
      ctp.sequence AS sequence,
      ctp.code AS code,
      jsonb_build_object(
        'code', ctp.code,
        'name', ctp.name,
        'description', ctp.description,
        'weight', ctp.weight,
        'sequence', ctp.sequence,
        'is_active', true,
        'options', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'code', cto.code,
            'label', cto.label,
            'score', cto.score,
            'sequence', cto.sequence,
            'is_active', true
          ) ORDER BY cto.sequence, cto.code)
          FROM public.criticality_template_options cto
          WHERE cto.template_parameter_id = ctp.id AND cto.is_active
        ), '[]'::jsonb)
      ) AS parameter_payload
    FROM public.criticality_template_parameters ctp
    WHERE ctp.template_id = p_template_id AND ctp.is_active
  ) AS source;

  IF v_payload IS NULL OR jsonb_array_length(v_payload->'parameters') = 0 THEN
    RAISE EXCEPTION 'La plantilla no tiene parámetros activos';
  END IF;

  v_result := public.replace_criticality_matrix(p_organization_id, v_payload);

  IF v_template.medium_min IS NOT NULL THEN
    PERFORM public.write_criticality_thresholds(
      p_organization_id, v_template.medium_min, v_template.high_min, v_template.critical_min
    );
  END IF;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_criticality_template(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_criticality_template(uuid, uuid) TO authenticated;

-- F3) create_template_from_current_matrix — misma firma; congela también los
-- umbrales EFECTIVOS (si la organización usa los valores por defecto, la
-- plantilla guarda 25/50/75 explícitos: es la escala con la que se trabajó).
CREATE OR REPLACE FUNCTION public.create_template_from_current_matrix(
  p_organization_id uuid,
  p_name text,
  p_description text DEFAULT NULL,
  p_category text DEFAULT NULL
)
RETURNS public.criticality_matrix_templates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template public.criticality_matrix_templates%ROWTYPE;
  v_parameter public.criticality_parameters%ROWTYPE;
  v_new_parameter_id uuid;
  v_active_count integer;
  v_thresholds record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage criticality templates for this organization';
  END IF;

  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RAISE EXCEPTION 'El nombre de la plantilla es obligatorio';
  END IF;

  SELECT COUNT(*) INTO v_active_count
  FROM public.criticality_parameters cp
  WHERE cp.organization_id = p_organization_id AND cp.is_active;

  IF v_active_count = 0 THEN
    RAISE EXCEPTION 'No hay una matriz activa que guardar como plantilla';
  END IF;

  SELECT e.* INTO v_thresholds FROM public.get_effective_criticality_thresholds(p_organization_id) AS e;

  INSERT INTO public.criticality_matrix_templates AS cmt (
    organization_id, name, description, category, scope, is_active, created_by_user_id,
    medium_min, high_min, critical_min
  ) VALUES (
    p_organization_id,
    TRIM(p_name),
    NULLIF(TRIM(COALESCE(p_description, '')), ''),
    NULLIF(TRIM(COALESCE(p_category, '')), ''),
    'organization',
    true,
    auth.uid(),
    v_thresholds.medium_min,
    v_thresholds.high_min,
    v_thresholds.critical_min
  ) RETURNING cmt.* INTO v_template;

  FOR v_parameter IN
    SELECT cp.* FROM public.criticality_parameters cp
    WHERE cp.organization_id = p_organization_id AND cp.is_active
    ORDER BY cp.sequence, cp.name
  LOOP
    INSERT INTO public.criticality_template_parameters AS ctp (
      template_id, code, name, description, weight, sequence, is_active
    ) VALUES (
      v_template.id, v_parameter.code, v_parameter.name, v_parameter.description,
      v_parameter.weight, v_parameter.sequence, true
    ) RETURNING ctp.id INTO v_new_parameter_id;

    INSERT INTO public.criticality_template_options (
      template_parameter_id, code, label, score, sequence, is_active
    )
    SELECT v_new_parameter_id, cpo.code, cpo.label, cpo.score, cpo.sequence, true
    FROM public.criticality_parameter_options cpo
    WHERE cpo.parameter_id = v_parameter.id AND cpo.is_active
    ORDER BY cpo.sequence, cpo.label;
  END LOOP;

  RETURN v_template;
END;
$$;

REVOKE ALL ON FUNCTION public.create_template_from_current_matrix(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_template_from_current_matrix(uuid, text, text, text) TO authenticated;

-- =========================================================================
-- G) replace_criticality_configuration — matriz + umbrales en UNA
-- transacción, para el Excel de configuración.
--   - p_thresholds NULL (Excel legacy sin hoja "Configuración"): solo
--     reemplaza la matriz y conserva los umbrales actuales.
--   - p_thresholds presente: valida los umbrales ANTES de tocar nada, luego
--     delega la matriz en replace_criticality_matrix (que valida todo el
--     payload antes de escribir) y recién entonces escribe los umbrales. Si
--     cualquiera de las dos partes es inválida, la excepción revierte todo.
-- replace_criticality_matrix conserva su contrato exacto.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.replace_criticality_configuration(
  p_organization_id uuid,
  p_matrix jsonb,
  p_thresholds jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_thresholds boolean := p_thresholds IS NOT NULL AND jsonb_typeof(p_thresholds) <> 'null';
  v_medium_min numeric;
  v_high_min numeric;
  v_critical_min numeric;
  v_matrix jsonb;
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

  -- Umbrales primero: si son inválidos se aborta antes de tocar la matriz.
  IF v_has_thresholds THEN
    SELECT t.medium_min, t.high_min, t.critical_min
      INTO v_medium_min, v_high_min, v_critical_min
      FROM public.criticality_thresholds_from_jsonb(p_thresholds) AS t;
  END IF;

  v_matrix := public.replace_criticality_matrix(p_organization_id, p_matrix);

  IF v_has_thresholds THEN
    PERFORM public.write_criticality_thresholds(p_organization_id, v_medium_min, v_high_min, v_critical_min);
  END IF;

  RETURN jsonb_build_object(
    'matrix', v_matrix,
    'thresholds', public.criticality_thresholds_payload(p_organization_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.replace_criticality_configuration(uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_criticality_configuration(uuid, jsonb, jsonb) TO authenticated;
