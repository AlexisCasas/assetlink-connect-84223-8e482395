# ROMAX R2A-03 — Tarifas, versiones y aprobación: Cloud QA

Fecha: 17-nov-2026. Proyecto Supabase Cloud OneFacility. Organización: ROMAX.

## Migraciones aplicadas
- `20261117193442_romax_cost_rates_versioning`: tabla de tarifas versionadas, FX snapshot, tratamiento tributario, procedencia, vigencia, estado y trigger.
- `20261117193538_romax_cost_rates_guard_fix`: corrección del trigger de inmutabilidad para excluir el campo generado `unit_cost_pen` durante cierre de vigencia.
- `20261117193631_romax_cost_rates_hardening`: índices de FKs y ajuste de política INSERT RLS para cachear `auth.uid()`.

## Funcionalidad y controles implementados
- Una tarifa se vincula a recurso, proveedor opcional, unidad, moneda, costo original, fuente y fechas.
- El tipo de cambio usado se conserva como snapshot. Para `organization_default`, el trigger obtiene tasa, fecha y referencia desde `provider_cost_settings`; si no existe configuración fechada, falla.
- El costo convertido a PEN se calcula como columna generada.
- Versionado automático serializado por organización/recurso/proveedor, incluyendo serie interna cuando supplier_id es NULL.
- Estados draft, pending_review, approved, rejected y archived.
- Aprobación/rechazo registra actor y fecha.
- Tarifa aprobada es inmutable en sus campos económicos y de identidad; permite cerrar valid_until o archivar tras cierre.
- El trigger impide aprobar intervalos superpuestos para la misma serie de recurso/proveedor.
- RLS y permisos restringen el acceso a la organización; authenticated no tiene hard delete.

## QA transaccional ejecutado en Cloud
Prueba ejecutada bajo rol authenticated y terminada con ROLLBACK:
1. Configuración FX de prueba USD/PEN 3.75.
2. Dos proveedores para un recurso, más una tarifa interna sin proveedor.
3. Alta USD 100 usando `organization_default` produjo snapshot PEN 375.
4. Primera versión asignada como 1.
5. Aprobación por el mismo usuario owner registró reviewed_by y reviewed_at.
6. Intento de alterar el costo aprobado fue rechazado.
7. Cierre de vigencia de la tarifa aprobada funcionó después de corregir el trigger.
8. Nueva versión para el mismo proveedor se asignó como versión 2.
9. Un segundo proveedor pudo tener su propia tarifa para el mismo recurso.
10. Un costo interno con supplier_id NULL pudo registrarse.
11. USD sin FX fechado fue rechazado.
12. Intento de aprobar una tarifa con vigencia solapada fue rechazado.
13. Un usuario de otra organización no pudo consultar las tarifas ROMAX.
14. La transacción completa se revirtió.

La primera pasada de QA detectó que el trigger comparaba el campo generado `unit_cost_pen` dentro de BEFORE UPDATE, bloqueando el cierre de vigencia. La transacción falló y se revirtió. Se corrigió con migración adicional y la batería se repitió con PASS.

Después del hardening se repitió un smoke test de inserción de configuración, proveedor, recurso y tarifa como owner con ROLLBACK: PASS.

## Verificación posterior
- Tabla `provider_cost_rates` con RLS habilitado.
- `anon` sin SELECT; `authenticated` sin DELETE.
- Índices de lookup, versionado, proveedor, unidad y auditoría presentes.
- Security Advisors: cero hallazgos nuevos asociados a `provider_cost_rates`.
- Performance Advisors: sin hallazgos nuevos de FK sin índice ni auth_rls_initplan; permanecen tres avisos `unused_index` en índices de auditoría/unidad, esperables en tabla sin datos.
- Tarifas persistentes ROMAX: 0.
- Proveedores persistentes ROMAX: 0.
- Recursos persistentes ROMAX: 0.
- Settings persistentes ROMAX: 0; no se configuró FX real.

## Estado de alcance
R2A-01, R2A-02 y R2A-03 aplicadas en Cloud. No se insertaron datos comerciales reales. No se modificaron clientes, sedes, contactos, inventario, histórico, solicitudes, cotizaciones operativas, frontend ni Vercel. La integración con el cotizador y la interfaz de administración quedan para siguientes incrementos.
