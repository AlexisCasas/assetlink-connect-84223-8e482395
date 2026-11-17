-- One Facility / ROMAX R2-M3
-- Cost rates, immutable approved versions, FX snapshots and single-step review.
-- No cost estimates or operational quote integration are created in this migration.

CREATE TABLE public.provider_cost_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL
    REFERENCES public.organizations(id) ON DELETE CASCADE,
  cost_item_id uuid NOT NULL,
  supplier_id uuid,
  version_number integer NOT NULL,
  unit_code text NOT NULL
    REFERENCES public.provider_cost_units(code) ON DELETE RESTRICT,
  currency_code text NOT NULL,
  unit_cost_original numeric(18, 6) NOT NULL,
  fx_rate_to_pen numeric(18, 8) NOT NULL,
  unit_cost_pen numeric(18, 6)
    GENERATED ALWAYS AS (round(unit_cost_original * fx_rate_to_pen, 6)) STORED,
  fx_source text NOT NULL DEFAULT 'not_applicable',
  fx_date date,
  fx_reference text,
  tax_treatment text NOT NULL DEFAULT 'unknown',
  tax_rate numeric(7, 4),
  source_type text NOT NULL,
  source_reference text,
  source_date date,
  source_document_ref text,
  source_notes text,
  valid_from date NOT NULL DEFAULT current_date,
  valid_until date,
  status text NOT NULL DEFAULT 'draft',
  created_by uuid DEFAULT auth.uid()
    REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT provider_cost_rates_item_tenant_fk
    FOREIGN KEY (organization_id, cost_item_id)
    REFERENCES public.provider_cost_items(organization_id, id)
    ON DELETE RESTRICT,

  CONSTRAINT provider_cost_rates_supplier_tenant_fk
    FOREIGN KEY (organization_id, supplier_id)
    REFERENCES public.provider_cost_suppliers(organization_id, id)
    ON DELETE RESTRICT,

  CONSTRAINT provider_cost_rates_version_unique
    UNIQUE NULLS NOT DISTINCT
      (organization_id, cost_item_id, supplier_id, version_number),

  CONSTRAINT provider_cost_rates_version_positive
    CHECK (version_number > 0),

  CONSTRAINT provider_cost_rates_currency_check
    CHECK (currency_code IN ('PEN', 'USD')),

  CONSTRAINT provider_cost_rates_original_cost_check
    CHECK (unit_cost_original >= 0),

  CONSTRAINT provider_cost_rates_fx_check
    CHECK (
      (
        currency_code = 'PEN'
        AND fx_rate_to_pen = 1
        AND fx_source = 'not_applicable'
        AND fx_date IS NULL
        AND fx_reference IS NULL
      )
      OR
      (
        currency_code = 'USD'
        AND fx_rate_to_pen > 0
        AND fx_source IN ('organization_default', 'documented', 'manual')
        AND fx_date IS NOT NULL
        AND fx_reference IS NOT NULL
        AND length(btrim(fx_reference)) > 0
      )
    ),

  CONSTRAINT provider_cost_rates_tax_check
    CHECK (
      (
        tax_treatment IN ('inclusive', 'exclusive')
        AND tax_rate IS NOT NULL
        AND tax_rate >= 0
        AND tax_rate <= 100
      )
      OR
      (
        tax_treatment IN ('not_applicable', 'unknown')
        AND tax_rate IS NULL
      )
    ),

  CONSTRAINT provider_cost_rates_source_type_check
    CHECK (source_type IN (
      'supplier_quote', 'supplier_invoice', 'purchase_record',
      'internal_cost_sheet', 'payroll_basis', 'manual'
    )),

  CONSTRAINT provider_cost_rates_supplier_required
    CHECK (
      source_type NOT IN ('supplier_quote', 'supplier_invoice', 'purchase_record')
      OR supplier_id IS NOT NULL
    ),

  CONSTRAINT provider_cost_rates_validity_check
    CHECK (valid_until IS NULL OR valid_until >= valid_from),

  CONSTRAINT provider_cost_rates_status_check
    CHECK (status IN ('draft', 'pending_review', 'approved', 'rejected', 'archived')),

  CONSTRAINT provider_cost_rates_review_metadata_check
    CHECK (
      (
        status IN ('draft', 'pending_review')
        AND reviewed_by IS NULL
        AND reviewed_at IS NULL
      )
      OR
      (
        status IN ('approved', 'rejected', 'archived')
        AND reviewed_by IS NOT NULL
        AND reviewed_at IS NOT NULL
      )
    ),

  CONSTRAINT provider_cost_rates_rejection_note_check
    CHECK (status <> 'rejected' OR length(btrim(review_note)) > 0),

  CONSTRAINT provider_cost_rates_source_reference_check
    CHECK (source_reference IS NULL OR length(btrim(source_reference)) > 0),

  CONSTRAINT provider_cost_rates_document_reference_check
    CHECK (source_document_ref IS NULL OR length(btrim(source_document_ref)) > 0)
);

