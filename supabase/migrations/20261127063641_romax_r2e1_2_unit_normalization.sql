-- R2-E1.2: system-managed presentation units and a strict ROMAX import resolver.
-- No changes to existing unit metadata, items, rates, inventory or tenant data.
INSERT INTO public.provider_cost_units(code,name,dimension,aliases,is_active) VALUES
 ('CAJA','Caja','count',ARRAY[]::text[],true),
 ('BOLSA','Bolsa','count',ARRAY[]::text[],true),
 ('BALDE','Balde','count',ARRAY[]::text[],true),
 ('MILLAR','Millar','count',ARRAY[]::text[],true),
 ('PAR','Par','count',ARRAY[]::text[],true),
 ('PQT','Paquete','count',ARRAY[]::text[],true)
ON CONFLICT (code) DO NOTHING;

-- A collision with incompatible metadata must abort rather than overwrite another catalog.
DO $$
BEGIN
 IF EXISTS (
  SELECT 1 FROM (VALUES ('CAJA','Caja'),('BOLSA','Bolsa'),('BALDE','Balde'),('MILLAR','Millar'),('PAR','Par'),('PQT','Paquete')) AS expected(code,name)
  LEFT JOIN public.provider_cost_units u ON u.code=expected.code
  WHERE u.code IS NULL OR u.name IS DISTINCT FROM expected.name OR u.dimension IS DISTINCT FROM 'count'
    OR u.aliases IS DISTINCT FROM ARRAY[]::text[] OR u.is_active IS DISTINCT FROM true
 ) THEN
   RAISE EXCEPTION 'R2-E1.2: incompatible presentation unit; review manually';
 END IF;
 IF EXISTS (
   SELECT 1 FROM public.provider_cost_units u
   CROSS JOIN LATERAL unnest(u.aliases) AS a(alias)
   WHERE upper(btrim(a.alias)) IN ('CAJA','BOLSA','BALDE','MILLAR','PAR','PQT')
     AND upper(btrim(a.alias)) <> u.code
 ) THEN
   RAISE EXCEPTION 'R2-E1.2: presentation code conflicts with an existing alias';
 END IF;
END $$;

-- Profile-specific exact identity resolution, never a physical conversion.
-- NULL means unresolved: importer must retain raw text and stage for manual review.
CREATE FUNCTION public.resolve_romax_material_import_unit(p_raw_unit text)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
 SELECT u.code
 FROM public.provider_cost_units AS u
 WHERE u.is_active AND u.code = CASE upper(btrim(p_raw_unit))
  WHEN 'UND' THEN 'UND'
  WHEN 'M' THEN 'M'
  WHEN 'ML' THEN 'M'
  WHEN 'GALÓN' THEN 'GAL'
  WHEN 'KG' THEN 'KG'
  WHEN 'ROLLO' THEN 'ROLLO'
  WHEN 'RLL' THEN 'ROLLO'
  WHEN 'M2' THEN 'M2'
  WHEN 'M3' THEN 'M3'
  WHEN 'CAJA' THEN 'CAJA'
  WHEN 'BOLSA' THEN 'BOLSA'
  WHEN 'BALDE' THEN 'BALDE'
  WHEN 'MILLAR' THEN 'MILLAR'
  WHEN 'PAR' THEN 'PAR'
  WHEN 'PQT' THEN 'PQT'
  WHEN 'GALON' THEN 'GAL'
  ELSE NULL
 END
$$;
REVOKE ALL ON FUNCTION public.resolve_romax_material_import_unit(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_romax_material_import_unit(text) TO authenticated,service_role;
COMMENT ON FUNCTION public.resolve_romax_material_import_unit(text) IS 'Strict ROMAX matrix v1 unit lookup only; GL, ZZ, unknown, inactive and empty inputs return NULL. No quantity or price conversion.';
