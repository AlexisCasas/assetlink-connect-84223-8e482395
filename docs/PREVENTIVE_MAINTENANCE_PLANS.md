# Mantenimiento preventivo

## Alcance

El módulo implementa el ciclo completo `ficha → plan → ocurrencia → solicitud → OT → siguiente ocurrencia` para organizaciones `client_company`. No crea un segundo flujo de solicitudes: `PreventiveRequestDialog` monta `OrderForm` y persiste mediante `persistRequest`, igual que el módulo principal.

La migración fuente es `supabase/migrations/20260918051511_preventive_maintenance_plans.sql`. Todas las escrituras de las siete tablas nuevas pasan por RPCs `SECURITY DEFINER` o triggers internos; el rol `authenticated` solo recibe `SELECT` sujeto a RLS.

## Modelo

- `maintenance_cards`, `maintenance_card_tasks`, `maintenance_card_materials`: alcance reutilizable. Los materiales son una previsión y muestran stock en vivo; no reservan ni descuentan inventario.
- `asset_meters`, `asset_meter_readings`: medidores acumulativos. Las lecturas efectivas son monotónicas. Una corrección anula la original y crea otra con `supersedes_reading_id`; un reset físico requiere retirar/reemplazar el medidor.
- `preventive_maintenance_plans`: configuración recurrente por calendario o medidor. Activo, ficha, disparador y medidor son identidad inmutable.
- `preventive_maintenance_occurrences`: ciclo concreto con vencimiento y `scope_snapshot` inmutables. Solo existe una ocurrencia `open/planned` por plan.

El snapshot conserva el activo/ruta/sede, la ficha, tareas, materiales y configuración relevante tal como existían al crear el ciclo. Los nombres y el stock actuales de materiales se consultan aparte; nunca se reescribe el snapshot.

## Reglas de cadencia

| Resultado del ciclo | Calendario | Medidor |
|---|---|---|
| Completado | `work_orders.completed_at + periodo` | lectura efectiva de cierre `+ interval_value` |
| Omitido | `occurrence.due_at + periodo` | `occurrence.due_meter_value + interval_value` |
| Reactivado sin ciclo vigente | `now() + periodo` | última lectura efectiva `+ interval_value` |

Editar un plan nunca mueve la ocurrencia vigente. Desactivarlo cancela una ocurrencia abierta, pero deja terminar una ya planificada; como el plan queda inactivo, ese cierre no crea el siguiente ciclo. Reactivar reutiliza una planificada existente y nunca revive una cancelada.

Los estados de oportunidad son calculados en `get_preventive_maintenance_plans`:

- calendario: `upcoming`, `due`, `overdue` usando `planning_lead_days`;
- medidor: `upcoming`, `due`, `overdue` usando lectura efectiva y `meter_lead_value`;
- si no hay lectura efectiva: `no_reading` (la UI muestra “Sin lectura de medidor”).

## Atomicidad e idempotencia

Cada frontera crítica es una sola transacción de PostgreSQL:

1. `save_preventive_maintenance_plan` inserta plan y ocurrencia #1; si el snapshot o la ocurrencia fallan, el plan también revierte.
2. `plan_preventive_maintenance_occurrence` bloquea primero el plan y luego la ocurrencia, valida tenant/activo/servicio/estado e impone `requests.id = request_creation_id`. Repetir el mismo vínculo es no-op exitoso.
3. El trigger `sync_preventive_occurrence_from_work_order` adjunta la OT al insertar y, en la primera transición a `completed/closed`, completa el ciclo, registra evento/notifica y crea exactamente el siguiente. Todo revierte con la transición de OT si algo falla.
4. Una OT preventiva por medidor solo cierra si existe una lectura efectiva del mismo medidor registrada en la ventana `occurrence.planned_at <= recorded_at <= work_orders.completed_at`. El trigger selecciona la más reciente de esa ventana; una lectura anulada o futura no sirve. Si no existe, aborta toda la transición indicando el nombre del medidor que debe actualizarse.
5. `skip_preventive_maintenance_occurrence` acepta solo ciclos abiertos, exige motivo y es idempotente.

La disciplina de locks es plan → ocurrencia. Los índices parciales únicos refuerzan un solo ciclo vigente, una sola solicitud/OT por ocurrencia y una sola OT interna por solicitud. La suite usa dos conexiones `dblink` simultáneas para verificar doble planificación y doble transición terminal.

## RPCs públicas

