# Permisos delegados Cliente → Facility Manager (Fase 1 · Puntos 9A y 9B)

- **9A — fundación backend.** Migración
  `supabase/migrations/20260927194923_facility_manager_delegated_permissions.sql`.
  Pruebas: `supabase/tests/facility_manager_delegated_permissions.test.sql`
  (328 aserciones).
- **9B — UI de administración** (§12). Migración
  `supabase/migrations/20260927205942_facility_manager_ui_integration.sql`.
  Pruebas: `supabase/tests/facility_manager_ui_integration.test.sql`
  (75 aserciones). Incluye el cierre de la semántica provider-facing de
  Facility Manager (§13).

**Acceso operativo delegado por módulo (9C):** desde **9C.1** son efectivos
`assets.*` y `criticality.*` (ver `docs/FACILITY_MANAGER_ASSETS_CRITICALITY.md`);
desde **9C.2**, `inspections.*` y `preventive_maintenance.*` (ver
`docs/FACILITY_MANAGER_INSPECTIONS_PREVENTIVE.md`); desde **9C.3**,
`maintenance_notices.*` (ver `docs/FACILITY_MANAGER_MAINTENANCE_NOTICES.md`).
Desde **9C.4**, `requests.*`, incluidas la conversión de avisos y la
solicitud preventiva (ver `docs/FACILITY_MANAGER_REQUESTS.md`). Desde
**9C.5**, `quotes.view` y `quotes.approve` (ver
`docs/FACILITY_MANAGER_QUOTES.md`; `quotes.manage` no abre nada). Desde
**Punto 10**, las fotos y documentos R2 de activos siguen `assets.view` /
`assets.manage` (ver `docs/ASSET_FILES_R2_PRODUCTIZATION.md`). El resto de
módulos (OT, reportes), además de inventario y los adjuntos de solicitudes,
todavía no abre nada.

## 1. Las tres capas

| Capa | Dónde vive | Responde a | Quién la administra |
|---|---|---|---|
| **1. Relación empresa → empresa** | `organization_relationships` (`source` = cliente, `target` = FM, `relationship_type = 'facility_management'`) | ¿Qué empresa FM tiene el contrato con este cliente, y en qué estado está? | Cliente (owner/admin) o platform_admin |
| **2. Permisos delegados** | `facility_management_permissions` | ¿Qué capacidades delegó el cliente a esa **empresa** FM? | Cliente (owner/admin) o platform_admin |
| **3. Miembros asignados** | `facility_management_relationship_members` | ¿Qué **personas** concretas del FM atienden a ese cliente? | FM (owner/admin) o platform_admin |

Una persona del FM obtiene acceso operativo (`has_facility_management_permission`
= `true`) **solo si se cumplen las tres**: relación `active` con cliente y
FM activos, permiso concedido a la empresa, y **esa persona asignada** a la
relación con su membresía activa.

La identidad no cambia: las personas asignadas siguen siendo miembros
**únicamente** de su FM. Nunca se convierten en miembros del cliente.
Ninguna tabla duplica cliente, FM, `user_id` ni rol: todo se resuelve desde
`organization_relationships` y `organization_members`.

### Ejemplo

```
Client A ──facility_management──▶ FM B      permisos: assets.view, work_orders.view
Client C ──facility_management──▶ FM B      permisos: assets.view

FM B:  Pedro (manager)   asignado a Client A y a Client C
       Carlos (technician) asignado solo a Client A
       Lucía (technician)  sin asignar
       Ana (owner)         sin asignar
```

| Persona | `get_my_facility_management_clients()` | `has_…(Client A, 'assets.view')` | `has_…(Client C, 'assets.view')` |
|---|---|---|---|
| Pedro | Client A, Client C | true | true |
| Carlos | Client A | true | false |
| Lucía | — | false | false |
| Ana (owner) | — | false | false |

Ana ve ambos clientes en `get_my_facility_management_portfolio()` y puede
asignar o desasignar personas, pero **no** obtiene acceso operativo por ser
owner. Si quiere operar, debe asignarse a sí misma.

