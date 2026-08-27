# AI_CONTEXT.md

## Base visual OneFacility

- La rama `feature/onefacility-design-system-foundation` incorpora los assets de
  marca, tokens globales compatibles con shadcn/ui y el rediseño de Login y
  Sidebar.
- Se usa Inter y fallbacks del sistema; Proxima Nova no se incluye porque no hay
  archivos ni licencia en el repositorio.
- Este cambio es exclusivamente visual: no modifica RLS, Edge Functions,
  Supabase, permisos, navegación ni lógica de negocio.

## Limpieza de login y favicon

- En la rama `feature/login-cleanup-and-favicon` se retiró el selector visual
  Cliente / Proveedor / Equipo de Login. La identidad productiva permanece
  determinada por la sesión autenticada, las organizaciones y sus membresías.
- El favicon y el icono para Apple apuntan al isotipo oficial de OneFacility.
- No se realizaron cambios de backend, Supabase, RLS ni permisos.

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

## Onboarding controlado en Login

- Rama `feature/controlled-onboarding-login`: se retiró el flujo público de
  registro (`/login` ya no crea cuentas Auth). El enlace de "Regístrate" se
  reemplazó por un mensaje informativo: "¿Necesitas acceso? Solicítalo al
  administrador de tu organización." `AuthContext` ya no expone `register`.
- El alta real de usuarios se realiza desde Administración (Edge Functions
  `admin-create-organization`, `admin-invite-organization-member`,
  `admin-add-existing-member`) por un `platform_admin`, nunca desde el
  formulario público.
- Un usuario Auth sin `organization_members` activa puede autenticarse pero no
  puede operar la plataforma: `ProtectedRoute` (en `App.tsx`) detecta
  `organizations.length === 0` tras el login y muestra una pantalla de "Sin
  acceso asignado" con la opción de cerrar sesión, en vez de renderizar el
  Dashboard.
- El mensaje de error de login genérico se aclaró sin exponer detalles
  técnicos de Supabase Auth.
- No se modificaron `supabase/migrations`, `supabase/functions`,
  `supabase/config.toml` ni políticas RLS en esta rama.

## Login solo email/password y navegación de platform_admin

- Se retiró de `Login.tsx` el botón "Continuar con Google" y su separador
  visual. `loginWithGoogle` sigue existiendo en `AuthContext` (configuración
  del provider intacta); simplemente no se invoca desde la UI pública.
- La organización activa se sigue determinando por `organizations` /
  `currentOrganization` cargadas desde `organization_members`. Cuando
  `currentOrganization.organizationType === 'platform_admin'`, `Sidebar.tsx`
  oculta "Dashboard", "Órdenes de trabajo" y "Mis Asignaciones"; "Administración"
  y "Notificaciones" permanecen visibles.
- `Dashboard.tsx` inicia en la vista `admin` para organizaciones
  `platform_admin` y redirige a `admin` cualquier navegación por hash hacia
  vistas operativas no permitidas (`#dashboard`, `#work-orders`, etc.).
- No se tocó backend, Supabase, RLS ni el modelo multi-tenant.

## Perfil organización en pestañas

- Rama `feature/organization-profile-tabs`: `OrganizationProfile.tsx` se
  reorganizó con `Tabs`/`TabsList`/`TabsTrigger`/`TabsContent` de shadcn/ui
  (ya presentes en el proyecto) en vez de mostrar todas las secciones
  apiladas. Pestañas: Datos de contacto, Empresa, Información comercial,
  Clientes, Documentos — una por cada sección real existente.
- Cambio exclusivamente visual/frontend: mismo estado `form`, mismos nombres
  de campos, mismo payload y lógica de `save()`, misma detección de
  `canEdit`/solo lectura. El botón "Guardar perfil" quedó único, debajo de
  las pestañas. No se tocó Supabase, RLS, Edge Functions ni migraciones.

## Miembros en modal dentro de Administración

- `AdminConsole.tsx`: el botón "Miembros" de la tabla de organizaciones abre
  un `Dialog` de shadcn/ui (`isMembersDialogOpen`) en vez de expandir un panel
  debajo de la tabla. El modal muestra nombre/tipo/estado de la organización,
  la lista de miembros con sus acciones de rol y activo/inactivo, y el
  formulario "Crear usuario" en una card interna.
