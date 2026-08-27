# Reporte operativo del técnico por actividad

El técnico registra ejecución **real** por actividad — inicio, fin, horas
reales, observaciones, material utilizado, evidencias y estado final — para
poder comparar planificación (`work_order_activities.estimated_hours`)
contra ejecución real. **No reemplaza `work_order_activities`, la
extiende**: el reporte cuelga de una actividad existente, nunca se creó un
módulo paralelo de OT ni de actividades.

## 1. Modelo

```
work_order_activities (1) ──< work_order_activity_reports (N) ──< work_order_activity_report_materials (N)
                                                                └─< work_order_activity_report_evidences (N)
```

**Múltiples reportes por actividad, a propósito.** No hay ninguna
restricción `UNIQUE` que limite una actividad a un solo reporte —
`submit_activity_report` siempre hace `INSERT`, nunca `UPDATE`. Si un
técnico trabaja la misma actividad en dos tramos (ej. dos turnos, o
retoma un trabajo bloqueado), cada tramo es un reporte independiente con
su propio `started_at`/`finished_at`/`actual_hours`. El total real de una
actividad es la **suma** de `actual_hours` de todos sus reportes — así lo
calcula `get_my_technician_work_orders` (`actual_hours_total`) y así lo
presenta la UI, nunca reemplazando un reporte anterior.

### `actual_hours`: por trigger, no por columna `GENERATED`

El primer intento fue `actual_hours numeric GENERATED ALWAYS AS
(EXTRACT(EPOCH FROM (finished_at - started_at))/3600) STORED` — Postgres
lo rechaza: la resta de dos `timestamptz` está catalogada como `STABLE`,
no `IMMUTABLE`, y `GENERATED ALWAYS AS` exige inmutabilidad. Se resolvió
con un trigger `BEFORE INSERT OR UPDATE`
(`compute_work_order_activity_report_hours`) que siempre recalcula
`actual_hours` a partir de `started_at`/`finished_at`, sobrescribiendo
cualquier valor recibido — no puede desincronizarse.

### No cronómetro obligatorio

El formulario exige **Desde/Hasta manuales** (`datetime-local`). Existe un
botón "usar hora actual" junto a cada campo como atajo — nunca un
cronómetro con estado propio, y nunca un campo obligatorio distinto de
Desde/Hasta.

### Reglas de asignación y consistencia (trigger, no solo RPC)

`check_work_order_activity_report_consistency` (mismo patrón que las
fases anteriores) valida en cada `INSERT`/`UPDATE`, independientemente de
quién escriba:

- `activity_id` pertenece a `work_order_id`.
- `organization_id` es la organización operadora tanto de la OT como de
  la actividad.
- `member_id` es un técnico activo de esa organización.
- `member_id` está asignado a la actividad
  (`work_order_activity_technicians`) **o** es el técnico principal de la
  OT (`work_orders.assigned_member_id`) — la misma regla de "asignado" ya
  usada por `technician_update_work_order_progress`.

### Materiales del reporte: sin descuento de stock

`work_order_activity_report_materials` registra qué material y cuánto se
usó **para el reporte**, con un trigger que valida que el material
pertenezca a la organización operadora y que, si se referencia una línea
de `work_order_materials` (planificación de la OT), pertenezca a la misma
OT. **Nunca se resta de `materials.stock`** — ni aquí ni en ningún otro
punto del sistema; sigue sin existir descuento automático, kardex ni
costeo, exactamente como en `docs/MINIMAL_INVENTORY_MATERIALS.md`.

### Evidencias: metadata en esta fase, no upload real

`work_order_activity_report_evidences` tiene `file_path`/`mime_type`/
`size_bytes` — el esquema queda **listo** para archivos reales — pero
esta fase no integra Supabase Storage: el formulario solo captura
`file_name` y opcionalmente un `file_url` pegado a mano (un link externo,
no un archivo subido). Decisión explícita, autorizada por el propio
alcance de la tarea; ver §5 (Pendiente).

## 2. RPCs

