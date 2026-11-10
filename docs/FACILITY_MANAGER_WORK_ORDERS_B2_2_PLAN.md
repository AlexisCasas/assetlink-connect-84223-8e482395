# One Facility — 9C.6-B2.2 (D3): creación de OT delegada

**Estado:** diseño técnico / preflight de solo lectura, pendiente de implementación y QA aislado. **Fecha:** 2026-11-10.  
**Base GitHub:** `productization/mvp`, commit `7fc400e47c6017b80aeb3a4a71f16f19a52923d7` (PR #83 / C2.1 integrado).  
**Supabase:** proyecto OneFacility `hplchnsseylngjopgbtl`. Ninguna escritura de OT, permiso o migración ejecutada para B2.2.

## 1. Contexto y decisión

- `docs/FACILITY_MANAGER_WORK_ORDERS_CONTRACT.md`: D1–D7 aprobadas, incluidas **D3 (creación delegada)** y **D4 (notas de seguimiento)** como entregas separadas.
- `docs/FACILITY_MANAGER_WORK_ORDERS_B2_1.md`: secuencia **B2.2 backend / C2.2 UI (D3)**, después **B2.3 / C2.3 (D4)** y **D (QA integral)**.
- En C2.1 ya existe `work_orders.manage` como grant de relación, pero el FM no hereda la membresía del cliente ni las facultades del operador.
- **B2.2 no cambia estados de órdenes existentes, no asigna técnicos, no crea solicitudes ni decide cotizaciones.** `quotes.approve` sigue separado.

## 2. Evidencias Cloud (2026-11-10, solo lectura)

- **29 OT**: 18 externas y 11 internas.
- **18 cotizaciones aprobadas sin OT = 0**: para el conjunto actual, la operación externa es principalmente una ruta idempotente sobre OT existentes.
- **2 solicitudes internas enviadas/elegibles sin OT**: no usarlas como fixtures de escritura en Cloud.
- Duplicados actuales: **0** por cotización y **0** por solicitud interna.
- Protección concurrente *ya instalada*: `work_orders_quote_id_key` UNIQUE (`quote_id`) y `uq_work_orders_internal_request` UNIQUE (`request_id`) **WHERE `quote_id IS NULL`**. Evitar crear índices redundantes.
- Funciones legacy: `create_work_order_from_quote(uuid)` y `create_internal_work_order_from_request(uuid,uuid)` retornan filas completas `work_orders`, autorizan por membresía directa del cliente y no son reutilizables directamente como endpoints FM.
- **No existen todavía** RPC de creación con prefijo `create_facility_management%work_order%`.
- C2.1 validada en producción; `work_orders.manage` temporales = 0 tras cierre.

## 3. Diseño de API B2.2

### 3.1 Crear OT externa desde cotización aprobada

`create_facility_management_work_order_from_quote(_client_organization_id uuid, _quote_id uuid) RETURNS jsonb`.

Validaciones obligatorias:

1. `auth.uid()` real; organización cliente y FM activas; relación `facility_management` activa; membresía FM activa y **asignación explícita** a esa relación; rol FM `owner/admin/manager`.
2. En la **misma relación**, exigir `requests.view`, `work_orders.view`, `work_orders.manage` y `quotes.view`. No sustituir por `quotes.approve` ni por membresía del proveedor.
3. Cotización pertenece a solicitud **externa del cliente indicado**, está `approved`, tiene proveedor legítimo y no tiene datos cruzados; validación en servidor con bloqueos.
4. Si ya hay OT para esa cotización, **devolverla sin nueva OT, notificación ni auditoría de creación**. En carrera, usar índice único existente, y comprobar cuál OT ganó.
5. Si no hay OT, crear `external` sin atribuir FM como técnico/planificador/proveedor. Los datos económicos y el proveedor se mantienen internos; no se devuelven en crudo.

### 3.2 Crear OT interna desde solicitud elegible

`create_facility_management_internal_work_order(_client_organization_id uuid, _request_id uuid) RETURNS jsonb`.

Validaciones obligatorias:

1. Mismos controles de identidad/relación/rol y los tres grants: `requests.view`, `work_orders.view`, `work_orders.manage`. El contrato aprobado no exige `requests.manage` adicional para una solicitud **ya enviada**; nunca otorgarlo implícitamente.
2. Solicitud pertenece al cliente, `request_type='internal'`, elegible (nunca `draft` ni `anulado`), cliente activo.
3. OT con `quote_id=NULL`, `client_organization_id=provider_organization_id=_client_organization_id`; `planner_member_id=NULL` y `assigned_member_id=NULL`; estado inicial `pending`. No llamar `resolve_caller_planner_member` como si el FM perteneciera al cliente.
4. Reutilizar orden interna existente mediante el índice parcial `uq_work_orders_internal_request`; proteger concurrencia (lock y/o `INSERT ... ON CONFLICT DO NOTHING`, seguida de lectura autorizada).
5. Notificación al cliente/operación correspondiente **una sola vez** si se crea una OT real.

### 3.3 Contrato de respuesta, ACL y auditoría

- Ambas RPC públicas devuelven solamente el DTO sanitizado de `get_facility_management_work_order(_client_organization_id,_work_order_id)`, **jamás `RETURNS work_orders`**.
- Prohibido exponer `total_amount`, `quote.description`, identificadores internos de miembros, correos, materiales y datos de proveedor que no pasen por el gate de confidencialidad 9C.5/B1.
- `SECURITY DEFINER` únicamente con verificación expresa de `auth.uid()`, `SET search_path=''`, objetos schema-calificados, lock timeout definido; revocar `PUBLIC/anon` y otorgar `EXECUTE` solo a `authenticated`.
- Registro en `audit_logs` para **nueva** creación: `organization_id` = cliente; `actor_user_id=auth.uid()`; acción distinguible interna/externa; contenido mínimo (ID de solicitud/cotización si autorizado para auditoría, OT y tipo), sin importe ni descripción libre.
- No modificar las RPC legacy ni las RLS existentes del cliente/operador como atajo. Las funciones FM nuevas deben ser rutas independientes.

## 4. Seguridad y concurrencia: pruebas obligatorias (QA aislado)

1. Sin sesión, sin asignación o relación suspendida: rechazo `42501`.
2. Sin cada grant requerido individualmente; `work_orders.manage` solo no equivale a `view`.
3. FM `requester/technician/viewer` no crea; owner/admin/manager asignado sí.
4. UUID inexistente o de otro cliente: respuesta indistinguible, sin filtraciones.
5. Cotización `submitted/rejected`, solicitud interna/externa cruzada, solicitud draft/anulada: rechazo.
6. Creación externa y creación interna con estado, organizaciones, miembros y payload correctos.
7. Segunda ejecución = misma OT, 0 notificaciones y auditorías adicionales.
8. Dos transacciones simultáneas sobre la misma solicitud/cotización = una sola OT; sin devolver `23505` crudo ni generar duplicados.
9. Falta de visibilidad económica: importe/textos sensibles ausentes del DTO incluso cuando la OT se creó correctamente.
10. Ningún cambio de permisos, RLS, roles cliente/proveedor, ejecución, técnico, estado o inventario; regresión B1/B2.1 y flujos legacy.
11. `pgTAP`, TypeScript/lint/build y pruebas de flujos UX focalizados; validar migración en base aislada **antes** de tocar Cloud.

## 5. Secuencia de construcción y puertas

| Etapa | Entregable | Puerta |
|---|---|---|
| **B2.2-A** | Auditoría de Cloud + contrato B2.2 | Este documento; sin escrituras productivas |
| **B2.2-B** | Migración SQL de dos RPC con ACL, audit, idempotencia y triggers existentes | PR draft; no merge |
| **B2.2-C** | pgTAP + estrés concurrente y regression legacy en base aislada | QA PASS |
| **B2.2-D** | Revisión de seguridad y aplicación secuenciada Cloud → GitHub | Autorización específica de migración y controles |
| **C2.2** | Acciones de creación seguras en solicitudes/cotizaciones delegadas | Preview + QA real; sin crear OT de prueba en producción sin permiso |
| **B2.3/C2.3 (D4)** | Notas de seguimiento lado cliente en entidad separada | Nuevo contrato y PR |
| **9C.6-D** | QA integral, limpieza y observabilidad final | PASS y cierre |

**NO-GO de B2.2:** no aplicar migración en Supabase Cloud, no crear OT reales ni conceder permisos desde este PR de planificación. Este documento no implica implementación concluida.
