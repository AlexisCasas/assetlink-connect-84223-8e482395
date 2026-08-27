# Roles operativos internos: Planner/Gestor y Técnico

Modela roles funcionales mínimos para operación interna (quién planifica,
quién ejecuta) sobre el modelo multi-tenant ya existente
(`organizations`/`organization_members`), sin crear ninguna matriz
jerárquica compleja ni un enum de rol nuevo.

## 1. Diagnóstico

- `organization_member_role` (enum, `20260717224621_multitenant_foundation.sql`):
  `owner, admin, manager, requester, quote_manager, technician, operator, viewer`.
  **`technician` ya existía** — no hizo falta agregar ningún valor de enum.
- `organization_members`: `id, organization_id, user_id, role, is_active,
  invited_by, joined_at, updated_at` — **sin `name`/`email`** (viven en
  `auth.users`, no accesible directo desde `select('*')` por RLS/diseño).
- `AdminConsole.tsx` ya crea/actualiza miembros vía Edge Functions
  (`admin-create-user-and-add-member`, `admin-update-organization-member`,
  `admin-list-organization-members`) — el `service_role` vive únicamente ahí,
  nunca en el frontend. Los `<Select>` de rol mostraban el valor crudo del
  enum (`owner`, `admin`, …) sin traducir.
- `usePermissions.ts` existía pero **no se usaba en ningún componente** —
  solo cubría `owner`/`admin`.
- `work_orders`: **sin ningún campo de asignación de técnico** (`assigned_to`,
  `technician_id`, etc. no existían) y su RLS **solo tenía policy de
  `SELECT`** — el propio comentario de
  `20260721205000_work_orders_from_approved_quotes.sql` decía
  *"Operational status updates... are intentionally deferred to later
  features"*.
- "Asignar Técnico" ya existía en dos lugares, **ninguno productivo**:
  - `AssetDetail.tsx`: botón `disabled`, puramente decorativo.
  - `AssignmentDialog.tsx` (usado desde `ProviderRequestList.tsx`, detrás de
    un `{false && ...}` inalcanzable): flujo legacy de
    Cotizador/Revisor/Aprobador sobre `team_members`/`assignments`
    (tablas no tenant-aware, keyed por `providers.id`), un concepto
    completamente distinto a "técnico ejecuta trabajo".
  - El lugar realmente productivo y tenant-aware es
    `WorkOrderDetailDialog.tsx` (antes solo lectura) — igual que sugería la
    propia tarea como alternativa natural.

## 2. Modelo funcional (sin enum nuevo)

| Rol real (`organization_member_role`) | Label individual | Label funcional agrupado |
|---|---|---|
| `owner` | Propietario | **Administrador** |
| `admin` | Administrador | **Administrador** |
| `manager` | Planner / Gestor | **Planner / Gestor** |
| `technician` | Técnico | **Técnico** |
| `viewer` | Visor | Visor |
| `requester`, `quote_manager`, `operator` | (labels existentes/seguros) | — |

Todo centralizado en `src/lib/organizationRoles.ts`:

- `ORGANIZATION_ROLE_LABELS`: label individual por valor de enum (mantiene
  `owner` y `admin` visualmente distintos en selects/listas — mostrar dos
  opciones idénticas "Administrador" en un `<Select>` sería inutilizable).
- `OPERATION_MEMBER_ROLES`: `['admin', 'manager', 'technician', 'viewer']` —
  el set mínimo pedido para la UI de administración de miembros.
- `isOrganizationAdminRole`, `isPlannerRole`, `isTechnicianRole`.
- `canPlanWork(role)`: owner/admin/manager.
- `canExecuteWork(role)`: technician.
- `getFunctionalRoleLabel(role)`: colapsa owner/admin → "Administrador",
  manager → "Planner / Gestor", technician → "Técnico" (para vistas
  resumidas que no necesitan distinguir propietario de administrador).

Reutilizado en `AdminConsole.tsx` (selects de rol), `Sidebar.tsx` y
`OrganizationSwitcher.tsx` (antes cada uno tenía su propio mapa de labels
duplicado, ahora comparten uno solo).

## 3. `usePermissions()` (hook existente, ahora sí usado)

Extendido, sin romper su API previa (`hasRole`, `isOwnerOrAdmin`,
`canManageMembers`, `canManageOrganization` siguen igual), agregando:

```ts
const { isOrganizationAdmin, isPlanner, isTechnician, canPlanWork, canExecuteWork } = usePermissions();
```

Derivado de `currentMembership` (organización activa) vía
`src/lib/organizationRoles.ts` — ningún cálculo de rol nuevo, solo
composición del helper central. Usado en `WorkOrderDetailDialog.tsx` para
decidir si se muestra el selector de técnico o solo el nombre en modo
lectura.

