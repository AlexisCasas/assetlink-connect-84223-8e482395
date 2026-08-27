# Historial integral del activo

"¿Qué le ha pasado a este activo?" — una sola línea de tiempo, dentro del
propio detalle del activo, consolidada **en el momento de la lectura**
desde las tablas fuente reales. No se creó ningún módulo paralelo ni
ninguna tabla espejo: `get_asset_integrated_history` es la única pieza
nueva de backend, y `AssetHistory.tsx` se integra directo en
`AssetDetail.tsx` (pestaña "Historial", junto a "Resumen").

## 1. Fuentes consolidadas — qué se duplica y qué no

| Fuente | Tipo de item | ¿Se duplicó algo? |
|---|---|---|
| `assets` (la fila del activo) | `asset_created` | **Solo como respaldo.** Se omite por completo si ya existe una fila `asset_events` con `event_type = 'created'` para ese activo (el caso normal — `useAssets.ts` ya registra ese evento en cada creación desde una fase anterior). Sin este `NOT EXISTS`, se vería la creación duplicada. |
| `assets.updated_at` | — | **Deliberadamente no usado.** `asset_events` ya registra `'updated'`/`'archived'`/`'restored'` en cada mutación real (`useAssets.ts`); agregar un item derivado de `updated_at` habría sido exactamente la duplicación que pidió evitar la tarea. |
| `asset_events` | `asset_event` | Fuente única para create/update/archive/restore y cualquier evento manual futuro — **no se tocó el esquema** de esta tabla (ya tenía `event_type`/`description`/`payload`, usado aquí como `metadata`). |
| `requests` (`asset_id`) | `request_created` | Directo desde la tabla, sin copia. |
| `work_orders` (`asset_id`) | `work_order_created` | Un solo item por OT (su creación) — no existe una tabla de historial de transiciones de estado, así que no hay un `work_order_status` separado que emitir; el estado actual ya viaja en el propio item. |
| `work_order_activities` | `activity_created` | Un solo item por actividad, mismo motivo — no hay `completed_at` en esta tabla, y su `status`/`updated_at` no marcan de forma confiable un momento único de finalización. `technician_report` (abajo) sí tiene ese dato real. |
| `work_order_activity_reports` | `technician_report` | La intervención real: `started_at`, `finished_at`, `actual_hours`, `observations`, `final_status`, todo en `metadata` además de en las columnas top-level. |
| `work_order_activity_report_materials` | `material_used` | Solo lo que se usó (código, nombre, cantidad, unidad) — nunca stock en vivo ni almacén del proveedor. |
| `work_order_activity_report_evidences` | `evidence_added` | Metadata tal cual existe hoy (nombre, link opcional) — sin upload real todavía, ver `docs/TECHNICIAN_ACTIVITY_REPORTS.md`. |
| *(futuro)* Inspecciones | `inspection_created` | **No implementado.** El tipo queda reservado en el vocabulario (`AssetHistoryEventType`) para cuando exista una tabla de inspecciones real — no se inventó ninguna tabla para esta fase. |

Regla general: cada fila de la línea de tiempo es una **lectura directa**
de su tabla origen (`source_table`/`source_id` en cada item apuntan
exactamente a esa fila) — nunca una copia persistida. Si mañana cambia un
`observations` de un reporte, el historial lo refleja en la siguiente
consulta sin ninguna migración de datos.

## 2. RPC: `get_asset_integrated_history(p_asset_id)`

`SECURITY DEFINER`, con alias corto en cada tabla desde la primera línea
(`a`, `ae`, `r`, `wo`, `woa`, `woar`, `woarm`, `woare`, `om`, `au`, `m`) y
cada rama del `UNION ALL` con **alias explícito por columna** (`AS id`,
`AS event_date`, etc.) — no solo por prudencia con el bug 42702 ya
conocido (`20260827170000_fix_work_order_activities_rpc_ambiguity.sql`),
sino porque sin esos alias el `ORDER BY event_date DESC` final ni siquiera
resolvería: en un `UNION ALL`, el nombre de cada columna de salida lo
determina la **primera** rama a nivel SQL, antes de que PL/pgSQL asigne
posicionalmente el resultado a los parámetros de `RETURNS TABLE`.

Devuelve una fila por item con: `id` (texto sintético, no un uuid — cada
tipo de item prefija su propio id real, ej. `report-<uuid>`),
`event_type`, `event_label`, `event_date`, `actor_name`/`actor_email`,
`source_table`/`source_id` (referencia real a la fila origen),
`title`, `description`, `status`, `metadata` (jsonb con lo específico de
cada tipo — ej. `actual_hours`/`estimated_hours` en `technician_report`).

## 3. Reglas de visibilidad

Dos niveles, evaluados dentro de la misma función (no depende de RLS
directa sobre 5+ tablas distintas, `SECURITY DEFINER` reimplementa la
regla):

1. **Puerta de entrada**: el llamador debe ser miembro activo de la
   organización dueña del activo (`assets.organization_id`), o
   `platform_admin`, o haber operado al menos una OT vinculada a ese
   activo (miembro de `work_orders.provider_organization_id` de alguna de
   ellas). Cualquier otra organización recibe una excepción explícita
   ("Not authorized to view this asset history") — **verificado**: un
   owner de una Organización B sin relación con el activo es rechazado.
