# One Facility — 9C.6-A: contrato funcional de órdenes de trabajo delegadas

**Estado:** D1–D7 aprobadas por el responsable funcional el 07/11/2026. 9C.6-B1 implementado en rama de revisión; no desplegado en Supabase Cloud. 9C.6-B2/C1/C2/D pendientes.  
**Fecha de auditoría:** 2026-11-07.  
**Repositorio:** `AlexisCasas/assetlink-connect-84223-8e482395`.  
**Base auditada:** `productization/mvp`, commit `729bb381840a40994513e91d234a8bbe65df33ad`.  
**Supabase Cloud consultado:** proyecto `hplchnsseylngjopgbtl`, PostgreSQL 17, 84 migraciones (última `20261107232637`).  
**Modo:** GitHub + Supabase, solo lectura de aplicación/BD. Sin cambios en base de datos, RLS, migraciones o producción.

> **Leyenda:** **VERIFICADO** = constatado en código/SQL/Cloud. **PROPUESTA** = comportamiento deseado aún no desarrollado. **DECISIÓN** = requiere aceptación del responsable funcional antes de 9C.6-B. La existencia de permisos en un enum no significa que ya otorguen acceso.

## 1. Propósito y frontera de responsabilidades

El cliente es propietario de su solicitud y de la relación contractual; el Facility Manager (FM) coordina en nombre del cliente y solo dentro de los permisos delegados; la organización operadora ejecuta y gestiona sus recursos internos. Un FM **no se convierte en proveedor** por gestionar una OT.

**VERIFICADO:** `work_orders.client_organization_id` y `provider_organization_id` distinguen cliente de operador. En OT interna coinciden; en OT externa difieren. La cabecera es visible a miembros del cliente o de la operadora mediante la RLS actual, pero actividades, materiales, bitácoras y reportes tienen restricciones específicas de la operadora.

**PROPUESTA:** el FM consulta el estado y coordina por cuenta del cliente, sin recibir automáticamente los privilegios de la organización operadora.

## 2. Inventario de producción y casos de QA

Consulta agregada en Cloud el 07/11/2026:

| Universo | Total | Desglose |
|---|---:|---|
| OT de todas las organizaciones | 29 | 18 externas / 11 internas |
| OT de Makro Test | 23 | 15 externas / 8 internas |
| Actividades de OT | 54 | Datos de ejecución existentes |
| Materiales de OT | 36 | Líneas de planificación y uso |
| Reportes de actividad | 44 | Datos de ejecución existentes |
| Concesiones `work_orders.view/manage` entre Makro Test y FM QA Test | 0 | No hay acceso delegado habilitado |
| RPC específicas `facility_management*work_order*` | 0 | No hay backend delegado de OT |

Casos existentes de QA **solo para lectura**, sin cambiar estados ni generar datos reales:

| OT | Origen | Estado |
|---|---|---|
| `OT-MAKRO-012` | Externa | pending |
| `OT-MAKRO-010` | Externa | assigned |
| `OT-MAKRO-013` | Externa | in_progress |
| `OT-MAKRO-014` | Externa | completed |
| `OT-MAKRO-015` | Externa | closed |
| `OT-MAKRO-020` | Interna | pending |
| `OT-2026-000009` | Interna | completed |
| `OT-MAKRO-016` | Interna | closed |

Los códigos representan registros existentes; no implican que estén disponibles para escritura de QA. Las pruebas de decisiones requerirán fixtures aislados.

## 3. Operaciones existentes verificadas

