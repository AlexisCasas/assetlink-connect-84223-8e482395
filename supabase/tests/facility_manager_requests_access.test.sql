-- Fase 1 · Punto 9C.4 — acceso operativo de Facility Manager a Solicitudes
-- (…_facility_manager_requests_access.sql).
-- Se ejecuta con: supabase test db --local
--
-- Cada intento corre como `authenticated` con un auth.uid() sintético.
-- Errores: P0001 = regla histórica (RAISE sin código); 42501 / 22023 / 55000
-- = reglas nuevas del modo delegado; 42501 también = RLS / sin EXECUTE.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(224);

-- -------------------------------------------------------------------------
-- Fixture (sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('d9100000-0000-0000-0000-000000000001', 'ca-owner@fm-requests.test', '{"name":"Olga Cliente"}'),
  ('d9100000-0000-0000-0000-000000000002', 'ca-manager@fm-requests.test', '{"name":"Mario Cliente"}'),
  ('d9100000-0000-0000-0000-000000000003', 'ca-technician@fm-requests.test', '{"name":"Tomas Cliente"}'),
  ('d9100000-0000-0000-0000-000000000004', 'ca-requester@fm-requests.test', '{"name":"Rita Cliente"}'),
  ('d9100000-0000-0000-0000-000000000006', 'ca-noname@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000011', 'fa-owner@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000012', 'fa-admin@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000013', 'fa-manager@fm-requests.test', '{"name":"Fabio Gestor"}'),
  ('d9100000-0000-0000-0000-000000000014', 'fa-technician@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000015', 'fa-requester@fm-requests.test', '{"name":"Rosa FM"}'),
  ('d9100000-0000-0000-0000-000000000016', 'fa-viewer@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000017', 'fa-quote-manager@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000018', 'fa-operator@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000019', 'fa-manager-unassigned@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-00000000001a', 'fa-requester-inactive@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000021', 'fb-manager@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000031', 'cb-owner@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000041', 'outsider@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000051', 'p1-owner@fm-requests.test', '{}'),
  ('d9100000-0000-0000-0000-000000000052', 's1-owner@fm-requests.test', '{}');

INSERT INTO public.organizations (id, name, organization_type) VALUES
  ('d9200000-0000-0000-0000-0000000000a1', 'Client A', 'client_company'),
  ('d9200000-0000-0000-0000-0000000000b1', 'Client B', 'client_company'),
  ('d9200000-0000-0000-0000-0000000000c1', 'Client V (solo view)', 'client_company'),
  ('d9200000-0000-0000-0000-0000000000d1', 'Client M (view + manage, sin create)', 'client_company'),
  ('d9200000-0000-0000-0000-0000000000e1', 'Client N (create + manage, sin view)', 'client_company'),
  ('d9200000-0000-0000-0000-0000000000f1', 'Client S (suspendida)', 'client_company'),
  ('d9200000-0000-0000-0000-0000000000fa', 'FM A', 'facility_manager'),
  ('d9200000-0000-0000-0000-0000000000fb', 'FM B', 'facility_manager'),
  ('d9200000-0000-0000-0000-000000000091', 'Proveedor P1', 'provider_company'),
  ('d9200000-0000-0000-0000-000000000092', 'Proveedor P2 (pendiente)', 'provider_company'),
  ('d9200000-0000-0000-0000-000000000093', 'Subcontratista S1', 'subcontractor_company');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('d9300000-0000-0000-0000-000000000001', 'd9200000-0000-0000-0000-0000000000a1', 'd9100000-0000-0000-0000-000000000001', 'owner', true),
  ('d9300000-0000-0000-0000-000000000002', 'd9200000-0000-0000-0000-0000000000a1', 'd9100000-0000-0000-0000-000000000002', 'manager', true),
  ('d9300000-0000-0000-0000-000000000003', 'd9200000-0000-0000-0000-0000000000a1', 'd9100000-0000-0000-0000-000000000003', 'technician', true),
  ('d9300000-0000-0000-0000-000000000004', 'd9200000-0000-0000-0000-0000000000a1', 'd9100000-0000-0000-0000-000000000004', 'requester', true),
  ('d9300000-0000-0000-0000-000000000006', 'd9200000-0000-0000-0000-0000000000a1', 'd9100000-0000-0000-0000-000000000006', 'technician', true),
  ('d9300000-0000-0000-0000-000000000011', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000011', 'owner', true),
  ('d9300000-0000-0000-0000-000000000012', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000012', 'admin', true),
  ('d9300000-0000-0000-0000-000000000013', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000013', 'manager', true),
  ('d9300000-0000-0000-0000-000000000014', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000014', 'technician', true),
  ('d9300000-0000-0000-0000-000000000015', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000015', 'requester', true),
  ('d9300000-0000-0000-0000-000000000016', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000016', 'viewer', true),
  ('d9300000-0000-0000-0000-000000000017', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000017', 'quote_manager', true),
  ('d9300000-0000-0000-0000-000000000018', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000018', 'operator', true),
  ('d9300000-0000-0000-0000-000000000019', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-000000000019', 'manager', true),
  ('d9300000-0000-0000-0000-00000000001a', 'd9200000-0000-0000-0000-0000000000fa', 'd9100000-0000-0000-0000-00000000001a', 'requester', true),
  ('d9300000-0000-0000-0000-000000000021', 'd9200000-0000-0000-0000-0000000000fb', 'd9100000-0000-0000-0000-000000000021', 'manager', true),
  ('d9300000-0000-0000-0000-000000000031', 'd9200000-0000-0000-0000-0000000000b1', 'd9100000-0000-0000-0000-000000000031', 'owner', true),
  ('d9300000-0000-0000-0000-000000000051', 'd9200000-0000-0000-0000-000000000091', 'd9100000-0000-0000-0000-000000000051', 'owner', true),
  ('d9300000-0000-0000-0000-000000000052', 'd9200000-0000-0000-0000-000000000093', 'd9100000-0000-0000-0000-000000000052', 'owner', true);

INSERT INTO public.client_branches (id, organization_id, client_email, name, city, site, address, is_active) VALUES
  ('d9600000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'secret@client-a.test', 'Sede A', 'Lima', 'S1', 'Av. A 1', true),
  ('d9600000-0000-0000-0000-0000000000a2', 'd9200000-0000-0000-0000-0000000000a1', 'secret@client-a.test', 'Sede A cerrada', 'Lima', 'S2', 'Av. A 2', false),
  ('d9600000-0000-0000-0000-0000000000b1', 'd9200000-0000-0000-0000-0000000000b1', 'secret@client-b.test', 'Sede B', 'Cusco', 'SB', 'Av. B 1', true);
INSERT INTO public.assets (id, organization_id, code, name, node_type, parent_asset_id, branch_id, status) VALUES
  ('d9400000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'A-1', 'Activo A1', 'equipment', NULL, 'd9600000-0000-0000-0000-0000000000a1', 'active'),
  ('d9400000-0000-0000-0000-0000000000b1', 'd9200000-0000-0000-0000-0000000000b1', 'B-1', 'Activo B1', 'equipment', NULL, NULL, 'active'),
  ('d9400000-0000-0000-0000-0000000000c1', 'd9200000-0000-0000-0000-0000000000c1', 'V-1', 'Activo V1', 'equipment', NULL, NULL, 'active');
INSERT INTO public.assets (id, organization_id, code, name, node_type, parent_asset_id, branch_id, status) VALUES
  ('d9400000-0000-0000-0000-0000000000a2', 'd9200000-0000-0000-0000-0000000000a1', 'A-2', 'Activo A2', 'component', 'd9400000-0000-0000-0000-0000000000a1', NULL, 'active'),
  ('d9400000-0000-0000-0000-0000000000a9', 'd9200000-0000-0000-0000-0000000000a1', 'A-9', 'Activo A9 archivado', 'equipment', NULL, NULL, 'archived');

INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status) VALUES
  ('d9700000-0000-0000-0000-0000000000aa', 'd9200000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('d9700000-0000-0000-0000-0000000000bb', 'd9200000-0000-0000-0000-0000000000b1', 'd9200000-0000-0000-0000-0000000000fb', 'facility_management', 'pending'),
  ('d9700000-0000-0000-0000-0000000000ca', 'd9200000-0000-0000-0000-0000000000c1', 'd9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('d9700000-0000-0000-0000-0000000000da', 'd9200000-0000-0000-0000-0000000000d1', 'd9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('d9700000-0000-0000-0000-0000000000ea', 'd9200000-0000-0000-0000-0000000000e1', 'd9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('d9700000-0000-0000-0000-0000000000fa', 'd9200000-0000-0000-0000-0000000000f1', 'd9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('d9700000-0000-0000-0000-000000000091', 'd9200000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-000000000091', 'provider', 'pending'),
  ('d9700000-0000-0000-0000-000000000092', 'd9200000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-000000000092', 'provider', 'pending'),
  ('d9700000-0000-0000-0000-000000000093', 'd9200000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-000000000093', 'subcontracting', 'pending');
INSERT INTO public.facility_management_permissions (relationship_id, permission)
SELECT 'd9700000-0000-0000-0000-0000000000aa'::uuid, p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'requests.create', 'requests.manage', 'maintenance_notices.view', 'maintenance_notices.manage',
                  'preventive_maintenance.view', 'preventive_maintenance.manage', 'inspections.view', 'inspections.manage']) p
UNION ALL SELECT 'd9700000-0000-0000-0000-0000000000bb', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'requests.create', 'requests.manage']) p
UNION ALL SELECT 'd9700000-0000-0000-0000-0000000000ca', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'maintenance_notices.view', 'maintenance_notices.manage', 'preventive_maintenance.view', 'preventive_maintenance.manage']) p
UNION ALL SELECT 'd9700000-0000-0000-0000-0000000000da', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'requests.manage']) p
UNION ALL SELECT 'd9700000-0000-0000-0000-0000000000ea', p::public.facility_management_permission
FROM unnest(ARRAY['requests.create', 'requests.manage']) p
UNION ALL SELECT 'd9700000-0000-0000-0000-0000000000fa', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'requests.create', 'requests.manage']) p;
INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id)
SELECT 'd9700000-0000-0000-0000-0000000000aa'::uuid, m::uuid FROM unnest(ARRAY[
  'd9300000-0000-0000-0000-000000000011', 'd9300000-0000-0000-0000-000000000012', 'd9300000-0000-0000-0000-000000000013',
  'd9300000-0000-0000-0000-000000000014', 'd9300000-0000-0000-0000-000000000015', 'd9300000-0000-0000-0000-000000000016',
  'd9300000-0000-0000-0000-000000000017', 'd9300000-0000-0000-0000-000000000018', 'd9300000-0000-0000-0000-00000000001a']) m
UNION ALL SELECT 'd9700000-0000-0000-0000-0000000000bb', 'd9300000-0000-0000-0000-000000000021'
UNION ALL SELECT r::uuid, 'd9300000-0000-0000-0000-000000000013' FROM unnest(ARRAY[
  'd9700000-0000-0000-0000-0000000000ca', 'd9700000-0000-0000-0000-0000000000da',
  'd9700000-0000-0000-0000-0000000000ea', 'd9700000-0000-0000-0000-0000000000fa']) r;
UPDATE public.organization_relationships SET status = 'active' WHERE id::text LIKE 'd9700000-%' AND id <> 'd9700000-0000-0000-0000-000000000092';
UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'd9700000-0000-0000-0000-0000000000fa';
UPDATE public.organization_members SET is_active = false WHERE id = 'd9300000-0000-0000-0000-00000000001a';

-- Solicitudes del cliente.
INSERT INTO public.requests (
  id, organization_id, request_number, title, description, asset, asset_id, location, service_type, deadline, status,
  request_type, is_public, created_by, created_by_user_id, created_by_name, created_by_email,
  coordination_contact_member_id, coordination_contact_name, coordination_contact_email,
  requires_visit, visit_schedule_mode, visit_contact_member_id, internal_responsible_member_id,
  branch_id, image_urls, document_urls
) VALUES
  ('d98e0000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'REQ-9C4-A1', 'Privada', 'd', 'Activo A1', 'd9400000-0000-0000-0000-0000000000a1', 'Lima - S1', 'correctivo', now() + interval '10 days', 'sent',
   'external', false, 'ca-owner@fm-requests.test', 'd9100000-0000-0000-0000-000000000001', 'ca-owner', 'ca-owner@fm-requests.test',
   'd9300000-0000-0000-0000-000000000002', 'Mario Cliente', 'ca-manager@fm-requests.test',
   true, 'to_schedule', 'd9300000-0000-0000-0000-000000000002', NULL,
   'd9600000-0000-0000-0000-0000000000a1', ARRAY['https://secret.test/img.png'], ARRAY['https://secret.test/doc.pdf']),
  ('d98e0000-0000-0000-0000-0000000000a2', 'd9200000-0000-0000-0000-0000000000a1', 'REQ-9C4-A2', 'Interna', 'd', 'Activo A1', 'd9400000-0000-0000-0000-0000000000a1', 'Lima - S1', 'correctivo', now() + interval '10 days', 'sent',
   'internal', false, 'ca-owner@fm-requests.test', 'd9100000-0000-0000-0000-000000000001', 'Olga Cliente', 'ca-owner@fm-requests.test',
   'd9300000-0000-0000-0000-000000000001', 'ca-owner', 'ca-owner@fm-requests.test',
   false, NULL, NULL, 'd9300000-0000-0000-0000-000000000003',
   'd9600000-0000-0000-0000-0000000000a1', NULL, NULL),
  ('d98e0000-0000-0000-0000-0000000000a3', 'd9200000-0000-0000-0000-0000000000a1', 'REQ-9C4-A3', 'Borrador del cliente', 'd', 'Activo A1', 'd9400000-0000-0000-0000-0000000000a1', 'Lima - S1', 'correctivo', now() + interval '10 days', 'draft',
   'external', false, 'ca-owner@fm-requests.test', 'd9100000-0000-0000-0000-000000000001', 'Olga Cliente', 'ca-owner@fm-requests.test',
   NULL, NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL),
  ('d98e0000-0000-0000-0000-0000000000a4', 'd9200000-0000-0000-0000-0000000000a1', 'REQ-9C4-A4', 'Cotizada', 'd', 'Activo A1', 'd9400000-0000-0000-0000-0000000000a1', 'Lima - S1', 'correctivo', now() + interval '10 days', 'quoted',
   'external', true, 'fixture', NULL, NULL, NULL, NULL, NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL),
  ('d98e0000-0000-0000-0000-0000000000a5', 'd9200000-0000-0000-0000-0000000000a1', 'REQ-9C4-A5', 'Anulada', 'd', 'Activo A1', NULL, 'Lima - S1', 'correctivo', now() + interval '10 days', 'anulado',
   'external', true, 'fixture', NULL, NULL, NULL, NULL, NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL),
  ('d98e0000-0000-0000-0000-0000000000a6', 'd9200000-0000-0000-0000-0000000000a1', 'REQ-9C4-A6', 'Con adjuntos', 'd', 'Activo A1', NULL, 'Lima - S1', 'correctivo', now() + interval '10 days', 'sent',
   'external', true, 'fixture', NULL, NULL, NULL, NULL, NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL),
  ('d98e0000-0000-0000-0000-0000000000b1', 'd9200000-0000-0000-0000-0000000000b1', 'REQ-9C4-B1', 'Cliente B', 'd', 'Activo B1', NULL, 'Cusco', 'correctivo', now() + interval '10 days', 'sent',
   'external', true, 'fixture', NULL, NULL, NULL, NULL, NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL),
  ('d98e0000-0000-0000-0000-0000000000c1', 'd9200000-0000-0000-0000-0000000000c1', 'REQ-9C4-C1', 'Cliente V', 'd', 'Activo V1', 'd9400000-0000-0000-0000-0000000000c1', 'x', 'correctivo', now() + interval '10 days', 'sent',
   'external', true, 'fixture', NULL, NULL, NULL, NULL, NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL),
  ('d98e0000-0000-0000-0000-0000000000d1', 'd9200000-0000-0000-0000-0000000000d1', 'REQ-9C4-D1', 'Cliente M', 'd', 'x', NULL, 'x', 'correctivo', now() + interval '10 days', 'sent',
   'external', true, 'fixture', NULL, NULL, NULL, NULL, NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.requests (id, organization_id, request_number, title, description, asset, location, service_type, deadline, status, request_type, is_public, created_by) VALUES
  ('d98e0000-0000-0000-0000-0000000000a7', 'd9200000-0000-0000-0000-0000000000a1', 'REQ-9C4-A7', 'Privada con adjuntos', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', false, 'fixture');
INSERT INTO public.request_details (request_id, activities, responsible_user, attachment_urls) VALUES
  ('d98e0000-0000-0000-0000-0000000000a7', 'Actividad A7', NULL, ARRAY['https://attach.test/a7.pdf']);
INSERT INTO public.request_provider_access (request_id, provider_organization_id, access_type, status) VALUES
  ('d98e0000-0000-0000-0000-0000000000a7', 'd9200000-0000-0000-0000-000000000091', 'invited', 'active');
INSERT INTO public.request_details (request_id, activities, responsible_user, attachment_urls) VALUES
  ('d98e0000-0000-0000-0000-0000000000a1', 'Actividad A1', 'Encargado X', NULL),
  ('d98e0000-0000-0000-0000-0000000000a6', 'Actividad A6', NULL, ARRAY['https://attach.test/secret.pdf']);
INSERT INTO public.request_provider_access (request_id, provider_organization_id, access_type, status) VALUES
  ('d98e0000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-000000000091', 'invited', 'active');
INSERT INTO public.quotes (request_id, provider_organization_id, amount, description, status) VALUES
  ('d98e0000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-000000000091', 100, 'Cotización P1', 'submitted');

-- Avisos.
INSERT INTO public.maintenance_notices (
  id, organization_id, notice_number, asset_id, title, description, priority, status, source_type,
  asset_name_snapshot, asset_code_snapshot, asset_path_snapshot, reported_by_user_id, responsible_member_id,
  converted_request_id, converted_by_user_id, converted_at
) VALUES
  ('d9900000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'AV-9C4-001', 'd9400000-0000-0000-0000-0000000000a1', 'Aviso a convertir', 'd', 'high', 'open', 'manual',
   'Activo A1', 'A-1', 'Activo A1', 'd9100000-0000-0000-0000-000000000003', 'd9300000-0000-0000-0000-000000000002', NULL, NULL, NULL),
  ('d9900000-0000-0000-0000-0000000000a2', 'd9200000-0000-0000-0000-0000000000a1', 'AV-9C4-002', 'd9400000-0000-0000-0000-0000000000a1', 'Aviso abierto', 'd', 'medium', 'open', 'manual',
   'Activo A1', 'A-1', 'Activo A1', 'd9100000-0000-0000-0000-000000000003', NULL, NULL, NULL, NULL),
  ('d9900000-0000-0000-0000-0000000000a3', 'd9200000-0000-0000-0000-0000000000a1', 'AV-9C4-003', 'd9400000-0000-0000-0000-0000000000a1', 'Convertido a un borrador del cliente', 'd', 'medium', 'converted', 'manual',
   'Activo A1', 'A-1', 'Activo A1', 'd9100000-0000-0000-0000-000000000003', NULL, 'd98e0000-0000-0000-0000-0000000000a3', 'd9100000-0000-0000-0000-000000000001', now()),
  ('d9900000-0000-0000-0000-0000000000c1', 'd9200000-0000-0000-0000-0000000000c1', 'AV-9C4-101', 'd9400000-0000-0000-0000-0000000000c1', 'Aviso V', 'd', 'medium', 'open', 'manual',
   'Activo V1', 'V-1', 'Activo V1', NULL, NULL, NULL, NULL, NULL);

-- Inspecciones en A: responsable con nombre, sin nombre y sin responsable.
INSERT INTO public.checklist_templates (id, organization_id, name) VALUES ('d9b00000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'Checklist bomba');
INSERT INTO public.checklist_template_items (id, template_id, question, sequence, is_required) VALUES
  ('d9b10000-0000-0000-0000-0000000000a1', 'd9b00000-0000-0000-0000-0000000000a1', '¿Sin fugas?', 1, true);
INSERT INTO public.checklist_template_response_options (id, template_id, label, value, sequence) VALUES
  ('d9b20000-0000-0000-0000-0000000000a1', 'd9b00000-0000-0000-0000-0000000000a1', 'Cumple', 'ok', 1);
INSERT INTO public.inspection_plans (id, organization_id, template_id, asset_id, responsible_member_id, title, frequency, next_due_at) VALUES
  ('d9b30000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'd9b00000-0000-0000-0000-0000000000a1', 'd9400000-0000-0000-0000-0000000000a1', 'd9300000-0000-0000-0000-000000000003', 'Inspección bomba', 'monthly', now() + interval '10 days'),
  ('d9b30000-0000-0000-0000-0000000000a2', 'd9200000-0000-0000-0000-0000000000a1', 'd9b00000-0000-0000-0000-0000000000a1', 'd9400000-0000-0000-0000-0000000000a1', 'd9300000-0000-0000-0000-000000000006', 'Inspección sin nombre', 'monthly', now() + interval '10 days'),
  ('d9b30000-0000-0000-0000-0000000000a3', 'd9200000-0000-0000-0000-0000000000a1', 'd9b00000-0000-0000-0000-0000000000a1', 'd9400000-0000-0000-0000-0000000000a1', NULL, 'Inspección sin responsable', 'monthly', now() + interval '10 days');
INSERT INTO public.inspection_runs (id, organization_id, plan_id, template_id, asset_id, responsible_member_id, scheduled_for, status) VALUES
  ('d9b50000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'd9b30000-0000-0000-0000-0000000000a1', 'd9b00000-0000-0000-0000-0000000000a1', 'd9400000-0000-0000-0000-0000000000a1', 'd9300000-0000-0000-0000-000000000003', now(), 'scheduled');

-- Preventivo: una ocurrencia abierta en A y otra en V, con ids fijos.
INSERT INTO public.maintenance_cards (id, organization_id, code, name) VALUES
  ('d9880000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'KA', 'Ficha A'),
  ('d9880000-0000-0000-0000-0000000000c1', 'd9200000-0000-0000-0000-0000000000c1', 'KV', 'Ficha V');
INSERT INTO public.preventive_maintenance_plans (id, organization_id, asset_id, card_id, trigger_type, responsible_member_id, frequency, first_due_at) VALUES
  ('d98c0000-0000-0000-0000-0000000000a1', 'd9200000-0000-0000-0000-0000000000a1', 'd9400000-0000-0000-0000-0000000000a1', 'd9880000-0000-0000-0000-0000000000a1', 'calendar', 'd9300000-0000-0000-0000-000000000002', 'monthly', now() + interval '20 days'),
  ('d98c0000-0000-0000-0000-0000000000c1', 'd9200000-0000-0000-0000-0000000000c1', 'd9400000-0000-0000-0000-0000000000c1', 'd9880000-0000-0000-0000-0000000000c1', 'calendar', NULL, 'monthly', now() + interval '20 days');
SELECT public.create_preventive_occurrence_locked('d98c0000-0000-0000-0000-0000000000a1', now() + interval '20 days', NULL);
SELECT public.create_preventive_occurrence_locked('d98c0000-0000-0000-0000-0000000000c1', now() + interval '20 days', NULL);
SET LOCAL session_replication_role = replica;
UPDATE public.preventive_maintenance_occurrences SET id = 'd98d0000-0000-0000-0000-0000000000a1', request_creation_id = 'd98a0000-0000-0000-0000-0000000000a1'
WHERE plan_id = 'd98c0000-0000-0000-0000-0000000000a1';
UPDATE public.preventive_maintenance_occurrences SET id = 'd98d0000-0000-0000-0000-0000000000c1', request_creation_id = 'd98a0000-0000-0000-0000-0000000000c1'
WHERE plan_id = 'd98c0000-0000-0000-0000-0000000000c1';
SET LOCAL session_replication_role = origin;

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
$$;
CREATE FUNCTION pg_temp.req(p_number text, p_extra jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'request_number', p_number, 'title', 'Solicitud FM', 'description', 'Descripción FM',
    'asset', 'Activo A1', 'asset_id', 'd9400000-0000-0000-0000-0000000000a1', 'location', 'Lima - S1',
    'service_type', 'correctivo', 'deadline', '2026-12-31T00:00:00Z', 'branch_id', 'd9600000-0000-0000-0000-0000000000a1',
    'city', 'Lima', 'store', 'S1', 'branch', 'S1', 'requires_visit', false, 'request_type', 'external',
    'min_quotes', 3, 'client_name', 'Sede A', 'client_branch', 'S1', 'is_public', true,
    'provider_organization_ids', '[]'::jsonb
  ) || p_extra;
$$;
CREATE FUNCTION pg_temp.list_item(p_client uuid, p_request uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT e FROM jsonb_array_elements(public.get_facility_management_requests(p_client, 'sent')) e WHERE e->>'id' = p_request::text;
$$;
CREATE FUNCTION pg_temp.occurrence(p_org uuid, p_id uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT e FROM jsonb_array_elements(public.get_preventive_maintenance_occurrences(p_org)) e WHERE e->>'id' = p_id::text;
$$;

-- -------------------------------------------------------------------------
-- 0. Estructura y grants
-- -------------------------------------------------------------------------
SELECT ok((SELECT bool_and(NOT has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
           FROM pg_proc p WHERE p.oid IN (
             'public.can_view_requests_as_facility_manager(uuid)'::regprocedure,
             'public.can_create_requests_as_facility_manager(uuid)'::regprocedure,
             'public.can_manage_requests_as_facility_manager(uuid)'::regprocedure,
             'public.can_convert_maintenance_notice_as_facility_manager(uuid)'::regprocedure,
             'public.can_plan_preventive_request_as_facility_manager(uuid)'::regprocedure,
             'public.facility_management_safe_person_name(text,text,text)'::regprocedure,
             'public.facility_management_request_payload(public.requests,boolean,boolean)'::regprocedure,
             'public.facility_management_can_see_request(public.requests,boolean,boolean)'::regprocedure,
             'public.sanitize_preventive_occurrence_for_delegate(public.preventive_maintenance_occurrences)'::regprocedure,
             'public.sanitize_maintenance_notice_for_delegate(public.maintenance_notices)'::regprocedure,
             'public.apply_request_audience_internal(uuid,boolean,uuid[])'::regprocedure)),
  'internal helpers are not executable by authenticated/anon');
SELECT ok((SELECT count(*) = 8 AND bool_and(p.prosecdef AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
                AND NOT has_function_privilege('anon', p.oid, 'EXECUTE') AND array_to_string(p.proconfig, ',') = 'search_path=""')
           FROM pg_proc p WHERE p.oid IN (
             'public.get_facility_management_requests(uuid,text)'::regprocedure,
             'public.get_facility_management_request(uuid,uuid)'::regprocedure,
             'public.save_facility_management_request(uuid,uuid,jsonb,jsonb,boolean)'::regprocedure,
             'public.delete_facility_management_request_draft(uuid,uuid)'::regprocedure,
             'public.annul_facility_management_request(uuid,uuid)'::regprocedure,
             'public.get_facility_management_request_branches(uuid)'::regprocedure,
             'public.get_facility_management_request_assets(uuid)'::regprocedure,
             'public.get_facility_management_request_providers(uuid)'::regprocedure)),
  'delegated entrypoints: SECURITY DEFINER, empty search_path, authenticated only');
SELECT ok((SELECT bool_and(p.prosecdef AND has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
           FROM pg_proc p WHERE p.oid IN (
             'public.set_request_audience(uuid,boolean,uuid[])'::regprocedure,
             'public.convert_maintenance_notice(uuid,uuid)'::regprocedure,
             'public.plan_preventive_maintenance_occurrence(uuid,uuid)'::regprocedure,
             'public.skip_preventive_maintenance_occurrence(uuid,text)'::regprocedure,
             'public.get_preventive_maintenance_plans(uuid)'::regprocedure,
             'public.get_preventive_maintenance_occurrences(uuid,uuid,text)'::regprocedure,
             'public.get_maintenance_notices(uuid)'::regprocedure)),
  'replaced RPCs keep SECURITY DEFINER, authenticated EXECUTE and no anon');
SELECT ok((SELECT prosrc ~ 'ARRAY\[''owner'', ''admin'', ''manager'', ''requester''\]' AND prosrc ~ 'apply_request_audience_internal'
                  AND prosrc !~ 'facility_manage'
           FROM pg_proc WHERE oid = 'public.set_request_audience(uuid,boolean,uuid[])'::regprocedure),
  'set_request_audience keeps its historic client-only authorization');
SELECT ok((SELECT prosrc ~ 'Un Facility Manager no puede recibir invitaciones' AND prosrc ~ 'ya presentó una cotización'
                  AND prosrc ~ 'request_private_invitation' AND prosrc !~ 'has_organization_role'
           FROM pg_proc WHERE oid = 'public.apply_request_audience_internal(uuid,boolean,uuid[])'::regprocedure),
  'apply_request_audience_internal carries the historic audience rules (FM target, quote lock, notification)');
SELECT ok((SELECT bool_and(prosrc !~ 'has_facility_management|_as_facility_manager|facility_management_') FROM pg_proc WHERE oid IN (
             'public.can_user_read_request(uuid)'::regprocedure, 'public.can_user_manage_request_access(uuid)'::regprocedure,
             'public.can_provider_quote_request(uuid,uuid)'::regprocedure, 'public.get_coordination_contacts(uuid)'::regprocedure,
             'public.get_assignable_technicians(uuid)'::regprocedure, 'public.get_assignable_planners(uuid)'::regprocedure,
             'public.create_internal_work_order_from_request(uuid,uuid)'::regprocedure,
             'public.get_provider_relationship_directory(uuid)'::regprocedure,
             'public.notify_internal_request_created()'::regprocedure)),
  'read helper, rosters, work-order generation, provider directory and the internal notification are not extended');
SELECT ok((SELECT bool_and(COALESCE(qual, '') || COALESCE(with_check, '') !~ 'facility_management') FROM pg_policies
           WHERE schemaname = 'public' AND tablename IN ('requests', 'request_details', 'request_provider_access')),
  'requests / request_details / request_provider_access policies are not widened');
SELECT is(
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
     AND (has_table_privilege('anon', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
       OR has_table_privilege('authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))),
  0::bigint, '9C.1H preserved: no meta privileges for anon/authenticated');

SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 1. La RLS y las RPCs del cliente NO se abren al FM
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT is((SELECT count(*) FROM public.requests WHERE organization_id = 'd9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'RLS: FM manager reads no client request rows');
SELECT is((SELECT count(*) FROM public.request_details WHERE request_id = 'd98e0000-0000-0000-0000-0000000000a1'), 0::bigint, 'RLS: FM manager reads no request_details');
SELECT is((SELECT count(*) FROM public.request_provider_access WHERE request_id = 'd98e0000-0000-0000-0000-0000000000a1'), 0::bigint, 'RLS: FM manager reads no request_provider_access');
SELECT throws_ok($$ INSERT INTO public.requests (organization_id, request_number, description, asset, location, service_type, deadline, created_by, created_by_user_id)
                    VALUES ('d9200000-0000-0000-0000-0000000000a1', 'REQ-RAW', 'x', 'x', 'x', 'correctivo', now(), 'x', 'd9100000-0000-0000-0000-000000000013') $$,
  '42501', NULL, 'RLS: FM manager cannot INSERT a raw client request');
WITH u AS (UPDATE public.requests SET title = 'hack' WHERE id = 'd98e0000-0000-0000-0000-0000000000a1' RETURNING 1)
SELECT is(count(*), 0::bigint, 'RLS: FM manager cannot UPDATE a raw client request') FROM u;
SELECT throws_ok($$ SELECT * FROM public.set_request_audience('d98e0000-0000-0000-0000-0000000000a4', true, '{}') $$,
  'P0001', 'Not authorized to manage this request''s audience', 'set_request_audience stays client-only');
SELECT throws_ok($$ SELECT public.create_internal_work_order_from_request('d98e0000-0000-0000-0000-0000000000a2') $$, 'P0001', NULL, 'Generar OT is never delegated');
SELECT throws_ok($$ SELECT * FROM public.get_coordination_contacts('d9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'client coordination roster stays private');
SELECT throws_ok($$ SELECT * FROM public.get_assignable_technicians('d9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'client technician roster stays private');
SELECT throws_ok($$ SELECT * FROM public.get_assignable_planners('d9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'client planner roster stays private');
SELECT throws_ok($$ SELECT * FROM public.get_provider_relationship_directory('d9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'client provider directory stays private');
SELECT throws_ok($$ SELECT * FROM public.apply_request_audience_internal('d98e0000-0000-0000-0000-0000000000a1', true, '{}') $$, '42501', NULL, 'apply_request_audience_internal is not callable');

-- -------------------------------------------------------------------------
-- 2. VER (requests.view, owner/admin/manager/requester)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000011');
SELECT is(jsonb_array_length(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1')), 4, 'view: FM owner lists the sent requests of Client A');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000012');
SELECT is(jsonb_array_length(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1')), 4, 'view: FM admin lists the sent requests');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT is(jsonb_array_length(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1')), 4, 'view: FM manager lists the sent requests');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT is(jsonb_array_length(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1')), 4, 'view: FM requester lists the sent requests');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: FM technician is rejected');
SELECT throws_ok($$ SELECT public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'detail: FM technician is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000016');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: FM viewer is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000017');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: FM quote_manager is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000018');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: FM operator is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000019');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: unassigned FM manager is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-00000000001a');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: inactive FM membership is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000021');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: FM B cannot read Client A');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000b1') $$, '42501', NULL, 'view: FM A cannot read Client B');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000e1') $$, '42501', NULL, 'view: create + manage without view => rejected');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000e1', 'drafts') $$, '42501', NULL, 'create without view: no drafts');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000e1', NULL, pg_temp.req('FM-N-1', '{"asset_id": null, "branch_id": null}')) $$,
  '42501', NULL, 'create without view: cannot create');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_request_branches('d9200000-0000-0000-0000-0000000000e1') $$, '42501', NULL, 'create without view: no branch directory');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000f1') $$, '42501', NULL, 'view: suspended relationship => rejected');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1', 'all') $$, '22023', NULL, 'view: unknown scope => 22023');
SELECT is(jsonb_array_length(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000c1')), 1, 'view: view-only client lists its sent requests');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000c1', 'drafts') $$, '42501', NULL, 'view-only: no drafts scope');
SELECT is((public.get_facility_management_request('d9200000-0000-0000-0000-0000000000c1', 'd98e0000-0000-0000-0000-0000000000c1')->'request'->>'can_edit')::boolean, false, 'view-only: detail is read-only');
SELECT is(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000c1', 'd98e0000-0000-0000-0000-0000000000c1')->'audience', 'null'::jsonb, 'view-only: no audience in the detail');
SELECT is(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000b1'), NULL, 'detail: another tenant''s request id => NULL');
SELECT is(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a3'), NULL, 'detail: a client draft is invisible => NULL');
SELECT is(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000ff'), NULL, 'detail: unknown id => NULL');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000041');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: outsider is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000031');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'view: another client owner is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'direct client owner does not use the delegated RPC');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000051');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'a provider cannot use the delegated RPC');

-- -------------------------------------------------------------------------
-- 3. Minimización
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT ok(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1')::text !~ 'fm-requests\.test', 'list: no client email anywhere');
SELECT ok(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1')::text !~ 'd9300000-0000-0000-0000-00000000000[1-4]|d9100000-0000-0000-0000-000000000001',
  'list: no client member or user id anywhere');
SELECT ok((SELECT bool_and(NOT (e ?| ARRAY['created_by', 'created_by_user_id', 'created_by_email', 'coordination_contact_member_id',
             'coordination_contact_email', 'visit_contact_member_id', 'internal_responsible_member_id', 'image_urls', 'document_urls', 'notified_at']))
           FROM jsonb_array_elements(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1')) e),
  'list: forbidden keys are absent');
SELECT ok(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1')::text !~ 'secret\.test|fm-requests\.test',
  'detail: no attachment URLs or emails');
SELECT is(pg_temp.list_item('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1')->>'created_by_name', 'Usuario del cliente',
  'names: an email-prefix creator name is never shown');
SELECT is(pg_temp.list_item('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a2')->>'created_by_name', 'Olga Cliente', 'names: a real creator name is kept');
SELECT is(pg_temp.list_item('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a2')->>'coordination_contact_name', 'Asignado por el cliente',
  'names: an email-prefix contact snapshot is never shown');
SELECT ok((SELECT e->>'coordination_contact_name' = 'Mario Cliente' AND (e->>'has_client_coordination_contact')::boolean AND (e->>'has_client_visit_contact')::boolean
           FROM pg_temp.list_item('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1') e),
  'contacts: safe name + presence flags only');
SELECT is(pg_temp.list_item('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a2')->>'internal_responsible_name', 'Asignado por el cliente',
  'internal responsible: label only');
SELECT ok((SELECT jsonb_array_length(d->'details') = 1 AND NOT (d->'details'->0 ? 'attachment_urls') AND d->'details'->0->>'activities' = 'Actividad A1'
           FROM public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1') d),
  'detail: rows without attachment_urls');
SELECT ok((SELECT (d->'request'->>'has_client_attachments')::boolean AND NOT (d->'request'->>'can_edit')::boolean AND d::text !~ 'attach\.test'
           FROM public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a6') d),
  'detail: client attachments are flagged, never exposed, and block editing');
SELECT is(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1')->'audience',
  '{"is_public": false, "providers": [{"organization_id": "d9200000-0000-0000-0000-000000000091", "organization_name": "Proveedor P1"}]}'::jsonb,
  'detail: manager gets the audience (ids + names only)');
SELECT ok((SELECT (e->>'can_edit')::boolean AND (e->>'can_annul')::boolean AND NOT (e->>'can_delete_draft')::boolean AND NOT (e->>'is_own')::boolean
           FROM pg_temp.list_item('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1') e),
  'flags: manager can edit and annul a sent client request');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT ok((SELECT NOT (d->'request'->>'can_edit')::boolean AND NOT (d->'request'->>'can_annul')::boolean AND d->'audience' = 'null'::jsonb
           FROM public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1') d),
  'flags: requester (create, no manage) reads a sent request without edit/annul/audience');

-- -------------------------------------------------------------------------
-- 4. CREAR (view + create, owner/admin/manager/requester)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001',
            pg_temp.req('FM-9C4-001'), '[{"activities":"Act 1","quantity":2},{"activities":"Act 2","responsible_user":"Encargado FM"}]')->'request'->>'status',
  'draft', 'create: FM requester saves a new draft');
SELECT is(jsonb_array_length(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1', 'drafts')), 1, 'create: the own draft is listed');
SELECT ok((SELECT (d->'request'->>'is_own')::boolean AND (d->'request'->>'can_edit')::boolean AND (d->'request'->>'can_delete_draft')::boolean
                  AND jsonb_array_length(d->'details') = 2
           FROM public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001') d),
  'create: own draft detail with edit/delete and its details');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT is(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001'), NULL, 'create: another FM user does not see the draft');
SELECT is(jsonb_array_length(public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000a1', 'drafts')), 0, 'create: drafts are per user');
RESET ROLE;
SELECT ok((SELECT organization_id = 'd9200000-0000-0000-0000-0000000000a1' AND created_by_user_id = 'd9100000-0000-0000-0000-000000000015'
                  AND created_by_email = 'fa-requester@fm-requests.test' AND created_by_name = 'Rosa FM'
                  AND coordination_contact_member_id IS NULL AND coordination_contact_name = 'Rosa FM'
                  AND coordination_contact_email = 'fa-requester@fm-requests.test' AND visit_contact_member_id IS NULL
                  AND internal_responsible_member_id IS NULL AND status = 'draft' AND priority = 2 AND is_public IS TRUE
           FROM public.requests WHERE id = 'd9e00000-0000-0000-0000-000000000001'),
  'create: client tenant, FM actor + FM contact snapshot, no client member ids');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000002',
            pg_temp.req('FM-9C4-002', jsonb_build_object('is_public', false, 'provider_organization_ids',
              jsonb_build_array('d9200000-0000-0000-0000-000000000091', 'd9200000-0000-0000-0000-000000000093'))), '[]', true)->'request'->>'status',
  'sent', 'create: private request submitted after the audience sync');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.request_provider_access WHERE request_id = 'd9e00000-0000-0000-0000-000000000002'
           AND status = 'active' AND access_type = 'invited' AND invited_by_user_id = 'd9100000-0000-0000-0000-000000000015'), 2::bigint,
  'audience: both invitations written with the FM as inviter');
SELECT is((SELECT count(*) FROM public.organization_notifications WHERE entity_id = 'd9e00000-0000-0000-0000-000000000002'
           AND type = 'request_private_invitation' AND actor_user_id = 'd9100000-0000-0000-0000-000000000015'
           AND metadata->>'client_organization_id' = 'd9200000-0000-0000-0000-0000000000a1'), 2::bigint,
  'audience: providers notified with the client org and the FM as actor');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE record_id = 'd9e00000-0000-0000-0000-000000000002' AND action = 'provider_invited'
           AND organization_id = 'd9200000-0000-0000-0000-0000000000a1' AND actor_user_id = 'd9100000-0000-0000-0000-000000000015'), 2::bigint,
  'audience: audit trail in the client with the FM actor');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000051');
SELECT ok(public.can_user_read_request('d9e00000-0000-0000-0000-000000000002'), 'provider flow: an invited provider reads the FM-created request');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000003',
                      pg_temp.req('FM-9C4-003', '{"is_public": false, "provider_organization_ids": ["d9200000-0000-0000-0000-0000000000fa"]}'), '[]', true) $$,
  '22023', NULL, 'audience: a facility manager can never be invited');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000003',
                      pg_temp.req('FM-9C4-003', '{"is_public": false, "provider_organization_ids": ["d9200000-0000-0000-0000-000000000092"]}'), '[]', true) $$,
  'P0001', NULL, 'audience: a non-active provider relationship is rejected');
SELECT is(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000003'), NULL,
  'atomicity: a failed audience leaves no request behind');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL,
                      pg_temp.req('FM-9C4-004', '{"is_public": false}'), '[]', true) $$,
  'P0001', 'Selecciona al menos un proveedor para enviar una invitación privada.', 'audience: private without providers is rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL,
                      pg_temp.req('FM-E-1', '{"is_public": false}'), '[]', false) $$,
  'P0001', 'Selecciona al menos un proveedor para enviar una invitación privada.', 'drafts: a private DRAFT without providers is rejected too (same contract as RequestList)');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000021',
            pg_temp.req('FM-E-2', '{"is_public": false, "provider_organization_ids": ["d9200000-0000-0000-0000-000000000091"]}'), '[]', false)->'request'->>'status',
  'draft', 'drafts: a private draft with an active provider is allowed');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL,
                      pg_temp.req('FM-E-3', '{"is_public": false, "provider_organization_ids": ["d9200000-0000-0000-0000-000000000092"]}'), '[]', false) $$,
  'P0001', NULL, 'drafts: a private draft with a non-homologated provider is rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL,
                      pg_temp.req('FM-E-4', '{"is_public": false, "provider_organization_ids": ["d9200000-0000-0000-0000-0000000000fa"]}'), '[]', false) $$,
  '22023', NULL, 'drafts: a private draft targeting a facility manager is rejected');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000005',
            pg_temp.req('FM-9C4-005', '{"request_type": "internal"}'), '[]', true)->'request'->>'status', 'sent', 'create: internal request submitted');
RESET ROLE;
SELECT ok((SELECT internal_responsible_member_id IS NULL AND is_public IS FALSE FROM public.requests WHERE id = 'd9e00000-0000-0000-0000-000000000005')
      AND NOT EXISTS (SELECT 1 FROM public.request_provider_access WHERE request_id = 'd9e00000-0000-0000-0000-000000000005'),
  'internal: no responsible and no audience');
SELECT is((SELECT count(*) FROM public.organization_notifications WHERE entity_id = 'd9e00000-0000-0000-0000-000000000005'
           AND type = 'internal_request_created' AND organization_id = 'd9200000-0000-0000-0000-0000000000a1'
           AND actor_user_id = 'd9100000-0000-0000-0000-000000000015'), 2::bigint,
  'internal: the historic trigger notifies the client o/a/m with the FM as actor');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-1')) $$, '42501', NULL, 'create: FM technician is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000016');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-2')) $$, '42501', NULL, 'create: FM viewer is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000c1', NULL, pg_temp.req('FM-X-3', '{"asset_id": null, "branch_id": null}')) $$,
  '42501', NULL, 'create: view-only client => rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000d1', NULL, pg_temp.req('FM-X-4', '{"asset_id": null, "branch_id": null}')) $$,
  '42501', NULL, 'create: manage without create cannot create');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-5', '{"coordination_contact_member_id": "d9300000-0000-0000-0000-000000000002"}')) $$,
  '42501', NULL, 'contacts: a client member cannot be assigned as coordination contact');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-6', '{"coordination_contact_member_id": "d9300000-0000-0000-0000-000000000013"}')) $$,
  '42501', NULL, 'contacts: an FM member cannot be assigned as coordination contact');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-7', '{"visit_contact_member_id": "d9300000-0000-0000-0000-000000000002"}')) $$,
  '42501', NULL, 'contacts: the visit contact cannot be assigned');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-8', '{"internal_responsible_member_id": "d9300000-0000-0000-0000-000000000003"}')) $$,
  '42501', NULL, 'contacts: the internal responsible cannot be assigned');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-9', '{"coordination_contact_email": "x@y.test"}')) $$,
  '42501', NULL, 'contacts: the contact snapshot cannot be written');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-10', '{"organization_id": "d9200000-0000-0000-0000-0000000000b1"}')) $$,
  '22023', NULL, 'whitelist: organization_id is rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-11', '{"created_by_user_id": "d9100000-0000-0000-0000-000000000001"}')) $$,
  '22023', NULL, 'whitelist: created_by_user_id is rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-12', '{"status": "sent"}')) $$,
  '22023', NULL, 'whitelist: status is rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-13', '{"image_urls": ["https://x.test/a.png"]}')) $$,
  '22023', NULL, 'whitelist: attachments are rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-14'), '[{"activities":"x","attachment_urls":["https://x.test/a.pdf"]}]') $$,
  '22023', NULL, 'whitelist: detail attachments are rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('  ')) $$,
  '22023', NULL, 'create: a request number is required');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-15', '{"branch_id": "d9600000-0000-0000-0000-0000000000b1"}')) $$,
  '22023', NULL, 'references: another client''s branch is rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-16', '{"branch_id": "d9600000-0000-0000-0000-0000000000a2"}')) $$,
  '22023', NULL, 'references: an inactive branch is rejected on create');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-17', '{"asset_id": "d9400000-0000-0000-0000-0000000000b1"}')) $$,
  '22023', NULL, 'references: another client''s asset is rejected');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', NULL, pg_temp.req('FM-X-18', '{"asset_id": "d9400000-0000-0000-0000-0000000000a9"}')) $$,
  '22023', NULL, 'references: an archived asset is rejected on create');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000b1', pg_temp.req('REQ-9C4-B1')) $$,
  '42501', NULL, 'tenant: another client''s request id cannot be overwritten');
