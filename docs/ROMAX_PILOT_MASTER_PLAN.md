# One Facility — Plan maestro y continuidad del piloto ROMAX

**Actualizado:** 27-nov-2026 · **Responsable funcional:** equipo ROMAX / One Facility · **Objetivo:** agilizar y ordenar la cotización de servicios de ROMAX sin obligar a sus clientes a usar el portal.

> Este archivo es el punto de reanudación cuando se agote el contexto del chat. Leer primero este plan, luego la documentación de la fase activa y verificar estado real en GitHub/Supabase antes de ejecutar cambios. Las fechas y estados se deben actualizar con evidencia, no por inferencia.

## 1. Bases aprobadas

- ROMAX es organización real de tipo proveedor (provider_company); sus clientes comerciales NO requieren organización cliente ni autenticación.
- Modelo híbrido: catálogo propio de clientes, sedes y contactos, con enlace futuro opcional a organización client_company real, explícito y administrativo.
- Prioridad del piloto: recepción y preparación de cotizaciones más rápidas; la ejecución completa de órdenes de trabajo y la integración Odoo son posteriores.
- Fuentes de verdad: base comercial y cotizaciones históricas de ROMAX en Drive, más el estado efectivo de One Facility en GitHub y Supabase. **No subir datos personales, presupuestos, adjuntos, tokens ni enlaces privados a este repositorio público.**
- Cotizaciones históricas NO implican trabajos adjudicados, aprobados ni precios de mercado vigentes.
- IA propone borradores y referencias; costos, márgenes, IGV y totales se calculan de forma determinista y son editables y auditables; aprobación humana inicialmente.
- Entrada por correo con OAuth mínimo alcance, bandeja de oportunidades propia de ROMAX, clasificación y deduplicación, sin crear solicitudes atribuidas falsamente a organizaciones cliente.
- Presupuesto interno S/1000 citado en reunión era ejemplo, no umbral de autoaprobación autorizado.

## 2. Sistema y puntos de verificación

- Repositorio: AlexisCasas/assetlink-connect-84223-8e482395 (público).
- Rama base: productization/mvp.
- Supabase proyecto productivo: OneFacility (ref hplchnsseylngjopgbtl).
- Organización ROMAX: a76fb740-78cf-4ed5-97dd-1e1e24fcab68; type provider_company.
- Producción alojada en Vercel; cambios de esquema no requieren modificar frontend si no se introduce interfaz.
- Convención: PR + QA aislado + merge autorizado + migración Supabase Cloud controlada + verificación de RLS/datos + documentar hallazgos.

## 3. Hitos y estado

| Etapa | Objetivo | Estado comprobado al 14-nov-2026 | Gate para cerrar |
| --- | --- | --- | --- |
| R0 | Organización ROMAX y primer usuario | Hecho: organización activa, un miembro activo owner | Login real y acceso en rol ROMAX; revalidar cuando aplique |
| R1-A | Modelo comercial híbrido | Cerrado: PR #98 y #99 mergeados; migración 20261114161357 aplicada; tablas vacías y RLS activo | PASS realizado en CI aislado y revisión SQL post-Cloud |
| R1-B | Depurar e importar clientes, sedes y contactos | **Carga principal PASS:** 6 clientes, 145 sedes, 170 contactos y 284 vínculos; quedan 19 excepciones y H16 | Revisar excepciones, confirmar siglas y cerrar lote sin ambigüedades |
| R1-C | Homologación de sedes y relaciones comerciales | Pendiente | Relación cliente-sede-contacto consistente, casos ambiguos resueltos |
| R1-D | Histórico de cotizaciones ROMAX 2026 | **R1-D1 PASS:** 25 PDFs importados, 20 clientes vinculados y 5 pendientes; **R1-D2 pendiente** de validación económica | Confirmar importes neto/IGV/bruto, revisar 5 contratantes y reutilización de partidas históricas |
| R1-E | Pantalla de consulta comercial/histórico | **En desarrollo PR:** ruta #quote-history, filtros cliente/sede/servicio/correlativo/fechas, 15 por página y detalle PDF | QA CI y revisión visual de 15 escenarios; merge/deploy solo tras autorización |
| R2 | Catálogo independiente de costos de materiales y mano de obra | Pendiente | Fecha de vigencia, unidad, moneda, proveedor y procedencia en cada costo |
| R3 | Captura Gmail cotizaciones | R3-GMAIL.2.2.1 PASS; R3-GMAIL.3 autorizado en GitHub | OAuth, deduplicación, filtro de correos relevantes, oportunidad a nombre de ROMAX |
| R4 | Cotizador asistido IA | Pendiente | Borrador con referencias verificables, números deterministas y revisión humana |
| R5 | Visita técnica estructurada | Pendiente | Horas, especialidad, cantidades, material, fotos y observaciones vinculadas al presupuesto |
| R6 | Gobernanza y plantilla oficial | Pendiente | Políticas ROMAX, aprobaciones internas, exportación/emisión y trazabilidad |

## 4. R1-A ya realizado (evidencia)

- PR #98: https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/pull/98
- PR #99: https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/pull/99
- Esquema aplicado: supabase/migrations/20261114161357_provider_commercial_directory.sql
- Tablas: commercial_clients, commercial_client_sites, commercial_client_contacts. Todas con RLS, tres políticas por tabla y sin acceso anónimo.
- FKs compuestas protegen pertenencia entre proveedor/cliente/sede/contacto; columnas propietario/padre no pueden modificarse en la web.
- Verificación post-migración: 10 organizaciones, 33 solicitudes y 22 cotizaciones existentes intactas; nuevas tablas inicialmente vacías.
- No se usa provider_commercial_clients legado por su modelo/lectura amplia. No se modificaron requests/quotes ni se desplegó UI en R1-A.

## 5. R1-B: contrato de importación

**Fuente primaria de contactos:** Base_Consolidada_Contactos_Clientes.xlsx bajo la carpeta privada ROMAX / CLIENTES / BASE DE DATOS. No almacenar su URL, ID, filas, correos, nombres ni teléfonos aquí.

1. Fuente XLSX inmutable; leer y calcular checksum/verificar versión, preservar identificador de fila de origen internamente.
2. Excluir encabezados repetidos, subtotales y total general; deduplicar filas completas normalizadas. No borrar registros originales.
3. Catalogar clientes según etiquetas originales, sin inventar razón social o RUC; Sodimac / Maestro se mantiene como agrupación provisional hasta verificar titular de cotización.
4. Sedes: nombres exactos de fuente primero; mapeo de alias confirmado antes de unir Makro MK/MKR y nombres compuestos de Tgestiona. Un nombre compuesto no es automáticamente un local físico.
5. Contactos: preservar persona, cargo, correo, teléfono y observación originales; un mismo correo puede pertenecer a varias sedes. Nunca deduplicar globalmente solo por correo.
6. Trazabilidad: source_system y source_key estables, únicos por organización, para reejecución idempotente. Comparar COUNT esperados y excepciones antes/después.
7. La información comercial privada se escribe solamente en Supabase con tenant ROMAX; nunca en GitHub público.
8. Una carga parcial solo se da por cerrada si registra claramente qué entidades ya entraron y cuáles están pendientes.

### Mapeo preliminar (sujeto a calidad)

| Columna fuente | Destino / regla |
| --- | --- |
| Cliente | commercial_clients.business_name; catálogo lógico, no nueva organización |
| Tienda / sede | commercial_client_sites.site_name, solo si representa sede identificable |
| Nombre del contacto | commercial_client_contacts.full_name |
| Cargo / nivel | commercial_client_contacts.job_title |
| Celular | commercial_client_contacts.phone como texto, sin perder múltiples números |
| Correo electrónico | commercial_client_contacts.email |
| Región / zona | candidate de site.region; si valores codificados, guardar fuente hasta homologar |
| Dirección | commercial_client_sites.address cuando corresponde inequívocamente |
| Archivo de origen | procedencia documentada y source_key estable |
| Observaciones | notas internas de importación pertinentes, sin publicación en GitHub |

## 6. Gates QA obligatorios

- **Seguridad:** RLS cruzada entre ROMAX y otro proveedor; outsider sin lectura; owner/admin/manager con escritura; viewer solo lectura. Sin grant de anon o hard DELETE web.
- **Integridad:** FKs mismo tenant, misma empresa y sede; enlace futuro a client_company no ejecutado automáticamente.
- **Calidad:** filas fuente reconciliadas, alias ambiguos en cuarentena, duplicados exactos eliminados, claves reejecutables; personas compartidas entre sedes no desaparecen.
- **Operación:** no crear falsas solicitudes cliente, ni tocar las 33 solicitudes y 22 cotizaciones preexistentes de la línea de base.
- **Documentación:** registrar PR, commit, versión de migración, conteos, excepciones y siguiente paso; comprobar estado real antes de dar PASS.

## 7. Decisiones pendientes

- Confirmar si Sodimac / Maestro se gestiona como una agrupación comercial o dos clientes con facturación separada.
- Aprobar equivalencias de nombres de sedes MK / MKR y abreviaturas de otras cadenas.
- Definir qué correos y roles de contacto se usan para cotizar frente a seguimiento operativo.
- Seleccionar cotizaciones 2026 del piloto y calificar su vigencia/calidad.
- Definir política formal de aprobación ROMAX y plantilla oficial.
- Revisar permisos de compartición de los archivos fuente de Drive antes de operaciones automatizadas.

