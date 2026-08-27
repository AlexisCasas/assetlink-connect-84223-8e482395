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
- Corrección posterior (`20260827170000_fix_work_order_activities_rpc_ambiguity.sql`):
  `get_work_order_activities` fallaba con Postgres 42702
  (`ambiguous_column`) — su `RETURNS TABLE(id uuid, ...)` crea variables
  OUT implícitas, y su primera consulta referenciaba `id` sin alias,
  ambiguo contra `work_orders.id`. Las tres RPCs de actividades se
  reescribieron con alias cortos de tabla (`wo`, `woa`, `woat`, `om`,
  `au`) y parámetros renombrados con prefijo `p_` (antes `target_*`) —
  Postgres no permite renombrar parámetros vía `CREATE OR REPLACE
  FUNCTION` (SQLSTATE 42P13), así que la migración correctiva hace `DROP
  FUNCTION` antes de recrear cada una. `src/hooks/useWorkOrderActivities.ts`
  actualizado a los nuevos nombres de parámetro. Esta convención de
  alias/prefijo `p_`/`v_` es ahora el estándar para toda RPC nueva del
  proyecto.

## Inventario mínimo + materiales de OT

- Rama `feature/minimal-inventory-materials`. Detalle completo en
  `docs/MINIMAL_INVENTORY_MATERIALS.md`. Agrega
  `warehouses → materials → work_order_materials` — explícitamente NO
  SAP MM (sin kardex, valorización, órdenes de compra, transferencias,
  reservas complejas, lotes, costeo, ni descuento automático de stock).
  Los materiales cuelgan de `work_orders` sin importar el origen de la OT,
  mismo principio que `work_order_activities`.
- Migración `20260828120000_minimal_inventory_materials.sql`, escrita
  desde el inicio con la convención de alias corto (`wo`, `wh`, `m`,
  `wom`, `cb`) y parámetros `p_`/variables `v_` que dejó la corrección de
  ambigüedad anterior — verificada end-to-end contra Postgres local
  (smoke test manual vía `psql`) antes de tocar el frontend.
- `materials`: `UNIQUE(organization_id, lower(code))` — código único por
  organización, no por almacén (decisión documentada: dos almacenes no
  pueden compartir el mismo SKU con significados distintos en esta fase).
  Sin `DELETE` en `warehouses`/`materials` — desactivar es
  `is_active = false` vía `upsert_warehouse`/`upsert_material`.
- `work_order_materials.organization_id` = siempre
  `work_orders.provider_organization_id` (mismo ancla que
  `work_order_activities`); `stock_snapshot` se congela al crear la línea
  o al cambiar de material, `current_stock` se resuelve en vivo en cada
  lectura.
- `get_work_order_materials` calcula `warning_status`
  (`ok`/`no_stock`/`insufficient_stock`) server-side con la regla exacta
  pedida: `stock = 0 y planificado > 0` → sin stock; `stock < planificado`
  → insuficiente; si no, disponible. **Nunca bloquea el guardado** —
  `upsert_work_order_material` siempre acepta la cantidad planificada.
- Visibilidad de `work_order_materials` igual de restrictiva que
  `work_order_activities`: solo la organización operadora o
  `platform_admin`; el cliente de una OT externa no ve el detalle de
  materiales. Ninguna de las tres tablas tiene policy
  `INSERT`/`UPDATE`/`DELETE` — escritura solo vía RPC.
- Frontend: `useInventoryCatalog.ts` + `InventoryView.tsx` (módulo nuevo,
  nuevo ítem "Inventario" en `Sidebar.tsx`/`Dashboard.tsx`, visible solo
  para owner/admin/manager de una organización operadora);
  `useWorkOrderMaterials.ts` + `WorkOrderMaterialsSection.tsx` (integrada
  en `WorkOrderDetailDialog.tsx` junto a Actividades, bajo la misma
  condición de visibilidad — renombrada `canViewActivities` →
  `canViewOperatingDetails` porque ahora gatea ambas secciones);
  `WorkOrderMaterialWarningBadge` en `StatusBadge.tsx`.
- Pendiente documentado (no construido): reactivar almacén/material
  desactivado (la UI no lo expone todavía), descuento real de stock al
  ejecutar la OT, múltiples almacenes para el mismo material, y
  reservas/bloqueo duro por stock insuficiente.

## "Mis órdenes de trabajo" — vista operativa del técnico

- Rama `feature/technician-work-view`. Detalle completo en
  `docs/TECHNICIAN_WORK_VIEW.md`. Un técnico ve únicamente su propio
  trabajo, leyendo `work_orders` + `work_order_activities` +
  `work_order_activity_technicians` + `work_order_materials` tal como ya
  existen — **no se creó ninguna tabla de "OT del técnico"** — más una
  tabla mínima nueva `work_order_work_logs` solo para notas de "Registrar
  trabajo".
- Migración `20260828170000_technician_work_view.sql`. RPC central
  `get_my_technician_work_orders()` **sin parámetro de organización** —
  se resuelve enteramente desde `auth.uid()`, agregando el trabajo del
  llamador en todas las organizaciones donde tenga membresía `technician`
  activa. Una OT se incluye si el llamador es su `assigned_member_id` o
  está vinculado a alguna de sus actividades vía
  `work_order_activity_technicians`. Verificado end-to-end vía `psql`:
  técnico de Organización A ve su OT asignada; técnico de Organización B
  ve `0` filas.
- `resolve_asset_path(uuid)`: helper interno **sin `GRANT EXECUTE` a
  `authenticated`** — solo invocable desde otra función `SECURITY
  DEFINER` (la de arriba), nunca directo desde el frontend; resuelve
  nombre/ruta de un activo bypaseando RLS de forma segura porque el
  técnico de una OT externa no es miembro de la organización cliente
  dueña del activo.
- `technician_update_work_order_progress(p_work_order_id, p_status?,
  p_notes?)`: única escritura permitida a un técnico sobre una OT.
  Transiciones válidas: `pending`/`assigned → in_progress`,
  `in_progress → completed` — **nunca `closed`** (verificado: rechazado
  con error explícito). Nunca toca planner, técnico asignado, fechas,
  prioridad ni materiales — esos siguen siendo de
  `update_work_order_operations`.
- `work_order_work_logs` (tabla real, no texto libre en
  `observations`): nota + `status_from`/`status_to` opcionales + autor +
  fecha. `get_work_order_work_logs` la expone en modo lectura a
  planner/admin/técnico de la organización operadora — sin esto, las
  notas de un técnico solo serían visibles para él mismo.