RESET ROLE;
SELECT is((SELECT title FROM public.requests WHERE id = 'd98e0000-0000-0000-0000-0000000000b1'), 'Cliente B', 'tenant: the Client B request is untouched');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 5. Borradores propios
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001',
            pg_temp.req('FM-9C4-001', '{"title": "Borrador editado", "request_type": "internal"}'))->'request'->>'title',
  'Borrador editado', 'own draft: edited (including its type, still a draft)');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001', pg_temp.req('FM-OTRO')) $$,
  '22023', NULL, 'own draft: the request number is immutable');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a3', pg_temp.req('REQ-9C4-A3')) $$,
  '42501', NULL, 'drafts: a client draft cannot be edited');
SELECT throws_ok($$ SELECT public.delete_facility_management_request_draft('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a3') $$,
  '42501', NULL, 'drafts: a client draft cannot be deleted');
SELECT throws_ok($$ SELECT public.delete_facility_management_request_draft('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'drafts: a sent request cannot be deleted');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001', pg_temp.req('FM-9C4-001')) $$,
  '42501', NULL, 'drafts: another FM user cannot edit the draft');
SELECT throws_ok($$ SELECT public.delete_facility_management_request_draft('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'drafts: another FM user cannot delete the draft');
SELECT throws_ok($$ SELECT public.annul_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'drafts: a draft cannot be annulled');
SELECT throws_ok($$ SELECT public.get_facility_management_requests('d9200000-0000-0000-0000-0000000000d1', 'drafts') $$, '42501', NULL, 'drafts: manage without create has no drafts');
SELECT throws_ok($$ SELECT public.delete_facility_management_request_draft('d9200000-0000-0000-0000-0000000000c1', 'd98e0000-0000-0000-0000-0000000000c1') $$,
  '42501', NULL, 'drafts: view-only cannot delete');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT lives_ok($$ SELECT public.delete_facility_management_request_draft('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001') $$,
  'drafts: the own draft is deleted');
SELECT is(public.get_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000001'), NULL, 'drafts: the deleted draft is gone');

-- -------------------------------------------------------------------------
-- 6. GESTIONAR (view + manage, owner/admin/manager)
-- -------------------------------------------------------------------------
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1', pg_temp.req('REQ-9C4-A1')) $$,
  '42501', NULL, 'manage: requester (no manage) cannot edit a sent request');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1',
            pg_temp.req('REQ-9C4-A1', jsonb_build_object('title', 'Editada por FM', 'is_public', false, 'requires_visit', true, 'visit_schedule_mode', 'to_schedule',
              'provider_organization_ids', jsonb_build_array('d9200000-0000-0000-0000-000000000091', 'd9200000-0000-0000-0000-000000000093'))),
            '[{"activities":"Nueva actividad"}]')->'request'->>'title',
  'Editada por FM', 'manage: FM manager edits a sent client request');
