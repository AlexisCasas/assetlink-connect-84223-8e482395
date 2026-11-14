-- One Facility | ROMAX R1-A: provider-owned commercial clients, sites and contacts.
-- No client organizations, fake requests, quote changes, or legacy data changes.
-- Future hybrid linkage is reserved; only service_role may set it.

CREATE TABLE public.commercial_clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  business_name text NOT NULL,
  legal_name text,
  tax_id text,
  commercial_code text,
  linked_client_organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  notes text,
  source_system text,
  source_key text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commercial_clients_business_name_valid CHECK (length(btrim(business_name)) BETWEEN 1 AND 200),
  CONSTRAINT commercial_clients_source_pair CHECK (
    (source_system IS NULL AND source_key IS NULL)
    OR (source_system IS NOT NULL AND source_key IS NOT NULL
      AND length(btrim(source_system)) > 0 AND length(btrim(source_key)) > 0)
  ),
  CONSTRAINT commercial_clients_tenant_id_unique UNIQUE (organization_id, id)
);
CREATE INDEX commercial_clients_tenant_name_idx
  ON public.commercial_clients (organization_id, lower(btrim(business_name)));
CREATE INDEX commercial_clients_tenant_active_idx
  ON public.commercial_clients (organization_id, is_active);
CREATE UNIQUE INDEX commercial_clients_source_key_unique
  ON public.commercial_clients (organization_id, lower(source_system), source_key)
  WHERE source_key IS NOT NULL;

-- Browser roles cannot populate/update the link; only privileged onboarding can.
-- Enforce that its target is an active client-company organization.
CREATE FUNCTION public.commercial_clients_check_linked_organization()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
BEGIN
  IF NEW.linked_client_organization_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = NEW.linked_client_organization_id
         AND o.organization_type = 'client_company'
         AND o.status = 'active'
    )
  THEN
    RAISE EXCEPTION 'linked_client_organization_id must be an active client_company'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER commercial_clients_link_guard
  BEFORE INSERT OR UPDATE OF linked_client_organization_id
  ON public.commercial_clients FOR EACH ROW
  EXECUTE FUNCTION public.commercial_clients_check_linked_organization();

CREATE TABLE public.commercial_client_sites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  commercial_client_id uuid NOT NULL,
  site_name text NOT NULL,
  site_code text,
  country_code text NOT NULL DEFAULT 'PE',
  region text,
  city text,
  district text,
  address text,
  notes text,
  source_system text,
  source_key text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commercial_client_sites_name_valid CHECK (length(btrim(site_name)) BETWEEN 1 AND 200),
  CONSTRAINT commercial_client_sites_source_pair CHECK (
    (source_system IS NULL AND source_key IS NULL)
    OR (source_system IS NOT NULL AND source_key IS NOT NULL
      AND length(btrim(source_system)) > 0 AND length(btrim(source_key)) > 0)
  ),
  CONSTRAINT commercial_client_sites_same_tenant_fk
    FOREIGN KEY (organization_id, commercial_client_id)
    REFERENCES public.commercial_clients(organization_id, id) ON DELETE RESTRICT,
  CONSTRAINT commercial_client_sites_tenant_client_id_unique
    UNIQUE (organization_id, commercial_client_id, id)
);
CREATE INDEX commercial_client_sites_client_idx
  ON public.commercial_client_sites (organization_id, commercial_client_id, is_active);
CREATE UNIQUE INDEX commercial_client_sites_source_key_unique
  ON public.commercial_client_sites (organization_id, lower(source_system), source_key)
  WHERE source_key IS NOT NULL;

CREATE TABLE public.commercial_client_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  commercial_client_id uuid NOT NULL,
  commercial_site_id uuid,
  full_name text NOT NULL,
  job_title text,
  email text,
  phone text,
  notes text,
  source_system text,
  source_key text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commercial_client_contacts_name_valid CHECK (length(btrim(full_name)) BETWEEN 1 AND 200),
  CONSTRAINT commercial_client_contacts_source_pair CHECK (
    (source_system IS NULL AND source_key IS NULL)
    OR (source_system IS NOT NULL AND source_key IS NOT NULL
      AND length(btrim(source_system)) > 0 AND length(btrim(source_key)) > 0)
  ),
  CONSTRAINT commercial_client_contacts_same_tenant_fk
    FOREIGN KEY (organization_id, commercial_client_id)
    REFERENCES public.commercial_clients(organization_id, id) ON DELETE RESTRICT,
  CONSTRAINT commercial_client_contacts_same_site_fk
    FOREIGN KEY (organization_id, commercial_client_id, commercial_site_id)
    REFERENCES public.commercial_client_sites(organization_id, commercial_client_id, id)
    ON DELETE RESTRICT
);
CREATE INDEX commercial_client_contacts_client_idx
  ON public.commercial_client_contacts (organization_id, commercial_client_id, is_active);
