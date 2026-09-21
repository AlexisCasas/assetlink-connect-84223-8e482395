-- A meter reading used to complete a preventive occurrence must represent the
-- maintenance window, rather than an older baseline.  This replaces the
-- trigger function without changing the trigger or its transition coverage.
CREATE OR REPLACE FUNCTION public.sync_preventive_occurrence_from_work_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan_id uuid;
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
  v_reading public.asset_meter_readings%ROWTYPE;
  v_next public.preventive_maintenance_occurrences%ROWTYPE;
  v_terminal_transition boolean;
  v_meter_name text;
BEGIN
  v_terminal_transition := NEW.status IN ('completed', 'closed')
    AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('completed', 'closed'));

  SELECT o.plan_id INTO v_plan_id FROM public.preventive_maintenance_occurrences o
  WHERE o.work_order_id = NEW.id OR (o.request_id = NEW.request_id AND o.status = 'planned')
  ORDER BY (o.work_order_id = NEW.id) DESC LIMIT 1;
  IF v_plan_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = v_plan_id FOR UPDATE;
  SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences o
  WHERE o.plan_id = v_plan_id AND (o.work_order_id = NEW.id OR o.request_id = NEW.request_id)
  ORDER BY (o.work_order_id = NEW.id) DESC LIMIT 1 FOR UPDATE;

  IF v_occ.organization_id IS DISTINCT FROM NEW.client_organization_id
    OR v_occ.asset_id IS DISTINCT FROM NEW.asset_id THEN
    RAISE EXCEPTION 'Work order tenant and asset must match the preventive occurrence';
  END IF;
  IF v_occ.request_id IS DISTINCT FROM NEW.request_id THEN
    RAISE EXCEPTION 'Work order request must match the preventive occurrence';
  END IF;
  IF v_occ.work_order_id IS NULL THEN
    IF v_occ.status <> 'planned' THEN RAISE EXCEPTION 'Only a planned occurrence can attach a work order'; END IF;
    UPDATE public.preventive_maintenance_occurrences SET work_order_id = NEW.id
    WHERE id = v_occ.id RETURNING * INTO v_occ;
  ELSIF v_occ.work_order_id <> NEW.id THEN
    RAISE EXCEPTION 'Preventive occurrence is already attached to a different work order';
  END IF;

  IF NOT v_terminal_transition OR v_occ.status = 'completed' THEN RETURN NEW; END IF;
  IF v_occ.status <> 'planned' THEN RAISE EXCEPTION 'Only a planned occurrence can be completed'; END IF;

  IF v_plan.trigger_type = 'meter' THEN
    SELECT am.name INTO v_meter_name FROM public.asset_meters am WHERE am.id = v_plan.meter_id;
    SELECT r.* INTO v_reading FROM public.asset_meter_readings r
    WHERE r.meter_id = v_plan.meter_id
      AND r.voided_at IS NULL
      AND r.recorded_at >= v_occ.planned_at
      AND r.recorded_at <= NEW.completed_at
    ORDER BY r.recorded_at DESC LIMIT 1;
    IF v_reading.id IS NULL THEN
      RAISE EXCEPTION 'Registra una lectura actual del medidor % antes de completar este mantenimiento preventivo.', COALESCE(v_meter_name, 'del plan');
    END IF;
  END IF;

  UPDATE public.preventive_maintenance_occurrences SET
    status = 'completed', completed_at = NEW.completed_at,
    completion_meter_reading_id = CASE WHEN v_plan.trigger_type = 'meter' THEN v_reading.id ELSE NULL END,
    completion_meter_value = CASE WHEN v_plan.trigger_type = 'meter' THEN v_reading.value ELSE NULL END
  WHERE id = v_occ.id RETURNING * INTO v_occ;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_occ.organization_id, v_occ.asset_id, 'preventive_maintenance_completed',
    'Mantenimiento preventivo completado',
    jsonb_build_object('plan_id', v_occ.plan_id, 'occurrence_id', v_occ.id,
      'work_order_id', NEW.id, 'sequence', v_occ.sequence,
      'completion_meter_value', v_occ.completion_meter_value), auth.uid()
  );
  PERFORM public.notify_preventive_occurrence(
    v_occ.id, 'preventive_maintenance_completed', 'Mantenimiento preventivo completado',
    'La ocurrencia preventiva #' || v_occ.sequence::text || ' fue completada.'
  );

  IF v_plan.is_active THEN
    IF v_plan.trigger_type = 'calendar' THEN
      v_next := public.create_preventive_occurrence_locked(
        v_plan.id,
        NEW.completed_at + public.preventive_frequency_interval(v_plan.frequency, v_plan.custom_interval, v_plan.custom_unit),
        NULL
      );
    ELSE
      v_next := public.create_preventive_occurrence_locked(v_plan.id, NULL, v_reading.value + v_plan.interval_value);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_preventive_occurrence_from_work_order() FROM PUBLIC, anon, authenticated;
