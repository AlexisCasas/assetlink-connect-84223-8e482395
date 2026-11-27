# ROMAX R2-E2 — Gestión comercial de precios

**Estado:** diseño técnico propuesto; pendiente de aprobación funcional antes de implementar R2-E2.1.  
**Fecha de revisión:** 27-nov-2026.  
**Base:** workbook privado ROMAX 2026 + estado verificado de GitHub/Supabase.  
**Privacidad:** no se incluyen importes unitarios, nombres/RUC de proveedores, referencias documentales ni filas del workbook.

## 1. Objetivo y límites

Convertir el catálogo técnico R2-E1 en un catálogo comercial gobernado: costos de mercado con procedencia y vigencia, historial inmutable, cálculo determinista FII/IGV, precio de venta ROMAX versionado y aprobación humana.

La IA podrá sugerir clasificación, comparables y borradores en R4. No calcula ni aprueba importes. El cálculo económico se implementará como regla determinista y auditable.

R2-E2 no modifica inventario, órdenes de trabajo, clientes, cotizaciones operativas ni el histórico de cotizaciones PDF. No habilita automáticamente los 736 materiales preliminares para cotizar.

## 2. Evidencia extraída del workbook

Hojas inspeccionadas: Matriz materiales, Dados de Alta, Historial precios, Parámetros y Categorías.

### Matriz y altas
- 779 códigos en Matriz materiales y 779 en Dados de Alta; la conciliación de códigos ya está comprobada en R2-E1.3.
- 245 filas con costo de mercado con IGV y 245 precios ROMAX calculados; 534 filas sin costo de mercado.
- 245 filas tienen FII aplicado; tres tienen FII excepcional. Los tres valores excepcionales no tienen aprobador ni observación justificativa; uno de esos registros aparece como Activo en la matriz, aunque Aprobado por está vacío en las 779 filas.
- Estado del registro en la matriz: 5 Activo y 774 Pendiente. Esto NO equivale a aprobación comercial.
- Dados de Alta: una validación logística figura como Validado y 778 como Pendiente; las 779 decisiones del líder comercial figuran Pendiente.
- Vigencia de los costos en matriz: 778 filas con 120 días y una con 180 días. La hoja Parámetros define 180 días como vigencia predeterminada para nuevas entradas.
- Las etiquetas de vigencia de la matriz se calculan con TODAY(); las etiquetas almacenadas pueden estar desactualizadas. El sistema debe calcularlas a partir de fecha de consulta + vigencia + fecha actual.

### Historial
- 273 registros y 245 códigos de material distintos.
- Todos los registros históricos tienen vigencia de 120 días; fechas de consulta entre 2025-11-04 y 2026-09-30.
- Proveedor/tienda y referencia de evidencia están informados en los 273 registros.
- Disponibilidad, Registrado por y Validado por están vacíos en los 273 registros. No inventar esos responsables ni disponibilidad.
- La columna Variación vs. anterior no contiene una regla calculada utilizable en el workbook; el parámetro de alerta 10% existe, pero falta acordar la base exacta de comparación.

### Parámetros y fórmulas
- FII estándar por costo de mercado con IGV: [0,100) => 0.30; [100,500) => 0.30; [500,1000) => 0.20; [1000,+∞) => 0.15. Se interpreta conforme a VLOOKUP aproximado sobre límites inferiores ordenados.
- El FII excepcional sustituye al estándar si existe y está aprobado. No sumar ambos.
- IGV: 0.18.
- Vigencia predeterminada: 180 días.
- Alerta previa al vencimiento: 30 días.
- Alerta por variación: 0.10.
- Precio ROMAX con IGV = ROUND(costo de mercado con IGV * (1 + FII aplicado), 2).
- Precio ROMAX sin IGV = ROUND(precio ROMAX con IGV / (1 + IGV), 2).
- Margen S/ = precio ROMAX con IGV - costo de mercado con IGV.
- Margen sobre venta = margen / precio ROMAX con IGV.
- FII no equivale al margen porcentual sobre la venta.

**Moneda:** el workbook no tiene una columna explícita de moneda en Matriz materiales. El encabezado Margen S/. apunta a PEN, pero esto debe confirmarse antes de importar importes. No convertir ni asignar USD por inferencia.