- Frontend: `useTechnicianWorkOrders.ts` +
  `TechnicianWorkView.tsx` (cards, no tabla — mucha información anidada
  por OT) + `TechnicianWorkLogDialog.tsx` +
  `TechnicianWorkOrderDetailDialog.tsx` (deliberadamente **no** reutiliza
  `WorkOrderDetailDialog.tsx` — ese componente condiciona edición a que
  `currentOrganization` coincida con la OT, poco fiable aquí porque un
  técnico puede tener trabajo en más de una organización a la vez).
- `Sidebar.tsx`: "Órdenes de trabajo" ahora excluye explícitamente el rol
  `technician` (`canViewWorkOrders = isOperatingOrg && !isTechnicianRole`);
  nuevo ítem "Mis órdenes" en su lugar. `Dashboard.tsx`: el propio `case
  'work-orders'` redirige a `TechnicianWorkView` si el rol es
  `technician`, cerrando el hueco de navegación directa por hash/URL.
- Pendiente documentado (no construido): registro avanzado de tiempos,
  evidencias/fotos, checklist técnico, y firma/cierre formal.

## Reporte operativo del técnico por actividad

- Rama `feature/technician-activity-report`. Detalle completo en
  `docs/TECHNICIAN_ACTIVITY_REPORTS.md`. Agrega
  `work_order_activities → work_order_activity_reports →
  work_order_activity_report_materials`/`_evidences` — **extiende**
  `work_order_activities`, no la reemplaza; sin módulo paralelo.
- Migración `20260828220000_technician_activity_reports.sql`.
  `actual_hours` se calcula por trigger
  (`compute_work_order_activity_report_hours`), no por columna
  `GENERATED ALWAYS AS` — la resta de dos `timestamptz` es `STABLE`, no
  `IMMUTABLE`, en el catálogo de Postgres, y `GENERATED` exige
  inmutabilidad (falla en la creación de la tabla si se intenta).
- **Múltiples reportes por actividad, a propósito**: sin `UNIQUE`,
  `submit_activity_report` siempre `INSERT`, nunca `UPDATE`. El total real
  de una actividad es la suma de `actual_hours` de todos sus reportes.
- Trigger de consistencia (`check_work_order_activity_report_consistency`)
  valida que `member_id` sea técnico activo asignado a la actividad
  (`work_order_activity_technicians`) o técnico principal de la OT
  (`work_orders.assigned_member_id`) — misma regla que
  `technician_update_work_order_progress`. Materiales del reporte nunca
  descuentan `materials.stock` (sin kardex, sin costeo). Evidencias son
  **metadata solamente** en esta fase (nombre + link opcional pegado a
  mano) — el esquema (`file_path`/`mime_type`/`size_bytes`) ya está listo
  para un upload real vía Supabase Storage, pendiente documentado.
- RPCs: `get_activity_report_form_data` (actividad + OT + técnicos +
  materiales disponibles + reportes previos del propio técnico, en una
  llamada), `submit_activity_report` (único camino de escritura;
  `final_status = completed` → actividad `completed`; `in_progress` o
  `blocked` → actividad `in_progress`, `blocked` deliberadamente no
  agregado al `CHECK` de `work_order_activities.status`; `pending` no
  toca el estado; nunca cierra la OT), `get_activity_reports_for_work_order`
  (reportes con `hours_difference` ya calculada — planner ve todos,
  técnico ve solo los suyos, mismo split que las policies `SELECT`).
- **`get_my_technician_work_orders` extendida sin editar su migración
  original** (`20260828170000_technician_work_view.sql`, ya
  mergeada/desplegada): un `CREATE OR REPLACE FUNCTION` con la misma
  firma y columnas de salida (no requiere `DROP FUNCTION`, a diferencia
  de un rename de parámetros) agrega `actual_hours_total`/`reports_count`
  al jsonb de cada actividad.
- **Verificado end-to-end vía `psql`** con el escenario exacto del
  enunciado (2h estimado, 08:00–11:00 real) → `actual_hours = 3.00`,
  `hours_difference = +1.00`, actividad `completed`, `materials.stock`
  sin cambios, visible para el técnico y para el planner.
- Frontend: `useActivityReports.ts` (un hook para las 3 RPCs) +
  `ActivityReportDialog.tsx` (Desde/Hasta manual, sin cronómetro
  obligatorio, botón "usar hora actual" opcional) integrado en
  `TechnicianWorkView.tsx` y `TechnicianWorkOrderDetailDialog.tsx`;
  `WorkOrderActivityReportsSummary.tsx` (resumen planificación vs. real
  para planner/admin) integrado en `WorkOrderDetailDialog.tsx`.
- Pendiente documentado (no construido): upload real de archivos
  (evidencias), cronómetro real, cierre automático de OT, consolidado
  avanzado de productividad.

## Historial integral del activo

- Rama `feature/asset-integrated-history`. Detalle completo en
  `docs/ASSET_INTEGRATED_HISTORY.md`. "¿Qué le ha pasado a este activo?"
  — una sola línea de tiempo consolidada **en el momento de la lectura**
  desde las tablas fuente reales (`assets`, `asset_events`, `requests`,
  `work_orders`, `work_order_activities`,
  `work_order_activity_reports`/`_materials`/`_evidences`). **Sin tabla
  espejo, sin módulo paralelo**: cada item apunta (`source_table`/
  `source_id`) directo a su fila origen.
- Migración `20260829110000_asset_integrated_history.sql`: una sola RPC
  nueva, `get_asset_integrated_history(p_asset_id)`. **Sin cambios de
  esquema a `asset_events`** — ya tenía `event_type`/`description`/
  `payload` (usado como `metadata`), y `useAssets.ts` ya lo alimenta en
  cada creación/edición/archivado/restauración desde una fase anterior.
- **Anti-duplicación explícita**: el item "creación del activo" normalmente
  sale de `asset_events` (`event_type='created'`); el respaldo derivado de
  `assets.created_at` solo se emite si esa fila de `asset_events` no
  existe (`NOT EXISTS`) — nunca ambos a la vez. `assets.updated_at` **no**
  se usa como fuente de un item separado, a propósito: `asset_events` ya
  cubre `updated`/`archived`/`restored`, así que hacerlo habría duplicado
  exactamente lo que la tarea pedía evitar.