RESET ROLE;
SELECT ok((SELECT coordination_contact_member_id = 'd9300000-0000-0000-0000-000000000002' AND coordination_contact_name = 'Mario Cliente'
                  AND coordination_contact_email = 'ca-manager@fm-requests.test' AND visit_contact_member_id = 'd9300000-0000-0000-0000-000000000002'
                  AND created_by_user_id = 'd9100000-0000-0000-0000-000000000001' AND created_by_email = 'ca-owner@fm-requests.test'
                  AND request_number = 'REQ-9C4-A1' AND organization_id = 'd9200000-0000-0000-0000-0000000000a1' AND status = 'sent'
                  AND image_urls = ARRAY['https://secret.test/img.png']
           FROM public.requests WHERE id = 'd98e0000-0000-0000-0000-0000000000a1'),
  'manage: client-owned contacts, creator, number, tenant, status and attachments are preserved');
SELECT is((SELECT array_agg(activities) FROM public.request_details WHERE request_id = 'd98e0000-0000-0000-0000-0000000000a1'), ARRAY['Nueva actividad'],
  'manage: details replaced');
SELECT is((SELECT count(*) FROM public.request_provider_access WHERE request_id = 'd98e0000-0000-0000-0000-0000000000a1' AND status = 'active'), 2::bigint,
  'manage: audience extended through the shared audience logic');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1',
                      pg_temp.req('REQ-9C4-A1', '{"is_public": false, "provider_organization_ids": ["d9200000-0000-0000-0000-000000000093"]}')) $$,
  'P0001', NULL, 'manage: a provider that already quoted cannot be removed');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a1',
                      pg_temp.req('REQ-9C4-A1', '{"coordination_contact_member_id": null}')) $$,
  '42501', NULL, 'manage: the client contact cannot be cleared');
