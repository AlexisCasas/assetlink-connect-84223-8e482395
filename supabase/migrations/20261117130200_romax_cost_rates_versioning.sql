-- R2A / Migration 3 of 3
-- Versioned rates, source provenance, FX snapshots, and single-step approval.
-- Approved rates are immutable; corrections create a new version.

CREATE TABLE public.provider_cost_rates (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 cost_item_id uuid NOT NULL,
 supplier_id uuid,
 version_number integer NOT NULL CHECK (version_number>0),
 unit_code text NOT NULL REFERENCES public.provider_cost_units(code) ON DELETE RESTRICT,
 currency_code text NOT NULL CHECK (currency_code IN ('PEN','USD')),
 unit_cost_original numeric(18,6) NOT NULL CHECK (unit_cost_original>=0),
 fx_rate_to_pen numeric(12,6) NOT NULL CHECK (fx_rate_to_pen>0),
 unit_cost_pen numeric(18,2) GENERATED ALWAYS AS (round(unit_cost_original*fx_rate_to_pen,2)) STORED,
 fx_source text NOT NULL,
 fx_date date,
 fx_reference text,
 tax_treatment text NOT NULL CHECK (tax_treatment IN ('inclusive','exclusive','not_applicable','unknown')),
 tax_rate numeric(7,4),
 source_type text NOT NULL CHECK (source_type IN ('supplier_quote','supplier_invoice','purchase_record','internal_cost_sheet','payroll_basis','manual')),
 source_reference text,
 source_date date,
 source_document_ref text,
 source_notes text,
 valid_from date NOT NULL,
 valid_until date,
 status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','pending_review','approved','rejected','archived')),
 created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 reviewed_by uuid REFERENCES auth.users(id),
 reviewed_at timestamptz,
 review_note text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT provider_cost_rates_item_fk FOREIGN KEY (organization_id,cost_item_id)
  REFERENCES public.provider_cost_items(organization_id,id) ON DELETE RESTRICT,
 CONSTRAINT provider_cost_rates_supplier_fk FOREIGN KEY (organization_id,supplier_id)
  REFERENCES public.provider_cost_suppliers(organization_id,id) ON DELETE RESTRICT,
 CONSTRAINT provider_cost_rates_tenant_id_unique UNIQUE (organization_id,id),
 CONSTRAINT provider_cost_rates_series_version_unique UNIQUE NULLS NOT DISTINCT
  (organization_id,cost_item_id,supplier_id,version_number),
 CONSTRAINT provider_cost_rates_valid_dates CHECK (valid_until IS NULL OR valid_until>=valid_from),
 CONSTRAINT provider_cost_rates_tax_rate CHECK (tax_rate IS NULL OR (tax_rate>=0 AND tax_rate<=100)),
 CONSTRAINT provider_cost_rates_currency_fx CHECK (
  (currency_code='PEN' AND fx_rate_to_pen=1 AND fx_source='not_required' AND fx_date IS NULL)
  OR (currency_code='USD' AND fx_source<>'not_required' AND fx_date IS NOT NULL)
 ),
 CONSTRAINT provider_cost_rates_review_metadata CHECK (
  (status='approved' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
  OR (status<>'approved')
 )
);
CREATE INDEX provider_cost_rates_lookup_idx
 ON public.provider_cost_rates(organization_id,cost_item_id,supplier_id,status,valid_from DESC);
CREATE INDEX provider_cost_rates_approved_idx
 ON public.provider_cost_rates(organization_id,cost_item_id,valid_from DESC)
 WHERE status='approved';

CREATE OR REPLACE FUNCTION public.guard_provider_cost_rate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
 v_role_ok boolean;
 v_overlap boolean;
BEGIN
 IF TG_OP='UPDATE' AND OLD.status='approved' THEN
  RAISE EXCEPTION 'Approved cost rates are immutable; create a new version';
 END IF;

 IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status AND NEW.status='approved' THEN
  v_role_ok := public.has_organization_role(NEW.organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]);
  IF NOT coalesce(v_role_ok,false) THEN
   RAISE EXCEPTION 'Not authorized to approve this cost rate';
  END IF;
  NEW.reviewed_by := auth.uid();
  NEW.reviewed_at := now();
 END IF;

 IF NEW.currency_code='USD' AND NEW.fx_source='organization_default' THEN
  IF NEW.fx_date IS NULL OR NEW.fx_rate_to_pen IS NULL THEN
   RAISE EXCEPTION 'USD rates require a dated FX snapshot';
  END IF;
 END IF;

 IF NEW.status='approved' THEN
  SELECT EXISTS (
   SELECT 1 FROM public.provider_cost_rates r
   WHERE r.organization_id=NEW.organization_id
    AND r.cost_item_id=NEW.cost_item_id
    AND r.supplier_id IS NOT DISTINCT FROM NEW.supplier_id
    AND r.id<>NEW.id
    AND r.status='approved'
    AND r.valid_from<=coalesce(NEW.valid_until,'infinity'::date)
    AND coalesce(r.valid_until,'infinity'::date)>=NEW.valid_from
  ) INTO v_overlap;
  IF v_overlap THEN RAISE EXCEPTION 'Approved rate validity overlaps another approved version in the same resource/supplier series'; END IF;
 END IF;
 NEW.updated_at := now();
 RETURN NEW;
END;
$$;

CREATE TRIGGER provider_cost_rates_guard
 BEFORE INSERT OR UPDATE ON public.provider_cost_rates
 FOR EACH ROW EXECUTE FUNCTION public.guard_provider_cost_rate();

ALTER TABLE public.provider_cost_rates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_cost_rates FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.provider_cost_rates TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.provider_cost_rates TO service_role;

CREATE POLICY provider_cost_rates_read ON public.provider_cost_rates
 FOR SELECT TO authenticated USING (public.is_organization_member(organization_id));
CREATE POLICY provider_cost_rates_insert ON public.provider_cost_rates
 FOR INSERT TO authenticated WITH CHECK (
  public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[])
  AND EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=organization_id AND o.organization_type='provider_company' AND o.status='active')
  AND created_by=auth.uid()
  AND status IN ('draft','pending_review')
 );
CREATE POLICY provider_cost_rates_update ON public.provider_cost_rates
 FOR UPDATE TO authenticated
 USING (
  public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[])
  AND status IN ('draft','pending_review','rejected')
 )
 WITH CHECK (
  public.has_organization_role(organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[])
  AND status IN ('draft','pending_review','rejected','approved','archived')
 );

COMMENT ON TABLE public.provider_cost_rates IS 'Versioned provider cost rates. Original currency, dated FX snapshot, source, review and validity are preserved. Approved rows cannot be edited.';
COMMENT ON COLUMN public.provider_cost_rates.unit_cost_pen IS 'Generated PEN snapshot; it never changes when organization default FX changes.';
