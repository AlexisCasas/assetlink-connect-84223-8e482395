-- Fase 1 · Punto 9C.5 — acceso operativo de Facility Manager a Cotizaciones
-- (…_facility_manager_quotes_access.sql).
-- Se ejecuta con: supabase test db --local
--
-- Cada intento corre como `authenticated` con un auth.uid() sintético.
-- Errores: 42501 = sin permiso / RLS / sin EXECUTE; 55000 = estado no
-- permitido; 22023 = entrada inválida; P0001 = regla histórica (RAISE sin
-- código) del flujo directo del cliente.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(162);

-- -------------------------------------------------------------------------
-- Fixture (sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('e9100000-0000-0000-0000-000000000001', 'ca-owner@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000002', 'ca-manager@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000003', 'ca-technician@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000011', 'fa-owner@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000012', 'fa-admin@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000013', 'fa-manager@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000014', 'fa-technician@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000015', 'fa-requester@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000016', 'fa-viewer@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000017', 'fa-quote-manager@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000018', 'fa-operator@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000019', 'fa-manager-unassigned@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-00000000001a', 'fa-requester-inactive@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000021', 'fb-manager@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000031', 'cb-owner@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000041', 'p1-owner@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000042', 'p2-owner@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000043', 'p3-owner@fm-quotes.test', '{}'),
  ('e9100000-0000-0000-0000-000000000051', 'outsider@fm-quotes.test', '{}');

INSERT INTO public.organizations (id, name, organization_type) VALUES
  ('e9200000-0000-0000-0000-0000000000a1', 'Client A', 'client_company'),
  ('e9200000-0000-0000-0000-0000000000b1', 'Client B', 'client_company'),
  ('e9200000-0000-0000-0000-0000000000c1', 'Client C (solo requests.view)', 'client_company'),
  ('e9200000-0000-0000-0000-0000000000d1', 'Client D (solo quotes.view)', 'client_company'),
  ('e9200000-0000-0000-0000-0000000000e1', 'Client E (ver, sin aprobar)', 'client_company'),
  ('e9200000-0000-0000-0000-0000000000f1', 'Client F (aprobar sin quotes.view)', 'client_company'),
  ('e9200000-0000-0000-0000-0000000000a2', 'Client G (solo quotes.manage)', 'client_company'),
  ('e9200000-0000-0000-0000-0000000000a3', 'Client S (suspendida)', 'client_company'),
  ('e9200000-0000-0000-0000-0000000000fa', 'FM A', 'facility_manager'),
  ('e9200000-0000-0000-0000-0000000000fb', 'FM B', 'facility_manager'),
  ('e9200000-0000-0000-0000-000000000091', 'Proveedor P1', 'provider_company'),
  ('e9200000-0000-0000-0000-000000000092', 'Proveedor P2', 'provider_company'),
  ('e9200000-0000-0000-0000-000000000093', 'Proveedor P3', 'provider_company');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('e9300000-0000-0000-0000-000000000001', 'e9200000-0000-0000-0000-0000000000a1', 'e9100000-0000-0000-0000-000000000001', 'owner', true),
  ('e9300000-0000-0000-0000-000000000002', 'e9200000-0000-0000-0000-0000000000a1', 'e9100000-0000-0000-0000-000000000002', 'manager', true),
  ('e9300000-0000-0000-0000-000000000003', 'e9200000-0000-0000-0000-0000000000a1', 'e9100000-0000-0000-0000-000000000003', 'technician', true),
  ('e9300000-0000-0000-0000-000000000011', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000011', 'owner', true),
  ('e9300000-0000-0000-0000-000000000012', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000012', 'admin', true),
  ('e9300000-0000-0000-0000-000000000013', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000013', 'manager', true),
  ('e9300000-0000-0000-0000-000000000014', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000014', 'technician', true),
  ('e9300000-0000-0000-0000-000000000015', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000015', 'requester', true),
  ('e9300000-0000-0000-0000-000000000016', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000016', 'viewer', true),
  ('e9300000-0000-0000-0000-000000000017', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000017', 'quote_manager', true),
  ('e9300000-0000-0000-0000-000000000018', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000018', 'operator', true),
  ('e9300000-0000-0000-0000-000000000019', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000019', 'manager', true),
  ('e9300000-0000-0000-0000-00000000001a', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-00000000001a', 'requester', true),
  ('e9300000-0000-0000-0000-000000000021', 'e9200000-0000-0000-0000-0000000000fb', 'e9100000-0000-0000-0000-000000000021', 'manager', true),
  ('e9300000-0000-0000-0000-000000000031', 'e9200000-0000-0000-0000-0000000000b1', 'e9100000-0000-0000-0000-000000000031', 'owner', true),
  ('e9300000-0000-0000-0000-000000000041', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 'owner', true),
  ('e9300000-0000-0000-0000-000000000042', 'e9200000-0000-0000-0000-000000000092', 'e9100000-0000-0000-0000-000000000042', 'owner', true),
  ('e9300000-0000-0000-0000-000000000043', 'e9200000-0000-0000-0000-000000000093', 'e9100000-0000-0000-0000-000000000043', 'owner', true);

INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status) VALUES
  ('e9700000-0000-0000-0000-0000000000aa', 'e9200000-0000-0000-0000-0000000000a1', 'e9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('e9700000-0000-0000-0000-0000000000bb', 'e9200000-0000-0000-0000-0000000000b1', 'e9200000-0000-0000-0000-0000000000fb', 'facility_management', 'pending'),
  ('e9700000-0000-0000-0000-0000000000cc', 'e9200000-0000-0000-0000-0000000000c1', 'e9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('e9700000-0000-0000-0000-0000000000dd', 'e9200000-0000-0000-0000-0000000000d1', 'e9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('e9700000-0000-0000-0000-0000000000ee', 'e9200000-0000-0000-0000-0000000000e1', 'e9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('e9700000-0000-0000-0000-0000000000ff', 'e9200000-0000-0000-0000-0000000000f1', 'e9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('e9700000-0000-0000-0000-0000000000a2', 'e9200000-0000-0000-0000-0000000000a2', 'e9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('e9700000-0000-0000-0000-0000000000a3', 'e9200000-0000-0000-0000-0000000000a3', 'e9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending');
INSERT INTO public.facility_management_permissions (relationship_id, permission)
SELECT 'e9700000-0000-0000-0000-0000000000aa'::uuid, p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'quotes.view', 'quotes.approve', 'quotes.manage']) p
UNION ALL SELECT 'e9700000-0000-0000-0000-0000000000bb', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'quotes.view', 'quotes.approve']) p
UNION ALL SELECT 'e9700000-0000-0000-0000-0000000000cc', 'requests.view'::public.facility_management_permission
UNION ALL SELECT 'e9700000-0000-0000-0000-0000000000dd', 'quotes.view'::public.facility_management_permission
UNION ALL SELECT 'e9700000-0000-0000-0000-0000000000ee', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'quotes.view']) p
UNION ALL SELECT 'e9700000-0000-0000-0000-0000000000ff', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'quotes.approve']) p
UNION ALL SELECT 'e9700000-0000-0000-0000-0000000000a2', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'quotes.manage']) p
UNION ALL SELECT 'e9700000-0000-0000-0000-0000000000a3', p::public.facility_management_permission
FROM unnest(ARRAY['requests.view', 'quotes.view', 'quotes.approve']) p;
INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id)
SELECT 'e9700000-0000-0000-0000-0000000000aa'::uuid, m::uuid FROM unnest(ARRAY[
  'e9300000-0000-0000-0000-000000000011', 'e9300000-0000-0000-0000-000000000012', 'e9300000-0000-0000-0000-000000000013',
  'e9300000-0000-0000-0000-000000000014', 'e9300000-0000-0000-0000-000000000015', 'e9300000-0000-0000-0000-000000000016',
  'e9300000-0000-0000-0000-000000000017', 'e9300000-0000-0000-0000-000000000018', 'e9300000-0000-0000-0000-00000000001a']) m
UNION ALL SELECT 'e9700000-0000-0000-0000-0000000000bb', 'e9300000-0000-0000-0000-000000000021'
UNION ALL SELECT r::uuid, 'e9300000-0000-0000-0000-000000000013' FROM unnest(ARRAY[
  'e9700000-0000-0000-0000-0000000000cc', 'e9700000-0000-0000-0000-0000000000dd', 'e9700000-0000-0000-0000-0000000000ee',
  'e9700000-0000-0000-0000-0000000000ff', 'e9700000-0000-0000-0000-0000000000a2', 'e9700000-0000-0000-0000-0000000000a3']) r;
UPDATE public.organization_relationships SET status = 'active' WHERE id::text LIKE 'e9700000-%';
UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'e9700000-0000-0000-0000-0000000000a3';
UPDATE public.organization_members SET is_active = false WHERE id = 'e9300000-0000-0000-0000-00000000001a';

-- Solicitudes. Los números 1xx son del cliente A.
INSERT INTO public.requests (id, organization_id, request_number, title, description, asset, location, service_type, deadline, status, request_type, is_public, created_by, min_quotes) VALUES
  ('e98e0000-0000-0000-0000-0000000000a1', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A1', 'Visible (2 de 2)', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 2),
  ('e98e0000-0000-0000-0000-0000000000a2', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A2', 'Oculta (2 de 3)', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 3),
  ('e98e0000-0000-0000-0000-0000000000a4', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A4', 'Borrador', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'draft', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000a5', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A5', 'Anulada', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'anulado', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000a6', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A6', 'Para rechazar', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000a7', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A7', 'Para aprobar (3 cotizaciones)', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 2),
  ('e98e0000-0000-0000-0000-0000000000a8', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A8', 'Cotizada', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'quoted', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000a9', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A9', 'Para aprobar (owner)', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000aa', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-AA', 'Paridad directa', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 2),
  ('e98e0000-0000-0000-0000-0000000000ab', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-AB', 'Paridad delegada', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 2),
  ('e98e0000-0000-0000-0000-0000000000ac', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-AC', 'Para rechazar (admin)', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000b1', 'e9200000-0000-0000-0000-0000000000b1', 'REQ-9C5-B1', 'Cliente B', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000c1', 'e9200000-0000-0000-0000-0000000000c1', 'REQ-9C5-C1', 'Cliente C', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000d1', 'e9200000-0000-0000-0000-0000000000d1', 'REQ-9C5-D1', 'Cliente D', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000e1', 'e9200000-0000-0000-0000-0000000000e1', 'REQ-9C5-E1', 'Cliente E', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000f1', 'e9200000-0000-0000-0000-0000000000f1', 'REQ-9C5-F1', 'Cliente F', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000f2', 'e9200000-0000-0000-0000-0000000000a2', 'REQ-9C5-G1', 'Cliente G', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1),
  ('e98e0000-0000-0000-0000-0000000000f3', 'e9200000-0000-0000-0000-0000000000a3', 'REQ-9C5-S1', 'Cliente S', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 1);
-- Solicitud interna con una cotización heredada.
INSERT INTO public.requests (id, organization_id, request_number, title, description, asset, location, service_type, deadline, status, request_type, is_public, created_by, internal_responsible_member_id) VALUES
  ('e98e0000-0000-0000-0000-0000000000a3', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-A3', 'Interna', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'internal', false, 'fixture', 'e9300000-0000-0000-0000-000000000003');

-- Cotizaciones. Los importes son únicos para poder buscarlos en las respuestas.
INSERT INTO public.quotes (id, request_id, provider_organization_id, created_by_user_id, amount, description, status, subtotal, igv_amount, utilities_amount, general_expenses_amount, base_subtotal, client_observation) VALUES
  ('e9a00000-0000-0000-0000-000000000001', 'e98e0000-0000-0000-0000-0000000000a1', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1001, 'Cot A1/P1', 'submitted', 850, 151, 90, 60, 700, 'obs-privada'),
  ('e9a00000-0000-0000-0000-000000000002', 'e98e0000-0000-0000-0000-0000000000a1', 'e9200000-0000-0000-0000-000000000092', 'e9100000-0000-0000-0000-000000000042', 1002, 'Cot A1/P2', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000003', 'e98e0000-0000-0000-0000-0000000000a1', 'e9200000-0000-0000-0000-000000000093', 'e9100000-0000-0000-0000-000000000043', 1003, 'Cot A1/P3 borrador', 'draft', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000004', 'e98e0000-0000-0000-0000-0000000000a2', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 2001, 'Cot A2/P1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000005', 'e98e0000-0000-0000-0000-0000000000a2', 'e9200000-0000-0000-0000-000000000092', 'e9100000-0000-0000-0000-000000000042', 2002, 'Cot A2/P2', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000006', 'e98e0000-0000-0000-0000-0000000000a3', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 3001, 'Cot interna', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000007', 'e98e0000-0000-0000-0000-0000000000a4', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 4001, 'Cot de borrador', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000008', 'e98e0000-0000-0000-0000-0000000000a5', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 5001, 'Cot de anulada', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000009', 'e98e0000-0000-0000-0000-0000000000a6', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 6001, 'Cot A6', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000010', 'e98e0000-0000-0000-0000-0000000000a7', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 7001, 'Cot A7/P1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000011', 'e98e0000-0000-0000-0000-0000000000a7', 'e9200000-0000-0000-0000-000000000092', 'e9100000-0000-0000-0000-000000000042', 7002, 'Cot A7/P2', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000012', 'e98e0000-0000-0000-0000-0000000000a7', 'e9200000-0000-0000-0000-000000000093', 'e9100000-0000-0000-0000-000000000043', 7003, 'Cot A7/P3', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000013', 'e98e0000-0000-0000-0000-0000000000a8', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 8001, 'Cot A8', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000014', 'e98e0000-0000-0000-0000-0000000000a9', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 9001, 'Cot A9', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000015', 'e98e0000-0000-0000-0000-0000000000aa', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1101, 'Cot AA/P1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000016', 'e98e0000-0000-0000-0000-0000000000aa', 'e9200000-0000-0000-0000-000000000092', 'e9100000-0000-0000-0000-000000000042', 1102, 'Cot AA/P2', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000017', 'e98e0000-0000-0000-0000-0000000000ab', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1101, 'Cot AB/P1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000018', 'e98e0000-0000-0000-0000-0000000000ab', 'e9200000-0000-0000-0000-000000000092', 'e9100000-0000-0000-0000-000000000042', 1102, 'Cot AB/P2', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000019', 'e98e0000-0000-0000-0000-0000000000b1', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1201, 'Cot B1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-00000000001a', 'e98e0000-0000-0000-0000-0000000000c1', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1301, 'Cot C1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-00000000001b', 'e98e0000-0000-0000-0000-0000000000d1', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1401, 'Cot D1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-00000000001c', 'e98e0000-0000-0000-0000-0000000000e1', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1501, 'Cot E1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-00000000001d', 'e98e0000-0000-0000-0000-0000000000f1', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1601, 'Cot F1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-00000000001e', 'e98e0000-0000-0000-0000-0000000000f2', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1701, 'Cot G1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-00000000001f', 'e98e0000-0000-0000-0000-0000000000f3', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1801, 'Cot S1', 'submitted', 0, 0, 0, 0, 0, NULL),
  ('e9a00000-0000-0000-0000-000000000020', 'e98e0000-0000-0000-0000-0000000000ac', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 1901, 'Cot AC', 'submitted', 0, 0, 0, 0, 0, NULL);

-- Solicitud cerrada antes de alcanzar min_quotes (2 de 3 recibidas, envío cerrado).
INSERT INTO public.requests (id, organization_id, request_number, title, description, asset, location, service_type, deadline, status, request_type, is_public, created_by, min_quotes, quotes_closed) VALUES
  ('e98e0000-0000-0000-0000-0000000000ad', 'e9200000-0000-0000-0000-0000000000a1', 'REQ-9C5-AD', 'Cerrada antes del mínimo', 'd', 'x', 'x', 'correctivo', now() + interval '10 days', 'sent', 'external', true, 'fixture', 3, true);
INSERT INTO public.quotes (id, request_id, provider_organization_id, created_by_user_id, amount, description, status) VALUES
  ('e9a00000-0000-0000-0000-000000000021', 'e98e0000-0000-0000-0000-0000000000ad', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000041', 13001, 'Cot AD/P1', 'submitted'),
  ('e9a00000-0000-0000-0000-000000000022', 'e98e0000-0000-0000-0000-0000000000ad', 'e9200000-0000-0000-0000-000000000092', 'e9100000-0000-0000-0000-000000000042', 13002, 'Cot AD/P2', 'submitted');

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
$$;
CREATE FUNCTION pg_temp.quote_of(p_payload jsonb, p_quote uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT e FROM jsonb_array_elements(p_payload->'quotes') e WHERE e->>'id' = p_quote::text;
$$;

CREATE FUNCTION pg_temp.rows_updated() RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN UPDATE public.quotes SET amount = 1; GET DIAGNOSTICS n = ROW_COUNT; RETURN n;
EXCEPTION WHEN insufficient_privilege THEN RETURN 0; END;
$$;
CREATE FUNCTION pg_temp.rows_deleted() RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN DELETE FROM public.quotes; GET DIAGNOSTICS n = ROW_COUNT; RETURN n;
EXCEPTION WHEN insufficient_privilege THEN RETURN 0; END;
$$;

-- -------------------------------------------------------------------------
-- 0. Estructura y grants
-- -------------------------------------------------------------------------
SELECT ok((SELECT bool_and(NOT has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
           FROM pg_proc p WHERE p.oid IN (
             'public.can_view_quotes_as_facility_manager(uuid)'::regprocedure,
             'public.can_approve_quotes_as_facility_manager(uuid)'::regprocedure,
             'public.facility_management_quote_prices_visible(uuid)'::regprocedure,
             'public.facility_management_quote_payload(public.quotes,boolean,boolean)'::regprocedure,
             'public.facility_management_request_quotes_payload(public.requests,boolean,uuid)'::regprocedure)),
  'internal helpers are not executable by authenticated/anon');
SELECT ok((SELECT count(*) = 5 AND bool_and(p.prosecdef AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
                AND NOT has_function_privilege('anon', p.oid, 'EXECUTE') AND array_to_string(p.proconfig, ',') = 'search_path=""')
           FROM pg_proc p WHERE p.oid IN (
             'public.get_facility_management_request_quotes(uuid,uuid)'::regprocedure,
             'public.get_facility_management_quote(uuid,uuid)'::regprocedure,
             'public.get_facility_management_quote_counts(uuid)'::regprocedure,
             'public.approve_facility_management_quote(uuid,uuid)'::regprocedure,
             'public.reject_facility_management_quote(uuid,uuid,text)'::regprocedure)),
  'delegated entrypoints: SECURITY DEFINER, empty search_path, authenticated only');
SELECT ok((SELECT bool_and(p.proconfig IS NOT NULL AND array_to_string(p.proconfig, ',') = 'search_path=""')
           FROM pg_proc p WHERE p.oid IN (
             'public.can_view_quotes_as_facility_manager(uuid)'::regprocedure,
             'public.can_approve_quotes_as_facility_manager(uuid)'::regprocedure,
             'public.facility_management_quote_prices_visible(uuid)'::regprocedure,
             'public.facility_management_quote_payload(public.quotes,boolean,boolean)'::regprocedure,
             'public.facility_management_request_quotes_payload(public.requests,boolean,uuid)'::regprocedure)),
  'internal helpers have an empty search_path');
SELECT is((SELECT array_agg(policyname::text ORDER BY policyname) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'quotes'),
  ARRAY['authorized providers can create quotes', 'authorized providers can delete their organization quotes',
        'authorized providers can update their organization quotes', 'authorized users can view quotes'],
  'quotes keeps exactly its four historic policies');
SELECT ok((SELECT bool_and(COALESCE(qual, '') || COALESCE(with_check, '') !~ 'facility_management') FROM pg_policies
           WHERE schemaname = 'public' AND tablename IN ('quotes', 'requests', 'request_details', 'request_provider_access')),
  'quotes / requests policies are not widened for the facility manager');
SELECT is(
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
     AND (has_table_privilege('anon', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
       OR has_table_privilege('authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))),
  0::bigint, '9C.1H preserved: no meta privileges for anon/authenticated');
SELECT is(public.facility_management_quote_prices_visible('e98e0000-0000-0000-0000-0000000000a1'), true, 'helper: 2 of 2 received => visible');
SELECT is(public.facility_management_quote_prices_visible('e98e0000-0000-0000-0000-0000000000a2'), false, 'helper: 2 of 3 received => hidden');
SELECT is(public.facility_management_quote_prices_visible(gen_random_uuid()), false, 'helper: unknown request => hidden');

SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 1. Quién puede leer
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user(NULL);
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'unauthenticated: list is rejected');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'unauthenticated: approve is rejected');

-- Roles del FM A asignados con requests.view + quotes.view.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000011');
SELECT lives_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, 'FM owner (assigned) can read');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000012');
SELECT lives_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, 'FM admin (assigned) can read');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT lives_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, 'FM manager (assigned) can read');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000015');
SELECT lives_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, 'FM requester (assigned) can read');

-- Roles sin acceso.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'FM technician cannot read quotes');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000016');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'FM viewer cannot read quotes');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000017');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'FM quote_manager role cannot read quotes (delegated)');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000018');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'FM operator cannot read quotes');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000019');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'FM manager NOT assigned cannot read');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-00000000001a');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'assigned FM requester with inactive membership cannot read');

-- Otras personas/organizaciones.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000021');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'FM B cannot read client A (no relationship)');
SELECT lives_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000b1', 'e98e0000-0000-0000-0000-0000000000b1') $$, 'FM B reads its own client B');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'client owner is not an FM: delegated read rejected');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000041');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'provider owner cannot use the delegated read');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000051');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'outsider cannot read');

-- Combinaciones de permisos (el FM manager asignado a cada cliente).
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000c1', 'e98e0000-0000-0000-0000-0000000000c1') $$, '42501', NULL, 'requests.view alone does not open quotes');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000d1', 'e98e0000-0000-0000-0000-0000000000d1') $$, '42501', NULL, 'quotes.view without requests.view does not open quotes');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000f1', 'e98e0000-0000-0000-0000-0000000000f1') $$, '42501', NULL, 'quotes.approve without quotes.view does not open quotes');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a2', 'e98e0000-0000-0000-0000-0000000000f2') $$, '42501', NULL, 'quotes.manage does not open quotes');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a3', 'e98e0000-0000-0000-0000-0000000000f3') $$, '42501', NULL, 'suspended relationship: no access');
SELECT lives_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000e1', 'e98e0000-0000-0000-0000-0000000000e1') $$, 'requests.view + quotes.view opens the read');

