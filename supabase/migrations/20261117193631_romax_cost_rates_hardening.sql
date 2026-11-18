CREATE INDEX provider_cost_rates_created_by_idx ON public.provider_cost_rates(created_by);
CREATE INDEX provider_cost_rates_reviewed_by_idx ON public.provider_cost_rates(reviewed_by);
CREATE INDEX provider_cost_rates_supplier_idx ON public.provider_cost_rates(organization_id,supplier_id);
CREATE INDEX provider_cost_rates_unit_code_idx ON public.provider_cost_rates(unit_code);
DROP POLICY provider_cost_rates_insert ON public.provider_cost_rates;
CREATE POLICY provider_cost_rates_insert ON public.provider_cost_rates FOR INSERT TO authenticated WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]) AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active') AND created_by=(select auth.uid()) AND status IN ('draft','pending_review'));