Las tres, `SECURITY DEFINER`, con el mismo cuidado de alias por columna
(`wo`, `woa`, `woat`, `wom`, `m`, `r`, `rm`, `ev`, `om`, `au`) desde la
primera línea que dejó establecida la corrección de ambigüedad
(`20260827170000_fix_work_order_activities_rpc_ambiguity.sql`).

- **`get_activity_report_form_data(p_activity_id)`**: todo lo que el
  formulario necesita en una llamada — la actividad, su OT, sus técnicos
  asignados, los materiales disponibles de la OT (para elegir "material
  utilizado"), y los reportes previos **del propio llamador** para esa
  actividad. Autorización: técnico asignado a la actividad o a la OT, o
  planner/admin/manager/platform_admin.
- **`submit_activity_report(...)`**: único camino de escritura para las
  tres tablas. Revalida que el llamador sea técnico activo asignado
  (misma regla que el trigger, por defensa en profundidad). Actualiza
  `work_order_activities.status` según `final_status`:
  - `completed` → actividad `completed`.
  - `in_progress` **o** `blocked` → actividad `in_progress` (`blocked` no
    se agregó al `CHECK` de `work_order_activities.status` — mapeo
    deliberado, ver §4).
  - `pending` → no toca el estado de la actividad (reporte de solo
    registro, sin afirmar avance).
  - Nunca cierra la OT completa, nunca descuenta stock.
- **`get_activity_reports_for_work_order(p_work_order_id)`**: todos los
  reportes de una OT con `hours_difference` (real − estimado) ya
  calculada server-side. Planner/admin/manager/platform_admin ven todos;
  un técnico ve **solo los suyos** — la misma regla que las policies
  `SELECT` de las tres tablas, reimplementada aquí porque `SECURITY
  DEFINER` evita RLS.
- **`get_my_technician_work_orders()` extendida**: esta función ya
  existía (`docs/TECHNICIAN_WORK_VIEW.md`, migración ya mergeada) — no se
  editó ese archivo. Esta fase agrega un `CREATE OR REPLACE FUNCTION` con
  la misma firma y lista de columnas de salida (no hace falta `DROP
  FUNCTION`, a diferencia de un rename de parámetros) que agrega
  `actual_hours_total` y `reports_count` dentro del jsonb de cada
  actividad, así "Mis órdenes" muestra horas reales sin una llamada
  extra por actividad.

### Verificado end-to-end (sin frontend, vía `psql`)

Escenario exacto del enunciado: actividad "Cambiar rodamiento" estimada en
2h, César la reporta de 08:00 a 11:00 con material ROD-001 cantidad 1 y
`final_status = completed`. Resultado: `actual_hours = 3.00`,
`hours_difference = +1.00`, `work_order_activities.status = completed`,
`materials.stock` sin cambios (10.00 antes y después), y tanto César como
el planner Alexis pueden leer el reporte vía
`get_activity_reports_for_work_order` (Alexis ve todos los reportes de la
OT; un segundo técnico de otra organización no vería nada).

## 3. Frontend

- `src/types/activityReport.ts`.
- `src/hooks/useActivityReports.ts`: `loadFormData`, `submitReport`,
  `loadReportsForWorkOrder` — un solo hook para las tres RPCs, como pidió
  la tarea.
- `src/components/technician/ActivityReportDialog.tsx`: formulario
  Desde/Hasta (con botón "usar hora actual" opcional), horas reales
  calculadas en vivo, observaciones, estado final, checklist de
  materiales disponibles de la OT con cantidad usada, evidencias
  (nombre + link opcional, repetible), y la lista de reportes previos del
  propio técnico para esa actividad.
- Integrado en `TechnicianWorkView.tsx` (botón "Reportar" por actividad,
  mostrando estimado/real/diferencia inline en la card) y en
  `TechnicianWorkOrderDetailDialog.tsx` (mismo botón en el detalle).
- `src/components/work-orders/WorkOrderActivityReportsSummary.tsx`:
  resumen de solo lectura "Planificación vs ejecución real" integrado en
  `WorkOrderDetailDialog.tsx` (visible bajo la misma condición que
  Actividades/Materiales, `canViewOperatingDetails`) — estimado, real y
  diferencia por reporte, más el total estimado vs. total real de toda la
  OT. Reutiliza `get_activity_reports_for_work_order`, sin ningún
  endpoint nuevo solo para el planner.

## 4. Estados

`final_status` del reporte: `pending`, `in_progress`, `completed`,
`blocked`. El `CHECK` de `work_order_activities.status` **no se tocó**
(sigue siendo `pending, assigned, in_progress, completed` — sin
`closed` para actividades, y ahora sin `blocked` tampoco): un reporte
`blocked` mapea la actividad a `in_progress`, no a un estado nuevo. Es una
decisión deliberada, ofrecida como la opción "segura" por la propia
tarea, para no tener que auditar cada lugar del código que ya asume esos
4 valores de estado de actividad.

## 5. Permisos

| Quién | Ve el formulario de reporte | Puede reportar | Ve reportes de la OT |
|---|---|---|---|
| Técnico asignado a la actividad o a la OT | Sí | Sí, solo esa actividad | Solo los suyos |
| Técnico de la misma organización, no asignado a esa actividad | No | No | Solo los suyos (ninguno, si no reportó nada) |
| owner/admin/manager de la organización operadora | Sí | No (no es técnico) | Todos |
| `platform_admin` | Sí | No (no es técnico) | Todos |

## 6. Cómo probar manualmente

1. Planner Alexis crea/abre una OT y una actividad "Cambiar rodamiento"
   con 2h estimadas, asignada a César. La OT tiene material ROD-001
   planificado 5.
2. César entra, va a "Mis órdenes", abre la OT, clic "Reportar" en esa
   actividad.
3. Registra Desde 08:00, Hasta 11:00, observación "Se encontró desgaste
   adicional.", material ROD-001 cantidad 1, estado final "Finalizada".
4. Guardar → confirmar horas estimadas 2, horas reales 3, diferencia +1,
   material y observación guardados, actividad en estado Finalizada.
5. Cerrar sesión y volver a entrar como César → confirmar persistencia.
6. Entrar como Alexis → confirmar que ve la planificación vs. ejecución
   real de esa actividad en el detalle de la OT.

## 7. Validaciones ejecutadas

- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores.
- Smoke test manual completo vía `psql` (bypaseando auth con
  `request.jwt.claim.sub`): el escenario exacto del checklist (2h
  estimado, 08:00–11:00 real, material, observación) + verificación de
  que `materials.stock` no cambia + verificación de que
  `get_activity_reports_for_work_order` respeta la visibilidad
  planner-ve-todo / técnico-ve-lo-suyo.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; las 3 tablas y las 3 RPCs (más `get_my_technician_work_orders`
  extendida) presentes con sus tipos.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- `npx tsc -p tsconfig.app.json --noEmit`: mismos errores preexistentes ya
  documentados en fases anteriores, ningún error nuevo.

## 8. Pendiente (documentado, no construido en esta fase)

- **Upload real de archivos** para evidencias — el esquema
  (`file_path`/`mime_type`/`size_bytes`) ya está listo; falta el bucket de
  Supabase Storage + RLS (mismo patrón que
  `request-detail-attachments`, ver `20260721171427_request_attachments_storage_rls.sql`)
  y la UI de carga. Por ahora solo nombre + link opcional.
- **Cronómetro real** (iniciar/pausar/detener con estado persistente) —
  el botón "usar hora actual" es solo un atajo de conveniencia sobre el
  formulario manual, no un cronómetro.
- **Cierre automático de la OT** cuando todas sus actividades están
  `completed` — deliberadamente no implementado; `closed` sigue siendo
  una decisión manual de planner/admin vía `update_work_order_operations`.
- **Consolidado avanzado de productividad** (horas reales por técnico en
  un rango de fechas, comparativas entre técnicos, etc.) — hoy solo existe
  el resumen por OT individual en `WorkOrderActivityReportsSummary.tsx`.