-- -------------------------------------------------------------------------
-- 2. Qué devuelve la lectura (importes visibles y ocultos)
-- -------------------------------------------------------------------------
CREATE TEMP TABLE r_visible AS SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') AS p;
CREATE TEMP TABLE r_hidden AS SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a2') AS p;
GRANT SELECT ON r_visible, r_hidden TO authenticated;

SELECT is((SELECT (p->>'prices_visible')::boolean FROM r_visible), true, 'visible: 2 of 2 => prices_visible');
SELECT is((SELECT (p->>'quotes_received')::int FROM r_visible), 2, 'visible: the draft quote is not counted');
SELECT is((SELECT jsonb_array_length(p->'quotes') FROM r_visible), 2, 'visible: the draft quote is not listed');
SELECT is((SELECT (pg_temp.quote_of(p, 'e9a00000-0000-0000-0000-000000000001')->>'amount')::numeric FROM r_visible), 1001::numeric, 'visible: amount is returned');
SELECT is((SELECT (pg_temp.quote_of(p, 'e9a00000-0000-0000-0000-000000000002')->>'amount')::numeric FROM r_visible), 1002::numeric, 'visible: second amount is returned');
SELECT is((SELECT pg_temp.quote_of(p, 'e9a00000-0000-0000-0000-000000000003') FROM r_visible), NULL::jsonb, 'visible: draft quote is absent');
SELECT is((SELECT array_agg(k ORDER BY k) FROM r_visible, jsonb_object_keys(p) k),
  ARRAY['can_approve', 'min_quotes', 'prices_visible', 'quotes', 'quotes_closed', 'quotes_received', 'request_id'],
  'list envelope has exactly the whitelisted keys');
