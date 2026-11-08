# One Facility — 9C.6-B1: acceso delegado a OT (backend solo lectura)

**Estado:** backend B1 aprobado en QA aislado; **sin aplicación a Supabase Cloud, sin merge y sin despliegue a Vercel Production**.  
**Contrato aprobado:** `docs/FACILITY_MANAGER_WORK_ORDERS_CONTRACT.md` (D1–D7 aprobadas; B2/C1/C2 fuera de alcance de B1).

## Alcance implementado

Migración aditiva `20261108003000_facility_manager_work_orders_read_access.sql`:

| RPC | Propósito y restricciones |
|---|---|
| `get_facility_management_work_orders(_client_organization_id uuid, _status text DEFAULT NULL, _limit int DEFAULT 50, _offset int DEFAULT 0)` | Lista paginada con `items,total,limit,offset`. Estado NULL = todos los estados existentes. Límite entre 1 y 100; offset entre 0 y 100000. |
| `get_facility_management_work_order(_client_organization_id uuid, _work_order_id uuid)` | Detalle sanitizado, error `42501` indistinguible para OT inexistente y OT de otro cliente. |

Helpers **internos** no ejecutables por `authenticated` ni `anon`:
- `can_view_work_orders_as_facility_manager`: exige `requests.view` + `work_orders.view` en una misma relación activa y miembro FM asignado, rol owner/admin/manager/requester.
- `can_view_facility_management_work_order_price`: además exige `quotes.view`, cotización de origen `approved` vinculada a solicitud y operador de la OT y visibilidad `min_quotes`/`quotes_closed` de 9C.5.
- `facility_management_work_order_read_payload`: lista blanca de campos; campos internos ajenos NO aparecen.

**RLS y CRUD:** no se alteran RLS, policies, grants de tablas, estados, OTP de proveedor, cotizaciones, notificaciones, ni registros de negocio. No se habilita acceso por tabla ni creación/actualización/cierre de OT. La clave `can_manage` permanece `false` en B1.

## Contrato de respuesta

Ejemplo de envoltura de lista:

```json
{"items":[{"id":"uuid","work_order_number":"OT-...","work_order_type":"external","status":"completed","priority":"high","title":"...","description":"...","request_number":"SOL-...","asset_label":null,"operator_label":"Proveedor externo","has_planner":true,"has_technician":false,"scheduled_at":null,"due_at":null,"created_at":"...","started_at":null,"completed_at":"...","total_amount":null,"prices_visible":false,"can_manage":false}],"total":1,"limit":50,"offset":0}
```

Notas:
- `total_amount` es `null` salvo que se cumplan simultáneamente todos los grants y la regla económica de la cotización.
- Si es una OT externa con importe no autorizado, el título se sustituye por «Orden externa» y la descripción se devuelve `null` porque ambos son texto libre y podrían contener cifras (HF01).
- `asset_label` solo si están presentes los grants de acceso al activo con rol FM owner/admin/manager.
- `request_number` es correlativo; no se exponen IDs de otros usuarios/organizaciones ni documentos/evidencias del proveedor.
- `operator_label` distingue «Interna» vs «Proveedor externo», sin ID del proveedor.
- No hay acceso a materiales, inventario, actividades operadoras, bitácoras ni reportes de ejecución por estas RPCs.
- Se excluyen OTs cuyo origen es una solicitud borrador o anulada, o cuya solicitud no pertenece al mismo cliente, tanto en listado como en detalle, incluso si la fila de OT apuntara a un ID válido.

## Seguridad y casos de prueba

Archivo `supabase/tests/facility_manager_work_orders_read_access.test.sql` (51 aserciones).

Cobertura prevista: roles permitidos, roles denegados, miembro no asignado, usuario desconocido, otro cliente, UUID inexistente, revocación de permisos, suspensión de relación, cliente suspendido, miembro inactivo, límites de paginación, estados, ocultación económica/textual, cierre anticipado de cotizaciones, activo con/sin grants, ACL de las RPCs y modo sin SELECT directo de tablas.

**QA aislado ejecutado:** GitHub Actions [run 42431580305](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/42431580305), commit `ed42da5`. Local `supabase start` PASS, `supabase test db` **PASS: 20 suites y 2282 aserciones**, con 51/51 de B1 y ACL estricta; `supabase stop --no-backup` PASS. No se utilizó Cloud.

## Gate de validación y despliegue

1. Refrescar una copia **aislada y descartable** de esquema local con migraciones del repo (nunca prod).
2. Comprobar que la migración nueva carga sin errores, se instala exactamente una vez y no altera firmas/ACL de RPCs anteriores.
3. Ejecutar la suite dedicada pgTAP (51/51) y la suite completa (`supabase test db --local`); resolver cualquier fallo antes de proceder.
4. Verificar ACL estricta, accesos positivos/negativos y que ni título, descripción, observaciones o importe revelen valores ocultos.
5. Revisar GitHub diff y checks. Como B1 no cambia frontend, **no se requiere despliegue de Vercel** para probarlo localmente.
6. Solo con PASS, respaldos y autorización de despliegue, aplicar **únicamente** la migración B1 a Supabase Cloud; revalidar firmas, ACL, 0 escrituras de negocio y NO conceder aún permisos de OT a relaciones reales.
7. En producción, cuando se habilite QA, asignar temporalmente a FM QA Test `work_orders.view` manteniendo `requests.view`; realizar QA con cuenta FM sin membresía del cliente y revertir el permiso de prueba si corresponde.
8. 9C.6-C1 implementará la interfaz en una entrega posterior; B1 no abre pantallas.

### Nota sobre plataforma de pruebas
Este contenedor no ofrece Docker/CLI, pero GitHub Actions ejecutó Docker + Supabase CLI en un runner aislado. Se validó el esquema y la regresión pgTAP completa con resultado PASS. No hubo DDL/fixtures sobre Cloud.

## Rollback previsto
Antes de un futuro `apply_migration` generar un backup recuperable y snapshot de ACL/funciones. B1 añade RPCs nuevas; si se requiere desactivar, revocar EXECUTE en las dos RPC públicas sin alterar datos. Nunca borrar manualmente una fila del historial de migraciones como rollback ordinario. No modificar ni revertir las funciones de 9C.5.

## Próximo paso
La suite local aislada ya está PASS. Quedan revisión del PR, preflight y respaldo para Cloud, y autorización de integración/despliegue B1. Después desarrollar 9C.6-C1. Las escrituras B2 quedan separadas.


### Estado posterior al QA

PR #80 continúa Draft sin merge. Supabase Cloud: 84 migraciones, 29 OT y 0 RPC nuevas / 0 concesiones de permisos OT; comprobado mediante SQL de solo lectura. El gate de pruebas está cerrado en PASS, pero **no autoriza implícitamente desplegar en producción**.