## 8. Siguiente acción técnica

Continuar R1-B con el inventario de clientes y el subconjunto de datos sin ambigüedades; guardar auditoría cuantitativa en docs/ROMAX_R1B_SOURCE_AUDIT.md. No integrar cambios de interfaz ni IA antes de cerrar trazabilidad de los maestros.

## 9. Último estado operativo verificado (14-nov-2026)

**Supabase Cloud OneFacility / ROMAX:** 6 clientes comerciales con procedencia romax_contactos_consolidados_20261109 y source_key única (Cassinelli, Makro, National, Oechsle, Sodimac / Maestro, Tgestiona). 0 sedes y 0 contactos comerciales importados. No se inventó razón social o RUC y no hay vínculo client_company externo. Conteos heredados sin cambios: 10 organizaciones, 33 solicitudes y 22 cotizaciones.

**Homologación revisada:** el Excel original consta de ocho hojas, incluido BASE GENERAL, seis hojas por cliente y RESUMEN. BASE GENERAL y las hojas individuales contienen el mismo universo de 289 fichas, no duplicados accidentales dentro de un mismo origen. Se identificaron 160 etiquetas de sede en bruto; 54 corresponden a Makro y permiten proponer 27 agrupaciones. Se entregó una matriz de homologación privada con 17 decisiones identificadas H01-H17, con archivo/hoja/fila. Ver docs/ROMAX_R1B_HOMOLOGATION_GATE.md.

**Siguiente gate:** esperar validación de ROMAX en H01-H17 (prioridad alta primero) antes de fusionar grupos ambiguos o asignar contactos. La matriz de revisión contiene datos operativos del cliente y NO debe subirse al repositorio público. En Cloud siguen 6 clientes, 0 sedes, 0 contactos salvo verificación nueva.

## 10. Resultado de homologación confirmado por ROMAX (14-nov-2026)

ROMAX respondió H01–H15 y H17; **H16 queda pendiente**: qué significan PVS/PVH/PVE/VIV y a nombre de quién se factura. Las siglas se preservaron literalmente. Regla H01: Makro Surco tienda y Oficina Central separadas; H02 SMP (REX) separado de SMP - MK; H03 sin número separado de sucursal 1 de Arequipa, Piura, Trujillo y Zárate. National es FM intermediario que opera comercialmente como cliente de ROMAX (registrado en sus notas), sin nueva organización. SFERA/MAC se conservan como sedes diferentes. Sodimac/Maestro continúa agrupado hasta revisar cotizaciones. Grupos Tgestiona desdoblados: H10 3, H11 3, H12 2, H13 3, H14 2, sin asignación arbitraria de contactos. TIENDA (National) y TIENDAS VARIAS (ITSE) no se importan como sedes. Los contactos sin sede quedan a nivel cliente.

**Carga L2 real verificada en Supabase Cloud:** 145 sedes en commercial_client_sites con source_system=romax_r1b_homologation_20261114, 145 source_key distintas: Makro 33, National 8, Oechsle 31, Sodimac / Maestro 54, Tgestiona 19, Cassinelli 0. Clientes=6; contactos=0; organizaciones=10; solicitudes=33; cotizaciones=22. No se ha cambiado el esquema, clientes externos ni la UI. El libro privado de homologación revisado conserva la relación entre etiqueta y celda fuente. Ver docs/ROMAX_R1B_HOMOLOGATION_DECISIONS.md.

**Hito realizado después:** PR #103 mergeado; migración 20261114165704 activó commercial_client_contact_sites. Lote L3 importado y verificado: 170 contactos con 284 enlaces, manteniendo 19 filas en revisión. Véase sección 11 y docs/ROMAX_R1B_CONTACTS_IMPORT_QA.md.

## 11. R1-B L3 — Contactos importados y verificados (14-nov-2026)

**Resultado productivo comprobado:** 6 clientes, 145 sedes, 170 contactos comerciales y 284 asociaciones contacto-sede en ROMAX. Contactos con varias sedes: 20. Todos tienen claves de importación únicas, 0 asociaciones de otro cliente/organización. Validación RLS con owner ROMAX: 170 contactos/284 vínculos visibles; un miembro de otra organización ve 0/0. Idempotencia: reinsertar un contacto o vínculo existente devolvió 0 nuevos. Baseline original intacta: 10 organizaciones, 33 requests, 22 quotes.

**Depuración:** 289 fichas de fuente, 270 filas utilizables, 19 en cuarentena (5 marcadores no personales National, 8 sin nombre Oechsle, 6 filas con dos nombres Tgestiona). Un par de variantes de un mismo contacto Sodimac/Maestro con mismo correo/teléfono/sede se consolidó en una identidad, resultando 170 en lugar de los 171 inicialmente previstos. La matriz privada de excepciones contiene hoja/celda exacta; no está en GitHub público.

**Próximo paso:** ROMAX confirma las 19 excepciones y H16 (siglas PVS/PVH/PVE/VIV). Continuar R1-D con el histórico de cotizaciones 2026 (lote piloto y estado documental), sin crear solicitudes artificiales. No se requirió cambiar interfaz ni desplegar Vercel para la carga del directorio.

## 12. Preparacion R1-D - Historico 2026 (14-nov-2026)

Se inspeccionaron 25 PDFs reales en las carpetas ROMAX de cotizaciones 2026, seleccionados de varios responsables: 10 de Makro, 10 Cassinelli/HMC, 1 Oechsle y 4 Plaza Vea/InRetail (no homologados en el directorio). El numero del PDF puede diferir del numero en el nombre del archivo, y hay correlativos repetidos en propuestas de distintos trabajos. No se mezclaran importaciones por numero; la clave sera el archivo y su procedencia. En esta fase importes quedan pendientes de validacion documental por neto/IGV, y la carpeta de enviados no confirma aceptacion. Modelo propuesto: commercial_quote_history + commercial_quote_history_documents, RLS lectura solo ROMAX, sin escrituras desde web. Ver docs/ROMAX_R1D_HISTORICAL_QUOTES.md.

Gate: CI de migraciones y pruebas pgTAP en Supabase local, merge, migracion Cloud, carga piloto de 25 y QA de identidad, ausencia de duplicados y aislamiento antes de pasar a R1-E. La muestra no valida automaticamente la relacion entre Plaza Vea y Tgestiona/National, ni convierte cotizaciones en precios vigentes.

## 13. Estado R1-D1 - Historico importado en Supabase Cloud (14-nov-2026)

**Hito confirmado:** PR #105 mergeado; dos suites de QA GitHub Actions PASS. Se crearon en produccion las tablas commercial_quote_history y commercial_quote_history_documents con RLS lectura exclusiva de miembros del proveedor y sin permisos de escritura desde frontend. Migracion 20261114172357, sincronizada en PR de cierre. Se importaron 25 cotizaciones PDF, 25 documentos de origen, 25 source_keys distintas (lote romax_r1d_2026_pdf_pilot_20261114), con fechas 2026 y moneda PEN verificadas en documentos.

**Conciliacion:** 20 vinculadas a cliente del directorio (Makro 10, Cassinelli 9, Oechsle 1), 5 sin vinculo automatico de contratante (cuatro Plaza Vea/InRetail y una Hipermercado Ceramicos). Se vincularon 10 sedes Makro exactas; sin forzar Cassinelli u Oechsle Chiclayo. Correlativo RMX-2026-0212 repetido para dos propuestas; diferencia entre el nombre de PDF RMX-2026-0199 y su referencia interna RMX-2026-0180 preservada. No se altero ni se certifico ningun precio: neto, IGV y bruto NULL, price_review=pending, commercial_status=unverified.

**QA Cloud:** owner ROMAX lee 25 cotizaciones y 25 documentos; usuario activo de otra organizacion lee 0/0. 0 duplicados en reintento de cotizacion o documento, 0 referencias entre tenants equivocados, 0 documentos sin fecha, 0 variaciones en conteos productivos base: organizaciones 10, solicitudes 33, cotizaciones operativas 22; directorio ROMAX 6 clientes, 145 sedes, 170 contactos y 284 vinculos.

**Siguiente desarrollo:** R1-E, pantalla de busqueda comercial de historial ROMAX, para aprovechar el piloto; en paralelo R1-D2, conciliacion de importes y partidas contra fuente PDF/XLSX. Mantener pendiente la validacion de los cinco contratantes, los 19 contactos excepcionales R1-B y H16. Ninguno de estos pendientes se corrige mediante suposiciones. No hubo despliegue de frontend o Vercel durante R1-D1. Evidencia: docs/ROMAX_R1D_PILOT_IMPORT_QA.md y docs/ROMAX_R1D_HISTORICAL_QUOTES.md.

## 14. R1-E - Pantalla de consulta del historico (14-nov-2026)

Se desarrollo en rama de PR una pantalla web de consulta para organizaciones provider_company activas, con nueva ruta #quote-history, menu Histórico cotizaciones, filtros por cliente comercial, sede homologada, servicio, fecha y correlativo. El usuario elige referencia impresa en PDF o numero de archivo, preservando discrepancias (caso 0180/0199) y el numero duplicado 0212 en dos trabajos distintos. Tabla paginada (15/page) y detalle PDF obtenido bajo demanda; al abrir Drive se requieren sus permisos propios. Se muestran 5 contratantes no homologados y ningun importe de los 25 hasta validar los costos en R1-D2.