## 2. Rol interno ≠ permiso delegado ≠ asignación

- El **permiso** se concede a la empresa FM, nunca a una persona.
- La **asignación** decide qué personas de esa empresa lo ejercen.
- El **rol interno** del FM (owner, admin, manager, technician…) no
  interviene en `has_facility_management_permission`. Cada módulo lo
  combinará al integrarse, por ejemplo:

```sql
-- futuro, no implementado:
can_manage_asset :=
  has_facility_management_permission(client_id, 'assets.manage')
  AND current_fm_role IN ('owner', 'admin', 'manager');
```

No se creó ningún rol nuevo.

## 3. Permisos disponibles

Enum cerrado `public.facility_management_permission`:

| Módulo | Capacidades |
|---|---|
| Activos | `assets.view`, `assets.manage` |
| Criticidad | `criticality.view`, `criticality.manage` |
| Inspecciones | `inspections.view`, `inspections.manage` |
| Preventivo | `preventive_maintenance.view`, `preventive_maintenance.manage` |
| Avisos de avería | `maintenance_notices.view`, `maintenance_notices.report`, `maintenance_notices.manage` |
| Solicitudes | `requests.view`, `requests.create`, `requests.manage` |
| Proveedores | `providers.manage` |
| Cotizaciones | `quotes.view`, `quotes.manage`, `quotes.approve` |
| Órdenes de trabajo | `work_orders.view`, `work_orders.manage` |
| Reportes | `reports.view` |

Ninguna capacidad implica otra (`*.manage` no concede `*.view`).

## 4. Máquina de estados

```
pending   -> active | suspended | ended
active    -> suspended | ended
suspended -> active | ended
ended     -> pending
```

| Status | Permisos | Miembros asignados | Acceso efectivo |
|---|---|---|---|
| `pending` | configurables | asignables | no |
| `active` | configurables | asignables | **sí** (si hay permiso + asignación + membresía activa) |
| `suspended` | se conservan, configurables | se conservan, asignables | no |
| `ended` | **borrados** | **borrados** | no; no se pueden configurar ni asignar |

- Una relación FM nace siempre en `pending` (vacía).
- El mismo status es un no-op idempotente (sin auditoría).
- Activar exige cliente y FM con `status = 'active'`.
- Pasar a `ended` borra permisos **y** asignaciones, sin importar quién lo
  haga (RPCs nuevas, RPC legacy o service_role). `ended -> pending` no
  restaura nada: la relación reabierta empieza completamente limpia.

### Membresía desactivada después de asignar

Asignar exige membresía activa. Si después la membresía se desactiva, la
fila de asignación **no** se borra, pero el acceso efectivo pasa a `false`
de inmediato (el helper exige `organization_members.is_active`).
`get_facility_management_members` la sigue mostrando con
`membership_is_active = false`. Si la membresía se reactiva, la asignación
vuelve a ser efectiva sin intervención.

## 5. Seguridad

### ACL

| Objeto | PUBLIC / anon | authenticated | service_role |
|---|---|---|---|
| `facility_management_permissions` | nada | `SELECT` (RLS) | `SELECT, INSERT, UPDATE, DELETE` |
| `facility_management_relationship_members` | nada | **nada** (ni `SELECT`) | `SELECT, INSERT, UPDATE, DELETE` |
| `organization_relationships` | nada | `SELECT` (RLS) | `SELECT, INSERT, UPDATE, DELETE` |

- `facility_management_relationship_members` asocia personas con clientes,
  así que su **superficie de lectura es exclusivamente RPC**
  (`get_facility_management_members`, `get_my_facility_management_portfolio`).
  RLS habilitado sin policies como defensa en profundidad.
- `facility_management_permissions`: una sola policy `SELECT` (miembro
  activo del cliente, miembro activo del FM, o platform_admin).
- `organization_relationships`: se eliminaron las 3 policies históricas de
  escritura directa; se conserva "members can view organization
  relationships".

### Invariantes (triggers — aplican a cualquier escritor)

Relaciones (solo filas `facility_management`; provider/subcontracting sin
cambios):

