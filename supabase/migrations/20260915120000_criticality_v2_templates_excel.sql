-- Fase 20 — Criticidad V2: plantillas, Excel y evaluación masiva.
--
-- NO modifica 20260829190000_configurable_criticality_matrix.sql. Todo lo que
-- esta fase cambia de aquella se hace por CREATE OR REPLACE con la MISMA
-- firma (get_criticality_matrix, calculate_asset_criticality), así que ningún
-- call site existente del frontend cambia de contrato.
--
-- Cinco bloques:
--   A) Códigos técnicos estables (code) en la matriz viva, con backfill
--      determinístico y trigger de autogeneración — para que exportar →
--      editar → importar → exportar sea un round-trip real. Los RPC
--      manuales existentes (upsert_criticality_parameter/_option) NO
--      cambian de firma: el trigger les genera el code.
--   B) Motor común de cálculo: validate_and_score_asset_criticality — única
--      implementación de "validar + puntuar". calculate_asset_criticality
--      pasa a delegar en él (misma API pública), y preview/bulk lo reusan.
--      La fórmula y los umbrales existen en UN solo lugar, nunca en JS.
--   C) replace_criticality_matrix — reemplazo transaccional desde payload
--      (Excel o plantilla): valida TODO primero, luego desactiva lo activo
--      (nunca DELETE) y recién entonces inserta.
--   D) Plantillas (3 tablas + RLS + 4 RPC), scope system/organization.
--   E) Preview masivo y aplicación masiva, server-side, reusando B).

-- =========================================================================
-- A1) criticality_slugify — normalización determinística nombre -> código.
-- Helper interno (sin GRANT): solo lo llaman el backfill y los triggers de
-- abajo. search_path = '' porque solo usa funciones de pg_catalog.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.criticality_slugify(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    NULLIF(
      BTRIM(
        SUBSTRING(
          REGEXP_REPLACE(
            UPPER(TRANSLATE(
              BTRIM(COALESCE(p_text, '')),
              'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ',
              'AAAAAEEEEIIIIOOOOOUUUUNCAAAAAEEEEIIIIOOOOOUUUUNC'
            )),
            '[^A-Z0-9]+', '_', 'g'
          ),
          1, 40
        ),
        '_'
      ),
      ''
    ),
    'ITEM'
  );
$$;

REVOKE ALL ON FUNCTION public.criticality_slugify(text) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- A2) code en la matriz viva. Se agrega nullable, se backfillea, se hace
-- NOT NULL y recién entonces se indexa.
-- =========================================================================
ALTER TABLE public.criticality_parameters
  ADD COLUMN IF NOT EXISTS code text NULL;

ALTER TABLE public.criticality_parameter_options
  ADD COLUMN IF NOT EXISTS code text NULL;

-- Backfill determinístico y libre de colisiones: slug del nombre, y ante
-- empate dentro de la misma organización (o del mismo parámetro, para las
-- opciones) se sufija con el número de fila en un orden estable
-- (sequence, created_at, id) para que el resultado sea reproducible.
WITH numbered AS (
  SELECT
    cp.id,
    public.criticality_slugify(cp.name) AS base,
    ROW_NUMBER() OVER (
      PARTITION BY cp.organization_id, public.criticality_slugify(cp.name)
      ORDER BY cp.sequence, cp.created_at, cp.id
    ) AS rn
  FROM public.criticality_parameters cp
  WHERE cp.code IS NULL
)
UPDATE public.criticality_parameters cp
SET code = CASE WHEN n.rn = 1 THEN n.base ELSE n.base || '_' || n.rn END
FROM numbered n
WHERE n.id = cp.id;

WITH numbered AS (
  SELECT
    cpo.id,
    public.criticality_slugify(cpo.label) AS base,
    ROW_NUMBER() OVER (
      PARTITION BY cpo.parameter_id, public.criticality_slugify(cpo.label)
      ORDER BY cpo.sequence, cpo.created_at, cpo.id
    ) AS rn
  FROM public.criticality_parameter_options cpo
  WHERE cpo.code IS NULL
)
UPDATE public.criticality_parameter_options cpo
SET code = CASE WHEN n.rn = 1 THEN n.base ELSE n.base || '_' || n.rn END
FROM numbered n
WHERE n.id = cpo.id;

