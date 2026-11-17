-- One Facility / ROMAX R2-M1
-- Global reference data and per-provider currency configuration.
-- No production cost data is seeded. The default USD/PEN rate remains unset
-- until ROMAX configures a documented value.

CREATE TABLE public.provider_cost_categories (
  code text PRIMARY KEY,
  name text NOT NULL,
  cost_level text NOT NULL,
  sort_order smallint NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_cost_categories_code_check
    CHECK (code ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  CONSTRAINT provider_cost_categories_name_check
    CHECK (length(btrim(name)) BETWEEN 1 AND 100),
  CONSTRAINT provider_cost_categories_level_check
    CHECK (cost_level IN ('direct', 'indirect')),
  CONSTRAINT provider_cost_categories_sort_check
    CHECK (sort_order >= 0)
);

INSERT INTO public.provider_cost_categories (code, name, cost_level, sort_order)
VALUES
  ('LABOR', 'Mano de obra', 'direct', 10),
  ('MATERIAL', 'Materiales y consumibles', 'direct', 20),
  ('EQUIPMENT', 'Equipos y maquinaria', 'direct', 30),
  ('SUBCONTRACT', 'Servicios subcontratados', 'direct', 40),
  ('MOBILIZATION', 'Movilización', 'direct', 50),
  ('DEMOBILIZATION', 'Desmovilización', 'direct', 60),
  ('OTHER_DIRECT', 'Otros costos directos', 'direct', 70),
  ('GENERAL_EXPENSE', 'Gastos generales', 'indirect', 80);

CREATE TABLE public.provider_cost_units (
  code text PRIMARY KEY,
  name text NOT NULL,
  dimension text NOT NULL,
  aliases text[] NOT NULL DEFAULT '{}'::text[],
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_cost_units_code_check
    CHECK (code ~ '^[A-Z0-9_]{1,12}$'),
  CONSTRAINT provider_cost_units_name_check
    CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  CONSTRAINT provider_cost_units_dimension_check
    CHECK (dimension IN (
      'count', 'length', 'area', 'volume', 'mass',
      'time', 'day', 'workday', 'lump_sum', 'trip', 'container'
    ))
);

INSERT INTO public.provider_cost_units (code, name, dimension, aliases)
VALUES
  ('UND', 'Unidad', 'count', ARRAY['UNIDAD', 'UN', 'UNID']::text[]),
  ('M', 'Metro', 'length', ARRAY['ML', 'METRO', 'METRO LINEAL']::text[]),
  ('M2', 'Metro cuadrado', 'area', ARRAY['M²', 'METRO CUADRADO']::text[]),
  ('M3', 'Metro cúbico', 'volume', ARRAY['M³', 'METRO CUBICO']::text[]),
  ('KG', 'Kilogramo', 'mass', ARRAY['KILO', 'KILOGRAMO']::text[]),
  ('H', 'Hora', 'time', ARRAY['HR', 'HORA']::text[]),
  ('DIA', 'Día', 'day', ARRAY['DÍA', 'DIAS', 'DÍAS']::text[]),
  ('JOR', 'Jornada', 'workday', ARRAY['JORNADA']::text[]),
  ('GLB', 'Global', 'lump_sum', ARRAY['GBL', 'GLOBAL', 'SERVICIO GLOBAL']::text[]),
  ('VIAJE', 'Viaje', 'trip', ARRAY['TRASLADO']::text[]),
  ('LT', 'Litro', 'volume', ARRAY['L', 'LITRO']::text[]),
  ('GAL', 'Galón', 'volume', ARRAY['GALON', 'GALÓN']::text[]),
  ('ROLLO', 'Rollo', 'container', ARRAY['RLL']::text[]);

-- Reference tables are readable by authenticated users but are maintained
-- only through reviewed migrations. No anon access and no browser writes.
REVOKE ALL ON public.provider_cost_categories, public.provider_cost_units
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.provider_cost_categories, public.provider_cost_units
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.provider_cost_categories, public.provider_cost_units
  TO service_role;

ALTER TABLE public.provider_cost_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_cost_units ENABLE ROW LEVEL SECURITY;

CREATE POLICY provider_cost_categories_authenticated_read
  ON public.provider_cost_categories
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY provider_cost_units_authenticated_read
  ON public.provider_cost_units
  FOR SELECT TO authenticated
  USING (true);

CREATE TABLE public.provider_cost_settings (
  organization_id uuid PRIMARY KEY
    REFERENCES public.organizations(id) ON DELETE CASCADE,
  base_currency_code text NOT NULL DEFAULT 'PEN',
  default_usd_pen_rate numeric(12, 6),
  default_fx_source text,
  default_fx_date date,
  default_fx_reference text,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_cost_settings_base_currency_check
    CHECK (base_currency_code = 'PEN'),
  CONSTRAINT provider_cost_settings_default_fx_positive
    CHECK (default_usd_pen_rate IS NULL OR default_usd_pen_rate > 0),
  CONSTRAINT provider_cost_settings_default_fx_source_check
    CHECK (default_fx_source IS NULL OR default_fx_source IN ('manual', 'documented')),
  CONSTRAINT provider_cost_settings_default_fx_complete
    CHECK (
      (default_usd_pen_rate IS NULL
        AND default_fx_source IS NULL
        AND default_fx_date IS NULL
        AND default_fx_reference IS NULL)
      OR
      (default_usd_pen_rate IS NOT NULL
        AND default_fx_source IS NOT NULL
        AND default_fx_date IS NOT NULL
        AND default_fx_reference IS NOT NULL
        AND length(btrim(default_fx_reference)) > 0)
    )
);

CREATE FUNCTION public.provider_cost_settings_assert_provider_org()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.organizations o
    WHERE o.id = NEW.organization_id
      AND o.organization_type = 'provider_company'
      AND o.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cost settings require an active provider_company organization'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$;

CREATE TRIGGER provider_cost_settings_assert_provider_org
  BEFORE INSERT OR UPDATE OF organization_id
  ON public.provider_cost_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.provider_cost_settings_assert_provider_org();

CREATE FUNCTION public.provider_cost_settings_stamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := COALESCE(auth.uid(), NEW.updated_by);
  RETURN NEW;
END;
$;

CREATE TRIGGER provider_cost_settings_stamp_before_write
  BEFORE INSERT OR UPDATE ON public.provider_cost_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.provider_cost_settings_stamp();

REVOKE ALL ON public.provider_cost_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.provider_cost_settings TO authenticated;
GRANT INSERT (
  organization_id, base_currency_code, default_usd_pen_rate,
  default_fx_source, default_fx_date, default_fx_reference
) ON public.provider_cost_settings TO authenticated;
GRANT UPDATE (
  base_currency_code, default_usd_pen_rate,
  default_fx_source, default_fx_date, default_fx_reference
) ON public.provider_cost_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.provider_cost_settings TO service_role;

ALTER TABLE public.provider_cost_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY provider_cost_settings_read
  ON public.provider_cost_settings
  FOR SELECT TO authenticated
  USING (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
  );

CREATE POLICY provider_cost_settings_insert
  ON public.provider_cost_settings
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
    AND EXISTS (
      SELECT 1
      FROM public.organizations o
      WHERE o.id = organization_id
        AND o.organization_type = 'provider_company'
        AND o.status = 'active'
    )
  );

CREATE POLICY provider_cost_settings_update
  ON public.provider_cost_settings
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
  )
  WITH CHECK (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
    AND EXISTS (
      SELECT 1
      FROM public.organizations o
      WHERE o.id = organization_id
        AND o.organization_type = 'provider_company'
        AND o.status = 'active'
    )
  );

REVOKE ALL ON FUNCTION public.provider_cost_settings_assert_provider_org()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.provider_cost_settings_stamp()
  FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.provider_cost_categories IS
  'ROMAX cost categories. Global reference data, maintained through migrations.';
COMMENT ON TABLE public.provider_cost_units IS
  'Canonical units and import aliases. No implicit unit conversion is performed.';
COMMENT ON TABLE public.provider_cost_settings IS
  'Provider organization currency configuration. USD/PEN default remains NULL until explicitly configured with source and date.';
