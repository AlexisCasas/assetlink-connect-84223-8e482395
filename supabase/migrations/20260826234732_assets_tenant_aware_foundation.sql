-- Assets tenant-aware foundation.
-- Single hierarchical "assets" table (parent_asset_id) instead of separate
-- tables per level (sociedad/sector/flota/componente). "Empresa/sector" nodes
-- inside the tree are NOT organizations; organization_id is the real tenant.

-- =========================================================================
-- A) asset_categories
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.asset_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  parent_category_id uuid NULL REFERENCES public.asset_categories(id) ON DELETE SET NULL,
  name text NOT NULL,
  description text NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_asset_categories_organization_id ON public.asset_categories (organization_id);
CREATE INDEX IF NOT EXISTS idx_asset_categories_parent_category_id ON public.asset_categories (parent_category_id);
CREATE INDEX IF NOT EXISTS idx_asset_categories_is_active ON public.asset_categories (organization_id, is_active);
CREATE UNIQUE INDEX IF NOT EXISTS uq_asset_categories_org_name ON public.asset_categories (organization_id, lower(name));

DROP TRIGGER IF EXISTS trg_asset_categories_updated_at ON public.asset_categories;
CREATE TRIGGER trg_asset_categories_updated_at
BEFORE UPDATE ON public.asset_categories
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- =========================================================================
-- B) assets
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  branch_id uuid NULL REFERENCES public.client_branches(id) ON DELETE SET NULL,
  parent_asset_id uuid NULL REFERENCES public.assets(id) ON DELETE SET NULL,
  asset_category_id uuid NULL REFERENCES public.asset_categories(id) ON DELETE SET NULL,
  code text NULL,
  name text NOT NULL,
  description text NULL,
  node_type text NOT NULL DEFAULT 'equipment',
  status text NOT NULL DEFAULT 'active',
  criticality text NULL,
  manufacturer text NULL,
  model text NULL,
  serial_number text NULL,
  barcode text NULL,
  qr_code text NULL,
  purchase_date date NULL,
  warranty_until date NULL,
  location_text text NULL,
  image_url text NULL,
  technical_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT assets_node_type_check CHECK (
    node_type IN ('structure', 'site', 'area', 'system', 'fleet', 'equipment', 'component', 'subcomponent')
  ),
  CONSTRAINT assets_status_check CHECK (status IN ('active', 'maintenance', 'inactive', 'archived')),
  CONSTRAINT assets_criticality_check CHECK (criticality IS NULL OR criticality IN ('low', 'medium', 'high', 'critical')),
  CONSTRAINT assets_parent_not_self CHECK (parent_asset_id IS NULL OR parent_asset_id <> id)
);

CREATE INDEX IF NOT EXISTS idx_assets_organization_id ON public.assets (organization_id);
CREATE INDEX IF NOT EXISTS idx_assets_branch_id ON public.assets (branch_id);
CREATE INDEX IF NOT EXISTS idx_assets_parent_asset_id ON public.assets (parent_asset_id);
CREATE INDEX IF NOT EXISTS idx_assets_asset_category_id ON public.assets (asset_category_id);
CREATE INDEX IF NOT EXISTS idx_assets_status ON public.assets (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_assets_node_type ON public.assets (node_type);
CREATE INDEX IF NOT EXISTS idx_assets_name_lower ON public.assets (organization_id, lower(name));

DROP TRIGGER IF EXISTS trg_assets_updated_at ON public.assets;
CREATE TRIGGER trg_assets_updated_at
BEFORE UPDATE ON public.assets
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Consistency guard: parent asset / category / branch must belong to the same
-- organization_id as the row being written. Runs as SECURITY INVOKER on
-- purpose: the same tenant-scoped SELECT policies already visible to the
-- caller are enough to resolve these lookups, so no privilege escalation
-- is introduced by this trigger.
CREATE OR REPLACE FUNCTION public.check_asset_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  parent_org uuid;
  category_org uuid;
  branch_org uuid;
BEGIN
  IF NEW.parent_asset_id IS NOT NULL THEN
    SELECT organization_id INTO parent_org FROM public.assets WHERE id = NEW.parent_asset_id;
    IF parent_org IS NULL OR parent_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'parent_asset_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.asset_category_id IS NOT NULL THEN
    SELECT organization_id INTO category_org FROM public.asset_categories WHERE id = NEW.asset_category_id;
    IF category_org IS NULL OR category_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'asset_category_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.branch_id IS NOT NULL THEN
    SELECT organization_id INTO branch_org FROM public.client_branches WHERE id = NEW.branch_id;
    IF branch_org IS NULL OR branch_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'branch_id must belong to the same organization_id';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assets_check_consistency ON public.assets;
CREATE TRIGGER trg_assets_check_consistency
BEFORE INSERT OR UPDATE ON public.assets
FOR EACH ROW EXECUTE FUNCTION public.check_asset_consistency();

-- =========================================================================
-- C) asset_documents
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.asset_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
  document_type text NULL,
  name text NOT NULL,
  file_url text NULL,
  storage_path text NULL,
  uploaded_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_asset_documents_organization_id ON public.asset_documents (organization_id);