- **Bug evitado antes de que ocurriera**: en un `UNION ALL` dentro de
  `RETURN QUERY`, el `ORDER BY` final resuelve contra los nombres de
  columna de la *primera* rama a nivel SQL (antes de que PL/pgSQL asigne
  el resultado a `RETURNS TABLE`) — sin alias explícito por columna en
  cada rama, `ORDER BY event_date DESC` habría fallado en tiempo de
  ejecución. Las 8 ramas del `UNION ALL` llevan `AS <columna>` en cada una.
- **Visibilidad deliberadamente más permisiva hacia el dueño del activo**
  que la de fases anteriores: el cliente dueño ve el detalle operativo
  completo (OT, actividad, técnico, material, evidencia) **incluso de una
  OT ejecutada por un proveedor externo** — a diferencia de
  `work_order_activities`/`work_order_materials`/`work_order_work_logs`,
  donde el cliente de una OT externa no veía ese detalle. Decisión
  explícita y acotada solo a esta RPC, documentada, sin tocar ninguna
  policy ni RPC existente. Un proveedor solo ve la cadena de *sus propias*
  OT sobre el activo (nunca solicitudes/eventos del activo ni OT de otro
  proveedor); una organización sin relación es rechazada.
- **Verificado end-to-end vía `psql`**: escenario completo (solicitud → OT
  interna → actividad → reporte con material y evidencia) → 7 items en
  orden cronológico correcto, visibles para dueño y técnico, rechazados
  para una organización sin relación, y una sola fila "Activo creado" (sin
  duplicado).
- Frontend: `useAssetHistory.ts` (puramente de lectura) +
  `AssetHistory.tsx` (una sola línea de tiempo cronológica con badge de
  grupo por item — nunca separada en secciones por tipo, eso rompería el
  orden cronológico) integrado en `AssetDetail.tsx` como pestaña
  "Historial" junto a "Resumen" (mismo patrón de `Tabs` que ya usaba el
  modo edición). El botón "Historial" que existía deshabilitado en la
  barra de acciones se eliminó — quedaba redundante con la pestaña real.
- Pendiente documentado (no construido): inspecciones (tipo
  `inspection_created` reservado, sin tabla), checklist técnico,
  mantenimientos preventivos, métricas predictivas, upload real de
  evidencias (mismo pendiente que la fase anterior).

## Notificaciones operativas in-app

- Rama `feature/operational-notifications`. Detalle completo en
  `docs/OPERATIONAL_NOTIFICATIONS.md`. Amplía el centro de notificaciones
  ya existente (`organization_notifications` desde
  `20260721184404_quote_notifications_tenant_flow.sql`,
  `NotificationBell.tsx`/`NotificationList.tsx`/
  `useOrganizationNotifications.ts`) con 7 eventos operativos —
  **sin sistema paralelo**: misma tabla, mismo hook, mismos componentes.
  Solo in-app (sin email/WhatsApp/push/scheduler real en esta fase).
- Migración `20260829150000_operational_notifications.sql`. Extiende
  `organization_notifications` con `recipient_member_id` (nullable —
  `NULL` preserva exactamente el comportamiento "broadcast a toda la
  organización" que ya tenían las notificaciones de cotizaciones, sin
  tocar ninguna fila existente), `priority`, `metadata`.
- **Idempotencia con dos índices únicos parciales** (uno para
  `recipient_member_id IS NULL`, otro para no-nulo) — un solo índice no
  alcanzaba porque `NULL` nunca es igual a `NULL` para unicidad.
  `create_notification_once` elige el índice correcto según el
  destinatario. Verificado: llamar `generate_operational_due_notifications()`
  dos veces seguidas nunca duplica.
- **Por qué targeted y no broadcast** para "notificar solo owner/admin/manager":
  un broadcast (`recipient_member_id IS NULL`) es visible por RLS a
  *cualquier* miembro de la organización sin importar su rol —
  `notify_role_members` inserta una fila dirigida por cada miembro
  calificado, no una sola fila compartida.
- Helpers `create_notification_once`/`notify_role_members`/`notify_member`:
  **no otorgados a `authenticated`**, mismo patrón que la
  `create_organization_notification` preexistente y que
  `resolve_asset_path` de la fase anterior — solo invocables desde otras
  funciones `SECURITY DEFINER`. `generate_operational_due_notifications()`
  sí se otorga a `authenticated` (no toma ninguna entrada libre que se
  pueda abusar).
- Los 7 eventos se disparan extendiendo 6 RPCs ya existentes
  (`create_work_order_from_quote`, `create_internal_work_order_from_request`,
  `update_work_order_operations`, `assign_work_order_technician`,
  `upsert_work_order_activity`, `submit_activity_report`,
  `technician_update_work_order_progress`) — todas con `CREATE OR REPLACE
  FUNCTION` simple, sin `DROP FUNCTION`, porque ninguna firma cambió — más
  un trigger nuevo en `requests` (`internal_request_created`, ya que las
  solicitudes se insertan directo desde el frontend sin RPC de creación).
  Único cambio de comportamiento en código ya desplegado: el
  `work_order_created` de `create_work_order_from_quote` pasó de broadcast
  a toda la organización proveedora a dirigido solo a owner/admin/manager
  — decisión deliberada de esta fase, documentada.
- **Visibilidad verificada con `SET ROLE authenticated`** (no como
  superusuario, que ignora RLS): César solo ve su propia notificación de
  "técnico asignado", Alexis solo las suyas, un owner de otra organización
  no ve ninguna.
- `generate_operational_due_notifications()`: sin cron/scheduler externo —
  se llama desde `useOrganizationNotifications.ts` (cada carga del centro
  de notificaciones) y `useWorkOrders.ts` (cada `refetch`), ambas
  best-effort.
- Frontend: `src/lib/notificationLabels.ts` (labels de tipo/prioridad,
  filtro "operativa", referencia textual a OT/Solicitud/Actividad) +
  cambios en `NotificationList.tsx`/`NotificationBell.tsx` (badge de
  prioridad, referencia, filtro Todas/Operativas). `useOrganizationNotifications.ts`
  **sin cambios en su API pública** — ya funcionaba correctamente para el
  modelo nuevo sin tocar `notifications`/`unreadCount`/`markAsRead`/
  `markAllAsRead`.
- Pendiente documentado (no construido): email/WhatsApp/push, scheduler
  real, preferencias de notificación, inspecciones próximas/vencidas
  (tipos reservados sin tabla).

## Indicadores de eficiencia y desviaciones

- Rama `feature/efficiency-deviations`. Detalle completo en
  `docs/EFFICIENCY_DEVIATIONS.md`. MVP de planificado vs. real calculado
  en vivo sobre datos ya existentes (`work_order_activities.estimated_hours`,
  `work_order_activity_reports.actual_hours`) — **sin tablas espejo ni
  sistema de tracking nuevo**.
