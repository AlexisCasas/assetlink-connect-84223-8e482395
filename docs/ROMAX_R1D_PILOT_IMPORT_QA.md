# ROMAX R1-D1 - Resultado del piloto de cotizaciones historicas 2026

**Ejecucion:** 14-nov-2026 | **Entorno:** Supabase Cloud OneFacility | **Organizacion:** ROMAX proveedor | **Estado:** lote de metadatos PASS, validacion economica y de contratantes pendiente.

## 1. Implementacion y pruebas

- PR #105: fusionado sobre productization/mvp, commit de merge c39738fab8d7071b66368ffa2cbd91ad99e299e0.
- Migracion de Cloud: version 20261114172357, nombre commercial_quote_history.
- Archivo versionado: supabase/migrations/20261114172357_commercial_quote_history.sql (corregido en PR posterior de cierre, SQL identico al aplicado).
- QA: los workflows 9C.6-B1 isolated database QA y 9C.8-B1 integral multi-tenant QA en GitHub Actions finalizaron con conclusion success.
- Prueba de R1-D: supabase/tests/romax_r1d_quote_history.test.sql, 23 aserciones incluidas en QA completo.
- Tablas privadas nuevas: commercial_quote_history y commercial_quote_history_documents.
- La interfaz no cambio: sin despliegue manual Vercel.

## 2. Fuente y alcance

- Se releyeron y validaron 25 PDF de la carpeta ROMAX de cotizaciones finales 2026 en Google Drive.
- Lote: romax_r1d_2026_pdf_pilot_20261114; identidad por archivo de Drive, almacenada de forma privada en Supabase (no en este repositorio publico).
- 25 cotizaciones independientes y 25 documentos primarios PDF; 25 claves de origen y 25 ID de documento distintos.
- 20 asociadas a clientes del directorio: Makro 10, Cassinelli 9, Oechsle 1.
- 5 con contratante pendiente: 4 de Plaza Vea / InRetail y 1 rotulada como Hipermercado Ceramicos. No asignar automaticamente a National, Tgestiona o Cassinelli por inferencia juridica.
- Se asociaron 10 sedes Makro con coincidencia comprobada. Cassinelli no tenia sedes comerciales de R1-B; Oechsle Chiclayo tenia opciones ambiguas, por lo que sus sedes quedaron sin vinculacion forzada.
- Todos los PDF contienen fecha documental de 2026 y moneda en soles; esos campos se guardaron.
- Todos los importes netos, impuestos y totales siguen NULL; price_review=pending hasta validacion; commercial_status=unverified mientras no exista prueba de aceptacion o envio formal.

## 3. Hallazgos de calidad

1. Numero RMX-2026-0212: dos documentos reales distintos de diferentes servicios/clientes. Permanecen como dos filas independientes; no hay constraint de unicidad del correlativo.
2. Un PDF de Cassinelli Piura: referencia impresa RMX-2026-0180; nombre de archivo RMX-2026-0199. Ambas referencias preservadas y reference_review=mismatch.
3. Cinco contratantes requieren homologacion antes de asignar un cliente comercial del directorio, no se crean organizaciones cliente nuevas.
4. La carpeta de cotizaciones enviadas no es evidencia de adjudicacion, conformidad, ejecucion ni pago. Todos los estados comerciales son unverified.
5. Precios de 2026 no deben utilizarse como lista vigente de costos; R1-D2 debe validar subtotal, IGV, total, unidades y lineas.

## 4. QA posterior en Supabase Cloud

| Verificacion | Resultado |
| --- | ---: |
| Cotizaciones historicas ROMAX | 25 |
| PDF principales vinculados | 25 |
| Fuentes de Drive unicas | 25 |
| Clientes homologados | 20 |
| Clientes por confirmar | 5 |
| Sedes inequívocas vinculadas | 10 |
| Discrepancias referencia archivo/PDF | 1 |
| Documentos sin fecha | 0 |
| Moneda faltante/distinta de PEN | 0 |
| Importes sin validar registrados como importes supuestamente reales | 0 |
| Cotizaciones erroneamente marcadas como aprobadas | 0 |
| Asociaciones entre tenants/clientes erróneos | 0 |
| Reintento idempotente de un registro historico | 0 duplicados |
| Reintento idempotente de documento | 0 duplicados |
| Lectura owner ROMAX bajo rol authenticated | 25 cotizaciones / 25 documentos |
| Lectura miembro de otra organizacion bajo rol authenticated | 0 cotizaciones / 0 documentos |
| RLS en ambas tablas | ENABLED |
| Acceso anon SELECT | Denegado |
| INSERT/UPDATE desde rol authenticated | Denegado |

**Sin regresion:** 10 organizaciones, 33 solicitudes, 22 cotizaciones operativas, 6 clientes ROMAX, 145 sedes ROMAX, 170 contactos ROMAX y 284 vinculos contacto-sede permanecen con sus conteos de referencia.

## 5. Acciones siguientes (gates separados)

1. **R1-D2**: conciliar precios por PDF y por sus XLSX cuando existan, separando neto, IGV, bruto, mano de obra, materiales, gastos generales, utilidad, unidades y partidas; revisar discrepancias financieras antes de marcar price_review=verified. No hacer calculos con campos ambiguos.
2. **Contratantes pendientes:** validar la razon social/relacion comercial de Plaza Vea / InRetail y Hipermercado Ceramicos, sin asociar automaticamente a intermediarios existentes.
3. **R1-E:** pantalla de consulta del historico para ROMAX con filtros cliente, sede, fecha, correlativo y servicio; enlazar la fuente de forma autorizada, respetando RLS. No exponer IDs privados de Drive en vistas publicas.
4. Mantener R1-B excepciones de 19 contactos e H16 como backlog separado; no bloquean la consulta de historicos.

**Privacidad:** este informe publico solo contiene conteos y diferencias de correlativos, sin nombres personales, correos, precios, credenciales, identificadores de Drive ni URLs privadas.
