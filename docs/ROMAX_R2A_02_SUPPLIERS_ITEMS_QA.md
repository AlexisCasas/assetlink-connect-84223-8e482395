# ROMAX R2A-02 — Proveedores y recursos: migración Cloud y QA

Fecha: 17-nov-2026. Proyecto Supabase Cloud OneFacility. Organización: ROMAX.

## Migraciones aplicadas
- `20261117191121_romax_cost_catalog_entities`: crea `provider_cost_suppliers` y `provider_cost_items`.
- `20261117191257_romax_cost_catalog_entities_hardening`: añade índices para claves foráneas y optimiza las políticas INSERT con `(select auth.uid())`.

## Diseño implementado
- Proveedores sencillos, por organización, RUC opcional y único cuando se informa.
- Recursos reutilizables, por organización, código opcional único cuando se informa, categoría y unidad obligatorias.
- Los proveedores no son obligatorios para costos internos; la asociación con tarifas se realizará en R2A-03.
- No se duplican clientes, sedes ni contactos.
- No se reutiliza el inventario ni se altera el módulo `materials`.
- RLS habilitado y políticas de lectura/alta/edición. No hay DELETE desde `authenticated`.
- Columnas `organization_id` y `created_by` protegidas contra actualización por grants de columna.

## QA ejecutado en Supabase Cloud
Prueba transaccional bajo rol `authenticated` con rollback:
1. Owner ROMAX creó dos proveedores y un recurso.
2. `created_by` se asignó automáticamente al usuario autenticado.
3. La unicidad de RUC duplicado fue rechazada.
4. La unicidad de código duplicado fue rechazada.
5. Usuario de otra organización no pudo consultar proveedores ni recursos ROMAX.
6. La transacción se revirtió; verificación posterior confirmó 0 proveedores y 0 recursos persistidos.

Tras la migración de hardening se repitió una prueba transaccional de alta de proveedor/recurso y rollback con el owner: PASS.

Verificaciones estructurales:
- Ambas tablas con RLS habilitado y seis políticas presentes (SELECT/INSERT/UPDATE por tabla).
- `anon` no tiene SELECT.
- `authenticated` no tiene DELETE.
- Migraciones confirmadas en historial Cloud.
- Advisors Security: cero hallazgos nuevos para estas tablas.
- Advisors Performance: quedan avisos `unused_index` sobre índices recién creados en tablas sin filas. Se conservan porque cubren FKs y búsquedas previstas; se reevaluarán cuando exista volumen real.

## Estado de datos
- Proveedores ROMAX: 0.
- Recursos ROMAX: 0.
- No se insertaron datos de prueba persistentes.
- R2A-03 tarifas/versiones/aprobación no se ha aplicado.
- Sin cambios a clientes, sedes, contactos, inventario, histórico, solicitudes, cotizaciones ni Vercel.

## Resultado
R2A-02 PASS. Siguiente gate: revisar y aplicar por separado R2A-03, que incorpora tarifas, monedas, snapshot FX, versionado y aprobación.
