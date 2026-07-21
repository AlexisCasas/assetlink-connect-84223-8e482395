# AI_CONTEXT.md

## Sucursales por tenant

- `client_branches` usa `organization_id` para su aislamiento tenant-aware;
  `client_email` permanece sólo como campo legacy temporal.
- BranchesList usa `currentOrganization` y owner/admin/manager pueden administrar;
  los demás roles mantienen acceso de sólo lectura, respaldado por RLS.
- RequestForm filtra sus sucursales activas por la organización actual, sin migrar
  aún las solicitudes a tenant-aware.

## Selector de organización activa

- Se creó `OrganizationSwitcher` y se integró debajo del encabezado de Sidebar.
- Muestra organización actual, tipo y rol; permite cambiar entre organizaciones
  reales del usuario cuando tiene más de una membresía.
- La preferencia visual se guarda en `onefacility.currentOrganizationId` y se
  valida siempre contra las organizaciones cargadas desde Supabase. No es fuente
  de permisos, tenants ni autorización.
- Hasta que existan organizaciones y memberships reales, el selector muestra un
  estado discreto de “Sin organización asignada”.

## Backend administrativo de organizaciones

Las operaciones administrativas se realizan sólo mediante Edge Functions con JWT
válido y autorización comprobada en backend. `SUPABASE_SERVICE_ROLE_KEY` se usa
únicamente dentro de las funciones y nunca se expone al frontend.

- `admin-create-organization`: sólo `platform_admin`; crea una organización y,
  opcionalmente, un owner existente o una invitación pendiente de owner.
- `admin-invite-organization-member`: `platform_admin` u `owner`/`admin` del
  tenant; registra una invitación pendiente. No gestiona organizaciones de tipo
  `platform_admin` ni envía correo todavía.
- `admin-add-existing-member`: `platform_admin` u `owner`/`admin` del tenant;
  asigna o reactiva una membresía para un usuario Auth ya existente.

### Bootstrap temporal del primer platform admin

Ejecutar **solamente en local o staging** desde SQL Editor con una cuenta de
operador. No existe endpoint público para bootstrap. Reemplazar los UUIDs:

```sql
-- El usuario debe existir en auth.users. Esta sentencia es segura si el trigger
-- ya creó el profile.
insert into public.profiles (id, email, name)
select id, email, coalesce(raw_user_meta_data->>'name', split_part(email, '@', 1))
from auth.users
where id = '<AUTH_USER_UUID>'::uuid
on conflict (id) do nothing;

insert into public.organizations (name, organization_type, created_by)
values ('One Facility Platform', 'platform_admin', '<AUTH_USER_UUID>')
returning id;

insert into public.organization_members (organization_id, user_id, role)
values ('<PLATFORM_ORGANIZATION_UUID>', '<AUTH_USER_UUID>', 'owner');
```

Después de este bootstrap, las funciones administrativas son la ruta prevista
para crear organizaciones y membresías. Las invitaciones se guardan en
`organization_invitations`; su aceptación y el correo se implementarán en una
feature posterior.

## Proyecto
One Facility / Assetlink Connect.

## Objetivo del producto
SaaS multi-tenant para gestión de mantenimiento, solicitudes, cotizaciones, proveedores, facility managers, subcontratistas, órdenes de trabajo, evidencias y cierre de servicios.

## Estado actual
La rama `onefacility-design` contiene el mockup visual generado con Lovable.

La rama `productization/mvp` será la base de desarrollo productivo.

Desde este punto, Lovable se usará como diseñador visual y fuente de componentes UI, pero no como rama productiva directa.

## Ramas principales
- `onefacility-design`: rama de diseño / mockup / Lovable.
- `productization/mvp`: rama base productiva.
- `feature/*`: ramas por módulo o tarea.
- `fix/*`: correcciones puntuales.

## Stack tecnológico
Frontend:
- React
- Vite
- TypeScript strict
- Tailwind CSS
- shadcn/ui