- Migración `20260829180000_efficiency_deviations.sql`, dos RPCs de
  lectura, ambas `SECURITY DEFINER`, `STABLE`, con el mismo alias
  obligatorio por tabla (`wo`/`woa`/`woar`/`woat`/`om`/`au`/`a`) que
  `20260827170000_fix_work_order_activities_rpc_ambiguity.sql` dejó como
  convención:
  - `get_efficiency_activity_metrics(p_organization_id, p_start_date,
    p_end_date)`: una fila por actividad (planificado, real, diferencia,
    % desviación, técnico resuelto, período).
  - `get_efficiency_summary(...)`: una fila resumen (OT terminadas/
    pendientes/vencidas + totales de horas/desviación) — reutiliza
    `get_efficiency_activity_metrics` como CTE en vez de recalcular la
    misma agregación dos veces.
- **Regla de división segura** aplicada igual en SQL y en cliente: si
  `planned_hours` es `NULL` o `0`, `deviation_percent` es `NULL` (nunca
  se divide entre cero). Mismo patrón ya usado en fases anteriores para
  otros porcentajes.
- **Deliberadamente sin `get_efficiency_grouped_metrics`**: las
  agrupaciones por OT/técnico/activo se hacen del lado del cliente
  (`useEfficiencyMetrics.ts` → `groupBy`) sobre las filas ya obtenidas de
  `get_efficiency_activity_metrics`, para no triplicar la misma fórmula
  de división segura.
- **Sin ranking de técnicos**: ningún query ni componente compara un
  técnico contra otro. La UI usa siempre "desviación vs. plan"/
  "variación", nunca "mejor/peor técnico" — ver la sección dedicada en
  `docs/EFFICIENCY_DEVIATIONS.md`.
- Permisos: solo `owner`/`admin`/`manager` de la organización operativa
  (`work_orders.provider_organization_id`) y `platform_admin` pueden
  llamar ambas RPCs — verificado con `SET ROLE authenticated` que un
  técnico y el owner de otra organización son rechazados. El ítem de
  navegación "Eficiencia" en `Sidebar.tsx` usa el mismo criterio
  (`canViewEfficiency`, idéntico en forma a `canViewInventory`): visible
  solo para owner/admin/manager de una organización operativa, nunca
  para técnico ni para la organización `platform_admin`.
- Frontend: `src/types/efficiency.ts`, `src/hooks/useEfficiencyMetrics.ts`,
  `src/lib/efficiencyFormat.ts` (formato neutral de desviación:
  `+1 h / +50 %`, `-0.5 h / -25 %`), `src/components/analytics/
  EfficiencyDashboard.tsx` (filtros de fecha, cards de resumen, tabla por
  actividad, pestañas de agregación Por OT/Por técnico/Por activo),
  ruteado en `Dashboard.tsx` como vista `'efficiency'`.
  `WorkOrderActivityReportsSummary.tsx` ahora también muestra
  `% desviación` por reporte y en el total, con cálculo local que replica
  la misma regla de división segura (sin llamar a una RPC adicional).
- Pendiente documentado (no construido): tipos de actividad normalizados,
  productividad comparable entre técnicos, tendencias por período,
  exportación, alertas predictivas.

## Matriz de criticidad configurable

- Rama `feature/configurable-criticality-matrix`. Detalle completo en
  `docs/CONFIGURABLE_CRITICALITY_MATRIX.md`. Evoluciona `assets.criticality`
  (existente desde `assets_tenant_aware_foundation`) sin eliminarlo: sigue
  siendo la única columna de "criticidad efectiva" que lee el resto de la
  app; con matriz configurada, `calculate_asset_criticality` la sobrescribe
  con el resultado calculado, y sin matriz configurada el campo se sigue
  comportando exactamente igual que antes (manual, editable desde
  `AssetDetail.tsx` vía `useAssets.ts`, sin cambios).
- Migración `20260829190000_configurable_criticality_matrix.sql`: 4 tablas
  nuevas (`criticality_parameters`, `criticality_parameter_options`,
  `asset_criticality_assessments`, `asset_criticality_assessment_answers`)
  + 7 RPCs, todas `SECURITY DEFINER` con alias obligatorio por tabla
  (cp/cpo/aca/acaa/a/om/au), mismo patrón que
  `20260827170000_fix_work_order_activities_rpc_ambiguity.sql`.
  `asset_criticality_assessments` reutiliza el trigger genérico
  `check_asset_child_organization()` ya existente (de
  `asset_documents`/`asset_events`) en vez de duplicar la validación
  organization_id-debe-coincidir-con-el-activo.
- **Ninguna de las 4 tablas nuevas tiene política de INSERT/UPDATE/DELETE**
  — mismo patrón más estricto que `warehouses`/`materials`
  (`20260828120000_minimal_inventory_materials.sql`): toda escritura pasa
  por las RPCs `SECURITY DEFINER`; "borrar" un parámetro/opción es siempre
  `is_active = false`, nunca un DELETE físico.
- `calculate_asset_criticality` exige una respuesta por cada parámetro
  **activo** de la organización (ni de más ni de menos, sin duplicados) o
  rechaza toda la evaluación antes de escribir nada — valida en dos
  pasadas (1: valida y acumula el score sin escribir; 2: inserta el
  encabezado con su score ya calculado, luego las respuestas congeladas).
  `weighted_score = option_score * weight / 100`; umbrales fijos del MVP:
  `<25 low / <50 medium / <75 high / >=75 critical` — sin tabla de
  umbrales configurables por ahora (evaluada y descartada deliberadamente
  para no arriesgar el alcance).
- Cada evaluación congela su propia foto (`asset_criticality_assessment_answers`
  copia nombre/etiqueta/peso/puntuación, no los referencia en vivo), y
  además inserta un `asset_events` con `event_type = 'criticality_assessed'`
  — `get_asset_integrated_history` se actualizó (mismo patrón
  `CREATE OR REPLACE`, sin `DROP FUNCTION` porque la firma no cambió) solo
  para añadir la etiqueta en español de ese tipo de evento; ningún otro
  branch de esa función cambió.
