-- ROMAX R2-E2.1: per-user pricing capabilities and market-cost access boundaries.
-- Additive migration. No Cloud apply, price import, or historical data changes.
CREATE TABLE public.provider_pricing_access_grants (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 capability text NOT NULL CHECK (capability IN (
  'market_cost.read',
  'market_cost.manage',
  'market_cost.validate',
  'commercial_price.read',
  'commercial_price.propose',
  'commercial_price.approve',
  'pricing_rules.manage'
 )),
 granted_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
 granted_at timestamptz NOT NULL DEFAULT now(),
 revoked_at timestamptz,
 revoked_by uuid REFERENCES auth.users(id),
 revocation_reason text,
 CONSTRAINT provider_pricing_access_grants_revocation_pair CHECK (
  (revoked_at IS NULL AND revoked_by IS NULL)
  OR (revoked_at IS NOT NULL AND revoked_by IS NOT NULL)
 ),
 CONSTRAINT provider_pricing_access_grants_revocation_date CHECK (
  revoked_at IS NULL OR revoked_at >= granted_at
 ),
 CONSTRAINT provider_pricing_access_grants_reason_length CHECK (
  revocation_reason IS NULL OR length(revocation_reason) <= 500
 )
);
CREATE UNIQUE INDEX provider_pricing_access_grants_active_unique
 ON public.provider_pricing_access_grants(organization_id,user_id,capability)
 WHERE revoked_at IS NULL;
CREATE INDEX provider_pricing_access_grants_user_lookup
 ON public.provider_pricing_access_grants(organization_id,user_id,capability)
 WHERE revoked_at IS NULL;
CREATE INDEX provider_pricing_access_grants_granted_by_idx
 ON public.provider_pricing_access_grants(granted_by);

ALTER TABLE public.provider_pricing_access_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_pricing_access_grants FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.provider_pricing_access_grants TO authenticated;
GRANT UPDATE (revoked_at,revoked_by,revocation_reason) ON public.provider_pricing_access_grants TO authenticated;
GRANT ALL ON public.provider_pricing_access_grants TO service_role;

CREATE POLICY provider_pricing_access_grants_read
 ON public.provider_pricing_access_grants FOR SELECT TO authenticated
 USING (
  public.is_organization_member(organization_id)
  AND (
   user_id=(SELECT auth.uid())
   OR public.has_organization_role(organization_id,ARRAY['owner','admin']::public.organization_member_role[])
  )
);
CREATE POLICY provider_pricing_access_grants_insert
 ON public.provider_pricing_access_grants FOR INSERT TO authenticated
 WITH CHECK (
  public.has_organization_role(organization_id,ARRAY['owner','admin']::public.organization_member_role[])
  AND granted_by=(SELECT auth.uid())
  AND EXISTS (
   SELECT 1 FROM public.organizations o
   WHERE o.id=organization_id
    AND o.organization_type='provider_company'
    AND o.status='active'
  )
  AND EXISTS (
   SELECT 1 FROM public.organization_members m
   WHERE m.organization_id=provider_pricing_access_grants.organization_id
    AND m.user_id=provider_pricing_access_grants.user_id
    AND m.is_active
  )
);
CREATE POLICY provider_pricing_access_grants_revoke
 ON public.provider_pricing_access_grants FOR UPDATE TO authenticated
 USING (
  public.has_organization_role(organization_id,ARRAY['owner','admin']::public.organization_member_role[])
  AND revoked_at IS NULL
 )
 WITH CHECK (
  public.has_organization_role(organization_id,ARRAY['owner','admin']::public.organization_member_role[])
  AND revoked_at IS NOT NULL
  AND revoked_by=(SELECT auth.uid())
);

