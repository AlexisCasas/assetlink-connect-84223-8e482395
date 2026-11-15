# ROMAX R1-D2H — Cuarto lote y cierre de familia de cotizaciones clásicas

**Fecha de revisión:** 14-nov-2026 (Lima). **Entorno:** Supabase Cloud One Facility. **Fuente:** PDF originales ROMAX en Google Drive, 5 páginas inspeccionadas visualmente. **Alcance:** 3 registros históricos existentes; sin modificaciones de frontend, esquema, RLS o cotizaciones operativas.

## Documentos estructurados

| Cotización | Cliente y sede documental | Servicios | Materiales/equipos | Secciones adicionales | Componentes económicos |
| --- | --- | ---: | ---: | ---: | ---: |
| RMX-2026-5063 | Oechsle, Chiclayo | 5 | 11 | 4 | 5 |
| RMX-2026-6167 | Makro, Surco | 3 | 3 | 3 | 5 |
| RMX-2026-6195 | Plaza Vea, Ate | 4 | 6 | 3 | 5 |
| **Total** | | **12** | **20** | **10** | **15** |

Se insertaron **32 partidas**, **10 secciones** y **15 componentes económicos**. La carga verifica por organización, ID histórico y archivo Google Drive exacto que las tres cotizaciones ya existían y tenían cero registros estructurados. No se crean nuevos clientes o documentos ni se reemplazan cotizaciones.

## Contrato aplicado

- **Servicios:** el listado conserva las descripciones y las cantidades/unidades de las filas del PDF cuando aparecen, pero sin tarifas individuales inventadas. El subtotal de servicios se obtiene del componente documental de mano de obra.
- **Materiales/equipos:** se cotejó visualmente cada fila descriptiva con unidad, cantidad, precio unitario y parcial. Se validó `cantidad x tarifa = parcial` y la suma contra el subtotal de materiales de cada PDF.
- **Resumen económico:** mano de obra, materiales, movilización, GG/utilidad y total neto del PDF son componentes distintos. En dos documentos el total impreso está redondeado a soles enteros; se mantiene sin forzar un centavo de ajuste.
- **Secciones adicionales:** alcance (incluye el texto completo de las actividades), seguridad, condiciones comerciales y aclaraciones técnicas solo cuando contienen texto informativo real. La fuente se identifica como `pdf_visual_review` con página 1 o 2 según el documento.
- **IGV:** las condiciones indican precios que no incluyen IGV. No se agregan cálculos de impuesto o total bruto ausentes.
- **Estado comercial:** `price_review=pending`, `commercial_status=unverified` y partidas `extracted_unverified` o `needs_review`; no se marcan precios aprobados para uso de IA.

## Excepciones del cotejo documental

1. **RMX-2026-5063:** suma de componentes con céntimos y total neto impreso redondeado; se conservaron ambos y el total en estado `needs_review`, sin ajuste artificial. El documento contiene cinco renglones de servicios, con el importe grupal de mano de obra, no repartido entre habitaciones/áreas.
2. **RMX-2026-6167:** el campo de aclaraciones técnicas contiene solamente la letra «C». No constituye una nota técnica identificable y no se importó como afirmación. El contenido literal sigue en el PDF y su transcripción. Los tres materiales/equipos concilian con su subtotal.
3. **RMX-2026-6195:** la primera descripción dice **«Cambio de 30 porcelanatos»**, mientras su columna de cantidad indica **38**. Se preservaron las dos expresiones y se marcó esa partida `needs_review`, sin sustituir el 38 por 30 ni viceversa. La anotación «colores similares» se preservó junto a la descripción de la partida correspondiente. El campo de aclaraciones técnicas contiene solamente «C» y no se convirtió en una nota inventada. El total neto también está redondeado respecto de los componentes con céntimos.

## QA realizado directamente en Supabase Cloud

| Prueba | Resultado |
| --- | --- |
| PDF visuales inspeccionados | 3 documentos, 5 páginas |
| Identidad única por organización + historial + PDF | 3/3 PASS |
| Partidas importadas | 32 (12 servicios + 20 materiales/equipos) |
| Secciones / componentes | 10 / 15 |
| Subtotales de materiales vs suma de parciales | 3/3 PASS |
| Cálculo de filas con precio | 0 errores |
| Totales netos idénticos a suma de componentes | 1/3; dos redondeos documentados |
| Unitarios de servicios inventados | 0 |
| Partida de porcelanatos ambigua identificada | 1 en estado `needs_review` |
| Componentes comerciales marcados verificados | 0 |
| Procedencia visual faltante en secciones | 0 |
| RLS propietario ROMAX — partidas / secciones / componentes | 32 / 10 / 15 |
| RLS usuario de organización distinta | 0 / 0 / 0 |
| Reintento de inserción de identidades existentes | 0 duplicados |
| Históricos / PDF / textos fuente preservados | 25 / 25 / 25 |
| Solicitudes / cotizaciones operativas preservadas | 33 / 22 |

## Estado acumulado y continuidad

Al cerrar este cuarto lote, el histórico ROMAX contiene **16 de 25 cotizaciones con partidas estructuradas (64 %)**: **102 partidas**, **60 secciones** y **76 componentes económicos**. Quedan **9 cotizaciones sin partidas**: 6 propuestas económicas detalladas, 2 por metraje y 1 mixta. La familia documental clásica quedó estructurada, **no equivale a aprobación comercial final de todos sus precios**.

**Siguiente fase recomendada:** comenzar con tres propuestas detalladas, inspeccionar el PDF renderizado y reconocer los servicios/materiales/resumen con encabezados diferentes. Mantener las mismas pruebas aritméticas, de procedencia, RLS y protección de datos.

**Seguridad y privacidad:** este informe público no incluye precios comerciales exactos, textos integrales de documentos, contactos privados ni IDs internos de Drive. Los PDF originales y la información de importes permanecen en sus fuentes con controles de acceso.

Referencias: `docs/ROMAX_R1D2G_CLASSIC_BATCH3_QA.md` y `docs/ROMAX_PILOT_MASTER_PLAN.md`.
