-- Fase 1 · Punto 9C.3 — acceso operativo de Facility Manager a Avisos de
-- avería / Backlog (…_facility_manager_maintenance_notices_access.sql).
-- Se ejecuta con: supabase test db --local
--
-- Cada intento corre como `authenticated` con un auth.uid() sintético.
-- Errores: P0001 = regla histórica de las RPCs (RAISE sin código);
-- 42501 / 22023 = reglas nuevas del modo delegado.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(112);

-- -------------------------------------------------------------------------
-- Fixture (sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('c9100000-0000-0000-0000-000000000001', 'ca-owner@fm-notices.test', '{"name":"Olga Cliente"}'),
  ('c9100000-0000-0000-0000-000000000002', 'ca-manager@fm-notices.test', '{"name":"Mario Cliente"}'),
  ('c9100000-0000-0000-0000-000000000003', 'ca-technician@fm-notices.test', '{"name":"Tomas Cliente"}'),
  ('c9100000-0000-0000-0000-000000000004', 'ca-requester@fm-notices.test', '{"name":"Rita Cliente"}'),
  ('c9100000-0000-0000-0000-000000000005', 'ca-viewer@fm-notices.test', '{"name":"Victor Cliente"}'),
  ('c9100000-0000-0000-0000-000000000006', 'ca-noname@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000011', 'fa-owner@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000012', 'fa-admin@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000013', 'fa-manager@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000014', 'fa-technician@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000015', 'fa-requester@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000016', 'fa-viewer@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000017', 'fa-manager-unassigned@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000018', 'fa-technician-inactive@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000021', 'fb-manager@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000031', 'cb-owner@fm-notices.test', '{}'),
  ('c9100000-0000-0000-0000-000000000041', 'outsider@fm-notices.test', '{}');

INSERT INTO public.organizations (id, name, organization_type) VALUES
  ('c9200000-0000-0000-0000-0000000000a1', 'Client A', 'client_company'),
  ('c9200000-0000-0000-0000-0000000000b1', 'Client B', 'client_company'),
  ('c9200000-0000-0000-0000-0000000000c1', 'Client C (view + criticality.view)', 'client_company'),
  ('c9200000-0000-0000-0000-0000000000d1', 'Client D (report + manage sin view)', 'client_company'),
  ('c9200000-0000-0000-0000-0000000000e1', 'Client E (suspendida)', 'client_company'),
  ('c9200000-0000-0000-0000-0000000000f1', 'Client F (view + report, sin inspections.view)', 'client_company'),
  ('c9200000-0000-0000-0000-000000000071', 'Client G (view + manage, sin report)', 'client_company'),
  ('c9200000-0000-0000-0000-0000000000fa', 'FM A', 'facility_manager'),
  ('c9200000-0000-0000-0000-0000000000fb', 'FM B', 'facility_manager');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('c9300000-0000-0000-0000-000000000001', 'c9200000-0000-0000-0000-0000000000a1', 'c9100000-0000-0000-0000-000000000001', 'owner', true),
  ('c9300000-0000-0000-0000-000000000002', 'c9200000-0000-0000-0000-0000000000a1', 'c9100000-0000-0000-0000-000000000002', 'manager', true),
  ('c9300000-0000-0000-0000-000000000003', 'c9200000-0000-0000-0000-0000000000a1', 'c9100000-0000-0000-0000-000000000003', 'technician', true),
  ('c9300000-0000-0000-0000-000000000004', 'c9200000-0000-0000-0000-0000000000a1', 'c9100000-0000-0000-0000-000000000004', 'requester', true),
  ('c9300000-0000-0000-0000-000000000005', 'c9200000-0000-0000-0000-0000000000a1', 'c9100000-0000-0000-0000-000000000005', 'viewer', true),
  ('c9300000-0000-0000-0000-000000000006', 'c9200000-0000-0000-0000-0000000000a1', 'c9100000-0000-0000-0000-000000000006', 'manager', true),
  ('c9300000-0000-0000-0000-000000000011', 'c9200000-0000-0000-0000-0000000000fa', 'c9100000-0000-0000-0000-000000000011', 'owner', true),
  ('c9300000-0000-0000-0000-000000000012', 'c9200000-0000-0000-0000-0000000000fa', 'c9100000-0000-0000-0000-000000000012', 'admin', true),
  ('c9300000-0000-0000-0000-000000000013', 'c9200000-0000-0000-0000-0000000000fa', 'c9100000-0000-0000-0000-000000000013', 'manager', true),
  ('c9300000-0000-0000-0000-000000000014', 'c9200000-0000-0000-0000-0000000000fa', 'c9100000-0000-0000-0000-000000000014', 'technician', true),
  ('c9300000-0000-0000-0000-000000000015', 'c9200000-0000-0000-0000-0000000000fa', 'c9100000-0000-0000-0000-000000000015', 'requester', true),
  ('c9300000-0000-0000-0000-000000000016', 'c9200000-0000-0000-0000-0000000000fa', 'c9100000-0000-0000-0000-000000000016', 'viewer', true),
  ('c9300000-0000-0000-0000-000000000017', 'c9200000-0000-0000-0000-0000000000fa', 'c9100000-0000-0000-0000-000000000017', 'manager', true),
  ('c9300000-0000-0000-0000-000000000018', 'c9200000-0000-0000-0000-0000000000fa', 'c9100000-0000-0000-0000-000000000018', 'technician', true),
  ('c9300000-0000-0000-0000-000000000021', 'c9200000-0000-0000-0000-0000000000fb', 'c9100000-0000-0000-0000-000000000021', 'manager', true),
  ('c9300000-0000-0000-0000-000000000031', 'c9200000-0000-0000-0000-0000000000b1', 'c9100000-0000-0000-0000-000000000031', 'owner', true);

INSERT INTO public.client_branches (id, organization_id, client_email, name, city, site, address, is_active) VALUES
  ('c9600000-0000-0000-0000-0000000000a1', 'c9200000-0000-0000-0000-0000000000a1', 'secret@client-a.test', 'Sede A', 'Lima', 'S1', 'Av. A 1', true);
INSERT INTO public.assets (id, organization_id, code, name, node_type, branch_id, status, criticality, metadata, technical_data) VALUES
  ('c9400000-0000-0000-0000-0000000000a1', 'c9200000-0000-0000-0000-0000000000a1', 'A-1', 'Activo A1', 'equipment', 'c9600000-0000-0000-0000-0000000000a1', 'active', 'high', '{"secret":"meta"}', '{"secret":"tech"}'),
  ('c9400000-0000-0000-0000-0000000000a2', 'c9200000-0000-0000-0000-0000000000a1', 'A-2', 'Activo A2', 'equipment', NULL, 'active', NULL, '{}', '{}'),
  ('c9400000-0000-0000-0000-0000000000a9', 'c9200000-0000-0000-0000-0000000000a1', 'A-9', 'Activo A9 archivado', 'equipment', NULL, 'archived', NULL, '{}', '{}'),
  ('c9400000-0000-0000-0000-0000000000b1', 'c9200000-0000-0000-0000-0000000000b1', 'B-1', 'Activo B1', 'equipment', NULL, 'active', NULL, '{}', '{}'),
  ('c9400000-0000-0000-0000-0000000000c1', 'c9200000-0000-0000-0000-0000000000c1', 'C-1', 'Activo C1', 'equipment', NULL, 'active', 'high', '{}', '{}'),
  ('c9400000-0000-0000-0000-0000000000d1', 'c9200000-0000-0000-0000-0000000000d1', 'D-1', 'Activo D1', 'equipment', NULL, 'active', NULL, '{}', '{}'),
  ('c9400000-0000-0000-0000-0000000000f1', 'c9200000-0000-0000-0000-0000000000f1', 'F-1', 'Activo F1', 'equipment', NULL, 'active', NULL, '{}', '{}'),
  ('c9400000-0000-0000-0000-000000000071', 'c9200000-0000-0000-0000-000000000071', 'G-1', 'Activo G1', 'equipment', NULL, 'active', NULL, '{}', '{}');

INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status) VALUES
  ('c9700000-0000-0000-0000-0000000000aa', 'c9200000-0000-0000-0000-0000000000a1', 'c9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('c9700000-0000-0000-0000-0000000000bb', 'c9200000-0000-0000-0000-0000000000b1', 'c9200000-0000-0000-0000-0000000000fb', 'facility_management', 'pending'),
  ('c9700000-0000-0000-0000-0000000000ca', 'c9200000-0000-0000-0000-0000000000c1', 'c9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('c9700000-0000-0000-0000-0000000000da', 'c9200000-0000-0000-0000-0000000000d1', 'c9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('c9700000-0000-0000-0000-0000000000ea', 'c9200000-0000-0000-0000-0000000000e1', 'c9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('c9700000-0000-0000-0000-0000000000fa', 'c9200000-0000-0000-0000-0000000000f1', 'c9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('c9700000-0000-0000-0000-00000000007a', 'c9200000-0000-0000-0000-000000000071', 'c9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending');
INSERT INTO public.facility_management_permissions (relationship_id, permission) VALUES
  ('c9700000-0000-0000-0000-0000000000aa', 'maintenance_notices.view'), ('c9700000-0000-0000-0000-0000000000aa', 'maintenance_notices.report'),
  ('c9700000-0000-0000-0000-0000000000aa', 'maintenance_notices.manage'), ('c9700000-0000-0000-0000-0000000000aa', 'inspections.view'),
  ('c9700000-0000-0000-0000-0000000000bb', 'maintenance_notices.view'), ('c9700000-0000-0000-0000-0000000000bb', 'maintenance_notices.report'),
  ('c9700000-0000-0000-0000-0000000000bb', 'maintenance_notices.manage'),
  ('c9700000-0000-0000-0000-0000000000ca', 'maintenance_notices.view'), ('c9700000-0000-0000-0000-0000000000ca', 'criticality.view'),
  ('c9700000-0000-0000-0000-0000000000da', 'maintenance_notices.report'), ('c9700000-0000-0000-0000-0000000000da', 'maintenance_notices.manage'),
  ('c9700000-0000-0000-0000-0000000000ea', 'maintenance_notices.view'), ('c9700000-0000-0000-0000-0000000000ea', 'maintenance_notices.report'),
  ('c9700000-0000-0000-0000-0000000000fa', 'maintenance_notices.view'), ('c9700000-0000-0000-0000-0000000000fa', 'maintenance_notices.report'),
  ('c9700000-0000-0000-0000-00000000007a', 'maintenance_notices.view'), ('c9700000-0000-0000-0000-00000000007a', 'maintenance_notices.manage');
INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES
  ('c9700000-0000-0000-0000-0000000000aa', 'c9300000-0000-0000-0000-000000000011'),
  ('c9700000-0000-0000-0000-0000000000aa', 'c9300000-0000-0000-0000-000000000012'),
  ('c9700000-0000-0000-0000-0000000000aa', 'c9300000-0000-0000-0000-000000000013'),
  ('c9700000-0000-0000-0000-0000000000aa', 'c9300000-0000-0000-0000-000000000014'),
  ('c9700000-0000-0000-0000-0000000000aa', 'c9300000-0000-0000-0000-000000000015'),
  ('c9700000-0000-0000-0000-0000000000aa', 'c9300000-0000-0000-0000-000000000016'),
  ('c9700000-0000-0000-0000-0000000000aa', 'c9300000-0000-0000-0000-000000000018'),
  ('c9700000-0000-0000-0000-0000000000bb', 'c9300000-0000-0000-0000-000000000021'),
  ('c9700000-0000-0000-0000-0000000000ca', 'c9300000-0000-0000-0000-000000000013'),
  ('c9700000-0000-0000-0000-0000000000da', 'c9300000-0000-0000-0000-000000000013'),
  ('c9700000-0000-0000-0000-0000000000ea', 'c9300000-0000-0000-0000-000000000013'),
  ('c9700000-0000-0000-0000-0000000000fa', 'c9300000-0000-0000-0000-000000000013'),
  ('c9700000-0000-0000-0000-00000000007a', 'c9300000-0000-0000-0000-000000000013');
UPDATE public.organization_relationships SET status = 'active' WHERE id::text LIKE 'c9700000-%';
UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'c9700000-0000-0000-0000-0000000000ea';
UPDATE public.organization_members SET is_active = false WHERE id = 'c9300000-0000-0000-0000-000000000018';

-- Inspecciones (A: una respuesta conforme y una no conformidad; B y F: no conformidad).
INSERT INTO public.checklist_templates (id, organization_id, name) VALUES
  ('c9800000-0000-0000-0000-0000000000a1', 'c9200000-0000-0000-0000-0000000000a1', 'Checklist A'),
  ('c9800000-0000-0000-0000-0000000000b1', 'c9200000-0000-0000-0000-0000000000b1', 'Checklist B'),
  ('c9800000-0000-0000-0000-0000000000f1', 'c9200000-0000-0000-0000-0000000000f1', 'Checklist F');
INSERT INTO public.checklist_template_items (id, template_id, question, sequence) VALUES
  ('c9810000-0000-0000-0000-0000000000a1', 'c9800000-0000-0000-0000-0000000000a1', '¿Presión correcta?', 1),
  ('c9810000-0000-0000-0000-0000000000a2', 'c9800000-0000-0000-0000-0000000000a1', '¿Sin fugas?', 2),
  ('c9810000-0000-0000-0000-0000000000b1', 'c9800000-0000-0000-0000-0000000000b1', '¿B ok?', 1),
  ('c9810000-0000-0000-0000-0000000000f1', 'c9800000-0000-0000-0000-0000000000f1', '¿F ok?', 1);
INSERT INTO public.inspection_runs (id, organization_id, template_id, asset_id, status, result, started_at, completed_at) VALUES
  ('c9850000-0000-0000-0000-0000000000a1', 'c9200000-0000-0000-0000-0000000000a1', 'c9800000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a1', 'completed', 'failed', now() - interval '1 hour', now()),
  ('c9850000-0000-0000-0000-0000000000b1', 'c9200000-0000-0000-0000-0000000000b1', 'c9800000-0000-0000-0000-0000000000b1', 'c9400000-0000-0000-0000-0000000000b1', 'completed', 'failed', now() - interval '1 hour', now()),
  ('c9850000-0000-0000-0000-0000000000f1', 'c9200000-0000-0000-0000-0000000000f1', 'c9800000-0000-0000-0000-0000000000f1', 'c9400000-0000-0000-0000-0000000000f1', 'completed', 'failed', now() - interval '1 hour', now());
INSERT INTO public.inspection_run_answers (run_id, template_item_id, item_question, response_label, response_value, is_failure) VALUES
  ('c9850000-0000-0000-0000-0000000000a1', 'c9810000-0000-0000-0000-0000000000a1', '¿Presión correcta?', 'Cumple', 'ok', false),
  ('c9850000-0000-0000-0000-0000000000a1', 'c9810000-0000-0000-0000-0000000000a2', '¿Sin fugas?', 'No cumple', 'fail', true),
  ('c9850000-0000-0000-0000-0000000000b1', 'c9810000-0000-0000-0000-0000000000b1', '¿B ok?', 'No cumple', 'fail', true),
  ('c9850000-0000-0000-0000-0000000000f1', 'c9810000-0000-0000-0000-0000000000f1', '¿F ok?', 'No cumple', 'fail', true);

-- Solicitudes del cliente (módulo NO delegado): una ya vinculada a un aviso
-- convertido y otra para la conversión directa.
INSERT INTO public.requests (id, organization_id, asset_id, request_number, description, asset, location, service_type, deadline, created_by) VALUES
  ('c98e0000-0000-0000-0000-0000000000a1', 'c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a1', 'REQ-NOTICE-A1', 'x', 'Activo A1', 'Sede A', 'correctivo', now() + interval '10 days', 'fixture'),
  ('c98e0000-0000-0000-0000-0000000000a2', 'c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a1', 'REQ-NOTICE-A2', 'x', 'Activo A1', 'Sede A', 'correctivo', now() + interval '10 days', 'fixture');

-- Avisos.
INSERT INTO public.maintenance_notices (
  id, organization_id, notice_number, asset_id, title, description, priority, status, source_type, source_id, source_metadata,
  asset_name_snapshot, asset_code_snapshot, asset_path_snapshot, branch_id_snapshot, branch_name_snapshot,
  reported_by_user_id, responsible_member_id, triage_notes, triaged_by_user_id, triaged_at,
  converted_request_id, converted_by_user_id, converted_at, dismissal_reason, dismissed_by_user_id, dismissed_at
) VALUES
  ('c9900000-0000-0000-0000-0000000000a1', 'c9200000-0000-0000-0000-0000000000a1', 'AV-T-000001', 'c9400000-0000-0000-0000-0000000000a1', 'Aviso abierto', 'd', 'medium', 'open', 'manual', NULL, '{}',
   'Activo A1', 'A-1', 'Sede A / Activo A1', 'c9600000-0000-0000-0000-0000000000a1', 'Sede A',
   'c9100000-0000-0000-0000-000000000003', 'c9300000-0000-0000-0000-000000000002', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-0000000000a2', 'c9200000-0000-0000-0000-0000000000a1', 'AV-T-000002', 'c9400000-0000-0000-0000-0000000000a1', 'Aviso revisado', 'd', 'high', 'triaged', 'manual', NULL, '{}',
   'Activo A1', 'A-1', 'Sede A / Activo A1', 'c9600000-0000-0000-0000-0000000000a1', 'Sede A',
   'c9100000-0000-0000-0000-000000000003', 'c9300000-0000-0000-0000-000000000006', 'Revisado', 'c9100000-0000-0000-0000-000000000001', now(), NULL, NULL, NULL, NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-0000000000a3', 'c9200000-0000-0000-0000-0000000000a1', 'AV-T-000003', 'c9400000-0000-0000-0000-0000000000a1', 'Aviso convertido', 'd', 'high', 'converted', 'manual', NULL, '{}',
   'Activo A1', 'A-1', 'Sede A / Activo A1', 'c9600000-0000-0000-0000-0000000000a1', 'Sede A',
   'c9100000-0000-0000-0000-000000000003', NULL, NULL, NULL, NULL, 'c98e0000-0000-0000-0000-0000000000a1', 'c9100000-0000-0000-0000-000000000001', now(), NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-0000000000a4', 'c9200000-0000-0000-0000-0000000000a1', 'AV-T-000004', 'c9400000-0000-0000-0000-0000000000a1', 'Aviso descartado', 'd', 'low', 'dismissed', 'manual', NULL, '{}',
   'Activo A1', 'A-1', 'Sede A / Activo A1', 'c9600000-0000-0000-0000-0000000000a1', 'Sede A',
   'c9100000-0000-0000-0000-000000000003', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Resuelto en sitio', 'c9100000-0000-0000-0000-000000000006', now()),
  ('c9900000-0000-0000-0000-0000000000a5', 'c9200000-0000-0000-0000-0000000000a1', 'AV-T-000005', 'c9400000-0000-0000-0000-0000000000a1', 'Aviso desde inspección', 'd', 'urgent', 'open', 'inspection_run', 'c9850000-0000-0000-0000-0000000000a1',
   '{"template_name":"Checklist A","item_id":"c9810000-0000-0000-0000-0000000000a2","item_question":"¿Sin fugas?","response_label":"No cumple"}',
   'Activo A1', 'A-1', 'Sede A / Activo A1', 'c9600000-0000-0000-0000-0000000000a1', 'Sede A',
   'c9100000-0000-0000-0000-000000000006', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-0000000000a6', 'c9200000-0000-0000-0000-0000000000a1', 'AV-T-000006', 'c9400000-0000-0000-0000-0000000000a2', 'Aviso para descartar', 'd', 'medium', 'open', 'manual', NULL, '{}',
   'Activo A2', 'A-2', 'Activo A2', NULL, NULL, 'c9100000-0000-0000-0000-000000000003', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-0000000000a7', 'c9200000-0000-0000-0000-0000000000a1', 'AV-T-000007', 'c9400000-0000-0000-0000-0000000000a1', 'Aviso para convertir', 'd', 'medium', 'open', 'manual', NULL, '{}',
   'Activo A1', 'A-1', 'Sede A / Activo A1', 'c9600000-0000-0000-0000-0000000000a1', 'Sede A',
   'c9100000-0000-0000-0000-000000000003', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-0000000000b1', 'c9200000-0000-0000-0000-0000000000b1', 'AV-T-000101', 'c9400000-0000-0000-0000-0000000000b1', 'Aviso B', 'd', 'medium', 'open', 'manual', NULL, '{}',
   'Activo B1', 'B-1', 'Activo B1', NULL, NULL, 'c9100000-0000-0000-0000-000000000031', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-0000000000c1', 'c9200000-0000-0000-0000-0000000000c1', 'AV-T-000201', 'c9400000-0000-0000-0000-0000000000c1', 'Aviso C', 'd', 'medium', 'open', 'manual', NULL, '{}',
   'Activo C1', 'C-1', 'Activo C1', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-0000000000d1', 'c9200000-0000-0000-0000-0000000000d1', 'AV-T-000301', 'c9400000-0000-0000-0000-0000000000d1', 'Aviso D', 'd', 'medium', 'open', 'manual', NULL, '{}',
   'Activo D1', 'D-1', 'Activo D1', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ('c9900000-0000-0000-0000-000000000071', 'c9200000-0000-0000-0000-000000000071', 'AV-T-000401', 'c9400000-0000-0000-0000-000000000071', 'Aviso G', 'd', 'medium', 'open', 'manual', NULL, '{}',
   'Activo G1', 'G-1', 'Activo G1', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
$$;
CREATE FUNCTION pg_temp.notice(p_org uuid, p_id uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT to_jsonb(n) FROM public.get_maintenance_notices(p_org) n WHERE n.id = p_id;
$$;
CREATE FUNCTION pg_temp.backlog_text(p_org uuid) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(to_jsonb(n)::text, '') FROM public.get_maintenance_notices(p_org) n;
$$;

-- -------------------------------------------------------------------------
-- 0. Estructura y grants
-- -------------------------------------------------------------------------
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_view_maintenance_notices(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_view_maintenance_notices(uuid)', 'EXECUTE'), 'can_view_maintenance_notices: internal');
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_create_maintenance_notice(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_create_maintenance_notice(uuid)', 'EXECUTE'), 'can_create_maintenance_notice: internal');
SELECT ok(NOT has_function_privilege('authenticated', 'public.can_triage_maintenance_notice(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.can_triage_maintenance_notice(uuid)', 'EXECUTE'), 'can_triage_maintenance_notice: internal');
SELECT ok(NOT has_function_privilege('authenticated', 'public.sanitize_maintenance_notice_for_delegate(public.maintenance_notices)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.sanitize_maintenance_notice_for_delegate(public.maintenance_notices)', 'EXECUTE'), 'sanitize_maintenance_notice_for_delegate: internal');
SELECT ok(has_function_privilege('authenticated', 'public.get_facility_management_maintenance_notice_assets(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.get_facility_management_maintenance_notice_assets(uuid)', 'EXECUTE'), 'notice asset directory: authenticated only, never anon');
SELECT ok((SELECT bool_and(p.prosecdef AND has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
           FROM pg_proc p WHERE p.oid IN ('public.get_maintenance_notices(uuid)'::regprocedure,
             'public.create_maintenance_notice(uuid,uuid,text,text,text,text,uuid,uuid)'::regprocedure,
             'public.triage_maintenance_notice(uuid,text,text,uuid,boolean)'::regprocedure,
             'public.dismiss_maintenance_notice(uuid,text)'::regprocedure)),
  'replaced RPCs keep SECURITY DEFINER, authenticated EXECUTE and no anon');
SELECT ok((SELECT prosrc ~ 'can_manage_maintenance_notice\(' AND prosrc !~ 'can_triage_maintenance_notice' FROM pg_proc
           WHERE oid = 'public.convert_maintenance_notice(uuid,uuid)'::regprocedure),
  'convert isolation: convert_maintenance_notice still uses the direct-only helper');
SELECT ok((SELECT bool_and(prosrc !~ 'facility_management') FROM pg_proc
           WHERE oid IN ('public.can_manage_maintenance_notice(uuid)'::regprocedure, 'public.can_report_maintenance_notice(uuid)'::regprocedure,
                         'public.get_assignable_planners(uuid)'::regprocedure)),
  'direct helpers and the client planner roster are not extended');
SELECT is((SELECT array_agg(cmd::text) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'maintenance_notices'), ARRAY['SELECT'],
  'maintenance_notices keeps a single SELECT policy (writes only through RPCs)');
SELECT ok(NOT has_table_privilege('authenticated', 'public.maintenance_notices', 'INSERT')
      AND NOT has_table_privilege('authenticated', 'public.maintenance_notices', 'UPDATE')
      AND NOT has_table_privilege('authenticated', 'public.maintenance_notices', 'DELETE'),
  'authenticated has no direct write privilege on maintenance_notices');
SELECT is(
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
     AND (has_table_privilege('anon', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
       OR has_table_privilege('authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))),
  0::bigint, '9C.1H preserved: no meta privileges for anon/authenticated');

SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 1. VER (maintenance_notices.view, owner/admin/manager/technician/requester/viewer)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000011');
SELECT is((SELECT count(*) FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1')), 7::bigint, 'view: FM owner reads the Client A backlog');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000012');
SELECT is((SELECT count(*) FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1')), 7::bigint, 'view: FM admin reads the Client A backlog');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT is((SELECT count(*) FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1')), 7::bigint, 'view: FM manager reads the Client A backlog');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000014');
SELECT is((SELECT count(*) FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1')), 7::bigint, 'view: FM technician reads the Client A backlog');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000015');
SELECT is((SELECT count(*) FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1')), 7::bigint, 'view: FM requester reads the Client A backlog');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000016');
SELECT is((SELECT count(*) FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1')), 7::bigint, 'view: FM viewer reads the Client A backlog (read-only)');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000017');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'view: unassigned FM manager is rejected');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a2', 'x', 'd') $$, 'P0001', NULL, 'report: unassigned FM manager is rejected');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', 'high') $$, 'P0001', NULL, 'manage: unassigned FM manager is rejected');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_maintenance_notice_assets('c9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'directory: unassigned FM manager is rejected');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000018');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'view: inactive FM membership is rejected');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000021');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'view: FM B cannot read Client A');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000b1') $$, 'P0001', NULL, 'view: FM A cannot read Client B');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000d1') $$, 'P0001', NULL, 'view: report + manage without view => rejected');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000e1') $$, 'P0001', NULL, 'view: suspended relationship => rejected');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000041');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'view: outsider is rejected');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000031');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'view: another client owner is rejected');

-- -------------------------------------------------------------------------
-- 2. Minimización de la respuesta delegada
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a5')->'source_id', 'null'::jsonb, 'sanitize: source_id (raw inspection run id) is hidden');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a5')->'source_metadata',
  '{"template_name":"Checklist A","item_question":"¿Sin fugas?","response_label":"No cumple"}'::jsonb,
  'sanitize: the frozen source snapshot stays, without the raw item id');
SELECT ok((SELECT n->>'status' = 'converted' AND n->'converted_request_id' = 'null'::jsonb AND n->'converted_request_number' = 'null'::jsonb AND n->>'converted_at' IS NOT NULL
           FROM pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a3') n),
  'sanitize: a converted notice keeps its status/date but hides the request id and number');
SELECT ok((SELECT bool_and(n.reported_by_user_id IS NULL AND n.responsible_member_id IS NULL) FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1') n),
  'sanitize: no user or client-membership ids reach the FM');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a1')->>'responsible_name', 'Mario Cliente', 'names: a stored display name is shown');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a2')->>'responsible_name', 'Asignado por el cliente',
  'names: a responsible without display name => generic label');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a5')->'reported_by_name', 'null'::jsonb, 'names: reporter without display name => NULL');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a4')->'dismissed_by_name', 'null'::jsonb, 'names: dismisser without display name => NULL');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a3')->>'converted_by_name', 'Olga Cliente', 'names: converter display name is kept');
SELECT ok(pg_temp.backlog_text('c9200000-0000-0000-0000-0000000000a1') !~ '(@|ca-noname|c9850000|c98e0000|c9810000|REQ-NOTICE)',
  'sanitize: no email, email prefix, inspection id or request id/number anywhere in the delegated backlog');
SELECT ok((SELECT n->>'asset_name_snapshot' = 'Activo A1' AND n->>'branch_name_snapshot' = 'Sede A' AND n->>'asset_path_snapshot' = 'Sede A / Activo A1'
           FROM pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a1') n),
  'sanitize: asset and branch snapshots stay');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000001');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a5')->>'source_id', 'c9850000-0000-0000-0000-0000000000a1', 'direct: source_id unchanged');
SELECT ok((SELECT n->>'converted_request_id' = 'c98e0000-0000-0000-0000-0000000000a1' AND n->>'converted_request_number' = 'REQ-NOTICE-A1'
           FROM pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a3') n), 'direct: request id and number unchanged');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a1')->>'reported_by_user_id', 'c9100000-0000-0000-0000-000000000003', 'direct: reporter id unchanged');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a2')->>'responsible_name', 'ca-noname', 'direct: historic name fallback unchanged');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a5')->'source_metadata'->>'item_id', 'c9810000-0000-0000-0000-0000000000a2', 'direct: source metadata unchanged');

