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
  -- Generated columns are not populated in NEW during BEFORE triggers;
  -- exclude the generated PEN snapshot from immutable-field comparison.
  IF (to_jsonb(NEW) - ARRAY['valid_until','status','updated_at','review_note','unit_cost_pen'])
     IS DISTINCT FROM
     (to_jsonb(OLD) - ARRAY['valid_until','status','updated_at','review_note','unit_cost_pen'])
     OR NEW.status NOT IN ('approved','archived')
  THEN
   RAISE EXCEPTION 'Approved cost rate is immutable; only validity closure or archival is allowed';
  END IF;
  IF NEW.status='archived' AND NEW.valid_until IS NULL THEN
   RAISE EXCEPTION 'Close the validity window before archiving an approved rate';
  END IF;
 END IF;

 IF TG_OP='INSERT' AND NEW.version_number=0 THEN
  PERFORM pg_advisory_xact_lock(hashtextextended(
    NEW.organization_id::text || ':' || NEW.cost_item_id::text || ':' || coalesce(NEW.supplier_id::text,'internal'),0
  ));
  SELECT coalesce(max(r.version_number),0)+1 INTO NEW.version_number
  FROM public.provider_cost_rates r
  WHERE r.organization_id=NEW.organization_id
   AND r.cost_item_id=NEW.cost_item_id
   AND r.supplier_id IS NOT DISTINCT FROM NEW.supplier_id;
 END IF;

 IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('approved','rejected') THEN
  v_role_ok := public.has_organization_role(NEW.organization_id,ARRAY['owner','admin','manager','quote_manager']::public.organization_member_role[]);
  IF NOT coalesce(v_role_ok,false) THEN
   RAISE EXCEPTION 'Not authorized to review this cost rate';
  END IF;
  NEW.reviewed_by := auth.uid();
  NEW.reviewed_at := now();
 ELSIF TG_OP='UPDATE' THEN
  NEW.reviewed_by := OLD.reviewed_by;
  NEW.reviewed_at := OLD.reviewed_at;
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
  IF v_overlap THEN RAISE EXCEPTION 'Approved rate validity overlaps another approved version in the same resource/supplier series'; END IF;
 END IF;
 NEW.updated_at := now();
 RETURN NEW;
END;
$$;