-- =========================================================================
-- A3) Triggers de autogeneración. Son lo que mantiene compatibles a
-- upsert_criticality_parameter/upsert_criticality_option (que NO reciben
-- code) sin crear overloads nuevos: si la fila llega sin code, se deriva del
-- nombre/etiqueta y se desambigua contra las filas ACTIVAS.
--
-- La unicidad (índices en A4) es parcial sobre is_active a propósito: este
-- módulo nunca borra, solo desactiva (is_active = false), así que reemplazar
-- una matriz deja las filas viejas con su code intacto. Si el índice fuera
-- total, reimportar la misma matriz (mismos códigos) chocaría contra su
-- propia versión anterior desactivada y el round-trip sería imposible. El
-- code identifica un parámetro/opción DENTRO de la matriz activa, que es
-- exactamente lo que el contrato Excel necesita.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.assign_criticality_parameter_code()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_base text;
  v_candidate text;
  v_suffix integer := 1;
BEGIN
  IF NEW.code IS NOT NULL AND TRIM(NEW.code) <> '' THEN
    NEW.code := TRIM(NEW.code);
    RETURN NEW;
  END IF;

  v_base := public.criticality_slugify(NEW.name);
  v_candidate := v_base;

  WHILE EXISTS (
    SELECT 1 FROM public.criticality_parameters cp
    WHERE cp.organization_id = NEW.organization_id
      AND cp.is_active
      AND LOWER(cp.code) = LOWER(v_candidate)
      AND cp.id <> NEW.id
  ) LOOP
    v_suffix := v_suffix + 1;
    v_candidate := v_base || '_' || v_suffix;
  END LOOP;

  NEW.code := v_candidate;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_criticality_parameter_code() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_criticality_parameters_assign_code ON public.criticality_parameters;
CREATE TRIGGER trg_criticality_parameters_assign_code
BEFORE INSERT OR UPDATE ON public.criticality_parameters
FOR EACH ROW EXECUTE FUNCTION public.assign_criticality_parameter_code();

CREATE OR REPLACE FUNCTION public.assign_criticality_option_code()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_base text;
  v_candidate text;
  v_suffix integer := 1;
BEGIN
  IF NEW.code IS NOT NULL AND TRIM(NEW.code) <> '' THEN
    NEW.code := TRIM(NEW.code);
    RETURN NEW;
  END IF;

  v_base := public.criticality_slugify(NEW.label);
  v_candidate := v_base;

  WHILE EXISTS (
    SELECT 1 FROM public.criticality_parameter_options cpo
    WHERE cpo.parameter_id = NEW.parameter_id
      AND cpo.is_active
      AND LOWER(cpo.code) = LOWER(v_candidate)
      AND cpo.id <> NEW.id
  ) LOOP
    v_suffix := v_suffix + 1;
    v_candidate := v_base || '_' || v_suffix;
  END LOOP;

  NEW.code := v_candidate;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_criticality_option_code() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_criticality_parameter_options_assign_code ON public.criticality_parameter_options;
CREATE TRIGGER trg_criticality_parameter_options_assign_code
BEFORE INSERT OR UPDATE ON public.criticality_parameter_options
FOR EACH ROW EXECUTE FUNCTION public.assign_criticality_option_code();

-- =========================================================================
-- A4) NOT NULL + unicidad (parcial sobre activos, ver A3).
-- =========================================================================
ALTER TABLE public.criticality_parameters ALTER COLUMN code SET NOT NULL;
ALTER TABLE public.criticality_parameter_options ALTER COLUMN code SET NOT NULL;

DO $$ BEGIN
  ALTER TABLE public.criticality_parameters
    ADD CONSTRAINT criticality_parameters_code_check CHECK (TRIM(code) <> '');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.criticality_parameter_options
    ADD CONSTRAINT criticality_parameter_options_code_check CHECK (TRIM(code) <> '');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_criticality_parameters_active_code
  ON public.criticality_parameters (organization_id, LOWER(code)) WHERE is_active;

CREATE UNIQUE INDEX IF NOT EXISTS idx_criticality_parameter_options_active_code
  ON public.criticality_parameter_options (parameter_id, LOWER(code)) WHERE is_active;