SELECT is((SELECT array_agg(k ORDER BY k) FROM r_visible, jsonb_object_keys(pg_temp.quote_of(p, 'e9a00000-0000-0000-0000-000000000001')) k),
  ARRAY['amount', 'approval_reason', 'approved_at', 'can_approve', 'created_at', 'description', 'id', 'rejected_at', 'rejection_reason', 'request_id', 'status'],
  'quote payload has exactly the whitelisted keys');
SELECT ok((SELECT p::text !~ '(provider_organization_id|provider_id|team_member_id|created_by_user_id|approved_by_user_id|rejected_by_user_id|client_observation|subtotal|igv_amount|utilities|general_expenses|base_subtotal|quote_sections|sales_conditions|work_order|obs-privada|e9200000-0000-0000-0000-00000000009)'
           FROM r_visible), 'visible: no provider, user, economic breakdown, observation or work order data');

SELECT is((SELECT (p->>'prices_visible')::boolean FROM r_hidden), false, 'hidden: 2 of 3 => prices hidden');
SELECT is((SELECT (p->>'quotes_received')::int FROM r_hidden), 2, 'hidden: received count is still shown');
SELECT is((SELECT (p->>'min_quotes')::int FROM r_hidden), 3, 'hidden: min_quotes is shown');
SELECT is((SELECT count(*) FROM r_hidden, jsonb_array_elements(p->'quotes') e WHERE e->'amount' = 'null'::jsonb), 2::bigint, 'hidden: every amount is null');
SELECT ok((SELECT p::text !~ '(2001|2002)' FROM r_hidden), 'hidden: the amounts appear nowhere in the response');
SELECT is((SELECT (p->>'can_approve')::boolean FROM r_hidden), false, 'hidden: cannot approve (FM manager has quotes.approve)');
SELECT is((SELECT (p->>'can_approve')::boolean FROM r_visible), true, 'visible: FM manager can approve');
SELECT is((SELECT count(*) FROM r_hidden, jsonb_array_elements(p->'quotes') e WHERE (e->>'can_approve')::boolean), 0::bigint, 'hidden: no quote is approvable');