- source = `client_company`, target = `facility_manager`, source ≠ target
  (`23514`). No exige organizaciones activas: pueden suspenderse después.
- Una fila **nueva** nace en `pending` (`55000`). Si el `INSERT` choca con
  una fila existente (`ON CONFLICT DO UPDATE`, como hace la RPC legacy), se
  aplica la máquina de estados de la rama `UPDATE`.
- Cliente/FM/tipo inmutables (`23514`); transiciones según la máquina
  (`55000`).
- `ended` borra permisos y asignaciones (trigger `AFTER UPDATE`).

Permisos: solo sobre una relación `facility_management` (`23514`) no
terminada (`55000`).

Asignaciones (`23514` en todos los casos): la relación existe, es
`facility_management`, no está `ended`, su target es `facility_manager`;
el miembro existe, pertenece **exactamente** al FM target y está activo en
el momento de asignarlo.

### Funciones

Todas `SET search_path = ''` con referencias schema-calificadas. Las 9 RPCs
son `SECURITY DEFINER`, con `REVOKE` de PUBLIC/anon y `EXECUTE` solo para
`authenticated`. Las 4 funciones de trigger son `SECURITY INVOKER` (todos
los escritores legítimos ya pueden leer lo que consultan) y no tienen
`EXECUTE` para ningún rol cliente. **Ninguna RPC recibe `user_id`,
`facility_manager_id` ni `membership_id` para resolver acceso**: la
identidad es siempre `auth.uid()`.

### SQLSTATE de errores funcionales

| Código | Significado |
|---|---|
| `42501` | no autenticado / no autorizado |
| `22023` | organizaciones, relación o miembros inválidos para la operación |
| `P0002` | relación inexistente |
| `55000` | transición o estado no permitido |
| `23514` | invariante de trigger violada |

## 6. RPCs

| Función | Quién | Qué hace |
|---|---|---|
| `has_facility_management_permission(_client, _permission) → boolean` | cualquier `authenticated` (evalúa `auth.uid()`) | `true` solo si: cliente `client_company` activo; relación FM `active`; FM activo; el llamante es miembro activo del FM; **esa membresía está asignada a la relación**; el permiso existe. No evalúa rol interno. Nunca `true` por ser owner/admin del FM ni por ser platform_admin. |
| `create_facility_management_relationship(_client, _fm) → uuid` | owner/admin del cliente, platform_admin | Crea en `pending`. Idempotente: si existe devuelve su id sin cambiar su status. |
| `set_facility_management_permissions(_relationship_id, _permissions[])` | owner/admin del cliente, platform_admin | Reemplazo atómico del set (`NULL` = vacío, sin duplicados). |
| `set_facility_management_relationship_status(_relationship_id, _status)` | owner/admin del cliente, platform_admin | Máquina de estados. |
| `get_facility_management_relationships(_client) → TABLE` | owner/admin del cliente, platform_admin | Relaciones FM del cliente con status y permisos. |
| `set_facility_management_members(_relationship_id, _organization_member_ids[])` | **owner/admin activos del FM target**, platform_admin | Reemplazo atómico de las personas asignadas (`NULL` = vacío, sin duplicados). Todos los ids deben ser miembros activos del FM target (`22023`). Rechaza `ended` (`55000`). |
| `get_facility_management_members(_relationship_id) → TABLE` | owner/admin del cliente, owner/admin del FM, platform_admin | Equipo asignado: `organization_member_id`, `user_id`, nombre, email, rol, `membership_is_active`, `assigned_at`. Ordenado por rol y nombre. |
| `get_my_facility_management_clients() → TABLE` | cualquier `authenticated` | **Clientes operativos del usuario**: relaciones `active`, cliente y FM activos, membresía activa **y asignada**. |
| `get_my_facility_management_portfolio() → TABLE` | owner/admin activos de un FM activo | **Cartera administrativa** del FM: todas sus relaciones (`pending`/`active`/`suspended`/`ended`) con status del cliente, permisos y `assigned_member_count`, esté o no asignado quien consulta. No otorga acceso operativo. |

### Nombre y email en `get_facility_management_members`

