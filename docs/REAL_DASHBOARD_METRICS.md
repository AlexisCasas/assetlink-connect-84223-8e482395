# Dashboard real de métricas operativas

Reemplaza `StatsCards.tsx` (números hardcodeados: "Total Activos: 147", "+12%", etc. — nunca conectados a una consulta real) por un dashboard conectado a base de datos vía una sola RPC consolidada.

## Métricas incluidas y su fuente real

| Card | Fuente | Criterio |
|---|---|---|
| Activos | `assets` | `organization_id` = la organización; excluye `status = 'archived'` (mismo criterio que `AssetTree` usa para ocultarlos por defecto y que el semáforo operativo ya excluye) |
| Activos críticos | `assets` | igual que arriba + `criticality = 'critical'` |
| Solicitudes abiertas | `requests` | `status IN ('sent', 'quoted')` — ver "Por qué se excluyen los draft" abajo |
| OT abiertas | `work_orders` | `provider_organization_id` = la organización, `status NOT IN ('completed', 'closed')` |
| OT vencidas | `work_orders` | igual que arriba + `due_at IS NOT NULL AND due_at < now()` — mismo criterio que `generate_operational_due_notifications()` ya usa |
| Inspecciones próximas | `inspection_plans` + `inspection_plan_alert_rules` | plan activo con una regla `before_due` **activa** cuya ventana está abierta ahora (`now() >= next_due_at - days_before`) — sin regla configurada, el plan **no cuenta** como próximo (sin ventana inventada) |
| Inspecciones vencidas | `inspection_plans` | plan activo con `next_due_at < now()` — incondicional, no depende de que exista una regla `overdue` configurada |
| Horas planificadas | `get_efficiency_summary(p_organization_id, NULL, NULL)` → `planned_hours_total` | totales de todo el tiempo (sin filtro de fecha en este MVP) |
| Horas reales | `get_efficiency_summary(p_organization_id, NULL, NULL)` → `actual_hours_total` | ídem |

Las horas **reutilizan** `get_efficiency_summary` en vez de recalcular la agregación de `work_order_activities`/`work_order_activity_reports` una segunda vez — mismo patrón de composición ya usado por `get_branch_traffic_light` llamando a `get_asset_traffic_light`.

## Por qué se excluyen los `draft` de "Solicitudes abiertas"

Un borrador (`requests.status = 'draft'`) no es una solicitud enviada — es un concepto ya separado en el resto de la aplicación: `DraftList.tsx` consulta `status = 'draft'` como su propia vista independiente, y la lista "real" de solicitudes en `RequestList.tsx` ya consulta `status = 'sent'` exclusivamente. Contar los drafts como "abiertos" habría inflado la métrica con solicitudes que el usuario ni siquiera envió todavía. `completed` y `anulado` son los dos estados reales de cierre del esquema (`request_status` no tiene un valor literal `cancelled`/`closed`/`rejected` — `anulado` es el equivalente real).

## Idempotencia frente a reglas de alerta simultáneas

Un mismo plan de inspección puede tener varias reglas `before_due` activas al mismo tiempo dentro de su ventana (ej. la regla de 90 días y la de 60 días ambas abiertas cerca del vencimiento). `upcoming_inspections` usa `COUNT(DISTINCT ip.id)` — un plan con múltiples reglas simultáneamente en ventana cuenta **una sola vez**, nunca una vez por regla.

## Permisos

`get_dashboard_metrics` exige `owner`/`admin`/`manager` de la organización, o `platform_admin` — **más estricto** que la mayoría de las otras RPCs de lectura de este proyecto (que permiten a cualquier miembro activo, incluyendo `technician`, ver sus propios datos). El criterio explícito: este es un resumen operativo de **toda la organización** (conteos de abiertos/vencidos, horas agregadas), no el dato de un activo o plan puntual al que un técnico ya tendría acceso por otra vía.

- `owner`/`admin`/`manager`: ven el dashboard real completo.
- `technician`: sigue viendo `TrafficLightSummaryCard` (esa RPC sí permite cualquier miembro activo, fase anterior), pero `DashboardMetricsCards` le muestra "Sin acceso a métricas operativas" en vez de datos globales — el gate del componente coincide exactamente con el de la RPC.
- `platform_admin`: `Dashboard.tsx` ya fuerza esa organización a la vista `admin` (Administración) antes de llegar siquiera a la vista por defecto — este dashboard nunca se renderiza para `platform_admin`, sin necesidad de un caso especial adicional.
- `requester`/`viewer`: caen en el mismo gate que `technician` (no son `owner`/`admin`/`manager`) — mismo mensaje "Sin acceso a métricas operativas".

Verificado con `psql`/`SET ROLE authenticated`: técnico y viewer rechazados; otra organización no puede leer nada; owner de la propia organización ve exactamente sus propios conteos, aislados de cualquier otra organización.

## `StatsCards.tsx` reemplazado, no eliminado

`StatsCards.tsx` seguía siendo importado por `src/pages/Index.tsx` — una página **no registrada en ninguna ruta** (`App.tsx` no la importa; no es alcanzable desde la aplicación) que además ya tenía errores de TypeScript preexistentes sin relación con esta fase. Eliminar `StatsCards.tsx` habría roto ese import sin ningún beneficio real (la página ya es código muerto). En su lugar:

- `Dashboard.tsx` (la app real) ya no importa ni usa `StatsCards` en ningún caso — ni en la vista principal, ni en el fallback de "Activos" para organizaciones no-cliente (que ahora muestra un mensaje neutral en vez de números falsos).
- `StatsCards.tsx` quedó con un comentario de cabecera explícito marcándolo como legacy/mock, deprecado, y advirtiendo no agregar nuevos usos.

## Formato

- Conteos: enteros simples.
- Horas: 2 decimales (`Math.round(x * 100) / 100`, mismo redondeo que el resto de las pantallas de horas — Eficiencia, resumen de reportes de actividad).
- OT vencidas / Inspecciones vencidas: tono de riesgo (`text-destructive`) cuando el conteo es > 0.
- Inspecciones próximas / Activos críticos: tono ámbar (`text-warning`) cuando el conteo es > 0.
- Estados `loading`/`error`/vacío explícitos — nunca un placeholder con datos de ejemplo.

## Pendientes (fuera de alcance de este MVP)

- Tendencia de OT (serie temporal).
- Gráficos de criticidad.
- Cumplimiento de inspecciones (% a tiempo vs. vencidas).
- Eficiencia por período (hoy son totales de todo el tiempo, sin filtro de fecha).
- Filtros de fecha en el propio dashboard.
- Exportación.
- Dashboard ejecutivo dedicado.
