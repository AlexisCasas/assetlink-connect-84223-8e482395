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

## Cotizaciones por tenant

- `quotes.provider_organization_id` es la identidad productiva de una
  cotización. `provider_id` y `team_member_id` se conservan como campos legacy
  nullable para compatibilidad visual y futuras tareas de backfill.
- `QuoteForm`, `ProviderRequestList` y `PublicRequestList` usan la
  organización activa. Un proveedor o facility manager autorizado solo puede
  cotizar solicitudes no-draft, publicas o con `request_provider_access` activo.
- RLS permite a la organización proveedora ver solo sus propias cotizaciones y
  al tenant cliente leer las cotizaciones de sus solicitudes. Aprobaciones,
  chats, notificaciones y ordenes de trabajo siguen pendientes de migración.

## Aprobacion de cotizaciones por tenant

- El cliente dueno de la solicitud usa las RPC `approve_quote` y
  `reject_quote`; ambas validan tenant y roles en base de datos.
- El proveedor no puede aprobar ni rechazar. El cliente tampoco recibe una
  policy `UPDATE` general sobre importes ni detalles de la cotizacion.
- Permanecen pendientes notificaciones, chat, ordenes de trabajo y aprobacion
  avanzada por limites.

## Notificaciones de cotizaciones por tenant

- `organization_notifications` es la tabla productiva de notificaciones por
  organizacion. La tabla legacy `notifications`, basada en email, no participa
  en este flujo.
- Los triggers de `quotes` crean eventos para cotizacion enviada, aprobada y no
  seleccionada. Las notificaciones se crean en base de datos, no desde el
  frontend, y cubren los rechazos automaticos de cotizaciones alternativas.
- RLS permite leer y marcar como leidas solo a miembros del tenant (o a
  platform admins). No hay policies de insercion o eliminacion para frontend.
- `NotificationBell`, integrado debajo del selector de organizacion del
  Sidebar, y `NotificationList` usan la organizacion activa. La lista se
  refresca al abrir el indicador; realtime queda pendiente si se requiere una
  actualizacion inmediata entre sesiones.

## Ordenes de trabajo desde cotizaciones aprobadas

- `work_orders` es la tabla productiva tenant-aware para formalizar una
  cotizacion aprobada. No reutiliza `assignments`, que permanece legacy.
- La RPC `create_work_order_from_quote` valida autenticacion, la cotizacion
  aprobada, tenant cliente y rol `owner`, `admin`, `manager` o `requester`;
  platform admins tambien pueden crearla.
- `quote_id` es unico y la RPC es idempotente: una llamada repetida devuelve la
  orden existente sin duplicar registros ni notificaciones.
- Cliente y proveedor pueden leer la orden segun su membresia. El proveedor
  recibe `work_order_created` en `organization_notifications`.
- `QuoteListDialog` permite crearla desde la cotizacion aprobada. Siguen
  pendientes la vista completa de ordenes, estados operativos, evidencias,
  cierre y chat.

## Listado tenant-aware de órdenes de trabajo

- `useWorkOrders` filtra por la organización activa: cliente por `client_organization_id`, proveedor/facility manager por `provider_organization_id` y plataforma mediante el RLS existente.
- El Sidebar muestra el módulo para organizaciones cliente, proveedor, facility manager y plataforma; sin organización activa, el módulo conserva un estado vacío seguro.
- Este flujo es solo de lectura: lista, detalle y recarga. Cambios de estado, asignaciones y ejecución operativa quedan fuera de alcance.

## Hardening de grants authenticated

- RLS define que filas puede usar un usuario, pero PostgREST tambien requiere
  grants sobre esquema, tablas y funciones antes de evaluar esas policies.
- La migracion `authenticated_grants_hardening` formaliza los grants minimos
  para el flujo tenant-aware de organizaciones, solicitudes, cotizaciones,
  notificaciones y ordenes de trabajo.
- `providers`, `profiles`, `user_roles` y chats permanecen legacy o pendientes;
  esta migracion no amplia sus permisos.

## Corrección RLS de RETURNING en cotizaciones

- La policy SELECT de `quotes` ahora evalúa la fila y su solicitud asociada sin
  llamar a `can_user_read_quote(quotes.id)`, evitando una autolectura de
  `quotes` durante `INSERT ... RETURNING` de PostgREST.
- Un proveedor autorizado puede crear una cotización y recibir su `id`; no se
  abrieron permisos legacy para providers, profiles, user_roles ni chats.

## Limpieza de ruido legacy en UI

- `RequestForm` ya no consulta `providers`; la selección directa de proveedores
  queda pendiente de migración tenant-aware y las solicitudes continúan
  publicándose como públicas.
- La ruta legacy de asignaciones queda aislada con el estado “Asignación
  pendiente”; no consulta `assignments` ni amplía permisos.