- Se separaron los estados de carga que antes compartía un único `loading`:
  `loadingOrganizations` (tabla principal) y `loadingMembers` (modal); y los
  de guardado: `saving` (organización) y `savingMember` (membresías/alta de
  usuario). Abrir miembros ya no muestra "Cargando organizaciones…" en la
  tabla principal, que permanece estable.
- Misma lógica de negocio: mismas Edge Functions
  (`admin-list-organization-members`, `admin-update-organization-member`,
  `admin-create-user-and-add-member`), mismas validaciones (email válido,
  contraseña temporal opcional ≥8 caracteres), mismos permisos. Cambio
  exclusivamente de UI/frontend, sin tocar Supabase, RLS ni backend.

## Organizaciones archivadas ocultas por defecto

- `AdminConsole.tsx`: la tabla principal de organizaciones oculta por defecto
  las de `status = 'archived'` (estado local `showArchived`, `false` por
  defecto). El botón "Ver archivadas"/"Ocultar archivadas" junto al título
  "Organizaciones" alterna la visibilidad filtrando en memoria sobre `items`
  ya cargado, sin volver a consultar Supabase.
- El filtro de estado sigue funcionando igual; si el usuario elige
  explícitamente "Archivada" se activa `showArchived` automáticamente para
  que el resultado sea coherente, y al desactivar "Ver archivadas" con ese
  filtro puesto, el filtro de estado vuelve a "Todos los estados". Las
  métricas superiores (conteo de archivadas) siguen calculándose sobre el
  total de `items`, no sobre la lista filtrada.
- Cambio exclusivamente de UI/frontend: no se tocaron Edge Functions, RLS,
  Supabase config, migraciones ni el modelo multi-tenant.

## Indicadores compactos y paginación en Administración

- `AdminConsole.tsx`: las 5 cards de indicadores (Total, Clientes,
  Proveedores, Administradores plataforma, Archivadas) se compactaron
  (`p-3`, número en `text-lg`, etiqueta en `text-xs`) en una grilla de 1
  columna en mobile, 2-3 en tablet y 5 en desktop.
- La tabla de organizaciones ahora tiene paginación local
  (`currentPage`/`pageSize`, 5/10/20 por página) aplicada después de
  búsqueda, filtro de tipo, filtro de estado y `showArchived`. Muestra
  "Mostrando X-Y de Z organizaciones" y botones Anterior/Siguiente,
  deshabilitados en los extremos. `currentPage` se resetea a 1 al cambiar
  cualquier filtro o el tamaño de página, y se corrige automáticamente si
  queda fuera de rango (p. ej. tras archivar una organización).
- Cambio exclusivamente de UI/frontend: no se tocaron Edge Functions, RLS,
  Supabase config, migraciones ni el modelo multi-tenant.

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

## Activos: fundación tenant-aware (Fase 1)

- Rama `feature/assets-tenant-aware-foundation`: se creó la base productiva del
  módulo Activos. Detalle completo en `docs/ASSETS_TENANT_AWARE_FOUNDATION.md`.
- Migración `supabase/migrations/20260826234732_assets_tenant_aware_foundation.sql`
  crea `asset_categories`, `assets`, `asset_documents`, `asset_events`.
- `assets` es una única tabla jerárquica vía `parent_asset_id` (niveles
  ilimitados: sociedad/sector/flota/equipo/componente/subcomponente son nodos
  del mismo árbol, no tablas ni organizaciones separadas). `organization_id` es
  el tenant real; `branch_id` referencia `client_branches` cuando aplica.
- RLS en las 4 tablas: `is_platform_admin()` o `is_organization_member()` para
  lectura; `has_organization_role(org, ['owner','admin','manager'])` o
  platform admin para alta/edición. Sin policy de `DELETE` — el archivado es
  lógico (`assets.status = 'archived'`). Grants otorgados solo a `authenticated`
  (select/insert/update), nada a `anon`.
