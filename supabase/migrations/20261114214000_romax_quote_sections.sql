-- ROMAX R1-D2C: document-anchored narrative and additional quote sections.
-- Universal extension: never infer a line price from flattened PDF text.
-- Read-only to browser users; finance amounts remain in their existing tables.
CREATE TABLE public.commercial_quote_history_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  history_id uuid NOT NULL,
  section_order integer NOT NULL,
  section_kind text NOT NULL,
  original_heading text NOT NULL,
  section_text text NOT NULL,
  source_page integer,
  provenance text NOT NULL DEFAULT 'pdf_extracted_text',
  review_status text NOT NULL DEFAULT 'extracted_unverified',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quote_history_sections_quote_fk
    FOREIGN KEY (organization_id, history_id)
    REFERENCES public.commercial_quote_history (organization_id, id) ON DELETE CASCADE,
  CONSTRAINT quote_history_sections_order_valid
    CHECK (section_order > 0),
  CONSTRAINT quote_history_sections_kind_valid
    CHECK (section_kind IN (
      'service_scope','material_scope','labor','equipment','additional_costs',
      'technical','safety','management_delivery','commercial_terms',
      'economic_summary','internal_costs','other'
    )),
  CONSTRAINT quote_history_sections_heading_valid
    CHECK (length(btrim(original_heading)) BETWEEN 3 AND 240),
  CONSTRAINT quote_history_sections_text_valid
    CHECK (length(btrim(section_text)) BETWEEN 3 AND 12000),
  CONSTRAINT quote_history_sections_page_valid
    CHECK (source_page IS NULL OR source_page > 0),
  CONSTRAINT quote_history_sections_provenance_valid
    CHECK (provenance IN ('pdf_extracted_text','pdf_visual_review','xlsx_source')),
  CONSTRAINT quote_history_sections_review_valid
    CHECK (review_status IN ('extracted_unverified','needs_review','verified')),
  CONSTRAINT quote_history_sections_unique_sequence
    UNIQUE (organization_id,history_id,section_order)
);

CREATE INDEX quote_history_sections_parent_idx
 ON public.commercial_quote_history_sections (organization_id,history_id,section_order);
CREATE INDEX quote_history_sections_kind_idx
 ON public.commercial_quote_history_sections (organization_id,section_kind);
CREATE INDEX quote_history_sections_text_search_idx
 ON public.commercial_quote_history_sections
 USING gin(to_tsvector('spanish'::regconfig,section_text));

REVOKE ALL ON public.commercial_quote_history_sections
 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.commercial_quote_history_sections TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.commercial_quote_history_sections TO service_role;

ALTER TABLE public.commercial_quote_history_sections ENABLE ROW LEVEL SECURITY;
CREATE POLICY commercial_quote_history_sections_read
 ON public.commercial_quote_history_sections FOR SELECT TO authenticated
 USING ((SELECT public.is_organization_member(organization_id)));

COMMENT ON TABLE public.commercial_quote_history_sections IS
 'ROMAX provider-owned narrative/technical/contractual sections of archived quotes, with original headings and review status; no automatic price inference.';
COMMENT ON COLUMN public.commercial_quote_history_sections.source_page IS
 'NULL when PDF page cannot be grounded; never guess page from flattened text.';


-- The extraction of some historical templates loses PDF page boundaries.
-- Preserve numeric summary facts as UNVERIFIED without fabricating a page.
-- Existing rows with known page numbers keep them unchanged.
ALTER TABLE public.commercial_quote_history_cost_components
  ALTER COLUMN source_page DROP NOT NULL;
COMMENT ON COLUMN public.commercial_quote_history_cost_components.source_page IS
 'Nullable when the source PDF page has not been confirmed; do not guess a page from flattened extraction.';