| Área | Implementación existente | Restricción actual relevante |
|---|---|---|
| Listado/cabecera | `useWorkOrders` hace `.from('work_orders').select('*')` | Cliente filtra por `client_organization_id`; FM actual filtra por **`provider_organization_id = FM`**, no por cliente delegado |
| Detalle | `WorkOrderDetailDialog` | Muestra IDs internos, importe, fechas, descripción y observaciones; **no es un DTO seguro para FM** |
| Crear OT desde cotización | `create_work_order_from_quote` | Cotización `approved`, solicitud externa; autorización del usuario del cliente/plataforma; no FM |
| Crear OT interna | `create_internal_work_order_from_request` | Solicitud interna, cliente activo y owner/admin/manager del cliente/plataforma; no FM |
| Planificar OT | `update_work_order_operations` | Solo owner/admin/manager de `provider_organization_id` o plataforma; actualiza planner, técnico, fechas, prioridad, estado y observaciones |
| Asignar técnico | `assign_work_order_technician` | Organización operadora |
| Técnico actualiza progreso | `technician_update_work_order_progress` | Técnico activo y realmente asignado por la operadora; transiciones `pending/assigned → in_progress → completed` |
| Actividades | `get_work_order_activities`, `upsert_work_order_activity`, `delete_work_order_activity` | Datos y membresías internas de operadora |
| Materiales | `get_work_order_materials`, `upsert_work_order_material`, `delete_work_order_material` | Inventario, stock y materiales de operadora |
| Bitácora de trabajo | `get_work_order_work_logs` | Organización operadora |
| Informes de actividad | `get_activity_reports_for_work_order`, `submit_activity_report` | Planificadores de operadora o técnico autor; pueden contener nombres/emails, materiales, evidencias |
| Seguimiento de FM | Ninguna RPC específica de OT | Aún no existe coordinación delegada diferenciada |

**Observación de seguridad existente:** en Cloud las tablas OT tienen grants de tabla declarados para `anon` y `authenticated`, pero la RLS de `work_orders` solo tiene política SELECT para miembro cliente/proveedor/plataforma; no se detectó una policy genérica de escritura en esas tablas. **Los grants por sí solos no autorizan filas ni sustituyen RLS.** No ampliar RLS ni grants como atajo; verificar ACL estricta durante 9C.6-B.

**Observación sobre estados:** `update_work_order_operations` valida que `target_status` pertenezca al conjunto `pending, assigned, in_progress, completed, closed`, pero ese filtro no equivale a una máquina de transiciones completa entre estados. No reutilizar esta RPC directa como mecanismo de estado delegado.

## 4. Frontera interna vs. externa — matriz Cliente / FM / Proveedor

| Operación | Cliente (flujo actual) | FM propuesto | Proveedor/operador actual |
|---|---|---|---|
| Leer cabecera de OT propia | Sí, sujeto a RLS | Sí, con `work_orders.view` y contexto delegado | Sí, si opera la OT |
| Leer cabecera externa | Sí | Sí, sanitizada | Sí, de OT que ejecuta |
| Leer cabecera interna | Sí | Sí, sanitizada | Cliente es también operadora |
| Consultar estado/fechas/prioridad | Sí | Sí, solo lectura | Sí |
| Consultar cotización origen | Según `quotes.*` | Solo con `quotes.view` y `requests.view` | Según autorización propia, nunca por delegación FM |
| Ver importe externo | Sí por la cabecera directa actual | **Solo con permiso económico y regla de visibilidad**, aplicada en servidor | Según permisos de operador |
| Crear OT desde cotización aprobada | RPC actual con roles del cliente | **DECISIÓN D3**: permitir acción delegada específica, no como proveedor | No por rol FM |
| Crear OT interna desde solicitud | RPC actual con roles del cliente | **DECISIÓN D3**: creación delegada restringida | Cliente es operador |
| Actualizar prioridad/fechas de OT interna | Planificador del cliente | **DECISIÓN D2**: coordinación acotada, no estado/tecnicidad | Operador cliente |
| Cambiar planner/técnico de OT externa | No como cliente | Nunca | Solo operadora |
| Actividades, técnicos por actividad, materiales, inventario | Solo en OT que el cliente opera directamente | No en contrato base 9C.6 | Solo operadora |
| Partes de ejecución, bitácora y evidencias | Según su rol en organización operadora | No crudos; solo eventual resumen aprobado | Solo operadora |
| Cambiar estado/cerrar OT externa | No unilateralmente | No unilateralmente | Solo operación autorizada de operadora |
| Registrar nota de seguimiento del cliente | Sin entidad separada actual | **DECISIÓN D4**: proponer nota separada y auditada | No modifica bitácora operativa |
| Eliminar OT | No se observa acción de eliminación general | No | No incorporar vía FM |