- Trigger `check_asset_consistency` en `assets` exige que `parent_asset_id`,
  `asset_category_id` y `branch_id` pertenezcan al mismo `organization_id`;
  `check_asset_child_organization` aplica el mismo control en
  `asset_documents`/`asset_events` contra su `asset_id`.
- La UI de Activos (`AssetTree`, `AssetDetail`, nuevo `AssetsView`) dejó de usar
  `mockAssets`/datos hardcodeados: consume `src/hooks/useAssets.ts`, filtrado
  por `currentOrganization`. El acceso al módulo ya no depende del rol legacy
  `'cliente'`, sino de `currentOrganization.organizationType === 'client_company'`
  (`Sidebar.tsx`, `Dashboard.tsx`); crear/editar/archivar requiere rol
  owner/admin/manager en esa organización.
- Integración con `requests`/`request_details` (que hoy usan `asset`/`equipment`
  como texto libre) queda pendiente para una fase posterior; no se tocó
  `RequestForm.tsx` en esta fase.
- `src/pages/Index.tsx` (código muerto, no está en las rutas de `App.tsx`) no se
  actualizó a la nueva firma de props de `AssetTree`/`AssetDetail` porque esta
  fase no debía borrar código legacy; queda pendiente de limpieza en una fase
  posterior junto con `src/components/tickets/TicketList.tsx`.

## Activos: hook productivo (Fase 2)

- Rama `feature/assets-productive-hook`: no agrega tablas ni migraciones;
  solo endurece la capa de datos/frontend sobre la fundación de Fase 1.
  Detalle completo en `docs/ASSETS_PRODUCTIVE_HOOK.md`.
- `useAssets()` centraliza todo lo que antes estaba repartido entre
  `AssetsView`/`AssetTree`: carga de `assets`/`asset_categories`/
  `client_branches`, selección, `showArchived`, permisos, construcción del
  árbol, mutaciones y eventos. Migrado a TanStack Query
  (`useQuery`/`useMutation`, ya disponible vía `QueryClientProvider` en
  `App.tsx` pero sin uso previo en el proyecto) en vez de
  `useState`/`useEffect` manual.
- Permisos derivados de `currentOrganization`/`currentMembership`:
  `canViewAssets` (organización `client_company` con membresía activa) y
  `canManageAssets` (además, rol owner/admin/manager) — coincide con la RLS
  de `assets`/`asset_categories`/`asset_documents`/`asset_events`. No se tocó
  `AuthContext.tsx`, `Dashboard.tsx` ni `Sidebar.tsx` en esta fase.
- El árbol tolera `parent_asset_id` huérfano o cíclico (datos corruptos) sin
  colgar la UI: usa un recorrido acotado con set de visitados y muestra como
  raíz cualquier nodo que no sea alcanzable en vez de ocultarlo en silencio.
- Se agregó `restoreAsset()` (`status = 'active'`, evento `restored`) y
  eventos `updated`/`archived`/`created` en `asset_events`. No se tocaron RLS,
  Edge Functions, migraciones ni `service_role`.

## Activos: edición avanzada del detalle (sin migración)

- Rama `feature/assets-detail-editing`: `public.assets` ya traía
  `manufacturer`, `model`, `serial_number`, `barcode`, `purchase_date`,
  `warranty_until`, `location_text` desde la migración de Fase 1 — **no hizo
  falta ninguna migración nueva** para esta fase. Detalle completo en
  `docs/ASSETS_DETAIL_EDITING.md`.
- `AssetDetail.tsx` gana un modo de edición (botón "Editar", visible solo con
  `canManageAssets` y activo no archivado) con formulario en pestañas
  (General / Técnica / Ubicación y clasificación, shadcn `Tabs`) y botones
  Guardar/Cancelar. Solo lectura si `!canManageAssets`; sin edición si el
  activo está archivado (ahí solo aplica "Restaurar", ya existente).
- `CreateAssetInput`/`UpdateAssetInput` (`src/types/asset.ts`) y
  `useAssets().updateAsset()`/`createAsset()` ahora aceptan los 7 campos
  técnicos reales; se agregó validación de fechas (`purchaseDate`/
  `warrantyUntil` deben ser parseables si se envían).
