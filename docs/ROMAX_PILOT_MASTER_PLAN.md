# One Facility — Plan maestro y continuidad del piloto ROMAX

**Actualizado:** 14-nov-2026 · **Responsable funcional:** equipo ROMAX / One Facility · **Objetivo:** agilizar y ordenar la cotización de servicios de ROMAX sin obligar a sus clientes a usar el portal.

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
| R1-D | Histórico de cotizaciones ROMAX 2026 | Pendiente | Lote piloto ~25 cotizaciones, archivos origen, fecha, moneda, estado distinguido |
| R1-E | Pantalla de consulta comercial/histórico | Pendiente | ROMAX busca por cliente/sede/fecha/servicio sin clientes logueados |
| R2 | Catálogo independiente de costos de materiales y mano de obra | Pendiente | Fecha de vigencia, unidad, moneda, proveedor y procedencia en cada costo |
| R3 | Captura Gmail cotizaciones | Pendiente | OAuth, deduplicación, filtro de correos relevantes, oportunidad a nombre de ROMAX |
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
