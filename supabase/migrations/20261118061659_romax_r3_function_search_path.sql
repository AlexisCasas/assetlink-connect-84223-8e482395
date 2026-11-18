-- Harden R3 helper functions against search_path hijacking.
alter function public.romax_set_updated_at() set search_path = public;
alter function public.validate_romax_opportunity_links() set search_path = public;
alter function public.validate_romax_opportunity_attachment_org() set search_path = public;
