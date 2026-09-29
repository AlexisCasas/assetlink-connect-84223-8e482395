-- Fase 1 · Punto 9C.2 — acceso operativo de Facility Manager a Inspecciones
-- + Mantenimiento preventivo (…_facility_manager_inspections_preventive_access.sql).
-- Se ejecuta con: supabase test db --local
--
-- Cada intento corre como `authenticated` con un auth.uid() sintético.
-- Errores: P0001 = las RPCs rechazan con RAISE sin código propio (regla
-- histórica conservada); 42501 = reglas nuevas del modo delegado
-- (responsable del cliente, inventario, directorios mínimos).
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(242);

-- -------------------------------------------------------------------------
-- Fixture (sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('b9100000-0000-0000-0000-000000000001', 'ca-owner@fm-insp.test', '{"name":"Olga Cliente"}'),
  ('b9100000-0000-0000-0000-000000000002', 'ca-manager@fm-insp.test', '{"name":"Mario Cliente"}'),
  ('b9100000-0000-0000-0000-000000000003', 'ca-technician@fm-insp.test', '{"name":"Tomas Cliente"}'),
  ('b9100000-0000-0000-0000-000000000004', 'fa-owner@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-000000000005', 'fa-admin@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-000000000006', 'fa-manager@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-000000000007', 'fa-technician@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-000000000008', 'fa-viewer@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-000000000009', 'fb-manager@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-00000000000a', 'outsider@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-00000000000b', 'platform@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-00000000000c', 'fa-manager-unassigned@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-00000000000d', 'cb-owner@fm-insp.test', '{}'),
  ('b9100000-0000-0000-0000-00000000000e', 'fa-technician-inactive@fm-insp.test', '{}'),
  -- Responsable del cliente SIN nombre: el fallback histórico usa el email.
  ('b9100000-0000-0000-0000-00000000000f', 'ca-noname@fm-insp.test', '{}');

INSERT INTO public.organizations (id, name, organization_type) VALUES
  ('b9200000-0000-0000-0000-0000000000a1', 'Client A', 'client_company'),
  ('b9200000-0000-0000-0000-0000000000b1', 'Client B', 'client_company'),
  ('b9200000-0000-0000-0000-0000000000c1', 'Client C (solo view)', 'client_company'),
  ('b9200000-0000-0000-0000-0000000000d1', 'Client D (manage sin view)', 'client_company'),
  ('b9200000-0000-0000-0000-0000000000e1', 'Client E (suspendida)', 'client_company'),
  ('b9200000-0000-0000-0000-0000000000f1', 'Client F (sin permisos 9C.2)', 'client_company'),
  ('b9200000-0000-0000-0000-0000000000fa', 'FM A', 'facility_manager'),
  ('b9200000-0000-0000-0000-0000000000fb', 'FM B', 'facility_manager'),
  ('b9200000-0000-0000-0000-0000000000ee', 'Plataforma 9C2', 'platform_admin');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('b9300000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-0000000000a1', 'b9100000-0000-0000-0000-000000000001', 'owner', true),
  ('b9300000-0000-0000-0000-000000000002', 'b9200000-0000-0000-0000-0000000000a1', 'b9100000-0000-0000-0000-000000000002', 'manager', true),
  ('b9300000-0000-0000-0000-000000000003', 'b9200000-0000-0000-0000-0000000000a1', 'b9100000-0000-0000-0000-000000000003', 'technician', true),
  ('b9300000-0000-0000-0000-000000000004', 'b9200000-0000-0000-0000-0000000000fa', 'b9100000-0000-0000-0000-000000000004', 'owner', true),
  ('b9300000-0000-0000-0000-000000000005', 'b9200000-0000-0000-0000-0000000000fa', 'b9100000-0000-0000-0000-000000000005', 'admin', true),
  ('b9300000-0000-0000-0000-000000000006', 'b9200000-0000-0000-0000-0000000000fa', 'b9100000-0000-0000-0000-000000000006', 'manager', true),
  ('b9300000-0000-0000-0000-000000000007', 'b9200000-0000-0000-0000-0000000000fa', 'b9100000-0000-0000-0000-000000000007', 'technician', true),
  ('b9300000-0000-0000-0000-000000000008', 'b9200000-0000-0000-0000-0000000000fa', 'b9100000-0000-0000-0000-000000000008', 'viewer', true),
  ('b9300000-0000-0000-0000-000000000009', 'b9200000-0000-0000-0000-0000000000fb', 'b9100000-0000-0000-0000-000000000009', 'manager', true),
  ('b9300000-0000-0000-0000-00000000000b', 'b9200000-0000-0000-0000-0000000000ee', 'b9100000-0000-0000-0000-00000000000b', 'owner', true),
  ('b9300000-0000-0000-0000-00000000000c', 'b9200000-0000-0000-0000-0000000000fa', 'b9100000-0000-0000-0000-00000000000c', 'manager', true),
  ('b9300000-0000-0000-0000-00000000000d', 'b9200000-0000-0000-0000-0000000000b1', 'b9100000-0000-0000-0000-00000000000d', 'owner', true),
  ('b9300000-0000-0000-0000-00000000000e', 'b9200000-0000-0000-0000-0000000000fa', 'b9100000-0000-0000-0000-00000000000e', 'technician', true),
  ('b9300000-0000-0000-0000-00000000000f', 'b9200000-0000-0000-0000-0000000000a1', 'b9100000-0000-0000-0000-00000000000f', 'manager', true);

INSERT INTO public.client_branches (id, organization_id, client_email, name, city, site, address, is_active) VALUES
  ('b9600000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'secret@client-a.test', 'Sede A', 'Lima', 'S1', 'Av. A 1', true),
  ('b9600000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'secret@client-b.test', 'Sede B', 'Lima', 'S1', 'Av. B 1', true),
  ('b9600000-0000-0000-0000-0000000000a2', 'b9200000-0000-0000-0000-0000000000a1', 'secret2@client-a.test', 'Sede A2 inactiva', 'Lima', 'S2', 'Av. A 2', false);

INSERT INTO public.assets (id, organization_id, code, name, node_type, branch_id, status, metadata, technical_data) VALUES
  ('b9400000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'A-1', 'Bomba A1', 'equipment', 'b9600000-0000-0000-0000-0000000000a1', 'active', '{"secret":"meta"}', '{"secret":"tech"}'),
  ('b9400000-0000-0000-0000-0000000000a2', 'b9200000-0000-0000-0000-0000000000a1', 'A-2', 'Tablero A2', 'equipment', NULL, 'active', '{}', '{}'),
  ('b9400000-0000-0000-0000-0000000000a9', 'b9200000-0000-0000-0000-0000000000a1', 'A-9', 'Archivado A9', 'equipment', NULL, 'archived', '{}', '{}'),
  ('b9400000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'B-1', 'Bomba B1', 'equipment', NULL, 'active', '{}', '{}'),
  ('b9400000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-0000000000c1', 'C-1', 'Bomba C1', 'equipment', NULL, 'active', '{}', '{}'),
  ('b9400000-0000-0000-0000-0000000000d1', 'b9200000-0000-0000-0000-0000000000d1', 'D-1', 'Bomba D1', 'equipment', NULL, 'active', '{}', '{}');

-- Relaciones: nacen pending, se configuran y se activan (como las RPCs 9A).
INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status) VALUES
  ('b9700000-0000-0000-0000-0000000000aa', 'b9200000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('b9700000-0000-0000-0000-0000000000bb', 'b9200000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000fb', 'facility_management', 'pending'),
  ('b9700000-0000-0000-0000-0000000000ca', 'b9200000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('b9700000-0000-0000-0000-0000000000da', 'b9200000-0000-0000-0000-0000000000d1', 'b9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('b9700000-0000-0000-0000-0000000000ea', 'b9200000-0000-0000-0000-0000000000e1', 'b9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('b9700000-0000-0000-0000-0000000000fa', 'b9200000-0000-0000-0000-0000000000f1', 'b9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending');
INSERT INTO public.facility_management_permissions (relationship_id, permission) VALUES
  ('b9700000-0000-0000-0000-0000000000aa', 'inspections.view'), ('b9700000-0000-0000-0000-0000000000aa', 'inspections.manage'),
  ('b9700000-0000-0000-0000-0000000000aa', 'preventive_maintenance.view'), ('b9700000-0000-0000-0000-0000000000aa', 'preventive_maintenance.manage'),
  ('b9700000-0000-0000-0000-0000000000bb', 'inspections.view'), ('b9700000-0000-0000-0000-0000000000bb', 'inspections.manage'),
  ('b9700000-0000-0000-0000-0000000000bb', 'preventive_maintenance.view'), ('b9700000-0000-0000-0000-0000000000bb', 'preventive_maintenance.manage'),
  ('b9700000-0000-0000-0000-0000000000ca', 'inspections.view'), ('b9700000-0000-0000-0000-0000000000ca', 'preventive_maintenance.view'),
  ('b9700000-0000-0000-0000-0000000000da', 'inspections.manage'), ('b9700000-0000-0000-0000-0000000000da', 'preventive_maintenance.manage'),
  ('b9700000-0000-0000-0000-0000000000ea', 'inspections.view'), ('b9700000-0000-0000-0000-0000000000ea', 'inspections.manage'),
  ('b9700000-0000-0000-0000-0000000000ea', 'preventive_maintenance.view'), ('b9700000-0000-0000-0000-0000000000ea', 'preventive_maintenance.manage'),
  ('b9700000-0000-0000-0000-0000000000fa', 'assets.view');
INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES
  ('b9700000-0000-0000-0000-0000000000aa', 'b9300000-0000-0000-0000-000000000004'),
  ('b9700000-0000-0000-0000-0000000000aa', 'b9300000-0000-0000-0000-000000000005'),
  ('b9700000-0000-0000-0000-0000000000aa', 'b9300000-0000-0000-0000-000000000006'),
  ('b9700000-0000-0000-0000-0000000000aa', 'b9300000-0000-0000-0000-000000000007'),
  ('b9700000-0000-0000-0000-0000000000aa', 'b9300000-0000-0000-0000-000000000008'),
  ('b9700000-0000-0000-0000-0000000000aa', 'b9300000-0000-0000-0000-00000000000e'),
  ('b9700000-0000-0000-0000-0000000000bb', 'b9300000-0000-0000-0000-000000000009'),
  ('b9700000-0000-0000-0000-0000000000ca', 'b9300000-0000-0000-0000-000000000006'),
  ('b9700000-0000-0000-0000-0000000000ca', 'b9300000-0000-0000-0000-000000000007'),
  ('b9700000-0000-0000-0000-0000000000da', 'b9300000-0000-0000-0000-000000000006'),
  ('b9700000-0000-0000-0000-0000000000da', 'b9300000-0000-0000-0000-000000000007'),
  ('b9700000-0000-0000-0000-0000000000ea', 'b9300000-0000-0000-0000-000000000006'),
  ('b9700000-0000-0000-0000-0000000000fa', 'b9300000-0000-0000-0000-000000000006');
UPDATE public.organization_relationships SET status = 'active' WHERE id::text LIKE 'b9700000-%';
UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'b9700000-0000-0000-0000-0000000000ea';
UPDATE public.organization_members SET is_active = false WHERE id = 'b9300000-0000-0000-0000-00000000000e';

-- Inspecciones -------------------------------------------------------------
INSERT INTO public.checklist_templates (id, organization_id, name) VALUES
  ('b9800000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'Plantilla A'),
  ('b9800000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'Plantilla B'),
  ('b9800000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-0000000000c1', 'Plantilla C'),
  ('b9800000-0000-0000-0000-0000000000d1', 'b9200000-0000-0000-0000-0000000000d1', 'Plantilla D');
INSERT INTO public.checklist_template_items (id, template_id, question, sequence, is_required) VALUES
  ('b9810000-0000-0000-0000-0000000000a1', 'b9800000-0000-0000-0000-0000000000a1', '¿Funciona A?', 1, true),
  ('b9810000-0000-0000-0000-0000000000b1', 'b9800000-0000-0000-0000-0000000000b1', '¿Funciona B?', 1, true),
  ('b9810000-0000-0000-0000-0000000000c1', 'b9800000-0000-0000-0000-0000000000c1', '¿Funciona C?', 1, true);
INSERT INTO public.checklist_template_response_options (id, template_id, label, value, sequence) VALUES
  ('b9820000-0000-0000-0000-0000000000a1', 'b9800000-0000-0000-0000-0000000000a1', 'Cumple', 'ok', 1),
  ('b9820000-0000-0000-0000-0000000000b1', 'b9800000-0000-0000-0000-0000000000b1', 'Cumple', 'ok', 1),
  ('b9820000-0000-0000-0000-0000000000c1', 'b9800000-0000-0000-0000-0000000000c1', 'Cumple', 'ok', 1);
INSERT INTO public.inspection_plans (id, organization_id, template_id, asset_id, responsible_member_id, title, frequency, next_due_at) VALUES
  ('b9830000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'b9800000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a1', 'b9300000-0000-0000-0000-000000000003', 'Plan A (responsable cliente)', 'monthly', now() + interval '10 days'),
  ('b9830000-0000-0000-0000-0000000000a0', 'b9200000-0000-0000-0000-0000000000a1', 'b9800000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a2', NULL, 'Plan A0 (sin responsable)', 'monthly', now() + interval '5 days'),
  ('b9830000-0000-0000-0000-0000000000a3', 'b9200000-0000-0000-0000-0000000000a1', 'b9800000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a2', 'b9300000-0000-0000-0000-00000000000f', 'Plan A3 (responsable sin nombre)', 'monthly', now() + interval '15 days'),
  ('b9830000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'b9800000-0000-0000-0000-0000000000b1', 'b9400000-0000-0000-0000-0000000000b1', NULL, 'Plan B', 'monthly', now() + interval '10 days'),
  ('b9830000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-0000000000c1', 'b9800000-0000-0000-0000-0000000000c1', 'b9400000-0000-0000-0000-0000000000c1', NULL, 'Plan C', 'monthly', now() + interval '10 days'),
  ('b9830000-0000-0000-0000-0000000000d1', 'b9200000-0000-0000-0000-0000000000d1', 'b9800000-0000-0000-0000-0000000000d1', 'b9400000-0000-0000-0000-0000000000d1', NULL, 'Plan D', 'monthly', now() + interval '10 days');
-- Plan histórico: sede inactiva + activo archivado (ya no están en el directorio mínimo).
INSERT INTO public.inspection_plans (id, organization_id, template_id, branch_id, asset_id, title, frequency, next_due_at) VALUES
  ('b9830000-0000-0000-0000-0000000000a4', 'b9200000-0000-0000-0000-0000000000a1', 'b9800000-0000-0000-0000-0000000000a1', 'b9600000-0000-0000-0000-0000000000a2', 'b9400000-0000-0000-0000-0000000000a9', 'Plan histórico', 'monthly', now() + interval '20 days');
INSERT INTO public.inspection_plan_alert_rules (id, plan_id, organization_id, alert_type, days_before) VALUES
  ('b9840000-0000-0000-0000-0000000000a1', 'b9830000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'before_due', 30),
  ('b9840000-0000-0000-0000-0000000000b1', 'b9830000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'before_due', 30);
INSERT INTO public.inspection_runs (id, organization_id, plan_id, template_id, asset_id, responsible_member_id, scheduled_for, status) VALUES
  ('b9850000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'b9830000-0000-0000-0000-0000000000a1', 'b9800000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a1', 'b9300000-0000-0000-0000-000000000003', now(), 'scheduled'),
  ('b9850000-0000-0000-0000-0000000000a2', 'b9200000-0000-0000-0000-0000000000a1', 'b9830000-0000-0000-0000-0000000000a0', 'b9800000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a2', NULL, now(), 'scheduled'),
  ('b9850000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'b9830000-0000-0000-0000-0000000000b1', 'b9800000-0000-0000-0000-0000000000b1', 'b9400000-0000-0000-0000-0000000000b1', NULL, now(), 'scheduled'),
  ('b9850000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-0000000000c1', 'b9830000-0000-0000-0000-0000000000c1', 'b9800000-0000-0000-0000-0000000000c1', 'b9400000-0000-0000-0000-0000000000c1', NULL, now(), 'scheduled');
INSERT INTO public.inspection_runs (id, organization_id, plan_id, template_id, asset_id, responsible_member_id, scheduled_for, started_at, completed_at, status, result) VALUES
  ('b9850000-0000-0000-0000-0000000000a3', 'b9200000-0000-0000-0000-0000000000a1', 'b9830000-0000-0000-0000-0000000000a3', 'b9800000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a2', 'b9300000-0000-0000-0000-00000000000f', now() - interval '2 days', now() - interval '2 days', now() - interval '2 days', 'completed', 'passed');

-- Preventivo ---------------------------------------------------------------
INSERT INTO public.warehouses (id, organization_id, name) VALUES
  ('b9860000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'Almacén A');
INSERT INTO public.materials (id, organization_id, warehouse_id, code, name, unit, stock) VALUES
  ('b9870000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'b9860000-0000-0000-0000-0000000000a1', 'MAT-A', 'Filtro secreto', 'und', 25);
INSERT INTO public.maintenance_cards (id, organization_id, code, name) VALUES
  ('b9880000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'KA', 'Ficha A'),
  ('b9880000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'KB', 'Ficha B');
INSERT INTO public.maintenance_card_tasks (card_id, sequence, title) VALUES
  ('b9880000-0000-0000-0000-0000000000a1', 1, 'Revisar'), ('b9880000-0000-0000-0000-0000000000b1', 1, 'Revisar');
INSERT INTO public.maintenance_card_materials (id, card_id, sequence, material_id, description, quantity, unit) VALUES
  ('b9890000-0000-0000-0000-0000000000a1', 'b9880000-0000-0000-0000-0000000000a1', 1, 'b9870000-0000-0000-0000-0000000000a1', 'Filtro del catálogo', 2, 'und'),
  ('b9890000-0000-0000-0000-0000000000a2', 'b9880000-0000-0000-0000-0000000000a1', 2, NULL, 'Trapo industrial', 1, 'und');
INSERT INTO public.asset_meters (id, organization_id, asset_id, name, unit) VALUES
  ('b98a0000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a1', 'Horómetro A', 'h'),
  ('b98a0000-0000-0000-0000-0000000000a2', 'b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a1', 'Horómetro A (retirar)', 'h'),
  ('b98a0000-0000-0000-0000-0000000000a3', 'b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a1', 'Horómetro A (reemplazar)', 'h'),
  ('b98a0000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'b9400000-0000-0000-0000-0000000000b1', 'Horómetro B', 'h'),
  ('b98a0000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-0000000000c1', 'b9400000-0000-0000-0000-0000000000c1', 'Horómetro C', 'h'),
  ('b98a0000-0000-0000-0000-0000000000d1', 'b9200000-0000-0000-0000-0000000000d1', 'b9400000-0000-0000-0000-0000000000d1', 'Horómetro D', 'h');
INSERT INTO public.asset_meter_readings (id, meter_id, value, recorded_at) VALUES
  ('b98b0000-0000-0000-0000-0000000000a1', 'b98a0000-0000-0000-0000-0000000000a1', 100, now() - interval '2 days'),
  ('b98b0000-0000-0000-0000-0000000000b1', 'b98a0000-0000-0000-0000-0000000000b1', 100, now() - interval '2 days'),
  ('b98b0000-0000-0000-0000-0000000000c1', 'b98a0000-0000-0000-0000-0000000000c1', 100, now() - interval '2 days');
INSERT INTO public.preventive_maintenance_plans (id, organization_id, asset_id, card_id, trigger_type, responsible_member_id, frequency, first_due_at) VALUES
  ('b98c0000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a1', 'b9880000-0000-0000-0000-0000000000a1', 'calendar', 'b9300000-0000-0000-0000-000000000002', 'monthly', now() + interval '20 days'),
  ('b98c0000-0000-0000-0000-0000000000b1', 'b9200000-0000-0000-0000-0000000000b1', 'b9400000-0000-0000-0000-0000000000b1', 'b9880000-0000-0000-0000-0000000000b1', 'calendar', NULL, 'monthly', now() + interval '20 days');
SELECT public.create_preventive_occurrence_locked('b98c0000-0000-0000-0000-0000000000a1', now() + interval '20 days', NULL);
SELECT public.create_preventive_occurrence_locked('b98c0000-0000-0000-0000-0000000000b1', now() + interval '20 days', NULL);
-- Ocurrencia ya planificada: enlazada a una Solicitud y una OT reales del
-- cliente (módulos NO delegados en 9C.2); su responsable no tiene nombre.
INSERT INTO public.preventive_maintenance_plans (id, organization_id, asset_id, card_id, trigger_type, responsible_member_id, frequency, first_due_at) VALUES
  ('b98c0000-0000-0000-0000-0000000000a2', 'b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a2', 'b9880000-0000-0000-0000-0000000000a1', 'calendar', 'b9300000-0000-0000-0000-00000000000f', 'monthly', now() + interval '25 days');
SELECT public.create_preventive_occurrence_locked('b98c0000-0000-0000-0000-0000000000a2', now() + interval '25 days', NULL);
INSERT INTO public.requests (id, organization_id, request_number, description, asset, location, service_type, deadline, created_by) VALUES
  ('b98e0000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'REQ-9C2-A', 'Preventivo', 'Tablero A2', 'Sede A', 'preventivo', now() + interval '25 days', 'fixture');
INSERT INTO public.work_orders (id, request_id, client_organization_id, provider_organization_id, work_order_number, work_order_type) VALUES
  ('b98f0000-0000-0000-0000-0000000000a1', 'b98e0000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'b9200000-0000-0000-0000-0000000000a1', 'OT-9C2-A', 'internal');
-- Ids fijos para poder referirlos como authenticated (sin RLS de lectura).
UPDATE public.preventive_maintenance_occurrences SET id = 'b98d0000-0000-0000-0000-0000000000a1' WHERE plan_id = 'b98c0000-0000-0000-0000-0000000000a1';
UPDATE public.preventive_maintenance_occurrences SET id = 'b98d0000-0000-0000-0000-0000000000b1' WHERE plan_id = 'b98c0000-0000-0000-0000-0000000000b1';
UPDATE public.preventive_maintenance_occurrences
SET id = 'b98d0000-0000-0000-0000-0000000000a2', status = 'planned', request_id = 'b98e0000-0000-0000-0000-0000000000a1',
    work_order_id = 'b98f0000-0000-0000-0000-0000000000a1', planned_at = now()
WHERE plan_id = 'b98c0000-0000-0000-0000-0000000000a2';

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
$$;
CREATE FUNCTION pg_temp.keys(p jsonb) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(array_agg(k ORDER BY k), ARRAY[]::text[]) FROM jsonb_object_keys(p) k;
$$;
CREATE FUNCTION pg_temp.card_materials(p_org uuid, p_code text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT c->'materials' FROM jsonb_array_elements(public.get_maintenance_cards(p_org, true)) c WHERE c->>'code' = p_code;
$$;

-- Payloads reutilizados.
CREATE FUNCTION pg_temp.answers_a() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '[{"template_item_id":"b9810000-0000-0000-0000-0000000000a1","response_option_id":"b9820000-0000-0000-0000-0000000000a1"}]'::jsonb;
$$;

-- -------------------------------------------------------------------------
-- 0. Estructura y grants
-- -------------------------------------------------------------------------
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_view_inspections(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_view_inspections(uuid)', 'EXECUTE'),
  'can_view_inspections: internal (no EXECUTE for authenticated/anon)');
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_plan_inspections(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_plan_inspections(uuid)', 'EXECUTE'),
  'can_plan_inspections: internal');
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_execute_inspections_as_facility_manager(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_execute_inspections_as_facility_manager(uuid)', 'EXECUTE'),
  'can_execute_inspections_as_facility_manager: internal');
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_view_preventive_maintenance(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_view_preventive_maintenance(uuid)', 'EXECUTE'),
  'can_view_preventive_maintenance: internal');
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_plan_preventive_maintenance(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_plan_preventive_maintenance(uuid)', 'EXECUTE'),
  'can_plan_preventive_maintenance: internal');
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_record_preventive_meter_reading(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_record_preventive_meter_reading(uuid)', 'EXECUTE'),
  'can_record_preventive_meter_reading: internal');
SELECT ok(NOT has_function_privilege('authenticated', 'public.sanitize_preventive_scope_snapshot(jsonb)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.sanitize_preventive_scope_snapshot(jsonb)', 'EXECUTE'),
  'sanitize_preventive_scope_snapshot: internal');
SELECT ok(has_function_privilege('authenticated', 'public.get_facility_management_inspection_targets(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.get_facility_management_inspection_targets(uuid)', 'EXECUTE'),
  'get_facility_management_inspection_targets: authenticated only, never anon');
SELECT ok(has_function_privilege('authenticated', 'public.get_facility_management_preventive_assets(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.get_facility_management_preventive_assets(uuid)', 'EXECUTE'),
  'get_facility_management_preventive_assets: authenticated only, never anon');

-- Las 30 RPCs reemplazadas conservan SECURITY DEFINER, EXECUTE para
-- authenticated y ninguno para anon/PUBLIC.
CREATE FUNCTION pg_temp.replaced_rpcs() RETURNS regprocedure[] LANGUAGE sql AS $$
  SELECT ARRAY[
    'public.get_checklist_templates(uuid,boolean)', 'public.get_inspection_plans(uuid,boolean)',
    'public.get_inspection_runs(uuid,text)', 'public.get_inspection_plan_alert_rules(uuid)',
    'public.get_inspection_run_detail(uuid)', 'public.upsert_checklist_template(uuid,text,text,text,uuid,boolean)',
    'public.upsert_checklist_template_item(uuid,text,text,text,integer,boolean,uuid,boolean)',
    'public.set_checklist_template_item_active(uuid,boolean)',
    'public.upsert_checklist_response_option(uuid,text,text,numeric,boolean,integer,uuid,boolean)',
    'public.set_checklist_response_option_active(uuid,boolean)', 'public.replace_inspection_plan_alert_rules(uuid,jsonb)',
    'public.upsert_inspection_plan_alert_rule(uuid,text,integer,text,uuid,boolean)',
    'public.set_inspection_plan_alert_rule_active(uuid,boolean)',
    'public.upsert_inspection_plan(uuid,uuid,text,uuid,uuid,uuid,uuid,text,text,date,timestamp with time zone,uuid,boolean,integer,text)',
    'public.create_inspection_run_from_plan(uuid)',
    'public.submit_inspection_run(uuid,timestamp with time zone,timestamp with time zone,jsonb,jsonb,text)',
    'public.get_maintenance_cards(uuid,boolean)', 'public.get_preventive_maintenance_plans(uuid)',
    'public.get_preventive_maintenance_occurrences(uuid,uuid,text)', 'public.get_asset_meters(uuid,boolean)',
    'public.set_maintenance_card_active(uuid,boolean)', 'public.set_preventive_maintenance_plan_active(uuid,boolean,text)',
    'public.skip_preventive_maintenance_occurrence(uuid,text)',
    'public.create_asset_meter(uuid,uuid,text,text,numeric,timestamp with time zone,text)',
    'public.correct_asset_meter_reading(uuid,numeric,text,text)', 'public.retire_asset_meter(uuid,text)',
    'public.replace_asset_meter(uuid,text,text,numeric,timestamp with time zone,text,text)',
    'public.save_maintenance_card(uuid,text,text,text,text,numeric,text,text,jsonb,jsonb,uuid)',
    'public.save_preventive_maintenance_plan(uuid,uuid,uuid,text,text,text,uuid,integer,text,integer,text,timestamp with time zone,uuid,numeric,uuid,numeric,uuid)',
    'public.record_asset_meter_reading(uuid,numeric,timestamp with time zone,text)'
  ]::regprocedure[];
$$;
SELECT is(cardinality(pg_temp.replaced_rpcs()), 30, 'structure: 30 replaced RPCs are tracked');
SELECT ok((SELECT bool_and(p.prosecdef) FROM pg_proc p WHERE p.oid = ANY (pg_temp.replaced_rpcs())),
  'structure: every replaced RPC is still SECURITY DEFINER');
SELECT ok((SELECT bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
           FROM pg_proc p WHERE p.oid = ANY (pg_temp.replaced_rpcs())),
  'structure: every replaced RPC keeps authenticated EXECUTE and no anon/PUBLIC');
SELECT ok((SELECT bool_and(p.proconfig IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
           FROM pg_proc p WHERE p.oid = ANY (pg_temp.replaced_rpcs())),
  'structure: every replaced RPC keeps a pinned search_path');
SELECT ok((SELECT prosrc ~ 'can_manage_preventive_maintenance\(' AND prosrc !~ 'can_plan_preventive_maintenance'
           FROM pg_proc WHERE oid = 'public.plan_preventive_maintenance_occurrence(uuid,uuid)'::regprocedure),
  'request isolation: plan_preventive_maintenance_occurrence still uses the direct-only helper');
SELECT ok((SELECT prosrc !~ 'facility_management' FROM pg_proc WHERE oid = 'public.can_manage_preventive_maintenance(uuid)'::regprocedure)
      AND (SELECT prosrc !~ 'facility_management' FROM pg_proc WHERE oid = 'public.can_record_asset_meter_reading(uuid)'::regprocedure),
  'direct preventive helpers are unchanged (no delegated branch)');
SELECT ok((SELECT bool_and(prosrc !~ 'facility_management') FROM pg_proc
           WHERE oid IN ('public.get_assignable_technicians(uuid)'::regprocedure, 'public.get_assignable_planners(uuid)'::regprocedure,
                         'public.get_inventory_catalog(uuid)'::regprocedure)),
  'client roster and inventory RPCs are not extended to Facility Managers');
SELECT is(
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
     AND (has_table_privilege('anon', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
       OR has_table_privilege('authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))),
  0::bigint, '9C.1H preserved: no meta privileges for anon/authenticated on public tables');

SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 1. Inspecciones — VER (inspections.view, owner/admin/manager/technician)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000004');
SELECT is(jsonb_array_length(public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true)), 1, 'insp view: FM owner reads Client A templates');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000005');
SELECT is(jsonb_array_length(public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true)), 1, 'insp view: FM admin reads Client A templates');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT is(jsonb_array_length(public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true)), 1, 'insp view: FM manager reads Client A templates');
SELECT is((SELECT count(*) FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000a1', true)), 4::bigint, 'insp view: FM manager reads Client A plans');
SELECT is((SELECT count(*) FROM public.get_inspection_runs('b9200000-0000-0000-0000-0000000000a1', NULL)), 3::bigint, 'insp view: FM manager reads Client A runs');
SELECT is((SELECT count(*) FROM public.get_inspection_plan_alert_rules('b9830000-0000-0000-0000-0000000000a1')), 1::bigint, 'insp view: FM manager reads Client A alert rules');
SELECT is((SELECT responsible_name FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000a1', true) WHERE id = 'b9830000-0000-0000-0000-0000000000a1'),
  'Tomas Cliente', 'insp view: the plan already carries the client-assigned responsible name (no roster needed)');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000007');
SELECT is(jsonb_array_length(public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true)), 1, 'insp view: FM technician reads Client A templates');
SELECT is(public.get_inspection_run_detail('b9850000-0000-0000-0000-0000000000a1')->>'id', 'b9850000-0000-0000-0000-0000000000a1', 'insp view: FM technician reads a Client A run detail');

SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000008');
SELECT throws_ok($$ SELECT public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'insp view: FM viewer is rejected');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000c');
SELECT throws_ok($$ SELECT * FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'insp view: FM manager not assigned to the relationship is rejected');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000e');
SELECT throws_ok($$ SELECT * FROM public.get_inspection_runs('b9200000-0000-0000-0000-0000000000a1', NULL) $$, 'P0001', NULL, 'insp view: inactive FM membership is rejected');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000009');
SELECT throws_ok($$ SELECT public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'insp view: FM B cannot read Client A');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT public.get_checklist_templates('b9200000-0000-0000-0000-0000000000b1', true) $$, 'P0001', NULL, 'insp view: FM A manager cannot read Client B');
SELECT throws_ok($$ SELECT public.get_inspection_run_detail('b9850000-0000-0000-0000-0000000000b1') $$, 'P0001', NULL, 'insp view: a Client B run id cannot be opened');
SELECT throws_ok($$ SELECT * FROM public.get_inspection_plan_alert_rules('b9830000-0000-0000-0000-0000000000b1') $$, 'P0001', NULL, 'insp view: Client B alert rules stay closed');
SELECT throws_ok($$ SELECT public.get_checklist_templates('b9200000-0000-0000-0000-0000000000f1', true) $$, 'P0001', NULL, 'insp view: no inspections.view permission => rejected');
SELECT throws_ok($$ SELECT public.get_checklist_templates('b9200000-0000-0000-0000-0000000000e1', true) $$, 'P0001', NULL, 'insp view: suspended relationship => rejected');
SELECT throws_ok($$ SELECT * FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000d1', true) $$, 'P0001', NULL, 'insp view: inspections.manage without view => rejected');
SELECT is((SELECT count(*) FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000c1', true)), 1::bigint, 'insp view: view-only relationship reads plans');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000a');
SELECT throws_ok($$ SELECT public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'insp view: outsider is rejected');

-- -------------------------------------------------------------------------
-- 2. Inspecciones — PLANIFICAR (view + manage, owner/admin/manager)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000004');
SELECT lives_ok($$ SELECT public.upsert_checklist_template('b9200000-0000-0000-0000-0000000000a1', 'Plantilla FM owner') $$, 'insp plan: FM owner creates a template');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000005');
SELECT lives_ok($$ SELECT public.upsert_checklist_template_item('b9800000-0000-0000-0000-0000000000a1', '¿Pregunta del admin FM?', NULL, NULL, 2, false) $$, 'insp plan: FM admin adds a template item');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT lives_ok($$ SELECT public.upsert_checklist_template('b9200000-0000-0000-0000-0000000000a1', 'Plantilla A editada', NULL, NULL, 'b9800000-0000-0000-0000-0000000000a1') $$, 'insp plan: FM manager edits a template');
SELECT lives_ok($$ SELECT public.set_checklist_template_item_active('b9810000-0000-0000-0000-0000000000a1', true) $$, 'insp plan: FM manager toggles an item');
SELECT lives_ok($$ SELECT public.upsert_checklist_response_option('b9800000-0000-0000-0000-0000000000a1', 'No cumple', 'fail', NULL, true, 2) $$, 'insp plan: FM manager adds a response option');
SELECT lives_ok($$ SELECT public.set_checklist_response_option_active('b9820000-0000-0000-0000-0000000000a1', true) $$, 'insp plan: FM manager toggles an option');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1',
  p_title => 'Plan creado por FM', p_asset_id => 'b9400000-0000-0000-0000-0000000000a2', p_frequency => 'monthly') $$, 'insp plan: FM manager creates a plan (no responsible)');
SELECT lives_ok($$ SELECT * FROM public.replace_inspection_plan_alert_rules('b9830000-0000-0000-0000-0000000000a1', '[{"alert_type":"before_due","days_before":15},{"alert_type":"overdue"}]') $$, 'insp plan: FM manager configures alert rules');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan_alert_rule('b9830000-0000-0000-0000-0000000000a0', 'before_due', 7) $$, 'insp plan: FM manager adds one alert rule');
SELECT lives_ok($$ SELECT public.set_inspection_plan_alert_rule_active((SELECT r.id FROM public.get_inspection_plan_alert_rules('b9830000-0000-0000-0000-0000000000a0') r LIMIT 1), false) $$, 'insp plan: FM manager toggles an alert rule');

SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000007');
SELECT throws_ok($$ SELECT public.upsert_checklist_template('b9200000-0000-0000-0000-0000000000a1', 'Tecnico FM') $$, 'P0001', NULL, 'insp plan: FM technician cannot create templates');
SELECT throws_ok($$ SELECT public.upsert_checklist_template_item('b9800000-0000-0000-0000-0000000000a1', 'x', NULL, NULL, 9) $$, 'P0001', NULL, 'insp plan: FM technician cannot add items');
SELECT throws_ok($$ SELECT public.set_checklist_template_item_active('b9810000-0000-0000-0000-0000000000a1', false) $$, 'P0001', NULL, 'insp plan: FM technician cannot toggle items');
SELECT throws_ok($$ SELECT public.upsert_checklist_response_option('b9800000-0000-0000-0000-0000000000a1', 'x', 'x') $$, 'P0001', NULL, 'insp plan: FM technician cannot add options');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'x', p_asset_id => 'b9400000-0000-0000-0000-0000000000a2') $$, 'P0001', NULL, 'insp plan: FM technician cannot create plans');
SELECT throws_ok($$ SELECT * FROM public.replace_inspection_plan_alert_rules('b9830000-0000-0000-0000-0000000000a1', '[]') $$, 'P0001', NULL, 'insp plan: FM technician cannot change alert rules');

SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT public.upsert_checklist_template('b9200000-0000-0000-0000-0000000000c1', 'Solo view') $$, 'P0001', NULL, 'insp plan: view-only relationship cannot create templates');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000c1', p_template_id => 'b9800000-0000-0000-0000-0000000000c1', p_title => 'x', p_asset_id => 'b9400000-0000-0000-0000-0000000000c1') $$, 'P0001', NULL, 'insp plan: view-only relationship cannot create plans');
SELECT throws_ok($$ SELECT public.upsert_checklist_template('b9200000-0000-0000-0000-0000000000d1', 'Manage sin view') $$, 'P0001', NULL, 'insp plan: inspections.manage without view cannot plan');
SELECT throws_ok($$ SELECT public.upsert_checklist_template_item('b9800000-0000-0000-0000-0000000000b1', 'x', NULL, NULL, 9) $$, 'P0001', NULL, 'insp cross-tenant: cannot add an item to a Client B template');
SELECT throws_ok($$ SELECT public.upsert_checklist_template('b9200000-0000-0000-0000-0000000000a1', 'x', NULL, NULL, 'b9800000-0000-0000-0000-0000000000b1') $$, 'P0001', 'Template not found for this organization', 'insp cross-tenant: a Client B template id cannot be edited through Client A');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000b1', p_title => 'x', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1') $$, 'P0001', 'template_id must belong to this organization', 'insp cross-tenant: a plan cannot use a Client B template');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'x', p_asset_id => 'b9400000-0000-0000-0000-0000000000b1') $$, 'P0001', 'asset_id must belong to this organization', 'insp cross-tenant: a plan cannot target a Client B asset');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'x', p_branch_id => 'b9600000-0000-0000-0000-0000000000b1') $$, 'P0001', 'branch_id must belong to this organization', 'insp cross-tenant: a plan cannot target a Client B branch');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000b1', p_template_id => 'b9800000-0000-0000-0000-0000000000b1', p_title => 'x', p_asset_id => 'b9400000-0000-0000-0000-0000000000b1', p_plan_id => 'b9830000-0000-0000-0000-0000000000b1') $$, 'P0001', NULL, 'insp cross-tenant: a Client B plan cannot be edited');
SELECT throws_ok($$ SELECT * FROM public.replace_inspection_plan_alert_rules('b9830000-0000-0000-0000-0000000000b1', '[]') $$, 'P0001', NULL, 'insp cross-tenant: Client B alert rules cannot be replaced');
SELECT throws_ok($$ SELECT public.set_inspection_plan_alert_rule_active('b9840000-0000-0000-0000-0000000000b1', false) $$, 'P0001', NULL, 'insp cross-tenant: a Client B alert rule cannot be toggled');

-- -------------------------------------------------------------------------
-- 3. Responsable de inspección (client-owned)
-- -------------------------------------------------------------------------
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'x', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000003') $$,
  '42501', 'The inspection plan responsible is assigned by the client', 'insp responsible: FM cannot set a client member on a new plan');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'x', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000007') $$,
  '42501', 'The inspection plan responsible is assigned by the client', 'insp responsible: FM cannot point the responsible to its own FM membership');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'Plan A', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000002', p_plan_id => 'b9830000-0000-0000-0000-0000000000a1') $$,
  '42501', 'The inspection plan responsible is assigned by the client', 'insp responsible: FM cannot change the existing responsible');
-- 9C.4: el FM nunca conoce el id. NULL = conservar el responsable real (no
-- puede limpiarlo); cualquier UUID, incluido el actual, => 42501.
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'Plan A (editado por FM)', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_responsible_member_id => NULL, p_frequency => 'monthly', p_plan_id => 'b9830000-0000-0000-0000-0000000000a1') $$,
  'insp responsible: FM edits other fields sending NULL; the server keeps the client responsible (cannot clear it)');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'Plan A0', p_asset_id => 'b9400000-0000-0000-0000-0000000000a2', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000003', p_plan_id => 'b9830000-0000-0000-0000-0000000000a0') $$,
  '42501', 'The inspection plan responsible is assigned by the client', 'insp responsible: FM cannot assign a responsible to an unassigned plan');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'Plan A (reenvío)', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000003', p_frequency => 'monthly', p_plan_id => 'b9830000-0000-0000-0000-0000000000a1') $$,
  '42501', 'The inspection plan responsible is assigned by the client', 'insp responsible: FM cannot resend even the current client responsible id');
SELECT throws_ok($$ SELECT * FROM public.get_assignable_technicians('b9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'insp responsible: FM does not get the client technician roster');
SELECT throws_ok($$ SELECT * FROM public.get_assignable_planners('b9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'insp responsible: FM does not get the client planner roster');

SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'Plan directo', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000003') $$,
  'insp responsible (direct): client manager still assigns a responsible on a new plan');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'Plan A0 (directo)', p_asset_id => 'b9400000-0000-0000-0000-0000000000a2', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000002', p_frequency => 'monthly', p_plan_id => 'b9830000-0000-0000-0000-0000000000a0') $$,
  'insp responsible (direct): client manager still changes the responsible');
SELECT ok((SELECT count(*) > 0 FROM public.get_assignable_planners('b9200000-0000-0000-0000-0000000000a1')), 'insp responsible (direct): client manager keeps the planner roster');
RESET ROLE;
SELECT results_eq(
  $$ SELECT title, responsible_member_id FROM public.inspection_plans WHERE id = 'b9830000-0000-0000-0000-0000000000a1' $$,
  $$ VALUES ('Plan A (editado por FM)'::text, 'b9300000-0000-0000-0000-000000000003'::uuid) $$,
  'insp responsible: FM edit persisted and the client responsible is unchanged');
SELECT is((SELECT responsible_member_id FROM public.inspection_plans WHERE title = 'Plan creado por FM'), NULL, 'insp responsible: the FM-created plan has no responsible');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 4. Inspecciones — EJECUTAR (view + manage, owner/admin/manager/technician)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000007');
SELECT lives_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a1') $$, 'insp execute: FM technician creates a run (not the client responsible)');
SELECT lives_ok($$ SELECT public.submit_inspection_run('b9850000-0000-0000-0000-0000000000a2', now() - interval '1 hour', now(), pg_temp.answers_a(),
  '[{"template_item_id":"b9810000-0000-0000-0000-0000000000a1","file_name":"foto.jpg","file_url":"https://evidence.example/foto.jpg","file_path":"inspections/foto.jpg","mime_type":"image/jpeg","size_bytes":"1200"}]', 'OK FM') $$,
  'insp execute: FM technician submits a run with evidence metadata');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT lives_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a0') $$, 'insp execute: FM manager creates a run');
SELECT lives_ok($$ SELECT public.submit_inspection_run('b9850000-0000-0000-0000-0000000000a1', now() - interval '1 hour', now(), pg_temp.answers_a()) $$, 'insp execute: FM manager submits a client-assigned run');
SELECT lives_ok($$ SELECT public.submit_inspection_run('b9850000-0000-0000-0000-0000000000a1', now() - interval '30 minutes', now(), pg_temp.answers_a()) $$, 'insp execute: completed-run semantics preserved (a completed run can be resubmitted, as for direct planners)');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000004');
SELECT lives_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a0') $$, 'insp execute: FM owner creates a run');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000005');
SELECT lives_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a0') $$, 'insp execute: FM admin creates a run');

SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000007');
SELECT throws_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000c1') $$, 'P0001', NULL, 'insp execute: view-only technician cannot create runs');
SELECT throws_ok($$ SELECT public.submit_inspection_run('b9850000-0000-0000-0000-0000000000c1', now() - interval '1 hour', now(), '[{"template_item_id":"b9810000-0000-0000-0000-0000000000c1","response_option_id":"b9820000-0000-0000-0000-0000000000c1"}]') $$, 'P0001', NULL, 'insp execute: view-only technician cannot submit runs');
SELECT throws_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000d1') $$, 'P0001', NULL, 'insp execute: inspections.manage without view cannot create runs');
SELECT throws_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000b1') $$, 'P0001', NULL, 'insp cross-tenant: cannot create a run from a Client B plan');
SELECT throws_ok($$ SELECT public.submit_inspection_run('b9850000-0000-0000-0000-0000000000b1', now() - interval '1 hour', now(), '[{"template_item_id":"b9810000-0000-0000-0000-0000000000b1","response_option_id":"b9820000-0000-0000-0000-0000000000b1"}]') $$, 'P0001', NULL, 'insp cross-tenant: cannot submit a Client B run');
SELECT throws_ok($$ SELECT public.submit_inspection_run('b9850000-0000-0000-0000-0000000000a2', now() - interval '1 hour', now(), '[{"template_item_id":"b9810000-0000-0000-0000-0000000000b1","response_option_id":"b9820000-0000-0000-0000-0000000000b1"}]') $$, 'P0001', NULL, 'insp cross-tenant: a Client A run cannot be answered with Client B items');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000008');
SELECT throws_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a0') $$, 'P0001', NULL, 'insp execute: FM viewer cannot create runs');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000c');
SELECT throws_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a0') $$, 'P0001', NULL, 'insp execute: unassigned FM manager cannot create runs');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000e');
SELECT throws_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a0') $$, 'P0001', NULL, 'insp execute: inactive FM technician cannot create runs');

-- Técnico directo: regla histórica intacta (solo el responsable del plan).
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000003');
SELECT lives_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a1') $$, 'insp execute (direct): the client responsible technician still creates runs');
SELECT throws_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a0') $$, 'P0001', NULL, 'insp execute (direct): a client technician who is not the responsible is still rejected');
SELECT throws_ok($$ SELECT public.upsert_checklist_template('b9200000-0000-0000-0000-0000000000a1', 'x') $$, 'P0001', NULL, 'insp plan (direct): client technician still cannot plan');
RESET ROLE;

SELECT results_eq(
  $$ SELECT status, result, created_by_user_id::text FROM public.inspection_runs WHERE id = 'b9850000-0000-0000-0000-0000000000a2' $$,
  $$ VALUES ('completed'::text, 'passed'::text, NULL::text) $$,
  'insp execute: the FM technician run is completed with the server-computed result');
SELECT is((SELECT count(*) FROM public.inspection_runs WHERE plan_id = 'b9830000-0000-0000-0000-0000000000a1' AND created_by_user_id = 'b9100000-0000-0000-0000-000000000007'), 1::bigint,
  'insp execute: the run created by the FM technician is attributed to that user');
SELECT is((SELECT responsible_member_id FROM public.inspection_runs WHERE plan_id = 'b9830000-0000-0000-0000-0000000000a1' AND created_by_user_id = 'b9100000-0000-0000-0000-000000000007'),
  'b9300000-0000-0000-0000-000000000003'::uuid, 'insp execute: the run keeps the client responsible (no fake FM membership)');
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'b9200000-0000-0000-0000-0000000000a1'), 4::bigint,
  'insp execute: no FM membership was created inside the client');
SELECT is((SELECT count(*) FROM public.asset_events WHERE asset_id = 'b9400000-0000-0000-0000-0000000000a2' AND event_type = 'inspection_completed' AND created_by_user_id = 'b9100000-0000-0000-0000-000000000007'), 1::bigint,
  'insp execute: the asset history records the FM technician completion');

-- -------------------------------------------------------------------------
-- 5. Evidencias (solo metadata; sin R2)
-- -------------------------------------------------------------------------
SELECT results_eq(
  $$ SELECT file_name, file_url, file_path FROM public.inspection_run_evidences WHERE run_id = 'b9850000-0000-0000-0000-0000000000a2' $$,
  $$ VALUES ('foto.jpg'::text, 'https://evidence.example/foto.jpg'::text, 'inspections/foto.jpg'::text) $$,
  'evidence: the metadata submitted by the FM technician is stored as-is');
SELECT ok((SELECT prosrc !~ 'facility_management' FROM pg_proc WHERE oid = 'public.authorize_asset_file_access(uuid,text)'::regprocedure),
  'evidence: authorize_asset_file_access (R2) is not extended by 9C.2');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT public.authorize_asset_file_access('b9400000-0000-0000-0000-0000000000a1', 'read') $$, 'P0001', NULL, 'evidence: inspections.manage grants no R2 asset-file access');

-- -------------------------------------------------------------------------
-- 6. Preventivo — VER (preventive_maintenance.view, owner/admin/manager/technician)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000004');
SELECT is(jsonb_array_length(public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true)), 1, 'pm view: FM owner reads Client A cards');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000005');
SELECT is(jsonb_array_length(public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true)), 1, 'pm view: FM admin reads Client A cards');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT is(jsonb_array_length(public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true)), 1, 'pm view: FM manager reads Client A cards');
SELECT is(jsonb_array_length(public.get_preventive_maintenance_plans('b9200000-0000-0000-0000-0000000000a1')), 2, 'pm view: FM manager reads Client A plans');
SELECT is(jsonb_array_length(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1')), 2, 'pm view: FM manager reads Client A occurrences');
SELECT is(jsonb_array_length(public.get_asset_meters('b9400000-0000-0000-0000-0000000000a1', true)), 3, 'pm view: FM manager reads Client A meters');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000007');
SELECT is(jsonb_array_length(public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true)), 1, 'pm view: FM technician reads Client A cards');
SELECT is(jsonb_array_length(public.get_asset_meters('b9400000-0000-0000-0000-0000000000a1', false)->0->'readings'), 1, 'pm view: FM technician reads meter readings');

SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000008');
SELECT throws_ok($$ SELECT public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'pm view: FM viewer is rejected');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000c');
SELECT throws_ok($$ SELECT public.get_preventive_maintenance_plans('b9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'pm view: unassigned FM manager is rejected');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000e');
SELECT throws_ok($$ SELECT public.get_asset_meters('b9400000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'pm view: inactive FM membership is rejected');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000009');
SELECT throws_ok($$ SELECT public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'pm view: FM B cannot read Client A');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000b1', true) $$, 'P0001', NULL, 'pm view: FM A manager cannot read Client B cards');
SELECT throws_ok($$ SELECT public.get_asset_meters('b9400000-0000-0000-0000-0000000000b1', true) $$, 'P0001', NULL, 'pm view: a Client B asset meter list stays closed');
SELECT throws_ok($$ SELECT public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000f1') $$, 'P0001', NULL, 'pm view: no preventive permission => rejected');
SELECT throws_ok($$ SELECT public.get_preventive_maintenance_plans('b9200000-0000-0000-0000-0000000000e1') $$, 'P0001', NULL, 'pm view: suspended relationship => rejected');
SELECT throws_ok($$ SELECT public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000d1', true) $$, 'P0001', NULL, 'pm view: preventive_maintenance.manage without view => rejected');
SELECT is(jsonb_array_length(public.get_preventive_maintenance_plans('b9200000-0000-0000-0000-0000000000c1')), 0, 'pm view: view-only relationship reads plans');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000a');
SELECT throws_ok($$ SELECT public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'pm view: outsider is rejected');

-- -------------------------------------------------------------------------
-- 7. Inventario y materiales (inventario no se delega)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT ok((SELECT bool_and(NOT (m ? 'material_id') AND NOT (m ? 'current_stock') AND NOT (m ? 'material_code') AND NOT (m ? 'material_name') AND NOT (m ? 'material_is_active'))
           FROM jsonb_array_elements(pg_temp.card_materials('b9200000-0000-0000-0000-0000000000a1', 'KA')) m),
  'inventory: delegated card reads expose no material_id, stock, code, name or active flag');
SELECT is((SELECT array_agg((m->>'client_linked_material')::boolean ORDER BY (m->>'sequence')::int)
           FROM jsonb_array_elements(pg_temp.card_materials('b9200000-0000-0000-0000-0000000000a1', 'KA')) m),
  ARRAY[true, false], 'inventory: delegated reads only flag which lines the client linked to its catalog');
SELECT ok(public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true)::text !~ 'Filtro secreto', 'inventory: the catalog material name never reaches the FM');
SELECT ok((SELECT bool_and(NOT (m ? 'material_id') AND NOT (m ? 'code') AND NOT (m ? 'name'))
           FROM jsonb_array_elements(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1')->0->'scope_snapshot'->'card'->'materials') m),
  'inventory: occurrence scope snapshots are sanitized for the FM');
SELECT ok((SELECT bool_and(NOT (m ? 'material_id') AND NOT (m ? 'code') AND NOT (m ? 'name'))
           FROM jsonb_array_elements(public.get_preventive_maintenance_plans('b9200000-0000-0000-0000-0000000000a1')->0->'current_occurrence'->'scope_snapshot'->'card'->'materials') m),
  'inventory: current-occurrence snapshots in the plan list are sanitized for the FM');
SELECT throws_ok($$ SELECT * FROM public.get_inventory_catalog('b9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'inventory: FM manager gets no inventory catalog');
SELECT throws_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000a1', 'KFM', 'Ficha FM', p_materials => '[{"material_id":"b9870000-0000-0000-0000-0000000000a1","description":"x","quantity":1,"unit":"und"}]') $$,
  '42501', 'A delegated facility manager cannot link inventory materials', 'inventory: FM cannot link a catalog material on a new card');
SELECT throws_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000a1', 'KA', 'Ficha A', p_materials => '[{"material_id":"b9870000-0000-0000-0000-0000000000a1","description":"x","quantity":1,"unit":"und"}]', p_card_id => 'b9880000-0000-0000-0000-0000000000a1') $$,
  '42501', 'A delegated facility manager cannot link inventory materials', 'inventory: FM cannot re-send or change a catalog link when editing');
SELECT lives_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000a1', 'KA', 'Ficha A (FM)', p_tasks => '[{"title":"Revisar"},{"title":"Limpiar"}]',
  p_materials => '[{"description":"Guantes","quantity":2,"unit":"par"},{"description":"Trapo industrial","quantity":3,"unit":"und"}]', p_card_id => 'b9880000-0000-0000-0000-0000000000a1') $$,
  'inventory: FM edits a card with free-text materials only');
RESET ROLE;
SELECT results_eq(
  $$ SELECT sequence, material_id, description FROM public.maintenance_card_materials WHERE card_id = 'b9880000-0000-0000-0000-0000000000a1' ORDER BY sequence $$,
  $$ VALUES (1, 'b9870000-0000-0000-0000-0000000000a1'::uuid, 'Filtro del catálogo'::text), (2, NULL::uuid, 'Guantes'::text), (3, NULL::uuid, 'Trapo industrial'::text) $$,
  'inventory: the client catalog link is preserved; the FM free-text lines replace the previous free-text lines');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000001');
SELECT ok((SELECT bool_and(m ? 'material_id' AND m ? 'current_stock') FROM jsonb_array_elements(pg_temp.card_materials('b9200000-0000-0000-0000-0000000000a1', 'KA')) m),
  'inventory (direct): client owner still receives material_id and stock');
SELECT ok(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1')->0->'scope_snapshot'->'card'->'materials'->0 ? 'material_id',
  'inventory (direct): client owner still receives the full scope snapshot');
SELECT lives_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000a1', 'KD', 'Ficha directa', p_materials => '[{"material_id":"b9870000-0000-0000-0000-0000000000a1","description":"Filtro","quantity":1,"unit":"und"}]') $$,
  'inventory (direct): client owner still links catalog materials');

-- -------------------------------------------------------------------------
-- 8. Preventivo — PLANIFICAR / ADMINISTRAR MEDIDORES (view + manage, o/a/m)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000004');
SELECT lives_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000a1', 'KO', 'Ficha FM owner', p_materials => '[{"description":"Aceite","quantity":1,"unit":"l"}]') $$, 'pm manage: FM owner creates a card');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000005');
SELECT lives_ok($$ SELECT public.create_asset_meter('b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a2', 'Horómetro admin FM', 'h', 5) $$, 'pm manage: FM admin creates a meter (with its initial reading)');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT lives_ok($$ SELECT public.set_maintenance_card_active((SELECT (c->>'id')::uuid FROM jsonb_array_elements(public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true)) c WHERE c->>'code' = 'KO'), false) $$, 'pm manage: FM manager deactivates a card');
SELECT lives_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000a2',
  p_card_id => 'b9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_frequency => 'monthly', p_first_due_at => now() + interval '40 days') $$, 'pm manage: FM manager creates a plan (no responsible)');
SELECT lives_ok($$ SELECT public.skip_preventive_maintenance_occurrence('b98d0000-0000-0000-0000-0000000000a1', 'Equipo detenido por el cliente') $$, 'pm manage: FM manager skips an occurrence with a reason');
SELECT lives_ok($$ SELECT public.correct_asset_meter_reading('b98b0000-0000-0000-0000-0000000000a1', 110, 'Error de digitación') $$, 'pm manage: FM manager corrects a reading');
SELECT lives_ok($$ SELECT public.retire_asset_meter('b98a0000-0000-0000-0000-0000000000a2', 'Dañado') $$, 'pm manage: FM manager retires a meter');
SELECT lives_ok($$ SELECT public.replace_asset_meter('b98a0000-0000-0000-0000-0000000000a3', 'Horómetro nuevo', 'h', 0, now(), 'Cambio de equipo') $$, 'pm manage: FM manager replaces a meter');
SELECT lives_ok($$ SELECT public.create_asset_meter('b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a1', 'Contador FM', 'ciclos') $$, 'pm manage: FM manager creates a meter');

SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000007');
SELECT throws_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000a1', 'KT', 'Ficha tecnico') $$, 'P0001', NULL, 'pm manage: FM technician cannot create cards');
SELECT throws_ok($$ SELECT public.set_maintenance_card_active('b9880000-0000-0000-0000-0000000000a1', false) $$, 'P0001', NULL, 'pm manage: FM technician cannot toggle cards');
SELECT throws_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000a2', p_card_id => 'b9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_frequency => 'monthly', p_first_due_at => now() + interval '9 days') $$, 'P0001', NULL, 'pm manage: FM technician cannot create plans');
SELECT throws_ok($$ SELECT public.set_preventive_maintenance_plan_active('b98c0000-0000-0000-0000-0000000000a1', false, 'x') $$, 'P0001', NULL, 'pm manage: FM technician cannot deactivate plans');
SELECT throws_ok($$ SELECT public.skip_preventive_maintenance_occurrence('b98d0000-0000-0000-0000-0000000000a1', 'x') $$, 'P0001', NULL, 'pm manage: FM technician cannot skip occurrences');
SELECT throws_ok($$ SELECT public.create_asset_meter('b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000a1', 'x', 'h') $$, 'P0001', NULL, 'pm manage: FM technician cannot create meters');
SELECT throws_ok($$ SELECT public.correct_asset_meter_reading('b98b0000-0000-0000-0000-0000000000a1', 120, 'x') $$, 'P0001', NULL, 'pm manage: FM technician cannot correct readings');
SELECT throws_ok($$ SELECT public.retire_asset_meter('b98a0000-0000-0000-0000-0000000000a1', 'x') $$, 'P0001', NULL, 'pm manage: FM technician cannot retire meters');
SELECT throws_ok($$ SELECT public.replace_asset_meter('b98a0000-0000-0000-0000-0000000000a1', 'x', 'h', 0, now(), 'x') $$, 'P0001', NULL, 'pm manage: FM technician cannot replace meters');

SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000c1', 'KC', 'Solo view') $$, 'P0001', NULL, 'pm manage: view-only relationship cannot create cards');
SELECT throws_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000d1', 'KD', 'Manage sin view') $$, 'P0001', NULL, 'pm manage: preventive_maintenance.manage without view cannot plan');
SELECT throws_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000a1', 'KB', 'x', p_card_id => 'b9880000-0000-0000-0000-0000000000b1') $$, 'P0001', 'Maintenance card not found in this organization', 'pm cross-tenant: a Client B card cannot be edited through Client A');
SELECT throws_ok($$ SELECT public.set_maintenance_card_active('b9880000-0000-0000-0000-0000000000b1', false) $$, 'P0001', NULL, 'pm cross-tenant: a Client B card cannot be toggled');
SELECT throws_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000b1', p_card_id => 'b9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_frequency => 'monthly', p_first_due_at => now() + interval '9 days') $$, 'P0001', NULL, 'pm cross-tenant: a plan cannot target a Client B asset');
SELECT throws_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_card_id => 'b9880000-0000-0000-0000-0000000000b1', p_trigger_type => 'calendar', p_frequency => 'monthly', p_first_due_at => now() + interval '9 days') $$, 'P0001', NULL, 'pm cross-tenant: a plan cannot use a Client B card');
SELECT throws_ok($$ SELECT public.set_preventive_maintenance_plan_active('b98c0000-0000-0000-0000-0000000000b1', false, 'x') $$, 'P0001', NULL, 'pm cross-tenant: a Client B plan cannot be deactivated');
SELECT throws_ok($$ SELECT public.skip_preventive_maintenance_occurrence('b98d0000-0000-0000-0000-0000000000b1', 'x') $$, 'P0001', NULL, 'pm cross-tenant: a Client B occurrence cannot be skipped');
SELECT throws_ok($$ SELECT public.create_asset_meter('b9200000-0000-0000-0000-0000000000a1', 'b9400000-0000-0000-0000-0000000000b1', 'x', 'h') $$, 'P0001', NULL, 'pm cross-tenant: a meter cannot be created on a Client B asset');
SELECT throws_ok($$ SELECT public.correct_asset_meter_reading('b98b0000-0000-0000-0000-0000000000b1', 120, 'x') $$, 'P0001', NULL, 'pm cross-tenant: a Client B reading cannot be corrected');
SELECT throws_ok($$ SELECT public.retire_asset_meter('b98a0000-0000-0000-0000-0000000000b1', 'x') $$, 'P0001', NULL, 'pm cross-tenant: a Client B meter cannot be retired');
SELECT throws_ok($$ SELECT public.replace_asset_meter('b98a0000-0000-0000-0000-0000000000b1', 'x', 'h', 0, now(), 'x') $$, 'P0001', NULL, 'pm cross-tenant: a Client B meter cannot be replaced');