Mismo criterio que el resto de RPCs del repo:
`COALESCE(NULLIF(TRIM(raw_user_meta_data->>'name'), ''), split_part(email, '@', 1))`.
Solo se extrae la clave `name`; nunca se devuelve metadata cruda, y solo de
miembros ya asignados a esa relación.

### Decisión: cartera sin platform_admin

`get_my_facility_management_portfolio()` es exclusiva de owner/admin del
FM. Sin parámetros, para platform_admin sería una cartera global ambigua, y
no debe requerir una membresía ficticia en un FM. platform_admin administra
por `relationship_id` con las demás RPCs. Para cualquier usuario sin rol
owner/admin en un FM activo (manager, technician, platform_admin, cliente)
devuelve un conjunto vacío, sin error.

## 7. Cliente vs Facility Manager

| Acción | Cliente owner/admin | FM owner/admin | Miembro asignado | Miembro no asignado |
|---|---|---|---|---|
| Crear relación | sí | no | no | no |
| Conceder/revocar permisos | sí | no | no | no |
| Cambiar status | sí | no | no | no |
| Ver relaciones del cliente | sí | no | no | no |
| Ver cartera del FM | no | sí | no | no |
| Asignar/desasignar personas | **no** | sí | no | no |
| Ver equipo asignado | sí | sí | no | no |
| Acceso operativo (`has_…`) | no | solo si se asigna | según permiso | no |
| Aparece en `get_my_…_clients` | — | solo si se asigna | sí (si `active`) | no |

El cliente no administra el roster del FM, pero conserva la capacidad de
**suspender o terminar** la relación completa para cortar el acceso de
inmediato.

## 8. Auditoría

`public.audit_logs`, siempre con `organization_id` = **cliente (source)** y
`actor_user_id = auth.uid()`:

| `action` | `table_name` | Contenido |
|---|---|---|
| `facility_management.relationship_created` | `organization_relationships` | cliente, FM, status inicial (solo en una creación real) |
| `facility_management.permissions_replaced` | `facility_management_permissions` | `permissions` anteriores / nuevos |
| `facility_management.status_changed` | `organization_relationships` | status anterior/nuevo; en `ended`, `removed_permissions` |
| `facility_management.members_replaced` | `facility_management_relationship_members` | `organization_member_ids` anteriores / nuevos |

Sin secretos, tokens ni metadata de usuario.

## 9. Homologación de proveedores (Fase 18) — deuda legacy CERRADA en 9B