CREATE OR REPLACE FUNCTION public.guard_provider_pricing_access_grant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=''
AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.granted_by IS DISTINCT FROM auth.uid()
     OR NEW.revoked_at IS NOT NULL
     OR NEW.revoked_by IS NOT NULL THEN
   RAISE EXCEPTION 'Pricing access grants must be created by the granting user and start active';
  END IF;
  RETURN NEW;
 END IF;

 IF TG_OP='UPDATE' THEN
  IF OLD.revoked_at IS NOT NULL THEN
   RAISE EXCEPTION 'Pricing access grant revocation is final';
  END IF;
  IF (to_jsonb(NEW)-ARRAY['revoked_at','revoked_by','revocation_reason'])
     IS DISTINCT FROM
     (to_jsonb(OLD)-ARRAY['revoked_at','revoked_by','revocation_reason']) THEN
   RAISE EXCEPTION 'Pricing access grant identity and provenance are immutable';
  END IF;
  IF NEW.revoked_at IS NULL OR NEW.revoked_by IS DISTINCT FROM auth.uid() THEN
   RAISE EXCEPTION 'Pricing access grants can only be revoked, not reactivated';
  END IF;
  RETURN NEW;
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER provider_pricing_access_grants_guard
 BEFORE INSERT OR UPDATE ON public.provider_pricing_access_grants
 FOR EACH ROW EXECUTE FUNCTION public.guard_provider_pricing_access_grant();
REVOKE ALL ON FUNCTION public.guard_provider_pricing_access_grant() FROM PUBLIC,anon,authenticated;

-- A read, manage or validate grant is required to see acquisition costs and suppliers.
DROP POLICY provider_cost_rates_read ON public.provider_cost_rates;
CREATE POLICY provider_cost_rates_read
 ON public.provider_cost_rates FOR SELECT TO authenticated
 USING (
  public.is_organization_member(organization_id)
  AND EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_rates.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability IN ('market_cost.read','market_cost.manage','market_cost.validate')
    AND g.revoked_at IS NULL
  )
);

DROP POLICY provider_cost_rates_insert ON public.provider_cost_rates;
CREATE POLICY provider_cost_rates_insert
 ON public.provider_cost_rates FOR INSERT TO authenticated
 WITH CHECK (
  EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_rates.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability='market_cost.manage'
    AND g.revoked_at IS NULL
  )
  AND EXISTS (
   SELECT 1 FROM public.organizations o
   WHERE o.id=organization_id
    AND o.organization_type='provider_company'
    AND o.status='active'
  )
  AND created_by=(SELECT auth.uid())
  AND status IN ('draft','pending_review')
);

DROP POLICY provider_cost_rates_update ON public.provider_cost_rates;
CREATE POLICY provider_cost_rates_update
 ON public.provider_cost_rates FOR UPDATE TO authenticated
 USING (
  public.is_organization_member(organization_id)
  AND status IN ('draft','pending_review','rejected','approved')
  AND EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_rates.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability IN ('market_cost.manage','market_cost.validate')
    AND g.revoked_at IS NULL
  )
 )
 WITH CHECK (
  public.is_organization_member(organization_id)
  AND status IN ('draft','pending_review','approved','rejected','archived')
  AND EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_rates.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability IN ('market_cost.manage','market_cost.validate')
    AND g.revoked_at IS NULL
  )
 );