-- -------------------------------------------------------------------------
-- 3. Criticidad viva condicionada a criticality.view
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT ok((SELECT bool_and(asset_current_criticality IS NULL) FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000a1')),
  'criticality: hidden without criticality.view');
SELECT is((SELECT asset_current_criticality FROM public.get_maintenance_notices('c9200000-0000-0000-0000-0000000000c1')), 'high', 'criticality: shown with an effective criticality.view');
SELECT throws_ok($$ SELECT public.get_criticality_matrix('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'criticality: notices.view does not open the #criticality module');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000005');
SELECT is(pg_temp.notice('c9200000-0000-0000-0000-0000000000a1', 'c9900000-0000-0000-0000-0000000000a1')->>'asset_current_criticality', 'high', 'criticality (direct): client viewer unchanged');

-- -------------------------------------------------------------------------
-- 4. REPORTAR manual (view + report, owner/admin/manager/technician/requester)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000011');
SELECT lives_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a2', 'FM owner', 'd') $$, 'report: FM owner creates a notice');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000012');
SELECT lives_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a2', 'FM admin', 'd') $$, 'report: FM admin creates a notice');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000014');
SELECT lives_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a2', 'FM technician', 'd') $$, 'report: FM technician creates a notice');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000015');
SELECT lives_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a2', 'FM requester', 'd') $$, 'report: FM requester creates a notice');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT ok((SELECT n.reported_by_user_id IS NULL AND n.responsible_member_id IS NULL AND n.source_id IS NULL
           FROM public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a1', 'FM manager', 'd', 'high') n),
  'report: FM manager creates a notice and the returned row is minimized');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000016');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a2', 'x', 'd') $$, 'P0001', NULL, 'report: FM viewer cannot report');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000d1', 'c9400000-0000-0000-0000-0000000000d1', 'x', 'd') $$, 'P0001', NULL, 'report: report without view cannot report');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-000000000071', 'c9400000-0000-0000-0000-000000000071', 'x', 'd') $$, 'P0001', NULL, 'report: view + manage without report cannot report');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000b1', 'x', 'd') $$, 'P0001', 'El activo no pertenece a esta organización', 'report cross-tenant: a Client B asset is rejected');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'x', 'd') $$, 'P0001', 'El activo no existe', 'report: an arbitrary asset id is rejected');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000b1', 'c9400000-0000-0000-0000-0000000000b1', 'x', 'd') $$, 'P0001', NULL, 'report cross-tenant: FM A cannot report on Client B');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a9', 'x', 'd') $$, '22023', 'Un activo archivado no admite avisos nuevos', 'report: FM cannot report manually on an archived asset');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000003');