SELECT lives_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a2',
                     pg_temp.req('REQ-9C4-A2', '{"request_type": "internal", "title": "Interna editada"}')) $$,
  'manage: internal request edited');
RESET ROLE;
SELECT is((SELECT internal_responsible_member_id FROM public.requests WHERE id = 'd98e0000-0000-0000-0000-0000000000a2'), 'd9300000-0000-0000-0000-000000000003'::uuid,
  'manage: the client internal responsible is preserved');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a2', pg_temp.req('REQ-9C4-A2')) $$,
  'P0001', NULL, 'manage: request_type stays locked after submission');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a6', pg_temp.req('REQ-9C4-A6')) $$,
  '55000', NULL, 'manage: a request with client attachments is not editable');
RESET ROLE;
CREATE TEMP TABLE a7_before AS SELECT
  (SELECT to_jsonb(r) FROM public.requests r WHERE r.id = 'd98e0000-0000-0000-0000-0000000000a7') AS req,
  (SELECT jsonb_agg(to_jsonb(d) ORDER BY d.id) FROM public.request_details d WHERE d.request_id = 'd98e0000-0000-0000-0000-0000000000a7') AS det,
  (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.request_provider_access a WHERE a.request_id = 'd98e0000-0000-0000-0000-0000000000a7') AS aud;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a7',
                      pg_temp.req('REQ-9C4-A7', '{"title": "Editada", "is_public": false, "provider_organization_ids": ["d9200000-0000-0000-0000-000000000093"]}'),
                      '[{"activities": "Reemplazo"}]', true) $$,
  '55000', NULL, 'attachments: a delegated edit (fields + details + audience) of a request with client attachments => 55000');
