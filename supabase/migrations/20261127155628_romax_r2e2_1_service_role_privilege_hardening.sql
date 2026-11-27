-- R2-E2.1 follow-up: remove default service_role TRUNCATE/DELETE and other broad table grants.
-- The service role retains only the DML needed by trusted server-side flows.
CREATE INDEX IF NOT EXISTS provider_pricing_access_grants_user_idx ON public.provider_pricing_access_grants(user_id);
CREATE INDEX IF NOT EXISTS provider_pricing_access_grants_revoked_by_idx ON public.provider_pricing_access_grants(revoked_by);

REVOKE ALL ON TABLE public.provider_pricing_access_grants FROM service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.provider_pricing_access_grants TO service_role;
