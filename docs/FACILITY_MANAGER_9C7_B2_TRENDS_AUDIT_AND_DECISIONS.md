# One Facility — 9C.7-B2/C2-A1 | Contrato para tendencias e indicadores históricos

**Fecha de auditoría:** 2026-11-10.  
**Estado:** AUDITORÍA A1 COMPLETADA / **D8–D15 APROBADAS por el responsable del proyecto (2026-11-10)**. Autoriza desarrollo de B2/C2 y QA aislado; no autoriza migraciones a Cloud, permisos permanentes, merge ni Production.  
**Rama base:** `productization/mvp` commit `7369c90c68e20838092150b75122aed480d6f6d5`.  
**Límites:** Solo inspección GitHub y consultas SELECT a Supabase Cloud; **sin** migraciones, grants, escritura en tablas, merge, ni despliegue.

## 1. Punto de partida y continuidad

La versión 9C.7 V1 está cerrada: contrato D1–D7, backend B1 en Cloud, frontend C1 en Vercel Production, QA positivo/negativo y revocación del permiso de prueba PASS. Los PR #89, #90 y #91 están fusionados.

- B1 `get_facility_management_client_metrics(client_id, relationship_id)`: ámbito exacto cliente–relación FM; `reports.view` obligatorio; OT protegidas además por `requests.view + work_orders.view`; solicitudes por `requests.view`; activos por `assets.view`. Secciones sin permiso = **null** y `availability=false`, nunca cero.
- C1 `DelegatedClientMetricsView`: inventario actual de OT, solicitudes, activos; explícitamente no ofrece tendencias ni SLA. Acceso por `managed-reports`, caché separada por usuario, FM, relación y cliente.
- Cloud al cierre de la auditoría: **0 grants `reports.view`**, **0 grants `work_orders.manage`**. No reabrir D3/D4 ni modificar usuarios.
- Permiso permanente **ya es gestionable por el cliente** en `ClientFacilityManagersView → FacilityManagementPermissionsEditor`; se ofrece con la etiqueta «Ver reportes» (`reports.view`) y la RPC `set_facility_management_permissions` de reemplazo atómico. El equipo FM asignado también debe seguir activo; conceder reportes no sustituye permisos de datos. **No hace falta implementar un acceso privilegiado nuevo ni concederlo automáticamente**.

## 2. Evidencia de capacidad histórica real — Makro Test

Corte SELECT en Cloud 2026-11-10 23:32 UTC (los datos cambian; no utilizar como fixture fija):

| Dato | Observación verificable |
|---|---|
| OT elegibles del cliente | 23, creadas entre **2026-08-17 y 2026-09-21 UTC** |
| OT creadas por mes local Perú | Agosto 2026: **20**; septiembre: **3** |
| OT con `completed_at` | **14/23**; agosto: **9**, septiembre: **5** |
| OT en estado completed/closed sin `completed_at` | **0**; completadas con estado no final: **0** |
| OT con `started_at` | **18/23**, pero no equivale a historia completa de estados |
| Solicitudes del cliente | **25**; agosto: **20**, septiembre: **5** |
| Backlog | **4 avisos**, de los cuales **2** siguen open/triaged; tienen `reported_at` |
| Cotizaciones | **16** (15 approved, 1 submitted), pero datos privados económicos: **NO exponer** |
| `audit_logs` | Solo **2** filas ligadas a `work_orders`; **0** a `requests`, cobertura insuficiente para reconstruir cada transición histórica |

La tabla `work_orders` tiene `created_at`, `started_at`, `completed_at`, `due_at`, `cancelled_at`, `status`; `requests` tiene `created_at` y `updated_at`. **No existen snapshots de estado por fecha** ni auditoría completa de las transiciones. Por tanto:
- **Sí**: OT creadas y OT finalizadas **durante** un período mediante fechas de evento verificables, solicitudes creadas durante un período.
- **No**: número de OT abiertas/vencidas en cada fecha pasada, «% SLA histórico», evolución de stock de activos o tasas de cumplimiento sin eventos/snapshots confiables.
- Una gráfica «últimos 30 días» mostrará ceros en Makro Test aunque el inventario tenga 23 OT: los registros del piloto datan de agosto/septiembre. Mostrar esos ceros como reales si el filtro es visible, no rellenarlos con datos inventados.

