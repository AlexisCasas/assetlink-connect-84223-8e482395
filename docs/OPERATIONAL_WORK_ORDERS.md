# Órdenes de trabajo operacionales

Convierte `work_orders` en una única entidad operacional real, compartida
por los dos orígenes existentes (externo, desde cotización aprobada;
interno, desde solicitud interna directa). **No se crea ningún módulo
paralelo de "OT interna"** — sigue existiendo una sola tabla, un solo hook
(`useWorkOrders`), una sola lista (`WorkOrdersList.tsx`) y un solo detalle
(`WorkOrderDetailDialog.tsx`); el origen es un dato más de la fila
(`work_order_type`), no una bifurcación de UI.

## 1. Origen: externo vs. interno

| | Externa | Interna |
|---|---|---|
| Se crea desde | `create_work_order_from_quote(target_quote_id)` (cotización aprobada) | `create_internal_work_order_from_request(target_request_id, target_assigned_member_id)` (solicitud interna) |
| `work_order_type` | `'external'` | `'internal'` |
| `quote_id` | siempre no nulo | siempre nulo (constraint `work_orders_type_quote_consistency` lo obliga) |
| `provider_organization_id` | organización del proveedor que cotizó | igual a `client_organization_id` (no hay proveedor externo) — decisión heredada de `docs/INTERNAL_REQUESTS_WORK_ORDERS.md` |
| "Organización operadora" (dueña de planner/técnico) | `provider_organization_id` | `provider_organization_id` (= `client_organization_id`) |

Ambas rutas de creación pueblan hoy los mismos campos operacionales nuevos
(§3) de la misma forma, así que la ficha y el listado no necesitan ningún
`if (interna) { ... } else { ... }` estructural — solo esconden/muestran
"Cotización aprobada" e "Importe" según `work_order_type`.

## 2. Campos nuevos (migración `20260827150000_operational_work_orders.sql`)

### Correlativo: `work_order_number`

Generado **siempre en el servidor**, nunca por el frontend: un trigger
`BEFORE INSERT` (`set_work_order_number`) lo asigna desde una secuencia
Postgres (`work_order_number_seq`) con formato `OT-<año de creación>-<secuencia
global, 6 dígitos>` (ej. `OT-2026-000123`). La secuencia es **global, no se
reinicia por año** — mantiene unicidad y monotonicidad estrictas sin la
complejidad de un contador por año; el "-2026-" del formato refleja
únicamente el año de creación de esa fila, no una numeración que reinicie
en 000001 cada enero. `NOT NULL` + índice `UNIQUE`.

### Activo: `work_orders.asset_id`

Snapshot relacional directo (no solo vía `request_id → requests.asset_id`),
backfillado desde `requests.asset_id` al crear la OT. Un trigger
(`check_work_order_asset_organization`) exige que el activo pertenezca a
`client_organization_id` — que es siempre la misma organización que
`requests.organization_id` en ambos flujos, así que no hace falta ningún
join extra para validarlo. **No es editable** después de creada la OT (ver
§4): es un dato de origen, igual que `request_id`/`quote_id`.

### Tipo: `work_orders.work_order_type`

Columna explícita (`'internal' | 'external'`) en vez de derivar todo de
`quote_id IS NULL` en cada vista — mejor UX operacional (filtrar/badge sin
recalcular). Un CHECK (`work_orders_type_quote_consistency`) la ata
permanentemente a la nulidad de `quote_id`, así que **no puede desincronizarse**:
`internal` siempre implica `quote_id IS NULL` y viceversa, a nivel de base
de datos, no solo por convención de la app.

### Planner: `work_orders.planner_member_id`

Referencia a `organization_members`. Un trigger
(`check_work_order_planner`, mismo patrón que el de técnico asignado)
exige que pertenezca a `provider_organization_id`, esté activo, y tenga rol
`owner`/`admin`/`manager`. Se resuelve **solo en el servidor**, nunca
confiando en un id que mande el cliente: la función
`resolve_caller_planner_member(organization_id)` busca la membresía propia
del usuario autenticado con ese rol en esa organización; si no existe
(el usuario que crea la OT no es owner/admin/manager de la organización
operadora — el caso típico al crear una OT externa desde el lado cliente,
que aprueba la cotización pero no es miembro del proveedor), queda `NULL`
y se asigna después manualmente desde la ficha.

### Técnico(s): `assigned_member_id` (sin cambios de esquema)

