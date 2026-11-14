# ROMAX R1-D2C — Auditoria de compatibilidad y piloto de homologacion

**Fecha:** 14-nov-2026. **Fuentes revisadas:** los 25 textos de PDF ya almacenados en Supabase, documentos originales cotejados en Drive (ejemplos 4087, 0180, 5076, 4080, 6200, dos documentos con numero 0212), y plantilla Excel oficial ROMAX 2026. **Sin precios personales o importes comerciales en este GitHub publico.**

## 1. Auditoria del lote

| Familia | Documentos | Identificacion textual | Consideracion |
| --- | ---: | --- | --- |
| Clasica de servicios/materiales | 15 | "1. DESCRIPCION DEL SERVICIO", "DESCRIPCION DE MATERIALES...", "4. TOTAL COSTOS..." | Mano de obra, materiales, movilidad y GG/utilidad; otros campos pueden ser vacios |
| Propuesta economica detallada | 7 | "1. PROPUESTA ECONOMICA" y "5. RESUMEN ECONOMICO" | Items/codigos 1.1, 2.1, etc.; subtotal, IGV y total; secciones tecnicas, seguridad y condiciones |
| Material/requerimiento por metraje | 2 | "METRAJE", "DESCRIPCION DEL MATERIAL O REQUERIMIENTO" | Precio por unidad o por conjunto; validar asociacion con columna descriptiva |
| Variante mixta | 1 | "Descripcion del servicio", "Descripcion de materiales relevantes", "Costo Unit" | Secciones propias de seguridad, tecnica y movilidad, sin forzar las mismas etiquetas |
| **TOTAL** | **25** | | |

Identificadores en esta muestra: el numero RMX-2026-0212 identifica dos documentos distintos. Por ello se identifica cada cotizacion por su archivo de Drive y su ID historico, **nunca por correlativo**.

## 2. Hallazgos de la plantilla Excel ROMAX 2026

El libro oficial presenta tres niveles de informacion:
- **Propuesta al cliente:** servicios, materiales y equipos, subtotal de mano de obra, materiales, movilidad, GG/utilidad y total documental, condiciones y plazo.
- **Recursos para el requerimiento:** personal y categoria, horas-hombre y dias, maquinaria de apoyo, consumibles y responsables tecnicos.
- **Detalle de costo interno:** mano de obra, equipos, herramientas, consumibles, movilizacion, gastos generales, utilidad y calculos de subtotal/IGV.

**Decisiones:** nunca mezclar costos internos de insumos con precios al cliente; conservar escenario comercial historico, moneda, fecha y fuente. El Excel sirve como fuente mejor estructurada cuando se confirma que corresponde exactamente al PDF, version y correlativo.

## 3. Contrato de homologacion por compatibilidad

| Bloque canonico | Fuente equivalente | Modelo actual/extensible |
| --- | --- | --- |
| Servicios y alcance | Listado de servicios, propuesta economica, trabajos/actividades | commercial_quote_history_line_items section_kind=service cuando el vinculo descripcion/cantidad es fiable; si no, narrative section_kind=service_scope |
| Materiales/consumibles | Materiales, requerimiento, equipos de apoyo | line_items material/equipment cuando partidas alineadas; narrative material_scope cuando no |
| Mano de obra y otros costos | Metrados, dias/hora-hombre, PDR, equipos, movilidad, GG y utilidad | cost_components para sumarios, line_items para partidas, narrative labor/additional_costs si no hay detalle tabular seguro |
| Resumen economico | Subtotal sin IGV, IGV y total o costo del servicio sin IGV | cost_components net_total/tax/gross_total, separados; no inventar impuesto cuando falta |
| Notas tecnicas y seguridad | Aclaraciones tecnicas, SST/EPP/PDR, alcance, exclusiones | sections technical/safety |
| Gestion y entrega | Pruebas, soporte, fotos, acta y cierre | sections management_delivery |
| Condiciones comerciales | Validez, garantia, forma de pago, plazo y horario | sections commercial_terms |
| Evidencia original | PDF/Excel de origen, numero de pagina cuando comprobado | history_documents, source_extracts, source_page nullable cuando no hay evidencia |
| Estructura interna de recursos | Personal, equipos, herramientas, materiales, gastos | sections internal_costs, futuras tablas R2 especializadas; no publicarlas como tarifas comerciales |