- Permisos: lectura de la matriz y del historial (cualquier miembro activo
  u `platform_admin`); escritura (crear/editar/desactivar parámetros y
  opciones, ejecutar una evaluación) solo owner/admin/manager o
  `platform_admin` — verificado con `SET ROLE authenticated` que un
  técnico puede leer pero no escribir, y que una organización no ve ni
  puede escribir la matriz/evaluaciones de otra. El ítem de navegación
  "Criticidad" en `Sidebar.tsx` usa `canViewCriticality`, deliberadamente
  acotado al mismo universo que `canViewAssets` (`client_company`
  únicamente, no `isOperatingOrg`) porque los activos —y por lo tanto su
  matriz— no existen para `provider_company`/`facility_manager`.
- Sin bloqueo si la suma de pesos de los parámetros activos no es 100% —
  `CriticalityMatrixView.tsx` solo muestra una advertencia visual, nunca
  impide crear parámetros ni ejecutar una evaluación.
- Frontend: `src/types/criticalityMatrix.ts`,
  `src/hooks/useCriticalityMatrix.ts` (un solo hook cubre tanto la gestión
  de la matriz por organización como la evaluación/historial por activo),
  `src/components/criticality/CriticalityMatrixView.tsx` +
  `CriticalityParameterDialog.tsx` + `CriticalityOptionDialog.tsx` (gestión
  de parámetros/opciones), `CriticalityAssessmentDialog.tsx` ("Evaluar
  criticidad" con preview de score local que replica la misma fórmula del
  servidor) + `CriticalityAssessmentHistory.tsx`, ambos integrados en
  `AssetDetail.tsx` (botón "Evaluar criticidad", campo "Criticidad
  (efectiva)" con badge de score solo cuando la última evaluación sigue
  vigente, historial en la pestaña "Historial" junto a `AssetHistory.tsx`).
  Ruteado en `Dashboard.tsx` como vista `'criticality'`.
- Pendiente documentado (no construido): umbrales configurables por
  organización, plantillas de matriz por industria, criticidad automática
  desde datos reales de fallas, recomendación automática con IA,
  simulación de escenarios, override manual explícito de
  effective_criticality distinto del calculado.

## Motor genérico de checklists e inspecciones

- Rama `feature/generic-checklists-inspections`. Detalle completo en
  `docs/GENERIC_CHECKLISTS_INSPECTIONS.md`. **ITSE nunca es un módulo**:
  es solo una fila en `checklist_templates` ("Plantilla ITSE"), igual que
  "Inspección de techos", "Auditoría interna" o "Inspección de luces de
  emergencia" — `category` es texto libre, nunca una lista cerrada. Nada
  en el esquema/RPCs/frontend menciona ITSE de forma especial.
- Migración `20260829200000_generic_checklists_inspections.sql`: 7 tablas
  nuevas (`checklist_templates`, `checklist_template_items`,
  `checklist_template_response_options`, `inspection_plans`,
  `inspection_runs`, `inspection_run_answers`, `inspection_run_evidences`)
  + 12 RPCs (13 con `get_inspection_runs`, ver abajo), mismo alias
  obligatorio por tabla (ct/cti/ctro/ip/ir/ira/ire/a/cb/om/au) que
  `20260827170000_fix_work_order_activities_rpc_ambiguity.sql` dejó como
  convención.
- **Flujo**: `checklist_templates` (+ items + response_options) →
  `inspection_plans` (recurrente, sobre sede/área/activo, con
  responsable/periodicidad/`next_due_at`) → `create_inspection_run_from_plan`
  → `inspection_runs` (una ejecución) → `submit_inspection_run` congela
  cada respuesta en `inspection_run_answers` (snapshot: `item_question`/
  `response_label`/`response_value`/`is_failure` copiados, no
  referenciados en vivo — una plantilla editada después nunca reescribe
  una ejecución histórica).
- **Resultado de una ejecución**: `failed` si alguna respuesta usa una
  opción `is_failure = true`; `not_applicable` si todas las respuestas
  usan `value = 'not_applicable'` (convención de texto, no un booleano
  dedicado); si no, `passed`. Exige respuesta a todo ítem activo+
  obligatorio antes de guardar (dos pasadas: valida todo primero, sin
  escribir; solo si el payload completo es válido inserta el header y
  luego las respuestas — mismo patrón de
  `calculate_asset_criticality`).
- **`next_due_at` se recalcula desde `completed_at`**, no desde el
  `next_due_at` anterior, para que una inspección tardía no arrastre
  atraso al siguiente ciclo. `frequency = 'one_time'` no tiene "siguiente
  ciclo".
- El trigger genérico `check_asset_child_organization()` no alcanza aquí
  (inspection_plans/inspection_runs tienen múltiples FKs opcionales, no
  solo un asset_id) — se creó `check_inspection_plan_organization()` y
  `check_inspection_run_organization()` dedicados, cada uno validando que
  template/sede/área/activo/responsable (y plan_id, para runs) pertenezcan
  a la misma `organization_id`.
- **`submit_inspection_run` inserta `asset_events` con
  `event_type = 'inspection_completed'`** cuando el run tiene `asset_id`
  — `get_asset_integrated_history` se actualizó (mismo `CREATE OR REPLACE`
  sin `DROP FUNCTION`, firma sin cambios) solo para añadir la etiqueta en
  español de ese tipo de evento a la rama genérica `asset_event`, junto a
  `criticality_assessed` de la fase anterior.
- **Notificaciones**: `generate_inspection_due_notifications()` reutiliza
  `notify_role_members`/`notify_member` de `operational_notifications`
  para los dos tipos ya reservados (`inspection_due_soon_future` dentro de
  7 días, `inspection_overdue_future` vencida). **Idempotencia por
  ciclo**: como un mismo plan recurre con un `next_due_at` distinto cada
  vez (a diferencia de una OT, que llega a su `due_at` una sola vez),
  reutilizar `plan.id` como `entity_id` habría silenciado toda
  notificación después del primer ciclo (el índice de dedup de
  `create_notification_once` no tiene dimensión de tiempo) — se usa
  `entity_id = md5(plan_id || ciclo || next_due_at)::uuid`, determinístico
  y distinto en cada ciclo, sin tocar el helper compartido. Llamada
  best-effort desde `useOrganizationNotifications.ts`, junto a
  `generate_operational_due_notifications`.
- **Ninguna de las 7 tablas tiene política de INSERT/UPDATE/DELETE** —
  mismo patrón más estricto que `warehouses`/`materials`/la matriz de
  criticidad: toda escritura pasa por las RPCs `SECURITY DEFINER`;
  "borrar" una plantilla/ítem/opción/plan es siempre `is_active = false`.