## 4. Selector de técnicos limitado por organización

**No existe columna `name`/`email` en `organization_members`**, así que
leerlas de forma segura desde el frontend requiere pasar por `auth.users`,
que RLS no expone directo a `authenticated`. Se implementó la ruta
recomendada por la propia tarea: una RPC `SECURITY DEFINER` mínima.

### `public.get_assignable_technicians(p_organization_id uuid)`

- Verifica `auth.uid()` autenticado.
- Verifica que el llamador sea `owner`/`admin`/`manager` de
  `p_organization_id` (vía `has_organization_role`, ya existente) o
  `platform_admin` (vía `is_platform_admin`, ya existente) — **si no, lanza
  excepción** y no devuelve ninguna fila.
- Devuelve solo `member_id, user_id, name, email` de miembros
  **activos** con `role = 'technician'` **de esa organización**, join
  contra `auth.users` (patrón ya usado en RLS legacy de este mismo
  proyecto, ej. `client_email = (SELECT email FROM auth.users WHERE id =
  auth.uid())` en `20260515182019_...sql`).
- `name` sale de `raw_user_meta_data->>'name'` (mismo campo que ya usa el
  Edge Function `admin-list-organization-members`), con fallback al prefijo
  del email.
- No expone ningún otro dato de `auth.users` (sin teléfono, sin metadata
  arbitraria, sin última conexión, etc.).

Frontend: `src/hooks/useOrganizationTechnicians.ts` (llama a la RPC, nunca
consulta `organization_members`/`auth.users` directo) y
`src/components/members/TechnicianSelect.tsx` (combobox controlado, muestra
"Nombre (email)", opción "Sin asignar", estados de carga/error, mensaje si
la organización no tiene técnicos activos aún).

**Aislamiento multi-tenant**: probado explícitamente — la RPC nunca
devuelve técnicos de una organización distinta a `p_organization_id`, y
además exige que el llamador tenga rol de gestión en *esa* organización
específica (no alcanza con ser owner/admin de cualquier otra).

## 5. Asignación operativa: `work_orders.assigned_member_id`

### Migración `20260827041707_operation_members_roles.sql`

- `ALTER TABLE public.work_orders ADD COLUMN assigned_member_id uuid NULL
  REFERENCES public.organization_members(id) ON DELETE SET NULL;` +
  índice `idx_work_orders_assigned_member_id`.
- Trigger `check_work_order_assigned_technician` (`BEFORE INSERT OR
  UPDATE`): si `assigned_member_id` no es nulo, exige que:
  a) pertenezca a `work_orders.provider_organization_id` (mismo tenant),
  b) `is_active = true`,
  c) `role = 'technician'`.
  Si cualquiera falla, `RAISE EXCEPTION` — el `UPDATE` no se aplica.
- **No se creó ninguna policy `UPDATE`/`INSERT`/`DELETE` genérica en
  `work_orders`** (sigue teniendo solo la `SELECT` de la fase anterior — el
  comentario original sobre "deferred to later features" sigue vigente para
  cambios de `status`/título/etc.). Es decir, **no se relajó RLS**.
- En su lugar, `public.assign_work_order_technician(target_work_order_id
  uuid, target_member_id uuid)` — `SECURITY DEFINER`, la única forma de
  escribir `assigned_member_id`:
  - Exige `auth.uid()`.
  - Carga la orden; si no existe, error.
  - Exige `owner`/`admin`/`manager` de `provider_organization_id` (la
    organización que ejecuta el trabajo, no la cliente) o `platform_admin`.
  - Hace el `UPDATE` (la consistencia de fila la valida el trigger de
    arriba, sin duplicar la lógica en la función).
  - `REVOKE ALL ... FROM PUBLIC` + `GRANT EXECUTE ... TO authenticated`
    (mismo patrón que el resto de funciones del proyecto).

### Por qué no se duplicó el técnico como texto libre

`assigned_member_id` referencia `organization_members.id` (no un nombre en
texto). El nombre/email para mostrar se resuelve en el momento, vía la
misma lista de `get_assignable_technicians` ya cargada — no se guarda texto
denormalizado en `work_orders`.

### Integración en UI

- `WorkOrderDetailDialog.tsx`: nueva sección "Técnico asignado".
  - Si quien mira es **owner/admin/manager de la organización proveedora**
    de esa orden (`currentOrganization.id === workOrder.provider_organization_id
    && canPlanWork`): muestra `TechnicianSelect` + botón "Guardar
    asignación" (llama a la RPC, refresca la orden en la lista con
    `onAssigned`).
  - En cualquier otro caso (cliente, viewer/requester, technician, u otra
    organización): solo lectura — muestra el nombre resuelto si está
    disponible, o "Sin técnico asignado".
  - **La organización cliente nunca ve el selector**, aunque su rol sea
    owner/admin: asignar técnicos es una decisión operativa interna del
    proveedor, no del cliente.