-- =========================================================================
-- A5) get_criticality_matrix — misma firma, ahora expone code.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_criticality_matrix(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view the criticality matrix for this organization';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cp.id,
    'code', cp.code,
    'name', cp.name,
    'description', cp.description,
    'weight', cp.weight,
    'sequence', cp.sequence,
    'is_active', cp.is_active,
    'options', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cpo.id,
        'code', cpo.code,
        'label', cpo.label,
        'score', cpo.score,
        'sequence', cpo.sequence,
        'is_active', cpo.is_active
      ) ORDER BY cpo.sequence, cpo.label)
      FROM public.criticality_parameter_options cpo
      WHERE cpo.parameter_id = cp.id AND (p_include_inactive OR cpo.is_active)
    ), '[]'::jsonb)
  ) ORDER BY cp.sequence, cp.name), '[]'::jsonb)
  INTO v_result
  FROM public.criticality_parameters cp
  WHERE cp.organization_id = p_organization_id AND (p_include_inactive OR cp.is_active);

  RETURN v_result;
END;
$$;

-- =========================================================================
-- B) validate_and_score_asset_criticality — MOTOR COMÚN.
--
-- Única implementación de "validar respuestas + puntuar" de todo el sistema:
-- la usan calculate_asset_criticality (evaluación individual),
-- preview_bulk_asset_criticality y bulk_calculate_asset_criticality. La
-- fórmula (score = Σ round(option.score * weight / 100, 2)) y los umbrales
-- (<25 low / <50 medium / <75 high / >=75 critical) viven SOLO aquí — nunca
-- se replican en JavaScript ni en el preview.
--
-- No escribe nada y no lanza excepción por errores de datos de fila: los
-- acumula en `errors` y devuelve valid=false, para que el preview masivo
-- pueda reportar 100 filas de una sola pasada. Los llamadores que necesitan
-- la semántica vieja (evaluación individual) convierten esos errores en
-- RAISE.
--
-- Helper interno: sin GRANT a authenticated, solo invocable desde las otras
-- funciones SECURITY DEFINER (mismo patrón que resolve_asset_path /
-- notify_role_members).
--
-- p_expected_organization_id: cuando no es NULL, el activo DEBE pertenecer a
-- esa organización. Es lo que impide que una fila de Excel con el UUID de un
-- activo de otro tenant se cuele en un preview/import (nunca se confía en el
-- UUID del archivo).
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

  -- Todo parámetro activo debe estar respondido exactamente una vez — misma
  -- regla que ya exigía calculate_asset_criticality, ahora reportada
  -- parámetro por parámetro para que el preview de Excel diga "Falta
  -- Frecuencia de falla" en vez de un conteo.
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

  RETURN jsonb_build_object(
    'valid', true,
    'asset_id', v_asset.id, 'asset_code', v_asset.code, 'asset_name', v_asset.name,
    'organization_id', v_asset.organization_id,
    'score', v_score,
    'calculated_criticality', CASE
      WHEN v_score < 25 THEN 'low'
      WHEN v_score < 50 THEN 'medium'
      WHEN v_score < 75 THEN 'high'
      ELSE 'critical'
    END,
    'errors', '[]'::jsonb, 'warnings', to_jsonb(v_warnings),
    'answers', v_resolved
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validate_and_score_asset_criticality(uuid, jsonb, uuid) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- B2) calculate_asset_criticality — MISMA firma y misma API pública que en
-- 20260829190000. Lo único que cambia: la validación y la fórmula ya no
-- viven aquí, se delegan al motor común de arriba. Autorización, escritura
-- del assessment, congelado de respuestas, update de assets.criticality y
-- asset_event se mantienen idénticos.
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

  INSERT INTO public.asset_criticality_assessments AS aca (
    asset_id, organization_id, score, calculated_criticality, manual_criticality, effective_criticality, notes, created_by_user_id
  ) VALUES (
    p_asset_id, v_asset.organization_id, v_score, v_calculated, v_asset.criticality, v_calculated, p_notes, auth.uid()
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
    'Criticidad evaluada: ' || v_calculated || ' (score ' || v_score || ')',
    jsonb_build_object('score', v_score, 'calculated_criticality', v_calculated, 'assessment_id', v_assessment.id),
    auth.uid()
  );

  RETURN v_assessment;
END;
$$;

