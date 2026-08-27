# Semáforo operativo de activos, áreas y sedes

Un semáforo **no decorativo**: cada color se deriva en vivo de fuentes reales ya existentes en el sistema (órdenes de trabajo, planes/ejecuciones de inspección, respuestas de checklist, `assets.status`). No hay una columna de color manual en ninguna tabla, y no se creó ninguna tabla espejo — todo se calcula en el momento de la consulta mediante dos RPCs de lectura.

## Fuentes reales usadas

### 🔴 Rojo (incumplimiento/falla)

| Fuente | Condición |
|---|---|
| OT vencida | `work_orders.asset_id = activo`, `due_at < now()`, `status NOT IN ('completed','closed')` |
| Inspección vencida | `inspection_plans` con `asset_id` o `area_asset_id` = activo, `is_active`, `next_due_at < now()` — **incondicional**, no depende de que exista una regla de alerta "overdue" configurada (ser vencido es un hecho de cumplimiento, no una notificación) |
| Checklist con no conformidad | La **última ejecución completada** de cada plan que apunta al activo tiene `result = 'failed'` — no "alguna vez falló", sino la más reciente; una ejecución posterior que pasa "resuelve" una falla anterior |
| Estado del activo | `assets.status = 'inactive'` |

### 🟠 Ámbar (advertencia próxima)

| Fuente | Condición |
|---|---|
| OT próxima a vencer | `due_at` dentro de las próximas 24 horas, no completada/cerrada — misma ventana de 24h que ya usa `generate_operational_due_notifications()` |
| Inspección próxima | Solo si el plan tiene una **regla `before_due` activa** cuya ventana está abierta ahora mismo (`now() >= next_due_at - days_before`). **Sin regla configurada, no hay ámbar por esta fuente** — nunca se inventa una ventana por defecto |
| Estado del activo | `assets.status = 'maintenance'` — informativo, nunca escala a rojo |

### 🟢 Verde

Sin razones rojas ni ámbar.

## `assets.status`: valores reales, sin inventar

El esquema no tiene un valor literal `out_of_service` — solo `active | maintenance | inactive | archived` (ver `20260826234732_assets_tenant_aware_foundation.sql`). Se documenta la decisión explícitamente en vez de inventar un valor:

- `inactive` → rojo ("Activo fuera de servicio") — el valor real más cercano al concepto de "fuera de servicio".
- `maintenance` → ámbar ("Activo en mantenimiento") — informativo, no es una falla.
- `archived` → el activo se **excluye por completo** del semáforo (mismo criterio que `AssetTree` ya usa para ocultarlos por defecto — ver `filterArchived` en `useAssets.ts`).
- `active` → sin razón por esta fuente.

## Por qué la criticidad sola nunca es rojo

`assets.criticality` (manual o calculada por la matriz de criticidad) se expone como columna de contexto en cada fila, pero **nunca contribuye por sí sola** a `direct_color`/`rollup_color`. La regla explícita del diseño: la criticidad es una medida de **riesgo** (qué tan grave sería una falla), no de **incumplimiento** (si algo ya está mal). Un activo crítico sin ninguna OT vencida, inspección vencida o no conformidad es verde — su criticidad simplemente se muestra al lado como dato adicional. La regla opcional del enunciado original ("critical + trabajo pendiente próximo → ámbar") se evaluó y se dejó fuera deliberadamente (explícitamente marcada como opcional, "si no complica") para no duplicar la señal que ya dan `work_order_due_soon`/`inspection_due_soon` por sí mismas.

## Roll-up: activo → área → sede

`get_asset_traffic_light` calcula, para cada activo, un **cierre transitivo** (`WITH RECURSIVE`) de ancestro→descendiente sobre `assets.parent_asset_id`. Para cada nodo:

- `direct_color`/`direct_severity`: solo sus propias fuentes.
- `rollup_color`/`rollup_severity`: el máximo entre él mismo y **todos** sus descendientes (rojo=2 > ámbar=1 > verde=0).
- `causing_asset_ids`: los descendientes (nunca el nodo mismo) con color no-verde — permite entrar a un área o sede roja y ver exactamente qué activo(s) la pusieron así.
- `rollup_reasons`: la unión de las razones directas de sí mismo y de cada descendiente no-verde, cada una con su propio `asset_id`/`asset_name` para saber de dónde vino.
- **Si el nodo no tiene hijos, `rollup = direct`** automáticamente (el cierre transitivo de una hoja es solo ella misma).

