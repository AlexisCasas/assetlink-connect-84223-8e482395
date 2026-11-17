# ROMAX R2C — Registro de tarifas: diseño e implementación inicial

**Estado:** interfaz implementada en la rama de trabajo; pendiente de build de preview y QA con sesión ROMAX. Sin merge ni producción.

## 1. Alcance

R2C permite registrar una tarifa de costo para un recurso existente, con proveedor opcional:
- Recurso y unidad.
- Proveedor opcional; vacío representa costo interno.
- Moneda original PEN o USD.
- Costo unitario original.
- Conversión a PEN con snapshot de tipo de cambio.
- Fuente del costo y referencia documental (texto/referencia; no implica carga de archivo).
- Tratamiento tributario y tasa opcional.
- Vigencia desde y hasta opcional.
- Alta inicial como `pending_review`; la aprobación/rechazo se implementa en R2D.

## 2. Tipo de cambio predeterminado

Se incorpora una sección para configurar el tipo de cambio USD/PEN de la organización:
- Solo owner/admin/manager pueden crear o actualizarlo.
- Exige valor positivo y fecha.
- Guarda fuente `manual` y referencia opcional.
- No se inicializa ni inventa un valor; ROMAX debe ingresar uno.
- Una tarifa USD puede usar ese valor predeterminado (`organization_default`) y el trigger copia tasa, fecha y referencia a la tarifa.
- También se permite registrar una tasa manual fechada para una tarifa individual.
- PEN siempre usa FX=1 y `not_required`.

## 3. Reglas de registro

- Cada alta inserta una nueva fila; la base asigna automáticamente el número de versión.
- Las tarifas se registran como `pending_review`; no se autoaprueban.
- Una tarifa aprobada no se edita; las correcciones crean una nueva versión, previa gestión de vigencia.
- El proveedor puede quedar vacío para costos internos.
- El costo PEN mostrado procede de la columna generada `unit_cost_pen`; no se modifica el precio de venta ni las cotizaciones históricas.
- La interfaz lista también recursos/proveedores inactivos asociados a tarifas antiguas, pero solo ofrece recursos/proveedores activos para nuevas tarifas.
- No se carga el archivo fuente en Storage en esta fase; se guarda una referencia documental.

## 4. Implementación

- Nuevo componente: `src/components/provider/CostRatesPanel.tsx`.
- Integración como pestaña **Tarifas** dentro de `CostCatalogView`.
- Se reutilizan las tablas R2A ya aplicadas: `provider_cost_rates`, `provider_cost_settings`, `provider_cost_items`, `provider_cost_suppliers` y `provider_cost_units`.
- No requiere migración adicional de Supabase.
- No se han insertado tarifas ni configurado el FX de ROMAX.

## 5. QA / despliegue

- La vista previa R2B anterior sigue READY y fue confirmada por el usuario.
- Para el commit que integra la pestaña Tarifas, el check de Vercel devolvió `build-rate-limit`; no hay un build READY que incluya R2C.
- Por esa razón no se declara compilación ni QA de R2C. No se hizo retry ni despliegue manual para evitar más solicitudes mientras Vercel bloquea por límite de builds.
- Pendiente: build de preview, QA autenticado de configuración FX, tarifa PEN, tarifa USD manual, tarifa USD con FX predeterminado, costo interno, proveedor, versionado y estado pending_review.
- No merge, no despliegue de producción.

## 6. Datos ROMAX confirmados antes de R2C

- 1 proveedor activo: Proveedor Test.
- 1 recurso activo: Material Test 001 (PR001, MATERIAL, UND).
- 0 tarifas.
- 0 settings de tipo de cambio.