Sigue siendo el técnico principal, ya existente desde
`docs/OPERATION_MEMBERS_ROLES.md`. **No se implementó
`work_order_technicians` (múltiples técnicos) en esta fase** — alcance
explícitamente diferido, ver §7.

### Fechas: `scheduled_at` / `due_at` (`timestamptz`)

Se eligió `timestamptz` (no `date`) por consistencia: es el tipo que ya usa
todo el resto del esquema para fechas operacionales (`requests.deadline`,
timestamps de `quotes`, etc.) — no existe ningún precedente de columna
`date` pelada para un concepto equivalente. `due_at` se backfillea desde
`requests.deadline` al crear la OT.

### Prioridad: `work_orders.priority`

`'low' | 'medium' | 'high' | 'urgent'`, backfillada desde
`requests.priority` (entero 1–4, 1 = emergencia la más alta — ver
`RequestForm.tsx`'s `priorityMap`) vía la función reutilizable
`map_request_priority_to_work_order_priority`: `1→urgent, 2→high,
3→medium, 4→low`. Un CHECK valida los 4 valores; default `'medium'`.

### Estado: `work_orders.status`

Se amplía sin romper nada: el único valor que la app escribió **alguna
vez** en `status` fue el default original `'created'` (confirmado por
grep: ninguna migración ni componente de `src/` escribe `status` desde
antes de esta fase), así que la migración lo remapea exhaustivamente —
`'created'` → `'assigned'` si ya tenía técnico, si no `'pending'` — y
después agrega el CHECK con el ciclo de vida nuevo: `pending, assigned,
in_progress, completed, closed`. `cancelled`/`suspended` quedan
explícitamente fuera del CHECK por ahora (ver §7) aunque las columnas
`cancelled_at`/`started_at`/`completed_at` ya existían desde el diseño
original.

`assign_work_order_technician` (ya existente) ahora también empuja el
estado entre los dos casos "obvios" alrededor de una asignación: si se
asigna un técnico y el estado era `pending`, pasa a `assigned`; si se
quita el técnico y el estado era `assigned`, vuelve a `pending`. Nunca
toca `in_progress`/`completed`/`closed` — esos son decisiones explícitas
del planner vía `update_work_order_operations`.

### Observaciones: `work_orders.observations` (`text`, nullable)

## 3. Creación: campos poblados por cada RPC

Ambos `CREATE OR REPLACE FUNCTION` (mismas firmas de siempre, sin cambios
en los call sites del frontend — `QuoteListDialog.tsx` y `RequestList.tsx`
no se tocaron):

**`create_work_order_from_quote(target_quote_id)`** — externa:
`work_order_type='external'`, `asset_id=requests.asset_id`,
`priority=` mapeada desde `requests.priority`, `due_at=requests.deadline`,
`planner_member_id=resolve_caller_planner_member(provider_organization_id)`,
`status='pending'` (nunca `'assigned'` aquí — esta RPC no recibe técnico).

**`create_internal_work_order_from_request(target_request_id,
target_assigned_member_id)`** — interna: igual que arriba pero
`work_order_type='internal'`, `planner_member_id=
resolve_caller_planner_member(organization_id)` (la organización cliente,
que es la operadora), y `status='assigned'` si se envió
`target_assigned_member_id`, si no `'pending'`.

## 4. Edición: `update_work_order_operations`

Único camino de escritura para los campos operacionales
(`planner_member_id`, `assigned_member_id`, `scheduled_at`, `due_at`,
`priority`, `status`, `observations`) de una OT ya creada. Reemplazo
completo (el frontend siempre manda el estado final deseado de cada campo,
igual que `assign_work_order_technician` ya hacía) — no hay
parches parciales ni flags de "limpiar campo".

- Solo owner/admin/manager de `provider_organization_id` (la organización
  operadora — para una OT interna, la misma organización cliente) o
  `platform_admin` pueden llamarla.
- `request_id`, `quote_id`, `asset_id`, `work_order_type`,
  `client_organization_id`, `provider_organization_id` **no son
  editables** aquí — son datos de origen, no de planificación.
- **No se agregó ninguna policy `UPDATE` genérica** a `work_orders` —
  sigue sin ninguna, como en las dos fases anteriores; esta RPC (más
  `assign_work_order_technician`, que sigue existiendo pero ya no se llama
  desde la UI, consolidada en la ficha) son las únicas formas de escribir.
- Un `technician` puede **ver** la ficha completa pero no tiene acceso a
  estos controles (ver §6). Permitirle cambiar su propio estado a
  `in_progress`/`completed` queda documentado como pendiente, no
  construido (§7).

## 5. UI

- `WorkOrdersList.tsx`: mismo listado de siempre (no hay una lista
  separada por tipo). Columnas siempre visibles: Correlativo, Tipo,
  Activo, Técnico, Fecha límite, Prioridad, Estado, Detalle — igual que
  la propia tarea pidió priorizar si la tabla queda muy ancha. Columnas
  adicionales (Solicitud origen, Planner, Programada, Cliente/Proveedor,
  Importe) se ocultan en pantallas angostas vía clases responsive de
  Tailwind (`hidden md:table-cell`, etc.), no vía un sistema de columnas
  configurables nuevo — `WorkOrdersList` no tenía esa infraestructura y no
  se justifica construirla solo para esta fase.
- Técnico/Planner ahora se resuelven **siempre** contra la organización
  del propio viewer (antes el nombre de técnico solo se resolvía si
  `isProviderView`). Esto es lo que hace que, para una OT interna, el
  cliente vea el nombre real de su propio técnico/planner — para una OT
  externa vista por el cliente, `technicians`/`planners` (acotados a su
  propia organización) simplemente no van a contener ese miembro (vive en
  la organización proveedora), y el fallback genérico ("Técnico asignado")
  se activa solo — ninguna organización ve nunca el roster de otra.
- `WorkOrderDetailDialog.tsx`: ficha completa (correlativo, tipo,
  solicitud origen, cotización solo si es externa, activo con ruta vía
  `RequestAssetSummary` reutilizado tal cual de solicitudes, planner,
  técnico, fechas, prioridad, estado, observaciones). Si
  `currentOrganization.id === provider_organization_id && canPlanWork`
  (misma condición que ya existía, generaliza sola a OT internas porque
  para ellas `provider_organization_id` es la propia organización
  cliente), se muestra un formulario editable único con un botón "Guardar
  cambios" que llama a `update_work_order_operations` una sola vez con
  todos los campos. Cualquier otro viewer ve la misma sección en modo
  solo lectura.
- Activo: `PlannerSelect.tsx` + `useOrganizationPlanners.ts` son nuevos,
  espejo exacto de `TechnicianSelect.tsx` +
  `useOrganizationTechnicians.ts` pero para el rol
  owner/admin/manager vía la RPC `get_assignable_planners`.

## 6. Permisos

| Quién | Ve la ficha | Edita planificación |
|---|---|---|
| owner/admin/manager de la organización operadora de esa OT (`provider_organization_id`) | Sí | Sí |
| Cualquier otro rol de esa misma organización (technician, viewer, requester) | Sí | No |
| Organización cliente viendo una OT externa (no es la operadora) | Sí (sin nombres de staff del proveedor) | No |
| `platform_admin` | Sí | Sí (autorización explícita en la RPC) |

Nada de esto se implementó relajando RLS: `work_orders` sigue sin ninguna
policy `INSERT`/`UPDATE` genérica; toda la autorización real vive en las
RPCs `SECURITY DEFINER`, que revalidan en cada llamada.

## 7. Pendiente (documentado, no construido en esta fase)

- **Múltiples técnicos por OT**: se evaluó una tabla puente
  `work_order_technicians (work_order_id, member_id, is_primary)` pero se
  descartó para esta fase por alcance — `assigned_member_id` sigue siendo
  el único técnico (principal) soportado. Construirla es la extensión
  natural cuando se necesite, sin tocar el resto de este diseño.
- **`cancelled`/`suspended`** no están en el CHECK de `status` todavía
  (aunque las columnas `cancelled_at`/`started_at` ya existen desde el
  diseño original de `work_orders`). Agregarlos requiere una migración de
  una línea (ampliar el CHECK) cuando se construya esa fase — deliberado,
  para no dejar estados "medio soportados" sin UI/transición real.
- **Técnico auto-gestionando su propio estado** (pasar una OT asignada a
  `in_progress`/`completed` sin pasar por un planner) no se implementó.
  `update_work_order_operations` exige owner/admin/manager de la
  organización operadora; un técnico puede ver su OT pero no cambiarle el
  estado. Si se decide habilitarlo, la ruta más simple es una RPC nueva y
  angosta (`technician_update_work_order_status`) que solo permita mover
  `assigned → in_progress → completed` y solo si `assigned_member_id =`
  la membresía propia del llamador — no reabrir
  `update_work_order_operations` a technicians.
- No hay todavía una vista "Mis OT" filtrada por técnico/planner (mismo
  pendiente ya documentado en `docs/OPERATION_MEMBERS_ROLES.md`).