SELECT lives_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a9', 'Directo archivado', 'd') $$, 'report (direct): client technician keeps the historic semantics');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000005');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a2', 'x', 'd') $$, 'P0001', NULL, 'report (direct): client viewer still cannot report');
RESET ROLE;
SELECT results_eq(
  $$ SELECT organization_id::text, source_type, source_id IS NULL, asset_name_snapshot, branch_name_snapshot, reported_by_user_id::text, notice_number ~ '^AV-[0-9]{4}-[0-9]{6}$'
     FROM public.maintenance_notices WHERE title = 'FM manager' $$,
  $$ VALUES ('c9200000-0000-0000-0000-0000000000a1'::text, 'manual'::text, true, 'Activo A1'::text, 'Sede A'::text, 'c9100000-0000-0000-0000-000000000013'::text, true) $$,
  'report: server-side correlative, snapshots and real reporter; no client membership created');
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'c9200000-0000-0000-0000-0000000000a1'), 6::bigint, 'report: no FM membership was created inside the client');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 5. REPORTAR desde una no conformidad de inspección
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT lives_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a1', 'Fuga', 'd', 'high', 'inspection_run',
  'c9850000-0000-0000-0000-0000000000a1', 'c9810000-0000-0000-0000-0000000000a2') $$, 'inspection: FM (notices view+report + inspections.view) reports from a failure');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a1', 'x', 'd', 'high', 'inspection_run',
  'c9850000-0000-0000-0000-0000000000a1', 'c9810000-0000-0000-0000-0000000000a1') $$, 'P0001', 'Solo se puede crear un aviso desde una respuesta marcada como no conformidad',
  'inspection: a conforming answer is rejected');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a1', 'x', 'd', 'high', 'inspection_run',
  'c9850000-0000-0000-0000-0000000000b1', 'c9810000-0000-0000-0000-0000000000b1') $$, 'P0001', 'La inspección no pertenece a esta organización', 'inspection cross-tenant: a Client B run is rejected');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000f1', 'c9400000-0000-0000-0000-0000000000f1', 'x', 'd', 'high', 'inspection_run',
  'c9850000-0000-0000-0000-0000000000f1', 'c9810000-0000-0000-0000-0000000000f1') $$, '42501', 'Not authorized to report from this inspection', 'inspection: without inspections.view => rejected');
