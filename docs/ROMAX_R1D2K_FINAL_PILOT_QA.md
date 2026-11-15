# ROMAX R1-D2K — Cierre del piloto de 25 cotizaciones históricas (14-nov-2026)

## Alcance y metodología
Tres PDFs de una página, cotejados visualmente con sus originales en Google Drive; ningún documento privado ni tarifa individual se publica en este repositorio. Los registros se identificaron por `history_id`, organización y `source_file_id`, nunca solo por su correlativo. La carga transaccional exigió que las tres tablas destino estuvieran vacías para cada historia antes de crear detalle, y que nombre documental, cliente y servicio coincidieran. No se crearon históricos nuevos ni se modificaron importes originales, condiciones, RLS, esquema o servicios operativos.

Documentos:
- **RMX-2026-4080** — Makro Arequipa 2; emergencia de suministro de agua; fuente Drive `1wBp678IDC-5TyUNutfewG6PMV6k0OXCH`. Formato clásico por categorías: 4 actividades de mano de obra, 4 de suministro, movilidad separada. El PDF presenta un subtotal sin IGV; no publica importe de IGV ni total con IGV. Se preservó `tax=NULL` y `gross_total` ausente; no se fabricó importe bruto.
- **RMX-2026-5076** — Cassinelli Chiclayo; racks; fuente Drive `1yu8R7PBZDFO4e3Fy9XlwPZ4J2jfan28k`. Dos partidas con cantidad 4 y costos parciales originales, **sin costo unitario explícito**. Por tanto `unit_price=NULL` en las dos filas, sin inferencia matemática de tarifa.
- **RMX-2026-5152** — Cassinelli Piura; mantenimiento correctivo y retorqueo; fuente Drive `1s8iAJBKy8fkq--TfGYS2H-0B3-pA-N6o`. Dos encabezados descriptivos sin valor independiente, preservados en `service_scope`, y tres líneas de material/servicio con precios originales. El PDF denomina al agregado `TOTAL COSTO MANO DE OBRA` aunque las partidas incluyan material: se conserva el rótulo original y no se interpreta como costo de mano de obra puro.

## Carga realizada
| Documento | Partidas | Secciones | Componentes | Observación de QA |
|---|---:|---:|---:|---|
| 4080 | 8 | 3 | 4 | Importes de mano de obra + suministros + movilidad suman neto. Solo subtotal sin IGV |
| 5076 | 2 | 2 | 4 | Suma de parciales = neto; 2 tarifas unitarias NULL |
| 5152 | 3 | 3 | 4 | Tres subpartidas componen neto; encabezados sin cargo adicional |
| **Total** | **13** | **8** | **12** | **3 documentos** |

QA posterior, consultado en Supabase:
- 4080: líneas (mano de obra y materiales) suman **S/ 2,410**. El costo de movilidad es componente independiente de **S/ 150**. Los tres componentes de costo suman el **neto S/ 2,560**. **Sin IGV ni total con IGV**, como el PDF.
- 5076: las dos líneas parciales suman **S/ 1,700**. Documento presenta **IGV S/ 306** y **total S/ 2,006**. No atribuir tarifa por unidad a las dos partidas.
- 5152: tres subpartidas suman **S/ 8,700**, IGV **S/ 1,566**, total **S/ 10,266**. Grupo 1 y 2 son solo títulos; no hay cargo independiente de grupo.
- Controles en las tres historias: **0 errores** en líneas con cantidad, costo unitario y parcial completos; **0 referencias interorganización** en partidas, secciones o componentes; documentos fuente intactos; estados nuevos `extracted_unverified`.
- Identidades/documentos/extractos históricos conservados: **25/25/25**. Solicitudes y cotizaciones operativas: **33/22**, sin cambios.
- **Progreso estructural 25/25 = 100 %**. Totales finales: **186 partidas**, **93 secciones** y **109 componentes**; **0 cotizaciones sin partidas**.

## Distinción esencial de cierre
Se declara **100 % de la extracción estructural del conjunto piloto**, no 100 % de validación comercial, QA visual de frontend o certificación RLS con sesiones ajenas. Los datos permanecen históricos y no aprobados para tarifarios vigentes. En particular, hay que revisar la visualización de subtotales por sección para documentos mixtos (como 5152), porque el rótulo de costo heredado puede abarcar material y mano de obra. El correctivo R1-D2I-FIX y el despliegue productivo del frontend se gestionan separadamente. Esta carga no implicó despliegue Vercel ni cambios en Drive.

### Próxima fase recomendada
QA integral de los 25 históricos: reconciliación por estructura y plantilla, separación rigurosa de grupos/filas, pruebas de sesión y RLS en interfaz, revisión de las advertencias de costos unitarios ausentes y etiquetas económicas mixtas, y despliegue controlado del frontend cuando Vercel lo permita.
