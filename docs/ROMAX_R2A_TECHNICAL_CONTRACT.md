# ROMAX R2A — Contrato técnico del catálogo independiente de costos

**Fecha:** 17-nov-2026  
**Estado:** diseño funcional aprobado; implementación en rama aislada.  
**Base de referencia:** One Facility / Supabase PostgreSQL 17.6.  
**Producción:** sin migraciones aplicadas, sin registros insertados, sin cambios en Vercel.

## 1. Decisiones de negocio aprobadas

- Fuentes de costos mixtas: proveedores y costos internos de ROMAX.
- Costo interno y precio de venta separados.
- Revisión humana antes de activar una tarifa.
- La misma persona puede registrar y aprobar si posee un rol autorizado.
- Una tarifa aprobada puede quedar sin fecha de vencimiento.
- Un recurso puede tener varios proveedores y alternativas de costo.
- Moneda original PEN/USD conservada; toda tarifa USD guarda un tipo de cambio snapshot y su conversión a PEN.
- Clientes, sedes y contactos se reutilizan desde `commercial_clients`, `commercial_client_sites` y `commercial_client_contacts`. No se duplican.
- El catálogo de costos no depende del cliente ni de la sede.
- El inventario (`materials`, `warehouses`, `work_order_materials`) permanece independiente.
- El histórico ROMAX (25 documentos, partidas y componentes) es referencia histórica, no un tarifario vigente.
- Las proyecciones de costos por oportunidad y sus versiones se reservan para R4; no se crean tablas de proyección en R2.

## 2. Modelo reducido: seis tablas

| Migración | Tablas | Responsabilidad |
|---|---|---|
| R2-M1 | `provider_cost_categories`, `provider_cost_units`, `provider_cost_settings` | Clasificaciones globales y configuración PEN/USD por organización |
| R2-M2 | `provider_cost_suppliers`, `provider_cost_items` | Proveedores y recursos reutilizables |
| R2-M3 | `provider_cost_rates` | Tarifas, versiones, fuente, vigencia, conversión y aprobación |

No se crea tabla independiente de clientes, contactos de proveedores, fuentes documentales, aprobaciones o proyecciones en esta entrega. La procedencia se guarda en cada tarifa y la aprobación se registra en la misma fila.

## 3. R2-M1 — Catálogos y configuración

### provider_cost_categories
Catálogo global, administrado por migraciones y de solo lectura para usuarios:
- LABOR (direct)
- MATERIAL (direct)
- EQUIPMENT (direct)
- SUBCONTRACT (direct)
- MOBILIZATION (direct)
- DEMOBILIZATION (direct)
- OTHER_DIRECT (direct)
- GENERAL_EXPENSE (indirect)

La utilidad y los impuestos no son recursos ni categorías de costo.

### provider_cost_units
Catálogo global y normalizado: UND, M, M2, M3, KG, H, DIA, JOR, GLB, VIAJE, LT, GAL y ROLLO. Los alias inequívocos se normalizan a un código canónico. La abreviatura ML es ambigua (metro lineal/mililitro) y queda fuera de la normalización automática; requiere confirmación. No se convierten unidades automáticamente.

### provider_cost_settings
Una fila por organización ROMAX, creada al configurar por primera vez:
- Moneda base PEN.
- Tipo de cambio USD/PEN predeterminado.
- Fuente, fecha y referencia del tipo de cambio.

El tipo de cambio no se fija en la migración porque ROMAX aún no ha indicado el valor numérico inicial. Mientras no esté configurado, no se podrá aprobar una tarifa USD que dependa del tipo predeterminado.

## 4. R2-M2 — Proveedores y recursos

### provider_cost_suppliers
Maestro sencillo creado bajo demanda: nombre comercial, razón social, RUC opcional, correo, teléfono, notas y estado activo. No hay tabla adicional de contactos en esta versión.

El RUC es único por organización cuando se informa. Los proveedores se desactivan, no se eliminan físicamente.

### provider_cost_items
Recurso/concepto reutilizable: código opcional, nombre, descripción, categoría, unidad predeterminada y especificación técnica. No pertenece a un cliente. Un recurso puede aparecer en cotizaciones para muchos clientes y sedes.

Categoría y unidad son referencias obligatorias a los catálogos globales.

## 5. R2-M3 — Tarifas y versiones

### provider_cost_rates
Cada fila representa una versión de costo para un recurso y un proveedor opcional:
- Recurso, proveedor opcional, unidad y versión.
- Moneda original, costo unitario original, tipo de cambio snapshot y costo convertido a PEN.
- Tratamiento tributario de origen: inclusive, exclusive, not_applicable o unknown; tasa solo cuando corresponda y expresada en puntos porcentuales (18.0000 = 18%, no 0.18).
- Fuente: supplier_quote, supplier_invoice, purchase_record, internal_cost_sheet, payroll_basis o manual.
- Referencia documental, fecha y notas.
- Vigencia desde obligatoria y hasta opcional.
- Estado draft, pending_review, approved, rejected o archived.
- created_by, reviewed_by, reviewed_at y review_note.