SELECT lives_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000f1', 'c9400000-0000-0000-0000-0000000000f1', 'Manual F', 'd') $$, 'inspection: the same FM still reports manually there');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000015');
SELECT throws_ok($$ SELECT public.create_maintenance_notice('c9200000-0000-0000-0000-0000000000a1', 'c9400000-0000-0000-0000-0000000000a1', 'x', 'd', 'high', 'inspection_run',
  'c9850000-0000-0000-0000-0000000000a1', 'c9810000-0000-0000-0000-0000000000a2') $$, '42501', 'Not authorized to report from this inspection', 'inspection: an FM requester (no effective inspections.view) is rejected');
RESET ROLE;
SELECT is((SELECT source_metadata - 'item_id' FROM public.maintenance_notices WHERE title = 'Fuga'),
  '{"template_name":"Checklist A","item_question":"¿Sin fugas?","response_label":"No cumple"}'::jsonb, 'inspection: frozen source metadata resolved by the server');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 6. GESTIONAR (view + manage, owner/admin/manager)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000011');
SELECT lives_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', 'high') $$, 'manage: FM owner changes the priority');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000012');
SELECT lives_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', NULL, 'Notas del admin FM') $$, 'manage: FM admin writes triage notes');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT ok((SELECT n.responsible_member_id IS NULL AND n.triaged_by_user_id IS NULL AND n.reported_by_user_id IS NULL
           FROM public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', 'urgent', 'Revisado por FM') n),
  'manage: FM manager triages and the returned row is minimized');