En 9A, `set_provider_relationship_status` (la RPC de "Proveedores
Homologados") todavía podía escribir filas `facility_management` sin
auditoría. **Desde 9B ya no administra Facility Managers**:

- `get_provider_relationship_directory` devuelve solo `provider_company` y
  `subcontractor_company` (mismo contrato de retorno).
- `set_provider_relationship_status` rechaza un target `facility_manager`
  con `22023` antes de escribir nada; no crea ni modifica relaciones
  `facility_management`. Proveedores y subcontratistas conservan
  exactamente su comportamiento histórico (incluidas sus transiciones
  libres, que no tienen la máquina de estados FM).
- Toda relación `facility_management` se gestiona **exclusivamente** con las
  RPCs de 9A.

`RequestProviderSelector` (invitación privada a cotizar) usa este mismo
directorio, así que tampoco lista Facility Managers — es la semántica
buscada, no un efecto colateral: ver §13.

## 10. 9C: integración por módulo

Cada módulo amplía sus policies/RPCs con el helper operativo de 9C.1,
`has_facility_management_operational_access(_all)(<client_org>, <permiso(s)>,
<roles FM permitidos>)`, que combina en la MISMA relación: asignación,
permiso(s), membresía activa y rol interno. Cada módulo tiene su propia
suite pgTAP.

- **9C.1 (hecho):** Activos + Criticidad, con el contexto reutilizable de
  "cliente operado" (`ManagedClientGate`, `?managedClient=` validado contra
  `get_my_facility_management_clients`). Ver
  `docs/FACILITY_MANAGER_ASSETS_CRITICALITY.md`.
- **9C.2 (hecho):** Inspecciones + Preventivo, con el mismo contexto de
  cliente operado. Ver `docs/FACILITY_MANAGER_INSPECTIONS_PREVENTIVE.md`.
  - technician ejecuta, pero no planifica;
  - `responsible_member_id` sigue siendo del cliente;
  - inventario, solicitudes preventivas y R2 quedan fuera.
- **9C.3 (hecho):** Avisos de avería / Backlog. Ver
  `docs/FACILITY_MANAGER_MAINTENANCE_NOTICES.md`.
  - viewer solo lee; technician y requester reportan; owner, admin y manager
    gestionan;
  - convertir un aviso en solicitud se delegó después, en 9C.4;
  - el responsable sigue siendo del cliente;
  - la respuesta delegada va minimizada: sin ids de solicitud ni de
    ejecución, nombres sin email y criticidad solo con `criticality.view`.
- **9C.4 (hecho):** Solicitudes. Ver `docs/FACILITY_MANAGER_REQUESTS.md`.
  - ver: `requests.view`, roles o/a/m/requester;
  - crear y operar los borradores propios: `view` + `create`, roles
    o/a/m/requester;
  - editar y anular solicitudes enviadas: `view` + `manage`, roles o/a/m;
  - aviso → solicitud y preventivo → solicitud exigen los permisos de ambos
    módulos, roles o/a/m;
  - la RLS de `requests` no se abre: todo pasa por RPCs minimizadas;
  - los contactos y el responsable interno siguen siendo del cliente;
  - cotizaciones, OT y el roster del cliente no se delegan.
- **Punto 10 (hecho):** Fotos y documentos R2 de activos. Ver
  `docs/ASSET_FILES_R2_PRODUCTIZATION.md`.
  - leer, listar y descargar: `assets.view`, roles o/a/m/technician;
  - subir, borrar y marcar principal: `assets.view` + `assets.manage`, roles
    o/a/m, y nunca sobre un activo archivado;
  - viewer y requester del FM no acceden; un miembro no asignado recibe el
    mismo "File not found" que un archivo inexistente;
  - sin política raw para el FM sobre `asset_documents`: solo RPCs y la Edge
    Function `asset-files`.
- **9C.5 (hecho):** Cotizaciones del cliente. Ver
  `docs/FACILITY_MANAGER_QUOTES.md`.
  - ver: `requests.view` + `quotes.view`, roles o/a/m/requester;
  - aprobar y rechazar: además `quotes.approve`, roles o/a/m;
  - los importes se ocultan en el servidor hasta `min_quotes`, y mientras
    tanto no se puede decidir;
  - la RLS de `quotes` no se abre; el FM nunca cotiza como proveedor;
  - `quotes.manage` no abre nada (no hay operación de gestión validada).
- Siguientes: OT, reportes.

## 11. Verificación

- Suite dedicada: 328/328.
- **Controles negativos** (transacciones descartables, nada queda en el
  repo):
  - quitar del helper la condición de asignación → fallan exactamente las
    6 pruebas "no asignado ⇒ false";
  - restaurar la validación incondicional "nace en pending" (ver hallazgo
    abajo) → fallan las 11 pruebas de la ruta legacy;
  - primera versión de 9A: ACL/policies reabiertos → 43 fallos; sin
    triggers → 13; helper sin filtros de status/membresía → 5.
- **Hallazgo corregido**: la validación "una relación FM nace en pending"
  corría en `BEFORE INSERT` y se disparaba también en el
  `INSERT ... ON CONFLICT DO UPDATE` de la RPC legacy, rechazando
  `Homologar`/`Suspender`/`Reactivar` sobre filas FM existentes. Ahora solo
  aplica cuando la fila es realmente nueva; hay pruebas de regresión del
  flujo de la UI.

## 12. Punto 9B — UI de administración

Vista única `#facility-management`
(`src/components/facility-management/FacilityManagementView.tsx`) cuya
variante depende del tipo de la organización activa y del rol:

| Contexto | Ítem del Sidebar | Puede |
|---|---|---|
| Cliente, owner/admin | **Facility Managers** | ver el directorio de empresas FM activas (`get_facility_manager_directory`), vincular (nace `pending`), cambiar estado (solo las transiciones que acepta la máquina 9A), editar permisos agrupados por módulo, ver el equipo asignado **en solo lectura** |
| Facility Manager, owner/admin | **Clientes administrados** | ver su cartera (`get_my_facility_management_portfolio`), ver permisos recibidos **en solo lectura**, asignar/desasignar personas **de su propia organización** |
| Cualquier otro (manager, technician, viewer…, provider, subcontractor, platform_admin) | nada | — (un `#facility-management` directo muestra "acceso denegado") |

- El gate vive en `getFacilityManagementMode` (`src/lib/facilityManagement.ts`)
  y lo aplican tanto el Sidebar como Dashboard (hash directo). Es solo UI:
  cada RPC vuelve a autorizar con `auth.uid()`.
- `useFacilityManagement` centraliza todas las llamadas; el frontend nunca
  escribe directo en las tablas de delegación. `currentOrganization` solo
  define el contexto visual.
- El roster del FM reutiliza `useOrganizationAccess` /
  `list_organization_access` (el mismo mecanismo de la pantalla Usuarios,
  que reemplazó a `admin-list-organization-members`); solo los miembros
  activos son seleccionables y se envía `organization_members.id`, nunca
  `user_id`.
- Labels de permisos y módulos en español; los códigos internos no cambian.
  El tipo del permiso sale de los tipos generados de Supabase y el listado,
  de `Constants.public.Enums.facility_management_permission`.
- `ApprovedProvidersList` ya no muestra ni filtra Facility Managers.

### RPC nueva: `get_facility_manager_directory(_client_organization_id)`

`SECURITY DEFINER`, `search_path = ''`, `EXECUTE` solo `authenticated`.
Owner/admin activos del cliente o platform_admin (`42501` si no); el id debe
ser un `client_company` (`22023`). Devuelve solo
`facility_manager_organization_id`, `facility_manager_organization_name`,
`relationship_id`, `relationship_status` de empresas `facility_manager`
activas (relación `NULL` si todavía no hay vínculo), ordenadas por nombre.
Nunca miembros, emails ni metadata.

### Verificación 9B

- `facility_manager_ui_integration.test.sql`: 75/75. Controles negativos:
  restaurando las versiones anteriores de las dos RPCs legacy de
  homologación fallan exactamente las 6 pruebas del cierre de esa ruta;
  restaurando las versiones anteriores de `is_provider_facing_organization`,
  `can_user_read_request` y `set_request_audience` fallan las pruebas de
  §13 (subcontratista provider-facing, FM no provider-facing, rechazo 22023
  y audiencia intacta) antes de que la transacción aborte.
- La suite 9A se adaptó sin cambiar su número de aserciones (328): sus
  pruebas que usaban la RPC legacy sobre filas FM ahora verifican las mismas
  garantías de trigger con un escritor de nivel servicio (`UPDATE` directo e
  `INSERT ... ON CONFLICT DO UPDATE`), y la que esperaba `55000` de la RPC
  legacy ahora espera su rechazo con `22023`.
- Smoke visual local (Chromium headless contra Supabase local, fixtures
  temporales, 46/46 checks; ver también §13): cliente vincula/configura/activa y ve el
  equipo en solo lectura; FM ve cartera y permisos en solo lectura y
  asigna/desasigna; client manager, FM manager y FM technician no ven el
  menú y el hash directo muestra acceso denegado; Proveedores Homologados
  sigue funcionando para proveedor y subcontratista sin mostrar FM.
- No existe infraestructura de pruebas unitarias frontend en el repo; no se
  introdujo una. La lógica pura (agrupación de permisos, gate por
  organización/rol, transiciones y labels de estado) está aislada en
  `src/lib/facilityManagement.ts` para cubrirla cuando exista.

## 13. Facility Manager NO es provider-facing (decisión funcional MVP)

- `provider_company` y `subcontractor_company` son las únicas
  organizaciones provider-facing: reciben invitaciones, ven el marketplace
  y cotizan.
- `facility_manager` **no** actúa como proveedor ni ofertante. Administra
  procesos del cliente mediante permisos delegados (9A/9C).
- `quotes.view`, `quotes.manage` y `quotes.approve` son permisos de
  **gestión delegada sobre el proceso de cotización del CLIENTE** (ver,
  gestionar, aprobar las cotizaciones que recibe el cliente), nunca
  "presentar una cotización como FM".
- Si en el futuro una organización debe actuar a la vez como FM y como
  proveedor, se modelará como **capacidad dual explícita**; no se inferirá
  de `organization_type = 'facility_manager'`.

### Backend (migración 9B, sección C)

| Función | Cambio |
|---|---|
| `is_provider_facing_organization(uuid)` | Solo `provider_company` y `subcontractor_company` activos. Antes: `provider_company` + `facility_manager` (y **faltaba** `subcontractor_company`). Es la única fuente de verdad. |
| `can_user_read_request(uuid)` | La rama provider-facing delega en el helper en vez de repetir tipos. Un FM no lee solicitudes públicas ni invitadas como proveedor. |
| `can_provider_quote_request(uuid, uuid)` | Sin cambios de código: ya dependía solo del helper. FM ⇒ `false` aunque la solicitud sea pública o exista un `request_provider_access` activo. `quotes.*` no interviene. |
| `set_request_audience(uuid, boolean, uuid[])` | Mismo contrato, reglas, atomicidad, auditoría y protección de cotizaciones. Destinatarios: solo provider-facing con relación **activa del tipo correspondiente** (`provider`/`subcontracting`); `facility_manager` ⇒ `22023`, aunque tenga una relación `facility_management` activa. |
| policies de `request_provider_access` | Sin cambios: ya usaban el helper, así que un FM no ve ni obtiene acceso por una fila creada por servicio. |

Efecto a tener en cuenta: `subcontractor_company` **gana** acceso
provider-facing real (antes el helper lo excluía aunque la UI y
`set_request_audience` ya lo trataban como proveedor).

El acceso **delegado** de un FM a las solicitudes/cotizaciones de su
cliente es 9C, por otra vía (`has_facility_management_permission`), no por
identidad de proveedor.

### Frontend

- Gate único `isProviderFacingOrganizationType` en
  `src/types/providerRelationship.ts` (mismo alcance que el helper SQL).
  Nunca se usa solo `user.role === 'proveedor'`: `AuthContext` sigue
  mapeando `facility_manager` a ese rol legacy por compatibilidad.
- Sidebar: "Solicitudes" (lado proveedor) y "Solicitudes Públicas" solo para
  proveedor/subcontratista. Un FM owner/admin conserva "Clientes
  administrados", "Perfil organización" y "Notificaciones".
- Dashboard: `#requests` (rama proveedor) y `#public-requests` muestran
  acceso denegado si la organización no es provider-facing, también por hash
  directo. El flujo de solicitudes del cliente no cambia.
- `ProviderRequestList`, `PublicRequestList` y `QuoteForm` usan el mismo
  gate.
- `RequestProviderSelector` solo lista proveedor/subcontratista con
  relación activa del tipo correspondiente; sin labels de Facility Manager.
- `OrganizationProfile` ya no muestra especialidades a un FM (las
  especialidades son un atributo del directorio de proveedores); los datos
  existentes se conservan.

### Verificación

- pgTAP (§12): `is_provider_facing_organization` por tipo/estado;
  `set_request_audience` acepta proveedor y subcontratista, rechaza FM con
  `22023` (con o sin relación `facility_management` activa) sin crear
  `request_provider_access`; `can_user_read_request` y
  `can_provider_quote_request` en `true` para proveedor/subcontratista y
  `false` para FM, incluso con una fila `request_provider_access` sintética.
- Smoke: FM owner sin "Solicitudes"/"Solicitudes Públicas" y con hash
  directo bloqueado; proveedor y subcontratista ven y abren ambas vistas;
  el cliente conserva "Mis Solicitudes"; el selector de invitación privada
  muestra proveedor y subcontratista y ningún FM.
