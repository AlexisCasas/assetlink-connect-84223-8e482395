# Actividades de la orden de trabajo

Agrega el nivel operativo de actividades dentro de una OT:
`work_orders → work_order_activities → técnicos por actividad`. Sigue la
misma regla que las dos fases anteriores — **una sola jerarquía**, sin
distinguir "actividades internas" de "actividades externas": una actividad
cuelga de `work_orders` sin que le importe si esa OT vino de una cotización
aprobada o de una solicitud interna directa.

## 1. Modelo

```
work_orders (1) ──< work_order_activities (N) ──< work_order_activity_technicians (N) >── organization_members
```

- **`work_order_activities`**: una fila por actividad (`OT-00125` →
  "Cambiar rodamiento", "Lubricar eje", "Realizar prueba"). `organization_id`
  es la organización operadora de la OT (`work_orders.provider_organization_id`
  — para una OT interna, la misma organización cliente), denormalizada y
  fijada por trigger (`check_work_order_activity_organization`) para que
  las consultas/RLS filtren directo sin joinear `work_orders` cada vez.
- **`work_order_activity_technicians`**: tabla puente, **múltiples técnicos
  por actividad desde el modelo** (el requerimiento dice "Técnico(s)"). La
  UI inicial expone un checklist simple sin un control dedicado para elegir
  "el principal" — el primer id que llega en `p_technician_member_ids` se
  marca `is_primary = true` server-side; ver §7 para el refinamiento
  pendiente.

### `due_at`: timestamptz, no `date`

Igual decisión que `work_orders.scheduled_at`/`due_at` en la fase anterior:
todo el resto del esquema usa `timestamptz` para fechas operacionales, no
existe un precedente de columna `date` pelada para un concepto equivalente
— se mantiene la consistencia en vez de introducir un tipo nuevo solo para
esta tabla.

### Estados de actividad (4, no 5)

`pending, assigned, in_progress, completed` — deliberadamente **sin**
`closed` (que sí existe en `work_orders.status`): una actividad se
completa, la OT completa se "cierra" como un paso administrativo aparte a
nivel de cabecera. Ningún trigger sincroniza automáticamente el estado de
la OT con el de sus actividades en esta fase (ver §7).

## 2. RLS y RPCs

Ninguna policy `INSERT`/`UPDATE`/`DELETE` genérica en ninguna de las dos
tablas — igual que `work_orders` desde su primera migración, toda
escritura pasa por una RPC `SECURITY DEFINER` que revalida autorización en
cada llamada.

### Visibilidad: más estricta que `work_orders` en sí

La policy `SELECT` de ambas tablas (y la autorización de
`get_work_order_activities`) exige ser miembro de `organization_id` (la
organización **operadora**) o `platform_admin` — **no** "cliente o
proveedor" como la policy `SELECT` de `work_orders` (que sí deja leer la OT
a ambos lados de una transacción externa). Es una decisión deliberada: el
desglose de actividades técnico por técnico es un detalle de ejecución
interno del operador, no algo que se comparta con el cliente por defecto.
Efecto concreto: un cliente que abre el detalle de **su propia OT externa**
ve toda la cabecera (correlativo, estado, importe, planner/técnico
genéricos) pero la sección "Actividades" **no se renderiza en absoluto**
para él (`WorkOrderDetailDialog.tsx` la oculta con la misma condición que
usa la RPC, en vez de mostrarla e intentar una llamada que fallaría por
autorización). Para una OT **interna**, `provider_organization_id ==
client_organization_id`, así que el cliente **es** la organización
operadora y ve la sección con normalidad — mismo componente, ningún branch
especial por origen.

### `get_work_order_activities(p_work_order_id)`

Devuelve las actividades de una OT ordenadas por `sequence, created_at`,
cada una con sus técnicos resueltos (`member_id, name, email, is_primary`)
como `jsonb`, mismo patrón de join contra `auth.users` que
`get_assignable_technicians`/`get_assignable_planners`. Una sola llamada —
el frontend nunca necesita stitch-ear una segunda consulta para nombres.

### `upsert_work_order_activity(...)`