SELECT lives_ok($$ SELECT public.dismiss_maintenance_notice('c9900000-0000-0000-0000-0000000000a6', 'Duplicado') $$, 'manage: FM manager dismisses with a reason');
SELECT throws_ok($$ SELECT public.dismiss_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', '  ') $$, 'P0001', 'El motivo del descarte es obligatorio', 'manage: a reason is still required');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a4', 'high') $$, 'P0001', NULL, 'manage: historic state rule (a dismissed notice cannot be triaged)');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000b1', 'high') $$, 'P0001', NULL, 'manage cross-tenant: a Client B notice cannot be triaged');
SELECT throws_ok($$ SELECT public.dismiss_maintenance_notice('c9900000-0000-0000-0000-0000000000b1', 'x') $$, 'P0001', NULL, 'manage cross-tenant: a Client B notice cannot be dismissed');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000d1', 'high') $$, 'P0001', NULL, 'manage: manage without view => rejected');
SELECT lives_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-000000000071', 'high') $$, 'manage: view + manage without report still manages');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', 'high') $$, 'P0001', NULL, 'manage: FM technician cannot triage');
SELECT throws_ok($$ SELECT public.dismiss_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', 'x') $$, 'P0001', NULL, 'manage: FM technician cannot dismiss');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000015');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', 'high') $$, 'P0001', NULL, 'manage: FM requester cannot triage');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000016');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', 'high') $$, 'P0001', NULL, 'manage: FM viewer cannot triage');
RESET ROLE;
SELECT results_eq(
  $$ SELECT priority, triage_notes, status, responsible_member_id::text FROM public.maintenance_notices WHERE id = 'c9900000-0000-0000-0000-0000000000a1' $$,
  $$ VALUES ('urgent'::text, 'Revisado por FM'::text, 'triaged'::text, 'c9300000-0000-0000-0000-000000000002'::text) $$,
  'manage: priority/notes persisted and the client responsible preserved');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 7. Responsable del aviso (client-owned)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', NULL, NULL, 'c9300000-0000-0000-0000-000000000001') $$,
  '42501', 'The notice responsible is assigned by the client', 'responsible: FM cannot assign a client member');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', NULL, NULL, NULL, true) $$,
  '42501', 'The notice responsible is assigned by the client', 'responsible: FM cannot clear the responsible');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', NULL, NULL, 'c9300000-0000-0000-0000-000000000013') $$,
  '42501', 'The notice responsible is assigned by the client', 'responsible: FM cannot point it to its own FM membership');