- Permisos: lectura (plantillas/planes/ejecuciones) para cualquier miembro
  activo u `platform_admin` — incluye `technician` (necesita ver sus
  propias inspecciones asignadas); escritura de plantillas/ítems/
  opciones/planes solo owner/admin/manager; ejecutar/guardar un run el
  propio responsable asignado u owner/admin/manager. Verificado con
  `SET ROLE authenticated` en los cuatro sentidos (técnico no puede
  escribir plantillas pero sí leerlas; otra organización no puede leer ni
  escribir nada; responsable puede ejecutar; no-responsable-no-planner no
  puede).
- **`get_inspection_runs` añadida más allá de la lista original de RPCs**:
  no hay otra forma limpia de listar `inspection_runs` con nombres
  resueltos (dos FKs distintas hacia `assets` hacen ambiguo un embed de
  PostgREST, más un segundo join a `auth.users` para el responsable).
  Mismo patrón que `get_inspection_plans`.
- Frontend: `src/types/checklist.ts` + `src/types/inspection.ts`,
  `src/hooks/useChecklistTemplates.ts` + `useInspectionPlans.ts` +
  `useInspectionRuns.ts`, `src/components/inspections/InspectionsView.tsx`
  (3 tabs: Plantillas / Programación / Ejecuciones-Historial) +
  `ChecklistTemplateEditorDialog.tsx` + `ChecklistItemEditorDialog.tsx` +
  `ChecklistOptionEditorDialog.tsx` + `InspectionPlanDialog.tsx` +
  `InspectionRunDialog.tsx` (preview local de no-conformidad, misma lógica
  que el servidor). "Inspecciones" en `Sidebar.tsx`/`Dashboard.tsx`:
  visible para owner/admin/manager **y** technician de organizaciones
  `client_company` (a diferencia de "Criticidad", que excluye a
  technician) — la gestión de plantillas/planes queda oculta para
  technician dentro de la vista (`canPlanWork`), no a nivel de navegación.
- Pendiente documentado (no construido): plantillas predefinidas (ITSE u
  otras) listas para importar, generación automática de OT por no
  conformidad, checklist móvil avanzado, upload real de evidencias,
  firmas digitales, vista de calendario, scheduler/cron real.
- **Bugfix post-implementación (mismo alcance, antes del primer commit)**:
  - `InspectionPlanDialog.tsx` perdía el draft con cualquier re-render
    ajeno (p.ej. el refresh de token de Supabase Auth al recuperar el foco
    de la ventana) porque `InspectionsView.tsx` le pasaba
    `templates={templates.filter(...)}` inline — un array nuevo en cada
    render — y el efecto de inicialización del diálogo dependía de esa
    prop. Fix: `activeTemplates` memoizado con `useMemo` en
    `InspectionsView.tsx`, y el efecto de inicialización del diálogo
    reescrito para disparar solo en la transición cerrado→abierto o
    cuando cambia el `id` del plan editado (con `useRef`, sin depender de
    `templates`/`branches`/`assets`/`plan` como objeto) — más un draft
    espejo en `sessionStorage` (clave por organización + id de plan o
    "new") que se restaura al reabrir y se limpia solo al guardar con
    éxito o al cancelar explícitamente (cerrar con Escape/clic afuera
    conserva el draft, no lo borra).
  - `create_inspection_run_from_plan`/`submit_inspection_run` ya
    comparaban correctamente `responsible_member_id` contra la fila de
    `organization_members` del llamante (nunca contra `auth.uid()`
    directo) — el "P0001 Not authorized" que reportó el usuario era en
    realidad consecuencia del bug anterior (el plan se guardaba sin
    responsable porque el formulario perdía esa selección). Se agregó de
    todas formas `om.organization_id = v_plan.organization_id` /
    `= v_run.organization_id` explícito en ambas funciones, como
    endurecimiento defensivo para que la autorización no dependa
    implícitamente de la garantía de escritura de `upsert_inspection_plan`.
  - `DialogDescription` agregado a los 5 diálogos de Inspecciones
    (warning de accesibilidad de Radix por `DialogContent` sin
    descripción).

## Programación y alertas de inspección configurables

- Rama `feature/inspection-scheduling-alerts`. Detalle completo en
  `docs/INSPECTION_SCHEDULING_ALERTS.md` (secciones "Periodicidad y
  next_due_at" y "Notificaciones in-app" de
  `docs/GENERIC_CHECKLISTS_INSPECTIONS.md` marcadas como superadas, con
  referencia cruzada). ITSE sigue sin ser un módulo — las alertas
  funcionan igual para cualquier plantilla del motor genérico.
- Migración `20260830100000_inspection_scheduling_alerts.sql` — nueva,
  NO edita `20260829200000_generic_checklists_inspections.sql` (ya
  mergeada a `productization/mvp`, confirmado vía `git log`). Alias
  obligatorio (ip/ipar/ir/ct/om/au) igual que el resto del motor.
- `inspection_plans` extendida con `custom_interval`/`custom_unit` y
  `frequency` ampliado a incluir `'custom'` (`daily` se mantiene en el
  `CHECK` solo por compatibilidad con filas preexistentes — el formulario
  nunca lo ofrece). Tabla nueva `inspection_plan_alert_rules`
  (`before_due` + `days_before`, o `overdue` sin `days_before`), con dos
  índices únicos parciales (uno por tipo, ya que NULL nunca es igual a
  NULL para unicidad — mismo patrón que `organization_notifications`
  broadcast/targeted).
- **Bug real encontrado y corregido en esta misma migración, no en el
  código ya desplegado**: agregar `p_custom_interval`/`p_custom_unit`
  como parámetros nuevos al final de `upsert_inspection_plan` con un
  `CREATE OR REPLACE FUNCTION` simple NO reemplaza la función ya
  desplegada — Postgres identifica una función por (nombre, lista de
  tipos de argumento), así que un 13-arg y un 15-arg son dos funciones
  *distintas*; sin `DROP FUNCTION` previo, ambas coexisten y PostgREST no
  puede desambiguar una llamada que solo pasa los 13 nombres originales
  ("function ... is not unique"). Corregido con
  `DROP FUNCTION IF EXISTS ...(13-arg signature)` antes del
  `CREATE OR REPLACE`. Distinto del caso ya documentado de
  `get_criticality_matrix`'s `p_include_inactive` (esa RPC nunca tuvo una
  versión previa desplegada con menos parámetros — se creó ya con ese
  parámetro desde su primera migración). `get_inspection_plans` sí
  necesitó `DROP FUNCTION` real (cambia el conjunto de columnas de salida
  de un `RETURNS TABLE`, lo cual `CREATE OR REPLACE` nunca permite,
  mismo error 42P13 de la clase ya documentada para renombrar parámetros).
