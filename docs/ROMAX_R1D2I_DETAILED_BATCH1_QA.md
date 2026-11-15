# ROMAX R1-D2I — Primer lote de propuestas económicas detalladas (14-nov-2026, Lima)

## Alcance y fuentes
Se cotejaron visualmente **6 páginas** de 3 documentos PDF originales privados de ROMAX en Google Drive: RMX-2026-0199 (código impreso 0180, Cassinelli Piura), RMX-2026-0212 (Cassinelli Piura, evaluación de racks) y RMX-2026-0209 (Hipermercado Cerámicos, Larco, estudio estructural). Los documentos se identificaron por el **ID de archivo fuente y el registro histórico en el tenant ROMAX**, no por número de cotización: existe otro 0212 en el histórico. PDF, contactos e importes monetarios permanecen fuera de este repositorio público.

## Ejecución Supabase Cloud
- Se utilizaron las tablas existentes `commercial_quote_history_line_items`, `commercial_quote_history_sections` y `commercial_quote_history_cost_components`, sin crear migración ni alterar RLS, frontend o esquema.
- La operación SQL verificó organización, nombre documental y fuente exacta, y exigió ausencia de registros estructurados previos antes de insertar. No se recrearon cotizaciones o documentos.
- **0199:** 3 partidas (grupo más dos subpartidas), 4 secciones y 3 componentes. Se preservan referencia impresa 0180 y nombre de archivo 0199.
- **0212 Cassinelli Piura:** 4 partidas (grupo más tres subpartidas), 4 secciones y 3 componentes. Se preserva como documento separado del otro correlativo 0212.
- **0209:** 14 filas (3 grupos y 11 subpartidas descriptivas), 4 secciones y 3 componentes. Se conservan dos opciones alternativas en el tercer grupo, sin duplicar su total; la numeración visible de estas alternativas repite 2.1/2.2. En la página 2 hay una descripción de entregable duplicada, preservada literalmente.
- **Totales del lote:** 21 partidas, 12 secciones y 9 componentes de resumen. Se conservaron condiciones comerciales y notas de seguridad/gestión, con procedencia `pdf_visual_review` en página 2.
- La extracción de texto del PDF 0209 incluye números en espacios aparentemente vacíos, que **no son precios visibles en el renderizado**. Las subpartidas sin precio gráfico permanecen con `unit_price=NULL` y `line_total=NULL`. Los únicos importes de servicio en ese documento son los tres grupos visibles, sin repartirlos entre las actividades.
- Los grupos de 0199 y 0212 son encabezados valorizados: sus importes no deben sumarse con sus propias subpartidas. La tarifa de grupo 0199 no se infirió porque el PDF solo imprime su parcial. **Estado comercial sin promover a aprobado:** todos los registros nuevos `extracted_unverified` y los tres históricos mantienen su calificación de revisión previa.

## QA post-escritura
| Control | Resultado |
|---|---|
| Identidades documentales halladas | 3/3 |
| Partidas del lote | 3 + 4 + 14 = 21 |
| Secciones del lote | 4 + 4 + 4 = 12 |
| Componentes de resumen | 3 + 3 + 3 = 9 |
| Conciliación grupo principal vs subtotal neto de cada PDF | 3/3 PASS |
| Conciliación subtotal + 18 % IGV = total de cada PDF | 3/3 PASS |
| Errores cantidad × unitario vs parcial para filas completas | 0 |
| Registros nuevos marcados `verified` | 0 |
| Relación cruzada entre organización de datos y cabecera | 0 |
| Histórico / documentos / textos privados | 25 / 25 / 25, sin variación |
| Solicitudes / cotizaciones operativas | 33 / 22, sin variación |
| Acumulado tras lote | **19/25 históricos estructurados; 123 partidas, 72 secciones, 85 componentes** |

Se inspeccionaron las políticas RLS de las tres tablas: `SELECT` solo para rol `authenticated` mediante `is_organization_member(organization_id)`; no se cambiaron políticas. **El aislamiento efectivo ROMAX vs usuario de otra organización todavía requiere una prueba de sesión real para este lote**; no se declara PASS de impersonación de tenant. La carga evitó duplicados existentes mediante guardas transaccionales antes de insertar. No se realizó una segunda escritura de prueba para confirmar idempotencia por reintento.

## Pendientes y decisión de continuidad
- Restan **6 cotizaciones sin partidas** del piloto de 25 (3 detalladas, 2 por metraje y 1 mixta). La clasificación fina debe verificarse por PDF, nunca por identificador solamente.
- QA con credenciales de dos organizaciones distintas en la pantalla de histórico, si se requiere certificación de aislamiento a nivel de sesión.
- El siguiente lote puede centrarse en las otras tres propuestas detalladas sin alterar ni reimportar estas tres.
- No se modificó Google Drive, no se desplegó Vercel y no se aprobó la vigencia comercial de los precios.