## 3. Estado real de Supabase Cloud

Organización ROMAX, proyecto OneFacility:
- 772 recursos, incluidos los 736 recursos nuevos en estado técnico preliminar.
- 779 identidades de origen; 43 continúan en revisión de homologación.
- 11 familias y 149 subfamilias.
- 2 filas en provider_cost_rates: una approved y una rejected; ambas tienen tax_treatment='unknown' y source_type='manual'. Preservar sin reinterpretar ni sobrescribir.
- 1 proveedor y 1 fila provider_cost_settings. Existe configuración FX manual fechada 2026-11-18 sin referencia documental; no cambiarla ni reutilizarla para convertir datos del workbook sin verificar vigencia y fuente.

### Hallazgo de seguridad prioritario
La política actual provider_cost_rates_read permite SELECT a cualquier miembro de la organización mediante is_organization_member(organization_id). provider_cost_suppliers_read aplica el mismo alcance. La UI está restringida por rol, pero la API/RLS no replica esa restricción; un miembro con acceso autenticado podría consultar costos directamente.

El enum organization_member_role contiene owner, admin, manager, requester, quote_manager, technician, operator y viewer; no existen roles dedicados logistics ni commercial_lead. En consecuencia, la separación de funciones debe resolverse con capacidades explícitas por usuario, no ampliando silenciosamente el enum global.

## 4. Decisiones técnicas propuestas (D01-D12)

| ID | Decisión propuesta |
|---|---|
| D01 | Separar costo de adquisición y precio de venta ROMAX. provider_cost_rates seguirá representando costos de mercado/adquisición; una nueva tabla provider_commercial_price_versions almacenará precios ROMAX versionados. |
| D02 | Crear provider_cost_market_history como histórico append-only para los 273 antecedentes. Cada actualización crea una fila nueva; no sobrescribir ni convertir un histórico en tarifa vigente. |
| D03 | Mantener proveedor y evidencia como datos de procedencia. La identidad original de proveedor/tienda se conserva literalmente hasta conciliar proveedores; no crear proveedores duplicados por diferencias de formato. |
| D04 | Reutilizar provider_cost_rates para los costos de mercado actuales, con proveedor, unidad, moneda, tax_treatment, fuente, fecha, vigencia y estado. Ningún costo se aprueba automáticamente. |
| D05 | Crear configuración comercial versionada y tramos FII. Aplicar exactamente los cuatro tramos y el método de límite inferior del Excel; una excepción sustituye al estándar y requiere motivo y aprobación. |
| D06 | Guardar IGV como parámetro versionado (valor inicial propuesto 18%). Los costos fuente marcados “con IGV” se registran como inclusive; los dos rates existentes con tax_treatment unknown no se modifican. |
| D07 | Mantener vigencia por registro. El valor 180 días será solo el default de nuevas entradas; los históricos conservarán 120 días y los costos de matriz conservarán su vigencia original. |
| D08 | Crear capacidades explícitas por usuario: market_cost.read, market_cost.manage, market_cost.validate, commercial_price.read, commercial_price.propose, commercial_price.approve y pricing_rules.manage. Owner/admin administran concesiones; no se alterará organization_member_role. |
| D09 | Separación de funciones: analista propone; logística valida el costo de mercado; líder comercial aprueba el precio ROMAX. El usuario que propone un precio no puede aprobar ese mismo precio. |
| D10 | La habilitación para cotizar será una condición calculada: recurso técnicamente validado + costo logístico aprobado y vigente + precio ROMAX aprobado y vigente + unidad consistente. |
| D11 | No importar ni aprobar automáticamente los 245 precios ROMAX sugeridos. Los tres FII excepcionales quedan en revisión hasta documentar motivo y aprobador. Los cinco estados “Activo” del Excel no sustituyen la aprobación comercial. |
| D12 | La moneda de los importes del workbook se confirma como PEN antes de cualquier carga económica. El parámetro de variación 10% se conserva, pero la comparación (mismo proveedor vs. último costo del recurso vs. referencia de mercado) se define antes de programar la alerta. |

## 5. Modelo de datos propuesto

