-- R2-E1.1: additive technical catalog foundation. No seed/import or rate changes.
SET LOCAL lock_timeout = '5s';
CREATE TABLE public.provider_material_families (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 code text NOT NULL CHECK (code=btrim(code) AND length(code) BETWEEN 1 AND 60),
 name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 200),
 is_active boolean NOT NULL DEFAULT true,
 created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (organization_id,id)
);
CREATE UNIQUE INDEX provider_material_families_code_idx ON public.provider_material_families(organization_id,lower(code));
CREATE TABLE public.provider_material_subfamilies (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 family_id uuid NOT NULL,
 code text NOT NULL CHECK (code=btrim(code) AND length(code) BETWEEN 1 AND 60),
 name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 200),
 is_active boolean NOT NULL DEFAULT true,
 created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (organization_id,family_id,id),
 FOREIGN KEY (organization_id,family_id) REFERENCES public.provider_material_families(organization_id,id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX provider_material_subfamilies_code_idx ON public.provider_material_subfamilies(organization_id,family_id,lower(code));
ALTER TABLE public.provider_cost_items
 ADD COLUMN material_family_id uuid,
 ADD COLUMN material_subfamily_id uuid,
 ADD COLUMN technical_validation_status text,
 ADD CONSTRAINT provider_cost_items_technical_status_check CHECK (technical_validation_status IN ('preliminary','in_review','validated')),
 ADD CONSTRAINT provider_cost_items_subfamily_requires_family CHECK (material_subfamily_id IS NULL OR material_family_id IS NOT NULL),
 ADD CONSTRAINT provider_cost_items_material_family_fk FOREIGN KEY (organization_id,material_family_id) REFERENCES public.provider_material_families(organization_id,id) ON DELETE RESTRICT,
 ADD CONSTRAINT provider_cost_items_material_subfamily_fk FOREIGN KEY (organization_id,material_family_id,material_subfamily_id) REFERENCES public.provider_material_subfamilies(organization_id,family_id,id) ON DELETE RESTRICT;
-- Legacy rows remain NULL; newly created items default to preliminary.
ALTER TABLE public.provider_cost_items ALTER COLUMN technical_validation_status SET DEFAULT 'preliminary';
CREATE INDEX provider_cost_items_material_family_idx ON public.provider_cost_items(organization_id,material_family_id,material_subfamily_id);
CREATE TABLE public.provider_catalog_import_batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 source_system text NOT NULL CHECK (source_system=btrim(source_system) AND length(source_system) BETWEEN 1 AND 60),
 content_sha256 text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
 status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','validated','imported','failed')),
 expected_rows integer NOT NULL CHECK (expected_rows>=0),
 created_by uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (organization_id,id),
 UNIQUE (organization_id,source_system,content_sha256)
);
CREATE TABLE public.provider_cost_item_sources (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 batch_id uuid NOT NULL,
 cost_item_id uuid,
 source_system text NOT NULL CHECK (source_system=btrim(source_system) AND length(source_system) BETWEEN 1 AND 60),
 source_code text NOT NULL CHECK (source_code=btrim(source_code) AND length(source_code) BETWEEN 1 AND 100),
 source_name text NOT NULL CHECK (length(btrim(source_name)) BETWEEN 1 AND 500),
 source_unit text NOT NULL CHECK (length(btrim(source_unit)) BETWEEN 1 AND 60),
 source_family text,
 source_subfamily text,
 source_specification text,
 source_brand text,
 mapping_status text NOT NULL DEFAULT 'pending' CHECK (mapping_status IN ('pending','confirmed','needs_review')),
 created_by uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (mapping_status <> 'confirmed' OR cost_item_id IS NOT NULL),
 FOREIGN KEY (organization_id,cost_item_id) REFERENCES public.provider_cost_items(organization_id,id) ON DELETE RESTRICT
);
ALTER TABLE public.provider_catalog_import_batches ADD CONSTRAINT provider_catalog_import_batches_tenant_source_id UNIQUE(organization_id,source_system,id);
ALTER TABLE public.provider_cost_item_sources ADD CONSTRAINT provider_cost_item_sources_batch_fk FOREIGN KEY(organization_id,source_system,batch_id) REFERENCES public.provider_catalog_import_batches(organization_id,source_system,id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX provider_cost_item_sources_identity_idx ON public.provider_cost_item_sources(organization_id,source_system,lower(source_code));
CREATE INDEX provider_cost_item_sources_item_idx ON public.provider_cost_item_sources(organization_id,cost_item_id);
CREATE INDEX provider_cost_item_sources_batch_idx ON public.provider_cost_item_sources(organization_id,source_system,batch_id);
ALTER TABLE public.provider_material_families ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_material_families FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.provider_material_families TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.provider_material_families TO service_role;
CREATE POLICY provider_material_families_read ON public.provider_material_families FOR SELECT TO authenticated USING (public.is_organization_member(organization_id));
ALTER TABLE public.provider_material_subfamilies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_material_subfamilies FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.provider_material_subfamilies TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.provider_material_subfamilies TO service_role;
CREATE POLICY provider_material_subfamilies_read ON public.provider_material_subfamilies FOR SELECT TO authenticated USING (public.is_organization_member(organization_id));
ALTER TABLE public.provider_cost_item_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_cost_item_sources FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.provider_cost_item_sources TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.provider_cost_item_sources TO service_role;
CREATE POLICY provider_cost_item_sources_read ON public.provider_cost_item_sources FOR SELECT TO authenticated USING (public.is_organization_member(organization_id));
ALTER TABLE public.provider_catalog_import_batches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_catalog_import_batches FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.provider_catalog_import_batches TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.provider_catalog_import_batches TO service_role;
CREATE POLICY provider_catalog_import_batches_read ON public.provider_catalog_import_batches FOR SELECT TO authenticated USING (public.is_organization_member(organization_id));
GRANT INSERT (organization_id,code,name,is_active) ON public.provider_material_families TO authenticated;
GRANT UPDATE (name,is_active) ON public.provider_material_families TO authenticated;
CREATE POLICY provider_material_families_insert ON public.provider_material_families FOR INSERT TO authenticated WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active') AND created_by=auth.uid());
CREATE POLICY provider_material_families_update ON public.provider_material_families FOR UPDATE TO authenticated USING (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active')) WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active'));
CREATE TRIGGER provider_material_families_updated_at BEFORE UPDATE ON public.provider_material_families FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
GRANT INSERT (organization_id,family_id,code,name,is_active) ON public.provider_material_subfamilies TO authenticated;
GRANT UPDATE (name,is_active) ON public.provider_material_subfamilies TO authenticated;
CREATE POLICY provider_material_subfamilies_insert ON public.provider_material_subfamilies FOR INSERT TO authenticated WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active') AND created_by=auth.uid());
CREATE POLICY provider_material_subfamilies_update ON public.provider_material_subfamilies FOR UPDATE TO authenticated USING (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active')) WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active'));
CREATE TRIGGER provider_material_subfamilies_updated_at BEFORE UPDATE ON public.provider_material_subfamilies FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
-- Classification and source reconciliation are controlled server-side until import/validation RPCs exist.
-- Existing grants and economic tables intentionally unchanged.
COMMENT ON COLUMN public.provider_cost_items.technical_validation_status IS 'NULL = legacy/unassessed; preliminary is not commercial approval. No commercial eligibility in R2-E1.1.';
COMMENT ON TABLE public.provider_cost_item_sources IS 'Technical source identity only; never store market costs, prices or supplier records here. Unresolved source rows may have no canonical item.';
COMMENT ON TABLE public.provider_catalog_import_batches IS 'Import manifest and digest; no raw workbook or pricing data.';