SELECT throws_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', NULL, NULL, 'c9300000-0000-0000-0000-000000000002') $$,
  '42501', 'The notice responsible is assigned by the client', 'responsible: FM cannot resend a responsible UUID even if unchanged');
SELECT throws_ok($$ SELECT * FROM public.get_assignable_planners('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'responsible: FM does not get the client planner roster');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', NULL, NULL, 'c9300000-0000-0000-0000-000000000001') $$, 'responsible (direct): client manager still assigns');
SELECT lives_ok($$ SELECT public.triage_maintenance_notice('c9900000-0000-0000-0000-0000000000a1', NULL, NULL, NULL, true) $$, 'responsible (direct): client manager still clears');
RESET ROLE;
SELECT is((SELECT responsible_member_id FROM public.maintenance_notices WHERE id = 'c9900000-0000-0000-0000-0000000000a1'), NULL, 'responsible (direct): the client change persisted');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 8. Convertir en Solicitud queda fuera (9C.4)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000011');
SELECT throws_ok($$ SELECT public.convert_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', 'c98e0000-0000-0000-0000-0000000000a2') $$,
  'P0001', 'Not authorized to convert maintenance notices for this organization', 'convert: FM owner with view + manage cannot convert');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.convert_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', 'c98e0000-0000-0000-0000-0000000000a2') $$,
  'P0001', 'Not authorized to convert maintenance notices for this organization', 'convert: FM manager with view + manage cannot convert');
