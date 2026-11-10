-- One Facility | 9C.6-B2.3 / D4: CLIENT-SIDE FM follow-up on EXTERNAL OT.
-- Independent from work_order_work_logs, provider observations, and execution.
-- Staged: read enabled after installation, write RPC has EXECUTE revoked until
-- a separately authorized QA window / UI verification. No live OT changes.
DO $preflight$
BEGIN
  IF to_regprocedure('public.has_facility_management_operational_access_all(uuid,public.facility_management_permission[],public.organization_member_role[])') IS NULL
    OR to_regclass('public.work_orders') IS NULL
    OR to_regclass('public.organization_relationships') IS NULL
    OR to_regclass('public.facility_management_relationship_members') IS NULL
    OR to_regclass('public.audit_logs') IS NULL
  THEN RAISE EXCEPTION '9C.6-B2.3 requires FM relationship, authorization and audit primitives'; END IF;
END
$preflight$;

CREATE TABLE public.facility_management_work_order_followups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  relationship_id uuid NOT NULL REFERENCES public.organization_relationships(id) ON DELETE RESTRICT,
  work_order_id uuid NOT NULL REFERENCES public.work_orders(id) ON DELETE RESTRICT,
  author_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  author_name_snapshot text NOT NULL,
  idempotency_key uuid NOT NULL,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fm_wo_followup_author_name_length CHECK (
    length(btrim(author_name_snapshot)) BETWEEN 1 AND 120
  ),
  CONSTRAINT fm_wo_followup_body_length CHECK (
    length(btrim(body)) BETWEEN 1 AND 2000
  ),
  CONSTRAINT fm_wo_followup_one_per_intent UNIQUE (
    relationship_id, work_order_id, idempotency_key
  )
);

CREATE INDEX fm_wo_followup_read_idx
  ON public.facility_management_work_order_followups (
    relationship_id, work_order_id, created_at DESC, id DESC
  );

ALTER TABLE public.facility_management_work_order_followups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_management_work_order_followups FORCE ROW LEVEL SECURITY;
-- No direct table policies: RLS deny-all plus table ACL. All access via safe RPC.
REVOKE ALL ON TABLE public.facility_management_work_order_followups
  FROM PUBLIC, anon, authenticated, service_role;

-- Match the actual relationship passed into the RPC, not merely any
-- relationship covering this same client. This prevents cross-FM sharing.
CREATE OR REPLACE FUNCTION public.has_facility_management_followup_relation_access(
  _client_organization_id uuid,
  _relationship_id uuid,
  _permissions public.facility_management_permission[],
  _allowed_roles public.organization_member_role[]
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT auth.uid() IS NOT NULL
    AND _client_organization_id IS NOT NULL AND _relationship_id IS NOT NULL
    AND COALESCE(array_length(_permissions,1),0) > 0
    AND COALESCE(array_length(_allowed_roles,1),0) > 0
    AND EXISTS (
      SELECT 1 FROM public.organization_relationships rel
      JOIN public.organizations client
        ON client.id = rel.source_organization_id
        AND client.organization_type='client_company' AND client.status='active'
      JOIN public.organizations fm
        ON fm.id = rel.target_organization_id
        AND fm.organization_type='facility_manager' AND fm.status='active'
      JOIN public.organization_members member
        ON member.organization_id=fm.id
        AND member.user_id=auth.uid()
        AND member.is_active AND member.role=ANY(_allowed_roles)
      JOIN public.facility_management_relationship_members assignment
        ON assignment.relationship_id=rel.id
        AND assignment.organization_member_id=member.id
      WHERE rel.id=_relationship_id
        AND rel.source_organization_id=_client_organization_id
        AND rel.relationship_type='facility_management'
        AND rel.status='active'
        AND NOT EXISTS (
          SELECT 1 FROM unnest(_permissions) req(permission)
          WHERE req.permission IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.facility_management_permissions gp
            WHERE gp.relationship_id=rel.id AND gp.permission=req.permission
          )
        )
    );
