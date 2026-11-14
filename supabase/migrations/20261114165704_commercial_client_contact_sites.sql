-- One Facility | ROMAX R1-B: one commercial contact may cover several sites.
-- Dedicated provider-owned association; no need to duplicate contact identities.
-- Safe for existing data. No changes to requests, quotes or organizations.
--
-- NB: commercial_client_contacts.commercial_site_id stays nullable for backward
-- compatibility. New imports keep it NULL and use this many-to-many link table.

ALTER TABLE public.commercial_client_contacts
  ADD CONSTRAINT commercial_client_contacts_tenant_client_id_unique
  UNIQUE (organization_id, commercial_client_id, id);

CREATE TABLE public.commercial_client_contact_sites (
  organization_id uuid NOT NULL,
  commercial_client_id uuid NOT NULL,
  commercial_contact_id uuid NOT NULL,
  commercial_site_id uuid NOT NULL,
  source_system text,
  source_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT commercial_client_contact_sites_pkey
    PRIMARY KEY (organization_id, commercial_contact_id, commercial_site_id),

  CONSTRAINT commercial_client_contact_sites_contact_fk
    FOREIGN KEY (organization_id, commercial_client_id, commercial_contact_id)
    REFERENCES public.commercial_client_contacts (organization_id, commercial_client_id, id)
    ON DELETE CASCADE,

  CONSTRAINT commercial_client_contact_sites_site_fk
    FOREIGN KEY (organization_id, commercial_client_id, commercial_site_id)
    REFERENCES public.commercial_client_sites (organization_id, commercial_client_id, id)
    ON DELETE CASCADE,

  CONSTRAINT commercial_client_contact_sites_source_check
    CHECK (source_system IS NULL OR length(btrim(source_system)) > 0)
);

CREATE INDEX commercial_client_contact_sites_by_site_idx
  ON public.commercial_client_contact_sites
  (organization_id, commercial_client_id, commercial_site_id);

CREATE INDEX commercial_client_contact_sites_by_contact_idx
  ON public.commercial_client_contact_sites
  (organization_id, commercial_client_id, commercial_contact_id);

-- Explicitly close default privileges and avoid exposing data to anon.
REVOKE ALL ON public.commercial_client_contact_sites FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.commercial_client_contact_sites TO authenticated;
GRANT INSERT (
  organization_id, commercial_client_id, commercial_contact_id,
  commercial_site_id, source_system, source_reference
) ON public.commercial_client_contact_sites TO authenticated;
-- Removing an association is permitted for organization managers,
-- but does not delete either the contact or its site.
GRANT DELETE ON public.commercial_client_contact_sites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.commercial_client_contact_sites
  TO service_role;

ALTER TABLE public.commercial_client_contact_sites ENABLE ROW LEVEL SECURITY;

CREATE POLICY commercial_contact_sites_read
  ON public.commercial_client_contact_sites
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(organization_id)));

CREATE POLICY commercial_contact_sites_insert
  ON public.commercial_client_contact_sites
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner','admin','manager']::public.organization_member_role[]
    ))
    AND EXISTS (
      SELECT 1
      FROM public.organizations o
      WHERE o.id = organization_id
        AND o.organization_type = 'provider_company'
        AND o.status = 'active'
    )
  );

CREATE POLICY commercial_contact_sites_delete
  ON public.commercial_client_contact_sites
  FOR DELETE TO authenticated
  USING ((SELECT public.has_organization_role(
    organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[]
  )));

COMMENT ON TABLE public.commercial_client_contact_sites IS
  'R1-B contact-to-site associations for a provider-owned commercial client; tenant and client boundaries enforced by composite FKs.';
COMMENT ON COLUMN public.commercial_client_contact_sites.source_reference IS
  'Private workbook-row lineage for the association; never publish source PII in GitHub.';
