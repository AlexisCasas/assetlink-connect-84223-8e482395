# ROMAX R1-D2I-FIX — Historial de cotizaciones: correlativos y grupos valorizados

Fecha de revisión: 14 de noviembre de 2026 (America/Lima). Repositorio: `AlexisCasas/assetlink-connect-84223-8e482395`, rama `productization/mvp`.

## Incidencia y causa

- El documento cuyo archivo se denomina **RMX-2026-0199** lleva el código **RMX-2026-0180** impreso en las dos páginas. Son el mismo histórico identificado por un solo `history_id` y un solo documento Drive. El filtro inicial buscaba únicamente `reference_document`, de modo que no encontraba 0199 sin cambiar manualmente a nombre de archivo.
- Los grupos valorizados y sus subpartidas estaban cargados como líneas separadas para preservar el PDF. En `HistoricalQuoteTables`, sumar todos los `line_total` producía el doble del subtotal de 0199 y 0212. Esos importes **no son partidas adicionales independientes**: el valor del grupo ya contiene sus subpartidas.

## Corrección de aplicación

- `src/lib/commercialQuoteHistory.ts`: se agregó la modalidad predeterminada **ambos correlativos** con disyunción PostgREST segura, bajo la misma restricción de organización y políticas RLS. Solo caracteres alfanuméricos, guiones y espacios se admiten en la expresión OR para impedir la inyección de sintaxis de filtros. Se conservan los modos de búsqueda exactos por tipo de referencia.
- `src/components/provider/CommercialQuoteHistoryView.tsx`: selector actualizado para ambos códigos; cuando el código impreso y de archivo difieren, se presentan los dos en el resultado, sin duplicar el registro ni inventar un correlativo canónico.
- `src/components/provider/HistoricalQuoteTables.tsx`: detecta únicamente encabezados valorizados cuya `source_note` original está marcada como `PDF 1. PROPUESTA ECONÓMICA; Grupo N`. Los grupos aparecen resaltados, con los detalles visualmente indentados. El subtotal independiente se obtiene de los grupos **una vez**, sin sumar sus subpartidas. Para otras cotizaciones, queda la suma histórica previa. Los datos originales continúan visibles y no se transforman en nuevas tarifas verificadas.
- Sin modificaciones SQL, esquema, migraciones, Drive, precios, condiciones, permisos ni roles.

## QA de conciliación contra PDFs y Supabase (PASS — datos)

| Fuente | Referencia impresa | Subtotal grupos | IGV | Total |
|---|---|---:|---:|---:|
| PDF archivado 0199 | 0180 | S/ 800.00 | S/ 144.00 | S/ 944.00 |
| PDF archivado 0212 (Cassinelli Piura) | 0212 | S/ 4,400.00 | S/ 792.00 | S/ 5,192.00 |
| PDF archivado 0209 (HMC Larco) | 0209 | S/ 42,500.00 | S/ 7,650.00 | S/ 50,150.00 |

Comprobación SQL por archivo fuente exacto: grupos = neto documental y neto + IGV = bruto, 3/3 PASS. Se evitaron joins entre líneas y componentes que multiplican importes por número de componentes. No se inspeccionó un usuario real de otra organización en esta revisión.

### Pendientes de cierre

- QA de compilación y prueba visual autenticada del frontend requieren entorno ejecutable/conectado; no están certificados por la consulta SQL.
- Verificar disponibilidad del despliegue Vercel en equipo y proyecto correctos. La consulta SQL de QA no autoriza declarar el frontend como ya publicado.
- La paginación y los filtros de cliente/sede/fecha permanecen con la misma semántica, salvo la nueva opción predeterminada de correlativo combinado.
- Los grupos valorizados de otros formatos deben revisarse individualmente; **no** se aplicó una heurística universal de exclusión de precios.