- Nuevo `src/lib/assetLabels.ts` centraliza las etiquetas/orden de
  `AssetNodeType`/`AssetStatus`/`AssetCriticality` que antes estaban
  duplicadas entre `AssetTree.tsx` y `AssetDetail.tsx`.
- Guardar exitoso invalida las queries de TanStack Query (mismo mecanismo del
  hook) y registra un evento `updated` en `asset_events` (best-effort, sin
  loguear el payload). Feedback con `useToast` (patrón ya usado en 18+
  archivos del proyecto) para éxito y error, más el mensaje de `state.error`
  visible dentro del formulario si falla.
- No se tocó RLS, Edge Functions, `service_role`, ni `requests`/
  `RequestForm.tsx`.

## Activos ↔ Solicitudes: relación productiva

- Rama `feature/assets-requests-integration`. Detalle completo en
  `docs/ASSETS_REQUESTS_INTEGRATION.md`.
- Migración `20260827012124_requests_asset_id.sql`: agrega
  `requests.asset_id uuid null references public.assets(id) on delete set
  null` + índice + trigger `check_request_asset_organization` (mismo patrón
  que `check_asset_consistency`: el activo debe pertenecer al mismo
  `organization_id` de la solicitud). **Sin cambios de RLS**: las policies
  existentes de `requests` (`can_user_read_request`) y `assets`
  (`is_organization_member`/`is_platform_admin`) ya eran correctas para esta
  columna — verificado, no asumido.
- Decisión de modelo: `requests.asset_id` (no `request_details.asset_id` ni
  tabla puente `request_assets`) — sigue el mismo patrón ya usado por
  `branch_id` (top-level, un activo principal por solicitud en esta fase
  MVP), sin tocar el detalle multi-línea legacy (`equipment`/
  `sub_equipment` en `request_details` siguen intactos).
- `RequestForm.tsx` gana `RequestAssetPicker` (combobox Popover+Command,
  busca por nombre/código/N° de serie, oculta archivados, no permite
  seleccionarlos). Al elegir un activo real, sobreescribe el campo legacy
  `requests.asset` (texto) con `"<Tipo de nodo>: <Nombre>"` — así
  proveedores (que NO tienen RLS para leer `assets` directamente) siguen
  viendo un resumen seguro sin exponer `serial_number`/`technical_data`/etc.
  Sin activo seleccionado, el comportamiento es el de siempre.
- `RequestList.tsx`/`OrderTable.tsx`: nueva columna "Activo asociado"
  (persistida en el sistema de columnas existente, compatible con
  localStorage previo) que, para el cliente dueño (con RLS completa sobre
  `assets`), hace join en vivo vía `useAssets()` para mostrar nombre actual +
  ruta jerárquica corta.
- `ProviderRequestList.tsx`: sin nueva consulta ni cambio de RLS — solo un
  ícono junto al texto ya visible (`requests.asset`) cuando `asset_id` no es
  null, para distinguir un activo real de texto libre.
- Trazabilidad hasta `work_orders`: ya alcanzable sin cambios, vía
  `work_orders.request_id → requests.asset_id → assets`; no se agregó
  columna en `work_orders` porque no hace falta.
- Limpieza posterior: el modal "Agregar Nuevo Detalle" dejó de pedir
  Equipo/Subequipo/Área/Subárea (picklists hardcodeados eliminados); ese
  contexto ahora viene del activo asociado en la cabecera. `request_details`
  sigue recibiendo esas columnas (sin migración) con valores derivados
  uniformes por solicitud, no borrados. Detalle en
  `docs/ASSETS_REQUESTS_INTEGRATION.md`.

## Roles operativos internos: Planner/Gestor y Técnico

- Rama `feature/operation-members-roles`. Detalle completo en
  `docs/OPERATION_MEMBERS_ROLES.md`. Sin enum nuevo: `technician` ya
  existía en `organization_member_role`.
