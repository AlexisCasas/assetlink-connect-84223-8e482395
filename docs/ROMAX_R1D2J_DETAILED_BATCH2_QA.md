# ROMAX R1-D2J — Segundo lote detallado y QA (14-nov-2026, Lima)

## Objetivo y alcance
Homologación por inspección de ocho páginas de tres propuestas económicas pendientes, conservando exactamente la distinción entre subtotal de encabezado y subpartidas (no se contabilizan ambas como cargos independientes). La fuente autoritativa de los precios y de la redacción es cada PDF original privado en Google Drive; este documento público conserva únicamente evidencias de estructura y conciliación, sin republicar tarifas ni texto comercial completo.

Fuentes revisadas, identificadas por **ID de documento en Supabase y archivo de Google Drive**:
1. **RMX-2026-0212, IN RETAIL / PLAZA CENTER, Higuereta**. Fuente Drive `1gnk0sO__oucYXPLh7FUyILg6nbCQoCDJ`, 4 páginas. No confundir con el otro 0212 de Cassinelli Piura: se usan `history_id` y `source_file_id`, no el correlativo para unir registros. Presenta tres encabezados económicos: **MATERIALES** (14 detalles), **MANO DE OBRA** (6 detalles) y **GASTOS ADICIONALES** (3 detalles); cada encabezado contiene su propio subtotal, no un cargo adicional.
2. **RMX-2026-4071, Cassinelli Ate**, fuente Drive `1qZAXuvGQ_Yt43rS3Ujet5O1wo6FZe_6a`, 2 páginas. Un encabezado económico **OBSERVACIONES ITSE** seguido de 18 detalles valorados. Se mantienen dos ítems con descripciones idénticas donde así aparecen en el PDF; no se deduplican.
3. **RMX-2026-4085, Cassinelli / HMC VES**, fuente Drive `1hWQpoexu51_KTz9EuG21A4hhVS1sty7_`, 2 páginas. Cinco actividades valoradas bajo tres encabezados descriptivos (**TRABAJOS PRELIMINARES Y DESMONTAJE**, **ADECUACIÓN Y ANULACIÓN DE CONEXIONES ELÉCTRICAS**, **REINSTALACIÓN Y VERIFICACIÓN FINAL**). Los encabezados no tienen precios individuales ni se crean partidas adicionales con el total de la propuesta. Conservados como encabezados narrativos y números originales 1.01/2.01/2.02/3.01/3.02.

## Ejecución
- Inserción de los datos estructurados en tablas existentes `commercial_quote_history_line_items`, `commercial_quote_history_sections` y `commercial_quote_history_cost_components`.
- Protección transaccional de cada importación: tenant y cabecera documental coincidentes, `source_file_id` inequívoco, y ausencia de cualquier detalle económico/narrativo previamente cargado; fallo de alguna condición abortaría la operación completa.
- 0212 Higuereta: 26 filas (tres grupos, 23 detalles), 4 secciones, 6 componentes.
- 4071 Ate: 19 filas (un grupo y 18 detalles), 4 secciones, 3 componentes.
- 4085 HMC VES: 5 filas valoradas, 5 secciones (incluye bloque narrativo de alcance), 3 componentes.
- **Total R1-D2J: 50 filas, 13 secciones, 12 componentes**. Todos los datos nuevos permanecen en `extracted_unverified`. Un estado de extracción y un cotejo de PDF no acreditan tarifa aprobada ni adjudicación.
- Mantener nulos los campos originalmente vacíos: por ejemplo, forma de pago no especificada en 4071 y 4085; no inventar condiciones.

## QA posterior a escritura
Consultas independientes de SQL agregaron líneas y componentes por separado para evitar multiplicar importes en joins. Se verificó cada historial por documento fuente, evitando la colisión del correlativo 0212.

| Control | Resultado |
|---|---|
| Fuente y cabecera encontradas correctamente | 3/3 PASS |
| Recuento de filas, secciones y componentes | 50 / 13 / 12 |
| Suma de subpartidas vs subtotal económico documental | 3/3 PASS |
| Suma de grupos económicos vs neto, cuando hay grupos valorizados | 2/2 PASS |
| Neto + IGV vs importe bruto en cada documento | 3/3 PASS |
| Errores cantidad × precio unitario vs parcial en filas completas | 0 |
| Descuadres entre organization_id en líneas, secciones, componentes y cabecera | 0 |
| Nuevas filas indebidamente promocionadas a estado verificado | 0 |
| Histórico, PDF y extractos originales | 25 / 25 / 25, sin cambios |
| Solicitudes y cotizaciones operativas | 33 / 22, sin cambios |
| Progreso acumulado | **22/25 cotizaciones estructuradas (88 %)** |
| Acumulados de detalle | **173 partidas, 85 secciones y 97 componentes** |

**Excepciones y controles pendientes:** no se ejecutó prueba de lectura con una sesión autenticada real de organización ajena, ni prueba visual del frontend/productivo; por tanto, no se marca PASS de esas pruebas. Los tres restantes requieren clasificación específica antes de importar: RMX-2026-4080 (formato clásico de costos), RMX-2026-5076 (por metraje/cantidades) y RMX-2026-5152 (mixto con grupos y cantidades). No se modificaron Drive, RLS, esquema, migraciones, cotizaciones operativas ni frontend. El correctivo visual R1-D2I-FIX continúa como trabajo separado y no se declara desplegado en producción por este lote.
