# One Facility · 9C.6-B2.1 — Planificación delegada de OT internas

**Estado:** migración **instalada en Supabase Cloud**, QA aislado PASS y PR #82 listo para integración; frontend de edición C2.1 **no implementado ni habilitado**.
**Fecha:** 10/11/2026.
**Base:** `productization/mvp` desde el merge de 9C.6-C1, commit `3b2a027`.

## Hito anterior

**9C.6-C1: cierre funcional confirmado por el usuario el 10/11/2026 en Production.** Se verificaron: entrada desde Clientes administrados, 23 OT de Makro Test (15 externas y 8 internas), filtro Cerradas (5), detalle interno/externo y ausencia de botones de modificación. El frontend está en Production con commit `3b2a027`. Este hito no altera ni sustituye las reglas de ejecución del operador.

## Alcance B2.1 (decisión D2 aprobada)

Se crea una sola función SQL nueva:

`update_facility_management_internal_work_order_schedule(client_org, work_order, expected_priority, expected_scheduled_at, expected_due_at, priority, scheduled_at, due_at)`.

Ajusta exclusivamente `priority`, `scheduled_at`, `due_at`, y **solo** para órdenes `internal`, de ese cliente/operadora, cuya solicitud de origen pertenece al mismo cliente y no es borrador/anulada, y estado `pending`, `assigned` o `in_progress`.

Se exige en la **misma relación activa**:
- `requests.view`;
- `work_orders.view`;
- `work_orders.manage`;
- usuario FM asignado, membresía activa y rol `owner`, `admin` o `manager`.

La sesión debe estar autenticada; jamás se actúa como proveedor ni como miembro ficticio del cliente.

No se permite modificar `status`, `planner_member_id`, `assigned_member_id`, `observations`, actividades, materiales, importes, cierres ni OT externas.

## Concurrencia, validación y auditoría

- La RPC primero comprueba autorización; luego bloquea la OT con `SELECT ... FOR UPDATE` y comprueba de nuevo la concesión.
- El cliente debe transmitir los tres valores previos; si alguno difiere se devuelve SQLSTATE `40001` y no se actualiza la OT. Esto evita sobrescribir cambios concurrentes en esos campos incluso cuando `updated_at` usa `now()`.
- Prioridad permitida: `low/medium/high/urgent`; fecha programada no posterior a fecha límite cuando ambas existen.
- Una actualización sin cambios es idempotente, no dispara UPDATE ni produce auditoría.
- Una actualización real deja un evento en `audit_logs` con usuario actor, organización cliente y solo los tres campos autorizados (valores anterior/nuevo).
- La respuesta usa el DTO sanitizado de B1: `get_facility_management_work_order`, sin materializar datos internos.
- `SECURITY DEFINER`, `search_path` vacío y `EXECUTE` exclusivamente a `authenticated`; no se modifican políticas RLS, grants de tablas ni funciones del operador.

## Pruebas y puertas

Archivo dedicado: `supabase/tests/facility_manager_work_orders_manage_access.test.sql` (41 aserciones) con fixtures dentro de una transacción `ROLLBACK`; no se crean datos en Cloud.

Cobertura: sin grant, roles owner/admin/manager y requester/technician/no asignado, otros clientes, UUID inexistente, orden externa y orden de solicitud borrador, estado cerrado/completado, prioridad y fecha inválida, valores esperados obsoletos, persistencia, auditoría del actor y de los cambios, idempotencia, revocación de cada grant, relación suspendida y membresía inactiva.

**QA completado:** GitHub Actions [run 42761748381](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/42761748381): **21 suites / 2,323 aserciones PASS**, incluidas las 41 nuevas de B2.1. La migración fue aplicada a Cloud como versión `20261110061336` y sus controles de ACL y RLS pasaron. El usuario FM de QA sin `work_orders.manage` recibió `42501`. **No conceder `work_orders.manage` ni habilitar la interfaz hasta QA de C2.1 y autorización específica de ese permiso.**

## Etapas siguientes

- **B2.1:** backend de planificación interna + regresión.
- **C2.1:** formulario limitado a prioridad y fechas, condicionado por capacidades del servidor; requiere diseñar y mostrar `can_manage` real para OT internas autorizadas y conservar la vista solo lectura para todos los demás.
- **B2.2 / C2.2 (D3):** creación delegada de OT desde cotización aprobada / solicitud interna, con idempotencia.
- **B2.3 / C2.3 (D4):** seguimiento del cliente separado de la bitácora operativa.
- **D:** QA integral, respaldo, despliegue secuenciado y auditoría post-release.

### Recuperación

La migración B2.1 ya está instalada. Ante incidente, utilizar con autorización el script `docs/rollbacks/9c6-b2-1-soft-disable.sql` que revoca `EXECUTE` de la nueva RPC (sin alterar B1/C1). Este procedimiento no sustituye un backup ni revierte registros existentes; tampoco borra el historial de migraciones.
## Verificación tras aplicación a Cloud

- `apply_migration`: éxito; versión `20261110061336_fm_internal_work_order_planning`. El contenido SQL corresponde al blob `68f2efe32fffdae175e6234aebf92469e43418f5`, probado en CI; el nombre de archivo en GitHub se alineó con Cloud sin alterar SQL.
- 86 migraciones totales; 29 OT, 11 audit_logs y 13 grants FM; 1 grant `work_orders.view` de QA y **0 grants `work_orders.manage`**.
- RPC `SECURITY DEFINER`, `search_path` vacío, `lock_timeout=3s`; `anon` sin EXECUTE y `authenticated` con EXECUTE condicionado a validación interna.
- QA contra Cloud con usuario FM asignado, sin manage: rechazo `42501` esperado. No se ejecutaron escrituras de OT productivas.
- RLS de `work_orders` y `audit_logs` sigue habilitado con una política por tabla.
