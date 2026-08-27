# Indicadores de eficiencia y desviaciones (MVP)

Indicadores operativos de planificado vs. real, calculados en vivo a partir de datos que ya existían en el sistema (`work_orders`, `work_order_activities.estimated_hours`, `work_order_activity_reports.actual_hours`). No se creó ningún sistema de tracking nuevo ni tablas espejo — solo dos RPCs de lectura.

## Fórmulas

Por actividad (`work_order_activities`):

- `planned_hours = work_order_activities.estimated_hours`
- `actual_hours = SUM(work_order_activity_reports.actual_hours)` de todos los reportes de esa actividad (0 si aún no hay reportes)
- `deviation_hours = actual_hours - planned_hours`
- `deviation_percent = ((actual_hours - planned_hours) / planned_hours) * 100`, redondeado a 2 decimales

Ejemplo (dado en la especificación de esta fase): planificadas 2 h, real 3 h → diferencia +1 h, desviación +50 %.

### Regla de división segura

`deviation_percent` **nunca** se calcula si `planned_hours` es `NULL` o `0` — en ese caso el valor es `NULL` (mostrado como "N/D" en la UI), tanto en SQL (`CASE WHEN estimated_hours IS NULL OR estimated_hours = 0 THEN NULL ELSE ROUND(...) END`) como en el cliente (`safeDeviationPercent` en `useEfficiencyMetrics.ts`, y el cálculo local espejo en `WorkOrderActivityReportsSummary.tsx`). Nunca se divide por cero.

## Fuentes de datos

| Campo | Origen |
|---|---|
| `planned_hours` | `work_order_activities.estimated_hours` |
| `actual_hours`, `reports_count`, `first_started_at`, `last_finished_at` | agregación de `work_order_activity_reports` por `activity_id` |
| `work_order_status`, `work_order_number` | `work_orders` |
| `asset_name` | `assets` vía `work_orders.asset_id` |
| `technician_name` | técnico primario de la actividad (`work_order_activity_technicians.is_primary`) o, si no hay, `work_orders.assigned_member_id` |
| `period_date` | `COALESCE(last_finished_at::date, work_orders.due_at::date, work_orders.created_at::date)` |
| Organización operativa | `work_orders.provider_organization_id` |

## RPCs

### `get_efficiency_activity_metrics(p_organization_id, p_start_date, p_end_date)`

Una fila por actividad con planificado, real, diferencia y % desviación. Filtra por `work_orders.provider_organization_id = p_organization_id` y opcionalmente por rango de `period_date`.

### `get_efficiency_summary(p_organization_id, p_start_date, p_end_date)`

Una fila resumen: `completed_work_orders` (status `completed`/`closed`), `pending_work_orders` (el resto), `overdue_work_orders` (no completadas/cerradas con `due_at < now()`), y los totales de horas/desviación. Internamente reutiliza `get_efficiency_activity_metrics` para la porción de horas — no recalcula la misma agregación dos veces.

### Sin `get_efficiency_grouped_metrics`

Se evaluó una tercera RPC para agrupar por OT/técnico/activo/período, pero se decidió **no construirla**: las agrupaciones (por OT, por técnico, por activo) se hacen del lado del cliente (`useEfficiencyMetrics.ts` → `groupBy`), reutilizando las filas ya obtenidas de `get_efficiency_activity_metrics` y la misma regla de división segura. A este volumen de datos, una tercera implementación de la misma fórmula solo agregaría duplicación sin beneficio real. La agrupación por período no se implementó como pestaña separada en el MVP (el filtro de fecha ya acota el período); queda como posible siguiente paso si se pide una vista de tendencia temporal.

## Permisos

- **Pueden ver**: `owner`, `admin`, `manager` de la organización operativa (`provider_organization_id`), y `platform_admin`.
- **No pueden ver**: `technician` (no tiene acceso a analítica global, solo a sus propios reportes vía `TechnicianWorkView`), `viewer`/`requester`, ni ninguna organización distinta a la consultada.
- Ambas RPCs son `SECURITY DEFINER`, verifican `auth.uid()` y el rol vía `has_organization_role(p_organization_id, ARRAY['owner','admin','manager'])` u `is_platform_admin()`, y están `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO authenticated` (no reciben input libre/abusable, por lo que no necesitan ser internas-only).
- En el frontend, el ítem de navegación "Eficiencia" solo aparece para `owner`/`admin`/`manager` de una organización operativa (mismo criterio que "Inventario"); no aparece para `technician` ni para la organización `platform_admin`.

## Limitación de interpretación — sin ranking de técnicos

**Estos indicadores son información operativa, no una evaluación de desempeño individual.** No se compara un técnico contra otro en ningún query, RPC ni componente de UI. La razón: con el volumen y la variedad de actividades actuales, comparar horas planificadas vs. reales entre técnicos sería engañoso — actividades distintas tienen complejidad distinta, y una sola desviación no dice nada sobre calidad de trabajo.

Reglas seguidas en toda la UI:

- Desviación positiva: `+1 h / +50 %`. Desviación negativa: `-0.5 h / -25 %`.
- Nunca se usa lenguaje de juicio ("mejor técnico", "peor técnico", "rendimiento").
- Se usa siempre "desviación vs. plan" o "variación".
- El color de la desviación (`deviationColorClass`) solo indica magnitud (qué tan grande es la variación), nunca "bueno/malo".
- La agrupación "Por técnico" muestra sumas y desviación agregada de ese técnico, sin ordenar ni comparar contra otros técnicos en la misma vista.

## Próximos pasos (fuera de alcance de este MVP)

- Tipos de actividad normalizados (para comparar actividades realmente equivalentes).
- Productividad comparable entre técnicos, una vez haya volumen suficiente y actividades normalizadas.
- Tendencias por período (series de tiempo, no solo un rango fijo).
- Exportación de los indicadores (CSV/Excel).
- Alertas predictivas de desviación.