-- =========================================================================
-- C) replace_criticality_matrix — reemplazo transaccional desde payload.
--
-- Lo usan tanto la importación de Excel como apply_criticality_template, así
-- que "validar → desactivar → insertar" existe en un solo lugar. Nunca
-- borra: la configuración anterior queda con is_active = false y las
-- evaluaciones históricas siguen apuntando a esas filas (sus snapshots ya
-- eran inmutables de todos modos).
--
-- Peso total != 100 NO bloquea (solo es advertencia en la UI), por diseño.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.replace_criticality_matrix(
  p_organization_id uuid,
  p_matrix jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parameters jsonb;
  v_parameter jsonb;
  v_option jsonb;
  v_codes text[] := ARRAY[]::text[];
  v_option_codes text[];
  v_code text;
  v_option_code text;
  v_index integer := 0;
  v_option_index integer;
  v_new_parameter_id uuid;
  v_is_active boolean;
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

  v_parameters := p_matrix->'parameters';

  IF v_parameters IS NULL OR jsonb_typeof(v_parameters) <> 'array' OR jsonb_array_length(v_parameters) = 0 THEN
    RAISE EXCEPTION 'p_matrix.parameters debe ser un arreglo con al menos un parámetro';
  END IF;

  -- PASADA 1: validar TODO el payload antes de tocar una sola fila.
  FOR v_parameter IN SELECT * FROM jsonb_array_elements(v_parameters) LOOP
    v_index := v_index + 1;
    v_code := NULLIF(TRIM(COALESCE(v_parameter->>'code', '')), '');
    v_is_active := COALESCE((v_parameter->>'is_active')::boolean, true);

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'Parámetro %: el código es obligatorio', v_index;
    END IF;
    IF LOWER(v_code) = ANY (SELECT LOWER(x) FROM unnest(v_codes) AS x) THEN
      RAISE EXCEPTION 'Código de parámetro duplicado: %', v_code;
    END IF;
    v_codes := array_append(v_codes, v_code);

    IF NULLIF(TRIM(COALESCE(v_parameter->>'name', '')), '') IS NULL THEN
      RAISE EXCEPTION 'Parámetro %s: el nombre es obligatorio', v_code;
    END IF;
    IF COALESCE((v_parameter->>'weight')::numeric, -1) < 0 THEN
      RAISE EXCEPTION 'Parámetro %: el peso debe ser >= 0', v_code;
    END IF;
    IF COALESCE((v_parameter->>'sequence')::integer, 0) <= 0 THEN
      RAISE EXCEPTION 'Parámetro %: el orden debe ser > 0', v_code;
    END IF;

    IF v_parameter->'options' IS NULL OR jsonb_typeof(v_parameter->'options') <> 'array' THEN
      RAISE EXCEPTION 'Parámetro %: options debe ser un arreglo', v_code;
    END IF;

    v_option_codes := ARRAY[]::text[];
    v_option_index := 0;

    FOR v_option IN SELECT * FROM jsonb_array_elements(v_parameter->'options') LOOP
      v_option_index := v_option_index + 1;
      v_option_code := NULLIF(TRIM(COALESCE(v_option->>'code', '')), '');

      IF v_option_code IS NULL THEN
        RAISE EXCEPTION 'Parámetro %, opción %: el código es obligatorio', v_code, v_option_index;
      END IF;
      IF LOWER(v_option_code) = ANY (SELECT LOWER(x) FROM unnest(v_option_codes) AS x) THEN
        RAISE EXCEPTION 'Parámetro %: código de opción duplicado (%)', v_code, v_option_code;
      END IF;
      v_option_codes := array_append(v_option_codes, v_option_code);

      IF NULLIF(TRIM(COALESCE(v_option->>'label', '')), '') IS NULL THEN
        RAISE EXCEPTION 'Parámetro %, opción %: la etiqueta es obligatoria', v_code, v_option_code;
      END IF;
      IF COALESCE((v_option->>'score')::numeric, -1) < 0 THEN
        RAISE EXCEPTION 'Parámetro %, opción %: el puntaje debe ser >= 0', v_code, v_option_code;
      END IF;
      IF COALESCE((v_option->>'sequence')::integer, 0) <= 0 THEN
        RAISE EXCEPTION 'Parámetro %, opción %: el orden debe ser > 0', v_code, v_option_code;
      END IF;
    END LOOP;

    -- Un parámetro activo sin ninguna opción activa haría imposible
    -- responderlo, y calculate_asset_criticality exige responder todos los
    -- activos: la matriz quedaría inevaluable.
    IF v_is_active AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_parameter->'options') o
      WHERE COALESCE((o.value->>'is_active')::boolean, true)
    ) THEN
      RAISE EXCEPTION 'Parámetro %: un parámetro activo necesita al menos una opción activa', v_code;
    END IF;
  END LOOP;

  -- PASADA 2: recién ahora se toca la base. Desactivar (NUNCA borrar) la
  -- configuración activa actual, incluidas sus opciones.
  UPDATE public.criticality_parameter_options cpo
  SET is_active = false
  WHERE cpo.is_active
    AND cpo.parameter_id IN (
      SELECT cp.id FROM public.criticality_parameters cp
      WHERE cp.organization_id = p_organization_id AND cp.is_active
    );

  UPDATE public.criticality_parameters cp
  SET is_active = false
  WHERE cp.organization_id = p_organization_id AND cp.is_active;

  -- PASADA 3: insertar la configuración nueva.
  FOR v_parameter IN SELECT * FROM jsonb_array_elements(v_parameters) LOOP
    INSERT INTO public.criticality_parameters AS cp (
      organization_id, code, name, description, weight, sequence, is_active
    ) VALUES (
      p_organization_id,
      TRIM(v_parameter->>'code'),
      TRIM(v_parameter->>'name'),
      NULLIF(TRIM(COALESCE(v_parameter->>'description', '')), ''),
      (v_parameter->>'weight')::numeric,
      (v_parameter->>'sequence')::integer,
      COALESCE((v_parameter->>'is_active')::boolean, true)
    ) RETURNING cp.id INTO v_new_parameter_id;

    FOR v_option IN SELECT * FROM jsonb_array_elements(v_parameter->'options') LOOP
      INSERT INTO public.criticality_parameter_options (
        parameter_id, code, label, score, sequence, is_active
      ) VALUES (
        v_new_parameter_id,
        TRIM(v_option->>'code'),
        TRIM(v_option->>'label'),
        (v_option->>'score')::numeric,
        (v_option->>'sequence')::integer,
        COALESCE((v_option->>'is_active')::boolean, true)
      );
    END LOOP;
  END LOOP;

  RETURN public.get_criticality_matrix(p_organization_id, true);
