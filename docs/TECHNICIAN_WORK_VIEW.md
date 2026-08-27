# "Mis órdenes de trabajo" — vista operativa del técnico

Un técnico necesita ver únicamente su propio trabajo, no la lista completa
de OT de su organización (eso sigue siendo de planner/admin). Esto se
resuelve leyendo `work_orders` + `work_order_activities` +
`work_order_activity_technicians` + `work_order_materials` tal como ya
existen — **no se creó ninguna tabla nueva de "OT del técnico"** — más una
tabla mínima nueva (`work_order_work_logs`) solo para el registro de
trabajo con nota, que tampoco duplica ni reemplaza nada existente.

## 1. Cómo se filtran las OT del técnico

`get_my_technician_work_orders()` — **sin parámetro de organización** — se
resuelve enteramente desde `auth.uid()`:

1. Encuentra todas las membresías activas del usuario con `role =
   'technician'` (puede tener más de una, en distintas organizaciones).
2. Para cada una, incluye una OT cuando:
   - `work_orders.assigned_member_id` = esa membresía (técnico principal), **o**
   - existe una fila en `work_order_activity_technicians` que vincula esa
     membresía a alguna actividad de esa OT.
3. La organización operadora de la OT (`provider_organization_id`) siempre
   debe coincidir con la organización de esa membresía — así que ninguna
   OT de otra organización puede aparecer, y ningún otro técnico de la
   misma organización aparece tampoco (el filtro es por `member_id`
   puntual, no por rol genérico).

No hay ningún parámetro que el frontend pueda manipular para pedir el
trabajo de otro usuario — la única entrada es `auth.uid()`.

**Verificado end-to-end** contra Postgres local (vía `psql`, sin pasar por
el frontend): César (técnico de Organización A) ve exactamente 1 OT
después de que Alexis se la asigna; Bob (técnico de Organización B) ve
`0` filas con la misma llamada. Confirma tanto el filtro por técnico
específico como el aislamiento entre organizaciones.

### Actividades por OT: qué subconjunto se muestra

Si el técnico está vinculado a actividades específicas de esa OT (vía
`work_order_activity_technicians`), se muestran solo esas. Si es el
técnico principal (`assigned_member_id`) y la OT **no tiene ninguna
actividad con técnico asignado** (por ejemplo, una OT simple sin desglose
por actividad), se muestran todas las actividades de la OT — es el único
ejecutor, así que "sus actividades" son todas.

### Activo, ruta y ubicación

`assets` tiene su propia RLS (`is_organization_member`) que **no** cubre
al técnico de una organización proveedora ejecutando una OT externa (el
activo pertenece a la organización cliente). Por eso `asset_name` y
`asset_path` se resuelven **dentro** de la RPC `SECURITY DEFINER`
(bypaseando RLS deliberadamente, pero exponiendo solo nombre y ruta
jerárquica — nunca serie, datos técnicos ni metadata completa, mismo
criterio de no-filtración que `check_request_asset_organization` ya
documentaba). `asset_path` usa un helper interno
`resolve_asset_path(uuid)` — **deliberadamente sin `GRANT EXECUTE` a
`authenticated`**: solo es invocable desde otra función `SECURITY
DEFINER` que ya validó al llamador (un frontend no puede llamarlo
directo para resolver el nombre de un activo arbitrario). `location` usa
`assets.location_text`, o si no está seteado, el nombre de la sede
(`client_branches`) del activo.

### Materiales, solo lectura

`materials`/`work_order_materials` se resuelven igual que
`get_work_order_materials` (mismo cálculo de `warning_status`), pero el
técnico **no puede escribir aquí** — no hay ningún camino de escritura de
materiales expuesto a esta vista; planificar materiales sigue siendo
tarea de owner/admin/manager vía `WorkOrderDetailDialog.tsx`.

## 2. Qué puede accionar el técnico

`technician_update_work_order_progress(p_work_order_id, p_status?,
p_notes?)` es la **única** escritura que un técnico puede hacer sobre una
OT. Antes de nada, revalida que el llamador:

