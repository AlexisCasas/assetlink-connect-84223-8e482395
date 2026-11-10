# One Facility — 9C.7-A1: auditoría y contrato propuesto de reportes delegados

**Fecha:** 2026-11-10  
**Estado:** A1 AUDITORÍA COMPLETADA / D1–D7 PROPUESTAS (NO aprobadas todavía).  
**Base auditada:** `productization/mvp`, merge 9C.6-D `4ca3e68c4b2e83f989f2fbdb326563afae7b4c8a`.  
**Entorno:** Supabase Cloud One Facility, auditoría exclusivamente SELECT / transacciones revertidas. No migración, no GRANT, no despliegue.

## 1. Hallazgo central

El dashboard existente **no implementa acceso delegado FM**.

- `src/pages/Dashboard.tsx` + `src/components/dashboard/DashboardMetricsCards.tsx` + `src/hooks/useDashboardMetrics.ts` usan `get_dashboard_metrics(p_organization_id)`.
- Esa RPC **requiere** `has_organization_role(p_organization_id, [owner,admin,manager])` o platform_admin; no comprueba la relación FM ni `reports.view`. Un FM asignado, sin membresía directa del cliente, fue **denegado** al invocarla para Makro Test, aunque `get_facility_management_work_orders` sí le devolvió 23 órdenes (`BEGIN/SET LOCAL ROLE authenticated/ROLLBACK`, PASS).
- Además, `get_dashboard_metrics` cuenta OT operadoras con `provider_organization_id = p_organization_id`. En 9C.7 se necesitan OT del **cliente** (`client_organization_id`) y solo las elegibles según las reglas de `get_facility_management_work_orders`. Reutilizarla produciría indicadores incorrectos aun si se ampliaran sus roles.
- `get_efficiency_activity_metrics`, `get_efficiency_summary` y `get_activity_reports_for_work_order` pertenecen al dominio **operador/proveedor**. No reutilizarlas en 9C.7 para saltarse permisos ni exponer trabajo, materiales, horas por técnico o evidencias.
- Existe el permiso `reports.view` en el enum `public.facility_management_permission`, pero **NO** está concedido a la única relación FM activa (Makro Test → FM QA Test). No modificar el contrato de permisos sin aprobación del cliente.

## 2. Inventario reproducible: Makro Test (2026-11-10)

| Fuente | Conteos en Cloud | Campos/advertencias |
|---|---:|---|
| `work_orders` (por `client_organization_id`) | **23**: 15 externas, 8 internas | Estados: 3 pending, 2 assigned, 4 in_progress, 9 completed, 5 closed |
| OT abiertas | **9** | pending + assigned + in_progress; todas las 9 estaban vencidas al corte de la consulta |
| OT con `due_at` | **23/23** | Vencimiento = `due_at < now()` y estado abierto. No confundir con cumplimiento histórico |
| OT con `started_at` / `completed_at` | **18 / 14** | Sin garantía de completitud en otros clientes; no calcular SLA de cierre sin contrato |
| `requests` (por `organization_id`) | **25**: 16 externas, 9 internas | 8 sent, 8 quoted, 9 completed; 25 con deadline |
| `quotes` vinculadas a solicitudes del cliente | **16**: 15 approved, 1 submitted | Importes y textos económicos sujetos a reglas de cotización; no devolverlos inicialmente |
| `assets` | **21** activas; **7** critical | Excluir status archived; requerir `assets.view` |
| `maintenance_notices` | **4**: open 1, triaged 1, converted 1, dismissed 1 | Requerir `maintenance_notices.view`; opcional en iteración posterior |
| `facility_management_work_order_followups` | **1** nota D4 de QA | Alcance por **relationship_id**; nunca agregar notas de otra relación FM |
| Relación FM | **1 activa**, 2 miembros asignados | 13 grants, 0 `reports.view`, 0 `work_orders.manage`; NO habilitar escrituras |

Estos son datos de corte, **no** esperados fijos de prueba. Las pruebas deberán cargar datos sintéticos y comparar contra agregaciones permitidas, no hardcodear `23`, `9`, `25`.

## 3. Decisiones D1–D7 propuestas (puerta funcional antes de B1)