END;
$$;

REVOKE ALL ON FUNCTION public.replace_criticality_matrix(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_criticality_matrix(uuid, jsonb) TO authenticated;

-- =========================================================================
-- D1) Plantillas de matriz de criticidad.
-- scope = 'system'        -> organization_id IS NULL      (catálogo global)
-- scope = 'organization'  -> organization_id IS NOT NULL  (privada del tenant)
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.criticality_matrix_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text NULL,
  category text NULL,
  scope text NOT NULL DEFAULT 'organization',
  is_active boolean NOT NULL DEFAULT true,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT criticality_matrix_templates_name_check CHECK (TRIM(name) <> ''),
  CONSTRAINT criticality_matrix_templates_scope_check CHECK (scope IN ('system', 'organization')),
  CONSTRAINT criticality_matrix_templates_scope_org_check CHECK (
    (scope = 'system' AND organization_id IS NULL)
    OR (scope = 'organization' AND organization_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_criticality_matrix_templates_organization_id
  ON public.criticality_matrix_templates (organization_id, is_active);
CREATE INDEX IF NOT EXISTS idx_criticality_matrix_templates_scope
  ON public.criticality_matrix_templates (scope, is_active);

DROP TRIGGER IF EXISTS trg_criticality_matrix_templates_updated_at ON public.criticality_matrix_templates;
CREATE TRIGGER trg_criticality_matrix_templates_updated_at
BEFORE UPDATE ON public.criticality_matrix_templates
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE IF NOT EXISTS public.criticality_template_parameters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES public.criticality_matrix_templates(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  description text NULL,
  weight numeric(5, 2) NOT NULL DEFAULT 0,
  sequence integer NOT NULL DEFAULT 1,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT criticality_template_parameters_code_check CHECK (TRIM(code) <> ''),
  CONSTRAINT criticality_template_parameters_name_check CHECK (TRIM(name) <> ''),
  CONSTRAINT criticality_template_parameters_weight_check CHECK (weight >= 0),
  CONSTRAINT criticality_template_parameters_sequence_check CHECK (sequence > 0)
);

CREATE INDEX IF NOT EXISTS idx_criticality_template_parameters_template_id
  ON public.criticality_template_parameters (template_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_criticality_template_parameters_code
  ON public.criticality_template_parameters (template_id, LOWER(code));

DROP TRIGGER IF EXISTS trg_criticality_template_parameters_updated_at ON public.criticality_template_parameters;
CREATE TRIGGER trg_criticality_template_parameters_updated_at
BEFORE UPDATE ON public.criticality_template_parameters
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE IF NOT EXISTS public.criticality_template_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_parameter_id uuid NOT NULL REFERENCES public.criticality_template_parameters(id) ON DELETE CASCADE,
  code text NOT NULL,
  label text NOT NULL,
  score numeric(8, 2) NOT NULL DEFAULT 0,
  sequence integer NOT NULL DEFAULT 1,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT criticality_template_options_code_check CHECK (TRIM(code) <> ''),
  CONSTRAINT criticality_template_options_label_check CHECK (TRIM(label) <> ''),
  CONSTRAINT criticality_template_options_score_check CHECK (score >= 0),
  CONSTRAINT criticality_template_options_sequence_check CHECK (sequence > 0)
);

CREATE INDEX IF NOT EXISTS idx_criticality_template_options_parameter_id
  ON public.criticality_template_options (template_parameter_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_criticality_template_options_code
  ON public.criticality_template_options (template_parameter_id, LOWER(code));

DROP TRIGGER IF EXISTS trg_criticality_template_options_updated_at ON public.criticality_template_options;
CREATE TRIGGER trg_criticality_template_options_updated_at
BEFORE UPDATE ON public.criticality_template_options
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- =========================================================================
-- D2) RLS de plantillas. Solo SELECT por policy; toda escritura pasa por las
-- RPC SECURITY DEFINER (mismo patrón que el resto de este módulo: ninguna
-- de las 4 tablas de criticidad tiene policy de INSERT/UPDATE/DELETE).
--
-- Una plantilla 'organization' de Cliente A es invisible para Cliente B —
-- ni por SELECT directo ni por las RPC, que repiten el mismo chequeo.
-- =========================================================================
ALTER TABLE public.criticality_matrix_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.criticality_template_parameters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.criticality_template_options ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authorized users can view criticality templates" ON public.criticality_matrix_templates;
CREATE POLICY "authorized users can view criticality templates" ON public.criticality_matrix_templates
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR scope = 'system'
    OR (organization_id IS NOT NULL AND (SELECT public.is_organization_member(organization_id)))
  );

DROP POLICY IF EXISTS "authorized users can view criticality template parameters" ON public.criticality_template_parameters;
CREATE POLICY "authorized users can view criticality template parameters" ON public.criticality_template_parameters
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.criticality_matrix_templates cmt
      WHERE cmt.id = criticality_template_parameters.template_id
        AND (
          public.is_platform_admin()
          OR cmt.scope = 'system'
          OR (cmt.organization_id IS NOT NULL AND public.is_organization_member(cmt.organization_id))
        )
    )
  );