### Calidad temporal y zona horaria
`organizations` **no tiene campo de timezone**. El cálculo de día/mes debe informar la zona usada y el filtro debe ser consistente con esa misma zona (incluidos medianoche y cambios de horario). Para el piloto peruano usar `America/Lima` **expresamente visible**, sin anunciarlo como estándar global; definir modelo de zona por organización antes de habilitar globalmente clientes de otros husos.

## 3. Contrato D8–D15 APROBADO (9C.7-B2-A2)

| ID | Decisión propuesta | Fundamento / límite |
|---|---|---|
| **D8 — Alcance** | B2 y C2 trabajan **un cliente y una relación FM por consulta**. Prohibir portafolio global y cruces implícitos; mantener B1/V1 intactos. | Continuidad D1–D4 y cero fuga multicliente |
| **D9 — Fechas** | Filtro `desde/hasta` de fechas calendario inclusivas, presets **30/90/180 días** (90 por defecto), tope **366 días**, `desde<=hasta`, zona explícita **America/Lima para piloto PE**, serie diaria; mensual como visual derivada, no como semántica nueva. | Evita períodos ilimitados, ambigüedad UTC e históricos falsos |
| **D10 — Flujos OT** | `ot_creadas` cuenta `work_orders.created_at`; `ot_finalizadas` cuenta `completed_at` no nulo. Solo OT con `client_organization_id` del cliente y `request_id` válida de ese cliente, excluyendo solicitudes draft/anuladas (igual que B1). `completed_at` es evento, no estado actual. | Criterios reproducibles; no usar `updated_at` como evento de cierre |
| **D11 — Solicitudes** | `solicitudes_creadas` desde `requests.created_at` bajo el cliente. Solo requieren `requests.view`. OT requieren **`requests.view + work_orders.view`** y todo requiere **`reports.view`** con las verificaciones completas de la misma relación. | Permisos por sección, ninguna inferencia de acceso |
| **D12 — No inventar historia** | **NO** generar series de abiertas/vencidas históricas, SLA, antigüedad en cada día, activos históricos, tiempo medio de solución ni porcentaje de cumplimiento en B2. Mantener las tarjetas de B1 identificadas como «estado actual». | No existe historial completo de transición y no se debe sustituir con el estado presente |
| **D13 — RPC nueva y DTO mínimo** | Añadir RPC de **solo lectura** `get_facility_management_client_trends(client_id uuid, relationship_id uuid, start_date date, end_date date, time_zone text)`; validación server-side del alcance, roles, grants, rango, zona admitida, output con `as_of`, zona, fechas y secciones: `work_orders.daily[{date,created,completed}]` y `requests.daily[{date,created}]`. Series de fechas completas con ceros **solo si la sección es autorizada**; si no, `null/unavailable`. Sin filas/UUIDs/identificadores, importes, proveedores, técnicos, notas, textos privados. | DTO acotado, sin cambiar la firma existente B1 |
| **D14 — UI y QA** | C2 con selector de periodo y gráficas/tabla accesible, estado vacío veraz, fecha/fecha de corte y zona horaria visibles. Query key por usuario+FM+relación+cliente+fechas+zona; invalidación al cambiar, nada cacheado visible entre clientes. CI pgTAP de DST/fronteras, período inválido, períodos sin filas, dos FM del mismo cliente, ACL, revocación, rangos, exactitud de agregados, sin fuga de DTO; CI TypeScript/lint/build y Vercel Preview. | Prevenir valores engañosos y regresiones multi-tenant |
| **D15 — Fuera de alcance / gates** | Avisos/backlog actuales, cotizaciones por conteo, exportaciones, snapshots históricos, SLA y consolidado de varios clientes quedan **para incrementos posteriores** tras contrato específico. Ninguna migración Cloud, merge, grant permanente o despliegue Production sin revisión y autorización separada. | La iteración B2/C2 se limita al histórico verificado |

**Zona:** En el piloto, aceptar solo `America/Lima` explícito desde el servidor/allowlist para evitar husos arbitrarios sin contrato. La fecha de fin seleccionada es inclusiva a nivel UI; en SQL el límite superior es **medianoche local del día siguiente, exclusivo** convertido a instante UTC. El agrupamiento diario debe aplicar el mismo huso, incluso cerca de los límites UTC. La UI deberá rotular la cobertura como **«Perú (America/Lima)»**, no «hora local de todos los clientes».