-- -------------------------------------------------------------------------
-- 9. Registrar lectura (view + manage, owner/admin/manager/technician)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000007');
SELECT lives_ok($$ SELECT public.record_asset_meter_reading('b98a0000-0000-0000-0000-0000000000a1', 500, now()) $$, 'pm meter: FM technician records a new reading');
SELECT throws_ok($$ SELECT public.record_asset_meter_reading('b98a0000-0000-0000-0000-0000000000c1', 500, now()) $$, 'P0001', NULL, 'pm meter: view-only technician cannot record readings');
SELECT throws_ok($$ SELECT public.record_asset_meter_reading('b98a0000-0000-0000-0000-0000000000d1', 500, now()) $$, 'P0001', NULL, 'pm meter: preventive_maintenance.manage without view cannot record readings');
SELECT throws_ok($$ SELECT public.record_asset_meter_reading('b98a0000-0000-0000-0000-0000000000b1', 500, now()) $$, 'P0001', NULL, 'pm meter cross-tenant: a Client B meter cannot be read into');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000008');
SELECT throws_ok($$ SELECT public.record_asset_meter_reading('b98a0000-0000-0000-0000-0000000000a1', 600, now()) $$, 'P0001', NULL, 'pm meter: FM viewer cannot record readings');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000003');
SELECT lives_ok($$ SELECT public.record_asset_meter_reading('b98a0000-0000-0000-0000-0000000000a1', 700, now() + interval '1 minute') $$, 'pm meter (direct): client technician still records readings');
SELECT throws_ok($$ SELECT public.save_maintenance_card('b9200000-0000-0000-0000-0000000000a1', 'KX', 'x') $$, 'P0001', NULL, 'pm manage (direct): client technician still cannot manage cards');
RESET ROLE;
SELECT is((SELECT created_by_user_id FROM public.asset_meter_readings WHERE meter_id = 'b98a0000-0000-0000-0000-0000000000a1' AND value = 500),
  'b9100000-0000-0000-0000-000000000007'::uuid, 'pm meter: the FM technician reading is attributed to that user');
