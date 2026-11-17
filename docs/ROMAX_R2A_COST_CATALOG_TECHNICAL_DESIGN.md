# ROMAX R2A — Contrato técnico y diseño de tres migraciones controladas

**Estado:** Implementación preparada en rama de trabajo; pendiente de ejecución en base desechable, revisión y aprobación antes de cualquier Cloud apply.  
**Rama:** `feature/romax-r2a-cost-catalog`  
**Decisiones funcionales aprobadas:** fuentes mixtas; costo y precio de venta separados; revisión humana; mano de obra por hora/jornada; vigencia sin vencimiento obligatoria; múltiples proveedores por recurso; conservar PEN/USD original y guardar conversión documentada a PEN.

## 1. Decisiones de diseño

- Se reutilizan los clientes, sedes y contactos existentes (`commercial_clients`, `commercial_client_sites`, `commercial_client_contacts`). No se crean clientes duplicados ni se enlaza un recurso a un cliente.
- El inventario (`materials`, `warehouses`, `work_order_materials`) no se reutiliza como tarifario: mantiene sus responsabilidades de almacén/stock/OT.
- El histórico (`commercial_quote_history_*`) es evidencia histórica, no tarifa vigente.
- Se crean recursos reutilizables y sus tarifas versionadas; el proveedor es opcional para costos internos y puede variar por tarifa.
- Categorías y unidades son catálogos globales de sistema; las tablas de ROMAX son tenant-scoped.
- La fuente documental se guarda directamente en la tarifa para evitar una tabla de fuentes prematura.
- La revisión se registra en la propia tarifa (`reviewed_by`, `reviewed_at`, `review_note`); no se crea una tabla de workflow en esta etapa.
- Configuración USD/PEN por organización inicia sin tipo de cambio prellenado: ROMAX debe establecer el primer valor y su fecha/fuente. No se inventa un valor.
- `unit_cost_pen` es un snapshot generado y redondeado a dos decimales; el original y FX usados permanecen en la fila.
- Una tarifa aprobada no admite edición de importes. Solo puede cerrarse su ventana de vigencia o archivarse; una nueva tarifa crea otra versión.
- La utilidad y los impuestos no son recursos del catálogo. Se aplicarán en el motor económico posterior.

## 2. Tres migraciones

### Migración 1 — Fundación, catálogos globales y settings
`20261117130000_romax_cost_catalog_foundation.sql`

Crea:
- `provider_cost_categories`: LABOR, MATERIAL, EQUIPMENT, SUBCONTRACT, MOBILIZATION, DEMOBILIZATION, OTHER_DIRECT, GENERAL_EXPENSE.
- `provider_cost_units`: UND, M, M2, M3, KG, H, DIA, JOR, GLB, VIAJE, LT, GAL, ROLLO y aliases.
- `provider_cost_settings`: una configuración por organización proveedora, PEN base y FX USD/PEN opcional.

Seguridad:
- Categorías/unidades: lectura autenticada; escritura por migración.
- Settings: lectura para miembros; alta/cambio para owner/admin/manager.
- Clave organization_id no se expone como columna actualizable.
- No se inicializa un tipo de cambio arbitrario.

### Migración 2 — Proveedores y recursos
`20261117130100_romax_cost_catalog_entities.sql`

Crea:
- `provider_cost_suppliers`: proveedor sencillo, RUC opcional, contacto básico, notas y estado.
- `provider_cost_items`: recurso/concepto, categoría, unidad predeterminada, código opcional y especificación técnica.

Seguridad:
- FK compuestas para garantizar tenant.
- RUC y código únicos por organización cuando existen.
- Owner/admin/manager/quote_manager pueden crear/editar.
- No hay hard delete desde authenticated.
- organization_id y created_by no son columnas actualizables.
- Proveedores no obligatorios para recursos/tarifas internos.

### Migración 3 — Tarifas, versiones y aprobación básica
`20261117130200_romax_cost_rates_versioning.sql`

Crea:
- `provider_cost_rates`: recurso, proveedor opcional, unidad, moneda, costo original, snapshot FX, PEN calculado, tratamiento tributario, fuente, vigencia, estado y revisión.

Reglas:
- Estados draft, pending_review, approved, rejected, archived.
- Versión asignada en trigger bajo advisory transaction lock; unicidad por organización/recurso/proveedor/versión, considerando proveedor NULL como una serie.
- USD con `organization_default` toma automáticamente FX, fecha y referencia de settings y falla si no hay configuración fechada; USD manual exige FX positivo y fecha; PEN exige FX 1 y source not_required.
- Una tarifa approved requiere reviewed_by y reviewed_at.
- La transición a approved/rejected registra al usuario y hora.
- La misma persona puede registrar y aprobar si posee rol autorizado.
- Tarifas aprobadas son inmutables en importe, recurso, proveedor, unidad, moneda y fuente. Se permite cerrar valid_until o archivar con vigencia cerrada.
- Trigger impide intervalos de vigencia superpuestos en una misma serie recurso/proveedor.
- La aprobación de nueva versión requiere cerrar la vigencia anterior cuando se superponen.
- Solo roles autorizados leen/escriben el catálogo; no hay DELETE desde la aplicación.