Backend:
- Supabase
- PostgreSQL
- Supabase Auth
- Row Level Security activo por defecto

Archivos:
- Cloudflare R2 compatible con S3
- Supabase solo guardará metadatos, referencias y enlaces firmados

Deploy:
- Local con Supabase CLI
- Staging en Vercel
- Producción en Vercel

## Modelo multi-tenant
La entidad central es `organizations`, no el usuario.

Relación base:

auth.users
→ profiles
→ organization_members
→ organizations

Tipos de organización esperados:
- client_company
- provider_company
- facility_manager
- subcontractor_company
- platform_admin

Roles internos esperados:
- owner
- admin
- manager
- requester
- quote_manager
- technician
- operator
- viewer

## Reglas críticas
- No usar `localStorage` como fuente de verdad para permisos, usuarios, tenants o datos productivos.
- No hardcodear IDs como `client-1`, `provider-1`, `user-1` en lógica productiva.
- No crear tablas sin migración.
- No dejar policies abiertas tipo “Anyone can view”.
- No mezclar lógica mock con lógica productiva.
- Todo acceso a datos debe respetar tenant y RLS.
- Todo módulo productivo debe incluir UI, DB, RLS, validaciones, manejo de errores y logs mínimos.

## Flujo Lovable → Producción
1. Lovable trabaja sobre `onefacility-design`.
2. Los componentes visuales útiles se migran manualmente a ramas `feature/*`.
3. Codex o Claude Code refactorizan esos componentes.
4. Se eliminan mocks.
5. Se conectan hooks reales de Supabase.
6. Se actualizan tipos.
7. Se agregan migraciones y RLS.
8. Se prueba en local/staging.
9. Se hace PR hacia `productization/mvp`.

## Próximo objetivo técnico
Implementar la base multi-tenant productiva:

- organizations
- profiles
- organization_members
- roles/enums
- activity_logs
- audit_logs
- hooks base
- RLS inicial
- separación entre demo/mock y productivo

## Última actualización
Inicio de la rama `productization/mvp`.

## Base multi-tenant implementada

- Se agregó una migración de base con `organizations`, `organization_members`,
  `organization_relationships`, `activity_logs` y `audit_logs`.
- La identidad real de proveedor y facility manager es una organización. La tabla
  `providers` se conserva temporalmente para el mockup y admite `organization_id` nullable.
- Se añadieron columnas de transición para organizaciones en `providers`,
  `client_branches`, `requests` y `quotes`.
- Las nuevas tablas usan RLS y helpers de membresía. El alta de organizaciones y
  las invitaciones deben realizarse desde un backend/Edge Function administrativo.
- `AuthContext` expone organizaciones, membresía y organización activa sin usar
  localStorage como fuente de permisos.

## Detalles de solicitudes por tenant

- `request_details` hereda el tenant desde `request_id` hacia
  `requests.organization_id`; no duplica `organization_id`.
- Sus policies RLS validan membresia y rol contra la solicitud padre para
  lectura, insercion, actualizacion y eliminacion.
- Storage de `attachment_urls`, `request_providers`, providers, cotizaciones y
  chats siguen pendientes de migracion tenant-aware.

## Solicitudes por tenant

- `requests.organization_id` define el tenant de cada solicitud. Sus policies
  RLS se basan en membresia y rol de organizacion, no en `localStorage` ni email.
- `RequestList` y `DraftList` cargan solo la organizacion activa. `RequestForm`
  exige una organizacion activa y persiste `organization_id` y `created_by_user_id`.
- La migracion de visibilidad para `PublicRequestList`, `ProviderRequestList`,
  cotizaciones, asignaciones, detalle y chat sigue pendiente; no se deben abrir
  policies de `requests` como solucion temporal.
- `VITE_ENABLE_DEMO_SEED=false` desactiva el seeding demo automático.