$function$;

REVOKE ALL ON FUNCTION public.has_facility_management_followup_relation_access(
  uuid,uuid,public.facility_management_permission[],public.organization_member_role[]
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_facility_management_work_order_followups(
  _client_organization_id uuid,
  _relationship_id uuid,
  _work_order_id uuid,
  _limit integer DEFAULT 20,
  _offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
SET statement_timeout TO '5s'
AS $function$
DECLARE v_items jsonb; v_total integer;
BEGIN
  IF _limit IS NULL OR _limit<1 OR _limit>50
    OR _offset IS NULL OR _offset<0 OR _offset>10000
  THEN RAISE EXCEPTION 'Invalid follow-up pagination' USING ERRCODE='22023'; END IF;

  IF NOT public.has_facility_management_followup_relation_access(
    _client_organization_id,_relationship_id,
    ARRAY['requests.view','work_orders.view']::public.facility_management_permission[],
    ARRAY['owner','admin','manager','requester']::public.organization_member_role[]
  ) OR NOT EXISTS (
    SELECT 1 FROM public.work_orders wo
    WHERE wo.id=_work_order_id
      AND wo.client_organization_id=_client_organization_id
      AND wo.work_order_type='external'
      AND wo.quote_id IS NOT NULL
      AND wo.provider_organization_id<>wo.client_organization_id
      AND EXISTS (
        SELECT 1 FROM public.requests r
        WHERE r.id=wo.request_id AND r.organization_id=_client_organization_id
          AND r.status NOT IN ('draft','anulado')
      )
  )
  THEN RAISE EXCEPTION 'Not authorized to view this follow-up' USING ERRCODE='42501'; END IF;

  SELECT count(*)::integer INTO v_total
  FROM public.facility_management_work_order_followups n
  WHERE n.client_organization_id=_client_organization_id
    AND n.relationship_id=_relationship_id
    AND n.work_order_id=_work_order_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',n.id,'body',n.body,'created_at',n.created_at,
    'author_name',n.author_name_snapshot,
    'authored_by_me',(n.author_user_id=auth.uid())
  ) ORDER BY n.created_at DESC,n.id DESC),'[]'::jsonb)
  INTO v_items
  FROM (
    SELECT id,body,created_at,author_user_id,author_name_snapshot
    FROM public.facility_management_work_order_followups
    WHERE client_organization_id=_client_organization_id
      AND relationship_id=_relationship_id
      AND work_order_id=_work_order_id
    ORDER BY created_at DESC,id DESC
    LIMIT _limit OFFSET _offset
  ) n;
  RETURN pg_catalog.jsonb_build_object(
    'items',v_items,'total',v_total,'limit',_limit,'offset',_offset
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.add_facility_management_work_order_followup(
  _client_organization_id uuid,
  _relationship_id uuid,
  _work_order_id uuid,
  _body text,
  _idempotency_key uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO ''
SET lock_timeout TO '3s'
AS $function$
DECLARE v_note public.facility_management_work_order_followups%ROWTYPE;
        v_new boolean:=false;
        v_message text;
        v_author_name text;
BEGIN
  IF NOT public.has_facility_management_followup_relation_access(
    _client_organization_id,_relationship_id,
    ARRAY['requests.view','work_orders.view','work_orders.manage']::public.facility_management_permission[],
    ARRAY['owner','admin','manager']::public.organization_member_role[]
  )
  THEN RAISE EXCEPTION 'Not authorized to add this follow-up' USING ERRCODE='42501'; END IF;

  IF _idempotency_key IS NULL OR _body IS NULL
    OR length(btrim(_body)) NOT BETWEEN 1 AND 2000
  THEN RAISE EXCEPTION 'Invalid follow-up text or request ID' USING ERRCODE='22023'; END IF;
  v_message:=btrim(_body);
  -- Display-only snapshot; never used for authorization. Keep author UUID
  -- private to audit/storage, and never expose email or auth metadata.
  SELECT pg_catalog.left(COALESCE(
    NULLIF(pg_catalog.btrim(u.raw_user_meta_data->>'name'),''),
    'Miembro Facility Manager'
  ),120) INTO v_author_name
  FROM auth.users u WHERE u.id=auth.uid();
  IF v_author_name IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE='42501';
  END IF;

  -- Share-lock the OT and its source request, without updating either.
  -- This closes the race where a request becomes draft/annulled mid-write.
  PERFORM wo.id FROM public.work_orders wo
  JOIN public.requests r
    ON r.id=wo.request_id
   AND r.organization_id=_client_organization_id
   AND r.status NOT IN ('draft','anulado')
  WHERE wo.id=_work_order_id
    AND wo.client_organization_id=_client_organization_id
    AND wo.work_order_type='external'
    AND wo.quote_id IS NOT NULL
    AND wo.provider_organization_id<>wo.client_organization_id
  FOR SHARE OF wo, r;
  IF NOT FOUND
  THEN RAISE EXCEPTION 'Not authorized to add this follow-up' USING ERRCODE='42501'; END IF;

  IF NOT public.has_facility_management_followup_relation_access(
    _client_organization_id,_relationship_id,
    ARRAY['requests.view','work_orders.view','work_orders.manage']::public.facility_management_permission[],
    ARRAY['owner','admin','manager']::public.organization_member_role[]
  )
  THEN RAISE EXCEPTION 'Not authorized to add this follow-up' USING ERRCODE='42501'; END IF;

  INSERT INTO public.facility_management_work_order_followups (
    client_organization_id,relationship_id,work_order_id,
    author_user_id,author_name_snapshot,idempotency_key,body
  ) VALUES (
    _client_organization_id,_relationship_id,_work_order_id,
    auth.uid(),v_author_name,_idempotency_key,v_message
  )
  ON CONFLICT (relationship_id,work_order_id,idempotency_key) DO NOTHING
  RETURNING * INTO v_note;
  IF FOUND THEN
    v_new:=true;
  ELSE
    SELECT * INTO v_note
    FROM public.facility_management_work_order_followups n
    WHERE n.relationship_id=_relationship_id
      AND n.client_organization_id=_client_organization_id
      AND n.work_order_id=_work_order_id
      AND n.idempotency_key=_idempotency_key;
    IF NOT FOUND OR v_note.author_user_id IS DISTINCT FROM auth.uid()
      OR v_note.body IS DISTINCT FROM v_message
    THEN RAISE EXCEPTION 'Follow-up request ID already used' USING ERRCODE='22023'; END IF;
  END IF;

  IF v_new THEN
    -- Audit is intentionally text-free (notes may contain private details).
    INSERT INTO public.audit_logs (
      organization_id,actor_user_id,table_name,record_id,action,old_data,new_data
    ) VALUES (
      _client_organization_id,auth.uid(),
      'facility_management_work_order_followups',v_note.id,
      'facility_manager_external_work_order_followup_created',NULL,
      pg_catalog.jsonb_build_object(
        'work_order_id',_work_order_id,
        'relationship_id',_relationship_id,
        'body_length',length(v_message)
      )
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'id',v_note.id,'body',v_note.body,'created_at',v_note.created_at,
    'author_name',v_note.author_name_snapshot,
    'authored_by_me',true
  );
END
$function$;

REVOKE ALL ON FUNCTION public.get_facility_management_work_order_followups(
  uuid,uuid,uuid,integer,integer
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_facility_management_work_order_followups(
  uuid,uuid,uuid,integer,integer
) TO authenticated;

-- Fail-closed in B2.3 deployment. C2.3 requires a separate reviewed activation.
REVOKE ALL ON FUNCTION public.add_facility_management_work_order_followup(
  uuid,uuid,uuid,text,uuid
) FROM PUBLIC, anon, authenticated, service_role;