## 4. Puertas de seguridad para un desarrollo B2

1. Usar la misma autorización real de B1: `auth.uid()`, cliente y FM activos, vínculo activo de tipo FM, miembro FM asignado y activo en rol owner/admin/manager, `reports.view` de la misma relación; permisos por sección. **No** mirar solo el rol del frontend ni filtrar datos luego de leer indiscriminadamente.
2. Si se implementa `SECURITY DEFINER`, repetir defensa estricta: `search_path=''`, referencias fully-qualified, `EXECUTE` solo para `authenticated`, prohibir PUBLIC/anon/service_role, `statement_timeout` bajo, revisar advisors. Reutilizar predicados del contrato B1 sin abrir `get_dashboard_metrics` al FM.
3. Fechas inválidas o >366 días retornan error de validación **antes de agregaciones**. Un UUID de cliente o relación ajena retorna la misma denegación `42501` para impedir enumeración.
4. pgTAP con casos agosto y septiembre, límites `2026-08-31 23:59:59 America/Lima` vs septiembre, 0 registros y `null` por grant ausente; cero filas con categoría no autorizada. No hardcodear los conteos de Makro como fixtures.
5. No crear OT de prueba en Cloud. No cargar reportes históricos sintéticos a Production. Toda prueba positiva Cloud requiere autorización temporal específica, reversión comprobada y monitoreo de integridad.

## 5. Corrección de UX identificada, independiente de permisos

`src/components/facility-management/ClientFacilityManagersView.tsx` aún muestra en el modal de permisos: «El acceso a los módulos todavía no está habilitado en esta versión». Eso **ya es falso**: existen módulos FM delegados y dashboard C1. Durante C2, reemplazar por un texto neutral, por ejemplo:
> «Los permisos se administran por cliente. Cada módulo requiere sus permisos específicos y la asignación del equipo del Facility Manager.»

Esta corrección es **solo texto**. No modifica `setPermissions`, roles, datos ni autorizaciones. Incorporar test de regresión.

## 6. Secuencia y control de salida

- **B2-A1 (este PR Draft)**: auditoría temporal y D8–D15 propuestos; QA solo lectura completado.
- **B2-A2**: responsable del proyecto aprueba o ajusta D8–D15 (incluida zona y rango).
- **B2-B1**: migración creada por Supabase CLI para **RPC nueva** y pruebas pgTAP en base descartable. Mantener `get_facility_management_client_metrics` intacta.
- **C2-C1**: frontend períodos/series/gráficos/tabla con rutas actuales y texto de permisos corregido; PR independiente y Preview.
- **D3**: autorizaciones separadas para migración Cloud, QA positivo/negativo con permission `reports.view`, merge y Production; revocación de QA al terminar.
- **Permisos permanentes del cliente**: se gestionan desde la UI ya existente, **sin concesión automática y sin suplantar la aprobación del cliente**. Mantener cero `reports.view` en FM QA Test hasta autorización explícita.

### Criterios de aceptación B2/C2
Para una relación FM con `reports.view + requests.view + work_orders.view`, el período agosto/septiembre 2026 del piloto debe mostrar 23 OT creadas y 14 completadas (solo si rango contiene todas sus fechas y la fuente sigue igual). Para una relación sin grants: error 42501 o sección `null`, nunca cero por denegación. Solicitudes por período requieren permiso `requests.view` y no dependen de OT. La serie de fechas sin eventos devuelve cero *autorizado*. Sin precios, actividad del proveedor, historiales falsos ni escritura.

## 7. Referencias
- `docs/FACILITY_MANAGER_REPORTS_9C7_A1_AUDIT.md` (D1–D7 aprobadas).
- `supabase/migrations/20261110224618_fm_delegated_client_metrics.sql` (B1 V1).
- `src/components/facility-management/DelegatedClientMetricsView.tsx` (C1 V1).
- `src/components/facility-management/ClientFacilityManagersView.tsx` y `FacilityManagementPermissionsEditor.tsx` (grants administrados por cliente).
- [9C.7 cierre V1](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/pull/91#issuecomment-6782073955).

**NO-GO:** presentar cifras de esta auditoría como métricas disponibles en la app, interpretar la aprobación de D8–D15 como autorización de despliegue, conceder `reports.view` de manera permanente sin acto del cliente, migrar Cloud, fusionar este PR o desplegar una pantalla todavía inexistente.
