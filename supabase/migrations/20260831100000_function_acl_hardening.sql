-- Fase 17 — Estabilización crítica: cierra el hallazgo confirmado contra
-- Supabase remoto (Security Advisor + inspección directa de pg_proc/
-- pg_default_acl):
--   (a) 74 funciones SECURITY DEFINER de public tenían EXECUTE efectivo
--       para el rol anon, incluso en los casos donde ya se había hecho
--       REVOKE ALL ... FROM PUBLIC — porque PUBLIC y anon son entradas de
--       ACL independientes, y anon lo heredaba de un default privilege
--       configurado fuera de las migraciones versionadas de este repo.
--   (b) Confirmado además: 28 funciones de public en producción todavía
--       tienen EXECUTE concedido a PUBLIC directamente (no solo heredado
--       por anon) — revocar únicamente de anon no alcanza, porque
--       cualquier rol (incluido authenticated) sigue heredando lo que
--       PUBLIC conserve. Hay que revocar de PUBLIC explícitamente además.
-- (pg_default_acl del owner postgres sobre el schema public, confirmado:
-- TODAS las funciones de public, incluidas las más recientes, son
-- propiedad de postgres.)
--
-- Bloques, en el orden en que deben aplicarse:
--   1) Revoca PUBLIC y anon de TODO public de una sola vez cada uno
--      (cierra ambas brechas ya).
--   1b) storage_request_id_from_name: no es SECURITY DEFINER ni una RPC
--       de frontend, pero las policies RLS de storage.objects para
--       request-detail-attachments la llaman directamente en su USING/
--       WITH CHECK — necesita EXECUTE explícito para authenticated tras
--       el REVOKE global de PUBLIC del bloque 1, o esas policies
--       empezarían a fallar con "permission denied for function".
--   2) Revoca anon Y authenticated de los 11 helpers/trigger functions
--      identificados en la auditoría (nunca deben ser RPC directas ni
--      llamables fuera de su propio contexto de trigger).
--   3) Reafirma explícitamente GRANT EXECUTE TO authenticated en las 64
--      RPC de cara al frontend (idempotente: ya lo tenían desde sus
--      migraciones originales; se repite aquí para dejar un registro
--      auditable y a prueba de que el bloque 1 no las haya afectado).
--   4) Corrige la causa raíz para toda función futura creada por
--      postgres en public — PUBLIC y anon/authenticated por separado.
--
-- No se otorga NINGÚN privilegio a anon en esta migración.

-- =========================================================================
-- 1) PUBLIC y anon: revoca EXECUTE de TODAS las funciones existentes en
--    public, dos sentencias separadas (incluye las 74 SECURITY DEFINER y
--    cualquier otra función del schema — confirmado: 28 de ellas seguían
--    con EXECUTE concedido a PUBLIC en producción). Ninguna función de
--    este proyecto está diseñada para ser invocada por anon (confirmado:
--    cero "GRANT ... TO anon" en todo el historial de migraciones), y las
--    únicas que deben seguir siendo accesibles sin pasar por un GRANT
--    propio (storage_request_id_from_name, bloque 1b; las 64 RPC del
--    bloque 3) reciben su GRANT explícito a continuación — así que este
--    REVOKE global no debería romper ningún otro flujo — se valida
--    explícitamente en las pruebas locales de esta fase.
-- =========================================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;

-- =========================================================================
-- 1b) storage_request_id_from_name — SECURITY INVOKER (no escala
--     privilegios: solo parsea el nombre del objeto), pero es llamada
--     directamente dentro de las policies RLS "... request detail
--     attachments" sobre storage.objects (todas TO authenticated —
--     20260721171427_request_attachments_storage_rls.sql), así que
--     authenticated necesita EXECUTE explícito tras el REVOKE de PUBLIC
--     de arriba. anon no la recibe: ninguna de esas policies es TO anon.
-- =========================================================================
GRANT EXECUTE ON FUNCTION public.storage_request_id_from_name(text) TO authenticated;