**Regla cardinal:** una transcripcion PDF aplanada puede separar las 3 cantidades y precios de sus 3 descripciones. Aunque los importes sean matematicamente conciliables, no se adjudica el precio a una descripcion sin revisar la tabla visual o el XLSX correspondiente.

## 4. Primer piloto: RMX-2026-4087 (HMC Iquitos)

Se comparara con el ejemplo clasico RMX-2026-6200 ya cargado. La propuesta 4087 utiliza un encabezado economico de tres posiciones numeradas, notas de instalacion/ventilacion, aclaraciones electricas y puesta a tierra, seguridad, gestion de entrega y condiciones comerciales, mas resumen de subtotal, IGV y total.

**Carga restringida:** notas y condiciones fuente en la nueva commercial_quote_history_sections; tres valores del resumen economico (subtotal sin IGV, IGV, total) en cost_components **extraidos_sin_verificar**, si concilian aritmeticamente con el texto real. Como el extractor no confirma paginas, source_page sera NULL. Las 3 filas economicas numeradas y los textos descriptivos se mantendran sin vinculacion unitaria hasta revisar la tabla original: NO crear asociaciones ni tarifas artificiales.

**Control aritmetico:** validar que subtotal + IGV = total segun PDF, independientemente del estado de contratacion. **Control del importe del encabezado:** validar la suma de las tres posiciones sin usarlo como precio vigente.

**Otros documentos:** 23 sin cambios en esta prueba (el caso clasico 6200 permanece como comparador). No cambiar price_review=pending ni amount_* de cabecera; no crear solicitudes o propuestas comerciales operativas.

## 5. Seguridad y QA

- Nueva tabla tenant-safe commercial_quote_history_sections; FK compuesta (organization_id,history_id), UNIQUE por orden, RLS SELECT solo miembros activos, sin INSERT/UPDATE desde navegador, anon denegado.
- Mantener la etiqueta original y la redaccion de fuente; clase canonica adicional, nota de procedencia y status=extracted_unverified.
- Donde no se conoce pagina, mantener NULL, sin inventar. El costo financiero del PDF puede incluir totales historicos sin establecer revision como verified.
- Migracion y pruebas pgTAP en base aislada antes de Cloud. Confirmar idempotencia, ausencia de duplicados y lectura ROMAX vs tercero.
- Frontend: tabla de secciones complementarias en detalle, con encabezado original y aviso de procedencia; transcripcion completa disponible por separado y colapsada por defecto.
- No introducir precios comerciales, PDF, nombres de contactos, emails ni archivos internos en el repositorio publico.
- Baseline: 25 cotizaciones historicas, 25 documentos/textos, 5 partidas + 5 componentes del caso 6200, 33 solicitudes y 22 cotizaciones operativas.

## 6. Siguientes gates

1. Verificar el piloto 4087 en Supabase (secciones, totales, idempotencia, RLS); si hay duda sobre partidas, dejarlas pendientes.
2. Desplegar frontend a Vercel solo despues de CI y verificar que el usuario ROMAX vea secciones + resumen y que las otras organizaciones no accedan.
3. Ampliar por **familia de formato**, 3–5 documentos por lote, cotejando Excel/PDF original: primero clasicos, luego detallados, metrajes y mixtos.
4. El contrato para la IA requerira referencias por documento, descripcion alineada a precio confirmado, estado de validacion y **vigencia**; no usar importes historicos extraidos como precios aprobados.

**Estado R1-D2:** homologacion completa del lote de 25 sigue pendiente; la primera prueba solo valida compatibilidad y seguridad.

## Ejecucion confirmada

PR #111 mergeado; cinco suites QA PASS. Migracion Cloud version 20261114213637 y piloto RMX-2026-4087 aplicado: seis secciones de alcance, tecnica, seguridad, soporte, economia y condiciones; tres componentes de resumen (neto, impuesto, total) extraidos sin verificar y con pagina desconocida = NULL. Control de aritmetica de filas del PDF y resumen PASS. 0 asignaciones precio/descripcion a filas ambiguas. RLS ROMAX 6/3 frente a otra organizacion 0/0. Ver docs/ROMAX_R1D2C_PILOT_QA.md.
