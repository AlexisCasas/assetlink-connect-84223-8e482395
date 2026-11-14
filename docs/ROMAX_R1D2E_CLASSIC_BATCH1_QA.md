# ROMAX R1-D2E — Primer lote de cuatro cotizaciones clásicas

**Fecha:** 14-nov-2026. **Entorno:** Supabase Cloud One Facility, organización ROMAX. **Estado:** carga documental y QA de seguridad PASS; cotejo visual definitivo de algunas asociaciones económicas PENDIENTE.

## Documentos incorporados

| Cotización | Ubicación documental | Servicios | Materiales | Componentes | Secciones |
| --- | --- | ---: | ---: | ---: | ---: |
| RMX-2026-2215 | Makro Arequipa 02 | 6 | 1 | 5 | 4 |
| RMX-2026-2217 | Makro Trujillo 02 | 1 | 1 | 5 | 4 |
| RMX-2026-2218 | Makro Piura 01 | 3 | 4 | 5 | 4 |
| RMX-2026-2219 | Cassinelli HMC Piura | 1 | 0 | 4 | 4 |
| **Total** | | **11** | **6** | **19** | **16** |

Cada PDF se vinculó a su registro histórico por organización, ID del historial e ID de archivo de Drive; el correlativo no se utiliza como clave única. Las cuatro cotizaciones tenían cero partidas, componentes y secciones antes de la importación.

## Criterios de homologación utilizados

- **Servicios:** registrar cada descripción explícita como línea estructurada; dejar cantidad, unidad, precio y subtotal sin llenar cuando la transcripción del PDF no permita relacionarlos de manera confiable.
- **Materiales:** preservar descripciones y tres asociaciones económicas simples como candidatas sujetas a revisión; no convertir asociaciones provisionales en tarifas aprobadas. Para el caso con cuatro materiales y varias cifras desordenadas, no distribuir los importes entre los nombres por inferencia.
- **Resumen económico:** mano de obra, materiales si hay valor documentado, movilización, gastos generales/utilidad y neto histórico por separado, con revisión pendiente.
- **IGV:** el documento indica que los precios no incluyen IGV. No calcular ni registrar un impuesto o bruto no expuesto.
- **Secciones:** alcance, aclaraciones técnicas, seguridad y condiciones comerciales, con encabezado original y estado extraído sin verificar. El contenido proviene de texto del PDF, no de interpretación visual de la tabla.
- **Fuente/páginas:** las partidas/resúmenes aparecen en página 1; las condiciones están en página 2 para los tres PDF de dos páginas y en página 1 para el PDF de una página. No se asignó procedencia de revisión visual.

## Excepciones controladas

1. **2215:** actividades de limpieza, desatoro, desmontaje/montaje, pruebas y eliminación de aguas grises conservadas sin precios individuales. La única línea material con cifra candidata sigue con estado needs_review.
2. **2217:** el subtotal de materiales es mayor que la partida numérica identificable de suministro de agua. Se conserva explícitamente la diferencia sin crear un concepto adicional. El componente de materiales y su línea candidata siguen needs_review.
3. **2218:** cuatro materiales están identificados, pero las cifras de la transcripción no están alineadas con sus nombres. Sus campos unitarios y parciales permanecen NULL hasta ver PDF visual/Excel original.
4. **2219:** una fila económica y un servicio principal permiten una asociación provisional, sin declarar el precio verificado. No se inventan materiales.
5. Las cuatro propuestas permanecen sin evidencia de adjudicación, envío certificado, ejecución o pago. Las cabeceras operativas no se modificaron.

## QA registrado en Supabase Cloud

| Prueba | Resultado |
| --- | --- |
| Documentos fuente identificados unívocamente | 4/4 |
| Líneas nuevas | 17 |
| Secciones nuevas | 16 |
| Componentes económicos nuevos | 19 |
| Conciliación de componentes y neto documental | 4/4 PASS |
| Líneas o componentes elevados incorrectamente a verified | 0 |
| RLS: owner ROMAX puede leer líneas/secciones/componentes del lote | 17 / 16 / 19 |
| RLS: usuario de otra organización puede leer | 0 / 0 / 0 |
| Reintento idempotente con identidad existente | 0 duplicados en las tres tablas |
| Cotizaciones históricas / PDF / textos privados inalterados | 25 / 25 / 25 |
| Solicitudes / cotizaciones operativas inalteradas | 33 / 22 |

Los totales acumulados ROMAX tras el lote son **25 líneas**, **22 secciones** y **27 componentes** económicos, contando los pilotos anteriores.

## Siguiente gate para cerrar el lote como homologado

Primero revisar visualmente el material sin identificar del caso 2217; después confirmar la correspondencia de tarifas de materiales de 2218, la distribución entre servicios de 2215 y la fila única de 2219. Si existe XLSX de origen, utilizar ese documento para cotejar cifras, fórmulas y encabezados. Hasta esa revisión no marcar precios como verified ni utilizarlos automáticamente como tarifas vigentes para la futura IA.

**Vercel:** no se realizaron cambios de frontend, base estructural ni permisos; el módulo de histórico existente ya lee estas tablas con RLS. No requiere nuevo despliegue para consultar los registros desde producción.

**Privacidad:** este archivo del repositorio público excluye valores comerciales, datos personales, identificadores privados de Google Drive y contenido completo de los PDF.

Referencia: docs/ROMAX_PILOT_MASTER_PLAN.md y docs/ROMAX_R1D2D_PDF_VISUAL_CORRECTION.md.
