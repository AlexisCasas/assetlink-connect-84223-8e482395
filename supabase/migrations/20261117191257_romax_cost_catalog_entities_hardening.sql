CREATE INDEX provider_cost_suppliers_created_by_idx ON public.provider_cost_suppliers(created_by);
CREATE INDEX provider_cost_items_created_by_idx ON public.provider_cost_items(created_by);
CREATE INDEX provider_cost_items_category_code_idx ON public.provider_cost_items(category_code);
CREATE INDEX provider_cost_items_default_unit_code_idx ON public.provider_cost_items(default_unit_code);
DROP POLICY provider_cost_suppliers_insert ON public.provider_cost_suppliers;
CREATE POLICY provider_cost_suppliers_insert ON public.provider_cost_suppliers FOR INSERT TO authenticated WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active') AND created_by=(select auth.uid()));
DROP POLICY provider_cost_items_insert ON public.provider_cost_items;
CREATE POLICY provider_cost_items_insert ON public.provider_cost_items FOR INSERT TO authenticated WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active') AND created_by=(select auth.uid()));