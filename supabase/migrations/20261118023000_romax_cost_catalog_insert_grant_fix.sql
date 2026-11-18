-- R2A hardening: allow authenticated app clients to use database-generated
-- primary keys on provider-owned catalog entities.
-- Keep historical migrations immutable; this is additive and safe to reapply.
GRANT INSERT (id,organization_id,display_name,legal_name,tax_id,email,phone,notes,is_active)
  ON public.provider_cost_suppliers TO authenticated;

GRANT INSERT (id,organization_id,code,name,description,category_code,default_unit_code,technical_specification,is_active)
  ON public.provider_cost_items TO authenticated;