SELECT is(public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a3'), NULL::jsonb, 'internal request => NULL');
SELECT is(public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a4'), NULL::jsonb, 'draft request => NULL');
SELECT is(public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000b1'), NULL::jsonb, 'another client''s request via client A => NULL');
SELECT is(public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', gen_random_uuid()), NULL::jsonb, 'unknown request => NULL');
SELECT isnt(public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a5'), NULL::jsonb, 'annulled request is readable');

-- Rol sin quotes.approve: lee con can_approve = false.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000015');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1')->>'can_approve')::boolean, false,
  'FM requester reads but cannot approve (role)');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000e1', 'e98e0000-0000-0000-0000-0000000000e1')->>'can_approve')::boolean, false,
  'no quotes.approve granted: can_approve = false');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a5')->>'can_approve')::boolean, false,
  'annulled request: can_approve = false');

-- Detalle.
SELECT is((public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000001')->'quote'->>'amount')::numeric, 1001::numeric, 'detail: visible amount');
SELECT is((public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000001')->>'quotes_received')::int, 2, 'detail: summary included');
SELECT is((public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000004')->'quote'->'amount'), 'null'::jsonb, 'detail: hidden amount is null');
SELECT ok(public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000004')::text !~ '(2001|2002)', 'detail: hidden amounts appear nowhere');
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000001')->'quote') k),
  ARRAY['amount', 'approval_reason', 'approved_at', 'can_approve', 'created_at', 'description', 'id', 'rejected_at', 'rejection_reason', 'request_id', 'status'],
  'detail: quote has exactly the whitelisted keys');
SELECT is(public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000003'), NULL::jsonb, 'detail: draft quote => NULL');
SELECT is(public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000006'), NULL::jsonb, 'detail: quote of an internal request => NULL');
SELECT is(public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000007'), NULL::jsonb, 'detail: quote of a draft request => NULL');
SELECT is(public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000019'), NULL::jsonb, 'detail: another client''s quote via client A => NULL');
SELECT is(public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', gen_random_uuid()), NULL::jsonb, 'detail: unknown quote => NULL');
SELECT throws_ok($$ SELECT public.get_facility_management_quote('e9200000-0000-0000-0000-0000000000c1', 'e9a00000-0000-0000-0000-00000000001a') $$, '42501', NULL, 'detail: no quotes.view => 42501');

-- Conteos.
SELECT is((SELECT (e->>'submitted_quotes')::int FROM jsonb_array_elements(public.get_facility_management_quote_counts('e9200000-0000-0000-0000-0000000000a1')) e
           WHERE e->>'request_id' = 'e98e0000-0000-0000-0000-0000000000a1'), 2, 'counts: only submitted quotes of the request (the draft quote is not counted)');
SELECT is((SELECT count(*) FROM jsonb_array_elements(public.get_facility_management_quote_counts('e9200000-0000-0000-0000-0000000000a1')) e
           WHERE e->>'request_id' IN ('e98e0000-0000-0000-0000-0000000000a3', 'e98e0000-0000-0000-0000-0000000000a4', 'e98e0000-0000-0000-0000-0000000000b1')),
  0::bigint, 'counts: no internal, draft or another client''s request');
SELECT ok(public.get_facility_management_quote_counts('e9200000-0000-0000-0000-0000000000a1')::text !~ '(amount|provider)', 'counts: no amounts or providers');
SELECT throws_ok($$ SELECT public.get_facility_management_quote_counts('e9200000-0000-0000-0000-0000000000c1') $$, '42501', NULL, 'counts: no quotes.view => 42501');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT public.get_facility_management_quote_counts('e9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'counts: technician => 42501');

-- -------------------------------------------------------------------------
-- 3. La RLS y las políticas de proveedor NO se abren al FM
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT is((SELECT count(*) FROM public.quotes), 0::bigint, 'FM manager reads zero quotes through raw RLS');
SELECT throws_ok($$ INSERT INTO public.quotes (request_id, provider_organization_id, created_by_user_id, amount, description, status)
  VALUES ('e98e0000-0000-0000-0000-0000000000a1', 'e9200000-0000-0000-0000-0000000000fa', 'e9100000-0000-0000-0000-000000000013', 1, 'FM como proveedor', 'submitted') $$,
  '42501', NULL, 'FM cannot insert a quote as a provider (own org)');
SELECT throws_ok($$ INSERT INTO public.quotes (request_id, provider_organization_id, created_by_user_id, amount, description, status)
  VALUES ('e98e0000-0000-0000-0000-0000000000a1', 'e9200000-0000-0000-0000-000000000091', 'e9100000-0000-0000-0000-000000000013', 1, 'FM suplantando', 'submitted') $$,
  '42501', NULL, 'FM cannot insert a quote on behalf of a provider');
SELECT is(pg_temp.rows_updated(), 0::bigint, 'FM cannot update any quote');
SELECT is(pg_temp.rows_deleted(), 0::bigint, 'FM cannot delete any quote');
SELECT is(public.can_provider_quote_request('e98e0000-0000-0000-0000-0000000000a1', 'e9200000-0000-0000-0000-0000000000fa'), false, 'FM organization cannot quote a request');
SELECT is(public.is_provider_facing_organization('e9200000-0000-0000-0000-0000000000fa'), false, 'FM is not provider-facing');
SELECT throws_ok($$ SELECT public.approve_quote('e9a00000-0000-0000-0000-000000000009') $$, 'P0001', 'Not authorized to approve this quote', 'FM cannot use the direct approve_quote');
SELECT throws_ok($$ SELECT public.reject_quote('e9a00000-0000-0000-0000-000000000009', 'x') $$, 'P0001', 'Not authorized to reject this quote', 'FM cannot use the direct reject_quote');
SELECT is((SELECT count(*) FROM public.work_orders), 0::bigint, 'FM reads zero work orders (not delegated in 9C.5)');
SELECT is((SELECT count(*) FROM public.organization_notifications), 0::bigint, 'FM reads zero client notifications');

-- -------------------------------------------------------------------------
-- 4. Aprobar / rechazar: quién puede
-- -------------------------------------------------------------------------
-- q09 (A6, visible, en revisión) para los intentos negativos.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000015');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'FM requester cannot approve (role)');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009', 'x') $$, '42501', NULL, 'FM requester cannot reject (role)');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'FM technician cannot approve');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000016');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'FM viewer cannot approve');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000017');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'FM quote_manager role cannot approve');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000019');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'FM manager NOT assigned cannot approve');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-00000000001a');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'inactive membership cannot approve');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000021');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'FM B cannot approve client A''s quote');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'client owner cannot use the delegated approve');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000041');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'provider cannot approve its own quote');

SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000e1', 'e9a00000-0000-0000-0000-00000000001c') $$, '42501', NULL, 'quotes.view without quotes.approve: cannot approve');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000f1', 'e9a00000-0000-0000-0000-00000000001d') $$, '42501', NULL, 'quotes.approve without quotes.view: cannot approve');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a2', 'e9a00000-0000-0000-0000-00000000001e') $$, '42501', NULL, 'quotes.manage does not approve');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a3', 'e9a00000-0000-0000-0000-00000000001f') $$, '42501', NULL, 'suspended relationship: cannot approve');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000e1', 'e9a00000-0000-0000-0000-00000000001c', 'x') $$, '42501', NULL, 'quotes.view without quotes.approve: cannot reject');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a3', 'e9a00000-0000-0000-0000-00000000001f', 'x') $$, '42501', NULL, 'suspended relationship: cannot reject');