- `replace_inspection_plan_alert_rules(p_plan_id, p_rules)`: reemplazo
  completo (borra e inserta, transaccional dentro de la función) — la
  RPC que usa el formulario. Reglas nunca referenciadas por otra tabla
  (a diferencia de los ítems de checklist, congelados en
  `inspection_run_answers`), así que el borrado físico es seguro.
- `generate_inspection_due_notifications()` reescrita: reemplaza la
  ventana fija de 7 días por un join contra `inspection_plan_alert_rules`
  activas por plan. `entity_id` pasa de
  `md5(plan_id || ciclo || next_due_at)` a
  `md5(plan_id || rule_id || next_due_at)` — agregar `rule_id` evita que
  dos reglas del mismo plan/ciclo (ej. 90 y 60 días antes) colisionen en
  un solo slot de deduplicación. Verificado con `psql`: 2 llamadas
  seguidas nunca duplican; después de avanzar `next_due_at` (nuevo
  ciclo), la misma regla vuelve a notificar sin bloqueo del ciclo
  anterior; owner/admin/manager y responsable reciben, un miembro no
  calificado no recibe nada.
- **Comportamiento nuevo importante**: un plan sin reglas de alerta
  configuradas ya no notifica (la ventana implícita de 7 días
  desapareció) — documentado explícitamente, no es una regresión sino la
  consecuencia esperada de que las alertas ahora sean 100% configurables.
- `submit_inspection_run`: recalculo de `next_due_at` extendido con
  `weekly/quarterly/semiannual/annual` (ya existían monthly/daily) y
  `custom` (`make_interval` según `custom_unit`), siempre anclado en
  `completed_at`, nunca en el `next_due_at` anterior.
- Frontend: `src/types/inspection.ts` extendido
  (`InspectionAlertRule`/`InspectionAlertRuleDraft`,
  `InspectionCustomUnit`, `'custom'` en `InspectionFrequency`).
  `useInspectionPlans.ts`: `savePlanWithAlertRules` reemplaza el antiguo
  `savePlan` expuesto (guarda el plan, luego reemplaza sus reglas,
  secuencial ya que las reglas necesitan el id del plan).
  `InspectionPlanDialog.tsx`: selector de periodicidad con
  "Personalizada" (cada [N] [días/semanas/meses/años]), sección
  "Alertas" (chips rápidos 90/60/30 + input de días personalizado +
  checkbox "Avisar cuando esté vencido"), default de 30-días-antes +
  Vencido solo para planes nuevos. El fix de la fase anterior (guard por
  `useRef` + draft en `sessionStorage`) se extendió para cubrir también
  `customInterval`/`customUnit`/`alertRules` — mismas garantías, ningún
  campo nuevo puede perderse por refetch ajeno.
  `InspectionsView.tsx`: card de plan muestra periodicidad (con el
  "Cada N unidad" cuando es personalizada) y alertas configuradas
  ("90d, 60d, 30d, Vencido"). `notificationLabels.ts`:
  `notificationEntityReference` para `inspection_plan` actualizado a
  leer `plan_title` (reemplazó la clave `title` de la fase anterior) y a
  mostrar el detalle de la regla ("Inspección: {plan} · 90 días antes" /
  "Inspección vencida: {plan}").
- Pendiente documentado (no construido): scheduler/cron real,
  email/WhatsApp/push, calendario avanzado, reglas escalonadas por
  severidad, plantillas predefinidas ITSE, feriados/días hábiles,
  snooze/posponer alerta.

## Semáforo operativo de activos/áreas/sedes

- Rama `feature/asset-status-traffic-light`. Detalle completo en
  `docs/ASSET_TRAFFIC_LIGHT.md`. No decorativo: cada color se deriva en
  vivo de OT/inspecciones/estado real — sin color manual, sin tabla
  espejo, dos RPCs de solo lectura.
- Migración `20260830150000_asset_status_traffic_light.sql` (nueva, no
  edita ninguna migración ya mergeada). `get_asset_traffic_light`:
  cierre transitivo `WITH RECURSIVE` sobre `assets.parent_asset_id`
  (ancestro→descendiente) para el roll-up; `get_branch_traffic_light`:
  una sede (`client_branches`) no es una fila de `assets`, así que agrega
  el `rollup_color` ya calculado de los activos etiquetados con ese
  `branch_id` (reutiliza `get_asset_traffic_light` como subconsulta en
  vez de duplicar lógica, mismo patrón que `get_efficiency_summary`
  llamando a `get_efficiency_activity_metrics`).
- **Bug real encontrado y corregido durante el propio desarrollo, antes
  de cualquier commit**: `RETURNS TABLE` declara un parámetro OUT llamado
  `asset_id`; una referencia SIN calificar a `asset_id` dentro de una de
  las CTEs internas (`all_reasons`) resultó ambigua entre ese OUT
  parameter y la columna de la CTE (42702) — exactamente la clase de bug
  que `20260827170000_fix_work_order_activities_rpc_ambiguity.sql`
  documenta. Corregido calificando cada referencia con el alias de su
  CTE de origen (`ras.asset_id`, `rwo.asset_id`, etc.). Detectado por el
  propio smoke test antes de aplicar en ningún entorno real.
- Reglas verde/ámbar/rojo (ver el doc para la tabla completa de fuentes):
  rojo = OT vencida / inspección vencida (incondicional, no depende de
  reglas de alerta) / última ejecución de checklist `failed` (la más
  reciente por plan, no "alguna vez falló" — una ejecución posterior que
  pasa resuelve una falla anterior) / `assets.status = 'inactive'`.
  Ámbar = OT próxima (ventana de 24h ya usada por
  `generate_operational_due_notifications`) / inspección próxima (solo
  si existe una regla `before_due` activa cuya ventana está abierta —
  nunca una ventana inventada) / `assets.status = 'maintenance'`.
  `assets.status` no tiene un valor `out_of_service` real — se usó
  `inactive` como el más cercano, documentado explícitamente en vez de
  inventar un valor.
- **Criticidad nunca es rojo por sí sola** — se expone como columna de
  contexto, nunca contribuye a `direct_color`/`rollup_color`. La regla
  opcional "critical + trabajo pendiente → ámbar" del enunciado original
  se evaluó y se dejó fuera deliberadamente (ya vendría cubierta por
  `work_order_due_soon`/`inspection_due_soon` por sí solas).