**Importante:** no trasladar directamente `WorkOrderDetailDialog` ni `useWorkOrders` al modo delegado: exponen campos, llamadas y dependencias de organización operadora que no corresponden al FM.

## 5. Matriz de roles y permisos — PROPUESTA

Capa de seguridad obligatoria **en cada RPC**, no solo en la interfaz:
1. Sesión autenticada real (`auth.uid()`).
2. Empresa cliente y FM activas.
3. Relación `facility_management` activa y vinculada a **esa** empresa cliente.
4. Membresía activa del usuario en la empresa FM.
5. Usuario explícitamente asignado a esa relación.
6. Todos los grants exigidos, en **la misma relación**, y rol FM válido.
7. OT realmente pertenece al cliente solicitado; la autorización no se infiere por UUID ni por pertenencia a otro cliente.
8. Tipo/estado aptos para la operación solicitada.

**Recomendación conservadora para 9C.6 (D1, por aprobar):**

| Rol FM | `work_orders.view` + `requests.view` | `work_orders.manage` + dependencias | Condición |
|---|---|---|---|
| owner | Ver | Gestionar acciones del cliente | Siempre sujeto a asignación explícita |
| admin | Ver | Gestionar acciones del cliente | Igual |
| manager | Ver | Gestionar acciones del cliente | Igual |
| requester | Ver | No | Consulta de seguimiento, sin decisiones |
| technician | No inicialmente | No | Técnicos de la operadora usan su flujo propio; definir caso FM separado si es necesario |
| viewer | No inicialmente | No | Mantener consistencia con la lectura restringida de solicitudes |

- `work_orders.manage` NO implica lectura: exigir `work_orders.view` y `requests.view`.
- `requests.view` permite enlazar al resumen de la solicitud; no entrega automáticamente derechos sobre cotizaciones.
- `quotes.view` es requisito adicional **solo** para el bloque de datos económicos o el enlace al detalle de la cotización.
- `quotes.approve` no es equivalente a `work_orders.manage` y no debe heredarse.
- `work_orders.view` sin `requests.view`: recomendación inicial = negar el módulo (dependencia de solicitud). Esto debe quedar claro en la UI de permisos.
- Una relación administrativa visible en el portafolio no basta para operar sin asignación.

**D1 pendiente de aprobación:** ¿requester puede leer todas las OT del cliente delegado o debe limitarse a las solicitudes que originó? Recomendación temporal: lectura de las OT del cliente, únicamente con ambos grants y asignación. No ampliar a technician/viewer sin modelo específico.

## 6. Contrato mínimo de respuesta: lista y detalle (PROPUESTA)

**DTO listado `get_facility_management_work_orders(_client_org, _filters)`:**