-- UUID de otro cliente / borrador / inexistente: la misma respuesta que una falta de permiso.
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000019') $$, '42501', NULL, 'approve: another client''s quote via client A => 42501');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000019', 'x') $$, '42501', NULL, 'reject: another client''s quote via client A => 42501');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000007') $$, '42501', NULL, 'approve: quote of a draft request => 42501');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', gen_random_uuid()) $$, '42501', NULL, 'approve: unknown quote => 42501');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000b1', 'e9a00000-0000-0000-0000-000000000009') $$, '42501', NULL, 'approve: no relationship with that client => 42501');

-- Estados no permitidos.
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000006') $$, '55000', NULL, 'approve: quote on an internal request => 55000');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000008') $$, '55000', NULL, 'approve: annulled request => 55000');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000008', 'x') $$, '55000', NULL, 'reject: annulled request => 55000');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000003') $$, '55000', NULL, 'approve: a draft quote is not approvable => 55000');

-- Importes ocultos: tampoco se decide a ciegas.
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000004') $$, '55000', NULL, 'approve: amounts still hidden => 55000');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000004', 'x') $$, '55000', NULL, 'reject: amounts still hidden => 55000');

-- Entrada inválida.
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009', repeat('x', 1001)) $$, '22023', NULL, 'reject: reason over 1000 chars => 22023');