### Reglas de versión
- La versión se asigna en base a organización + recurso + proveedor (NULL identifica costo interno).
- La secuencia se protege con bloqueo transaccional y restricción única que trata NULL como un valor comparable.
- Una tarifa aprobada no permite editar sus valores económicos. Para actualizarla se crea una versión nueva.
- Al aprobar una nueva versión, el sistema cierra automáticamente la vigencia de una versión anterior que se solape, siempre que la anterior haya empezado antes. No se admite aprobar una tarifa retroactiva que se solape con una versión que ya comienza en esa fecha o después.
- Una versión aprobada sin fecha de fin se considera vigente hasta que sea reemplazada o se cierre su vigencia.
- La misma persona puede crear, enviar a revisión y aprobar; la identidad del aprobador y la fecha quedan registradas.
- Las tarifas rechazadas no se activan; una corrección se registra como nueva versión.

### Moneda y tipo de cambio
- PEN: factor 1, sin conversión.
- USD con tipo predeterminado: el trigger copia el tipo, fecha y referencia configurados en provider_cost_settings.
- USD con tipo documentado/manual: se exige factor positivo, fecha y referencia.
- unit_cost_pen es una columna generada a partir del costo original y el factor guardado.
- Cambiar el tipo predeterminado no modifica versiones anteriores.
- No se permite aprobar una tarifa USD si no existe un tipo de cambio completo y trazable.

### Proveedor y fuente
supplier_quote, supplier_invoice y purchase_record requieren proveedor. Los costos internos pueden usar supplier_id NULL. La fuente documental se conserva en la tarifa; no se fuerza un proveedor para mano de obra interna.

## 6. Relaciones y restricciones

- Categoría y unidad: relaciones obligatorias desde el recurso.
- Tarifa → recurso: FK compuesta por organization_id + cost_item_id.
- Tarifa → proveedor: FK compuesta por organization_id + supplier_id, opcional.
- Proveedores y recursos pertenecen a una organización activa de tipo provider_company.
- El proveedor y el recurso de una tarifa deben pertenecer a la misma organización.
- El unit_code de una tarifa debe coincidir con la unidad predeterminada del recurso; no hay conversiones silenciosas.
- El proveedor no pertenece al recurso; se vincula a la tarifa.
- No se permite cambiar el tenant de un registro.
- Los registros utilizados se desactivan/archivan; no se borran físicamente desde la aplicación.

## 7. Seguridad

- Categorías y unidades: lectura para authenticated; sin escritura desde navegador; sin acceso anon.
- Proveedores, recursos, configuración y tarifas: RLS por tenant y por roles owner, admin, manager y quote_manager.
- No se otorga acceso al catálogo interno a requester, technician, operator ni viewer por defecto.
- INSERT/UPDATE se limitan por columnas; organization_id, created_by, version_number, unit_cost_pen y datos de aprobación no son editables directamente.
- No hay política DELETE para usuarios autenticados.
- Las funciones de trigger usan search_path vacío y nombres cualificados; no usan SECURITY DEFINER.
- service_role permanece exclusivamente en backend y no se expone al cliente.

## 8. Cálculo y separación comercial

Se conservan cuatro niveles:
1. Costos directos: mano de obra, materiales, equipos, subcontratos, movilidad y desmovilización.
2. Costos indirectos: gastos generales y otros indirectos.
3. Formación de precio: utilidad/margen y ajustes autorizados.
4. Impuestos: IGV u otros aplicables.

R2 implementa el catálogo de costos, no modifica todavía el motor de cotización existente ni define el porcentaje/fórmula de utilidad. La distinción entre markup sobre costo y margen sobre venta queda para R2E.

## 9. Las tres migraciones controladas

1. R2-M1: datos de referencia y configuración económica.
2. R2-M2: proveedores y recursos.
3. R2-M3: tarifas, versionado, FX snapshot, estados y aprobación.

Cada migración tiene pruebas pgTAP en base local desechable. Se verifica RLS multiempresa, FKs compuestas, unidad, moneda, tipo de cambio, auto-cierre de vigencia, autoaprobación autorizada y no mutación de tarifas aprobadas.

## 10. No incluido

- Aplicar migraciones a Supabase Cloud.
- Insertar proveedores, recursos, tarifas o tipos de cambio reales.
- Crear pantallas R2B.
- Modificar el cotizador actual.
- Modificar inventario o cotizaciones operativas.
- Crear oportunidades, Gmail o proyecciones R4.
- Desplegar Vercel.

## 11. Gates de salida

- CI local Supabase completo y pgTAP R2 PASS.
- Sin avisos críticos de seguridad ni políticas RLS ausentes.
- Revisión de las tres migraciones y nombres de versión.
- Confirmar que el proyecto Cloud objetivo es OneFacility (`hplchnsseylngjopgbtl`) antes de cualquier aplicación remota.
- Aplicación Cloud únicamente tras autorización explícita y plan de rollback/backup revisado.

**Estado:** contrato funcional aprobado; implementación R2-M1 a R2-M3 en rama de desarrollo. Sin cambios en producción.
