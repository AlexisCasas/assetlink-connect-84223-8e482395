-- One Facility / ROMAX R1-D: private historical quotations from external source files.
-- A quote reference is NOT globally unique; the source document is the stable identity.
-- No writes to operational requests, quotes, approvals, or client-company tenants.
-- External historical PDFs/Excel remain in ROMAX Drive (metadata only here).

CREATE TABLE public.commercial_quote_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  commercial_client_id uuid,
  commercial_site_id uuid,
  source_client_name text,
  source_site_name text,
  reference_document text,
  reference_filename text,
  reference_review text NOT NULL DEFAULT 'unverified',
  proposal_date date,
  service_title text NOT NULL,
  currency_code text,
  amount_net numeric(18,2),
  amount_tax numeric(18,2),
  amount_gross numeric(18,2),
  price_review text NOT NULL DEFAULT 'pending',
  commercial_status text NOT NULL DEFAULT 'unverified',
  client_match_status text NOT NULL DEFAULT 'unmatched',
  source_context text NOT NULL DEFAULT 'ROMAX 2026 quotations archive',
  import_batch text NOT NULL,
  import_source_key text NOT NULL,
  internal_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT commercial_quote_history_title_valid
    CHECK (length(btrim(service_title)) BETWEEN 3 AND 500),
  CONSTRAINT commercial_quote_history_reference_status_valid
    CHECK (reference_review IN ('match','mismatch','unverified')),
  CONSTRAINT commercial_quote_history_price_status_valid
    CHECK (price_review IN ('pending','verified','needs_review')),
  CONSTRAINT commercial_quote_history_business_status_valid
    CHECK (commercial_status IN ('unverified','sent_verified','accepted_verified','rejected_verified','cancelled_verified')),
  CONSTRAINT commercial_quote_history_client_status_valid
    CHECK (client_match_status IN ('matched','unmatched','needs_review')),
  CONSTRAINT commercial_quote_history_client_status_consistent
    CHECK ((commercial_client_id IS NOT NULL AND client_match_status = 'matched')
        OR (commercial_client_id IS NULL AND client_match_status <> 'matched')),
  CONSTRAINT commercial_quote_history_currency_valid
    CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$'),
  CONSTRAINT commercial_quote_history_amounts_positive
    CHECK ((amount_net IS NULL OR amount_net >= 0)
      AND (amount_tax IS NULL OR amount_tax >= 0)
      AND (amount_gross IS NULL OR amount_gross >= 0)),
  CONSTRAINT commercial_quote_history_price_review_consistent
    CHECK (price_review <> 'verified' OR amount_net IS NOT NULL OR amount_gross IS NOT NULL),
  CONSTRAINT commercial_quote_history_site_requires_client
    CHECK (commercial_site_id IS NULL OR commercial_client_id IS NOT NULL),
  CONSTRAINT commercial_quote_history_import_source_valid
    CHECK (length(btrim(import_batch)) > 0 AND length(btrim(import_source_key)) > 0),
  CONSTRAINT commercial_quote_history_same_tenant_client_fk
    FOREIGN KEY (organization_id, commercial_client_id)
    REFERENCES public.commercial_clients (organization_id, id) ON DELETE RESTRICT,
  CONSTRAINT commercial_quote_history_same_client_site_fk
    FOREIGN KEY (organization_id, commercial_client_id, commercial_site_id)
    REFERENCES public.commercial_client_sites (organization_id, commercial_client_id, id) ON DELETE RESTRICT,
  CONSTRAINT commercial_quote_history_tenant_id_unique
    UNIQUE (organization_id,id),
  CONSTRAINT commercial_quote_history_source_unique
    UNIQUE (organization_id,import_source_key)
);

CREATE INDEX commercial_quote_history_client_search_idx
  ON public.commercial_quote_history (organization_id, commercial_client_id, proposal_date DESC);
CREATE INDEX commercial_quote_history_site_search_idx
  ON public.commercial_quote_history (organization_id, commercial_site_id, proposal_date DESC);
CREATE INDEX commercial_quote_history_ref_search_idx
  ON public.commercial_quote_history (organization_id,reference_document);
CREATE INDEX commercial_quote_history_date_idx
  ON public.commercial_quote_history (organization_id, proposal_date DESC);
CREATE INDEX commercial_quote_history_description_fts_idx
  ON public.commercial_quote_history
  USING gin (to_tsvector('spanish'::regconfig, coalesce(service_title, '') || ' ' || coalesce(source_client_name,'') || ' ' || coalesce(source_site_name,'')));

CREATE TRIGGER commercial_quote_history_updated_at
  BEFORE UPDATE ON public.commercial_quote_history
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE public.commercial_quote_history_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  history_id uuid NOT NULL,
  source_provider text NOT NULL DEFAULT 'google_drive',
  source_file_id text NOT NULL,
  source_filename text NOT NULL,
  mime_type text NOT NULL,
  source_folder_label text,
  document_role text NOT NULL DEFAULT 'reference',
  extracted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT commercial_quote_history_docs_filename_valid
    CHECK (length(btrim(source_filename)) BETWEEN 1 AND 700),
  CONSTRAINT commercial_quote_history_docs_file_id_valid
    CHECK (length(btrim(source_file_id)) > 0),
  CONSTRAINT commercial_quote_history_docs_provider_valid
    CHECK (length(btrim(source_provider)) > 0),
  CONSTRAINT commercial_quote_history_docs_role_valid
    CHECK (document_role IN ('primary_pdf','supporting_pdf','source_spreadsheet','reference')),
  CONSTRAINT commercial_quote_history_docs_history_fk
    FOREIGN KEY (organization_id, history_id)
    REFERENCES public.commercial_quote_history (organization_id, id)
    ON DELETE RESTRICT,
  CONSTRAINT commercial_quote_history_docs_identity_unique
    UNIQUE (organization_id, source_provider, source_file_id)
);

CREATE INDEX commercial_quote_history_documents_parent_idx
  ON public.commercial_quote_history_documents (organization_id, history_id);

-- External history is read-only for the application. A separate, audited
-- import service will perform future additions/corrections with service_role.
REVOKE ALL ON public.commercial_quote_history,
  public.commercial_quote_history_documents
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.commercial_quote_history,
  public.commercial_quote_history_documents
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.commercial_quote_history,
  public.commercial_quote_history_documents
  TO service_role;

ALTER TABLE public.commercial_quote_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_quote_history_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY commercial_quote_history_read
  ON public.commercial_quote_history
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(organization_id)));

CREATE POLICY commercial_quote_history_documents_read
  ON public.commercial_quote_history_documents
  FOR SELECT TO authenticated
  USING ((SELECT public.is_organization_member(organization_id)));

COMMENT ON TABLE public.commercial_quote_history IS
  'Provider-owned historical quotations, read-only to app users, distinct from live requests/quotes.';
COMMENT ON COLUMN public.commercial_quote_history.reference_document IS
  'Quote reference printed inside file; NOT unique, and may disagree with filename.';
COMMENT ON COLUMN public.commercial_quote_history.price_review IS
  'Amounts stay NULL until checked against original document, including IGV semantics.';
COMMENT ON COLUMN public.commercial_quote_history.commercial_status IS
  'Source folder alone does not verify sent/accepted/rejected business status.';
COMMENT ON TABLE public.commercial_quote_history_documents IS
  'Private document provenance/identity. Source files remain on Google Drive, not public GitHub.';
