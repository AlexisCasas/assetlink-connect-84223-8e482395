-- R2A / Migration 2 of 3
-- Organization-owned suppliers and reusable cost resources.

CREATE TABLE public.provider_cost_suppliers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 display_name text NOT NULL,
 legal_name text,
 tax_id text,
 email text,
 phone text,
 notes text,
 is_active boolean NOT NULL DEFAULT true,
 created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT provider_cost_suppliers_name_check CHECK (length(btrim(display_name)) BETWEEN 1 AND 200),
 CONSTRAINT provider_cost_suppliers_tax_id_check CHECK (tax_id IS NULL OR length(btrim(tax_id)) BETWEEN 8 AND 20),
 CONSTRAINT provider_cost_suppliers_tenant_id_unique UNIQUE (organization_id,id)
);
CREATE UNIQUE INDEX provider_cost_suppliers_tax_id_unique
 ON public.provider_cost_suppliers(organization_id,tax_id) WHERE tax_id IS NOT NULL;
CREATE INDEX provider_cost_suppliers_name_idx
 ON public.provider_cost_suppliers(organization_id,lower(display_name));

CREATE TABLE public.provider_cost_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 code text,
 name text NOT NULL,
 description text,
 category_code text NOT NULL REFERENCES public.provider_cost_categories(code) ON DELETE RESTRICT,
 default_unit_code text NOT NULL REFERENCES public.provider_cost_units(code) ON DELETE RESTRICT,
 technical_specification text,
 is_active boolean NOT NULL DEFAULT true,
 created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT provider_cost_items_name_check CHECK (length(btrim(name)) BETWEEN 1 AND 200),
 CONSTRAINT provider_cost_items_code_check CHECK (code IS NULL OR length(btrim(code)) BETWEEN 1 AND 60),
 CONSTRAINT provider_cost_items_tenant_id_unique UNIQUE (organization_id,id)
);
CREATE UNIQUE INDEX provider_cost_items_code_unique
 ON public.provider_cost_items(organization_id,lower(code)) WHERE code IS NOT NULL;
CREATE INDEX provider_cost_items_category_idx
 ON public.provider_cost_items(organization_id,category_code,is_active);
CREATE INDEX provider_cost_items_name_idx
 ON public.provider_cost_items(organization_id,lower(name));

CREATE TRIGGER provider_cost_suppliers_updated_at
 BEFORE UPDATE ON public.provider_cost_suppliers
 FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER provider_cost_items_updated_at
 BEFORE UPDATE ON public.provider_cost_items
 FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.provider_cost_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_cost_items ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.provider_cost_suppliers,public.provider_cost_items FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.provider_cost_suppliers,public.provider_cost_items TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.provider_cost_suppliers,public.provider_cost_items TO service_role;

CREATE POLICY provider_cost_suppliers_read ON public.provider_cost_suppliers
 FOR SELECT TO authenticated USING (public.is_organization_member(organization_id));
CREATE POLICY provider_cost_suppliers_insert ON public.provider_cost_suppliers
 FOR INSERT TO authenticated WITH CHECK (
  public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[])
  AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active')
  AND created_by=auth.uid()
);
CREATE POLICY provider_cost_suppliers_update ON public.provider_cost_suppliers
 FOR UPDATE TO authenticated
 USING (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]))
 WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]));

CREATE POLICY provider_cost_items_read ON public.provider_cost_items
 FOR SELECT TO authenticated USING (public.is_organization_member(organization_id));
CREATE POLICY provider_cost_items_insert ON public.provider_cost_items
 FOR INSERT TO authenticated WITH CHECK (
  public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[])
  AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active')
  AND created_by=auth.uid()
);
CREATE POLICY provider_cost_items_update ON public.provider_cost_items
 FOR UPDATE TO authenticated
 USING (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]))
 WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]));

COMMENT ON TABLE public.provider_cost_suppliers IS 'Provider-owned suppliers. Supplier is optional on cost rates for internal resources.';
COMMENT ON TABLE public.provider_cost_items IS 'Reusable cost resources, independent from client, warehouse inventory, and historical quotations.';