| Campo | Visibilidad y condición |
|---|---|
| `id` de OT | Solo como identificador opaco para detalle; no se considera secreto y requiere control server-side por cada llamada |
| `work_order_number`, `title` | Sí; título del servicio autorizado (evaluar si contiene datos libres sensibles) |
| `work_order_type` | `internal` / `external` |
| `status`, `priority` | Sí |
| `scheduled_at`, `due_at`, `created_at`, `completed_at` | Sí |
| `request_number` | Público para la organización, sin exponer `request_id` sin necesidad |
| `asset_label` / ruta segura | Solo si `assets.view` y autorizado para ese activo; de otro modo texto genérico o null |
| `operator_label` | 'Interna' o 'Proveedor externo'; nombre de proveedor solo si fue explícitamente autorizado |
| `has_planner`, `has_technician` | Indicadores, sin IDs ni datos de miembros |
| `total_amount` | null salvo autorización económica + `quotes.view` + visibilidad real de cotización de origen |
| `can_manage` | Flag orientativo derivado en servidor; **no sustituye** validar escrituras |
| `client_organization_id`, `provider_organization_id` | No incluir en DTO público delegado salvo necesidad justificada y documentada |
| `planner_member_id`, `assigned_member_id`, `created_by_user_id` | No exponer |

**DTO detalle `get_facility_management_work_order(_client_org, _work_order_id)`:**
- Incluye cabecera minimizada y banderas de capacidad por acción, nunca `SELECT *`.
- `description` y `observations`: **texto libre potencialmente económico/privado**. Para OT externas con precio oculto, devolver null en campos de texto libre con riesgo de cifras, no limpiar por regex. Definir cuáles pueden mostrarse tras alcanzar visibilidad. Las observaciones internas del proveedor no deben difundirse por defecto aunque el precio sea visible.
- No exponer datos de `organization_members`, `auth.users`, IDs del proveedor, inventarios, SKUs, stock, coste, horas, materiales, logs de ejecución, notas operadoras, reportes crudos ni evidencias firmadas/URLs.
- Para OT internas, la presencia de acceso al cliente como FM **no transforma** sus privilegios en membresía de la organización operadora. Si se aprueba lectura de detalles internos, requerirá nueva RPC con un DTO explícito.
- Errores indistinguibles para OT inexistente/no autorizada/otro cliente; no revelar existencia de terceros.
- No usar `get_work_order_activities`, `get_work_order_materials`, `get_activity_reports_for_work_order` ni `get_work_order_work_logs` desde el FM por defecto.

**D5 pendiente:** ¿se permite ver importe externo cuando `min_quotes` aún no se alcanza, pero la OT ya existe por el flujo directo? Recomendación: **no**; mantener la condición económica igual a 9C.5, y null para textos sensibles hasta que sea visible. Evitar la fuga previa de `description`.

## 7. Acciones de gestión — opciones separadas, nunca permisos globales

### 7.1 Consulta (alcance base recomendado)
- Listar por cliente seleccionado mediante `ManagedClientGate`, estados, fechas y prioridad.
- Abrir detalle seguro, seguimiento y enlaces profundos autorizados.
- Leer OT externa/interna sin acceso a información privada de ejecución.

### 7.2 Gestión de OT interna — DECISIÓN D2
Recomendación para un alcance incremental: con `work_orders.manage`, owner/admin/manager FM, permitir **solo** ajuste de `priority`, `scheduled_at` y `due_at` en OT **interna** no terminal (exceptuar `completed/closed`); exigir validación de fechas, bloqueos y auditoría. Mantener `planner_member_id`, `assigned_member_id`, `status`, `observations` y datos del operador fuera de esta RPC hasta revisar la gestión de roster del cliente.

No llamar `update_work_order_operations` existente: opera como rol de proveedor, puede modificar estados y técnicos y devuelve la fila completa.

### 7.3 Gestión de OT externa — DECISIÓN D4
Permitir **únicamente coordinación del lado del cliente**, por ejemplo nota de seguimiento con actor FM real, fecha, cliente, OT y relación; en entidad separada (no `work_order_work_logs`, ni `observations` del proveedor). Requiere nuevo contrato de confidencialidad/lectura y criterio de visibilidad para el cliente y proveedor. Si no se aprueba el submódulo, `work_orders.manage` no modifica OT externas en 9C.6 inicial.

