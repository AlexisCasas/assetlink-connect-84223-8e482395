# ROMAX R1-D2B - Formato tabular unificado para cotizaciones historicas

**Motivo:** al revisar RMX-2026-4087, el usuario observo una transcripcion PDF con cifras fuera de contexto, sin el formato de las partidas del cotizador de One Facility. Se solicita reutilizar ese formato en el historico.

## Alcance UI (sin SQL ni nuevas importaciones)

- Se extrae el encabezado y estructura visual de la tabla de partidas del formulario de cotizaciones hacia src/components/requests/QuoteItemsTable.tsx.
- **Modo edicion:** QuoteForm.tsx conserva columnas, inputs, validaciones, subtotales, controles de guardar y permisos. No se modifica el modelo quotes.
- **Modo historico:** HistoricalQuoteTables.tsx comparte el diseno, pero muestra valores **solo lectura** en tabla: Descripcion | Cantidad | Unidad | Precio unitario | Parcial. Sin guardar ni editar.
- Secciones "Listado de servicios" y "Descripcion de materiales y consumibles". Si no existen partidas normalizadas, se ve **una tabla con fila informativa** y no precios inventados.
- Resumen economico de cada PDF en tabla: Concepto | Importe historico | Pagina | Revision; total resaltado solo si existe.
- Para documentos sin homologacion (24/25), se puede expandir el texto fuente completo como **tabla de lineas de transcripcion**: Linea | Contenido extraido; no como un bloque plano.
- La transcripcion advierte que el extractor PDF puede reordenar columnas y que filas numericas aisladas no se convierten en precios asignados.
- La consulta sigue siendo bajo demanda. Cambiar de cotizacion oculta las tablas anteriores hasta completar la nueva lectura.

## Exclusiones y protecciones

- No convertir automaticamente texto plano en cantidades, partidas o precios cuando la tabla del PDF perdio estructura.
- No cambiar extracted_unverified a verified, calcular IGV ausente ni promover tarifas historicas como vigentes.
- No crear solicitudes/organizaciones ficticias ni exponer PDF privados fuera del tenant. El enlace a Drive requiere permiso independiente.
- No modificar RLS, solicitudes ni cotizaciones operativas. Solo frontend.

## QA antes de produccion

| Codigo | Prueba | Resultado esperado |
| --- | --- | --- |
| T1 | Cotizacion nueva, editor | Tabla igual que antes, inputs y guardado sin regresion |
| T2 | ROMAX RMX-2026-6200 | 3 servicios y 2 materiales, valores documentales existentes, pagina y aviso sin homologar; 5 componentes economicos |
| T3 | ROMAX RMX-2026-4087 | Dos secciones con tablas pendientes, mas transcripcion en filas; sin cantidades/precios asignados arbitrariamente |
| T4 | Totales e IGV | Celdas vacias cuando falta dato; no presentar total historico como valor vigente |
| T5 | Varios documentos seguidos | Nunca mostrar desglose de una cotizacion al abrir otra |
| T6 | Otro proveedor o FM | Permisos y RLS anteriores se mantienen |
| T7 | Enlace Google Drive | PDF original accesible cuando el usuario tiene sus propios permisos |
| T8 | Regresion frontend | Vercel build y suites GitHub PASS |

## Continuidad

R1-D2A ya guardo el texto privado de los 25 PDF y estructuro las partidas solo del primer documento. **R1-D2B es una mejora de presentacion**, no completa las 24 homologaciones restantes. La futura carga de partidas debe usar PDF visual y, preferentemente, XLSX original para confirmar cada concepto, cantidad, precio y subtotal antes de reutilizarlos con IA.

Referencias: docs/ROMAX_R1D2A_IMPORT_QA.md, docs/ROMAX_R1E_HISTORICAL_QUOTES_UI.md, docs/ROMAX_PILOT_MASTER_PLAN.md.