- Fichas: `get_maintenance_cards`, `save_maintenance_card`, `set_maintenance_card_active`.
- Medidores: `get_asset_meters`, `create_asset_meter`, `record_asset_meter_reading`, `correct_asset_meter_reading`, `retire_asset_meter`, `replace_asset_meter`.
- Planes/ciclos: `get_preventive_maintenance_plans`, `get_preventive_maintenance_occurrences`, `save_preventive_maintenance_plan`, `set_preventive_maintenance_plan_active`, `plan_preventive_maintenance_occurrence`, `skip_preventive_maintenance_occurrence`.

Helpers, builders de snapshot y triggers no tienen `EXECUTE` para `authenticated`.

## Permisos

| Rol | Lectura | Registrar lectura | Administrar fichas/planes/medidores | Planificar/omitir |
|---|---:|---:|---:|---:|
| owner/admin/manager | Sí | Sí | Sí | Sí |
| technician | Sí | Sí | No | No |
| requester/viewer | Sí | No | No | No |
| platform_admin | Sí | Sí | Sí | Sí |

El backend vuelve a validar cada regla; ocultar controles en frontend no es autorización. El proveedor accede al trabajo mediante los permisos existentes de solicitud/OT, no mediante lectura directa de planes del cliente.

## Eventos, notificaciones y navegación

Las acciones generan una sola fila `asset_events`: `preventive_plan_created`, `meter_reading_recorded`, `preventive_maintenance_planned`, `preventive_maintenance_completed` o `preventive_maintenance_skipped`. `get_asset_integrated_history` conserva su UNION histórica y solo decora la rama genérica de `asset_events`, por lo que no duplica filas.

Planificado/completado/omitido notifican al responsable y a owner/admin/manager mediante deduplicación existente. El `entity_type` es `preventive_maintenance_occurrence`; el enlace canónico es `#preventive-maintenance?plan=<uuid>&occurrence=<uuid>`.

## UI

La vista `preventive-maintenance` contiene:

- Planes: alta/edición, activación, estado de oportunidad y próximo ciclo.
- Fichas: cabecera, tareas y materiales vinculados o libres.
- Historial de ciclos: planificar u omitir ciclos abiertos.
- Medidores: alta, retiro, lecturas y correcciones auditadas.

`AssetDetail` muestra un resumen por activo y Dashboard muestra conteos activos/próximos/vencidos/sin lectura.

Al registrar, corregir, retirar o reemplazar una lectura, los hooks de medidores y mantenimiento preventivo publican una invalidación local por organización/activo. Las vistas de Planes, Próximos/Pendientes, Dashboard y AssetDetail vuelven a pedir sus RPCs al servidor sin recalcular `timing_status` en el cliente ni vaciar los datos visibles durante el refetch.

## Pruebas y verificación

```text
supabase db reset --local
supabase test db --local
npm run build
npm run lint
```

Las pruebas están en:

- `supabase/tests/preventive_maintenance_plans.test.sql` (90 aserciones funcionales/RLS/invariantes);
- `supabase/tests/preventive_maintenance_concurrency.test.sql` (9 aserciones con conexiones concurrentes).
- `supabase/tests/preventive_maintenance_qa.test.sql` (81 aserciones de gates QA, incluido QA-12 aislado para la ventana de lectura de cierre).

## Despliegue y rollback

Antes de desplegar, tomar backup, ejecutar la migración en staging, regenerar tipos y correr la suite. La migración agrega un índice único parcial sobre OT internas; si existieran duplicados históricos por `request_id`, el despliegue debe detenerse y depurarlos antes de reintentar.

Rollback recomendado antes de uso productivo: retirar la UI, restaurar `get_asset_integrated_history_before_preventive` a su nombre original, eliminar triggers/funciones/policies/índices y luego las tablas en orden inverso (ocurrencias → planes → lecturas → medidores → materiales/tareas → fichas).

Con datos productivos no se recomienda un `DROP`: desactivar la UI y los planes, conservar tablas/eventos para auditoría y desplegar una migración correctiva. Un rollback destructivo perdería snapshots, trazabilidad de correcciones y vínculos solicitud/OT; requiere backup verificado y aprobación operativa explícita.

## Limitaciones y pendientes

- La planificación es deliberadamente manual/event-driven; esta entrega no incorpora cron, scheduler ni generación masiva automática.
- Los materiales del snapshot son informativos: no reservan ni descuentan inventario.
- La orden externa se registra mediante referencia, proveedor y enlace; su ciclo de vida fuera de OneFacility no se sincroniza automáticamente.
- Antes del despliegue conviene ejecutar las pruebas manuales con usuarios reales de cada rol y confirmar los enlaces profundos desde el centro de notificaciones.
- El `tsc` global del repositorio conserva 6 errores anteriores a este módulo en `AdminConsole`, `BranchesList`, `QuoteListDialog` e `Index`; los archivos nuevos del preventivo no agregan errores TypeScript.
