# ROMAX R1-D2A - Partidas de servicios, materiales y costos historicos

**Motivo:** la pantalla R1-E (PR #107, produccion) consultaba metadatos de las 25 cotizaciones 2026, pero no guardaba ni mostraba sus partidas de servicios, materiales, cantidades y precios. ROMAX necesita la estructura para consultar trabajos anteriores y, mas adelante, usar referencias historicas verificables con IA.

## Contrato de datos nuevo

Migracion propuesta: supabase/migrations/20261114181500_romax_quote_history_details.sql.

- commercial_quote_history_line_items: una fila por servicio/material/equipo, con descripcion, unidad, cantidad, precio unitario y subtotal **opcional**, pagina del PDF, orden y review_status. No inventar precios que faltan en el documento; dejar NULL.
- commercial_quote_history_cost_components: resumen economico (mano de obra, materiales, movilizacion, GG+utilidad, total sin IGV, IGV y total bruto cuando existan). Se conserva el rotulo tal como figura en el PDF.
- commercial_quote_history_source_extracts: texto extraido del PDF, asociado a la cotizacion. Conserva informacion documental recuperable en futura busqueda de IA cuando el desglose no este validado; **NO equivale a partidas estructuradas verificadas**.
- Identidad y control de acceso: FK compuesta (organization_id,history_id), RLS SELECT solo miembros del proveedor, ninguna escritura desde navegador (service_role es solo del backend). 0 datos anon.
- Revisiones: extracted_unverified, verified, needs_review. El estado de verificacion va por **fila**, **componente** y **texto fuente**, nunca se deduce a partir de que exista el archivo.

## Ejemplo de aceptacion: RMX-2026-6200, Makro Huacho (PDF de 2 paginas)

**Pagina 1 / listado de servicios** (no se deben inferir costos por partida a partir del subtotal):
- Cambio de 10 garruchas, UND 10, precio unitario no disponible.
- Trabajo de soldadura/apuntalamiento en 10 coches, UND 10, precio unitario no disponible.
- Gestion de seguridad, PDR, UND 1, precio unitario no disponible.

**Pagina 1 / materiales y equipos de apoyo:**
- Garruchas: cantidad y tarifa documentadas en PDF original (no transcribir importes en GitHub publico).
- Consumibles: cantidad y tarifa documentadas en PDF original.

**Pagina 2 / resumen economico:**
- Mano de obra, materiales y consumibles, movilizacion/desmovilizacion, gastos generales y utilidad, y total sin IGV, cada uno en un componente separado con su valor de fuente reservado en Supabase.
- Verificar que la suma de componentes coincida con el total documental. El PDF indica que los precios **no incluyen IGV**. No inferir total bruto hasta confirmar IGV.
- Documento de referencia historica, no precio vigente ni prueba de adjudicacion.

## Extraccion de los otros 24 PDFs

Se almacenara el texto original extraido de cada uno con estado raw_unverified en Cloud; este texto puede contener celdas y conceptos **fuera de orden**, especialmente en formatos de tablas. Por eso no se pretende poblar unit_price o asociar cantidades con conceptos mediante una simple expresion regular: los valores solo se incorporan al desglose estructurado cuando se contrasten con las paginas correspondientes. La pantalla debe indicar "pendiente de desglose" y permitir expandir el texto original, ademas de abrir el PDF Drive con permisos propios.

**Proximo incremento de calidad:** homologacion por documento de las partidas restantes y precios, comparacion de neto/IGV/bruto y deteccion de duplicados. Preferir los XLSX de origen cuando existan para reconciliar filas y formulas. Los registros se importaran por archivo y posicion en el documento, no por correlativo de cotizacion (que puede repetirse).

## QA minimo antes de merge / despliegue

1. GitHub Actions migraciones aisladas y test R1-D2 (24 aserciones): PASS, ademas de suites frontend.
2. RLS en las tres tablas, sin grants anon ni escritura authenticated; no lecturas cruzadas entre ROMAX y otros proveedores.
3. PDF 6200: 5 partidas estructuradas, 5 componentes de resumen; 10 garruchas x 65=650, consumibles 1 x 200=200, subtotal materiales=850 y neto=2040. El PDF dice NO INCLUYE IGV.
4. 25 cotizaciones originales, 25 documentos y 25 textos completos privados; restantes 24 sin desglose estructurado falso.
5. El usuario ROMAX puede expandir desglose o texto extraido; un usuario de otra organizacion ve 0. El listado no recupera texto completo, solo cuando se abre detalle.
6. Las cotizaciones operativas (22), solicitudes (33), clientes (6), sedes (145) y contactos (170) se conservan. Ninguna cifra historica se publica como precio validado o tarifa vigente.
7. Aplicar migracion en Cloud solo tras CI; verificar registro en historial y sincronizar nombre de migration con repo. Desplegar Vercel despues de QA controlado.

## Uso futuro con IA (contrato)

- Responder "que se cotizo antes" con document_id/correlativo/fecha/cliente, partidas y **paginas del PDF**, distinguiendo siempre info extraida vs validada.
- Para sugerir **precios nuevos**, utilizar solamente partidas con review_status verified, normalizadas por unidad y fecha; comparar contra catalogo actual R2, nunca usar automaticamente precios de 2026 como vigentes.
- Mantener cantidades, precios unitarios, subtotales, IGV, GG+utilidad y condiciones por separado. Cualquier contradiccion debe alertarse en la interfaz.
- Los textos fuente contienen informacion privada ROMAX: consultas solo con RLS/RPC autorizadas por proveedor; nunca inyectar todo el corpus a terceros ni publicar PDFs como dataset abierto.

Referencia: docs/ROMAX_PILOT_MASTER_PLAN.md, docs/ROMAX_R1D_PILOT_IMPORT_QA.md, docs/ROMAX_R1E_HISTORICAL_QUOTES_UI.md.