- tenga una membresía `technician` activa en la organización operadora de
  esa OT, **y**
- esté efectivamente asignado a esa OT (principal o por actividad) — las
  mismas dos condiciones que determinan si la OT aparece en "Mis órdenes".

Transiciones de estado permitidas (validadas server-side, no solo en la UI):

| Desde | Hacia | Quién |
|---|---|---|
| `pending` / `assigned` | `in_progress` | Técnico asignado |
| `in_progress` | `completed` | Técnico asignado |
| cualquier estado | `closed` | **Nunca desde esta RPC** — reservado a `update_work_order_operations` (owner/admin/manager/platform_admin) |

Cualquier otro intento de transición (incluido `closed`) es rechazado por
la RPC con un error explícito — **verificado**: César intentando
`p_status => 'closed'` recibe `"Technicians can only move pending/assigned
work orders to in_progress, or in_progress work orders to completed"`.

La RPC nunca toca `planner_member_id`, `assigned_member_id`,
`scheduled_at`, `due_at`, `priority`, ni ninguna fila de
`work_order_materials` — esos campos siguen siendo exclusivos de
`update_work_order_operations` (owner/admin/manager/platform_admin).

### Registrar trabajo: `work_order_work_logs`

`p_status` y `p_notes` son ambos opcionales, pero se exige al menos uno.
Esto cubre las tres acciones de la UI con una sola RPC:

- **Iniciar**: `p_status = 'in_progress'`, sin nota.
- **Finalizar**: `p_status = 'completed'`, sin nota.
- **Registrar trabajo**: nota con o sin cambio de estado adjunto.

Se optó por una tabla real (`work_order_work_logs`: `note`, `status_from`,
`status_to`, `member_id`, `created_at`) en vez de concatenar texto en
`work_orders.observations` — mantiene autoría y fecha estructuradas, y deja
`observations` como el campo de cabecera exclusivo del planner, sin que un
técnico lo pise. **No es un kardex ni una auditoría de cada cambio de
campo** — solo las notas explícitas que un técnico decide dejar.

`get_work_order_work_logs(p_work_order_id)` expone esos registros en modo
lectura a cualquiera que ya pueda ver el detalle operativo de la OT
(planner/admin/técnico de la organización operadora) — sin esto, una nota
de un técnico solo sería visible para él mismo, lo cual vacía de sentido
la función. Integrado en `TechnicianWorkOrderDetailDialog.tsx` ("Registro
de trabajo").

## 3. Qué NO puede hacer el técnico

- Cambiar `planner_member_id`, `assigned_member_id` (a otro técnico),
  `scheduled_at`, `due_at`, `priority`.
- Crear, editar o eliminar actividades (`work_order_activities`) o
  materiales (`work_order_materials`) — solo verlos.
- Cerrar una OT (`closed`).
- Ver el listado general "Órdenes de trabajo" de su organización — ver §5.
- Ver trabajos de otro técnico, ni de otra organización.

## 4. Frontend

- `src/types/technicianWorkOrder.ts`.
- `src/hooks/useTechnicianWorkOrders.ts`: `get_my_technician_work_orders`
  + `updateProgress` (envuelve `technician_update_work_order_progress`).
- `src/components/technician/TechnicianWorkView.tsx`: "Mis órdenes de
  trabajo", cards (no tabla — hay demasiada información anidada por OT
  para una fila plana: actividades + materiales + acciones). Cada card
  muestra correlativo, tipo, activo, ubicación, fechas, prioridad, estado,
  actividades asignadas, materiales, y las 4 acciones.
- `src/components/technician/TechnicianWorkLogDialog.tsx`: formulario
  simple de nota + cambio de estado opcional (solo ofrece la transición
  válida siguiente, si existe).