- Chat y selector directo de proveedores siguen pendientes de migración
  tenant-aware. El flujo público de solicitud, cotización, aprobación y orden
  de trabajo permanece operativo.

## Preparación para staging

- El flujo MVP tenant-aware fue validado localmente: solicitud pública,
  cotización, aprobación/rechazo y creación/consulta de orden de trabajo.
- Se inicia la preparación de staging con Vercel para frontend y Supabase Cloud
  para Auth, base de datos y Storage; R2 permanece opcional y pendiente.
- Pendientes: chat tenant-aware, selector directo de proveedores, asignaciones
  operativas, evidencias/cierre y realtime.

## Administración de organizaciones y miembros

- Existe un Admin Console para platform admins owner/admin y las Edge Functions `admin-list-organization-members`, `admin-create-user-and-add-member` y `admin-update-organization-member`.
- El alta productiva de usuarios se realiza en backend/Edge Functions; no usa seedData ni tablas legacy.
- `admin-create-user-and-add-member` admite una contraseña temporal opcional de
  al menos 8 caracteres para staging/demo. Se usa sólo dentro de Supabase Auth
  Admin, nunca se devuelve ni se registra; en producción se recomienda
  invitación o recuperación de contraseña por email.

## Perfil empresarial por organización

- `organization_profiles` separa los datos empresariales de la organización del
  perfil personal del usuario. Sus policies permiten lectura a miembros activos
  y edición a owner/admin del tenant o a platform admins.
- `OrganizationProfile` sustituye la vista legacy de perfil proveedor; no usa
  `providers`, `profiles`, `user_roles`, asignaciones ni chat. Storage/R2 para
  logo y documentos continúa pendiente.

## Sesion productiva sin auth legacy

- `AuthContext` construye la identidad basica desde Supabase Auth (email y
  metadata `name`) y ya no consulta automaticamente `profiles` ni `user_roles`.
- Los permisos y roles productivos provienen de `organizations` y
  `organization_members`; el `UserRole` legacy solo se deriva temporalmente de
  la organizacion activa para rutas visuales antiguas.
- El footer del Sidebar usa organizacion y membership actuales, evitando mostrar
  un rol legacy que contradiga el selector de organizacion.
- `DEMO_ACCOUNTS` solo participa cuando `VITE_ENABLE_DEMO_SEED=true`. Profiles,
  user_roles, providers y chats siguen legacy o pendientes de migracion.

## Aislamiento temporal de chat legacy

- Sidebar ya no consulta automaticamente `request_chat_participants` ni
  `chat_messages` para contar mensajes al iniciar sesion o cargar Dashboard.
- La entrada de chat queda deshabilitada y la ruta legacy de contacto muestra un
  placeholder: "Chat pendiente de migracion tenant-aware".
- El acceso al foro desde `RequestList` queda aislado con un mensaje informativo
  y ya no monta el dialog que consulta `chat_messages`.
- No se abrieron grants ni policies legacy, y no se crearon tablas nuevas. El
  chat tenant-aware, participantes, realtime y storage quedan pendientes.

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

## Storage de anexos de detalle

- El bucket privado `request-detail-attachments` usa RLS que hereda el tenant
  desde `storage.objects.name` hacia `requests.organization_id`.
- El path reservado para nuevas cargas es
  `request-details/{request_id}/{safe-random-filename}`; el UUID de solicitud
  se valida en base de datos, no en datos del frontend.
- La subida y persistencia real de `attachment_urls`, junto con storage de otros
  modulos, permanece pendiente.

## Visibilidad de solicitudes para proveedores

- `request_provider_access` formaliza invitaciones y accesos activos por
  organizacion proveedora o facility manager; no usa `request_providers` legacy
  como fuente de autorizacion.
- Se reutiliza `requests.is_public` para marketplace. Las solicitudes draft no
  son visibles para proveedores, quienes solo pueden leer solicitudes, detalles
  y anexos autorizados por RLS.
- `PublicRequestList` y `ProviderRequestList` requieren una organizacion activa
  de tipo proveedor o facility manager. La migracion de quotes tenant-aware
  sigue pendiente.

## Solicitudes por tenant

- `requests.organization_id` define el tenant de cada solicitud. Sus policies
  RLS se basan en membresia y rol de organizacion, no en `localStorage` ni email.
- `RequestList` y `DraftList` cargan solo la organizacion activa. `RequestForm`
  exige una organizacion activa y persiste `organization_id` y `created_by_user_id`.
- La migracion de visibilidad para `PublicRequestList`, `ProviderRequestList`,
  cotizaciones, asignaciones, detalle y chat sigue pendiente; no se deben abrir
  policies de `requests` como solucion temporal.
- `VITE_ENABLE_DEMO_SEED=false` desactiva el seeding demo automático.