Crea (`p_activity_id = NULL`) o actualiza una actividad. Solo
owner/admin/manager de `work_orders.provider_organization_id` o
`platform_admin`. Reemplazo completo del set de técnicos
(`p_technician_member_ids`, misma convención que `update_work_order_operations`
de la fase anterior — el frontend siempre manda la lista completa deseada,
no un delta). Cada técnico se revalida server-side (misma organización,
activo, rol `technician`) antes de escribir nada. `sequence` se
autoasigna (`MAX(sequence)+1` de esa OT) si no se envía explícitamente.

### `delete_work_order_activity(p_activity_id)`

Solo owner/admin/manager de la organización operadora o `platform_admin`.
Los técnicos vinculados se borran solos por `ON DELETE CASCADE`.

### Corrección: ambigüedad de columnas (`20260827170000_fix_work_order_activities_rpc_ambiguity.sql`)

`get_work_order_activities` originalmente usaba `RETURNS TABLE(id uuid,
...)`, que en PL/pgSQL crea variables OUT implícitas con esos mismos
nombres (`id`, `status`, `sequence`, etc.) visibles en todo el cuerpo de la
función. Su primera consulta (`... FROM public.work_orders WHERE id =
target_work_order_id`) referenciaba `id` sin alias — ambiguo entre
`work_orders.id` y la variable OUT `id` → Postgres 42702
(`ambiguous_column`) en cada llamada. Se corrigió con alias cortos de tabla
en las tres funciones (`wo`, `woa`, `woat`, `om`, `au`) y renombrando todos
los parámetros con prefijo `p_` (antes `target_*`) para que ningún nombre
de parámetro se parezca a una columna. Como Postgres no permite renombrar
parámetros vía `CREATE OR REPLACE FUNCTION` (`SQLSTATE 42P13`), la
migración correctiva hace `DROP FUNCTION` (misma firma de tipos) antes de
cada `CREATE OR REPLACE FUNCTION`. La migración original
(`20260827160000_work_order_activities.sql`, ya aplicada en
local/remoto) queda intacta — esta es una migración correctiva encima,
no una edición de la original.

### Reordenar: sin RPC dedicada

Los botones subir/bajar de la lista llaman `upsert_work_order_activity` dos
veces (intercambian `sequence` entre la actividad y su vecina inmediata) —
no se creó una RPC de reordenamiento aparte. No hay `UNIQUE` sobre
`(work_order_id, sequence)`, así que el duplicado transitorio entre ambas
llamadas es inofensivo.

## 3. Frontend

- `src/types/workOrderActivity.ts`: `WorkOrderActivity`,
  `WorkOrderActivityTechnician`, `WorkOrderActivityInput`.
- `src/hooks/useWorkOrderActivities.ts`: carga (`get_work_order_activities`),
  `saveActivity`/`deleteActivity`/`moveActivity`. Cada mutación
  **refresca la lista completa desde el servidor** en vez de parchear
  estado local — los nombres de técnico siempre vienen de la resolución
  del servidor, nunca adivinados en el cliente.
- `src/components/work-orders/WorkOrderActivitiesSection.tsx`: la sección
  "Actividades" en sí (lista + acciones), integrada directo en
  `WorkOrderDetailDialog.tsx` — **no es un módulo/pantalla aparte**.
- `src/components/work-orders/ActivityEditorDialog.tsx`: formulario de
  alta/edición (descripción, horas, secuencia, fecha límite, estado,
  checklist de técnicos scoped a la organización operadora vía
  `useOrganizationTechnicians`, el mismo hook ya usado para el técnico
  principal de la OT).
- `src/lib/dateTime.ts`: conversión `timestamptz` ↔
  `<input type="datetime-local">`, extraída de `WorkOrderDetailDialog.tsx`
  (que ya la tenía para `scheduled_at`/`due_at` de cabecera) para
  reutilizarla también en `ActivityEditorDialog.tsx` sin duplicarla.