### 7.4 Creación de OT — DECISIÓN D3
Evaluar y aprobar expresamente dos operaciones delegadas:
1. Desde cotización `approved` de solicitud externa, con `work_orders.manage` + `quotes.view` + `requests.view`; nunca con identidad del proveedor. Revalidar no duplicación y aprobación mediante lock/constraint transaccional.
2. Desde solicitud interna elegible, con `work_orders.manage` + `requests.view` (+ `requests.manage` si se aprueba), sin asignar técnicos en nombre del cliente. Definir elegibilidad y prevención de duplicados.

Sin aprobación de D3: ambas creaciones quedan fuera de 9C.6-B y continúan exclusivamente en el flujo directo.

### 7.5 Estados y cierre
Estados detectados: `pending`, `assigned`, `in_progress`, `completed`, `closed`. La función de técnico permite únicamente `pending/assigned → in_progress` y `in_progress → completed`. La RPC de planner acepta los cinco valores pero no impone todos los arcos posibles.

**Propuesta:** 9C.6 **no concede al FM cambio directo de `status`**, ni reabrir ni cerrar OT externas, ni cancelar; una eventual aceptación/cierre del lado del cliente debe diseñarse como acción separada y con precondiciones (estado completado, pruebas, auditoría), no como `UPDATE status` genérico.

## 8. Diseño de API mínimo para 9C.6-B (propuesta)

1. `get_facility_management_work_orders(_client_org, _filters?) → jsonb` — lista sanitizada y paginada; validar filtros, topes de página y orden.
2. `get_facility_management_work_order(_client_org, _work_order_id) → jsonb` — detalle sanitizado, comprobación por ID y cliente.
3. **Opcional según D2:** `update_facility_management_internal_work_order_schedule(...)` — únicamente campos aprobados; bloqueo de fila, CAS/versión y auditoría.
4. **Opcional según D3:** `create_facility_management_work_order_from_quote(...)` y `create_facility_management_internal_work_order(...)`, con revalidación transaccional e idempotencia.
5. **Opcional según D4:** `add_facility_management_work_order_followup(...)` y `get_facility_management_work_order_followups(...)` en entidad separada.

Patrón esperado: nuevas RPCs con autorización completa por solicitud, `SECURITY DEFINER` solo si justificado; `search_path` vacío y referencias cualificadas; `auth.uid()` obligatorio, sin grants a `PUBLIC/anon`; `EXECUTE` solo para `authenticated` en RPCs públicas aprobadas; sin SELECT bruto ni UPDATE directo sobre tablas privadas; usar el helper `has_facility_management_operational_access_all` con permisos y roles explícitos.

**No** reutilizar la RLS de cliente como identidad simulada del FM ni alterar el JWT para fingir que pertenece a la organización cliente.

## 9. UI prevista para 9C.6-C (propuesta)

- Nueva opción 'Órdenes de trabajo' en la vista operativa del cliente administrado, activada solamente con grants/rol eficaces; integrarse con `ManagedClientGate` y parámetro `managedClient` verificado.
- Reutilizar aspecto visual de lista, pero **no** la carga existente de `useWorkOrders` ni la respuesta completa de `WorkOrderDetailDialog`.
- Columnas: correlativo, interna/externa, título, activo autorizado, estado, prioridad, programada/límite, indicador 'técnico asignado', importe solo si autorizado, detalle.
- Filtros de estado que incluyan terminadas y cerradas, sin ocultar histórico como ocurrió en E1-FIX02.
- Acciones según permisos en servidor y por estado; en OT externa no aparece edición operativa, asignación de proveedor, materiales, reportes internos ni cambio de estado.
- Mensajes correctos de acceso revocado; deep link `#work-orders?managedClient=…&workOrder=…` debe pasar por autorización, no abrir datos de otro cliente.
- Evitar llamada a `generate_operational_due_notifications` desde las consultas delegadas de solo lectura: la carga FM no debe crear notificaciones de manera implícita.

## 10. Riesgos identificados