## 3. Restricciones intencionales

- No se crea catálogo de clientes ni contactos de proveedores.
- No se crean conversiones automáticas entre unidades.
- No se actualizan tarifas históricas ni cotizaciones anteriores al cambiar FX.
- No se permite aprobar una tarifa USD sin FX fechado.
- No se publica el catálogo a otras organizaciones.
- No se integra aún el catálogo con `QuoteForm`; se conserva la lógica actual de cotizaciones.
- No se construye todavía la proyección de costos por oportunidad. Se diseña en R4/R2E posterior, con snapshot de la tarifa usada.

## 4. Pruebas preparadas

Archivo: `supabase/tests/romax_r2a_cost_catalog.test.sql` (pgTAP, transacción con ROLLBACK, base local/desechable únicamente).

21 aserciones previstas:
1. Presencia de las seis tablas.
2. Anon sin lectura y authenticated sin hard delete.
3. Owner puede crear configuración, proveedor, recurso y tarifa USD.
4. Cálculo USD 100 × FX 3.75 = PEN 375.
5. Versionado automático y coexistencia de múltiples proveedores.
6. USD sin fecha FX rechazado.
7. Autoaprobación por owner y captura de reviewer.
8. Tarifa aprobada no permite cambiar importe.
9. Cierre de vigencia permite nueva versión sin solapamiento.
10. Viewer puede leer pero no crear.
11. Otro tenant no puede leer tarifas.

**Importante:** el test está escrito, pero todavía NO se ha ejecutado. No declarar PASS hasta correr las tres migraciones y pgTAP en una base local/desechable con el mismo baseline de migraciones.

## 5. Orden de ejecución y gates

1. Revisar estáticamente SQL, grants, RLS, triggers y test.
2. Ejecutar migraciones en base local/desechable en orden 1 → 2 → 3.
3. Ejecutar pgTAP y corregir fallos.
4. Ejecutar advisors de Supabase y revisar funciones/triggers/privilegios.
5. Revisar diff final y CI.
6. Abrir/validar PR y solicitar aprobación.
7. Solo con autorización separada: aplicar migraciones en Supabase Cloud.
8. QA Cloud read-only: tablas, seeds, policies, grants, FX sin valor inventado y baseline operativo intacto.

**No ejecutado:** ninguna migración Cloud, inserción de proveedores/recursos/tarifas, actualización de inventario, integración del cotizador ni despliegue Vercel.


## Actualización de ejecución — R2A-01 (17-nov-2026)

R2A-01 ya fue aplicada en Supabase Cloud y superó sus pruebas transaccionales con ROLLBACK. Se registraron las versiones `20261117185721_romax_cost_catalog_foundation` y `20261117185936_romax_cost_catalog_foundation_hardening`. Resultado: 8 categorías, 13 unidades, RLS/grants comprobados, cero filas de configuración creadas y ningún tipo de cambio ficticio. Los dos hallazgos RLS de rendimiento y la FK sin índice fueron corregidos; queda un aviso `unused_index` esperado por tabla vacía. Informe: `docs/ROMAX_R2A_01_FOUNDATION_QA.md`.

**Estado actualizado:** R2A-01 PASS; R2A-02 y R2A-03 siguen sin aplicar. El test pgTAP de 21 aserciones global no se ejecutó porque pgTAP no está instalado en Cloud; las pruebas de esta primera migración fueron transaccionales directas y se revirtieron.


## R2A-02 — Estado de implementación

Aplicadas en Supabase Cloud las migraciones `20261117191121_romax_cost_catalog_entities` y `20261117191257_romax_cost_catalog_entities_hardening`. QA PASS: dos proveedores y un recurso creados transaccionalmente; unicidad de RUC/código; `created_by`; aislamiento multiempresa; rollback; prueba owner posterior al hardening. Conteos persistentes ROMAX: 0 proveedores y 0 recursos, intencional. RLS y grants verificados; Security Advisors sin hallazgos nuevos. Quedan avisos `unused_index` en tablas sin volumen. R2A-03 sigue pendiente. Ver `docs/ROMAX_R2A_02_SUPPLIERS_ITEMS_QA.md`.

## R2A-03 — Estado de ejecución

La tabla `provider_cost_rates` y trigger de versionado/aprobación fueron aplicados en Cloud. Migraciones registradas: `20261117193442`, `20261117193538` (guard fix) y `20261117193631` (hardening). QA transaccional PASS con ROLLBACK, cubriendo FX USD/PEN, versión 1 y 2, autoaprobación, inmutabilidad, cierre de vigencia, proveedor alternativo, costo interno, FX ausente, solapamiento y aislamiento multiempresa. Se corrigió durante QA un bug en la comparación de la columna generada `unit_cost_pen`. No hay tarifas ni otros datos comerciales persistentes; no se configuró tipo de cambio ROMAX. Ver `docs/ROMAX_R2A_03_COST_RATES_VERSIONING_QA.md`.