SELECT is((SELECT count(*) FROM public.requests WHERE organization_id = 'c9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'convert: the FM reads no client requests');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT public.convert_maintenance_notice('c9900000-0000-0000-0000-0000000000a7', 'c98e0000-0000-0000-0000-0000000000a2') $$, 'convert (direct): client manager still converts');

-- -------------------------------------------------------------------------
-- 9. Directorio mínimo de activos para reportar
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000015');
SELECT is((SELECT array_agg(code ORDER BY code) FROM public.get_facility_management_maintenance_notice_assets('c9200000-0000-0000-0000-0000000000a1')), ARRAY['A-1', 'A-2'],
  'directory: an FM reporter lists only the non-archived Client A assets');
SELECT ok((SELECT string_agg(to_jsonb(a)::text, '') FROM public.get_facility_management_maintenance_notice_assets('c9200000-0000-0000-0000-0000000000a1') a) !~ 'secret',
  'directory: no metadata, technical data or branch email');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000016');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_maintenance_notice_assets('c9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'directory: FM viewer (no report) is rejected');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_maintenance_notice_assets('c9200000-0000-0000-0000-0000000000d1') $$, '42501', NULL, 'directory: report without view is rejected');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_maintenance_notice_assets('c9200000-0000-0000-0000-0000000000b1') $$, '42501', NULL, 'directory: another client stays closed');
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_maintenance_notice_assets('c9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'directory: delegated-only (direct members keep their picker)');
RESET ROLE;
SELECT is(pg_get_function_result('public.get_facility_management_maintenance_notice_assets(uuid)'::regprocedure), 'TABLE(id uuid, name text, code text, status text)',
  'directory: returns only id/name/code/status');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 10. Sin acceso cross-module nuevo
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT * FROM public.get_asset_traffic_light('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: traffic light stays closed');
SELECT throws_ok($$ SELECT * FROM public.get_asset_integrated_history('c9400000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: integrated history stays closed');
SELECT throws_ok($$ SELECT * FROM public.get_inventory_catalog('c9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: inventory stays closed');
SELECT throws_ok($$ SELECT public.authorize_asset_file_access('c9400000-0000-0000-0000-0000000000a1', 'read') $$, 'P0001', NULL, 'no leak: R2 stays closed');
SELECT is((SELECT count(*) FROM public.work_orders WHERE client_organization_id = 'c9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'no leak: no client work orders');
SELECT is((SELECT count(*) FROM public.assets WHERE organization_id = 'c9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'no leak: notices do not imply assets.view');
SELECT is((SELECT count(*) FROM public.maintenance_notices WHERE organization_id = 'c9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'no leak: the table stays reachable only through the RPCs');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