| Riesgo | Hecho / mitigación propuesta |
|---|---|
| Fuga de información personal | El detalle actual incluye IDs internos y las RPCs operadoras incluyen emails de técnicos; crear DTO con allowlist |
| Fuga económica | `work_orders.total_amount` se muestra directamente hoy a lectores de la tabla; respetar `quotes.view` y visibilidad 9C.5 en servidor delegado, incluyendo texto libre |
| Escalada de privilegios | `work_orders.manage` no puede reutilizar `update_work_order_operations` para actuar como operadora |
| BOLA entre clientes | Revalidar relación, asignación, organización y OT en cada RPC; probar UUID ajeno |
| Escritura sobre estados terminales | No permitir cambios a completed/closed sin decisión explícita |
| Doble OT en una aprobación | Idempotencia, lock y prueba de concurrencia al crear OT desde cotización/solicitud |
| Cross-client con doble membresía | Probar FM asignado **sin** membresía directa de cliente y usuario ajeno |
| Notificaciones/efectos de lectura | El hook existente ejecuta generación de notificaciones; no reutilizarlo |
| RLS vs. grants de tabla | Hay grants declarados para roles API; la RLS es la barrera actual. No ampliar grants/RLS; QA con ACL estricta |
| Filtración por evidencias de ejecución | Evitar URLs o documentos de proveedor en el DTO FM sin contrato explícito |

## 11. Matriz de aceptación para 9C.6-D

| Código | Caso | Resultado esperado |
|---|---|---|
| OT-01 | Owner/admin/manager FM asignado, relación activa, ambos permisos de lectura | Lista y detalle sanitizados |
| OT-02 | FM sin `work_orders.view` | Negado, no aparece módulo |
| OT-03 | FM con `work_orders.view` pero sin `requests.view` | Negado según D1 |
| OT-04 | FM no asignado, incluso owner del FM | Negado |
| OT-05 | Relación suspendida/ended; cliente o FM inactivo | Negado inmediatamente |
| OT-06 | Usuario de otro FM / OT de otro cliente por UUID | Error indistinguible, sin datos |
| OT-07 | Usuario solo FM (sin membresía directa en cliente) | Acceso delegado positivo; SELECT directo no ampliado |
| OT-08 | Doble membresía cliente/FM | Debe funcionar según contexto explícito sin heredar poderes de proveedor |
| OT-09 | OT externa pending, assigned, in_progress, completed, closed | Visible según scope y permisos, siempre solo lectura operativa |
| OT-10 | OT interna pending, completed, closed | Idem; campos según tipo |
| OT-11 | Cotización bajo `min_quotes`, sin `quotes.view` | Importe y textos económicos nulos incluso por detalle/deep link |
| OT-12 | Cotización alcanza mínimo o cierre de envío y FM tiene `quotes.view` | Importe permitido, sin datos privados del proveedor |
| OT-13 | Planner, técnico, inventario, reportes y evidencias operadoras | No accesibles por RPC/FM/URL |
| OT-14 | Revocar `work_orders.view` o desasignar miembro | Lectura nueva falla; no caché autorizativa persistente |
| OT-15 | `work_orders.manage` sin `work_orders.view` | No abre escritura |
| OT-16 | FM intentar asignar técnico/cambiar estado OT externa | Denegado |
| OT-17 | FM gestionar OT interna completed/closed (si D2) | Denegado |
| OT-18 | Concurrentes duplicando OT (si D3) | Una sola OT/auditoría consistente |
| OT-19 | Usuario autorizado abre deep link OT | Solo su cliente, sin información ajena |
| OT-20 | Cliente directo/proveedor con permisos actuales | Sin regresión funcional |
| OT-21 | pgTAP con ACL estricta; regresión integral SQL; build y smoke Vercel Preview | PASS previo a PR/merge |