- Modelo funcional mínimo, centralizado en `src/lib/organizationRoles.ts`
  (reutilizado en `AdminConsole.tsx`, `Sidebar.tsx`,
  `OrganizationSwitcher.tsx`, que antes duplicaban cada uno su propio mapa
  de labels): `owner`/`admin` => **Administrador**, `manager` => **Planner
  / Gestor**, `technician` => **Técnico**. `usePermissions()` (existía sin
  usarse) ahora expone `canPlanWork`/`canExecuteWork`/`isPlanner`/
  `isTechnician` y se usa en `WorkOrderDetailDialog.tsx`.
- Selector de técnicos (`TechnicianSelect.tsx` +
  `useOrganizationTechnicians.ts`) limitado por organización vía la RPC
  `SECURITY DEFINER` `get_assignable_technicians(p_organization_id)`
  (`organization_members` no tiene `name`/`email`, viven en `auth.users`);
  valida que el llamador sea owner/admin/manager de esa organización o
  platform_admin, y nunca devuelve técnicos de otro tenant.
- Campo nuevo: `work_orders.assigned_member_id uuid null references
  organization_members(id)` (migración
  `20260827041707_operation_members_roles.sql`), con trigger que exige
  mismo `provider_organization_id`, activo, y `role = 'technician'`. Se
  escribe solo vía la RPC `SECURITY DEFINER` `assign_work_order_technician`
  (owner/admin/manager de la organización proveedora, o platform_admin) —
  **no se agregó ninguna policy `UPDATE` genérica** a `work_orders` (sigue
  sin ellas, como en la fase anterior).
- Pendiente documentado (no construido): no hay pantalla "Mis Asignaciones"
  filtrada por técnico todavía; un `technician` ve el mismo "Órdenes de
  trabajo" que el resto de su organización proveedora.

## Solicitudes internas y externas

- Rama `feature/internal-requests-work-orders`. Detalle completo en
  `docs/INTERNAL_REQUESTS_WORK_ORDERS.md`. Segundo camino de ejecución
  (Solicitud → OT directa, sin proveedores) al lado del flujo externo ya
  existente (Solicitud → proveedores → cotizaciones → selección → OT), sin
  tocar ni deprecar el externo.
- Campo nuevo: `requests.request_type text not null default 'external'
  check in ('external','internal')` (migración
  `20260827043747_internal_requests_work_orders.sql`). El `NOT NULL
  DEFAULT` backfillea toda solicitud legacy a `'external'` en la propia
  migración — el frontend no necesita tratar ningún caso `null`.
- Campo opcional: `requests.internal_responsible_member_id uuid null
  references organization_members(id)`, con trigger que exige mismo
  `organization_id`, activo, y `role = 'technician'` (mismo patrón que el
  trigger de `assigned_member_id` en `work_orders` de la fase anterior).
- `work_orders.quote_id` pasa a nullable (antes `NOT NULL UNIQUE`): una OT
  interna no tiene cotización de origen; `UNIQUE` permite múltiples `NULL`.
- Para una OT interna, `provider_organization_id = client_organization_id
  = requests.organization_id` (no hay proveedor externo) — deliberado, así
  la policy `SELECT` existente y el trigger de técnico asignado de
  `work_orders` siguen funcionando sin ningún cambio de RLS.
- RPC `SECURITY DEFINER` `create_internal_work_order_from_request(
  target_request_id, target_assigned_member_id default null)`: valida
  `request_type = 'internal'`, organización cliente activa, llamador
  owner/admin/manager de esa organización o platform_admin; es idempotente
  (si ya existe una OT interna para la solicitud, la devuelve en vez de
  duplicar). **No se agregó ninguna policy `INSERT`/`UPDATE` genérica** a
  `work_orders` — sigue siendo la única forma de crear una OT interna.
- `RequestForm.tsx`: campo "Tipo de gestión" (Externa por defecto/Interna).
  En Interna se oculta cotizaciones mínimas y toda la sección de
  proveedores/marketplace; aparece un selector opcional de responsable
  interno reutilizando `TechnicianSelect.tsx` (nuevo prop `emptyMessage`).