2. **Filtrado por item**, dentro de la misma consulta:
   - `asset_created`/`asset_event`/`request_created`: solo dueño del
     activo o `platform_admin`. Un proveedor que ejecutó una OT sobre el
     activo **no** ve la solicitud original ni los eventos manuales del
     activo — no los necesita para responder "qué intervención hice".
   - `work_order_created`/`activity_created`/`technician_report`/
     `material_used`/`evidence_added`: visibles para el dueño del activo
     **siempre** (incluida una OT ejecutada por un proveedor externo —
     el cliente dueño del activo tiene interés legítimo en saber qué se
     hizo, sin importar quién lo hizo) y para la organización que operó
     *esa* OT específica (nunca la de otra OT ajena sobre el mismo
     activo).

Esto es una regla **más permisiva hacia el dueño del activo** que la ya
establecida para `work_order_activities`/`work_order_materials`/
`work_order_work_logs` en fases anteriores (donde el cliente de una OT
externa no veía el detalle operativo, solo el proveedor) — decisión
explícita de esta fase, documentada aquí y acotada **solo** a esta RPC de
historial; no cambia ninguna policy ni RPC existente.

**Verificado end-to-end** (vía `psql`, sin frontend): con una OT interna
completa (solicitud → OT → actividad → reporte con material y evidencia),
el owner del activo ve las 7 filas esperadas en orden cronológico
correcto, el técnico de la misma organización también las ve todas, y un
owner de una organización sin relación es rechazado con excepción — y
solo aparece **una** fila "Activo creado" (no dos), confirmando que el
respaldo de `assets` no duplicó el evento ya existente en `asset_events`.

## 4. Frontend

- `src/types/assetHistory.ts`: `AssetHistoryEventType`,
  `AssetHistoryGroup` (agrupación visual — varios `event_type` comparten
  grupo, ej. `asset_created`/`asset_event` → "Evento del activo"),
  `AssetHistoryItem`.
- `src/hooks/useAssetHistory.ts`: carga vía la RPC, expone
  `items`/`loading`/`error`/`refresh`. Puramente de lectura — no hay
  ninguna escritura en este hook, el historial se ensambla en el momento
  de cada consulta.
- `src/components/assets/AssetHistory.tsx`: **una sola línea de tiempo
  cronológica** (nunca separada en secciones por tipo — eso rompería el
  orden cronológico que pide la tarea), donde cada item lleva un badge/
  ícono de color según su grupo para que el tipo siga siendo fácil de
  distinguir de un vistazo. Estado vacío: "Este activo aún no tiene
  historial operativo."
- Integrado en `AssetDetail.tsx`: la vista de solo-lectura del activo
  ahora usa `Tabs` ("Resumen" / "Historial"), mismo patrón visual que ya
  usaba el modo edición (`General`/`Técnica`/`Ubicación`). El botón
  "Historial" que existía **deshabilitado** en la barra de acciones se
  eliminó — quedaría redundante con la pestaña real.

## 5. Cómo probar manualmente

1. Abrir un activo → confirmar la pestaña "Historial" junto a "Resumen".
2. Crear una solicitud asociada al activo, generar su OT, crear una
   actividad y asignar un técnico.
3. El técnico reporta la actividad: inicio/fin, observación, material
   usado, evidencia (nombre + link opcional).
4. Volver al activo, pestaña "Historial" → confirmar que aparecen: creación
   del activo, la solicitud, la OT, la actividad, la intervención del
   técnico, el material usado y la evidencia — en orden cronológico
   descendente.
5. Cambiar a una organización sin relación con el activo → confirmar que
   no ve nada (ni el activo, ni su historial).
6. Confirmar que no se duplicó nada en `asset_events` — sigue teniendo
   solo sus propias filas (`created`/`updated`/`archived`/`restored`),
   ninguna copia de solicitudes, OT, actividades, reportes, materiales ni
   evidencias.

## 6. Validaciones ejecutadas

- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores.
- Smoke test manual completo vía `psql` (bypaseando auth con
  `request.jwt.claim.sub`): escenario completo solicitud → OT → actividad
  → reporte con material y evidencia, verificando las 7 filas esperadas,
  el orden cronológico, el rechazo de una organización sin relación, y la
  ausencia de duplicado en "Activo creado".
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; `get_asset_integrated_history` presente con su tipo.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- `npx tsc -p tsconfig.app.json --noEmit`: mismos errores preexistentes ya
  documentados en fases anteriores, ningún error nuevo.

## 7. Pendiente (documentado, no construido en esta fase)

- **Inspecciones**: `inspection_created` queda reservado en el vocabulario
  de tipos, sin tabla ni fuente real todavía.
- **Checklist técnico** por actividad/inspección — no implementado.
- **Mantenimientos preventivos** (planificación recurrente, no solo
  correctivo bajo demanda) — no implementado.
- **Métricas predictivas** (MTBF, tendencias de fallas, etc.) sobre el
  historial consolidado — no implementado; el historial hoy es puramente
  descriptivo, no analítico.
- **Evidencia con upload real** — mismo pendiente ya documentado en
  `docs/TECHNICIAN_ACTIVITY_REPORTS.md`; cuando exista, este historial la
  mostrará sin cambios (ya lee `file_url`/`file_name` de la fuente real).