### Sede (`client_branches`)

Una sede **no es una fila de `assets`** en este esquema — es una tabla aparte, sin relación jerárquica con `parent_asset_id`. `get_branch_traffic_light` no puede apoyarse en el mismo cierre recursivo; en su lugar:

1. Reutiliza `get_asset_traffic_light` (compuesta como subconsulta, no duplicada) para obtener el `rollup_color` ya calculado de cada activo etiquetado con `branch_id = sede`.
2. Agrega el máximo severity entre esos activos.
3. Suma cualquier plan de inspección **puramente a nivel de sede** (`branch_id` con `asset_id` y `area_asset_id` ambos `NULL` — una inspección general del local, no de un equipo específico).

Si una organización etiqueta `branch_id` tanto en un área como en sus equipos hijos, el resultado sigue siendo correcto (la severidad máxima es idempotente ante la redundancia) pero `causing_asset_ids`/`rollup_reasons` pueden listar tanto el área como sus hijos — no es un error, solo redundancia informativa si la organización etiquetó la sede en más de un nivel del mismo árbol.

## Cómo descubrir el activo causante

1. En el árbol de `AssetsView`, cada nodo muestra un punto de color con `rollup_color` (para un padre, refleja el peor descendiente; para una hoja, es su propio color) — el `title`/`aria-label` del punto resume la razón ("Rojo por OT vencida").
2. En `AssetDetail`, la sección "Semáforo operativo" muestra color directo, color heredado (si tiene hijos), razones directas, **activos causantes** (lista clicable — clic selecciona ese activo en el árbol) y razones heredadas con el nombre de qué activo las originó.

## No es historial

El semáforo es **estado calculado en el momento de la consulta**, no un registro de eventos. No se inserta ningún `asset_events` por cambios de color — a diferencia de `criticality_assessed` o `inspection_completed` (que sí son eventos reales que ocurrieron), "el activo se puso rojo" no es un evento discreto, es una condición continua que puede cambiar en cualquier instante según el estado actual de OTs/inspecciones. `AssetDetail` lo deja explícito en la propia UI.

## Autorización

Mismo patrón que el resto del motor operativo (`get_asset_integrated_history`, `get_criticality_matrix`, `get_inspection_plans`): cualquier miembro activo de la organización, o `platform_admin`, puede leer — **incluye a `technician`** (ya puede ver activos e inspecciones; el semáforo no expone ninguna comparación entre técnicos ni analítica agregada por persona). Ninguna de las dos RPCs tiene política de escritura — son 100% de lectura, `SECURITY DEFINER`, sin exponer `service_role` al frontend. Verificado con `psql`/`SET ROLE authenticated`: una organización no puede leer el semáforo de otra.

## No es una tabla espejo

`get_asset_traffic_light`/`get_branch_traffic_light` no escriben nada — cada llamada recalcula el semáforo completo desde `work_orders`, `inspection_plans`, `inspection_runs`, `inspection_run_answers` y `assets` en ese mismo instante. No hay una tabla `asset_traffic_light` con colores guardados que pueda desincronizarse de la realidad.

## Pendientes (fuera de alcance de este MVP)

- Ponderaciones configurables del semáforo (hoy las reglas verde/ámbar/rojo son fijas, no configurables por organización).
- Reglas de color por organización (cada organización podría querer su propia definición de "vencido").
- Severidad diferenciada por tipo de checklist (hoy todo `inspection_failed` es rojo, sin importar el tipo de plantilla).
- Suppress/snooze de una razón puntual.
- SLA por contrato (hoy la ventana de "próximo a vencer" es fija: 24h para OT, la regla de alerta configurada para inspecciones).
- Dashboard ejecutivo dedicado (hoy solo un resumen simple de conteos en el Dashboard).
- Histórico de cambios de semáforo (cuándo pasó de verde a rojo, por ejemplo) — hoy es solo el estado actual.
- Materialización/cron si el volumen de activos crece lo suficiente como para que el cálculo en vivo sea costoso (hoy no hace falta a esta escala).
