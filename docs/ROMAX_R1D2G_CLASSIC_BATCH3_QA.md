# ROMAX R1-D2G — Tercer lote de cotizaciones clásicas

**Fecha de referencia:** 14-nov-2026 (Lima). **Fuente de verdad:** PDF originales de ROMAX en Drive, cuatro páginas renderizadas y cotejadas visualmente. **Destino:** histórico privado ROMAX en Supabase Cloud, proyecto One Facility. **Resultado:** carga documental, conciliación de partidas y aislamiento multiorganización PASS.

## Alcance

| Documento | Cliente/sede | Servicios | Materiales/equipos | Secciones | Componentes económicos |
| --- | --- | ---: | ---: | ---: | ---: |
| RMX-2026-0197 | Makro / Huacho | 5 | 3 | 4 | 5 |
| RMX-2026-5160 | Plaza Vea / Ventanilla | 3 | 4 | 4 | 5 |
| RMX-2026-5161 | Makro / Cusco | 4 | 4 | 4 | 5 |
| **Total** | | **12** | **11** | **12** | **15** |

Se importaron **23 partidas**, **12 secciones de origen** y **15 componentes** en registros históricos que ya existían. Ningún dato de encabezado, cliente, documento fuente o cotización operativa fue creado ni reemplazado.

## Criterios de homologación

- El subtotal gris de **Listado de servicios** procede de `component_kind=labor`, no de la suma de tarifas individuales incompletas.
- Los cinco trabajos del documento de coberturas y las tres operaciones de porcelanato conservan las unidades/cantidades visibles donde las hay, pero no se les inventa tarifa unitaria.
- Los materiales y equipos de apoyo se incorporan con su propia unidad, cantidad, precio y parcial **únicamente después de cotejar las filas de las tablas originales**.
- Las secciones independientes conservan: alcance, seguridad, aclaraciones técnicas y condiciones de venta. Proveniencia `pdf_visual_review`, páginas verificadas (dos páginas para 0197, una para los otros dos).
- Las condiciones documentales señalan importes **sin IGV**; no se agrega impuesto ni bruto no documentado.
- Precios y componentes permanecen históricos; `review_status` no se cambia a `verified`, y `price_review` de las cabeceras continúa `pending`.

## Excepciones y advertencias comerciales

1. **RMX-2026-5160:** los cuatro componentes suman una cantidad con céntimos, mientras el total neto impreso está redondeado a soles enteros. Se conservan ambos valores y el total documental se etiqueta `needs_review`. No se crea ajuste ficticio ni se modifica una tarifa para forzar la igualdad.
2. **RMX-2026-5160:** el PDF expresa trabajos sobre 90 piezas y consigna cantidades de materiales diferentes, entre ellas 23 unidades de porcelanato. Se conserva esa diferencia entre unidades de actividad y unidades de abastecimiento, sin inferir cobertura, equivalencia ni desperdicio.
3. **RMX-2026-0197:** el costo del grupo de servicios no está repartido entre sus cinco actividades, aunque las cantidades sean visibles; las tarifas individuales quedan vacías.
4. **RMX-2026-5161:** solo la primera actividad tiene una unidad/cantidad explícita. No se atribuye a las tres actividades siguientes un precio o cantidad que el PDF no contiene.

## QA ejecutado en Supabase Cloud

| Verificación | Resultado |
| --- | --- |
| Documentos / páginas fuente revisadas | 3 PDF / 4 páginas |
| Identidad por organización, history_id y archivo Drive | 3/3 PASS |
| Partidas / secciones / componentes insertados | 23 / 12 / 15 |
| Sumas de materiales contra subtotal de su grupo | 3/3 PASS |
| Cálculo cantidad × precio de renglones con importe | 0 errores |
| Neto exacto contra suma de componentes | 2/3; una excepción de redondeo preservada |
| Tarifas individuales de servicios inferidas | 0 |
| Estados comerciales o líneas convertidos a verified | 0 |
| Procedencia visual faltante en secciones | 0 |
| Lectura RLS owner ROMAX (partidas / secciones / componentes) | 23 / 12 / 15 |
| Lectura RLS de usuario ajeno a ROMAX | 0 / 0 / 0 |
| Reimportación del mismo registro | 0 duplicados |
| Solicitudes y cotizaciones operativas preservadas | 33 / 22 |
| PDF y textos fuente históricos preservados | 25 / 25 |

**Acumulado del piloto:** 13 cotizaciones históricas con partidas estructuradas de 25; 70 partidas, 50 secciones y 61 componentes económicos. Restan 12 cotizaciones sin partidas, de las cuales **3 son clásicas**, **6 propuestas detalladas**, **2 de metrajes** y **1 mixta**.

## Despliegue y control de cambios

Se comprobó que `one-facility.vercel.app` está en estado `READY`, con la interfaz de histórico previamente aprobada. Este lote solo incorporó registros del histórico privado: **no hubo código de frontend, migración SQL, alteración de RLS, nueva publicación Vercel ni importes en el repositorio público**. La documentación y el plan maestro se registran con PR propio.

**Próximo lote recomendado:** completar los tres clásicos restantes RMX-2026-5063, RMX-2026-6167 y RMX-2026-6195. Son documentos con más partidas de materiales y requieren el mismo cotejo visual antes de asociar unitarios.

Referencias: `docs/ROMAX_R1D2F_CLASSIC_BATCH2_QA.md`, `docs/ROMAX_PILOT_MASTER_PLAN.md`.
