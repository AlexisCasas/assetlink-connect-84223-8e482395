-- PostgREST needs object privileges before it can evaluate tenant RLS policies.
-- These grants intentionally expose only the tenant-aware surface; RLS remains
-- the authorization boundary for every row and operation below.
GRANT USAGE ON SCHEMA public TO authenticated;

GRANT SELECT ON TABLE public.organizations TO authenticated;
GRANT SELECT ON TABLE public.organization_members TO authenticated;
GRANT SELECT ON TABLE public.organization_relationships TO authenticated;
GRANT SELECT ON TABLE public.client_branches TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.requests TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.request_details TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.quotes TO authenticated;
GRANT SELECT ON TABLE public.request_provider_access TO authenticated;
GRANT SELECT, UPDATE ON TABLE public.organization_notifications TO authenticated;
GRANT SELECT ON TABLE public.work_orders TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_user_organizations() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_organization_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_organization_role(uuid, public.organization_member_role[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_read_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_provider_quote_request(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_read_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_quote(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_work_order_from_quote(uuid) TO authenticated;