RESET ROLE;
SELECT is((SELECT to_jsonb(r) FROM public.requests r WHERE r.id = 'd98e0000-0000-0000-0000-0000000000a7'), (SELECT req FROM a7_before),
  'attachments: the request row is identical after the rejected edit');
SELECT is((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.id) FROM public.request_details d WHERE d.request_id = 'd98e0000-0000-0000-0000-0000000000a7'), (SELECT det FROM a7_before),
  'attachments: details and attachment_urls are identical');
SELECT is((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.request_provider_access a WHERE a.request_id = 'd98e0000-0000-0000-0000-0000000000a7'), (SELECT aud FROM a7_before),
  'attachments: the audience is identical');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a5', pg_temp.req('REQ-9C4-A5')) $$,
  '55000', NULL, 'manage: an annulled request is not editable');
SELECT lives_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a4',
                     pg_temp.req('REQ-9C4-A4', '{"title": "Cotizada editada"}')) $$,
  'manage: a quoted request is editable');
SELECT throws_ok($$ SELECT public.save_facility_management_request('d9200000-0000-0000-0000-0000000000c1', 'd98e0000-0000-0000-0000-0000000000c1', pg_temp.req('REQ-9C4-C1', '{"asset_id": null, "branch_id": null}')) $$,
  '42501', NULL, 'manage: view-only client cannot edit');
