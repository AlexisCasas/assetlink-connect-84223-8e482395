-- R3-GMAIL.1: service-only encrypted mailbox connection and single-use OAuth attempt.
-- Materialize with supabase migration new before applying; never run against Cloud in CI.
CREATE TABLE public.romax_gmail_connections (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'disconnected' CHECK (status IN ('disconnected','pending','exchanging','connected','revoking')),
  attempt_hash text,
  attempt_owner uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  attempt_verifier text,
  attempt_expires_at timestamptz,
  mailbox_email text,
  refresh_ciphertext text,
  connected_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  connected_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (attempt_hash IS NULL OR attempt_hash ~ '^[0-9a-f]{64}$'),
  CHECK (
    (status = 'disconnected' AND attempt_hash IS NULL AND attempt_owner IS NULL AND attempt_verifier IS NULL AND attempt_expires_at IS NULL AND mailbox_email IS NULL AND refresh_ciphertext IS NULL AND connected_by IS NULL AND connected_at IS NULL)
    OR (status IN ('pending','exchanging') AND attempt_hash IS NOT NULL AND attempt_owner IS NOT NULL AND attempt_verifier IS NOT NULL AND attempt_expires_at IS NOT NULL AND mailbox_email IS NULL AND refresh_ciphertext IS NULL AND connected_by IS NULL AND connected_at IS NULL)
    OR (status IN ('connected','revoking') AND attempt_hash IS NULL AND attempt_owner IS NULL AND attempt_verifier IS NULL AND attempt_expires_at IS NULL AND mailbox_email IS NOT NULL AND refresh_ciphertext IS NOT NULL AND connected_by IS NOT NULL AND connected_at IS NOT NULL)
  )
);
ALTER TABLE public.romax_gmail_connections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.romax_gmail_connections FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.romax_gmail_connections TO service_role;
CREATE INDEX romax_gmail_attempt_owner_idx ON public.romax_gmail_connections(attempt_owner);
CREATE INDEX romax_gmail_connected_by_idx ON public.romax_gmail_connections(connected_by);
COMMENT ON TABLE public.romax_gmail_connections IS 'Server-only. AES-GCM encrypted refresh credential and PKCE verifier; no browser access. No email bodies.';
