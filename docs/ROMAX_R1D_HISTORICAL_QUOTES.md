# ROMAX R1-D - Historico de cotizaciones 2026 (piloto)

**Objetivo:** consultar propuestas anteriores para busqueda y futuras sugerencias de presupuesto. ROMAX es el proveedor propietario de los datos. Los clientes externos NO necesitan una cuenta One Facility.

## Alcance inicial

- Lote piloto controlado: **25 documentos PDF reales de 2026** provenientes de varios responsables comerciales de ROMAX.
- Se cotejaron los PDF directamente, no solo sus nombres. La muestra incluye 10 propuestas de Makro, 10 de Cassinelli/HMC, 1 de Oechsle y 4 de clientes aun no homologados (Plaza Vea/InRetail).
- Otros clientes catalogados, como National y Tgestiona, no se asignan de forma automatica a propuestas de Plaza Vea. Esto requiere validacion del contratante efectivo.
- No se crean organizaciones cliente, solicitudes falsas ni autorizaciones de trabajo.
- La carpeta "COTIZACIONES ENVIADAS" no prueba que una propuesta haya sido recibida, aceptada, contratada ni ejecutada. Se registra commercial_status=unverified hasta encontrar prueba explicita.
- Se detectaron correlativos iguales para proyectos distintos, y al menos un archivo cuyo numero no coincide con el numero interno del PDF. No se debe usar el correlativo como clave unica.

## Modelo protegido

Migracion: supabase/migrations/20261114172300_commercial_quote_history.sql (version a sincronizar con Supabase Cloud tras aplicar).

- commercial_quote_history: organizacion proveedora, cliente/sede comercial opcionales con FK compuestas del mismo tenant; nombre del cliente y sede tal como figuran en el documento; correlativo impreso, correlativo del archivo, estado de revision, fecha, titulo del servicio, moneda, campos numericos opcionales y estado comercial.
- commercial_quote_history_documents: PDF u hoja de calculo asociados a la propuesta. Identidad unica por organizacion + proveedor de documentos + identificador del archivo, nunca por numero de propuesta. No vincular PDF y XLSX solo por nombre parecido.
- Indices por cliente, sede, fecha, correlativo y busqueda textual en espanol para R1-E.
- RLS: lectura solo a miembros activos de la organizacion propietaria. Historicos solo lectura para usuarios web; importacion y correccion por servicio administrativo autorizado. Anon sin acceso.

## Calidad y trazabilidad

1. Identificador de origen por archivo de Drive (privado en BD); import_source_key estable evita reimportaciones.
2. Fecha proposal_date: leer dentro del PDF. Si no hay, dejar NULL. Nunca confundir fecha de modificacion Drive con fecha de propuesta.
3. Cliente/sede: conservar el texto documental; enlazar al directorio ROMAX solo cuando corresponda de forma inequivoca.
4. Referencia: preservar reference_document y reference_filename, con discrepancias visibles; correlativos iguales no se fusionan.
5. Moneda: PEN solo si el documento contiene soles, en otro caso NULL.
6. **Importes:** hay formatos dispares, separadores decimales y neto vs IGV. En L1 los importes quedan NULL y price_review=pending hasta validacion financiera contra PDF/XLSX; no sugerir como precio vigente.
7. Originales siguen en Drive. Solamente metadatos, referencias y evidencia privada en Supabase, nunca PDFs, importes ni PII en GitHub publico.
8. commercial_status=unverified hasta verificar envio, adjudicacion o rechazo por evidencia adicional.
9. Cuatro documentos sin cliente de los seis del directorio quedan unmatched, visibles para ROMAX sin crear clientes ficticios ni deducir intermediarios.

## Gate de despliegue y QA

1. Ejecutar migracion y prueba supabase/tests/romax_r1d_quote_history.test.sql en entorno Supabase local desechable, con ambos workflows CI PASS.
2. Merge controlado, aplicacion en Supabase Cloud y sincronizacion de version con historial real.
3. Verificar RLS con owner ROMAX vs usuario de otra organizacion, grants y FKs.
4. Importar solo los 25 PDF cotejados, con documento vinculado y atributos respaldados por contenido original.
5. Conciliar fuentes, keys unicas, correlativos repetidos, mismatch y clientes no enlazados. Reintentar para validar idempotencia.
6. Comprobar no-regresion: 10 organizaciones, 33 solicitudes, 22 cotizaciones; directorio ROMAX 6 clientes/145 sedes/170 contactos/284 vinculos al gate.

## Despues del lote L1

- R1-D2: extraer y verificar neto/IGV/bruto y lineas (unidad, cantidad y tarifa) contra documento original; no tratar el costo historico como lista de precios vigente.
- R1-E: pantalla de busqueda por cliente, sede, fecha, termino y referencia, con permisos de ROMAX.
- Corroborar relaciones contractuales de Plaza Vea/InRetail con posibles intermediarios antes de asignarlos a National/Tgestiona.
- Guardar las pruebas de diferencia entre numero del archivo y numero impreso; no repararlas silenciosamente.

**Continuidad:** docs/ROMAX_PILOT_MASTER_PLAN.md y docs/ROMAX_R1B_CONTACTS_IMPORT_QA.md. Actualizar este documento tras la implantacion.