- `src/components/technician/TechnicianWorkOrderDetailDialog.tsx`: detalle
  de solo lectura, **deliberadamente no una reutilización de
  `WorkOrderDetailDialog.tsx`** — ese componente espera una fila completa
  de `work_orders` y condiciona la edición a que `currentOrganization`
  coincida con la OT, lo cual no es fiable aquí (un técnico puede tener
  trabajo en más de una organización a la vez, mientras el selector de
  organización de la UI solo puede estar en una). Este diálogo solo
  muestra lo que la propia RPC ya trajo, más el registro de trabajo.

## 5. Sidebar / Dashboard

- `Sidebar.tsx`: la visibilidad de "Órdenes de trabajo" ahora excluye
  explícitamente el rol `technician`
  (`canViewWorkOrders = isOperatingOrg && !isTechnicianRole`); un nuevo
  ítem "Mis órdenes" (`canViewMyWorkOrders = isOperatingOrg &&
  isTechnicianRole`) aparece en su lugar. Ningún otro rol
  (owner/admin/manager/viewer/requester/etc.) cambia de comportamiento.
- `Dashboard.tsx`: nueva vista `'my-work-orders'` → `TechnicianWorkView`.
  Además, el propio `case 'work-orders'` redirige a `TechnicianWorkView`
  si el rol activo es `technician` — cierra el hueco de que alguien
  navegue directo a `#work-orders` por URL/hash y termine viendo la lista
  completa sin filtrar, aunque el botón del Sidebar ya no exista para él.

## 6. Cómo probar manualmente

1. Alexis (planner) asigna a César como técnico principal de una OT (o en
   una actividad).
2. Cierra sesión, entra César.
3. Debe ver "Mis órdenes" en el Sidebar (no "Órdenes de trabajo").
4. Debe ver únicamente esa OT — ninguna otra de Alexis ni de otro técnico.
5. Cambiando a Organización B, un técnico de esa organización no debe ver
   la OT de César.
6. La card debe mostrar activo, ubicación, prioridad, estado, actividades
   y materiales.
7. "Iniciar" → la OT pasa a "En ejecución".
8. "Registrar trabajo" → guarda una nota (con o sin cambio de estado).
9. "Finalizar" → la OT pasa a "Finalizada".
10. Cerrar sesión, volver a entrar como César → confirmar que todo
    persiste (estado, notas visibles en "Ver detalle").
11. Como Alexis, abrir esa misma OT → confirmar que las notas de César
    son visibles en su detalle (`get_work_order_work_logs`).

## 7. Validaciones ejecutadas

- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores.
- Smoke test manual completo vía `psql` en el contenedor local
  (bypaseando auth con `request.jwt.claim.sub`): creación de 2
  organizaciones + 3 usuarios (Alexis owner, César técnico Org A, Bob
  técnico Org B), asignación de OT, y las tres transiciones de estado
  exactas del checklist (`in_progress`, nota sin cambio de estado,
  `completed`, intento fallido de `closed`) — todos con el resultado
  esperado, sin ningún error de ambigüedad de columnas.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; `work_order_work_logs` y las 4 RPCs presentes con sus tipos.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- `npx tsc -p tsconfig.app.json --noEmit`: mismos errores preexistentes ya
  documentados en fases anteriores, ningún error nuevo.

## 8. Pendiente (documentado, no construido en esta fase)

- **Registro avanzado de tiempos** (hora de inicio/fin real, duración
  trabajada por actividad) — hoy solo existe el timestamp de cada nota en
  `work_order_work_logs`, sin un cronómetro ni cálculo de horas
  trabajadas.
- **Evidencias / fotos** adjuntas a una actividad o a un registro de
  trabajo — no implementado.
- **Checklist técnico** (pasos obligatorios antes de finalizar) — no
  implementado; "Finalizar" es una transición de estado libre, sin
  validación de completitud de actividades/materiales.
- **Firma / cierre formal** del trabajo (firma digital, conformidad del
  cliente) — no implementado; `closed` sigue siendo exclusivo de
  planner/admin vía `update_work_order_operations`, sin ningún flujo de
  aprobación adicional todavía.