| ID | Propuesta conservadora | Motivación / efecto |
|---|---|---|
| **D1** | 9C.7 es módulo **independiente**: «Indicadores de clientes» en contexto Facility Manager y acceso desde «Clientes administrados» | No ampliar `get_dashboard_metrics` ni alterar el dashboard del operador |
| **D2** | Acceso a cualquier reporte requiere **`reports.view` explícito** en la **misma relación FM–cliente** y rol FM `owner/admin/manager`, más miembro FM activo, asignado y relación/cliente/FM activos | `reports.view` ya existe, pero no se concede automáticamente; sin él, módulo y RPC denegados |
| **D3** | Además de D2, cada dominio exige su permiso de lectura: OT: `requests.view + work_orders.view`; solicitudes: `requests.view`; activos: `assets.view`; backlog: `maintenance_notices.view`; cotizaciones: `requests.view + quotes.view` | Un grant de reportes **no eleva** permisos de datos. Sin permiso de un dominio, la sección vuelve **null/unavailable**, nunca cero |
| **D4** | Primer corte por **cliente + relationship_id explícitos**, nunca portfolio global ni suma entre FM/clientes. No unificar información de clientes distintos de forma silenciosa | Previene fuga multi-tenant, colisiones entre varios FM para un mismo cliente y errores de caché |
| **D5** | KPI V1: total OT, abiertas, vencidas, por estado, internas/externas y solicitudes abiertas, con filtro de cliente y fecha de corte; sumar activos/criticidad solo con `assets.view`. Cotizaciones: solo **conteos permitidos**, sin precio, textos ni datos de proveedores en V1, y preferiblemente fase posterior a reglas económicas | Garantizar indicadores verificables. No presentar importes aunque la organización pueda ver una OT; las condiciones de `min_quotes` son independientes |
| **D6** | Distinguir **inventario actual** (OT abiertas/vencidas, activos, backlog) de **flujo histórico** (OT creadas/completadas en periodo). En C1 comenzar con foto actual sin selector de fecha; tendencias y SLA pasan a C2 con definiciones propias | Evita que «9 vencidas» se malinterprete como «9 se vencieron en los últimos 30 días»; no inventar SLA |
| **D7** | RPC `get_facility_management_client_metrics(_client_organization_id uuid,_relationship_id uuid)` solo lectura, salida JSONB con sección/controles de permiso, `as_of`, enteros no negativos y **sin filas, UUID de técnicos, adjuntos, notas, cifras económicas ni textos privados**. PR B1 con pgTAP, ACL estricta, ambiente descartable; Cloud/Vercel solo con autorización posterior | Server-side scope obligatorio; no agregar desde tablas en navegador ni confiar en permisos cliente JS |

**La ausencia actual de `reports.view` implica que el tablero 9C.7 debe aparecer como sin acceso a FM QA Test hasta que el cliente lo autorice expresamente.** No habilitar GRANT en esta fase.

## 4. Especificación de indicadores sugeridos para B1 (sin implementación A1)

| Clave | Fuente y criterio | Gate por dominio | Semántica |
|---|---|---|---|
| `work_orders.total` | `work_orders` WHERE client = parámetro, request perteneciente al mismo cliente y no draft/anulado (igual a B1) | `reports.view + requests.view + work_orders.view` | Inventario actual |
| `work_orders.open` | estados `pending,assigned,in_progress` | igual | Inventario actual |
| `work_orders.overdue_open` | abiertas AND `due_at IS NOT NULL AND due_at < now()` | igual | Inventario vencido hoy |
| `work_orders.by_status` | pending/assigned/in_progress/completed/closed | igual | Desglose que debe sumar total |
| `work_orders.by_type` | internal/external | igual | Desglose que debe sumar total |
| `requests.open` | `requests` WHERE organization = cliente AND status IN (sent, quoted), excluye drafts/anulados | `reports.view + requests.view` | Inventario de solicitudes enviadas sin completar |
| `assets.active` | `assets` WHERE organization = cliente AND status <> archived | `reports.view + assets.view` | Inventario |
| `assets.critical` | mismo universo + criticality = critical | igual | Inventario |
| `maintenance_notices.open` | `maintenance_notices` WHERE organization = cliente AND status IN (open, triaged), **propuesto para B2** | `reports.view + maintenance_notices.view` | Pendientes de triage/gestión |
| `quotes.*` | **B2 posterior**: solo conteos autorizados y compatibles con `min_quotes` | `reports.view + requests.view + quotes.view` | No tocar importes/titulares del proveedor |
| `efficiency.*` / `hours.*` | **FUERA V1**; requerir nuevo contrato de confidencialidad y operacionalidad | No deducir acceso de `reports.view` | No se expone por delegación |

