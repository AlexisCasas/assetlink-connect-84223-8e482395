# Permisos delegados Cliente → Facility Manager (Fase 1 · Punto 9A)

Fundación **solo backend**. Migración:
`supabase/migrations/20260927194923_facility_manager_delegated_permissions.sql`.
Pruebas: `supabase/tests/facility_manager_delegated_permissions.test.sql`
(328 aserciones).

Esta fase **no** amplía todavía las RLS de ningún módulo funcional
(activos, criticidad, inspecciones, preventivo, avisos, solicitudes,
cotizaciones, OT, reportes) y **no** toca frontend (Sidebar, Dashboard,
`usePermissions`, `types.ts`). Hoy nadie del FM ve datos nuevos del
cliente: la integración módulo por módulo es el paso siguiente.

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

## 9. Convivencia con la homologación de proveedores (Fase 18) — deuda para 9B

`set_provider_relationship_status` (usada por `ApprovedProvidersList`)
también puede escribir filas `facility_management`. Se conserva porque el
frontend depende de ella, pero queda gobernada por los triggers:

- respeta la máquina de estados (las transiciones de la UI actual caben en
  ella);
- no puede conceder permisos ni asignar personas (no tiene cómo);
- si termina una relación, se borran permisos y asignaciones; reabrirla no
  restaura nada.

Lo que **no** hace es auditar. **Deuda para 9B**: cuando exista la UI
específica de Facility Managers, mover la gestión FM a las RPCs de esta
migración y limitar `set_provider_relationship_status` a
`provider`/`subcontracting`.

## 10. Próximo paso: integración por módulo

Cada módulo ampliará sus policies/RPCs con
`has_facility_management_permission(<client_org>, '<modulo>.<accion>')`,
combinado con el rol interno del FM que corresponda, y con su propia suite
pgTAP. Hasta entonces, conceder permisos y asignar personas no abre ningún
dato. También queda pendiente regenerar `src/integrations/supabase/types.ts`
y la UI (delegaciones y equipo en el cliente; cartera, asignaciones y
selector de clientes operativos en el FM).

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