-- Nada cambió en los intentos fallidos (se lee como superusuario).
RESET ROLE;
SELECT is((SELECT count(*) FROM public.quotes WHERE id IN (
  'e9a00000-0000-0000-0000-000000000004', 'e9a00000-0000-0000-0000-000000000005', 'e9a00000-0000-0000-0000-000000000006',
  'e9a00000-0000-0000-0000-000000000008', 'e9a00000-0000-0000-0000-000000000009', 'e9a00000-0000-0000-0000-000000000019') AND status = 'submitted'),
  6::bigint, 'failed attempts changed nothing');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE action LIKE 'facility_management.quote_%'), 0::bigint, 'failed attempts wrote no audit rows');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 5. Aprobar y rechazar con éxito
-- -------------------------------------------------------------------------
-- 5.1 Aprobar (manager) con tres cotizaciones: las otras en revisión se rechazan.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
CREATE TEMP TABLE r_approved AS SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000011') AS p;
GRANT SELECT ON r_approved TO authenticated;
SELECT is((SELECT p->>'status' FROM r_approved), 'approved', 'approve: returns the approved quote');
SELECT is((SELECT (p->>'amount')::numeric FROM r_approved), 7002::numeric, 'approve: amount is visible in the response');
SELECT is((SELECT array_agg(k ORDER BY k) FROM r_approved, jsonb_object_keys(p) k),
  ARRAY['amount', 'approval_reason', 'approved_at', 'can_approve', 'created_at', 'description', 'id', 'rejected_at', 'rejection_reason', 'request_id', 'status'],
  'approve: response has exactly the whitelisted keys');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000011') $$, '55000', NULL, 'approve: already approved => 55000');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000010') $$, '55000', NULL, 'approve: a sibling auto-rejected quote cannot be approved afterwards');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000011', 'x') $$, '55000', NULL, 'reject: an approved quote cannot be rejected');