- `RequestList.tsx`/`OrderTable.tsx`: columna "Tipo de Gestión" (badge
  Interna/Externa vía `RequestTypeBadge`, integrada al sistema de columnas
  configurables existente); para internas, "Cotizaciones" muestra "No
  aplica" y las acciones muestran "Generar OT"/"OT generada" en vez del
  botón de cotizaciones.
- `PublicRequestList.tsx`/`ProviderRequestList.tsx`: agregado
  `.eq('request_type', 'external')` a sus queries — las solicitudes
  internas nunca llegan a marketplace ni a proveedores.
- `WorkOrdersList.tsx`/`WorkOrderDetailDialog.tsx`: badge "Solicitud
  interna" cuando `quote_id` es null; ninguna rama de código nueva asume
  `quote_id` no nulo.

## Órdenes de trabajo operacionales

- Rama `feature/operational-work-orders`. Detalle completo en
  `docs/OPERATIONAL_WORK_ORDERS.md`. `work_orders` pasa a ser una única
  entidad operacional real compartida por ambos orígenes (externo/interno)
  — **no se creó ningún módulo paralelo**; sigue siendo una sola tabla, un
  solo hook, una sola lista y un solo detalle.
- Migración `20260827150000_operational_work_orders.sql` agrega:
  `work_order_number` (correlativo `OT-<año>-<secuencia global>`, generado
  siempre por un trigger de servidor, nunca por el frontend, `UNIQUE`);
  `asset_id` (snapshot relacional, backfillado desde `requests.asset_id`,
  no editable después de creada la OT); `work_order_type`
  (`'internal'|'external'`, atado por CHECK a la nulidad de `quote_id` así
  que no puede desincronizarse); `planner_member_id` (owner/admin/manager
  de `provider_organization_id`, resuelto solo en el servidor vía
  `resolve_caller_planner_member`, nunca confiando en un id del cliente);
  `scheduled_at`/`due_at` (`timestamptz`, `due_at` backfillado desde
  `requests.deadline`); `priority` (`low/medium/high/urgent`, backfillado
  desde `requests.priority` 1–4 vía
  `map_request_priority_to_work_order_priority`); `observations`.
- `status` se amplía sin romper nada: el único valor que la app escribió
  alguna vez fue el default `'created'` (confirmado por grep, ningún
  RPC/UI escribía `status` antes de esta fase), así que se remapea
  exhaustivamente a `pending`/`assigned` y el CHECK nuevo solo admite
  `pending, assigned, in_progress, completed, closed` (`cancelled`/
  `suspended` quedan fuera del CHECK a propósito, documentados como
  pendientes).
- RPC nueva `update_work_order_operations`: único camino de escritura para
  los campos operacionales (planner, técnico, fechas, prioridad, estado,
  observaciones) de una OT ya creada — reemplazo completo, mismo patrón
  que `assign_work_order_technician`. Solo owner/admin/manager de
  `provider_organization_id` o `platform_admin`. **No se agregó ninguna
  policy `UPDATE` genérica** a `work_orders`. `assign_work_order_technician`
  ahora también empuja `status` entre `pending`↔`assigned` alrededor de
  una asignación (nunca toca `in_progress`/`completed`/`closed`).
- RPC nueva `get_assignable_planners` (+ `useOrganizationPlanners.ts` +
  `PlannerSelect.tsx`): espejo exacto de `get_assignable_technicians` /
  `useOrganizationTechnicians.ts` / `TechnicianSelect.tsx` pero para el rol
  owner/admin/manager.
- `create_work_order_from_quote` y `create_internal_work_order_from_request`
  (mismas firmas, sin cambios en sus call sites del frontend) ahora
  pueblan todos los campos nuevos al crear la OT.
- `WorkOrdersList.tsx`: Técnico/Planner ahora se resuelven siempre contra
  la organización del propio viewer (antes el nombre de técnico solo se
  resolvía viendo como proveedor) — esto es lo que permite que un cliente
  vea el nombre real de su propio técnico/planner en sus OT internas, sin
  que ninguna organización vea nunca el roster de otra (el fallback
  genérico se activa solo cuando el miembro no está en la propia
  organización). Columnas priorizadas si la tabla queda angosta:
  Correlativo, Tipo, Activo, Técnico, Fecha límite, Prioridad, Estado,
  Detalle; el resto se oculta con clases responsive de Tailwind, sin
  construir un sistema de columnas configurables nuevo para esta lista.