Cualquier dimensión sin permiso se devuelve como `null` con `available=false`, nunca `0`. Cero significa **métrica visible y cero registros**. No devolver totales transversales que incluyan secciones no autorizadas.

## 5. Contrato técnico / UI planeado

- **Backend B1:** RPC de solo lectura; `SECURITY DEFINER` solo si es estrictamente necesario por RLS; `search_path=''`, referencias fully qualified; negar a `PUBLIC/anon`; `authenticated` puede invocar pero el propio servidor comprueba `auth.uid()`, rol FM, pertenencia, relación explícita, miembro asignado, estado activo, `reports.view` y grants de cada sección en **la misma relación**, no «cualquier relación con este cliente». Enumerar errores 42501 vs 22023; sin revelar si existe un cliente ajeno.
- **Frontend C1:** nueva sección por cliente `managed-reports` con contexto explícito `managedClient`; `ManagedClientGate`, tipo `FacilityManagementOperationalModule` y control `canFacilityManagerViewReports` definido por `reports.view` + rol FM válido. Tarjetas KPI con `as_of`, sin datos de ejemplo, carga/error/vacío/sin permiso diferenciados. Cache queryKey = user ID + organización FM actual + relationshipId + client ID y cancelación/invalidation al cambiar.
- **Ubicación:** botón «Ver indicadores» en la cartera FM para el cliente autorizado; no mezclar cifras con el dashboard de la organización FM. No mostrar un KPI como ceros si el usuario carece de permiso.
- **Sin escrituras:** no habilitar `work_orders.manage`, D3 de creación de OT ni escritura D4. Ningún refresh masivo, automatización cron ni vista materializada en V1.
- **Auditoría de seguridad:** pgTAP de rol válido, sin reportes.view, sin grants del dominio, relación suspendida, FM/cliente inactivo, miembro FM no asignado, usuario con dos FM, cliente ajeno por UUID, proveedor sin rol FM, mismo cliente dos FM, conteos sin fuga, no-privileged DTO, revocación inmediata, RLS, ACL y regresión de `get_dashboard_metrics` intacta.
- **QA:** contrastar RPC contra SELECT de datos sintéticos dentro de transacción local; luego prueba Cloud de lectura con `reports.view` inicialmente deshabilitado (42501); activación del permiso del cliente sólo bajo autorización y QA temporal controlado. CI frontend + Vercel Preview; merge/Production bajo gate explícito.

## 6. Secuencia 9C.7 y criterios de cierre

- **A1 — Auditoría**: este documento; PASS inspección del código, Cloud y fuentes; **sin cambios productivos**.
- **A2 — Aprobación**: D1–D7 con el alcance y la restricción de `reports.view`.
- **B1 — RPC métricas seguras**: migración versionada + pgTAP + regresiones en Supabase aislado; consulta limitada, no uso de funciones operadoras.
- **C1 — Dashboard delegado**: cards KPI V1 por cliente, navegación/contexto, con diseño responsive; Preview de Vercel.
- **D — QA y activación**: preflight, aprobación para migración Cloud, lectura denegada por defecto a FM sin `reports.view`, acceso positivo con grant explícito aprobado, revocación y verificación. Merge/deploy sólo con autorización.
- **B2/C2 (opcional, posterior)**: reportes de tendencias, rango de fechas, backlog, cotizaciones sin importes, exportación y portafolio consolidado, únicamente tras nuevo contrato de visibilidad.

**NO-GO actuales:** implementar B1 antes de decidir D1–D7, conceder `reports.view` silenciosamente, exponer datos operativos del proveedor, sumar importes por defecto, sumar varios clientes sin ámbito, probar con OT reales nuevas, aplicar migraciones/merge/desplegar por el solo hecho de presentar este A1.