RESET ROLE;
SELECT is((SELECT status || '/' || approved_by_user_id::text FROM public.quotes WHERE id = 'e9a00000-0000-0000-0000-000000000011'),
  'approved/e9100000-0000-0000-0000-000000000013', 'approve: the FM user is recorded as approver');
SELECT is((SELECT count(*) FROM public.quotes WHERE request_id = 'e98e0000-0000-0000-0000-0000000000a7' AND status = 'rejected' AND rejection_reason = 'Not selected'
           AND rejected_by_user_id = 'e9100000-0000-0000-0000-000000000013'), 2::bigint, 'approve: the two other quotes are rejected as "Not selected"');
SELECT is((SELECT count(*) FROM public.quotes WHERE id IN ('e9a00000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-000000000004', 'e9a00000-0000-0000-0000-000000000019') AND status = 'submitted'),
  3::bigint, 'approve: quotes of other requests/clients are untouched');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE action = 'facility_management.quote_approved' AND organization_id = 'e9200000-0000-0000-0000-0000000000a1'
           AND actor_user_id = 'e9100000-0000-0000-0000-000000000013' AND record_id = 'e9a00000-0000-0000-0000-000000000011'
           AND new_data->'auto_rejected_quote_ids' @> '"e9a00000-0000-0000-0000-000000000010"'::jsonb), 1::bigint,
  'approve: audited against the client organization');
SELECT ok((SELECT bool_and((old_data::text || new_data::text) !~ '(7001|7002|7003|amount)') FROM public.audit_logs WHERE action LIKE 'facility_management.quote_%'),
  'audit rows contain no amounts');
SELECT is((SELECT count(*) FROM public.organization_notifications WHERE organization_id = 'e9200000-0000-0000-0000-000000000092' AND type = 'quote_approved'), 1::bigint,
  'approve: the provider is notified as in the direct flow');
SET LOCAL ROLE authenticated;

-- Conteos y resumen coherentes después de pasar de submitted a approved/rejected.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT is((SELECT count(*) FROM jsonb_array_elements(public.get_facility_management_quote_counts('e9200000-0000-0000-0000-0000000000a1')) e
           WHERE e->>'request_id' = 'e98e0000-0000-0000-0000-0000000000a7'), 0::bigint, 'counts: after approving, the request has no quotes under review');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a7')->>'quotes_received')::int, 3,
  'summary: quotes_received does not drop when quotes become approved/rejected');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a7')->>'prices_visible')::boolean, true,
  'summary: amounts stay visible after the decision');
SELECT is((SELECT array_agg(e->>'status' ORDER BY e->>'status') FROM jsonb_array_elements(public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a7')->'quotes') e),
  ARRAY['approved', 'rejected', 'rejected'], 'summary: one approved, the others rejected');
SELECT is((SELECT count(*) FROM jsonb_array_elements(public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a7')->'quotes') e WHERE (e->>'can_approve')::boolean),
  0::bigint, 'summary: no quote is left to decide (per-quote can_approve = false)');

-- 5.2 Aprobar (admin) en una solicitud 'quoted' y owner en otra.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000012');
SELECT lives_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000013') $$, 'FM admin approves on a quoted request');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000011');
SELECT lives_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000014') $$, 'FM owner approves');

-- 5.3 Rechazar con razón (trim) y sin razón.
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
CREATE TEMP TABLE r_rejected AS SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009', '  Fuera de presupuesto  ') AS p;
GRANT SELECT ON r_rejected TO authenticated;
SELECT is((SELECT p->>'status' FROM r_rejected), 'rejected', 'reject: returns the rejected quote');
SELECT is((SELECT p->>'rejection_reason' FROM r_rejected), 'Fuera de presupuesto', 'reject: reason is trimmed');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009', 'otra') $$, '55000', NULL, 'reject: already rejected => 55000');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000009') $$, '55000', NULL, 'approve: a rejected quote cannot be approved');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000012');
SELECT is((public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000020', '   ')->'rejection_reason'), 'null'::jsonb, 'reject: blank reason is stored as NULL');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT is((SELECT COALESCE(sum((e->>'submitted_quotes')::int), 0) FROM jsonb_array_elements(public.get_facility_management_quote_counts('e9200000-0000-0000-0000-0000000000a1')) e), 11::bigint,
  'counts: only the quotes still under review remain after approve/reject');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.audit_logs WHERE action = 'facility_management.quote_rejected' AND organization_id = 'e9200000-0000-0000-0000-0000000000a1'), 2::bigint, 'reject: both rejections are audited');
