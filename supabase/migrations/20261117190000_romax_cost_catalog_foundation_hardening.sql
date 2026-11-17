-- R2A-01 hardening follow-up: index audit FK and cache auth.uid() in RLS policies.
CREATE INDEX provider_cost_settings_updated_by_idx
 ON public.provider_cost_settings(updated_by);

DROP POLICY provider_cost_settings_insert ON public.provider_cost_settings;
CREATE POLICY provider_cost_settings_insert ON public.provider_cost_settings
 FOR INSERT TO authenticated WITH CHECK (
   public.has_organization_role(organization_id,ARRAY['owner','admin','manager']::public.organization_member_role[])
   AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active')
   AND updated_by=(select auth.uid())
 );

DROP POLICY provider_cost_settings_update ON public.provider_cost_settings;
CREATE POLICY provider_cost_settings_update ON public.provider_cost_settings
 FOR UPDATE TO authenticated
 USING (public.has_organization_role(organization_id,ARRAY['owner','admin','manager']::public.organization_member_role[]))
 WITH CHECK (public.has_organization_role(organization_id,ARRAY['owner','admin','manager']::public.organization_member_role[]) AND updated_by=(select auth.uid()));