DROP POLICY IF EXISTS "authorized users can view criticality template options" ON public.criticality_template_options;
CREATE POLICY "authorized users can view criticality template options" ON public.criticality_template_options
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.criticality_template_parameters ctp
      INNER JOIN public.criticality_matrix_templates cmt ON cmt.id = ctp.template_id
      WHERE ctp.id = criticality_template_options.template_parameter_id
        AND (
          public.is_platform_admin()
          OR cmt.scope = 'system'
          OR (cmt.organization_id IS NOT NULL AND public.is_organization_member(cmt.organization_id))
        )
    )
  );

GRANT SELECT ON TABLE public.criticality_matrix_templates TO authenticated;
GRANT SELECT ON TABLE public.criticality_template_parameters TO authenticated;
GRANT SELECT ON TABLE public.criticality_template_options TO authenticated;

-- =========================================================================
-- D3) can_access_criticality_template — helper interno de visibilidad,
-- compartido por las 3 RPC de plantillas para no repetir la regla.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.can_access_criticality_template(p_template_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.criticality_matrix_templates cmt
    WHERE cmt.id = p_template_id
      AND (
        public.is_platform_admin()
        OR cmt.scope = 'system'
        OR (cmt.organization_id IS NOT NULL AND public.is_organization_member(cmt.organization_id))
      )
  );
$$;