CREATE INDEX IF NOT EXISTS idx_asset_documents_asset_id ON public.asset_documents (asset_id);

-- =========================================================================
-- D) asset_events
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.asset_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  description text NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_asset_events_organization_id ON public.asset_events (organization_id);
CREATE INDEX IF NOT EXISTS idx_asset_events_asset_id ON public.asset_events (asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_events_event_type ON public.asset_events (event_type);

-- Same tenant-consistency guard as assets, reused for the two child tables:
-- organization_id must match the organization_id of the referenced asset_id.
CREATE OR REPLACE FUNCTION public.check_asset_child_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  asset_org uuid;
BEGIN
  SELECT organization_id INTO asset_org FROM public.assets WHERE id = NEW.asset_id;
  IF asset_org IS NULL OR asset_org <> NEW.organization_id THEN
    RAISE EXCEPTION 'organization_id must match the organization_id of asset_id';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_asset_documents_check_org ON public.asset_documents;
CREATE TRIGGER trg_asset_documents_check_org
BEFORE INSERT OR UPDATE ON public.asset_documents
FOR EACH ROW EXECUTE FUNCTION public.check_asset_child_organization();

DROP TRIGGER IF EXISTS trg_asset_events_check_org ON public.asset_events;
CREATE TRIGGER trg_asset_events_check_org
BEFORE INSERT OR UPDATE ON public.asset_events
FOR EACH ROW EXECUTE FUNCTION public.check_asset_child_organization();

-- =========================================================================
-- RLS
-- =========================================================================
ALTER TABLE public.asset_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_events ENABLE ROW LEVEL SECURITY;

-- asset_categories --------------------------------------------------------
CREATE POLICY "organization members can view asset categories" ON public.asset_categories
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization managers can create asset categories" ON public.asset_categories
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  );

CREATE POLICY "organization managers can update asset categories" ON public.asset_categories
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  );

-- assets --------------------------------------------------------------------
CREATE POLICY "organization members can view assets" ON public.assets
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization managers can create assets" ON public.assets
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  );

CREATE POLICY "organization managers can update assets" ON public.assets
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  );

-- asset_documents -----------------------------------------------------------
CREATE POLICY "organization members can view asset documents" ON public.asset_documents
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization managers can create asset documents" ON public.asset_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  );

CREATE POLICY "organization managers can update asset documents" ON public.asset_documents
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  );

-- asset_events ----------------------------------------------------------------
CREATE POLICY "organization members can view asset events" ON public.asset_events
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "organization managers can create asset events" ON public.asset_events
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  );

CREATE POLICY "organization managers can update asset events" ON public.asset_events
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ))
  );

-- No DELETE policy on any of the 4 tables for now. Logical archive only via
-- assets.status = 'archived'.

-- =========================================================================
-- Grants (PostgREST needs object privileges before RLS is evaluated; RLS
-- above remains the actual authorization boundary). No privileges to anon.
-- =========================================================================
GRANT SELECT, INSERT, UPDATE ON TABLE public.asset_categories TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.assets TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.asset_documents TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.asset_events TO authenticated;