- `causing_asset_ids` = descendientes (nunca el nodo mismo) con color
  no-verde; `rollup_reasons` = unión de razones directas de sí mismo y
  de cada descendiente no-verde, cada una con su propio `asset_id`/
  `asset_name`. Si el nodo no tiene hijos, `rollup = direct`
  automáticamente (el cierre transitivo de una hoja es solo ella misma).
  Verificado con `psql`: activo rojo → área roja (rollup) → sede roja,
  con `causing_asset_ids` señalando el/los activo(s) responsables en
  cada nivel; un activo con múltiples causas simultáneas (OT vencida +
  checklist failed) muestra ambas razones correctamente.
- Permisos: mismo patrón que `get_asset_integrated_history`/
  `get_criticality_matrix`/`get_inspection_plans` — cualquier miembro
  activo u `platform_admin`, incluye `technician` (ya ve activos e
  inspecciones; el semáforo no compara técnicos ni expone analítica
  agregada por persona). Verificado con `SET ROLE authenticated`: otra
  organización no puede leer nada.
- **No es historial**: no se inserta `asset_events` por cambios de color
  — es estado calculado en el momento de la consulta, no un evento
  discreto que "ocurrió". Explícito en la propia UI de
  `AssetDetail.tsx`.
- Frontend: `src/types/assetTrafficLight.ts`,
  `src/hooks/useAssetTrafficLight.ts` (una sola llamada trae ambas RPCs;
  expone `getAsset(id)` para lookup O(1) y `summary` con conteos
  green/amber/red por `direct_color`, para evitar sobre-contar el mismo
  problema en varios niveles del árbol), `src/lib/trafficLightLabels.ts`
  (reutiliza los tokens `success`/`warning`/`destructive` ya usados en
  `assetLabels.ts` — ningún color decorativo nuevo). Integrado en
  `AssetTree.tsx` (punto de color con `rollup_color` por nodo, tooltip
  vía `title`/`aria-label` con el resumen real de la razón),
  `AssetDetail.tsx` (sección "Semáforo operativo": color directo, color
  heredado si tiene hijos, razones directas, activos causantes
  clicables, razones heredadas), y un resumen simple
  (`TrafficLightSummaryCard.tsx`) en el Dashboard por defecto — visible
  solo para organizaciones `client_company` (donde existen activos),
  `null` en cualquier otro caso.
- Pendiente documentado (no construido): ponderaciones configurables del
  semáforo, reglas por organización, severidad por tipo de checklist,
  suppress/snooze, SLA por contrato, dashboard ejecutivo dedicado,
  histórico de cambios de semáforo, materialización/cron si el volumen
  de activos lo justifica.

## Dashboard real de métricas operativas

- Rama `feature/real-dashboard-metrics`. Detalle completo en
  `docs/REAL_DASHBOARD_METRICS.md`. Reemplaza `StatsCards.tsx` (números
  hardcodeados, nunca conectados a una consulta) con una sola RPC
  consolidada.
- Migración `20260830200000_real_dashboard_metrics.sql` (nueva RPC, sin
  cambios de esquema): `get_dashboard_metrics(p_organization_id)` — una
  fila con `total_assets`/`critical_assets` (excluye `archived`, mismo
  criterio que el semáforo operativo), `open_requests` (`status IN
  ('sent','quoted')` — excluye `draft` deliberadamente, ver el doc para
  la justificación basada en cómo `DraftList.tsx`/`RequestList.tsx` ya
  separan ese concepto), `open_work_orders`/`overdue_work_orders` (mismo
  criterio que `generate_operational_due_notifications`),
  `upcoming_inspections` (solo planes con una regla `before_due` activa
  cuya ventana está abierta — `COUNT(DISTINCT ip.id)` porque un plan
  puede tener varias reglas simultáneamente en ventana y debe contar una
  sola vez) / `overdue_inspections` (incondicional a reglas, igual que
  el semáforo), y `planned_hours`/`actual_hours` delegados a
  `get_efficiency_summary(p_organization_id, NULL, NULL)` en vez de
  recalcular esa agregación una segunda vez.
- Cada conteo se computa primero en una variable `v_`-prefijada y solo
  se referencia por ese nombre en el `RETURN QUERY` final — `RETURNS
  TABLE` declara columnas OUT con el mismo nombre que las métricas
  (`total_assets`, etc.), así que cualquier referencia sin calificar a
  esos nombres dentro del cuerpo habría sido ambigua (42702), el mismo
  bug ya encontrado y corregido en `get_asset_traffic_light` en la fase
  anterior — evitado desde el diseño esta vez.
- Permisos deliberadamente **más estrictos** que la mayoría de las RPCs
  de lectura del proyecto: solo owner/admin/manager o `platform_admin`
  (no "cualquier miembro activo" como `get_asset_traffic_light`/
  `get_criticality_matrix`/etc.) — es un resumen de toda la organización
  (conteos agregados, horas totales), no el dato de un activo/plan
  puntual. Verificado con `SET ROLE authenticated`: técnico y viewer
  rechazados; otra organización no puede leer nada.
- Frontend: `src/types/dashboardMetrics.ts`,
  `src/hooks/useDashboardMetrics.ts`,
  `src/components/dashboard/DashboardMetricsCards.tsx` (9 cards, gate a
  `canPlanWork` idéntico al de la RPC — un técnico ve "Sin acceso a
  métricas operativas" en vez de datos globales, mientras que
  `TrafficLightSummaryCard` sigue visible para él, gate distinto y
  documentado explícitamente). `Dashboard.tsx`: la vista por defecto ya
  no importa `StatsCards` en ningún caso (ni la principal ni el
  fallback de "Activos" para organizaciones no-cliente, que ahora
  muestra un mensaje neutral en vez de números falsos).
  `platform_admin` nunca llega a esta vista (ya forzado a `admin` antes)
  — sin caso especial adicional necesario.
- `StatsCards.tsx` **no se eliminó** (sigue importado por
  `src/pages/Index.tsx`, una página no registrada en `App.tsx` —
  código muerto preexistente, fuera de alcance tocar) — se le agregó un
  comentario de cabecera marcándolo explícitamente legacy/mock/deprecado
  para evitar un uso accidental futuro.
- Pendiente documentado (no construido): tendencia de OT, gráficos de
  criticidad, cumplimiento de inspecciones, eficiencia por período
  (hoy son totales de todo el tiempo sin filtro de fecha), filtros de
  fecha, exportación, dashboard ejecutivo dedicado.
