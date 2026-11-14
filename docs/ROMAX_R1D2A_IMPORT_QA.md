# ROMAX R1-D2A — Cierre del lote inicial de detalles históricos

**Fecha:** 14-nov-2026 · **Entorno:** Supabase Cloud OneFacility · **Organización:** ROMAX proveedor · **Resultado:** PASS para esquema, texto fuente de 25 PDF y desglose estructurado piloto de 1 cotización.

## Control de versiones y alcance

- PR #108 integrado: desarrollo de modelo, frontend y pruebas SQL.
- Migración registrada en Cloud: 20261114182230_romax_quote_history_details.sql.
- Contenido de la migración idéntico al SQL evaluado en la rama del PR #108; se corrigió el nombre del archivo del repositorio para coincidir con la versión de Cloud y evitar replay.
- Se habilitaron tres tablas de **solo lectura desde el navegador**:
  commercial_quote_history_line_items, commercial_quote_history_cost_components y commercial_quote_history_source_extracts.
- Se conservaron las 25 cotizaciones y sus 25 PDF, el directorio comercial de ROMAX y el histórico de solicitudes y cotizaciones operativas.
- Los textos fuente de los 25 PDF se importaron como raw_unverified, uno por cotización y siempre bajo el tenant ROMAX. **No se crearon nuevas cotizaciones.**

## Primer caso estructurado

- Documento fuente RMX-2026-6200, Makro Huacho, dos páginas.
- **3 conceptos de servicios** (precios unitarios ausentes conservados como NULL) y **2 conceptos de materiales**, cada uno con unidad/cantidad y números fuente únicamente si figuran en el PDF.
- **5 componentes económicos**: mano de obra, materiales/consumibles, movilización, GG+utilidad y total sin IGV.
- Control: suma de cantidades por tarifa material = subtotal materiales del PDF; suma de cuatro componentes = total neto sin IGV: ambos PASS.
- Los valores económicos permanecen con review_status=extracted_unverified. No se dedujo IGV ni total bruto. **No se subieron precios comerciales al repositorio público.**

## Evidencia de QA de Cloud

| Control | Resultado |
| --- | ---: |
| Cotizaciones / PDF preexistentes | 25 / 25 |
| Textos originales almacenados | 25 |
| Partidas estructuradas del primer documento | 5 |
| Componentes económicos del primer documento | 5 |
| Partidas de servicios sin precio unitario inventado | 3 |
| Falsos valores marcados como verified | 0 |
| Duplicados añadidos por reintento idempotente | 0 |
| RLS activa en las tres tablas | Sí |
| Acceso anon a tablas nuevas | Denegado |
| Inserción y modificación desde navegador | Denegadas |
| Lectura ROMAX owner (textos / partidas / costos) | 25 / 5 / 5 |
| Lectura de miembro de otro tenant | 0 / 0 / 0 |
| Supabase Security Advisor (tablas nuevas) | Sin alertas |
| Solicitudes / cotizaciones operativas intactas | 33 / 22 |
| Organizaciones intactas | 10 |

## Límite real de la entrega

Los **otros 24 PDF** conservan su texto extraído en Supabase, pero sus listados de servicios/materiales **todavía no están convertidos a filas estructuradas verificadas**. Los extractores de Drive pueden devolver columnas PDF fuera de orden; no se deben vincular precios unitarios con conceptos de forma inferida. La pantalla ofrece el texto fuente y el enlace Drive mientras se cotejan las partidas con cada PDF/XLSX de origen.

**No equivale a completar R1-D2 para los 25 documentos.** El seguimiento siguiente debe registrar progresivamente las partidas, revisión económica e IGV por documento, preservando source_page, review_status, nombre original y contexto de fecha.

## Siguiente gate

1. QA visual de ROMAX en la pantalla del detalle RMX-2026-6200: tres servicios, dos materiales, resumen por conceptos y PDF de Drive.
2. Inspeccionar que otro PDF sin desglose muestre claramente «Pendiente de revisión estructurada» y permita consultar texto sin presentar precios asignados por error.
3. Revisar individualmente los 24 PDF restantes o sus XLSX, guardar partidas con cantidades/unidades/documento/página; luego validar cifras contra subtotal neto, IGV y total por cotización.
4. La futura IA consultará referencias documentales e información histórica, pero los costos no se podrán presentar como precios vigentes hasta tener validación y una comparación con catálogo R2.

**Seguridad:** no incluir datos personales, PDF completos, valores unitarios ni material privado de Drive en GitHub público.
