-- R2-E2.1 follow-up: remove default service_role TRUNCATE/DELETE and other broad table grants.
-- The service role retains only the DML needed by trusted server-side flows.
REVOKE ALL ON TABLE public.provider_pricing_access_grants FROM service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.provider_pricing_access_grants TO service_role;