CREATE INDEX provider_cost_rates_item_idx
  ON public.provider_cost_rates (organization_id, cost_item_id, supplier_id, version_number DESC);

CREATE INDEX provider_cost_rates_approved_lookup_idx
  ON public.provider_cost_rates
    (organization_id, cost_item_id, supplier_id, valid_from DESC)
  WHERE status = 'approved';

CREATE INDEX provider_cost_rates_status_idx
  ON public.provider_cost_rates (organization_id, status, valid_from DESC);

-- Version numbers are generated inside a transaction and serialized per
-- organization + resource + supplier (NULL supplier means internal cost).
CREATE FUNCTION public.provider_cost_rates_prepare_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_default_rate numeric(12, 6);
  v_default_date date;
  v_default_reference text;
  v_item_unit text;
  v_lock_key bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.organizations o
    WHERE o.id = NEW.organization_id
      AND o.organization_type = 'provider_company'
      AND o.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cost rates require an active provider_company organization'
      USING ERRCODE = '23514';
  END IF;

  SELECT i.default_unit_code
    INTO v_item_unit
  FROM public.provider_cost_items i
  WHERE i.organization_id = NEW.organization_id
    AND i.id = NEW.cost_item_id;

  IF v_item_unit IS NULL THEN
    RAISE EXCEPTION 'Cost item does not exist in this organization'
      USING ERRCODE = '23503';
  END IF;

  IF NEW.unit_code <> v_item_unit THEN
    RAISE EXCEPTION 'Rate unit must match the cost item default unit; conversions are not implicit'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.source_type IN ('supplier_quote', 'supplier_invoice', 'purchase_record')
     AND NEW.supplier_id IS NULL THEN
    RAISE EXCEPTION 'Supplier is required for supplier quote, invoice or purchase record sources'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.currency_code = 'PEN' THEN
    NEW.fx_rate_to_pen := 1;
    NEW.fx_source := 'not_applicable';
    NEW.fx_date := NULL;
    NEW.fx_reference := NULL;
  ELSIF NEW.currency_code = 'USD' THEN
    IF NEW.fx_source = 'organization_default' THEN
      SELECT s.default_usd_pen_rate, s.default_fx_date, s.default_fx_reference
        INTO v_default_rate, v_default_date, v_default_reference
      FROM public.provider_cost_settings s
      WHERE s.organization_id = NEW.organization_id;

      IF v_default_rate IS NULL OR v_default_date IS NULL
         OR v_default_reference IS NULL THEN
        RAISE EXCEPTION 'Configure a documented default USD/PEN rate before approving USD costs'
          USING ERRCODE = '23514';
      END IF;

      NEW.fx_rate_to_pen := v_default_rate;
      NEW.fx_date := v_default_date;
      NEW.fx_reference := v_default_reference;
    ELSIF NEW.fx_source IN ('documented', 'manual') THEN
      IF NEW.fx_rate_to_pen IS NULL OR NEW.fx_rate_to_pen <= 0
         OR NEW.fx_date IS NULL OR NEW.fx_reference IS NULL
         OR length(btrim(NEW.fx_reference)) = 0 THEN
        RAISE EXCEPTION 'USD costs require a positive FX rate, date and reference'
          USING ERRCODE = '23514';
      END IF;
    ELSE
      RAISE EXCEPTION 'USD costs require organization_default, documented or manual FX source'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    RAISE EXCEPTION 'Only PEN and USD are supported in the initial cost catalog'
      USING ERRCODE = '23514';
  END IF;

  v_lock_key := pg_catalog.hashtextextended(
    NEW.organization_id::text || ':' ||
    NEW.cost_item_id::text || ':' ||
    COALESCE(NEW.supplier_id::text, 'internal'),
    0
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(v_lock_key);

  SELECT COALESCE(MAX(r.version_number), 0) + 1
    INTO NEW.version_number
  FROM public.provider_cost_rates r
  WHERE r.organization_id = NEW.organization_id
    AND r.cost_item_id = NEW.cost_item_id
    AND r.supplier_id IS NOT DISTINCT FROM NEW.supplier_id;

  NEW.status := 'draft';
  NEW.created_by := COALESCE(NEW.created_by, auth.uid());
  NEW.reviewed_by := NULL;
  NEW.reviewed_at := NULL;
  NEW.updated_at := now();

  RETURN NEW;
END;
$$;

CREATE TRIGGER provider_cost_rates_prepare_insert
  BEFORE INSERT ON public.provider_cost_rates
  FOR EACH ROW
  EXECUTE FUNCTION public.provider_cost_rates_prepare_insert();

-- A rate can be edited only while draft. Submission freezes its economic
-- fields. Approval is a one-step human action; the same authorized user may
-- create and approve. Replacing an overlapping approved rate closes the old
-- validity window while preserving its original price and review metadata.
CREATE FUNCTION public.provider_cost_rates_guard_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_previous record;
  v_lock_key bigint;
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.id IS DISTINCT FROM OLD.id
     OR NEW.cost_item_id IS DISTINCT FROM OLD.cost_item_id
        AND OLD.status <> 'draft'
     OR NEW.supplier_id IS DISTINCT FROM OLD.supplier_id
        AND OLD.status <> 'draft'
     OR NEW.version_number IS DISTINCT FROM OLD.version_number
     OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'Rate identity and version are immutable'
      USING ERRCODE = '23514';
  END IF;

  IF OLD.status = 'draft' THEN
    IF NEW.status NOT IN ('draft', 'pending_review') THEN
      RAISE EXCEPTION 'Draft rates may only remain draft or be submitted for review'
        USING ERRCODE = '23514';
    END IF;

    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  IF OLD.status = 'pending_review' THEN
    IF (to_jsonb(NEW) - ARRAY['status', 'review_note', 'reviewed_by', 'reviewed_at', 'updated_at'])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['status', 'review_note', 'reviewed_by', 'reviewed_at', 'updated_at']) THEN
      RAISE EXCEPTION 'Submitted rates are read-only; create a new version to change cost data'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.status NOT IN ('pending_review', 'approved', 'rejected') THEN
      RAISE EXCEPTION 'Invalid review status transition'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.status = 'approved' THEN
      IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'An authenticated reviewer is required'
          USING ERRCODE = '42501';
      END IF;

      v_lock_key := pg_catalog.hashtextextended(
        NEW.organization_id::text || ':' ||
        NEW.cost_item_id::text || ':' ||
        COALESCE(NEW.supplier_id::text, 'internal'),
        0
      );
      PERFORM pg_catalog.pg_advisory_xact_lock(v_lock_key);

      FOR v_previous IN
        SELECT r.id, r.valid_from, r.valid_until
        FROM public.provider_cost_rates r
        WHERE r.organization_id = NEW.organization_id
          AND r.cost_item_id = NEW.cost_item_id
          AND r.supplier_id IS NOT DISTINCT FROM NEW.supplier_id
          AND r.status = 'approved'
          AND r.id <> NEW.id
          AND (r.valid_until IS NULL OR r.valid_until >= NEW.valid_from)
          AND (NEW.valid_until IS NULL OR r.valid_from <= NEW.valid_until)
        FOR UPDATE
      LOOP
        IF v_previous.valid_from >= NEW.valid_from THEN
          RAISE EXCEPTION 'An overlapping approved rate starts on or after this version; review the validity dates'
            USING ERRCODE = '23514';
        END IF;

        UPDATE public.provider_cost_rates
        SET valid_until = NEW.valid_from - 1,
            review_note = concat_ws(E'\n', NULLIF(review_note, ''), 'Vigencia cerrada automáticamente al aprobar versión ' || NEW.version_number::text)
        WHERE id = v_previous.id;
      END LOOP;

      NEW.reviewed_by := auth.uid();
      NEW.reviewed_at := now();
    ELSIF NEW.status = 'rejected' THEN
      IF auth.uid() IS NULL OR length(btrim(COALESCE(NEW.review_note, ''))) = 0 THEN
        RAISE EXCEPTION 'A rejection requires an authenticated reviewer and a reason'
          USING ERRCODE = '23514';
      END IF;
      NEW.reviewed_by := auth.uid();
      NEW.reviewed_at := now();
    ELSE
      NEW.reviewed_by := NULL;
      NEW.reviewed_at := NULL;
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  IF OLD.status = 'approved' THEN
    IF NEW.status = 'archived' THEN
      IF (to_jsonb(NEW) - ARRAY['status', 'review_note', 'updated_at'])
         IS DISTINCT FROM
         (to_jsonb(OLD) - ARRAY['status', 'review_note', 'updated_at'])
         OR length(btrim(COALESCE(NEW.review_note, ''))) = 0 THEN
        RAISE EXCEPTION 'Archiving an approved rate requires a reason and cannot change its economic values'
          USING ERRCODE = '23514';
      END IF;
      NEW.updated_at := now();
      RETURN NEW;
    END IF;

    IF NEW.status <> 'approved'
       OR (to_jsonb(NEW) - ARRAY['valid_until', 'review_note', 'updated_at'])
          IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['valid_until', 'review_note', 'updated_at'])
       OR length(btrim(COALESCE(NEW.review_note, ''))) = 0 THEN
      RAISE EXCEPTION 'Approved rates are immutable; shortening validity requires an audit reason'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.valid_until IS NULL
       OR NEW.valid_until < OLD.valid_from
       OR (OLD.valid_until IS NOT NULL AND NEW.valid_until >= OLD.valid_until) THEN
      RAISE EXCEPTION 'An approved rate validity window may only be shortened'
        USING ERRCODE = '23514';
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Rejected or archived rates are immutable'
    USING ERRCODE = '23514';