DROP POLICY provider_cost_suppliers_read ON public.provider_cost_suppliers;
CREATE POLICY provider_cost_suppliers_read
 ON public.provider_cost_suppliers FOR SELECT TO authenticated
 USING (
  public.is_organization_member(organization_id)
  AND EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_suppliers.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability IN ('market_cost.read','market_cost.manage','market_cost.validate')
    AND g.revoked_at IS NULL
  )
);
DROP POLICY provider_cost_suppliers_insert ON public.provider_cost_suppliers;
CREATE POLICY provider_cost_suppliers_insert
 ON public.provider_cost_suppliers FOR INSERT TO authenticated
 WITH CHECK (
  EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_suppliers.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability='market_cost.manage'
    AND g.revoked_at IS NULL
  )
  AND EXISTS (
   SELECT 1 FROM public.organizations o
   WHERE o.id=organization_id
    AND o.organization_type='provider_company'
    AND o.status='active'
  )
  AND created_by=(SELECT auth.uid())
);
DROP POLICY provider_cost_suppliers_update ON public.provider_cost_suppliers;
CREATE POLICY provider_cost_suppliers_update
 ON public.provider_cost_suppliers FOR UPDATE TO authenticated
 USING (
  public.is_organization_member(organization_id)
  AND EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_suppliers.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability='market_cost.manage'
    AND g.revoked_at IS NULL
  )
 )
 WITH CHECK (
  public.is_organization_member(organization_id)
  AND EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_suppliers.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability='market_cost.manage'
    AND g.revoked_at IS NULL
  )
 );

-- FX settings are governed by pricing_rules.manage, not broad organization roles.
DROP POLICY provider_cost_settings_insert ON public.provider_cost_settings;
CREATE POLICY provider_cost_settings_insert
 ON public.provider_cost_settings FOR INSERT TO authenticated
 WITH CHECK (
  EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_settings.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability='pricing_rules.manage'
    AND g.revoked_at IS NULL
  )
  AND EXISTS (
   SELECT 1 FROM public.organizations o
   WHERE o.id=organization_id
    AND o.organization_type='provider_company'
    AND o.status='active'
  )
  AND updated_by=(SELECT auth.uid())
);
DROP POLICY provider_cost_settings_update ON public.provider_cost_settings;
CREATE POLICY provider_cost_settings_update
 ON public.provider_cost_settings FOR UPDATE TO authenticated
 USING (
  public.is_organization_member(organization_id)
  AND EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_settings.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability='pricing_rules.manage'
    AND g.revoked_at IS NULL
  )
 )
 WITH CHECK (
  public.is_organization_member(organization_id)
  AND EXISTS (
   SELECT 1 FROM public.provider_pricing_access_grants g
   WHERE g.organization_id=provider_cost_settings.organization_id
    AND g.user_id=(SELECT auth.uid())
    AND g.capability='pricing_rules.manage'
    AND g.revoked_at IS NULL
  )
  AND updated_by=(SELECT auth.uid())
);

-- Trigger-level separation: manage can maintain drafts; validate can review;
-- the creator cannot approve/reject their own cost-rate submission.
CREATE OR REPLACE FUNCTION public.guard_provider_cost_rate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=''
AS $$
DECLARE
 v_can_manage boolean;
 v_can_validate boolean;
 v_overlap boolean;