- **provider_cost_rates (existente):** costo de mercado actual versionado. R2-E2 endurece RLS y aprobación logística.
- **provider_cost_market_history (nuevo):** evidencia histórica inmutable; conserva código original, registro HIS, fecha, proveedor/tienda original, ciudad, costo con IGV, disponibilidad (NULL si fuente vacía), vigencia, vencimiento, referencia de evidencia y observaciones. Registrado por/validado por permanecen NULL si la fuente no los trae.
- **provider_commercial_pricing_settings (nuevo):** IGV, default de vigencia, alerta previa, umbral de variación y versión de fórmula.
- **provider_fii_bands (nuevo):** tramos estándar versionados por vigencia.
- **provider_item_fii_overrides (nuevo):** excepciones por recurso, motivo, estado y aprobación independiente.
- **provider_commercial_price_versions (nuevo):** snapshot de costo fuente, FII aplicado, IGV, precio con/sin IGV, margen, margen sobre venta, fórmula usada, vigencia y ciclo de aprobación.
- **provider_pricing_access_grants (nuevo):** capacidades por usuario y organización, concesión/revocación auditada.

No se almacena una copia de precios comerciales en provider_cost_rates. La tarifa de adquisición y el precio ROMAX permanecen separados.

## 6. Plan incremental

1. **R2-E2.1 — Seguridad y permisos:** restringir lectura de costos/proveedores a capacidades; definir concesiones por usuario; impedir que miembros sin permiso consulten importes por Data API; pruebas RLS entre roles y tenants. Sin importar precios.
2. **R2-E2.2 — Parámetros y motor determinista:** configuración IGV, tramos FII, overrides excepcionales, redondeo y versionado de fórmula; pruebas de límites 100/500/1000 y casos con/sin IGV.
3. **R2-E2.3 — Proveedores e histórico:** conciliar identidades de proveedor/tienda y cargar los 273 antecedentes en tabla append-only, conservando los campos faltantes como NULL.
4. **R2-E2.4 — Costos de mercado actuales:** preparar los 245 costos como pendientes de validación logística, preservando fuente, moneda, unidad y vigencia. Los 534 sin costo permanecen sin tarifa.
5. **R2-E2.5 — Precio ROMAX y aprobaciones:** generar propuestas deterministas, revisar los tres FII excepcionales, exigir aprobación comercial distinta del proponente y crear versiones inmutables.
6. **R2-E2.6 — Interfaz y QA:** vistas de logística y líder comercial, alertas, comparación y auditoría; permisos verificados en UI y RLS.
7. **R2-E2.7 — Habilitación para cotizar:** QA integral de elegibilidad y contrato de lectura para R4; ningún precio preliminar se usa en cotizaciones.

## 7. Gates de seguridad y calidad

- Un viewer/technician/operator sin concesión no puede leer costos, proveedores ni precios por UI ni API.
- Logistics puede registrar/validar costo si tiene la capacidad, pero no aprobar precio ROMAX salvo concesión separada.
- Commercial approver puede aprobar precio ROMAX, pero no alterar costos históricos ni las reglas FII.
- Proponente y aprobador de un precio son usuarios distintos.
- Una tarifa aprobada y un precio aprobado son inmutables en sus valores; las correcciones crean nueva versión.
- Las vigencias no se solapan en una misma serie.
- Los 273 históricos se concilian sin huérfanos ni duplicados y sin atribuir responsables inexistentes.
- Los 36 recursos originales, 772 recursos actuales y 2 rates existentes permanecen preservados.
- CI, pgTAP, advisors y QA Cloud controlado antes de importar.
- Sin merge, carga económica real ni despliegue productivo hasta gates y autorización correspondientes.

## 8. Pendientes de confirmación funcional

1. Confirmar que todos los importes de la matriz están en PEN.
2. Aprobar el modelo de capacidades por usuario para separar analista, logística y líder comercial.
3. Definir contra qué referencia se compara la variación de 10%.
4. Proporcionar/crear los usuarios ROMAX que desempeñarán logística y aprobación comercial antes de activar la segregación real.

**Estado:** R2_E2_DESIGN=PROPOSED. No se han importado los 273 históricos, los 245 costos actuales ni precios ROMAX; no se ha cambiado RLS ni se ha aplicado migración R2-E2 en Cloud.