SELECT throws_ok($$ SELECT public.annul_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a5') $$,
  '55000', NULL, 'annul: an annulled request cannot be annulled again');
SELECT throws_ok($$ SELECT public.annul_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000b1') $$,
  '42501', NULL, 'annul: another tenant''s request is rejected');
SELECT is(public.annul_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a6')->>'status', 'anulado',
  'annul: FM manager annuls a sent request');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000d1', 'd98e0000-0000-0000-0000-0000000000d1',
            pg_temp.req('REQ-9C4-D1', '{"asset_id": null, "branch_id": null, "title": "M editada"}'))->'request'->>'title', 'M editada',
  'manage without create: edits a sent request');
SELECT lives_ok($$ SELECT public.annul_facility_management_request('d9200000-0000-0000-0000-0000000000d1', 'd98e0000-0000-0000-0000-0000000000d1') $$,
  'manage without create: annuls');
RESET ROLE;
SELECT is((SELECT status::text FROM public.requests WHERE id = 'd98e0000-0000-0000-0000-0000000000d1'), 'anulado', 'manage without create: the request is annulled');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT throws_ok($$ SELECT public.annul_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98e0000-0000-0000-0000-0000000000a2') $$,
  '42501', NULL, 'manage: requester cannot annul');

-- -------------------------------------------------------------------------
-- 7. Directorios mínimos
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT is((SELECT array_agg(name || ':' || is_active ORDER BY name) FROM public.get_facility_management_request_branches('d9200000-0000-0000-0000-0000000000a1')),
  ARRAY['Sede A:true', 'Sede A cerrada:false'], 'branches: all client branches with is_active');
SELECT ok((SELECT string_agg(to_jsonb(b)::text, '') FROM public.get_facility_management_request_branches('d9200000-0000-0000-0000-0000000000a1') b) !~ 'secret@',
  'branches: no client_email');
SELECT is((SELECT array_agg(name || '|' || path ORDER BY name) FROM public.get_facility_management_request_assets('d9200000-0000-0000-0000-0000000000a1')),
  ARRAY['Activo A1|Activo A1', 'Activo A2|Activo A1 › Activo A2'], 'assets: non-archived only, with path');
SELECT is((SELECT array_agg(organization_name ORDER BY organization_name) FROM public.get_facility_management_request_providers('d9200000-0000-0000-0000-0000000000a1')),
  ARRAY['Proveedor P1', 'Subcontratista S1'], 'providers: only active provider/subcontractor relationships (never FM, never pending)');
SELECT is((SELECT count(*) FROM public.get_facility_management_request_providers('d9200000-0000-0000-0000-0000000000d1')), 0::bigint,
  'providers: manage-only client with no relationships => empty');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_request_branches('d9200000-0000-0000-0000-0000000000c1') $$, '42501', NULL, 'branches: view-only is rejected');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_request_assets('d9200000-0000-0000-0000-0000000000c1') $$, '42501', NULL, 'assets: view-only is rejected');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_request_providers('d9200000-0000-0000-0000-0000000000c1') $$, '42501', NULL, 'providers: view-only is rejected');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_request_assets('d9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'assets: FM technician is rejected');

-- -------------------------------------------------------------------------
-- 8. Aviso -> Solicitud (avisos view+manage Y solicitudes view+create, o/a/m)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000011',
            pg_temp.req('FM-9C4-011'))->'request'->>'status', 'draft', 'notice: FM manager drafts the request for the notice');
SELECT is((public.convert_maintenance_notice('d9900000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000011')).status, 'converted',
  'notice: FM manager converts the notice');
SELECT ok((SELECT n.converted_request_id = 'd9e00000-0000-0000-0000-000000000011' AND n.reported_by_user_id IS NULL
                  AND n.responsible_member_id IS NULL AND n.converted_by_user_id IS NULL
           FROM public.convert_maintenance_notice('d9900000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000011') n),
  'notice: idempotent retry returns the minimized row with the visible request id');
SELECT ok((SELECT n.converted_request_id = 'd9e00000-0000-0000-0000-000000000011' AND n.converted_request_number = 'FM-9C4-011'
           FROM public.get_maintenance_notices('d9200000-0000-0000-0000-0000000000a1') n WHERE n.id = 'd9900000-0000-0000-0000-0000000000a1'),
  'notice: the backlog shows the generated request with requests.view');
SELECT ok((SELECT n.converted_request_id IS NULL AND n.converted_request_number IS NULL
           FROM public.get_maintenance_notices('d9200000-0000-0000-0000-0000000000a1') n WHERE n.id = 'd9900000-0000-0000-0000-0000000000a3'),
  'notice: a notice converted into a client draft keeps the request hidden');
SELECT throws_ok($$ SELECT public.convert_maintenance_notice('d9900000-0000-0000-0000-0000000000a2', 'd98e0000-0000-0000-0000-0000000000a3') $$,
  'P0001', 'La solicitud no existe', 'notice: a client draft does not exist for the delegate');
SELECT throws_ok($$ SELECT public.delete_facility_management_request_draft('d9200000-0000-0000-0000-0000000000a1', 'd9e00000-0000-0000-0000-000000000011') $$,
  '55000', NULL, 'notice: a draft linked to a notice cannot be deleted');
SELECT throws_ok($$ SELECT public.convert_maintenance_notice('d9900000-0000-0000-0000-0000000000c1', 'd98e0000-0000-0000-0000-0000000000c1') $$,
  'P0001', NULL, 'notice: without requests.create the FM cannot convert');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000015');
SELECT throws_ok($$ SELECT public.convert_maintenance_notice('d9900000-0000-0000-0000-0000000000a2', 'd9e00000-0000-0000-0000-000000000002') $$,
  'P0001', NULL, 'notice: FM requester (not o/a/m) cannot convert');
RESET ROLE;
SELECT is((SELECT created_by_user_id FROM public.asset_events WHERE event_type = 'maintenance_notice_converted'
           AND payload->>'notice_id' = 'd9900000-0000-0000-0000-0000000000a1'), 'd9100000-0000-0000-0000-000000000013'::uuid,
  'notice: the asset history records the FM actor');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000002');
SELECT ok((SELECT n.status = 'converted' AND n.reported_by_user_id = 'd9100000-0000-0000-0000-000000000003'
           FROM public.convert_maintenance_notice('d9900000-0000-0000-0000-0000000000a2', 'd98e0000-0000-0000-0000-0000000000a4') n),
  'notice: the direct client manager still converts and gets the full row');