- `WorkOrdersList.tsx`: columna adicional "Técnico" (solo visible cuando se
  navega como organización proveedora), con el nombre resuelto o "—".

## 6. Accesos y permisos (sin tocar RLS de organizaciones)

| Quién | Ve "Órdenes de trabajo" | Puede asignar técnico | Ve "Administración" |
|---|---|---|---|
| owner/admin/manager de `client_company`, `provider_company`, `facility_manager` | Sí (ya existente, sin cambios) | Solo si es la organización **proveedora** de esa orden | No (a menos que además sea platform_admin) |
| `technician` | Sí (mismo menú que el resto de su organización — ver pendientes) | No | No |
| `viewer`/`requester` | Sí | No | No |
| `platform_admin` | No (ya oculto antes de esta fase — `canViewWorkOrders` excluye `platform_admin`) | No aplica (no gestiona técnicos de su propia organización platform_admin como si fuera cliente/proveedor) | Sí (sin cambios) |

Nada de esto se implementó reabriendo RLS: la autorización real vive en
`assign_work_order_technician`/`get_assignable_technicians` (`SECURITY
DEFINER`, revalidan en cada llamada) y en `usePermissions()` a nivel de UI.

## 7. Pendiente (documentado, no construido en esta fase)

- **No existe una pantalla "Mis Asignaciones" dedicada para técnicos de una
  organización proveedora.** El "Mis Asignaciones" que ya existe en el
  Sidebar es del flujo legacy `team_member` (mapeado desde organizaciones
  `platform_admin`, no de `technician`). Un técnico de `provider_company`
  hoy ve el mismo "Órdenes de trabajo" que el resto de su organización
  (todas las órdenes del proveedor, no filtradas a "las mías"). Construir
  una vista filtrada por `assigned_member_id = mi membership.id` es la
  extensión natural, pero no se hizo en esta fase (explícitamente fuera de
  alcance: *"no inventar un módulo grande todavía"*).
- Un `technician` que ve `WorkOrderDetailDialog` de una orden asignada a él
  mismo no ve el nombre propio resuelto (la RPC de técnicos exige rol
  owner/admin/manager; para un `technician` la llamada falla de forma
  segura y cae a "Técnico asignado" genérico). No es una fuga de datos —
  solo una limitación de UX a resolver junto con el punto anterior.
- No se restructuró el Sidebar del proveedor por rol granular (todos los
  miembros de una `provider_company` siguen viendo el mismo bloque de menú
  hoy) — deliberado, para no arriesgar ocultar módulos por accidente a
  admin/planner sin una pantalla de reemplazo lista para el técnico.

## 8. Validaciones ejecutadas

- `git status --short`: working tree limpio al iniciar, rama
  `feature/operation-members-roles` correcta.
- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores sobre el resto del historial.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; `work_orders.assigned_member_id`, `assign_work_order_technician`
  y `get_assignable_technicians` presentes con sus tipos.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- Extra (no pedido, para confirmar que no se rompió nada):
  `npx tsc -p tsconfig.app.json --noEmit` — mismos errores preexistentes ya
  documentados en fases anteriores, ningún error nuevo.

## 9. Checklist manual (dentro de Organización A, `provider_company`)

1. Como platform admin (o owner de Organización A), crear un usuario
   **Planner** con rol real `manager` desde Administración → confirmar que
   el selector de rol ahora muestra "Planner / Gestor" (no `manager`).
2. Crear **Técnico Alexis** y **Técnico César** con rol `technician`.
3. Como owner/admin/manager de Organización A, abrir una orden de trabajo
   propia (`provider_organization_id` = Organización A) → confirmar que el
   selector de técnico lista a Alexis y César (nombre + email).
4. Cambiar a Organización B (u otro usuario de Organización B) → abrir una
   orden de trabajo de Organización B → confirmar que Alexis/César **no**
   aparecen en el selector.
5. Asignar a César → guardar → confirmar toast de éxito, que la columna
   "Técnico" de la lista se actualiza, y que reabrir el detalle muestra a
   César ya seleccionado.
6. Iniciar sesión como Técnico Alexis (rol `technician`) → abrir la misma
   orden → confirmar que **no** ve el selector, solo texto de solo lectura.
7. Iniciar sesión como un `viewer`/`requester` de Organización A → confirmar
   que tampoco ve el selector.
8. Confirmar que un platform admin en su organización `platform_admin` no
   ve "Órdenes de trabajo" en el menú (sin cambios respecto a antes) y que
   Administración sigue funcionando con normalidad.
9. `git grep -n "service_role" src` sin resultados.
10. `npm run build` exitoso.