END;
$$;

CREATE TRIGGER provider_cost_rates_guard_update
  BEFORE UPDATE ON public.provider_cost_rates
  FOR EACH ROW
  EXECUTE FUNCTION public.provider_cost_rates_guard_update();

REVOKE ALL ON public.provider_cost_rates FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.provider_cost_rates TO authenticated;

GRANT INSERT (
  organization_id, cost_item_id, supplier_id, unit_code, currency_code,
  unit_cost_original, fx_rate_to_pen, fx_source, fx_date, fx_reference,
  tax_treatment, tax_rate, source_type, source_reference, source_date,
  source_document_ref, source_notes, valid_from, valid_until
) ON public.provider_cost_rates TO authenticated;

GRANT UPDATE (
  cost_item_id, supplier_id, unit_code, currency_code, unit_cost_original,
  fx_rate_to_pen, fx_source, fx_date, fx_reference, tax_treatment, tax_rate,
  source_type, source_reference, source_date, source_document_ref, source_notes,
  valid_from, valid_until, status, review_note
) ON public.provider_cost_rates TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.provider_cost_rates TO service_role;

ALTER TABLE public.provider_cost_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY provider_cost_rates_read
  ON public.provider_cost_rates
  FOR SELECT TO authenticated
  USING (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
  );

