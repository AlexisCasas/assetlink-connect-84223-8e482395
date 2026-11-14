# ROMAX R1-D2D - Corrección visual de secciones en PDF RMX-2026-4087

**Fecha:** 14-nov-2026. **Caso:** Cassinelli, HMC Iquitos, suministro e instalación de ventiladores. **Fuente de verdad:** PDF original en Drive, página 1, visualizada por render (no transcripción lineal).

## Hallazgo

La extracción de texto del PDF devuelve las cifras y descripciones en bloques separados. La homologación R1-D2C clasificó por error los conceptos "Sistema eléctrico" y "Puesta a tierra" como **Aclaraciones técnicas** y mezcló los cuatro renglones de aclaraciones técnicas con **Soporte de gestión y entrega**. El documento original distingue claramente tres partidas económicas bajo un grupo principal "INSTALACIÓN DE VENTILADORES Y EXTRACTORES".

## Distribución corregida

| Bloque | PDF original | Modelo |
| --- | --- | --- |
| 1. Propuesta económica | Grupo de instalación de ventiladores y extractores; tres partidas, una de suministro e instalación, otra del sistema eléctrico y otra de puesta a tierra | `commercial_quote_history_line_items` 3 servicios ordenados + sección `service_scope` como título del grupo, sin duplicar partidas |
| 2. Aclaraciones técnicas | Cuatro notas 2.1 a 2.4: personal calificado, herramientas/equipos, procedimientos, pruebas | `commercial_quote_history_sections` tipo `technical` |
| 3. Consideraciones de seguridad | Seis notas 3.1 a 3.6 | `commercial_quote_history_sections` tipo `safety` |
| 4. Soporte de gestión y entrega | Seis notas 4.1 a 4.6, sobre accesos, programación, avances y cierre | `commercial_quote_history_sections` tipo `management_delivery` |
| 5. Resumen económico | Subtotal sin IGV, IGV y total de propuesta | Tres `commercial_quote_history_cost_components`: `net_total`, `tax`, `gross_total` |
| 6. Condiciones comerciales | Validez, forma de pago (casilla **sin completar**), plazo, horario, garantía | `commercial_quote_history_sections` tipo `commercial_terms` |

**NO hay una tabla independiente de materiales/consumibles** en este PDF. Sus insumos vienen incluidos en las partidas económicas y no se deben presentar como materiales adicionales o duplicar en el presupuesto.

## Criterios de calidad

- Las tres partidas económicas corresponden visualmente a renglones 1.00, 2.00 y 3.00, con unidad, cantidad, tarifa y parcial, y sus importes suman exactamente el subtotal del grupo. **Las cifras originales se guardan solo en Supabase, no en el repositorio público.**
- No usar los precios de 2026 como vigentes ni marcar `review_status=verified` automáticamente. Corroboración visual = procedencia correcta, no aprobación comercial.
- Cada partida, sección y componente de resumen tiene `source_page=1` (única página del PDF). Se preserva el PDF como evidencia.
- La sección 1 aparece una sola vez como tabla con título de grupo, y la sección 5 se muestra una vez como resumen financiero. Evitar que `HistoricalQuoteSections` duplique ambas como notas narrativas.
- Aclaraciones técnicas **no contienen** el detalle pagado de sistema eléctrico ni puesta a tierra: esos conceptos están en las filas 2 y 3 de la tabla económica.
- No marcar "forma de pago" como completada: en el PDF esa casilla está vacía.
- Mantener el resto de secciones independientes, incluyendo seguridad y condiciones aunque su redacción se repita en otros documentos.
- Los demás 24 documentos no cambian y no se inventan materiales o conceptos faltantes.

## QA de aceptación

| Código | Validación |
| --- | --- |
| V1 | PDF visual de una página: grupo y tres partidas emparejados con cantidad, unidad, precio y parcial |
| V2 | Suma de las tres partidas coincide con subtotal del grupo y con resumen neto |
| V3 | IGV y total concilian |
| V4 | Aclaraciones técnicas tiene exclusivamente notas 2.1–2.4 |
| V5 | Soporte de gestión conserva exclusivamente notas 4.1–4.6 |
| V6 | Seguridad y condiciones comerciales separadas; pago vacío no rellenado |
| V7 | Sin materiales duplicados, título de grupo visible y sin resumen económico duplicado |
| V8 | RLS: ROMAX puede consultar; otra organización no |
| V9 | No se crean cotizaciones operativas ni se alteran otros documentos |
| V10 | CI frontend, regresión y Vercel Preview PASS antes de merge/deploy |

**Continuidad:** consultar también `docs/ROMAX_R1D2C_PILOT_QA.md` y `docs/ROMAX_PILOT_MASTER_PLAN.md`. Para futuros formatos, revisar el PDF renderizado o archivo Excel específico antes de distribuir tarifas entre actividades.