REVOKE ALL ON FUNCTION public.can_access_criticality_template(uuid) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- D4) get_criticality_templates — plantillas system + las propias del tenant.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_criticality_templates(p_organization_id uuid)
RETURNS TABLE (
  id uuid,
  organization_id uuid,
  scope text,
  name text,
  description text,
  category text,
  is_active boolean,
  parameter_count integer,
  option_count integer,
  total_weight numeric,
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
    RAISE EXCEPTION 'Not authorized to view criticality templates for this organization';
  END IF;

  RETURN QUERY
  SELECT
    cmt.id,
    cmt.organization_id,
    cmt.scope,
    cmt.name,
    cmt.description,
    cmt.category,
    cmt.is_active,
    COALESCE((
      SELECT COUNT(*)::integer FROM public.criticality_template_parameters ctp
      WHERE ctp.template_id = cmt.id AND ctp.is_active
    ), 0) AS parameter_count,
    COALESCE((
      SELECT COUNT(*)::integer
      FROM public.criticality_template_options cto
      INNER JOIN public.criticality_template_parameters ctp2 ON ctp2.id = cto.template_parameter_id
      WHERE ctp2.template_id = cmt.id AND ctp2.is_active AND cto.is_active
    ), 0) AS option_count,
    COALESCE((
      SELECT SUM(ctp3.weight) FROM public.criticality_template_parameters ctp3
      WHERE ctp3.template_id = cmt.id AND ctp3.is_active
    ), 0)::numeric AS total_weight,
    cmt.created_at
  FROM public.criticality_matrix_templates cmt
  WHERE cmt.is_active
    AND (
      cmt.scope = 'system'
      OR cmt.organization_id = p_organization_id
    )
  ORDER BY cmt.scope DESC, cmt.name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_criticality_templates(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_criticality_templates(uuid) TO authenticated;

-- =========================================================================
-- D5) get_criticality_template — cabecera + parámetros + opciones.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_criticality_template(p_template_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template public.criticality_matrix_templates%ROWTYPE;
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

  RETURN jsonb_build_object(
    'id', v_template.id,
    'organization_id', v_template.organization_id,
    'scope', v_template.scope,
    'name', v_template.name,
    'description', v_template.description,
    'category', v_template.category,
    'is_active', v_template.is_active,
    'created_at', v_template.created_at,
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

-- =========================================================================
-- D6) apply_criticality_template — arma el payload desde la plantilla y
-- delega en replace_criticality_matrix, así "reemplazar la matriz" tiene una
-- sola implementación (validar → desactivar → insertar, transaccional).
-- =========================================================================
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

  -- Cliente B no puede aplicar una plantilla privada de Cliente A: la misma
  -- regla de visibilidad que la policy SELECT, revalidada aquí.
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

  RETURN public.replace_criticality_matrix(p_organization_id, v_payload);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_criticality_template(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_criticality_template(uuid, uuid) TO authenticated;

-- =========================================================================
-- D7) create_template_from_current_matrix — congela la matriz ACTIVA actual
-- como plantilla privada de la organización. No copia evaluaciones.
-- =========================================================================
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

  INSERT INTO public.criticality_matrix_templates AS cmt (
    organization_id, name, description, category, scope, is_active, created_by_user_id
  ) VALUES (
    p_organization_id,
    TRIM(p_name),
    NULLIF(TRIM(COALESCE(p_description, '')), ''),
    NULLIF(TRIM(COALESCE(p_category, '')), ''),
    'organization',
    true,
    auth.uid()
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
-- E1) preview_bulk_asset_criticality — NO escribe nada. Devuelve, fila por
-- fila, el resultado que tendría la evaluación, calculado por el MISMO
-- motor (validate_and_score_asset_criticality) que usa la evaluación real.
-- El score del preview nunca sale de una fórmula paralela en JS.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.preview_bulk_asset_criticality(
  p_organization_id uuid,
  p_rows jsonb
)
RETURNS TABLE (
  row_number integer,
  asset_id uuid,
  asset_code text,
  asset_name text,
  valid boolean,
  score numeric,
  calculated_criticality text,
  errors jsonb,
  warnings jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row jsonb;
  v_result jsonb;
  v_asset_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to evaluate criticality for this organization';
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'p_rows debe ser un arreglo';
  END IF;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    v_asset_id := NULLIF(v_row->>'asset_id', '')::uuid;
    row_number := COALESCE((v_row->>'row_number')::integer, 0);

    IF v_asset_id IS NULL THEN
      asset_id := NULL;
      asset_code := NULL;
      asset_name := NULL;
      valid := false;
      score := NULL;
      calculated_criticality := NULL;
      errors := to_jsonb(ARRAY['La fila no tiene un ID interno de activo válido.']);
      warnings := '[]'::jsonb;
      RETURN NEXT;
      CONTINUE;
    END IF;

    v_result := public.validate_and_score_asset_criticality(
      v_asset_id, v_row->'answers', p_organization_id
    );

    asset_id := v_asset_id;
    asset_code := v_result->>'asset_code';
    asset_name := v_result->>'asset_name';
    valid := (v_result->>'valid')::boolean;
    score := NULLIF(v_result->>'score', '')::numeric;
    calculated_criticality := v_result->>'calculated_criticality';
    errors := v_result->'errors';
    warnings := v_result->'warnings';
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.preview_bulk_asset_criticality(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_bulk_asset_criticality(uuid, jsonb) TO authenticated;

-- =========================================================================
-- E2) bulk_calculate_asset_criticality — aplica un subconjunto ya
-- considerado válido por el preview, PERO revalida todo desde cero.
--
-- PASADA 1: valida las N filas con el motor común. Si alguna ya no es
-- válida (la matriz cambió entre el preview y el import, el activo se
-- archivó/borró, otro tenant, etc.) aborta el subset completo — nunca deja
-- evaluaciones parciales.
--
-- PASADA 2: delega cada fila en calculate_asset_criticality, que es el único
-- escritor de evaluaciones del sistema (assessment + snapshots +
-- assets.criticality + asset_event). Reimportar un activo crea SIEMPRE un
-- assessment nuevo; nunca sobrescribe el anterior.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.bulk_calculate_asset_criticality(
  p_organization_id uuid,
  p_rows jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row jsonb;
  v_result jsonb;
  v_asset_id uuid;
  v_row_number integer;
  v_failures text[] := ARRAY[]::text[];
  v_assessment public.asset_criticality_assessments%ROWTYPE;
  v_results jsonb := '[]'::jsonb;
  v_low integer := 0;
  v_medium integer := 0;
  v_high integer := 0;
  v_critical integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to evaluate criticality for this organization';
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'p_rows debe ser un arreglo con al menos una fila';
  END IF;

  -- PASADA 1 — validar todo, sin escribir.
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    v_row_number := COALESCE((v_row->>'row_number')::integer, 0);
    v_asset_id := NULLIF(v_row->>'asset_id', '')::uuid;

    IF v_asset_id IS NULL THEN
      v_failures := array_append(v_failures, format('Fila %s: ID interno de activo inválido', v_row_number));
      CONTINUE;
    END IF;

    v_result := public.validate_and_score_asset_criticality(v_asset_id, v_row->'answers', p_organization_id);

    IF NOT (v_result->>'valid')::boolean THEN
      v_failures := array_append(v_failures, format('Fila %s: %s', v_row_number,
        array_to_string(ARRAY(SELECT jsonb_array_elements_text(v_result->'errors')), '; ')));
    END IF;
  END LOOP;

  IF array_length(v_failures, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'No se aplicó ninguna evaluación: % fila(s) inválida(s). %',
      array_length(v_failures, 1), array_to_string(v_failures, ' | ');
  END IF;

  -- PASADA 2 — escribir, reutilizando el único escritor existente.
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    v_row_number := COALESCE((v_row->>'row_number')::integer, 0);
    v_asset_id := (v_row->>'asset_id')::uuid;

    v_assessment := public.calculate_asset_criticality(
      v_asset_id,
      v_row->'answers',
      NULLIF(TRIM(COALESCE(v_row->>'notes', '')), '')
    );

    v_results := v_results || jsonb_build_object(
      'row_number', v_row_number,
      'asset_id', v_asset_id,
      'assessment_id', v_assessment.id,
      'score', v_assessment.score,
      'calculated_criticality', v_assessment.calculated_criticality
    );

    CASE v_assessment.calculated_criticality
      WHEN 'low' THEN v_low := v_low + 1;
      WHEN 'medium' THEN v_medium := v_medium + 1;
      WHEN 'high' THEN v_high := v_high + 1;
      ELSE v_critical := v_critical + 1;
    END CASE;
  END LOOP;

  RETURN jsonb_build_object(
    'evaluated', jsonb_array_length(v_results),
    'counts', jsonb_build_object('low', v_low, 'medium', v_medium, 'high', v_high, 'critical', v_critical),
    'results', v_results
  );
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_calculate_asset_criticality(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bulk_calculate_asset_criticality(uuid, jsonb) TO authenticated;
