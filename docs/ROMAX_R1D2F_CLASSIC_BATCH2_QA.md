# ROMAX R1-D2F — Segundo lote de cotizaciones clásicas

**Fecha:** 14-nov-2026. **Origen:** cuatro PDF históricos de ROMAX, recuperados en Drive y revisados mediante render de todas sus páginas. **Destino:** tablas históricas privadas de One Facility en Supabase Cloud.

## Alcance y resultado

| Documento | Cliente / sede | Servicios | Materiales/equipos | Secciones narrativas | Componentes económicos | Evidencia |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| RMX-2026-2210 | Cassinelli / HMC Maranga | 3 | 0 | 4 | 4 | PDF original página 1 |
| RMX-2026-2221 | Makro / Surco | 4 | 1 | 4 | 5 | PDF original páginas 1 y 2 |
| RMX-2026-4084 | Plaza Vea / La Molina | 2 | 4 | 4 | 5 | PDF original página 1 |
| RMX-2026-5162 | Makro / Cusco | 5 | 3 | 4 | 5 | PDF original página 1 |
| **Total** | | **14** | **8** | **16** | **19** | |

Se insertaron **22 partidas**, **16 secciones** y **19 componentes económicos** exclusivamente en los cuatro registros históricos ya existentes. No se crearon nuevos clientes, cotizaciones operativas ni solicitudes.

## Homologación aplicada

- **Grupo de servicios:** cada línea se incorporó con el orden y descripción respaldados por la tabla visual del PDF. Cuando el PDF solo declara un subtotal de servicios, se conserva ese valor a nivel de componente `labor`, no se asigna proporcionalmente entre sus tareas.
- **Grupo de materiales/equipos de apoyo:** importes unitarios, cantidades y parciales se registraron solamente cuando cada renglón quedó asociado visualmente a su descripción. Las cifras unitarias no se convierten en tarifas vigentes.
- **Sin materiales independientes:** el documento 2210 no contiene ese bloque y no se crearon materiales ficticios.
- **Secciones de origen:** se preservaron alcance, consideraciones de seguridad, aclaraciones técnicas y condiciones de venta. La procedencia `pdf_visual_review` incluye la página real de cada sección.
- **IGV:** los documentos indican que los precios no incluyen IGV. No se calculó ni añadió un impuesto o monto bruto inexistente en la fuente.
- **Fuente exacta:** los cuatro registros se vincularon a su `history_id` y archivo de Drive, además de verificar el código impreso. No se usa el correlativo como única identidad.
- **Calidad comercial:** todas las líneas quedaron `extracted_unverified`, las cabeceras `price_review=pending`, `commercial_status=unverified`. El cotejo visual demuestra fidelidad a la fuente, no aprobación comercial.

## Excepción documental del lote

**RMX-2026-4084**: el documento presenta un total neto redondeado a una cantidad de soles enteros. Los cuatro componentes económicos están expresados con céntimos, y la suma difiere del entero impreso por el redondeo de medio sol. Se conservaron ambos: componentes tal como figuran y total neto impreso, marcado `needs_review`. No se crea una partida de ajuste, no se altera el precio de ningún material ni se convierte la diferencia en IGV.

Los otros tres documentos conciliaron exactamente entre componentes y total neto.

## QA productivo ejecutado

| Control | Resultado |
| --- | --- |
| PDF original renderizado e inspeccionado visualmente | 4/4 (cinco páginas) |
| Registros históricos fuente identificados unívocamente | 4/4 |
| Partidas / secciones / componentes insertados | 22 / 16 / 19 |
| Conciliación neto exacta | 3/4; una excepción explícita de redondeo |
| Desajustes `cantidad * tarifa` en renglones con precio | 0 |
| Tarifas de servicio deducidas sin fuente | 0 |
| Partidas económicas marcadas comercialmente `verified` | 0 |
| Secciones sin página real o sin procedencia visual | 0 |
| Lectura RLS owner ROMAX: partidas / secciones / componentes | 22 / 16 / 19 |
| Lectura RLS miembro de otra organización | 0 / 0 / 0 |
| Intento idempotente de reinsertar identidad existente | 0 / 0 / 0 |
| Históricos / PDF / textos privados preservados | 25 / 25 / 25 |
| Solicitudes / cotizaciones operativas preservadas | 33 / 22 |

**Estado acumulado de ROMAX tras R1-D2F:** 47 partidas estructuradas, 38 secciones complementarias y 46 componentes económicos. Son **10 cotizaciones con algún nivel de estructuración** (2 pilotos individuales más dos lotes de cuatro); las demás 15 aún carecen de partidas estructuradas.

## Vercel y continuidad

El dominio `one-facility.vercel.app` fue comprobado en estado READY antes de importar. El frontend activo ya dispone de tabla histórica y subtotales por bloque: **no se editaron componentes de React, no se solicitaron despliegues nuevos y no se cambiaron políticas RLS ni migraciones**.

La siguiente fase continúa por lotes de 3–5 PDF, priorizando los **seis documentos clásicos aún sin estructurar** antes de pasar a las propuestas detalladas, variantes por metraje y formato mixto. Cada futuro lote requiere cotejo visual, conciliación, pruebas RLS e informe de excepciones.

**Confidencialidad:** no publicar PDFs originales, precios comerciales, datos personales, IDs de Drive ni texto privado de los documentos en el repositorio público. Los valores exactos y sus partidas se conservan exclusivamente en Supabase Cloud y en los PDF bajo permisos de Drive.

Referencia: `docs/ROMAX_PILOT_MASTER_PLAN.md` y `docs/ROMAX_R1D2E_CLASSIC_BATCH1_QA.md`.
