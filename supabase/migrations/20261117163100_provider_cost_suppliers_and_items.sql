-- One Facility / ROMAX R2-M2
-- Provider-owned suppliers and reusable cost resources.
-- No customer, site, inventory, or historical quote records are duplicated.

CREATE FUNCTION public.provider_cost_assert_provider_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.organizations o
    WHERE o.id = NEW.organization_id
      AND o.organization_type = 'provider_company'
      AND o.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cost catalog records require an active provider_company organization'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TABLE public.provider_cost_suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL
    REFERENCES public.organizations(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  legal_name text,
  tax_id text,
  email text,
  phone text,
  notes text,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid DEFAULT auth.uid()
    REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_cost_suppliers_tenant_id_unique
    UNIQUE (organization_id, id),
  CONSTRAINT provider_cost_suppliers_display_name_check
    CHECK (length(btrim(display_name)) BETWEEN 1 AND 200),
  CONSTRAINT provider_cost_suppliers_legal_name_check
    CHECK (legal_name IS NULL OR length(btrim(legal_name)) BETWEEN 1 AND 250),
  CONSTRAINT provider_cost_suppliers_email_check
    CHECK (email IS NULL OR length(btrim(email)) <= 320),
  CONSTRAINT provider_cost_suppliers_phone_check
    CHECK (phone IS NULL OR length(btrim(phone)) <= 60)
);

CREATE UNIQUE INDEX provider_cost_suppliers_tax_id_unique
  ON public.provider_cost_suppliers (organization_id, lower(btrim(tax_id)))
  WHERE tax_id IS NOT NULL AND length(btrim(tax_id)) > 0;

CREATE INDEX provider_cost_suppliers_name_idx
  ON public.provider_cost_suppliers (organization_id, lower(btrim(display_name)));

CREATE INDEX provider_cost_suppliers_active_idx
  ON public.provider_cost_suppliers (organization_id, is_active);

CREATE TRIGGER provider_cost_suppliers_assert_org
  BEFORE INSERT OR UPDATE OF organization_id
  ON public.provider_cost_suppliers
  FOR EACH ROW
  EXECUTE FUNCTION public.provider_cost_assert_provider_organization();

CREATE TRIGGER provider_cost_suppliers_updated_at
  BEFORE UPDATE ON public.provider_cost_suppliers
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE public.provider_cost_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL
    REFERENCES public.organizations(id) ON DELETE CASCADE,
  code text,
  name text NOT NULL,
  description text,
  category_code text NOT NULL
    REFERENCES public.provider_cost_categories(code) ON DELETE RESTRICT,
  default_unit_code text NOT NULL
    REFERENCES public.provider_cost_units(code) ON DELETE RESTRICT,
  technical_specification text,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid DEFAULT auth.uid()
    REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_cost_items_tenant_id_unique
    UNIQUE (organization_id, id),
  CONSTRAINT provider_cost_items_name_check
    CHECK (length(btrim(name)) BETWEEN 1 AND 250),
  CONSTRAINT provider_cost_items_code_check
    CHECK (code IS NULL OR length(btrim(code)) BETWEEN 1 AND 80),
  CONSTRAINT provider_cost_items_description_check
    CHECK (description IS NULL OR length(description) <= 4000)
);

CREATE UNIQUE INDEX provider_cost_items_code_unique
  ON public.provider_cost_items (organization_id, lower(btrim(code)))
  WHERE code IS NOT NULL AND length(btrim(code)) > 0;

CREATE INDEX provider_cost_items_name_idx
  ON public.provider_cost_items (organization_id, lower(btrim(name)));

CREATE INDEX provider_cost_items_category_idx
  ON public.provider_cost_items (organization_id, category_code, is_active);

CREATE TRIGGER provider_cost_items_assert_org
  BEFORE INSERT OR UPDATE OF organization_id
  ON public.provider_cost_items
  FOR EACH ROW
  EXECUTE FUNCTION public.provider_cost_assert_provider_organization();

CREATE TRIGGER provider_cost_items_updated_at
  BEFORE UPDATE ON public.provider_cost_items
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_updated_at();

-- Cost data is private to authorized commercial roles of its provider tenant.
-- No anon access, no hard-delete policy, and no browser ability to change tenant
-- ownership or the creator identity.
REVOKE ALL ON public.provider_cost_suppliers, public.provider_cost_items
  FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.provider_cost_suppliers, public.provider_cost_items
  TO authenticated;

GRANT INSERT (
  organization_id, display_name, legal_name, tax_id, email, phone, notes, is_active
) ON public.provider_cost_suppliers TO authenticated;

GRANT UPDATE (
  display_name, legal_name, tax_id, email, phone, notes, is_active
) ON public.provider_cost_suppliers TO authenticated;

GRANT INSERT (
  organization_id, code, name, description, category_code,
  default_unit_code, technical_specification, is_active
) ON public.provider_cost_items TO authenticated;

GRANT UPDATE (
  code, name, description, category_code,
  default_unit_code, technical_specification, is_active
) ON public.provider_cost_items TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.provider_cost_suppliers, public.provider_cost_items
  TO service_role;

ALTER TABLE public.provider_cost_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_cost_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY provider_cost_suppliers_read
  ON public.provider_cost_suppliers
  FOR SELECT TO authenticated
  USING (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
  );

CREATE POLICY provider_cost_suppliers_insert
  ON public.provider_cost_suppliers
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by = (SELECT auth.uid())
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

CREATE POLICY provider_cost_suppliers_update
  ON public.provider_cost_suppliers
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

CREATE POLICY provider_cost_items_read
  ON public.provider_cost_items
  FOR SELECT TO authenticated
  USING (
    (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    ))
  );

CREATE POLICY provider_cost_items_insert
  ON public.provider_cost_items
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by = (SELECT auth.uid())
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

CREATE POLICY provider_cost_items_update
  ON public.provider_cost_items
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

REVOKE ALL ON FUNCTION public.provider_cost_assert_provider_organization()
  FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.provider_cost_suppliers IS
  'ROMAX provider-owned supplier master. Supplier is optional on internal cost rates.';
COMMENT ON TABLE public.provider_cost_items IS
  'Reusable ROMAX cost resources. Independent of customers and warehouse inventory.';