-- -------------------------------------------------------------------------
-- 9. Ocurrencia preventiva -> Solicitud (preventivo view+manage Y
--    solicitudes view+create, o/a/m)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT is(pg_temp.occurrence('d9200000-0000-0000-0000-0000000000a1', 'd98d0000-0000-0000-0000-0000000000a1')->>'request_creation_id',
  'd98a0000-0000-0000-0000-0000000000a1', 'preventive: the planner capability sees request_creation_id');
SELECT is((SELECT p->'current_occurrence'->>'request_creation_id' FROM jsonb_array_elements(public.get_preventive_maintenance_plans('d9200000-0000-0000-0000-0000000000a1')) p
           WHERE p->>'id' = 'd98c0000-0000-0000-0000-0000000000a1'),
  'd98a0000-0000-0000-0000-0000000000a1', 'preventive: plans expose request_creation_id to the planner capability');
SELECT is(pg_temp.occurrence('d9200000-0000-0000-0000-0000000000c1', 'd98d0000-0000-0000-0000-0000000000c1')->>'request_creation_id', NULL,
  'preventive: without requests.create request_creation_id stays hidden');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000014');
SELECT is(pg_temp.occurrence('d9200000-0000-0000-0000-0000000000a1', 'd98d0000-0000-0000-0000-0000000000a1')->>'request_creation_id', NULL,
  'preventive: FM technician never sees request_creation_id');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT is(public.save_facility_management_request('d9200000-0000-0000-0000-0000000000a1', 'd98a0000-0000-0000-0000-0000000000a1',
            pg_temp.req('MP-9C4-A1', '{"service_type": "preventivo"}'))->'request'->>'id',
  'd98a0000-0000-0000-0000-0000000000a1', 'preventive: FM manager drafts the request with request_creation_id');
SELECT ok((SELECT o.status = 'planned' AND o.request_id = 'd98a0000-0000-0000-0000-0000000000a1' AND o.work_order_id IS NULL
                  AND o.request_creation_id = 'd98a0000-0000-0000-0000-0000000000a1'
           FROM public.plan_preventive_maintenance_occurrence('d98d0000-0000-0000-0000-0000000000a1', 'd98a0000-0000-0000-0000-0000000000a1') o),
  'preventive: FM manager plans the occurrence; minimized row (no work order id)');
SELECT is(pg_temp.occurrence('d9200000-0000-0000-0000-0000000000a1', 'd98d0000-0000-0000-0000-0000000000a1')->>'request_id',
  'd98a0000-0000-0000-0000-0000000000a1', 'preventive: request_id visible with requests.view');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000014');
SELECT ok((SELECT e->>'request_id' IS NULL AND e->>'work_order_id' IS NULL FROM pg_temp.occurrence('d9200000-0000-0000-0000-0000000000a1', 'd98d0000-0000-0000-0000-0000000000a1') e),
  'preventive: FM technician (no requests.view) still sees no request/work-order id');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.plan_preventive_maintenance_occurrence('d98d0000-0000-0000-0000-0000000000c1', 'd98a0000-0000-0000-0000-0000000000c1') $$,
  'P0001', 'Not authorized', 'preventive: without requests.create the FM cannot plan');
SELECT ok((SELECT o.status = 'skipped' AND o.request_creation_id IS NULL AND o.work_order_id IS NULL
           FROM public.skip_preventive_maintenance_occurrence('d98d0000-0000-0000-0000-0000000000c1', 'Sin acceso') o),
  'preventive: skip returns a minimized row to the delegate');
RESET ROLE;
SELECT is((SELECT status::text FROM public.requests WHERE id = 'd98a0000-0000-0000-0000-0000000000a1'), 'draft', 'preventive: linking keeps the request status');
CREATE FUNCTION pg_temp.plan(p_org uuid, p_id uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT e FROM jsonb_array_elements(public.get_preventive_maintenance_plans(p_org)) e WHERE e->>'id' = p_id::text;
$$;
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 9b. Responsable del plan preventivo: del cliente, nunca expuesto al FM y
--     conservado en el servidor.
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT ok((SELECT p->>'responsible_member_id' IS NULL AND (p->>'has_responsible')::boolean
           FROM pg_temp.plan('d9200000-0000-0000-0000-0000000000a1', 'd98c0000-0000-0000-0000-0000000000a1') p),
  'responsible: the FM plan payload has no responsible_member_id, only has_responsible (UI: "Asignado por el cliente")');
SELECT is((pg_temp.plan('d9200000-0000-0000-0000-0000000000c1', 'd98c0000-0000-0000-0000-0000000000c1')->>'has_responsible')::boolean, false,
  'responsible: a plan without responsible reports has_responsible = false');
SELECT is(pg_temp.occurrence('d9200000-0000-0000-0000-0000000000a1', 'd98d0000-0000-0000-0000-0000000000a1')->'scope_snapshot'->'plan'->'responsible', '{"assigned": true}'::jsonb,
  'snapshot: the delegated responsible is only {"assigned": true}');
SELECT ok((public.get_preventive_maintenance_plans('d9200000-0000-0000-0000-0000000000a1')::text || public.get_preventive_maintenance_occurrences('d9200000-0000-0000-0000-0000000000a1')::text) !~ 'membership_id|d9300000-0000-0000-0000-00000000000[1-4]|d9100000-0000-0000-0000-00000000000[1-4]|@',
  'snapshot/plans: no membership_id, member/user id or email in delegated preventive payloads');
SELECT throws_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_card_id => 'd9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_frequency => 'monthly', p_first_due_at => now() + interval '25 days', p_plan_id => 'd98c0000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'd9300000-0000-0000-0000-000000000002') $$,
  '42501', 'The preventive plan responsible is assigned by the client', 'responsible: the FM cannot inject (or resend) a client membership id');
SELECT throws_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_card_id => 'd9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_frequency => 'monthly', p_first_due_at => now() + interval '25 days', p_plan_id => 'd98c0000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'd9300000-0000-0000-0000-000000000013') $$,
  '42501', 'The preventive plan responsible is assigned by the client', 'responsible: the FM cannot inject its own FM membership id');
SELECT ok((SELECT responsible_member_id IS NULL AND created_by_user_id IS NULL
           FROM public.save_preventive_maintenance_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_card_id => 'd9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_frequency => 'monthly', p_first_due_at => now() + interval '25 days', p_plan_id => 'd98c0000-0000-0000-0000-0000000000a1', p_priority => 'high')),
  'responsible: the FM edits another field; the returned plan carries no client ids');
SELECT ok((SELECT responsible_member_id IS NULL FROM public.set_preventive_maintenance_plan_active('d98c0000-0000-0000-0000-0000000000a1', false, 'Pausa FM'))
      AND (SELECT responsible_member_id IS NULL FROM public.set_preventive_maintenance_plan_active('d98c0000-0000-0000-0000-0000000000a1', true)),
  'responsible: deactivate/activate return no responsible id to the FM');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000014');
SELECT ok((public.get_preventive_maintenance_plans('d9200000-0000-0000-0000-0000000000a1')::text || public.get_preventive_maintenance_occurrences('d9200000-0000-0000-0000-0000000000a1')::text) !~ 'membership_id|d9300000-0000-0000-0000-00000000000[1-4]|d9100000-0000-0000-0000-00000000000[1-4]|@',
  'responsible: an FM technician (view only) gets no internal ids either');
RESET ROLE;
SELECT results_eq($$ SELECT priority, responsible_member_id FROM public.preventive_maintenance_plans WHERE id = 'd98c0000-0000-0000-0000-0000000000a1' $$,
  $$ VALUES ('high'::text, 'd9300000-0000-0000-0000-000000000002'::uuid) $$,
  'responsible: the FM edit persisted and the real responsible was preserved server-side');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000002');
SELECT is(pg_temp.plan('d9200000-0000-0000-0000-0000000000a1', 'd98c0000-0000-0000-0000-0000000000a1')->>'responsible_member_id', 'd9300000-0000-0000-0000-000000000002',
  'responsible (direct): the client still receives responsible_member_id');
SELECT lives_ok($$ SELECT public.save_preventive_maintenance_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_card_id => 'd9880000-0000-0000-0000-0000000000a1', p_trigger_type => 'calendar', p_frequency => 'monthly', p_first_due_at => now() + interval '25 days', p_plan_id => 'd98c0000-0000-0000-0000-0000000000a1', p_priority => 'high', p_responsible_member_id => 'd9300000-0000-0000-0000-000000000001') $$,
  'responsible (direct): the client still changes the responsible');
RESET ROLE;
SELECT is((SELECT responsible_member_id FROM public.preventive_maintenance_plans WHERE id = 'd98c0000-0000-0000-0000-0000000000a1'), 'd9300000-0000-0000-0000-000000000001'::uuid,
  'responsible (direct): the client change is persisted');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 9c. Inspecciones: ningún organization_members.id del cliente sale al FM;
--     el servidor conserva el responsable real.
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT ok((SELECT count(*) = 3 AND bool_and(responsible_member_id IS NULL) FROM public.get_inspection_plans('d9200000-0000-0000-0000-0000000000a1', true)),
  'insp A: delegated get_inspection_plans returns responsible_member_id NULL');
SELECT ok((SELECT count(*) >= 1 AND bool_and(responsible_member_id IS NULL) FROM public.get_inspection_runs('d9200000-0000-0000-0000-0000000000a1', NULL))
      AND (SELECT string_agg(to_jsonb(r)::text, '') FROM public.get_inspection_runs('d9200000-0000-0000-0000-0000000000a1', NULL) r) !~ 'd9300000-0000-0000-0000-00000000000[1-6]|d9100000-0000-0000-0000-00000000000[1-6]|@',
  'insp B: delegated get_inspection_runs carries no member/user id or email');
SELECT ok((SELECT d->>'responsible_member_id' IS NULL AND (d->>'has_responsible')::boolean AND d->>'responsible_name' = 'Tomas Cliente' AND d::text !~ 'd9300000-0000-0000-0000-00000000000[1-6]|d9100000-0000-0000-0000-00000000000[1-6]|@'
           FROM public.get_inspection_run_detail('d9b50000-0000-0000-0000-0000000000a1') d),
  'insp C: delegated get_inspection_run_detail has no member id, only has_responsible + safe name');
