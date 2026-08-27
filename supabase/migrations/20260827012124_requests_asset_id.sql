-- Links a request to a real tenant-aware asset (public.assets), replacing
-- the free-text "equipo" as the productive source of truth going forward.
-- Legacy text columns (requests.asset, request_details.equipment/
-- sub_equipment) are kept untouched for backward compatibility and visual
-- fallback when a request has no linked asset.
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS asset_id uuid NULL REFERENCES public.assets(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_requests_asset_id ON public.requests (asset_id);

-- Consistency guard, same pattern as public.assets' own
-- check_asset_consistency: a linked asset must belong to the same
-- organization_id as the request. Runs as SECURITY INVOKER on purpose — the
-- caller already has the tenant-scoped SELECT access on public.assets
-- needed to resolve this lookup (they must be a member of that
-- organization to have set asset_id in the first place), so no privilege
-- escalation is introduced.
CREATE OR REPLACE FUNCTION public.check_request_asset_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  asset_org uuid;
BEGIN
  IF NEW.asset_id IS NOT NULL THEN
    SELECT organization_id INTO asset_org FROM public.assets WHERE id = NEW.asset_id;
    IF asset_org IS NULL OR NEW.organization_id IS NULL OR asset_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'asset_id must belong to the same organization_id as the request';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_requests_check_asset_org ON public.requests;
CREATE TRIGGER trg_requests_check_asset_org
BEFORE INSERT OR UPDATE ON public.requests
FOR EACH ROW EXECUTE FUNCTION public.check_request_asset_organization();

-- No RLS changes: existing policies on public.requests (can_user_read_request)
-- and public.assets (is_organization_member / is_platform_admin) are already
-- correct for this column. A provider who can already read a request row via
-- RLS now also sees its (opaque, harmless) asset_id, but their existing RLS
-- on public.assets still blocks reading the linked asset row directly — by
-- design, providers only see the denormalized asset name/type the client
-- already writes into requests.asset (a pre-existing text column), never the
-- full asset (no serial number, no technical_data, etc.).