SELECT is((SELECT count(*) FROM public.asset_meter_readings WHERE meter_id = 'b98a0000-0000-0000-0000-0000000000a1' AND voided_at IS NOT NULL), 1::bigint,
  'pm manage: the corrected reading stays voided in the audit trail');
SELECT results_eq(
  $$ SELECT status, skip_reason FROM public.preventive_maintenance_occurrences WHERE id = 'b98d0000-0000-0000-0000-0000000000a1' $$,
  $$ VALUES ('skipped'::text, 'Equipo detenido por el cliente'::text) $$,
  'pm manage: the skipped occurrence keeps its reason');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 10. Responsable del plan preventivo (client-owned)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_card_id => 'b9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000002', p_frequency => 'monthly', p_first_due_at => now() + interval '9 days') $$,
  '42501', 'The preventive plan responsible is assigned by the client', 'pm responsible: FM cannot set a client member on a new plan');
SELECT throws_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_card_id => 'b9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000001', p_frequency => 'monthly', p_first_due_at => now() + interval '20 days', p_plan_id => 'b98c0000-0000-0000-0000-0000000000a1') $$,
  '42501', 'The preventive plan responsible is assigned by the client', 'pm responsible: FM cannot change the existing responsible');
-- 9C.4: el delegado nunca conoce el id del responsable. Reenviarlo (aunque
-- sea el actual) es inyectar un UUID del cliente: 42501. NULL = conservar el
-- responsable real (no es posible limpiarlo).
SELECT throws_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_card_id => 'b9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_priority => 'high', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000002', p_frequency => 'monthly', p_first_due_at => now() + interval '20 days', p_plan_id => 'b98c0000-0000-0000-0000-0000000000a1') $$,
  '42501', 'The preventive plan responsible is assigned by the client', 'pm responsible: FM cannot resend even the current client responsible id');