CREATE INDEX commercial_client_contacts_site_idx
  ON public.commercial_client_contacts (organization_id, commercial_site_id)
  WHERE commercial_site_id IS NOT NULL;
CREATE UNIQUE INDEX commercial_client_contacts_source_key_unique
  ON public.commercial_client_contacts (organization_id, lower(source_system), source_key)
  WHERE source_key IS NOT NULL;

CREATE TRIGGER commercial_clients_updated_at
  BEFORE UPDATE ON public.commercial_clients
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER commercial_client_sites_updated_at
  BEFORE UPDATE ON public.commercial_client_sites
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER commercial_client_contacts_updated_at
  BEFORE UPDATE ON public.commercial_client_contacts
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Limit browser clients to SELECT, INSERT of safe columns and UPDATE of
-- mutable fields only. No anon access or hard deletes from authenticated.
REVOKE ALL ON TABLE
  public.commercial_clients, public.commercial_client_sites,
  public.commercial_client_contacts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE
  public.commercial_clients, public.commercial_client_sites,
  public.commercial_client_contacts TO authenticated;
GRANT INSERT (organization_id, business_name, legal_name, tax_id, commercial_code,
  notes, source_system, source_key, is_active)
  ON public.commercial_clients TO authenticated;
GRANT UPDATE (business_name, legal_name, tax_id, commercial_code,
  notes, source_system, source_key, is_active)
  ON public.commercial_clients TO authenticated;
GRANT INSERT (organization_id, commercial_client_id, site_name, site_code,
  country_code, region, city, district, address, notes, source_system, source_key,
  is_active) ON public.commercial_client_sites TO authenticated;
GRANT UPDATE (site_name, site_code, country_code, region, city, district,
  address, notes, source_system, source_key, is_active)
  ON public.commercial_client_sites TO authenticated;
GRANT INSERT (organization_id, commercial_client_id, commercial_site_id,
  full_name, job_title, email, phone, notes, source_system, source_key, is_active)
  ON public.commercial_client_contacts TO authenticated;
GRANT UPDATE (commercial_site_id, full_name, job_title, email, phone, notes,
  source_system, source_key, is_active)
  ON public.commercial_client_contacts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.commercial_clients, public.commercial_client_sites,
  public.commercial_client_contacts TO service_role;

ALTER TABLE public.commercial_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_client_sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_client_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY commercial_clients_read ON public.commercial_clients
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(organization_id)));
CREATE POLICY commercial_clients_insert ON public.commercial_clients
  FOR INSERT TO authenticated WITH CHECK (
    (SELECT public.has_organization_role(organization_id,
      ARRAY['owner','admin','manager']::public.organization_member_role[]))
    AND EXISTS (
      SELECT 1 FROM public.organizations o
       WHERE o.id = organization_id
         AND o.organization_type = 'provider_company' AND o.status = 'active'
    )
  );
CREATE POLICY commercial_clients_update ON public.commercial_clients
  FOR UPDATE TO authenticated
  USING ((SELECT public.has_organization_role(organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[])))
  WITH CHECK ((SELECT public.has_organization_role(organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[])));

CREATE POLICY commercial_client_sites_read ON public.commercial_client_sites
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(organization_id)));
CREATE POLICY commercial_client_sites_insert ON public.commercial_client_sites
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_organization_role(organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[])));
CREATE POLICY commercial_client_sites_update ON public.commercial_client_sites
  FOR UPDATE TO authenticated
  USING ((SELECT public.has_organization_role(organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[])))
  WITH CHECK ((SELECT public.has_organization_role(organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[])));

CREATE POLICY commercial_client_contacts_read ON public.commercial_client_contacts
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(organization_id)));
CREATE POLICY commercial_client_contacts_insert ON public.commercial_client_contacts
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_organization_role(organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[])));
CREATE POLICY commercial_client_contacts_update ON public.commercial_client_contacts
  FOR UPDATE TO authenticated
  USING ((SELECT public.has_organization_role(organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[])))
  WITH CHECK ((SELECT public.has_organization_role(organization_id,
    ARRAY['owner','admin','manager']::public.organization_member_role[])));

REVOKE ALL ON FUNCTION public.commercial_clients_check_linked_organization()
  FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.commercial_clients IS
  'Provider-owned commercial customers; not platform tenants or logins.';
COMMENT ON COLUMN public.commercial_clients.linked_client_organization_id IS
  'Service-only future linkage to an explicitly onboarded client_company.';
COMMENT ON TABLE public.commercial_client_sites IS
  'Sites belonging to a provider-owned commercial customer, with tenant-safe FK.';
COMMENT ON TABLE public.commercial_client_contacts IS
  'Contacts belonging to same commercial customer and optional validated site.';
