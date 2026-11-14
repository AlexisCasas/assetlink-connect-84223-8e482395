-- One Facility / ROMAX R1-D2: quote line details with source provenance.
-- Quote amounts here are historical extracts; not approved/current prices.
-- Existing commercial_quote_history and operational quotes remain unchanged.

CREATE TABLE public.commercial_quote_history_line_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 history_id uuid NOT NULL,
 section_kind text NOT NULL,
 line_order integer NOT NULL,
 description text NOT NULL,
 unit_label text,
 quantity numeric(16,4),
 unit_price numeric(18,4),
 line_total numeric(18,2),
 currency_code text NOT NULL DEFAULT 'PEN',
 source_page integer NOT NULL,
 source_note text,
 review_status text NOT NULL DEFAULT 'extracted_unverified',
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT commercial_quote_history_line_parent_fk
  FOREIGN KEY (organization_id,history_id)
  REFERENCES public.commercial_quote_history(organization_id,id) ON DELETE CASCADE,
 CONSTRAINT commercial_quote_history_line_section_check
  CHECK (section_kind IN ('service','material','equipment','other')),
 CONSTRAINT commercial_quote_history_line_order_check CHECK (line_order>0),
 CONSTRAINT commercial_quote_history_line_description_check
  CHECK (length(btrim(description)) BETWEEN 2 AND 2000),
 CONSTRAINT commercial_quote_history_line_positive
  CHECK ((quantity IS NULL OR quantity>=0) AND
         (unit_price IS NULL OR unit_price>=0) AND
         (line_total IS NULL OR line_total>=0)),
 CONSTRAINT commercial_quote_history_line_currency
  CHECK (currency_code ~ '^[A-Z]{3}$'),
 CONSTRAINT commercial_quote_history_line_page
  CHECK (source_page>0),
 CONSTRAINT commercial_quote_history_line_review
  CHECK (review_status IN ('extracted_unverified','verified','needs_review')),
 CONSTRAINT commercial_quote_history_line_identity
  UNIQUE (organization_id,history_id,section_kind,line_order)
);

CREATE TABLE public.commercial_quote_history_cost_components (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 history_id uuid NOT NULL,
 component_kind text NOT NULL,
 amount numeric(18,2) NOT NULL,
 currency_code text NOT NULL DEFAULT 'PEN',
 source_page integer NOT NULL,
 source_label text NOT NULL,
 review_status text NOT NULL DEFAULT 'extracted_unverified',
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT commercial_quote_history_component_parent_fk
  FOREIGN KEY (organization_id,history_id)
  REFERENCES public.commercial_quote_history(organization_id,id) ON DELETE CASCADE,
 CONSTRAINT commercial_quote_history_component_kind
  CHECK (component_kind IN
   ('labor','materials','mobilization','overhead_profit','net_total','tax','gross_total','other')),
 CONSTRAINT commercial_quote_history_component_value CHECK (amount>=0),
 CONSTRAINT commercial_quote_history_component_currency CHECK (currency_code ~ '^[A-Z]{3}$'),
 CONSTRAINT commercial_quote_history_component_page CHECK (source_page>0),
 CONSTRAINT commercial_quote_history_component_label CHECK (length(btrim(source_label))>0),
 CONSTRAINT commercial_quote_history_component_review
  CHECK (review_status IN ('extracted_unverified','verified','needs_review')),
 CONSTRAINT commercial_quote_history_component_identity
  UNIQUE (organization_id,history_id,component_kind)
);

CREATE TABLE public.commercial_quote_history_source_extracts (
 organization_id uuid NOT NULL,
 history_id uuid NOT NULL,
 source_text text NOT NULL,
 extraction_method text NOT NULL DEFAULT 'google_drive_text',
 review_status text NOT NULL DEFAULT 'raw_unverified',
 extracted_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (organization_id,history_id),
 CONSTRAINT commercial_quote_history_extract_parent_fk
  FOREIGN KEY (organization_id,history_id)
  REFERENCES public.commercial_quote_history(organization_id,id) ON DELETE CASCADE,
 CONSTRAINT commercial_quote_history_extract_content
  CHECK (length(btrim(source_text)) > 0),
 CONSTRAINT commercial_quote_history_extract_review
  CHECK (review_status IN ('raw_unverified','reviewed'))
);

CREATE INDEX commercial_quote_history_lines_by_quote
 ON public.commercial_quote_history_line_items(organization_id,history_id,section_kind,line_order);
CREATE INDEX commercial_quote_history_costs_by_quote
 ON public.commercial_quote_history_cost_components(organization_id,history_id);
CREATE INDEX commercial_quote_history_line_search
 ON public.commercial_quote_history_line_items
 USING gin(to_tsvector('spanish'::regconfig,description));
CREATE INDEX commercial_quote_history_extract_search
 ON public.commercial_quote_history_source_extracts
 USING gin(to_tsvector('spanish'::regconfig,source_text));

REVOKE ALL ON public.commercial_quote_history_line_items,
 public.commercial_quote_history_cost_components,
 public.commercial_quote_history_source_extracts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.commercial_quote_history_line_items,
 public.commercial_quote_history_cost_components,
 public.commercial_quote_history_source_extracts TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.commercial_quote_history_line_items,
 public.commercial_quote_history_cost_components,
 public.commercial_quote_history_source_extracts TO service_role;

ALTER TABLE public.commercial_quote_history_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_quote_history_cost_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_quote_history_source_extracts ENABLE ROW LEVEL SECURITY;

CREATE POLICY commercial_quote_history_lines_read
 ON public.commercial_quote_history_line_items FOR SELECT TO authenticated
 USING ((SELECT public.is_organization_member(organization_id)));
CREATE POLICY commercial_quote_history_costs_read
 ON public.commercial_quote_history_cost_components FOR SELECT TO authenticated
 USING ((SELECT public.is_organization_member(organization_id)));
CREATE POLICY commercial_quote_history_source_extracts_read
 ON public.commercial_quote_history_source_extracts FOR SELECT TO authenticated
 USING ((SELECT public.is_organization_member(organization_id)));

COMMENT ON TABLE public.commercial_quote_history_line_items IS
 'Extracted services/materials/quantities/prices, linked to quote and PDF page; no price automatically approved.';
COMMENT ON TABLE public.commercial_quote_history_cost_components IS
 'Historical cost summary per quote; never an up-to-date price catalog.';
COMMENT ON TABLE public.commercial_quote_history_source_extracts IS
 'Private PDF extracted text for eventual grounded semantic retrieval. Not reviewed; protected by provider RLS.';