Gates: PR, compilacion/lint/regresion, evaluacion visual de escenarios E1-E15, luego merge y despliegue Vercel de forma controlada tras autorizacion. Sin cambios de SQL ni permisos productivos en R1-E; RLS server de R1-D1 sigue vigente. Ver docs/ROMAX_R1E_HISTORICAL_QUOTES_UI.md. Una vez desplegado, registrar URL/SHA y QA real. El desarrollo no resuelve por si mismo los 5 contratantes, 19 excepciones de contactos ni H16.


## 15. Correctivo R1-D2A - Detalle de servicios, materiales y costos

**Hallazgo tras despliegue R1-E:** el usuario detecto que la pantalla no mostraba el listado de servicios ni los materiales/precios presentes en los PDF, requisito para la futura investigacion historica con IA. Se reviso directamente la cotizacion RMX-2026-6200 Makro Huacho (2 paginas) y se confirmaron cinco partidas y cinco componentes economicos, con total sin IGV conservado solo en Supabase.

**Solucion implementada (PR #108):** tres nuevas tablas para partidas, componentes y texto extraido del PDF; referencias por pagina, revision por valor, RLS y lectura por demanda en detalle. Guardar los 25 textos de PDF como material documental raw_unverified, pero estructurar valores y cantidades solo despues de validacion del formato visual/Excel de origen. Primer ejemplo estructurado: RMX-2026-6200. No convertir valores historicos sin verificar en lista vigente para IA.

**Control:** ejecutar QA aislado, comprobar importacion y aislamiento entre organizaciones, despues merge/migracion/despliegue de frontend con seguridad. La fase R1-D2 completa seguira abierta hasta verificar las partidas de los restantes 24 documentos y el IGV. Ver docs/ROMAX_R1D2_QUOTE_LINE_ITEMS.md.

**QA R1-D2A aplicado (14-nov-2026):** PR #108 PASS; migracion Supabase 20261114182230; 25 textos documentales privados y 5 partidas + 5 componentes estructurados del ejemplo RMX-2026-6200, sin precios inventados. Seguridad RLS ROMAX 25/5/5 vs otro tenant 0/0/0. Los restantes 24 PDFs siguen pendientes de homologacion de partidas. PR de continuidad sincroniza version Cloud y documentos. Ver docs/ROMAX_R1D2A_IMPORT_QA.md.



## 16. R1-D2B - Presentacion tabular reutilizada (14-nov-2026)

Hallazgo del QA visual de ROMAX: en cotizaciones como RMX-2026-4087, la transcripcion de PDF se mostraba en un bloque de texto sin estructura, mientras el cotizador operativo ya tenia un esquema tabular de partidas. Se reutilizo la presentacion de QuoteForm mediante el componente compartido QuoteItemsTable, manteniendo el editor y habilitando un modo de consulta historica solo lectura.

Las cotizaciones con partidas estructuradas muestran tablas por servicio/material con descripcion, cantidad, unidad, tarifa y parcial, y un resumen economico tabular con origen por pagina y revision. Las otras 24 conservan tablas en estado pendiente y el texto fuente se presenta como transcripcion por filas (no homologadas), sin asociar cantidades y precios de forma especulativa.

El desarrollo esta en PR y debe pasar build, QA visual y regresiones antes de cualquier merge o deploy a Vercel Production. No hay nuevas migraciones ni cambios a Supabase Cloud. Ver docs/ROMAX_R1D2B_TABULAR_HISTORY_UI.md para checklist T1-T8.


## 17. R1-D2C — Auditoria multi-formato e inicio de homologacion (14-nov-2026)

Se revisaron los 25 textos de PDF en ROMAX y los documentos fuente de muestra, mas la plantilla Excel oficial 2026 de tres hojas. Familias documentales: 15 clasicos, 7 de propuesta economica detallada, 2 por metrajes, 1 mixto. No se puede homologar solo por correlativo porque existen numeros duplicados y diferencias entre archivo y PDF.

**Contrato aprobado para piloto:** conservar partidas de servicios/materiales solo cuando se asocien de forma respaldada con cantidad/unidad/precio; separar costos internos de precios de venta; mantener resumen neto/IGV/bruto cuando la evidencia lo soporte; agregar secciones tecnicas, seguridad, soporte y condiciones comerciales como datos narrativos protegidos por tenant. Las paginas de PDF desconocidas permanecen NULL. El primer caso nuevo es RMX-2026-4087 (formato detallado), comparado con RMX-2026-6200 (clasico previamente estructurado). No adjudicar importes de filas numericas a textos del PDF aplanado de 4087 hasta validar su tabla visual o fuente Excel.

Nueva tabla commercial_quote_history_sections y consulta UI bajo RLS; se mantiene la separacion extracted_unverified versus verified. Plan de QA: CI de migraciones, RLS de nuevo tenant, cotejo del resumen financiero del piloto, idempotencia y lectura visual en Vercel. El resto del lote no se importa automaticamente. Ver docs/ROMAX_R1D2C_HOMOLOGATION_AUDIT_PILOT.md.

**R1-D2C piloto aplicado y verificado (14-nov-2026):** PR #111 mergeado, migracion 20261114213637 en Supabase Cloud, 6 secciones y 3 componentes financieros extraidos sin homologacion de precio por partida del PDF 4087. RLS 6/3 ROMAX versus 0/0 otro tenant; tres sumas de conciliacion financiera PASS; idempotencia PASS, sin regresiones de datos operativos. Documentacion tecnica y QA: docs/ROMAX_R1D2C_PILOT_QA.md. Las otras cotizaciones no se han homologado de forma masiva.

## 18. R1-D2D - Correccion de fuente visual RMX-2026-4087 (14-nov-2026)

Se reviso el PDF original renderizado (una pagina). Hallazgo: en la propuesta economica del documento, la instalacion de ventiladores/extractores es un grupo con tres partidas valorizadas (suministro/instalacion, sistema electrico y puesta a tierra). La homologacion previa habia clasificado erroneamente las ultimas dos como aclaraciones tecnicas, y habia mezclado las cuatro notas tecnicas autenticas con soporte de gestion.

Correctivo: vincular las tres filas y sus precios exactos solo al documento 4087, separar las notas tecnicas 2.1-2.4, seguridad 3.1-3.6, gestion 4.1-4.6, resumen 5.1-5.3 y condiciones 6.1-6.5; la forma de pago no esta consignada. Fuente pagina 1. El PDF no contiene una lista de materiales independiente, por lo que no debe mostrarse una tabla extra vacia para ese formato. En UI, mostrar titulo de grupo una vez con las tres partidas y evitar duplicar resumen y alcance en las notas complementarias. No elevar precios a verificados/vigentes ni tocar otros documentos o cotizaciones operativas. Ver docs/ROMAX_R1D2D_PDF_VISUAL_CORRECTION.md.

**QA R1-D2D registrado:** revisión visual del PDF 4087 (página única) PASS; tres líneas de servicio y sus precios fieles a fuente, seis secciones reclasificadas con página 1 y tres componentes económicos; conciliación neto/IGV/total PASS; RLS 3/6/3 para ROMAX frente a 0/0/0 para otro tenant. CI original del PR #113: 4 suites PASS, Vercel Preview READY. Cambios de datos del caso piloto aplicados a Supabase Cloud; frontend pendiente de merge/deploy a producción. No se modificaron otros 24 documentos ni los módulos operativos. Ver docs/ROMAX_R1D2D_PDF_VISUAL_CORRECTION.md.


## 19. R1-D2E — Primer lote de cuatro clásicos (14-nov-2026)

Se cargaron en Supabase Cloud las cotizaciones RMX-2026-2215, 2217, 2218 y 2219, ya existentes en el histórico. Se conservaron sus identidades por archivo y sus estados comerciales; no hubo nuevas solicitudes ni nuevas cotizaciones operativas. Los datos documentales agregados fueron 17 partidas descriptivas, 16 secciones de alcance/técnica/seguridad/condiciones y 19 componentes económicos, todos bajo el tenant ROMAX y sin elevar precios a verificados.

QA Cloud: los cuatro netos del resumen concilian con la suma de sus componentes; owner ROMAX 17/16/19 registros visibles frente a usuario ajeno 0/0/0, reintentos 0 duplicados. Las excepciones principales son: 2217 tiene una diferencia no explicada entre la partida de agua identificable y el subtotal de materiales; 2218 conserva cuatro materiales sin atribuirles cifras; 2215 requiere confirmar distribución entre actividades; 2219 exige cotejar visualmente el servicio y su única línea económica. Ninguna excepción fue completada mediante suposiciones.

Este lote todavía requiere cotejo visual/PDF o XLSX fuente para considerarse homologación financiera definitiva. El frontend productivo existente consume las tablas, por lo que no se necesitó desplegar Vercel. Informe detallado: docs/ROMAX_R1D2E_CLASSIC_BATCH1_QA.md. Mantener los próximos grupos de 3 a 5 documentos y gates de RLS y conciliación idénticos.


## 20. R1-D2E2 - Subtotales de secciones del lote clasico (14-nov-2026)

Se revisaron con el usuario las cotizaciones RMX-2026-2215, 2217 y 2218, confirmando que el encabezado gris de "Listado de servicios" debe reflejar el subtotal documental del grupo, sin confundir la primera descripcion con un encabezado. Igual criterio para el subtotal de "Descripcion de materiales y consumibles". Los servicios y materiales sin desglose unitario permanecen en filas separadas sin importes inventados.

En la cotizacion 2217 el usuario confirmo que el unico servicio lleva el subtotal documental correspondiente. La fila de servicio se actualizo en Supabase Cloud con dicho **parcial** y sin asignar unidad, cantidad ni precio unitario artificial. El PDF contiene un precio unitario y parcial de cisterna que no explican totalmente su subtotal de materiales: la interfaz presenta las cifras de fuente, diferencia y un equivalente global **calculado**, sin reemplazar el precio original ni inferir IGV.

El formato detallado (4087) conserva su grupo original; el 2219 permanece sin cambios de datos. Implementacion frontend en PR R1-D2E2: subtotal proveniente de componentes economicos, no de la suma incompleta de lineas. Mantener RLS, no elevar estados de revision y verificar CI/Vercel antes de publicar. Ver docs/ROMAX_R1D2E2_SECTION_SUBTOTAL_QA.md.


## 21. R1-D2F — Segundo lote de cuatro cotizaciones clásicas (14-nov-2026)

**Despliegue verificado:** Vercel producción `one-facility.vercel.app` en estado READY, con el componente de históricos actualizado de PR #115. No fue necesario desplegar código para este lote.

**Documentos cargados:** RMX-2026-2210, 2221, 4084 y 5162, vinculados a los PDF originales de Google Drive y cotejados visualmente (cinco páginas). Se incorporaron a Supabase Cloud **22 partidas** (14 de servicios y 8 de materiales/equipos), **16 secciones documentales** y **19 componentes económicos**, sin modificar cabeceras ni inventar unitarios para servicios agrupados.

**Conciliación:** tres documentos cuadran exactamente; uno (4084) muestra el total neto del PDF redondeado a soles enteros, mientras la suma de componentes tiene céntimos. Se preservó el total impreso, el desglose real y `needs_review` para ese total sin generar una línea artificial. IGV no incluido en documentos, por lo que no se agregaron impuestos no declarados.

**QA real:** RLS owner ROMAX 22/16/19 frente a otro tenant 0/0/0; errores de cálculo de partidas 0; estados `verified` asignados por error 0; reimportación idempotente 0 duplicados; solicitudes y cotizaciones operativas conservadas (33/22). Totales acumulados ROMAX: 47 partidas, 38 secciones y 46 componentes, con 25 PDFs/textos originales intactos.

**Pendientes:** seis documentos clásicos por estructurar, luego seis propuestas detalladas, dos formatos de metraje y uno mixto. La fidelidad al PDF no equivale a aprobar tarifas vigentes para la IA. Ver informe `docs/ROMAX_R1D2F_CLASSIC_BATCH2_QA.md`.


## 22. R1-D2G — Tercer lote clásico documentado (14-nov-2026)

Se verificaron visualmente los PDF originales RMX-2026-0197, RMX-2026-5160 y RMX-2026-5161 (4 páginas). En Supabase Cloud se cargaron **23 partidas** (12 servicios y 11 materiales/equipos), **12 secciones narrativas** y **15 componentes financieros**. Se respetan las cantidades y tarifas de materiales del documento original, sin asignar precios unitarios a actividades con solo subtotal grupal.

**QA de importación:** tres subtotales de materiales concilian exactamente con sus partidas; los grupos económicos cuadran en 0197 y 5161; en 5160 se conserva la discrepancia entre suma con céntimos y total entero redondeado, `needs_review`, sin ajuste artificial. RLS ROMAX 23/12/15, otro tenant 0/0/0, multiplicaciones erradas 0, duplicados 0, promociones comerciales a `verified` 0. Los documentos originales, las 33 solicitudes y las 22 cotizaciones operativas se preservan.

**Progreso:** 13 de 25 cotizaciones estructuradas. Acumulado ROMAX 70 partidas, 50 secciones y 61 componentes. Restan **3 clásicos** (5063, 6167, 6195), **6 detalladas**, **2 por metraje** y **1 mixta**. Vercel productivo READY, sin requerirse despliegue para este lote. Informe: `docs/ROMAX_R1D2G_CLASSIC_BATCH3_QA.md`.


## 23. R1-D2H — Cuarto lote clásico, familia estructurada (14-nov-2026)

Se revisaron visualmente los PDF originales **RMX-2026-5063, 6167 y 6195** (5 páginas) y se incorporaron **32 partidas**, **10 secciones narrativas** y **15 componentes económicos** al histórico privado de ROMAX. Las cantidades y tarifas de materiales concilian en los tres documentos; los servicios sin desglose individual conservan el subtotal de mano de obra del PDF sin repartirlo artificialmente.

Excepciones documentadas: 5063 y 6195 presentan redondeo entre componentes monetarios y total neto impreso; la primera actividad de 6195 dice «Cambio de 30 porcelanatos», pero la columna de cantidad muestra 38, ambas evidencias preservadas con `needs_review`. En 6167 y 6195 la sección de aclaraciones técnicas únicamente contiene la letra «C» y no se convirtió en una aclaración inventada.

QA de Supabase: 0 errores de multiplicación, 0 precios de servicio inferidos, 0 promociones de revisión comercial, reintento de importación 0 duplicados y **RLS propietario ROMAX 32/10/15 frente a otro tenant 0/0/0**. No cambiaron los 25 documentos, 33 solicitudes ni 22 cotizaciones operativas; no se requirió desplegar Vercel.

**Progreso:** 16 de 25 cotizaciones estructuradas, con acumulados de 102 partidas, 60 secciones y 76 componentes. **Familia clásica estructurada; quedan 6 detalladas, 2 por metrajes y 1 mixta**. La estructuración fiel al documento no constituye aprobación comercial ni vigencia de sus tarifas. Informe completo: `docs/ROMAX_R1D2H_CLASSIC_BATCH4_QA.md`.


## 24. R1-D2I — Primer lote de propuestas económicas detalladas (14-nov-2026)

Se cotejaron visualmente 6 páginas de los originales ROMAX 0199 (impreso 0180), 0212 Cassinelli Piura y 0209 Hipermercado Cerámicos Larco. Se insertaron **21 partidas**, **12 secciones narrativas** y **9 componentes de resumen** en Supabase Cloud; la guardia de escritura validó tenant ROMAX, identidad documental exacta y ausencia de detalle previo. Grupos valorizados y subpartidas se conservan como jerarquías; sus cifras no se suman dos veces. En 0209 se mantuvieron precios unitarios NULL en las subpartidas donde el PDF visual no presenta importes, y se preservó la numeración repetida 2.1/2.2 del tercer grupo. Todos los nuevos registros siguen `extracted_unverified`, sin aprobación comercial.

**QA:** 3/3 conciliaciones subtotal + IGV = total y grupos contra neto; 0 errores en las filas con cantidades y precios completos; 0 relaciones intertenant inconsistentes; políticas RLS verificadas sin modificación. No se hizo impersonación con sesión de otra organización ni prueba de reintento mediante segunda escritura: gates restantes si se exige certificación integral. Base operativa sin cambios (33 solicitudes, 22 cotizaciones) y 25 PDF/textos históricos intactos. **Progreso: 19/25**, acumulado **123 partidas, 72 secciones, 85 componentes**. Quedan **6 documentos** (3 detallados, 2 por metraje y 1 mixto). No hubo despliegue Vercel ni cambios a Drive. Informe: `docs/ROMAX_R1D2I_DETAILED_BATCH1_QA.md`.


## R1-D2J — Segundo lote detallado (14-nov-2026)

Se realizó cotejo visual de los 8 folios de **0212 Plaza Center Higuereta**, **4071 Cassinelli Ate** y **4085 HMC VES**, separados estrictamente por `history_id` y `source_file_id`. Se cargaron **50 filas históricas**, **13 secciones** y **12 componentes** en Supabase Cloud (sin duplicar grupos y subpartidas ni crear precios faltantes). **QA SQL 3/3 PASS** para suma de detalles, subtotales, IGV y totales; 0 errores aritméticos; 0 cruces indebidos de organización; se preserva `extracted_unverified`. Histórico consolidado **22/25 (88 %)**; 173 partidas, 85 secciones, 97 componentes. Los originales y la operativa no cambiaron. **Pendientes:** 4080 (clásico por categorías), 5076 (metraje/cantidad) y 5152 (mixto). La validación de pantalla y despliegue del correctivo R1-D2I-FIX siguen independientes. Documento: `docs/ROMAX_R1D2J_DETAILED_BATCH2_QA.md`.


## R1-D2K — Cierre de estructuración del piloto (14-nov-2026)

Se cotejaron visualmente los tres PDF restantes **4080 Makro Arequipa 2, 5076 Cassinelli Chiclayo y 5152 Cassinelli Piura** y se incorporaron en Supabase **13 partidas, 8 secciones y 12 componentes**. Se protegió la escritura con verificación por `history_id`, `source_file_id`, organización y cabecera, además de rechazo si existía detalle previo. QA SQL: 0 errores en partidas con unitarios/parciales explícitos, 0 cruces de organización, y conciliación económica en los tres documentos. Particularidades conservadas: 4080 incluye movilidad como componente separado pero no reporta IGV/bruto; 5076 contiene dos parciales con unitarios ausentes; 5152 conserva dos grupos como encabezados no sumables y tres subpartidas valorizadas.

**Cierre de extracción estructural: 25/25 históricos (100 %), con 186 partidas, 93 secciones y 109 componentes; pendientes estructurales 0.** Se mantuvieron 25 originales y extractos, así como 33 solicitudes y 22 cotizaciones operativas sin cambios. Los nuevos detalles siguen `extracted_unverified` y no se consideran precios comerciales vigentes. Quedan pendientes el QA visual real de usuario, certificación de sesiones/RLS, revisión de advertencias documentales y despliegue del correctivo UI `R1-D2I-FIX` cuando se habilite Vercel. Informe: `docs/ROMAX_R1D2K_FINAL_PILOT_QA.md`.


## Cierre de excepción documental RMX-2026-2217 — 16-nov-2026

Por confirmación y autorización expresa del usuario, la línea **CISTERNA DE AGUA** se corrigió en Supabase Cloud a cantidad 40 M3, unitario equivalente **S/ 53.75** y parcial **S/ 2,150**, conciliando con el subtotal 4.2 de materiales. La fila y el componente quedaron `extracted_unverified`. El PDF fuente conserva visiblemente S/ 45 / S/ 1,800; esa diferencia se registra en la procedencia de la línea, y el original no se modifica. QA: 40 × 53.75 = 2,150; línea = componente materiales; componentes 4.1–4.4 = neto S/ 3,360. La excepción queda cerrada por decisión del usuario, sin aprobar el valor como tarifa comercial vigente. Evidencia: `docs/ROMAX_R1D2E_CLASSIC_BATCH1_QA.md`.


## R2A — Catálogo independiente de costos: contrato técnico e implementación preparada (17-nov-2026)

Decisiones aprobadas por ROMAX: fuentes mixtas (proveedores y costos internos); costo separado de precio de venta; revisión humana antes de activar; mano de obra por hora/jornada; vigencia sin vencimiento obligatorio; múltiples proveedores por recurso; conservar PEN/USD original y registrar conversión a PEN con FX documentado. El FX USD/PEN predeterminado será configurable por organización y no se inicializa con un valor inventado.

**Diseño simplificado:** se reutilizan `commercial_clients`, `commercial_client_sites` y `commercial_client_contacts`; no se duplican clientes. No se reutilizan `materials`/inventario ni el histórico de cotizaciones como tarifario. El proveedor es opcional en tarifas internas. Categorías/unidades son globales y predefinidas. La fuente y revisión se guardan en la tarifa, sin tabla separada de documentos/workflow en esta primera etapa. La utilidad e impuestos permanecen fuera del catálogo de recursos.

**Implementación preparada en rama `feature/romax-r2a-cost-catalog`:**
1. `20261117130000_romax_cost_catalog_foundation.sql`: categorías, unidades y configuración económica por organización.
2. `20261117130100_romax_cost_catalog_entities.sql`: proveedores y recursos.
3. `20261117130200_romax_cost_rates_versioning.sql`: tarifas, snapshot PEN, versionado concurrente, revisión, vigencia y RLS.

Test pgTAP preparado: `supabase/tests/romax_r2a_cost_catalog.test.sql` (21 aserciones; solo base local/desechable). Documento técnico: `docs/ROMAX_R2A_COST_CATALOG_TECHNICAL_DESIGN.md`.

**Estado honesto:** SQL y test escritos y sometidos a revisión estática inicial; pgTAP, aplicación de migraciones en local, advisors y CI todavía no ejecutados. No se aplicó nada en Supabase Cloud, no se crearon registros de negocio y no se desplegó Vercel. Los gates previos a Cloud son: ejecutar las tres migraciones en base desechable, correr las 21 pruebas, resolver fallos, ejecutar advisors y revisar PR. Se requiere autorización separada para aplicar a Supabase Cloud.


## R2A — Ejecución controlada migración 1 (17-nov-2026)

**R2A-01 PASS:** aplicadas en Supabase Cloud `20261117185721_romax_cost_catalog_foundation` y hardening `20261117185936_romax_cost_catalog_foundation_hardening`. Resultado 8 categorías, 13 unidades, RLS/grants verificados, FX no configurado y 0 filas settings persistentes. Pruebas transaccionales owner/actualización/aislamiento externo con ROLLBACK PASS. Advisors sin hallazgos de seguridad nuevos en las tablas R2A; los dos avisos de initplan y la FK sin índice se corrigieron. Queda un aviso de índice aún no usado, esperado por la tabla vacía. No se modificó el inventario ni cotizaciones existentes. Informe: `docs/ROMAX_R2A_01_FOUNDATION_QA.md`.

Siguiente paso: R2A-02 proveedores y recursos, con ejecución y pruebas independientes. R2A-03 no se aplica hasta cerrar R2A-02.


## R2A-02 — Proveedores y recursos (17-nov-2026)

**PASS:** aplicadas en Supabase Cloud `20261117191121_romax_cost_catalog_entities` y `20261117191257_romax_cost_catalog_entities_hardening`. Creadas `provider_cost_suppliers` y `provider_cost_items`, con RLS, políticas por organización, RUC/código únicos por organización, proveedor opcional en costos internos y sin hard delete desde authenticated. QA transaccional owner: altas de dos proveedores y un recurso; duplicados de RUC/código rechazados; `created_by` automático; usuario de otro tenant sin lectura; rollback y recuento posterior 0/0. Tras hardening, alta owner + rollback PASS. Advisors Security sin hallazgos nuevos; Performance conserva solo avisos `unused_index` esperados en tablas vacías. No se modificaron clientes, inventario ni cotizaciones. Informe: `docs/ROMAX_R2A_02_SUPPLIERS_ITEMS_QA.md`.

Siguiente gate: R2A-03 tarifas/versiones/aprobación, sin aplicar hasta cerrar su revisión y autorización.

## R2A-03 — Tarifas y versiones (17-nov-2026)

**PASS:** aplicadas en Supabase Cloud `20261117193442_romax_cost_rates_versioning`, `20261117193538_romax_cost_rates_guard_fix` y `20261117193631_romax_cost_rates_hardening`. Incluye tarifas, moneda original, snapshot FX a PEN, fuente, tratamiento tributario, versionado automático por serie recurso/proveedor, estados y aprobación básica, inmutabilidad tras aprobar y prevención de vigencias superpuestas. QA transaccional con rollback PASS: USD 100 × 3.75 = PEN 375; versión 1/2; autoaprobación auditada; edición de precio aprobado rechazada; cierre de vigencia y nueva versión permitidos; proveedor alternativo y costo interno sin proveedor; USD sin FX fechado rechazado; solapamiento rechazado; otro tenant sin lectura. Se detectó y corrigió un defecto del trigger que impedía cerrar vigencia por comparar la columna generada `unit_cost_pen`. Tras hardening, smoke insert owner PASS. Cero tarifas/proveedores/recursos/settings persistentes para ROMAX. Security Advisors sin hallazgos nuevos; performance sin nuevos FKs faltantes ni initplan, tres avisos unused_index esperables por tabla vacía. Informe: `docs/ROMAX_R2A_03_COST_RATES_VERSIONING_QA.md`.

**R2A completo:** migraciones 01, 02 y 03 aplicadas y probadas por separado. Siguiente trabajo: R2B interfaz y primeros datos reales bajo aprobación; R2C importación de fuentes; R2D revisión/flujo; R2E motor económico; R2F QA e integración futura con cotizador. No se modificó Vercel ni se integró aún el cotizador.

## R2B — Primera entrega UI: proveedores y recursos (17-nov-2026)

Se añadió `CostCatalogView` y navegación `#cost-catalog`, restringida a organizaciones `provider_company` y roles owner/admin/manager/quote_manager. Permite listar, buscar, crear, editar, activar y desactivar proveedores y recursos; consume categorías/unidades precargadas. No crea clientes, sedes ni contactos; no registra tarifas ni tipo de cambio. Preview Vercel del commit `b276b0a` quedó READY y el check Vercel en GitHub success. No hubo merge ni producción. No se crearon registros reales. **Pendiente:** QA CRUD y RLS en navegador con sesión ROMAX, prueba de rol no autorizado y aislamiento con otro tenant. Informe: `docs/ROMAX_R2B_SUPPLIERS_ITEMS_UI_QA.md`. Tras PASS, R2C tarifas y proveedores asociados.

## R2B cierre y R2C primera implementación (17-nov-2026)

**R2B confirmado PASS por usuario:** vista previa validada y altas reales desde la interfaz comprobadas en Cloud: 1 proveedor activo (Proveedor Test) y 1 recurso activo (Material Test 001, código PR001, MATERIAL/UND), creados por miembro autorizado ROMAX. Tarifas: 0; FX settings: 0. La confirmación cubre navegación, carga y altas; no declara edición/desactivación probadas.

**R2C implementado en código, pendiente de preview/QA:** pestaña Tarifas para alta de costos PEN/USD, proveedor opcional, fuente y referencia, IGV, vigencia y estado inicial pending_review. Añade formulario para configurar FX USD/PEN de ROMAX con valor positivo y fecha, sin inicializar un valor inventado. Cada tarifa conserva snapshot FX y número de versión generado en DB. Documento: `docs/ROMAX_R2C_RATE_ENTRY_DESIGN.md`.

**Bloqueo actual:** Vercel devolvió `build-rate-limit` para el commit que integra R2C; no hay preview READY con esta pestaña. No se hizo retry, merge ni producción. Siguiente gate: esperar disponibilidad de builds, obtener preview y ejecutar QA autenticado antes de cargar tarifas reales.

## Estado maestro actualizado — 18-nov-2026

### R1-D — Histórico
La extracción estructural del piloto quedó en **25/25 documentos (100 %)**, con **186 partidas, 93 secciones y 109 componentes**. Los datos estructurados permanecen `extracted_unverified`: son referencia histórica y no tarifario vigente. Quedan como gates separados el QA visual real de usuario, certificación de sesión/RLS y cierre de cualquier advertencia documental pendiente.

### R2 — Catálogo independiente de costos
R2A quedó completo en Supabase Cloud: foundation, proveedores/recursos y tarifas/versionado/revisión. R2B tiene UI y datos de prueba. R2C incorporó comparación de hasta cuatro alternativas y un seed controlado de **35 recursos normalizados** derivados del piloto, sin copiar precios históricos como tarifas.

Actualmente ROMAX tiene **36 recursos** en el catálogo (35 del seed + 1 recurso de prueba) y **2 tarifas de prueba**, ambas `pending_review`. No se han creado tarifas a partir de los precios de las 25 cotizaciones.

### R2D — Revisión de tarifas
Se implementó la bandeja de revisión en `CostRatesPanel`: aprobación/rechazo explícito, motivo obligatorio al rechazar y visualización de los datos que deben revisarse. Documento QA: `docs/ROMAX_R2D_RATE_REVIEW_QA.md`.

### Bloqueo operativo actual
El check de Vercel del PR #120 está fallando con `upgradeToPro=build-rate-limit`, por lo que el nuevo commit no puede obtener todavía un preview. Esto bloquea **QA visual**, no el desarrollo ni la revisión del código. No se ha hecho merge ni producción.

### Siguiente ruta de alto valor
1. Cerrar R2D con QA visual cuando haya preview.
2. Completar el mínimo útil de recursos de mano de obra y servicios/costos claramente normalizables, sin inventar tarifas.
3. Iniciar **R3 — bandeja de oportunidades** con modelo propio de ROMAX.
4. Después conectar Gmail con OAuth mínimo y deduplicación.
5. Construir el primer vertical slice R4: oportunidad → análisis → antecedentes → costos → borrador de cotización.


## R3 — Estado de implementación · 18-nov-2026

**Backend PASS:** se migraron `romax_opportunities` y `romax_opportunity_attachments` a Supabase Cloud OneFacility, con RLS, deduplicación por message/thread/attachment ID y validaciones de tenant. Las funciones auxiliares quedaron con `search_path=public`.

**Frontend implementado en rama:** `#opportunities` ya dispone de bandeja, búsqueda, filtro de estado y entrada manual temporal. Cliente, sede y contacto se seleccionan desde los maestros comerciales existentes.

**Sin Gmail todavía:** el cliente aún no confirmó el buzón. La conexión OAuth queda como siguiente paso condicionado a esas credenciales. No se desplegó Vercel.

**QA controlado:** 0 oportunidades y 0 adjuntos persistentes en Cloud; no se usaron registros temporales para las pruebas estructurales. QA de navegador queda pendiente de ejecución manual.

**Siguiente incremento recomendado:** completar QA visual/manual de `#opportunities` y después avanzar con R4-A — análisis técnico de la oportunidad — sin esperar la integración Gmail. Cuando exista el buzón, R3 podrá conectarse sobre este modelo sin rediseñar la base.


## R4-A — Estado de implementación · 18-nov-2026

Se avanzó R4-A sin depender de Gmail: 

- `romax_opportunity_analyses` versiona el análisis técnico.
- `romax_opportunity_analysis_items` estructura servicios, materiales, equipos, mano de obra, movilización y otros.
- El análisis permite cantidades/unidades/especificaciones y puede sugerir un recurso de R2, pero **no contiene precios, costos ni márgenes**.
- Se implementó el editor manual `#opportunity-analysis?opportunity=<uuid>` y el botón **Analizar** desde la bandeja R3.
- La versión anterior queda `superseded` al guardar una nueva versión.
- QA estructural Cloud PASS; QA navegador pendiente.

### Próximo orden
1. QA manual de R3 + R4-A usando una oportunidad de prueba creada desde la interfaz.
2. R4-B: comparación/recuperación de antecedentes de las 25 cotizaciones.
3. R4-C: vincular partidas aprobadas con R2 y ejecutar cálculo económico determinístico.
4. Gmail se integra cuando el cliente entregue el buzón, sin bloquear R4.


## 10. R2-E2.1 — Seguridad y permisos comerciales (27-nov-2026)

R2-E2.1 implementado y aplicado en Supabase Cloud OneFacility. PR #128 abierto en Draft; no merge ni despliegue productivo.

Capacidades por usuario/organización: `market_cost.read`, `market_cost.manage`, `market_cost.validate` y `pricing_rules.manage`; `commercial_price.*` queda reservado para R2-E2.5. RLS restringe costos/proveedores; owner/admin administran concesiones auditables con revocación irreversible. Creador no puede aprobar/rechazar su propio costo. INSERT requiere membresía activa. `service_role` no puede DELETE/TRUNCATE la tabla de auditoría.

Migraciones aplicadas: `20261127154749_romax_r2e2_1_pricing_access_security` y `20261127155628_romax_r2e2_1_service_role_privilege_hardening`.

CI integral PASS: 37 archivos pgTAP / 2,882 aserciones; R2A 22/22 y R2-E2.1 46/46. TypeScript (sin diagnósticos nuevos; baseline heredado de Index.tsx), ESLint, contrato de seguridad y Vite PASS. PR run https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/46029672570; push run https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/46029661761.

Cloud conserva 2 tarifas, 1 proveedor y 1 configuración FX; 0 concesiones iniciales. ROMAX tiene un único owner activo y las dos tarifas existentes (una approved y una rejected) fueron revisadas por su mismo creador antes de la nueva regla; se preservaron sin alterarlas. Agregar un segundo miembro activo y asignar `market_cost.validate` antes de futuras aprobaciones.

Los heads independientes de PR #122/#123 aún usan nombres de migración antiguos; PR #128 alinea los archivos con versiones Cloud 20261127063621 y 20261127063641. Reconciliar la cadena antes de merge/deploy y no ejecutar db push desde ramas intermedias.

No se importaron precios/históricos, no se cambiaron concesiones reales, no se hizo merge y no hubo despliegue productivo.


## Estado vigente y ruta crítica — 27-nov-2026 (sustituye estados pendientes históricos)

**Cierre HOM-01–04:** #122, #123, #126, #127 y #128 integrados en `3f9d22f`, candidato `c51a091` CI PASS, 0 diferencias funcionales. Cuatro migraciones canónicas Cloud ya registradas: 20261127063621, 20261127063641, 20261127154749, 20261127155628. No reejecutar las versiones antiguas. Regresión complementaria 5/5 PASS. Vercel desplegado manualmente.

**Cierre QA-01:** T01–T05/T07–T08 PASS por usuario; T06 inicialmente FAIL (detalle fuera de la tabla). #129 corrige detalle inline, expansión única y diseño adaptable, preserva campos originales de Excel. CI 5/5 PASS, QA visual correctivo confirmado por usuario y merge `a5483dbd5d6fca208add8224953ae5efc5963bb5`. Producción READY, dominio one-facility.vercel.app, deployment dpl_8B7CxzubNgfdijrurUrEDksVErVs. Rollback frontend anterior: dpl_DRZ6dZjspc1C2jaXx1e3SHyTXEnb. Sin escrituras Cloud, usuarios, importaciones ni grants nuevos en este cierre. Auto-deploy productivo sigue deshabilitado. TypeScript tolera solo baseline heredado de Index.tsx. QA móvil no fue reportado por separado.

**Decisión operativa del usuario:** mantener únicamente el propietario actual de ROMAX; no crear perfiles ni incorporar segundo usuario por ahora. El código vigente todavía impide que un creador valide/rechace su propia tarifa, incluso siendo owner. El QA comercial no está cerrado. Antes de validar costos nuevos, diseñar R2-E2.1B (nombre propuesto): mecanismo explícito, limitado a ROMAX/owner activo, para registrar y revisar con una sola cuenta, con confirmación y auditoría; conservar RLS, permisos explícitos, inmutabilidad, historial y separación por defecto para otras organizaciones. No activar automáticamente ni cambiar Cloud sin autorización. La política de aprobación de precios R2-E2.5 debe alinearse con esta decisión, sin aprobación automática por IA. No bloquear el diseño de parámetros mientras se resuelve el flujo operativo.

### Ruta crítica actualizada (orden propuesto para revisión)

| Incremento | Estado | Entregable / gate |
|---|---|---|
| R0 / R1-A/B/C | Base operativa; excepciones pendientes | Reutilizar maestros; resolver solo excepciones necesarias para el piloto (H16 y filas ambiguas sin inventar vínculos) |
| R1-D / R1-E | 25/25 históricos estructurados; extracción no equivale a certificación comercial | Revisar advertencias y QA de consulta; usar como referencia, nunca tarifa vigente |
| R2A–D / R2-E0 | Base de costos y compatibilidad implementada | Mantener módulos existentes y probar regresiones |
| R2-E1.1–E1.5 | Catálogo preliminar cargado y UI productiva, QA-01 cerrado | 772 recursos documentados, 779 identidades, 43 pendientes; resolver equivalencias/unidades necesarias antes de usar sus partidas; no fusionar por similitud ni asumir subfamilia |
| R2-E2.1B | Pendiente de diseño y QA | Operación con owner único; probar permisos, alta, revisión, auditoría, denegaciones cross-tenant; sin nuevos perfiles |
| R2-E2.2 A–F | Pendiente | Parámetros IGV/FII versionados, bandas, excepciones, función determinista, UI reglas y CI; IGV inicial 18%, vigencia 180 días, alerta 30 días, bandas 30/30/20/15%; validar límites y redondeos |
| R2-E2.3 | Pendiente | Conciliar proveedores y 273 antecedentes históricos de mercado con procedencia, append-only e idempotencia; conservar vigencia histórica 120 días; no inventar datos |
| R2-E2.4 | Pendiente | Confirmar PEN de matriz, cargar 245 costos candidatos pendientes; 534 sin costo quedan sin tarifa; revisar coincidencias, fechas, impuesto y vigencia; aprobar explícitamente solo costos aptos |
| R2-E2.5 | Pendiente | Versionar precio de venta separado del costo; propuesta, revisión humana y trazabilidad de reglas/override; política owner único a definir |
| R2-E2.6 | Pendiente | UI comercial y alertas (10% exige base comparativa aprobada), excepciones FII sin sustento quedan pendientes |
| R2-E2.7 | Pendiente | Elegibilidad para cotizar: recurso homologado, unidad compatible, costo vigente validado y precio/regla aprobados; bloqueo explícito si falta dato |
| R3 / R4-A / R4-A.1 | Entrada manual, análisis y versión idempotente desplegados | Reutilizar flujo actual; análisis no contiene precios; IA efectiva aún pendiente |
| R4-B | Pendiente; puede avanzar en paralelo con R2-E2 | Buscar y vincular antecedentes de 25 cotizaciones, mostrando fuente, alcance y diferencias; no copiar importes |
| R4-C | Pendiente; depende R2-E2.7 | Motor de presupuesto por partida: cantidades/unidades, costo, precio, mano de obra, equipos, servicios, movilización, subtotal, IGV, total y snapshots de fuente/regla |
| R4-D | Pendiente | Borrador editable con listado de servicios, materiales/consumibles, aclaraciones técnicas, resumen económico y consideraciones; versionado |
| R4-E | Pendiente | IA asistida para extraer alcance, sugerir partidas y antecedentes, señalar faltantes; motor determinista calcula; revisión humana |
| R6 | Pendiente | Plantilla oficial, revisión, PDF y emisión manual con trazabilidad; no envío automático sin política |
| R3 Gmail | Paralelo, pendiente de buzón/OAuth | Captura y deduplicación de correo/adjuntos, sin bloquear el primer piloto manual |
| R5 | Backlog complementario | Visitas, fotos, medidas, especialidades, horas y observaciones |

**Primer hito demostrable:** oportunidad manual → análisis versionado → antecedentes → recursos/costos válidos → cálculo determinista → borrador editable → revisión/PDF. Luego Gmail automatiza entrada y R4-E asiste preparación. Si se incorpora IA antes de emisión, probar su salida con el mismo flujo manual. No convertir el catálogo en un ERP ni exigir completar los 779 materiales para probar un caso acotado. Los recursos sin costo no se cotizan a cero. Mano de obra/equipos/servicios deben tener fuentes válidas cuando correspondan. El usuario realiza QA navegador y decisiones de negocio; asistente implementa PR, CI, verificación Cloud read-only y despliegues/migraciones con autorización separada.

**Siguiente acción:** preparar contrato técnico R2-E2.1B y R2-E2.2, revisar alcance y aprobar antes de modificar políticas/migraciones. El primer caso económico piloto puede usar un subconjunto validado. No iniciar importación de precios/históricos ni conceder permisos reales en este cierre.


## R3-GMAIL — evaluación inicial 27-nov-2026

Se adelanta entrada de solicitudes en paralelo a R2-E2, por decisión del usuario. Conector Gmail de ChatGPT confirmado; OAuth propio de One Facility pendiente. Evaluación de muestra real completada sin escrituras ni cambios al buzón; oportunidades Gmail=0, adjuntos=0. Próximo incremento R3-GMAIL.1, conexión de aplicación y contrato seguro de captura, seguido de preview manual e importación idempotente con revisión. Ver [evaluación y plan](ROMAX_R3_GMAIL_INTAKE_EVALUATION.md). No publicar contenido del correo en el repositorio público.


## R3-GMAIL.1 — candidato OAuth (27-nov-2026)

PR #130 Draft: panel propietario, callback OAuth autenticado, alcance gmail.readonly, state/PKCE, verificación de buzón, cifrado AES-GCM y desconexión; migración canónica generada por CLI en CI desechable y pgTAP de ACL. Sin Cloud, merge, envío ni importación. CI de servidor simulado 6/6 y primer ensayo de base 2,894 aserciones PASS; revalidar head definitivo y ejecutar QA OAuth real antes de R3-GMAIL.2. Configuración Google Cloud/Edge Secrets pendiente. Ver [contrato y pasos](ROMAX_R3_GMAIL_1_OAUTH.md). El alcance confirmado es siete días, sync manual, revisión owner, clasificación, adjuntos PDF/XLSX/DOCX en incrementos posteriores.


Activación autorizada 27-nov-2026: MCP aplicó el SQL idéntico y asignó versión Cloud 20261127205522. Se renombra archivo Git sin cambiar blob; no reejecutar versión original 20261127202747. Tabla vacía, RLS habilitado, anon/authenticated sin lectura, service_role con lectura. Edge Function activa v1; QA OAuth real pendiente.


## R3-GMAIL.2 — 27-nov-2026
R3-GMAIL.1 cerrado, QA real 8/8, conexión confirmada en Cloud y CI final 6/6. R3-GMAIL.2 candidato: lectura manual paginada de 168 horas, clasificación preliminar y vista temporal, sin escrituras ni adjuntos descargados. Ver [contrato](ROMAX_R3_GMAIL_2_PREVIEW.md). R3-GMAIL.3 confirmación/importación y .4 procesamiento pendientes.


## Cierre R3-GMAIL.2 — 27-nov-2026

PR #131 integrado y desplegado. CI 6/6 PASS. Edge Function v2 ACTIVE con vista previa de Gmail, Vercel producción READY en commit 9117364. R3-GMAIL.2 habilita lectura manual paginada de siete días y clasificación preliminar; no persiste oportunidades ni descarga adjuntos. El buzón `ventas@romaxfm.com` continúa conectado y el contador de oportunidades Gmail sigue en 0. QA real de sincronización en navegador queda a cargo del propietario; después se decide el cierre funcional y R3-GMAIL.3 (confirmación/importación idempotente).


Nota de observabilidad: los 4 POST 200 y 3 OPTIONS 204 observados en la ventana consultada correspondían a llamadas anteriores a la versión 2. Desde la actualización de la Edge Function (21:44:14 UTC) no se registran invocaciones nuevas; por tanto, la vista previa queda desplegada pero aún requiere la primera sincronización manual del propietario para confirmar el recorrido real.


## Auditoría inicial R3-GMAIL.2 — 27-nov-2026
Primera página revisada en solo lectura: 12 conversaciones; 6 hilos comerciales (5 solicitudes + 1 actualización), 4 cotizadas/operativas, 2 falsos positivos. Se identificaron errores de clasificación en reenvíos, alias internos y ampliaciones de plazo. No se importaron correos. NO GO importación hasta corregir clasificador, validar fechas America/Lima y revisar páginas siguientes. Ver [auditoría anonimizada](ROMAX_R3_GMAIL_2_FIRST_PAGE_AUDIT.md).


## R3-GMAIL.2.1 — correctivo en desarrollo
PR independiente para reenvíos, alias @romaxfm.com y ampliaciones de plazo con historial y validación de día de semana en America/Lima. Casos Cassinelli Piura, Makro ventas3, UTP Lima Sur, UTP Chiclayo y UTP Piura. Sin escrituras ni despliegue; pendiente CI.


R3-GMAIL.2.1 incluye exclusión de soporte Suplayer, reconocimiento de solicitudes que dicen propuesta sin “cotización” literal y separación de coordinación SST/ingreso como operación. Pendiente CI final.


R3-GMAIL.2.1: parser de plazos ampliado a fechas ISO yyyy-mm-dd, además de dd/mm y dd.mm; mantiene validación de día de semana y zona America/Lima. El PR sigue Draft hasta que la última ejecución de CI confirme el head definitivo.


## R3-GMAIL.2.1 — QA aislado autorizado
Se crea `romax-gmail-connection-qa` con allowlist `status/preview` y CORS restringido al alias Vercel Preview de `feature/romax-r3-gmail-2-1`. Vercel Preview de esa rama invoca QA mediante `VITE_ROMAX_GMAIL_FUNCTION_NAME`; producción mantiene la función productiva por defecto. Sin merge, cambios en producción, SQL, importación o modificaciones Gmail. Validar login de propietario y correos auditados antes de autorizar R3-GMAIL.3.


## QA aislado R3-GMAIL.2.1 — 27-nov-2026
Autorizado y desplegado `romax-gmail-connection-qa` v1 ACTIVE (`verify_jwt=true`), con allowlist `status/preview`. Vercel Preview de `feature/romax-r3-gmail-2-1` tiene override branch-scoped `VITE_ROMAX_GMAIL_FUNCTION_NAME`; bundle verificado. CI commit 8cbfca1 10/10 PASS, 22 pruebas Deno. Producción Edge v2 y Vercel `9117364a` sin cambios. Falta login manual del propietario en preview y primera sincronización real. No merge, no importación ni SQL.


## R3-GMAIL.2.2 — interpretación de conversaciones
Implementación en PR #132: lectura temporal de texto MIME en ventana de siete días, comparación de plazos, reconocimiento de propuestas, exclusión de promociones y política explícita de revisión/vinculación. Véase `docs/ROMAX_R3_GMAIL_2_2_CONVERSATION_INTERPRETATION.md`. CI pendiente; no merge, importación ni cambios Cloud.


## R3-GMAIL.2.2.1 — correctivo QA
Corregir detección de cotizaciones de alias ROMAX usando payload MIME completo, extracción de fechas de tablas HTML Outlook y exclusión de promociones con señales de lista + contenido. Incluye regresiones Makro, Cassinelli Trujillo y Samsung. Requiere CI completo y despliegue únicamente de `romax-gmail-connection-qa`; no merge ni cambios en producción.

## Cierre R3-GMAIL.2.2.1 — 28-nov-2026

QA real v3 confirmado por el propietario: Q01–Q08 PASS. CI del código probado 3c66e85: 10/10 checks y 34/34 pruebas Deno PASS. Logs QA v3 HTTP 200/204 corroboran ejecución, no contenido. Al cierre: 0 oportunidades Gmail, 0 adjuntos importados. PR #132 abierto Draft, sin merge. Edge productiva v2 intacta.

## R3-GMAIL.3 — autorización

D01–D12 aprobadas. PR independiente: 3.1 transacción, auditoría, ACL e idempotencia; 3.2 confirmación owner; 3.3 pruebas aisladas. Cloud, QA v4, merge y producción no autorizados. No importar correos reales sin confirmación expresa en la interfaz.

## Replanning funcional — 28-nov-2026

La primera oportunidad Gmail real fue confirmada intencional por el propietario; QA visual 8/8 y CI #133 40c8d08 PASS. Cloud homologado 20261128145232; falta resincronización real sin duplicado y merge autorizado. Se revisó matriz de 27 requisitos y reunión 27/11; el siguiente incremento propuesto es R3-SOL.1 (bandeja/ficha estructuradas de solicitudes), seguido por enriquecimiento revisable, adjuntos y asignación exclusiva. Reutilizar R1, R2 y R4-A; R2-E2 continúa en paralelo antes del motor económico R4-C. La ruta crítica anterior es histórica donde contradiga el nuevo plan. Ver [replanning funcional](ROMAX_FUNCTIONAL_REPLANNING_20261128.md). Solo documentación; ninguna implementación ni publicación de fuentes privadas.

## R3-SOL.1 — diseño funcional 28-nov-2026

P01–P12 aprobadas por propietario. Se documenta [contrato R3-SOL.1](ROMAX_R3_SOL_1_FUNCTIONAL_DESIGN.md): tabla y ficha de solo lectura, tabs registrados/Gmail, filtros y métricas sustentados en datos existentes, ruta privada, manual y análisis sin regresión; no agregar campos ficticios, migraciones ni permisos. SOL1-D01–D12 y QA S01–S24 pendientes de aprobación para implementar. PR #134 documental abierto; #132/#133 sin merge, resincronización real pendiente. No código, importaciones ni despliegues solicitados.

## R3-SOL.1 — aprobación de implementación

SOL1-D01–D12 aprobadas; rama feature/romax-r3-sol-1, PR funcional dependiente de #134. Alcance frontend, sin migraciones ni ampliación de permisos. Candidato sujeto a CI y QA visual; resincronización real #133 y merges continúan pendientes. No autorizar publicación productiva por esta aprobación.

## R3-SOL.1D — aceptación funcional 28/11/2026

QA visual aprobado por propietario (confirmación global, sin desglose individual). CI run 46160145444, 3/3 PASS, head abd9f89. Cloud 4 oportunidades (3 Gmail nuevas sin vincular, 1 manual en análisis vinculada), 3 auditorías concordantes, 3 mensajes y 3 hilos únicos; primera oportunidad conservada. QA v7 5 POST 200 y 5 OPTIONS 204; logs no prueban cada interacción. Cierre funcional; no merge ni producción. Siguiente: R3-SOL.2 diseño, sin escrituras Cloud.

Ver [contrato de enriquecimiento](ROMAX_R3_SOL_2_ENRICHMENT_DESIGN.md), decisiones E01–E12 propuestas.

## R3-SOL.2 — implementación candidata

E01–E12 aprobadas; rama feature/romax-r3-sol-2, SQL solo GitHub, formulario de revisión, lectura Gmail dirigida y filtros de plazo. CI y cierre de brechas de trazabilidad pendientes; no Cloud, merge o producción.

## R3-SOL.2 — Cierre funcional (28/11/2026)

QA real confirmado por propietario y cotejado en Cloud: cinco oportunidades (cuatro Gmail con hilos/mensajes únicos y cuatro auditorías concordantes), una ficha enriquecida con versiones 1–3, cinco recibos (tres saved y dos unchanged), proyección vigente igual a v3; cuatro solicitudes anteriores con huella intacta. Resumen y plazo de fecha sin hora verificados: cinco entradas de evidencia privada, componentes del mismo evento, parser/fecha/mensaje conservados. Indicadores esperados al cierre: 1 por vencer, 4 sin plazo confirmado, 0 vencidas. QA persistencia 11/11 PASS; CI y security gate aprobados. Migración Cloud canónica 20261128164558; Edge QA v8, Vercel Preview. No merge ni producción; el cierre funcional no equivale a liberación general. Siguiente R3-GMAIL.4 / R3-SOL.4, diseño de adjuntos privados bajo demanda.

Ver [R3-GMAIL.4 — contrato de adjuntos](ROMAX_R3_GMAIL_4_ATTACHMENTS_DESIGN.md), decisiones A01–A12 propuestas.

## R3-GMAIL.4A — fundamento documental

A01–A12 aprobadas; implementación candidata GitHub-only. Tabla existente ampliada, ACL de metadatos y registro service-only, auditoría y estados separados, prueba concurrente y CI. Cloud y descarga permanecen sin cambios; R3-GMAIL.4B espera cierre 4A.

## Checkpoint vigente — 28/11/2026 (prevalece sobre estados históricos)

R3-GMAIL.4A CI integral PASS en commit de código d5a7612e675972c6cec6214a40175bfabcc0dc28, run 46176658892: 41 archivos / 3018 pgTAP (50 nuevos), 38 Deno, 21 frontend, TypeScript sin nuevos diagnósticos, ESLint y Vite; concurrencia importación, revisión y documentos PASS. Asesores locales ejecutados, 0 ERROR, 11 WARN y 9 INFO; la nueva observación sobre tabla de auditoría privada sin políticas es intencional (denegación directa). Revisar alcance y ACL del candidato antes de cierre formal 4A. No hay migración Cloud 4A ni descarga real. PR #139 Draft.

La ruta crítica aprobada es el replanning del 28/11 y el contrato de adjuntos A01–A12, no la secuencia histórica del 27/11. Estado y siguientes gates en [memoria de continuidad](ROMAX_CONTINUITY_20261128.md).


### Checkpoint R3-GMAIL.4A — seguridad (28/11/2026)

Revisión independiente del candidato GitHub/local `PASS_REPOSITORY_LOCAL`, sin bloqueantes SQL/ACL demostrados; CI run 46176658892 aprobado. PR #139 se conserva Draft y sin merge; 4A no aplicada en Cloud. Condiciones obligatorias para 4B: validar identidad del actor y pertenencia Gmail de cada mensaje/parte al hilo autorizado, sin descarga de binarios; 4C conserva validación binaria/escaneo/almacenamiento. Véase [informe de seguridad 4A](ROMAX_R3_GMAIL_4A_SECURITY_FINAL_REVIEW_20261128.md). Próximo hito con autorización independiente: R3-GMAIL.4B. No autorizar Cloud ni producción por este checkpoint.


## R3-GMAIL.4B — detección dirigida

Autorizado desarrollo GitHub-only sobre 4A con security review PASS_REPOSITORY_LOCAL. Edge descubre metadatos del hilo de oportunidad y registra vía RPC 4A, sin bajar binarios ni exponer IDs; CI pendiente. No Cloud, Gmail real, merge o producción. 4C requiere scanner y contrato de almacenamiento.