-- =========================================================================
-- 2) Helpers internos y trigger functions — ni anon ni authenticated deben
--    poder invocarlas directamente. Los helpers siguen siendo llamables
--    desde otras funciones SECURITY DEFINER propiedad de postgres (esa
--    llamada interna corre con los privilegios del owner, no con los del
--    rol que invocó la RPC pública original) — sin necesidad de GRANT.
--    Los trigger functions siguen disparándose solas vía CREATE TRIGGER
--    (el motor de triggers no exige EXECUTE al rol que provoca el evento
--    DML) — verificado en las pruebas locales de esta fase.
--
--    Helpers internos (5):
-- =========================================================================
REVOKE ALL ON FUNCTION public.create_organization_notification(uuid, uuid, text, text, text, text, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_notification_once(uuid, uuid, uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_role_members(uuid, public.organization_member_role[], uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_member(uuid, uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_asset_path(uuid) FROM PUBLIC, anon, authenticated;

-- Trigger functions (5) — se disparan solas vía CREATE TRIGGER, nunca por
-- rol; no reciben GRANT en ninguna de sus migraciones originales, así que
-- este REVOKE explícito cierra únicamente el acceso heredado por default.
REVOKE ALL ON FUNCTION public.add_chat_participants_on_assignment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_quote_status_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_internal_request_created() FROM PUBLIC, anon, authenticated;
-- lock_request_type_after_submission (20260831090000_request_type_integrity.sql,
-- esta misma fase): trigger de integridad de request_type, no una RPC —
-- mismo tratamiento que los cuatro anteriores.
REVOKE ALL ON FUNCTION public.lock_request_type_after_submission() FROM PUBLIC, anon, authenticated;

-- has_role — legacy, previa al sistema multi-tenant, reemplazada
-- funcionalmente por has_organization_role. Confirmado sin ninguna
-- llamada .rpc('has_role', ...) en el frontend (src/). No se elimina en
-- esta fase (fuera de alcance: tocaría además profiles/user_roles/
-- app_role); se trata como helper legacy sin acceso directo.
REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- 3) RPC de cara al frontend (64) — anon ya quedó sin acceso por el bloque
--    1. Se reafirma explícitamente el GRANT a authenticated (ya existente
--    desde la migración original de cada función; GRANT es idempotente,
--    no falla si ya estaba otorgado) para dejar esta migración como la
--    fuente de verdad auditable de "estas son las RPC que sí deben quedar
--    accesibles a authenticated".
-- =========================================================================
GRANT EXECUTE ON FUNCTION public.is_organization_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_organization_role(uuid, public.organization_member_role[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_organizations() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_provider_facing_organization(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_manage_request_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_read_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_provider_quote_request(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_read_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_quote(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_work_order_from_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_work_order_technician(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_assignable_technicians(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_internal_work_order_from_request(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_caller_planner_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_assignable_planners(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_work_order_operations(uuid, uuid, uuid, timestamptz, timestamptz, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_work_order_activities(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_work_order_activity(uuid, text, uuid, numeric, timestamptz, text, integer, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_work_order_activity(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_catalog(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_warehouse(uuid, text, uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_material(uuid, uuid, text, text, text, uuid, numeric, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_work_order_materials(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_work_order_material(uuid, uuid, uuid, numeric, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_work_order_material(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_technician_work_orders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.technician_update_work_order_progress(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_work_order_work_logs(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_activity_report_form_data(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_activity_report(uuid, timestamptz, timestamptz, text, text, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_activity_reports_for_work_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_asset_integrated_history(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_operational_due_notifications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_efficiency_activity_metrics(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_efficiency_summary(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_criticality_matrix(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_criticality_parameter(uuid, text, text, numeric, integer, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_criticality_option(uuid, text, numeric, integer, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_criticality_parameter_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_criticality_option_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_asset_criticality(uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_asset_criticality_assessments(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_checklist_templates(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_checklist_template(uuid, text, text, text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_checklist_template_item(uuid, text, text, text, integer, boolean, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_checklist_template_item_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_checklist_response_option(uuid, text, text, numeric, boolean, integer, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_checklist_response_option_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_inspection_plan(uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, date, timestamptz, uuid, boolean, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inspection_plans(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inspection_runs(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_inspection_run_from_plan(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inspection_run_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_inspection_run(uuid, timestamptz, timestamptz, jsonb, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_inspection_due_notifications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inspection_plan_alert_rules(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_inspection_plan_alert_rule(uuid, text, integer, text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_inspection_plan_alert_rule_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_inspection_plan_alert_rules(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_asset_traffic_light(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_branch_traffic_light(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dashboard_metrics(uuid) TO authenticated;

-- =========================================================================
-- map_request_priority_to_work_order_priority — no es SECURITY DEFINER
-- (corre como SECURITY INVOKER, sin riesgo de escalación de privilegios),
-- pero el Advisor la marca por su search_path mutable, y no tiene ningún
-- uso legítimo como RPC directa (sin .rpc('map_request_priority_to_work_
-- order_priority', ...) en el frontend; solo la llaman internamente
-- update_work_order_operations, create_work_order_from_quote y
-- create_internal_work_order_from_request). Se trata como helper interno:
-- se agrega SET search_path = public y se revoca de PUBLIC, anon y
-- authenticated.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.map_request_priority_to_work_order_priority(request_priority integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN request_priority = 1 THEN 'urgent'
    WHEN request_priority = 2 THEN 'high'
    WHEN request_priority = 3 THEN 'medium'
    WHEN request_priority = 4 THEN 'low'
    ELSE 'medium'
  END;
$$;

REVOKE ALL ON FUNCTION public.map_request_priority_to_work_order_priority(integer) FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- 4) Causa raíz futura: toda función nueva creada por postgres en public
--    deja de heredar EXECUTE para PUBLIC/anon/authenticated
--    automáticamente. Confirmado: las funciones más recientes
--    (get_dashboard_metrics, get_asset_traffic_light,
--    create_internal_work_order_from_request, create_work_order_from_quote)
--    también son propiedad de postgres, así que esto aplica al rol
--    correcto del proyecto. Dos sentencias separadas — PUBLIC primero,
--    igual que el bloque 1, para no depender de que anon/authenticated
--    nunca hereden un privilegio por defecto de PUBLIC otra vez. No toca
--    defaults de tablas ni secuencias, y no toca service_role — cada RPC
--    nueva deberá seguir trayendo su propio GRANT EXECUTE ... TO
--    authenticated explícito, exactamente como ya lo hace cada migración
--    existente de este repo.
-- =========================================================================
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