- Badge nuevo `WorkOrderActivityStatusBadge` en `StatusBadge.tsx`
  (`WORK_ORDER_ACTIVITY_STATUS_LABELS`: Pendiente/Asignada/En
  ejecución/Finalizada) — deliberadamente separado de
  `WorkOrderStatusBadge` (la cabecera de la OT) porque los sets de valores
  son distintos (la OT tiene `closed`, la actividad no).

## 4. Permisos

| Quién | Ve "Actividades" | Gestiona (crear/editar/eliminar/reordenar) |
|---|---|---|
| owner/admin/manager de la organización operadora de esa OT | Sí | Sí |
| `technician`/`viewer`/`requester` de esa misma organización | Sí | No (solo lectura) |
| Cliente viendo una OT externa que no opera | No (sección oculta) | No aplica |
| `platform_admin` | Sí | Sí |

Un técnico puede ver todas las actividades de la OT (no solo las suyas) y
sus técnicos asignados, pero no tiene ningún control de edición — igual
que ya pasaba con la planificación de cabecera en la fase anterior. Que un
técnico autogestione el estado de **sus propias** actividades (ej. marcar
"En ejecución"/"Finalizada" sin pasar por un planner) queda documentado
como pendiente, no construido (§7).

## 5. Cómo probar manualmente

1. Abrir el detalle de una OT (interna o externa) como owner/admin/manager
   de su organización operadora.
2. Confirmar la sección "Actividades" con el mensaje vacío inicial.
3. Agregar "Cambiar rodamiento" (2h, técnico Alexis), "Lubricar eje" (1h,
   técnico César), "Realizar prueba" (0.5h, Alexis + César) — confirmar que
   la tercera acepta ambos técnicos marcados.
4. Guardar, cerrar el diálogo, reabrirlo → confirmar que las 3 persisten
   con técnicos, horas, secuencia y estado intactos.
5. Cambiar una actividad a "En ejecución" o "Finalizada", guardar, reabrir
   → confirmar persistencia.
6. Repetir con una OT interna y una externa → confirmar que ambas usan
   exactamente la misma sección (ningún texto/comportamiento distinto por
   origen, salvo la visibilidad ya documentada en §2 si se mira una OT
   externa desde el lado cliente).
7. Cambiar a la Organización B (otro owner/admin/manager) y abrir una OT
   que opera Organización B → el checklist de técnicos del formulario **no**
   debe mostrar a Alexis/César (son de Organización A).
8. Iniciar sesión como técnico → confirmar que ve la sección completa pero
   sin botones de agregar/editar/eliminar/reordenar.

## 6. Validaciones ejecutadas

- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; `work_order_activities`, `work_order_activity_technicians`,
  `get_work_order_activities`, `upsert_work_order_activity`,
  `delete_work_order_activity` presentes con sus tipos.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- `npx tsc -p tsconfig.app.json --noEmit`: mismos errores preexistentes ya
  documentados en fases anteriores, ningún error nuevo.

## 7. Pendiente (documentado, no construido en esta fase)

- **Elegir explícitamente un técnico principal** en el formulario: hoy es
  implícito (el primero marcado en el checklist). Si se necesita un
  control dedicado (radio junto a cada checkbox), es un cambio acotado a
  `ActivityEditorDialog.tsx` — el modelo (`is_primary`) ya lo soporta.
- **Sincronización automática de estado** entre actividades y la OT de
  cabecera (ej. marcar la OT `in_progress` cuando la primera actividad
  pasa a `in_progress`, o `completed` cuando todas terminan) no se
  implementó — cada nivel se edita independientemente.
- **Autogestión de estado por el técnico**: un técnico no puede cambiar el
  estado de una actividad propia sin pasar por un planner, igual que la
  cabecera de la OT. Si se habilita, seguir el mismo patrón sugerido en
  `docs/OPERATIONAL_WORK_ORDERS.md` §7 — una RPC angosta
  (`technician_update_activity_status`) que solo permita transiciones
  `assigned → in_progress → completed` y solo si el llamador está entre
  los técnicos vinculados a esa actividad.
- **Reordenar por drag-and-drop** no se implementó — solo botones
  subir/bajar y el campo numérico de secuencia en el formulario.
