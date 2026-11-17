-- R2A / Migration 1 of 3
-- Global cost categories and units; per-organization currency settings.
-- No production application performed by this file.

CREATE TABLE public.provider_cost_categories (
  code text PRIMARY KEY,
  name text NOT NULL,
  cost_level text NOT NULL CHECK (cost_level IN ('direct','indirect')),
  sort_order integer NOT NULL CHECK (sort_order > 0),
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT provider_cost_categories_code_check CHECK (code ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  CONSTRAINT provider_cost_categories_name_check CHECK (length(btrim(name)) BETWEEN 1 AND 100)
);

CREATE TABLE public.provider_cost_units (
  code text PRIMARY KEY,
  name text NOT NULL,
  dimension text NOT NULL,
  aliases text[] NOT NULL DEFAULT '{}',
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT provider_cost_units_code_check CHECK (code ~ '^[A-Z][A-Z0-9_]{0,19}$'),
  CONSTRAINT provider_cost_units_name_check CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  CONSTRAINT provider_cost_units_dimension_check CHECK (dimension IN ('count','length','area','volume','mass','time','service','trip'))
);

INSERT INTO public.provider_cost_categories(code,name,cost_level,sort_order) VALUES
 ('LABOR','Mano de obra','direct',10),
 ('MATERIAL','Materiales y consumibles','direct',20),
 ('EQUIPMENT','Equipos y maquinaria','direct',30),
 ('SUBCONTRACT','Servicios subcontratados','direct',40),
 ('MOBILIZATION','Movilización','direct',50),
 ('DEMOBILIZATION','Desmovilización','direct',60),
 ('OTHER_DIRECT','Otros costos directos','direct',70),
 ('GENERAL_EXPENSE','Gastos generales','indirect',80)
ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name,cost_level=EXCLUDED.cost_level,sort_order=EXCLUDED.sort_order;

INSERT INTO public.provider_cost_units(code,name,dimension,aliases) VALUES
 ('UND','Unidad','count',ARRAY['UNIDAD','UN','PZA']),
 ('M','Metro','length',ARRAY['ML','MT']),
 ('M2','Metro cuadrado','area',ARRAY['M²']),
 ('M3','Metro cúbico','volume',ARRAY['M³']),
 ('KG','Kilogramo','mass',ARRAY['KILO']),
 ('H','Hora','time',ARRAY['HR']),
 ('DIA','Día','time',ARRAY['D']),
 ('JOR','Jornada','time',ARRAY['JORNAL']),
 ('GLB','Global','service',ARRAY['GBL','GLOBAL']),
 ('VIAJE','Viaje','trip',ARRAY['VJ']),
 ('LT','Litro','volume',ARRAY['L']),
 ('GAL','Galón','volume',ARRAY['GALON']),
 ('ROLLO','Rollo','count',ARRAY['RLL'])
ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name,dimension=EXCLUDED.dimension,aliases=EXCLUDED.aliases;

ALTER TABLE public.provider_cost_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_cost_units ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.provider_cost_categories,public.provider_cost_units FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.provider_cost_categories,public.provider_cost_units TO authenticated,service_role;

CREATE POLICY provider_cost_categories_read ON public.provider_cost_categories
 FOR SELECT TO authenticated USING (true);
CREATE POLICY provider_cost_units_read ON public.provider_cost_units
 FOR SELECT TO authenticated USING (true);

CREATE TABLE public.provider_cost_settings (
 organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
 base_currency_code text NOT NULL DEFAULT 'PEN' CHECK (base_currency_code='PEN'),
 default_usd_pen_rate numeric(12,6),
 fx_source text,
 fx_date date,
 fx_reference text,
 updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT provider_cost_settings_fx_positive CHECK (default_usd_pen_rate IS NULL OR default_usd_pen_rate > 0),
 CONSTRAINT provider_cost_settings_fx_metadata CHECK (
   (default_usd_pen_rate IS NULL AND fx_source IS NULL AND fx_date IS NULL AND fx_reference IS NULL)
   OR (default_usd_pen_rate IS NOT NULL AND fx_source IS NOT NULL AND length(btrim(fx_source))>0 AND fx_date IS NOT NULL)
 )
);

ALTER TABLE public.provider_cost_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_cost_settings FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.provider_cost_settings TO authenticated;
CREATE POLICY provider_cost_settings_read ON public.provider_cost_settings
 FOR SELECT TO authenticated USING (public.is_organization_member(organization_id));
CREATE POLICY provider_cost_settings_insert ON public.provider_cost_settings
 FOR INSERT TO authenticated WITH CHECK (
   public.has_organization_role(organization_id,ARRAY['owner','admin','manager']::public.organization_member_role[])
   AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active')
 );
CREATE POLICY provider_cost_settings_update ON public.provider_cost_settings
 FOR UPDATE TO authenticated
 USING (public.has_organization_role(organization_id,ARRAY['owner','admin','manager']::public.organization_member_role[]))
 WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager']::public.organization_member_role[]));

CREATE TRIGGER provider_cost_settings_updated_at
 BEFORE UPDATE ON public.provider_cost_settings
 FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

COMMENT ON TABLE public.provider_cost_categories IS 'System-managed categories for provider cost resources; not customer-facing quote sections.';
COMMENT ON TABLE public.provider_cost_units IS 'System-managed normalized units; aliases support import normalization only and do not imply conversions.';
COMMENT ON TABLE public.provider_cost_settings IS 'Per-provider organization economic defaults. FX rate intentionally starts NULL until ROMAX configures a documented value.';