SELECT results_eq($$ SELECT title, responsible_name, has_responsible FROM public.get_inspection_plans('d9200000-0000-0000-0000-0000000000a1', true) ORDER BY title $$,
  $$ VALUES ('Inspección bomba'::text, 'Tomas Cliente'::text, true), ('Inspección sin nombre', NULL, true), ('Inspección sin responsable', NULL, false) $$,
  'insp D: safe name when stored; has_responsible without name ("Asignado por el cliente"); none => false');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_template_id => 'd9b00000-0000-0000-0000-0000000000a1', p_title => 'Inspección bomba (FM)', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_frequency => 'monthly', p_plan_id => 'd9b30000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'd9300000-0000-0000-0000-000000000003') $$,
  '42501', 'The inspection plan responsible is assigned by the client', 'insp F: the FM cannot resend the current responsible id');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_template_id => 'd9b00000-0000-0000-0000-0000000000a1', p_title => 'Inspección bomba (FM)', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_frequency => 'monthly', p_plan_id => 'd9b30000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'd9300000-0000-0000-0000-000000000002') $$,
  '42501', 'The inspection plan responsible is assigned by the client', 'insp G: the FM cannot send another client member');
SELECT throws_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_template_id => 'd9b00000-0000-0000-0000-0000000000a1', p_title => 'Inspección bomba (FM)', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_frequency => 'monthly', p_plan_id => 'd9b30000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'd9300000-0000-0000-0000-000000000013') $$,
  '42501', 'The inspection plan responsible is assigned by the client', 'insp H: the FM cannot send its own FM membership');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_template_id => 'd9b00000-0000-0000-0000-0000000000a1', p_title => 'Inspección bomba (FM)', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_frequency => 'monthly', p_plan_id => 'd9b30000-0000-0000-0000-0000000000a1') $$,
  'insp I: the FM omits the responsible (NULL); the edit of an existing plan is valid');
SELECT ok((SELECT responsible_member_id IS NULL AND created_by_user_id IS NULL
           FROM public.upsert_inspection_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_template_id => 'd9b00000-0000-0000-0000-0000000000a1', p_title => 'Inspección nueva FM', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_frequency => 'monthly')),
  'insp J: a new delegated plan returns no ids');
SELECT ok((SELECT responsible_member_id IS NULL AND created_by_user_id IS NULL FROM public.create_inspection_run_from_plan('d9b30000-0000-0000-0000-0000000000a1'))
      AND (SELECT responsible_member_id IS NULL AND created_by_user_id IS NULL
           FROM public.submit_inspection_run('d9b50000-0000-0000-0000-0000000000a1', now() - interval '1 hour', now(),
             '[{"template_item_id":"d9b10000-0000-0000-0000-0000000000a1","response_option_id":"d9b20000-0000-0000-0000-0000000000a1"}]'::jsonb)),
  'insp: create_inspection_run_from_plan and submit_inspection_run return no ids to the FM');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000014');
SELECT ok((SELECT string_agg(to_jsonb(p)::text, '') FROM public.get_inspection_plans('d9200000-0000-0000-0000-0000000000a1', true) p) !~ 'd9300000-0000-0000-0000-00000000000[1-6]'
      AND (SELECT string_agg(to_jsonb(r)::text, '') FROM public.get_inspection_runs('d9200000-0000-0000-0000-0000000000a1', NULL) r) !~ 'd9300000-0000-0000-0000-00000000000[1-6]',
  'insp: an FM technician gets no client member ids either');
RESET ROLE;
SELECT results_eq($$ SELECT title, responsible_member_id FROM public.inspection_plans WHERE id = 'd9b30000-0000-0000-0000-0000000000a1' $$,
  $$ VALUES ('Inspección bomba (FM)'::text, 'd9300000-0000-0000-0000-000000000003'::uuid) $$,
  'insp E: the FM edit persisted and the stored responsible is identical');
SELECT is((SELECT responsible_member_id FROM public.inspection_plans WHERE title = 'Inspección nueva FM'), NULL,
  'insp J: the new delegated plan has no responsible');
SELECT is((SELECT responsible_member_id FROM public.inspection_runs WHERE plan_id = 'd9b30000-0000-0000-0000-0000000000a1' AND created_by_user_id = 'd9100000-0000-0000-0000-000000000013'),
  'd9300000-0000-0000-0000-000000000003'::uuid, 'insp: the FM-created run still carries the client responsible server-side');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000002');
SELECT is((SELECT responsible_member_id FROM public.get_inspection_plans('d9200000-0000-0000-0000-0000000000a1', true) WHERE id = 'd9b30000-0000-0000-0000-0000000000a1'), 'd9300000-0000-0000-0000-000000000003'::uuid,
  'insp K: the direct client still sees responsible_member_id');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_template_id => 'd9b00000-0000-0000-0000-0000000000a1', p_title => 'Inspección bomba (FM)', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_frequency => 'monthly', p_plan_id => 'd9b30000-0000-0000-0000-0000000000a1', p_responsible_member_id => 'd9300000-0000-0000-0000-000000000002') $$,
  'insp K: the direct client still changes the responsible');
SELECT lives_ok($$ SELECT public.upsert_inspection_plan(p_organization_id => 'd9200000-0000-0000-0000-0000000000a1', p_template_id => 'd9b00000-0000-0000-0000-0000000000a1', p_title => 'Inspección bomba (FM)', p_asset_id => 'd9400000-0000-0000-0000-0000000000a1', p_frequency => 'monthly', p_plan_id => 'd9b30000-0000-0000-0000-0000000000a1', p_responsible_member_id => NULL) $$,
  'insp K: the direct client still clears it (historic semantics)');
RESET ROLE;
SELECT is((SELECT responsible_member_id FROM public.inspection_plans WHERE id = 'd9b30000-0000-0000-0000-0000000000a1'), NULL, 'insp K: the direct clear persisted');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 10. Regresión del camino directo del cliente
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.requests WHERE id = 'd98e0000-0000-0000-0000-0000000000a1'), 1::bigint, 'direct: client requester still reads through RLS');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT * FROM public.set_request_audience('d98e0000-0000-0000-0000-0000000000a4', true, '{}') $$, 'direct: client owner still manages the audience');
SELECT throws_ok($$ SELECT * FROM public.set_request_audience('d98e0000-0000-0000-0000-0000000000a4', false, '{}') $$,
  'P0001', 'Selecciona al menos un proveedor para enviar una invitación privada.', 'direct: private without providers is rejected for the client too');
SELECT ok((SELECT is_public AND provider_organization_ids = '{}'::uuid[]
           FROM public.set_request_audience('d98e0000-0000-0000-0000-0000000000a4', true, '{}')), 'direct: set_request_audience returns the historic shape');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT public.create_internal_work_order_from_request('d98e0000-0000-0000-0000-0000000000a2') $$, 'direct: client manager still generates the internal OT');

-- -------------------------------------------------------------------------
-- E1-FIX02. Historical scope is additive: sent/drafts are unchanged;
-- quoted and completed are read-only in the UI, with no tenant leakage.
-- -------------------------------------------------------------------------
RESET ROLE;
INSERT INTO public.requests
  (id, organization_id, request_number, title, description, asset, location,
   service_type, deadline, status, request_type, is_public, created_by)
VALUES
  ('d98e0000-0000-0000-0000-0000000000a8',
   'd9200000-0000-0000-0000-0000000000a1',
   'REQ-E1-COMPLETED', 'Histórico completado', 'Solo lectura', 'Activo',
   'Lima', 'correctivo', now() + interval '10 days', 'completed',
   'external', true, 'fixture');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000013');
SELECT ok(EXISTS(
  SELECT 1 FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','history')) e
  WHERE e->>'request_number' = 'REQ-9C4-A4'
), 'E1 history includes an authorized quoted request');
SELECT ok(EXISTS(
  SELECT 1 FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','history')) e
  WHERE e->>'request_number' = 'REQ-E1-COMPLETED'
), 'E1 history includes an authorized completed request');
SELECT ok(EXISTS(
  SELECT 1 FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','history')) e
  WHERE e->>'request_number' = 'REQ-9C4-A1'
), 'E1 history retains sent requests');
SELECT ok(NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','history')) e
  WHERE e->>'request_number' = 'REQ-9C4-A3'
), 'E1 history excludes client drafts');
SELECT ok(NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','history')) e
  WHERE e->>'request_number' = 'REQ-9C4-A5'
), 'E1 history excludes annulled requests');
SELECT ok(NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','history')) e
  WHERE e->>'request_number' = 'REQ-9C4-B1'
), 'E1 history excludes another tenant');
SELECT ok(NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','sent')) e
  WHERE e->>'request_number' = 'REQ-9C4-A4'
), 'E1 legacy sent scope remains limited to sent requests');
SELECT ok(NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','sent')) e
  WHERE e->>'request_number' = 'REQ-E1-COMPLETED'
), 'E1 legacy sent scope excludes completed requests');
SELECT is((SELECT (e->>'can_edit')::boolean
  FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','history')) e
  WHERE e->>'request_number' = 'REQ-E1-COMPLETED'), false,
  'E1 completed request cannot be edited');
SELECT is((SELECT (e->>'can_annul')::boolean
  FROM jsonb_array_elements(public.get_facility_management_requests(
    'd9200000-0000-0000-0000-0000000000a1','history')) e
  WHERE e->>'request_number' = 'REQ-E1-COMPLETED'), false,
  'E1 completed request cannot be annulled');
SELECT ok(public.get_facility_management_request(
  'd9200000-0000-0000-0000-0000000000a1',
  'd98e0000-0000-0000-0000-0000000000a8') IS NOT NULL,
  'E1 completed request details remain readable');
SELECT ok(public.get_facility_management_requests(
  'd9200000-0000-0000-0000-0000000000a1','history')::text !~ 'fm-requests\\.test',
  'E1 history retains person/email minimization');
SELECT pg_temp.as_user('d9100000-0000-0000-0000-000000000019');
SELECT throws_ok($ SELECT public.get_facility_management_requests(
  'd9200000-0000-0000-0000-0000000000a1','history') $,
  '42501', NULL, 'E1 history rejects unassigned FM manager');

SELECT * FROM finish();
ROLLBACK;