SELECT lives_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_card_id => 'b9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_priority => 'high', p_responsible_member_id => NULL, p_frequency => 'monthly', p_first_due_at => now() + interval '20 days', p_plan_id => 'b98c0000-0000-0000-0000-0000000000a1') $$,
  'pm responsible: FM edits the plan without the id; the server preserves the client responsible (cannot clear it)');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_asset_id => 'b9400000-0000-0000-0000-0000000000a1', p_card_id => 'b9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_priority => 'high', p_responsible_member_id => 'b9300000-0000-0000-0000-000000000001', p_frequency => 'monthly', p_first_due_at => now() + interval '20 days', p_plan_id => 'b98c0000-0000-0000-0000-0000000000a1') $$,
  'pm responsible (direct): client owner still changes the responsible');
RESET ROLE;
SELECT results_eq(
  $$ SELECT priority, responsible_member_id FROM public.preventive_maintenance_plans WHERE id = 'b98c0000-0000-0000-0000-0000000000a1' $$,
  $$ VALUES ('high'::text, 'b9300000-0000-0000-0000-000000000001'::uuid) $$,
  'pm responsible: FM edit persisted; only the client changed the responsible');
SELECT is(ARRAY(SELECT responsible_member_id FROM public.preventive_maintenance_plans
                WHERE asset_id = 'b9400000-0000-0000-0000-0000000000a2' AND created_by_user_id = 'b9100000-0000-0000-0000-000000000006'),
  ARRAY[NULL::uuid], 'pm responsible: the FM-created plan has no responsible');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 11. Solicitudes preventivas quedan fuera (9C.4)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT public.plan_preventive_maintenance_occurrence((SELECT (o->>'id')::uuid FROM jsonb_array_elements(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1', NULL, 'open')) o LIMIT 1), gen_random_uuid()) $$,
  'P0001', 'Not authorized', 'request isolation: FM manager with preventive view+manage cannot link a request to an occurrence');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000004');
SELECT throws_ok($$ SELECT public.plan_preventive_maintenance_occurrence((SELECT (o->>'id')::uuid FROM jsonb_array_elements(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1', NULL, 'open')) o LIMIT 1), gen_random_uuid()) $$,
  'P0001', 'Not authorized', 'request isolation: FM owner cannot link a request either');
SELECT is((SELECT count(*) FROM public.requests WHERE organization_id = 'b9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'request isolation: the FM reads no client requests');

-- -------------------------------------------------------------------------
-- 12. Directorios mínimos de referencia
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT is(pg_temp.keys(public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000a1')), ARRAY['assets', 'branches'], 'targets: only branches and assets');
SELECT is(pg_temp.keys(public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000a1')->'branches'->0), ARRAY['id', 'is_active', 'name'], 'targets: branches expose only id/name/is_active');
SELECT is(pg_temp.keys(public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000a1')->'assets'->0),
  ARRAY['branch_id', 'code', 'id', 'name', 'node_type', 'parent_asset_id', 'status'], 'targets: assets expose only the minimal fields');
SELECT is(jsonb_array_length(public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000a1')->'assets'), 2, 'targets: archived and other-tenant assets are excluded');
SELECT ok(public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000a1')::text !~ 'secret', 'targets: no branch email, metadata or technical data');
SELECT throws_ok($$ SELECT public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000b1') $$, '42501', NULL, 'targets: another client stays closed');
SELECT throws_ok($$ SELECT public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000c1') $$, '42501', NULL, 'targets: view-only relationship (cannot plan) gets no directory');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000007');
SELECT throws_ok($$ SELECT public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'targets: FM technician (cannot plan) gets no directory');
SELECT is((SELECT count(*) FROM public.get_facility_management_preventive_assets('b9200000-0000-0000-0000-0000000000a1')), 2::bigint, 'pm assets: FM technician lists the non-archived Client A assets');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_preventive_assets('b9200000-0000-0000-0000-0000000000b1') $$, '42501', NULL, 'pm assets: another client stays closed');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_preventive_assets('b9200000-0000-0000-0000-0000000000f1') $$, '42501', NULL, 'pm assets: no preventive permission => closed');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'targets: delegated-only (direct members keep their own flow)');
RESET ROLE;
SELECT is(pg_get_function_result('public.get_facility_management_preventive_assets(uuid)'::regprocedure), 'TABLE(id uuid, name text, code text, status text)', 'pm assets: returns only id/name/code/status');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 13. Cliente directo: comportamiento histórico
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000003');
SELECT is(jsonb_array_length(public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true)), 2, 'direct: client technician reads templates');
SELECT is(jsonb_array_length(public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true)), 3, 'direct: client technician reads cards');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT public.upsert_checklist_template('b9200000-0000-0000-0000-0000000000a1', 'Plantilla directa') $$, 'direct: client manager still creates templates');
SELECT lives_ok($$ SELECT public.create_inspection_run_from_plan('b9830000-0000-0000-0000-0000000000a0') $$, 'direct: client manager still creates runs');
SELECT lives_ok($$ SELECT public.skip_preventive_maintenance_occurrence((SELECT (o->>'id')::uuid FROM jsonb_array_elements(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1', NULL, 'open')) o WHERE o->>'plan_id' = 'b98c0000-0000-0000-0000-0000000000a1'), 'Directo') $$, 'direct: client manager still skips occurrences');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000d');
SELECT throws_ok($$ SELECT public.get_checklist_templates('b9200000-0000-0000-0000-0000000000a1', true) $$, 'P0001', NULL, 'direct: another client owner still cannot read Client A');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-00000000000b');
SELECT is(jsonb_array_length(public.get_maintenance_cards('b9200000-0000-0000-0000-0000000000a1', true)), 3, 'direct: platform admin keeps read access');

-- -------------------------------------------------------------------------
-- 14. Sin acceso cross-module nuevo
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('b9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: maintenance notices stay closed');
SELECT throws_ok($$ SELECT * FROM public.get_asset_traffic_light('b9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: traffic light stays closed');
SELECT throws_ok($$ SELECT * FROM public.get_asset_integrated_history('b9400000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: integrated history stays closed');
SELECT is((SELECT count(*) FROM public.assets WHERE organization_id = 'b9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'no leak: inspections/preventive do not grant assets.view (no RLS read of assets)');
SELECT is((SELECT count(*) FROM public.client_branches WHERE organization_id = 'b9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'no leak: no RLS read of client branches');
SELECT is((SELECT count(*) FROM public.inspection_runs WHERE organization_id = 'b9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'no leak: inspection tables are only reachable through the RPCs');
SELECT is((SELECT count(*) FROM public.maintenance_card_materials), 0::bigint, 'no leak: card materials are not readable directly by the FM');
RESET ROLE;

-- -------------------------------------------------------------------------
-- 15. Hardening final 9C.2
-- -------------------------------------------------------------------------
CREATE FUNCTION pg_temp.occurrence(p_org uuid, p_id text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT o FROM jsonb_array_elements(public.get_preventive_maintenance_occurrences(p_org)) o WHERE o->>'id' = p_id;
$$;
CREATE FUNCTION pg_temp.pm_plan(p_org uuid, p_id text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT p FROM jsonb_array_elements(public.get_preventive_maintenance_plans(p_org)) p WHERE p->>'id' = p_id;
$$;
SET LOCAL ROLE authenticated;

-- A. Ids de Solicitudes / OT ocultos al delegado.
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT is(pg_temp.occurrence('b9200000-0000-0000-0000-0000000000a1', 'b98d0000-0000-0000-0000-0000000000a2')->>'status', 'planned', 'ids: FM reads the planned occurrence');
SELECT ok((SELECT o->'request_creation_id' = 'null'::jsonb AND o->'request_id' = 'null'::jsonb AND o->'work_order_id' = 'null'::jsonb
           FROM pg_temp.occurrence('b9200000-0000-0000-0000-0000000000a1', 'b98d0000-0000-0000-0000-0000000000a2') o),
  'ids: request_creation_id / request_id / work_order_id are hidden from the FM');
SELECT ok((SELECT bool_and(o->'request_creation_id' = 'null'::jsonb AND o->'request_id' = 'null'::jsonb AND o->'work_order_id' = 'null'::jsonb)
           FROM jsonb_array_elements(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1')) o),
  'ids: no delegated occurrence reveals request/work-order ids');
SELECT ok((SELECT p->'current_occurrence'->'request_creation_id' = 'null'::jsonb AND p->'current_occurrence'->'request_id' = 'null'::jsonb
                  AND p->'current_occurrence'->'work_order_id' = 'null'::jsonb
           FROM pg_temp.pm_plan('b9200000-0000-0000-0000-0000000000a1', 'b98c0000-0000-0000-0000-0000000000a2') p),
  'ids: the plan list current occurrence hides them too');
SELECT ok(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1')::text !~ '(b98e0000|b98f0000)'
      AND public.get_preventive_maintenance_plans('b9200000-0000-0000-0000-0000000000a1')::text !~ '(b98e0000|b98f0000)',
  'ids: the linked request / work order ids appear nowhere in delegated preventive payloads');
SELECT is((SELECT count(*) FROM public.requests WHERE id = 'b98e0000-0000-0000-0000-0000000000a1'), 0::bigint, 'ids: the FM still cannot read the linked request');
SELECT is((SELECT count(*) FROM public.work_orders WHERE id = 'b98f0000-0000-0000-0000-0000000000a1'), 0::bigint, 'ids: the FM still cannot read the linked work order');
SELECT throws_ok($$ SELECT public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000b1') $$, 'P0001', NULL, 'ids: cross-tenant occurrences stay blocked');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000001');
SELECT ok((SELECT o->>'request_id' = 'b98e0000-0000-0000-0000-0000000000a1' AND o->>'work_order_id' = 'b98f0000-0000-0000-0000-0000000000a1'
                  AND o->>'request_creation_id' IS NOT NULL
           FROM pg_temp.occurrence('b9200000-0000-0000-0000-0000000000a1', 'b98d0000-0000-0000-0000-0000000000a2') o),
  'ids (direct): the client still receives its request/work-order ids');
SELECT is(pg_temp.pm_plan('b9200000-0000-0000-0000-0000000000a1', 'b98c0000-0000-0000-0000-0000000000a2')->'current_occurrence'->>'request_id',
  'b98e0000-0000-0000-0000-0000000000a1', 'ids (direct): the plan list current occurrence keeps them');

-- B. responsible_name nunca derivado del email para el FM.
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT is((SELECT responsible_name FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000a1', true) WHERE id = 'b9830000-0000-0000-0000-0000000000a1'),
  'Tomas Cliente', 'name: a stored display name is still shown to the FM');
SELECT ok((SELECT responsible_member_id IS NULL AND has_responsible AND responsible_name IS NULL FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000a1', true) WHERE id = 'b9830000-0000-0000-0000-0000000000a3'),
  'name: no display name => the FM gets NULL, not the email prefix (plans)');
SELECT is((SELECT responsible_name FROM public.get_inspection_runs('b9200000-0000-0000-0000-0000000000a1', NULL) WHERE id = 'b9850000-0000-0000-0000-0000000000a3'), NULL,
  'name: no email prefix in the delegated runs list');
SELECT is(public.get_inspection_run_detail('b9850000-0000-0000-0000-0000000000a3')->'responsible_name', 'null'::jsonb, 'name: no email prefix in the delegated run detail');
SELECT ok((SELECT string_agg(to_jsonb(p)::text, '') FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000a1', true) p) !~ '(ca-noname|@)'
      AND (SELECT string_agg(to_jsonb(r)::text, '') FROM public.get_inspection_runs('b9200000-0000-0000-0000-0000000000a1', NULL) r) !~ '(ca-noname|@)'
      AND public.get_inspection_run_detail('b9850000-0000-0000-0000-0000000000a3')::text !~ '(ca-noname|@)',
  'name: no email or email prefix anywhere in delegated inspection payloads');
SELECT ok(NOT (pg_temp.occurrence('b9200000-0000-0000-0000-0000000000a1', 'b98d0000-0000-0000-0000-0000000000a2')->'scope_snapshot'->'plan'->'responsible' ? 'name'),
  'name: the delegated preventive snapshot drops the responsible name');
SELECT ok(public.get_preventive_maintenance_occurrences('b9200000-0000-0000-0000-0000000000a1')::text !~ '(ca-noname|@)'
      AND public.get_preventive_maintenance_plans('b9200000-0000-0000-0000-0000000000a1')::text !~ '(ca-noname|@)',
  'name: no email or email prefix anywhere in delegated preventive payloads');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000001');
SELECT is((SELECT responsible_name FROM public.get_inspection_plans('b9200000-0000-0000-0000-0000000000a1', true) WHERE id = 'b9830000-0000-0000-0000-0000000000a3'),
  'ca-noname', 'name (direct): the historic fallback is unchanged for the client');
SELECT is(public.get_inspection_run_detail('b9850000-0000-0000-0000-0000000000a3')->>'responsible_name', 'ca-noname', 'name (direct): run detail unchanged');
SELECT is(pg_temp.occurrence('b9200000-0000-0000-0000-0000000000a1', 'b98d0000-0000-0000-0000-0000000000a2')->'scope_snapshot'->'plan'->'responsible'->>'name',
  'ca-noname', 'name (direct): the preventive snapshot is unchanged for the client');

-- C. Destinos históricos (activo archivado / sede inactiva).
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000006');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1',
  p_title => 'Plan histórico (editado por FM)', p_branch_id => 'b9600000-0000-0000-0000-0000000000a2', p_asset_id => 'b9400000-0000-0000-0000-0000000000a9',
  p_frequency => 'monthly', p_plan_id => 'b9830000-0000-0000-0000-0000000000a4') $$,
  'historic target: FM edits another field of a plan on an inactive branch + archived asset');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'x', p_asset_id => 'b9400000-0000-0000-0000-0000000000a9') $$,
  '22023', 'An archived asset cannot be newly assigned to an inspection plan', 'historic target: FM cannot use an archived asset on a new plan');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'x', p_area_asset_id => 'b9400000-0000-0000-0000-0000000000a9') $$,
  '22023', 'An archived asset cannot be newly assigned to an inspection plan', 'historic target: FM cannot use an archived area on a new plan');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'x', p_branch_id => 'b9600000-0000-0000-0000-0000000000a2') $$,
  '22023', 'An inactive branch cannot be newly assigned to an inspection plan', 'historic target: FM cannot use an inactive branch on a new plan');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'Plan A3', p_asset_id => 'b9400000-0000-0000-0000-0000000000a9',
  p_plan_id => 'b9830000-0000-0000-0000-0000000000a3') $$,
  '22023', 'An archived asset cannot be newly assigned to an inspection plan', 'historic target: FM cannot switch an existing plan to an archived asset');
SELECT ok(public.get_facility_management_inspection_targets('b9200000-0000-0000-0000-0000000000a1')::text !~ '(b9600000-0000-0000-0000-0000000000a2|b9400000-0000-0000-0000-0000000000a9)',
  'historic target: the minimal directory never offers the inactive branch or the archived asset');
SELECT pg_temp.as_user('b9100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'b9200000-0000-0000-0000-0000000000a1', p_template_id => 'b9800000-0000-0000-0000-0000000000a1', p_title => 'Plan directo archivado', p_asset_id => 'b9400000-0000-0000-0000-0000000000a9') $$,
  'historic target (direct): the client keeps its previous semantics');
RESET ROLE;
SELECT results_eq(
  $$ SELECT title, branch_id, asset_id, responsible_member_id FROM public.inspection_plans WHERE id = 'b9830000-0000-0000-0000-0000000000a4' $$,
  $$ VALUES ('Plan histórico (editado por FM)'::text, 'b9600000-0000-0000-0000-0000000000a2'::uuid, 'b9400000-0000-0000-0000-0000000000a9'::uuid, NULL::uuid) $$,
  'historic target: the edit kept the inactive branch and the archived asset');

SELECT * FROM finish();
ROLLBACK;