SELECT is((SELECT new_data->>'has_reason' FROM public.audit_logs WHERE action = 'facility_management.quote_rejected' AND record_id = 'e9a00000-0000-0000-0000-000000000009'), 'true',
  'reject: audit records only whether a reason existed');
SELECT is((SELECT count(*) FROM public.organization_notifications WHERE organization_id = 'e9200000-0000-0000-0000-000000000091' AND type = 'quote_rejected'), 3::bigint,
  'reject: providers are notified (A7 not selected + two rejections)');
SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 6. Paridad con el flujo directo
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT public.approve_quote('e9a00000-0000-0000-0000-000000000015') $$, 'direct: client owner approves through the historic RPC (unchanged)');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT lives_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000017') $$, 'delegated: FM manager approves the equivalent quote');
RESET ROLE;
SELECT is(
  (SELECT jsonb_agg(jsonb_build_object('status', status, 'reason', rejection_reason, 'approved', approved_at IS NOT NULL, 'rejected', rejected_at IS NOT NULL) ORDER BY amount, status)
   FROM public.quotes WHERE request_id = 'e98e0000-0000-0000-0000-0000000000aa'),
  (SELECT jsonb_agg(jsonb_build_object('status', status, 'reason', rejection_reason, 'approved', approved_at IS NOT NULL, 'rejected', rejected_at IS NOT NULL) ORDER BY amount, status)
   FROM public.quotes WHERE request_id = 'e98e0000-0000-0000-0000-0000000000ab'),
  'direct and delegated approvals leave the same state on equivalent requests');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000002');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.quotes WHERE request_id = 'e98e0000-0000-0000-0000-0000000000a2'), 2::bigint, 'direct: the client still reads its quotes through RLS (amounts included)');
SELECT is((SELECT sum(amount) FROM public.quotes WHERE request_id = 'e98e0000-0000-0000-0000-0000000000a2'), 4003::numeric, 'direct: raw amounts are untouched by the delegated rule');
SELECT is((SELECT count(*) FROM public.quotes WHERE request_id = 'e98e0000-0000-0000-0000-0000000000b1'), 0::bigint, 'direct: client A still cannot read client B quotes');

-- -------------------------------------------------------------------------
-- 6b. Solicitud cerrada antes de alcanzar min_quotes, y conteos tras la paridad
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT is((SELECT COALESCE(sum((e->>'submitted_quotes')::int), 0) FROM jsonb_array_elements(public.get_facility_management_quote_counts('e9200000-0000-0000-0000-0000000000a1')) e), 7::bigint,
  'counts: the direct and the delegated approvals of section 6 leave the same remainder');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000ad')->>'quotes_closed')::boolean, true,
  'closed before min_quotes: the closed flag is reported');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000ad')->>'prices_visible')::boolean, false,
  'closed before min_quotes: closing does NOT reveal amounts (current rule: only quotes >= min_quotes)');
SELECT ok(public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000ad')::text !~ '(13001|13002)',
  'closed before min_quotes: the amounts appear nowhere');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000ad')->>'can_approve')::boolean, false,
  'closed before min_quotes: the delegate cannot decide');
SELECT throws_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000021') $$, '55000', NULL,
  'closed before min_quotes: approve => 55000 (request blocked for the delegate)');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000021', 'x') $$, '55000', NULL,
  'closed before min_quotes: reject => 55000');
-- Escape existente (sin cambiar reglas): bajar min_quotes editando la solicitud.
RESET ROLE;
UPDATE public.requests SET min_quotes = 2 WHERE id = 'e98e0000-0000-0000-0000-0000000000ad';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT is((public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000ad')->>'prices_visible')::boolean, true,
  'lowering min_quotes (request edit) reveals the amounts');
SELECT lives_ok($$ SELECT public.approve_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000021') $$,
  'lowering min_quotes unblocks the delegate');

-- -------------------------------------------------------------------------
-- 7. El acceso se corta de inmediato
-- -------------------------------------------------------------------------
RESET ROLE;
UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'e9700000-0000-0000-0000-0000000000aa';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'suspended relationship cuts the read');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000001', 'x') $$, '42501', NULL, 'suspended relationship cuts the decision');
RESET ROLE;
UPDATE public.organization_relationships SET status = 'active' WHERE id = 'e9700000-0000-0000-0000-0000000000aa';
DELETE FROM public.facility_management_permissions WHERE relationship_id = 'e9700000-0000-0000-0000-0000000000aa' AND permission = 'quotes.view';
SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'revoking quotes.view cuts the read');
SELECT throws_ok($$ SELECT public.reject_facility_management_quote('e9200000-0000-0000-0000-0000000000a1', 'e9a00000-0000-0000-0000-000000000001', 'x') $$, '42501', NULL, 'revoking quotes.view cuts the decision even with quotes.approve');
RESET ROLE;
DELETE FROM public.facility_management_relationship_members WHERE relationship_id = 'e9700000-0000-0000-0000-0000000000aa' AND organization_member_id = 'e9300000-0000-0000-0000-000000000013';
INSERT INTO public.facility_management_permissions (relationship_id, permission) VALUES ('e9700000-0000-0000-0000-0000000000aa', 'quotes.view');
SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT public.get_facility_management_request_quotes('e9200000-0000-0000-0000-0000000000a1', 'e98e0000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'unassigning the member cuts the read');

SELECT * FROM finish();
ROLLBACK;