QA de escrituras: solo Supabase local/aislado hasta autorización explícita. En Cloud usar inicialmente consultas de lectura y los códigos Makro Test mencionados en `2. No crear datos ficticios en producción durante 9C.6-A.

## 12. Decisiones pendientes (para aprobación de producto)

| Código | Decisión | Recomendación |
|---|---|---|
| **D1** | Roles de lectura y dependencias | Lectura owner/admin/manager/requester con `work_orders.view` + `requests.view`; technician/viewer fuera inicialmente |
| **D2** | Gestión de OT interna | Solo prioridad + fechas en OT no terminal; sin cambio de estado, técnicos ni planner |
| **D3** | Crear OT como representante del cliente | Permitir desde cotización aprobada y solicitud interna, con RPCs separadas, idempotencia y permisos estrictos; decidir si incluir en esta entrega |
| **D4** | Seguimiento externo | Notas del lado cliente en entidad separada, sin editar ni filtrar datos internos del proveedor |
| **D5** | Ver importe de OT externa | Solo `quotes.view` y precio verdaderamente visible según la regla de 9C.5; esconder textos libres sensibles bajo el mismo gate |
| **D6** | Acceso a nombre del proveedor y evidencias | Nombre comercial solo si permitido; informes/evidencias internas excluidos del contrato inicial |
| **D7** | Cierre de OT interna por FM | No incluido inicialmente. Evaluar acción separada tras completar, nunca actualización indiscriminada de estado |

**APROBADO:** D1–D7 en su alcance y restricciones según esta tabla; su implementación se realizará por etapas. Esta aprobación funcional **no autoriza** desplegar una migración sin pruebas previas ni ejecutar escrituras de OT en Cloud. 9C.6-B1 es estrictamente de lectura.

## 13. Secuencia recomendada de entrega

- **9C.6-A (actual):** auditoría y contrato, aprobar D1–D7.
- **9C.6-B1:** acceso de lectura, DTO, list/detail y pgTAP de seguridad/ACL; sin escritura FM.
- **9C.6-C1:** interfaz delegada solo lectura, filtros, enlaces profundos, estado/precios seguros.
- **9C.6-B2/C2:** únicamente operaciones de gestión explícitamente aprobadas en D2–D4, con transacciones, concurrencia y auditoría.
- **9C.6-D:** pruebas completas locales, Vercel Preview, respaldo y despliegue secuenciado Supabase → GitHub → Vercel Production, QA real con FM sin membresía de cliente.
- **9C.7:** reportes agregados delegados como módulo independiente; no abrir prematuramente `get_activity_reports_for_work_order`.

## 14. Evidencia de auditoría (origen)

Repositorio GitHub, commit base `729bb381`:
- `src/hooks/useWorkOrders.ts`, `src/components/work-orders/WorkOrdersList.tsx`, `WorkOrderDetailDialog.tsx`, `src/pages/Dashboard.tsx`.
- `src/components/facility-management/DelegatedModules.tsx`, `src/lib/facilityManagement.ts`.
- `docs/WORK_ORDER_ACTIVITIES.md`, `docs/MINIMAL_INVENTORY_MATERIALS.md`, `docs/FACILITY_MANAGER_DELEGATED_PERMISSIONS.md`.

Supabase Cloud (lecturas SQL; 2026-11-07):
- Catálogo de columnas de `work_orders`, `work_order_activities`, `work_order_materials`, `work_order_activity_reports` y tablas relacionadas.
- `pg_policies` para las tablas de OT y `pg_proc` para las RPCs de planificación, ejecución, lectura y creación.
- Agregados de OT por tipo/estado; relación Makro Test → FM QA Test y concesiones OT.
- Solo una etapa de diseño: no se ejecutó SQL DDL/DML ni se modificó GitHub Productivo.

**Resultado 9C.6-A:** contrato **aprobado funcionalmente (D1–D7)**. 9C.6-B1 en rama, sujeto a pgTAP local/QA de seguridad, revisión y despliegue controlado posterior.