BEGIN
 SELECT EXISTS (
  SELECT 1 FROM public.provider_pricing_access_grants g
  WHERE g.organization_id=NEW.organization_id
   AND g.user_id=(SELECT auth.uid())
   AND g.capability='market_cost.manage'
   AND g.revoked_at IS NULL
 ) INTO v_can_manage;

 SELECT EXISTS (
  SELECT 1 FROM public.provider_pricing_access_grants g
  WHERE g.organization_id=NEW.organization_id
   AND g.user_id=(SELECT auth.uid())
   AND g.capability='market_cost.validate'
   AND g.revoked_at IS NULL
 ) INTO v_can_validate;

 IF TG_OP='INSERT' THEN
  IF NOT coalesce(v_can_manage,false) THEN
   RAISE EXCEPTION 'market_cost.manage capability required to register a cost rate';
  END IF;
  IF NEW.status NOT IN ('draft','pending_review') THEN
   RAISE EXCEPTION 'New cost rates must start as draft or pending_review';
  END IF;
  IF NEW.version_number=0 THEN
   PERFORM pg_advisory_xact_lock(hashtextextended(
    NEW.organization_id::text || ':' || NEW.cost_item_id::text || ':' || coalesce(NEW.supplier_id::text,'internal'),0
   ));
   SELECT coalesce(max(r.version_number),0)+1 INTO NEW.version_number
   FROM public.provider_cost_rates r
   WHERE r.organization_id=NEW.organization_id
    AND r.cost_item_id=NEW.cost_item_id
    AND r.supplier_id IS NOT DISTINCT FROM NEW.supplier_id;
  END IF;
 ELSIF TG_OP='UPDATE' THEN
  IF OLD.status='approved' THEN
   IF NOT coalesce(v_can_validate,false) THEN
    RAISE EXCEPTION 'market_cost.validate capability required to close or archive an approved cost rate';
   END IF;
   IF (to_jsonb(NEW)-ARRAY['valid_until','status','updated_at','review_note','unit_cost_pen'])
      IS DISTINCT FROM
      (to_jsonb(OLD)-ARRAY['valid_until','status','updated_at','review_note','unit_cost_pen'])
      OR NEW.status NOT IN ('approved','archived') THEN
    RAISE EXCEPTION 'Approved cost rate is immutable; only validity closure or archival is allowed';
   END IF;
   IF NEW.status='archived' AND NEW.valid_until IS NULL THEN
    RAISE EXCEPTION 'Close the validity window before archiving an approved rate';
   END IF;
   NEW.reviewed_by := OLD.reviewed_by;
   NEW.reviewed_at := OLD.reviewed_at;
  ELSIF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('approved','rejected') THEN
   IF NOT coalesce(v_can_validate,false) THEN
    RAISE EXCEPTION 'market_cost.validate capability required to review a cost rate';
   END IF;
   IF OLD.created_by=(SELECT auth.uid()) THEN
    RAISE EXCEPTION 'A cost-rate creator cannot approve or reject their own submission';
   END IF;
   IF (to_jsonb(NEW)-ARRAY['status','updated_at','review_note','reviewed_by','reviewed_at','unit_cost_pen'])
      IS DISTINCT FROM
      (to_jsonb(OLD)-ARRAY['status','updated_at','review_note','reviewed_by','reviewed_at','unit_cost_pen']) THEN
    RAISE EXCEPTION 'A cost-rate review may only change status and review note';
   END IF;
   NEW.reviewed_by := (SELECT auth.uid());
   NEW.reviewed_at := now();
  ELSE
   IF NOT coalesce(v_can_manage,false) THEN
    RAISE EXCEPTION 'market_cost.manage capability required to maintain a draft cost rate';
   END IF;
   NEW.reviewed_by := OLD.reviewed_by;
   NEW.reviewed_at := OLD.reviewed_at;
  END IF;
 END IF;

 IF NEW.currency_code='USD' AND NEW.fx_source='organization_default' THEN
  SELECT s.default_usd_pen_rate,s.fx_date,s.fx_reference
   INTO NEW.fx_rate_to_pen,NEW.fx_date,NEW.fx_reference
  FROM public.provider_cost_settings s
  WHERE s.organization_id=NEW.organization_id;
  IF NEW.fx_date IS NULL OR NEW.fx_rate_to_pen IS NULL THEN
   RAISE EXCEPTION 'Organization default USD/PEN rate is not configured with a date';
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
  IF v_overlap THEN
   RAISE EXCEPTION 'Approved rate validity overlaps another approved version in the same resource/supplier series';
  END IF;
 END IF;

 NEW.updated_at := now();
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_provider_cost_rate() FROM PUBLIC,anon,authenticated;

COMMENT ON TABLE public.provider_pricing_access_grants IS
 'Per-user, tenant-scoped pricing capabilities. Grants are immutable except for one-way revocation; commercial price capabilities are reserved for later R2-E2 increments.';
COMMENT ON COLUMN public.provider_cost_rates.status IS
 'Acquisition-cost workflow: market_cost.manage registers drafts; market_cost.validate reviews. The creator cannot approve/reject their own submission.';