- `WorkOrderDetailDialog.tsx`: ficha operacional completa con un único
  formulario editable (planner, técnico, fechas, prioridad, estado,
  observaciones) que guarda todo con una sola llamada a
  `update_work_order_operations`, visible solo si
  `currentOrganization.id === provider_organization_id && canPlanWork`
  (condición ya existente, generaliza sola a OT internas). Activo asociado
  reutiliza `RequestAssetSummary` tal cual.
- Pendiente documentado (no construido): múltiples técnicos por OT
  (`work_order_technicians` evaluado y diferido — la fase siguiente
  terminó implementando multi-técnico a nivel de **actividad**, no de OT
  completa; ver más abajo), `cancelled`/`suspended` en el ciclo de vida de
  `status`, y que un técnico autogestione el estado de su propia OT sin
  pasar por un planner.

## Actividades de la orden de trabajo

- Rama `feature/work-order-activities`. Detalle completo en
  `docs/WORK_ORDER_ACTIVITIES.md`. Agrega el nivel operativo
  `work_orders → work_order_activities → work_order_activity_technicians`
  — **una sola jerarquía**, sin distinguir actividades internas de
  externas; cuelga de `work_orders` sin importar el origen de la OT.
- Migración `20260827160000_work_order_activities.sql`: tabla
  `work_order_activities` (`organization_id` = siempre
  `work_orders.provider_organization_id`, fijado por trigger;
  `due_at timestamptz`, misma convención que `work_orders.due_at`;
  `status` con 4 valores — `pending, assigned, in_progress, completed`,
  deliberadamente sin `closed`; `sequence` autoasignada) + tabla puente
  `work_order_activity_technicians` (multi-técnico **desde el modelo**,
  con `is_primary`; cada técnico se valida por trigger igual que
  `assigned_member_id`/`planner_member_id` — misma organización, activo,
  rol `technician`).
- RPCs nuevas: `get_work_order_activities` (actividades + técnicos
  resueltos como jsonb en una sola llamada), `upsert_work_order_activity`
  (crear/editar, reemplazo completo del set de técnicos, mismo patrón que
  `update_work_order_operations`), `delete_work_order_activity` (cascada
  sobre el puente). **No se agregó ninguna policy INSERT/UPDATE/DELETE
  genérica** en ninguna de las dos tablas.
- Visibilidad deliberadamente más estricta que `work_orders`: solo la
  organización **operadora** (`provider_organization_id`) o
  `platform_admin` ven las actividades — no el cliente del otro lado de
  una OT externa (el desglose técnico por técnico es detalle interno del
  operador). `WorkOrderDetailDialog.tsx` oculta la sección entera en ese
  caso en vez de mostrarla y fallar por autorización. Para una OT interna,
  `provider_organization_id == client_organization_id`, así que el
  cliente sí ve la sección con normalidad — mismo componente, sin branch
  por origen.
- Frontend nuevo: `src/types/workOrderActivity.ts`,
  `src/hooks/useWorkOrderActivities.ts` (cada mutación refresca desde el
  servidor en vez de parchear estado local), `WorkOrderActivitiesSection.tsx`
  + `ActivityEditorDialog.tsx` (integrados dentro de
  `WorkOrderDetailDialog.tsx`, no un módulo aparte), `src/lib/dateTime.ts`
  (conversión timestamptz ↔ datetime-local extraída para reutilizarse
  entre la cabecera de la OT y el formulario de actividad),
  `WorkOrderActivityStatusBadge` en `StatusBadge.tsx`.
- Reordenar (subir/bajar) reutiliza `upsert_work_order_activity` dos veces
  para intercambiar `sequence` — sin RPC dedicada.
- Pendiente documentado (no construido): elegir explícitamente un técnico
  principal en el formulario (hoy es implícito, el primero marcado),
  sincronización automática de estado entre actividades y la OT de
  cabecera, autogestión de estado por el propio técnico, y reordenar por
  drag-and-drop.