CREATE POLICY provider_cost_rates_insert
  ON public.provider_cost_rates
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by = (SELECT auth.uid())
    AND status = 'draft'
    AND (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
    AND EXISTS (
      SELECT 1 FROM public.organizations o
      WHERE o.id = organization_id
        AND o.organization_type = 'provider_company'
        AND o.status = 'active'
    )
  );

CREATE POLICY provider_cost_rates_update
  ON public.provider_cost_rates
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
  )
  WITH CHECK (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
    AND EXISTS (
      SELECT 1 FROM public.organizations o
      WHERE o.id = organization_id
        AND o.organization_type = 'provider_company'
        AND o.status = 'active'
    )
  );

REVOKE ALL ON FUNCTION public.provider_cost_rates_prepare_insert()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.provider_cost_rates_guard_update()
  FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.provider_cost_rates IS
  'Versioned supplier and internal cost rates. Original currency and FX snapshot are retained; only approved rates may feed future estimates.';
COMMENT ON COLUMN public.provider_cost_rates.unit_cost_original IS
  'Original unit cost in currency_code. Never overwritten by FX updates.';
COMMENT ON COLUMN public.provider_cost_rates.unit_cost_pen IS
  'Stored generated value using the immutable fx_rate_to_pen snapshot.';
COMMENT ON COLUMN public.provider_cost_rates.valid_until IS
  'NULL means no expiry. Replacing an overlapping approved version closes the previous validity window.';
