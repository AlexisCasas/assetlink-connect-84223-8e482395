# ROMAX / One Facility — Memoria de continuidad
Fecha: 28/11/2026. Checkpoint de trabajo para reanudar en otro chat del mismo proyecto. No contiene documentos de cliente, cuerpos de correo, credenciales, identificadores de personas ni detalles explotables de deuda de seguridad.

## 1. Fuentes vigentes
- [Plan maestro](ROMAX_PILOT_MASTER_PLAN.md), último checkpoint prevalece sobre estados históricos.
- [Replanning funcional aprobado](ROMAX_FUNCTIONAL_REPLANNING_20261128.md), P01–P12.
- [Contrato R3-SOL.2](ROMAX_R3_SOL_2_ENRICHMENT_DESIGN.md), E01–E12 aprobadas.
- [Contrato de adjuntos](ROMAX_R3_GMAIL_4_ATTACHMENTS_DESIGN.md), A01–A12 aprobadas, D01–D30 escenarios de QA.
Repositorio AlexisCasas/assetlink-connect-84223-8e482395. Rama activa feature/romax-r3-gmail-4a. Base productization/mvp. Verificar estados vivos mediante MCP, no asumir que un estado histórico sigue vigente.

## 2. Avance funcional
| Área | Estado |
|---|---|
| R0 / R1 | Directorio híbrido y 25 cotizaciones históricas estructuradas; excepciones y advertencias por resolver según necesidad del piloto |
| R2 catálogo | Fundación, normalización y UI productiva; catálogo preliminar, 772 recursos documentados / 779 identidades / 43 pendientes según corte previo |
| R2-E2 | Seguridad de precios base implementada; owner único, política explícita de revisión, parámetros, costos vigentes y elegibilidad por completar. Ver plan maestro, no presumir aprobación de costos |
| R3-GMAIL.1–2 | OAuth gmail.readonly y preview manual; correctivos de interpretación y QA 8/8 completados |
| R3-GMAIL.3 | Importación confirmada por propietario, deduplicación y auditoría; QA funcional completado |
| R3-SOL.1 | Centralizador y ficha, QA visual aprobado |
| R3-SOL.2 / 2.1 / 2.2 | Enriquecimiento versionado, procedencia, plazos, hardening y QA real cerrados (11/11 persistencia); security gate scoped PASS |
| R3-GMAIL.4A | Fundación documental en GitHub; CI 3/3 PASS; revisión final de seguridad específica pendiente |
| R3-GMAIL.4B–E | Pendientes, contrato A01–A12 aprobado |
| R3-SOL.3 | Asignación exclusiva y reasignación auditada pendiente |
| R4-A/A.1 | Análisis técnico versionado e idempotente ya desplegado, sin precios |
| R4-B–E / R6 / R7 | Pendientes según replanning |
| R5 | Complementario, visitas cuando aplique |

## 3. Cadena de PRs al checkpoint
Todos los siguientes PR se verificaron abiertos en Draft, sin merge. Deben integrarse en orden de dependencia únicamente con autorización separada; no db push desde ramas intermedias.
| PR | Alcance | Head de código o diseño verificado |
|---|---|---|
| #132 | Correctivos Gmail 2.1/2.2 | ccaad1d7d201eccfe0ea049b1efbd54e3f1d6650 |
| #133 | Importación Gmail 3 | 40c8d08b4b19ac189b2d4c52d1affd4982d02853 |
| #134 | Replanning funcional | d5afa32a146244e2810e6f182ad67863ff6757f9 |
| #135 | Centralizador SOL.1 | abd9f897c9099bc40b32357b1160f047edfc1497 |
| #136 | Diseño SOL.2 | 9e1564a267308ee18a206372e7d966036b6e9abf |
| #137 | Enriquecimiento y seguridad | 5b02df6e5272422000d3165a7eccb143029e5b92 |
| #138 | Cierre SOL.2 y diseño adjuntos | 8ea6dc8c254a283021e39f004b3e7546e7836b7c |
| #139 | Fundación 4A | d5a7612e675972c6cec6214a40175bfabcc0dc28 (head probado; checkpoint documental posterior) |

## 4. Ambientes (último cotejo previo, revalidar antes de cambios)
- Supabase Cloud OneFacility, proyecto hplchnsseylngjopgbtl. QA y producción comparten DB. Migraciones ya aplicadas y homologadas: 20261127205522 (OAuth), 20261128145232 (Gmail import), 20261128164558 (SOL.2 review). No volver a ejecutar identificadores provisionales.
- Último cierre real SOL.2: cinco oportunidades, cuatro Gmail con cuatro auditorías concordantes, una ficha v1/v2/v3, cinco recibos (tres saved, dos unchanged), cinco evidencias privadas de Gmail en v3, un plazo confirmado sin hora. Las cuatro oportunidades previas conservaron huella original. Adjuntos ROMAX registrados: cero. Esto es línea base del cierre, no una consulta nueva del día.
- Edge QA romax-gmail-connection-qa v8, verify_jwt=true, código contrastado con PR #137. Productiva romax-gmail-connection v5, no reemplazar. Preview de SOL.2: https://one-facility-git-feature-romax-r3-sol-2-alexiscasasrs-projects.vercel.app, variable branch-scoped VITE_ROMAX_GMAIL_FUNCTION_NAME=romax-gmail-connection-qa. Secrets QA se gestionan desde dashboard (MCP sin herramienta de secrets); no pedir valores sensibles en chat. Vercel producción último cotejo 9117364a, dpl_5yPrNT5eZ6iG42XwJh2qsyfMKRDr.
- Respaldo recuperable fue omitido explícitamente solo para la migración SOL.2. No extender esa excepción a futuras migraciones. Verificar respaldo/preflight y pedir autorización Cloud cuando corresponda.
- OF-SEC.01: deuda preexistente de seguridad transversal requiere auditoría privada antes de liberación general. No publicar hallazgos detallados ni confundir gate ROMAX con aprobación de toda la plataforma.

## 5. R3-GMAIL.4A: último estado técnico
Migración candidata GitHub: supabase/migrations/20261128201434_romax_r3_gmail_4a_metadata.sql (identificador provisional, sin aplicación Cloud; CLI no disponible en runtime MCP de edición). Tabla existente, FK compuesta tenant/oportunidad, columnas de disponibilidad/escaneo/revisión, vista public.romax_attachment_metadata security_invoker, grants por columna, inserción manual acotada, RPC public.romax_register_gmail_attachment_metadata(uuid,uuid,uuid,timestamptz,text,jsonb) service-only; esquema privado romax_docs_private, auditoría append-only. Identidad única existente tenant/mensaje/adjunto (más estricta que per-opportunity); MIME part namespace part:. Lote atómico <=50, validación preliminar MIME/extensión/tamaño, sin prometer validación binaria. No bucket, descarga, scanner, leases de lifecycle ni extracción. 4B debe comprobar pertenencia real de mensaje/parte al hilo en Gmail; RPC solo comprueba hilo de oportunidad y actor/conexión, no llama Gmail.
CI run 46176658892, código d5a7612: 3/3 PASS; 41 archivos pgTAP / 3018 aserciones, 50 de 4A; Deno 38, frontend 21, tres concurrencias PASS. Asesores local 9 INFO / 11 WARN / 0 ERROR; tabla privada nueva sin política es intencional. Cierre formal seguridad 4A pendiente de revisión independiente, no declarar por CI solo. TypeScript conserva baseline heredado, sin nuevos diagnósticos.

## 6. Ruta crítica desde aquí
1. Revisar seguridad final de 4A sobre SQL y pruebas, permisos efectivos, idempotencia, integridad tenant, audit actor, compatibilidad manual, invariantes de estados y asesores; corregir hallazgos en mismo PR con CI antes de cerrar.
2. 4B: detección dirigida por oportunidad autorizada, Gmail readonly, owner activo, metadatos sin binario; thread obtenido en servidor, cada message/part verificado, separar cliente/ROMAX/inline/enlaces, límites y respuesta parcial explícita. Deno, pruebas de autorización, idempotencia, no raw IDs al navegador, flags QA/productivo separados OFF. PR apilado, autorización de implementación según alcance. No leer adjuntos reales sin autorización.
3. 4C: decidir scanner y cuarentena; bucket privado, descarga explícita, 10 MiB/archivo, 25 MiB/lote, máximo 5; validación real, no macros/contenido activo, hash, lease/fencing, recuperación de storage/DB, URL temporal o streaming. Bloquear liberación si no hay escaneo. Autorización separada para Cloud/QA.
4. 4D: pestaña Documentos, contador real, estados, reintentos, descarga autorizada y QA. 4E: extracción técnica trazable y revisable por página/hoja/celda, parser aislado; sin OCR/CAD/IA externa sin decisión adicional.
5. R3-SOL.3: asignación exclusiva atómica, roles y equipo; sin crear cuentas reales.
6. R4-A/R4-B: análisis técnico y antecedentes; R2-E2.1B–7 en paralelo (owner único, costo vigente validado y venta/reglas aprobadas, faltantes no son cero).
7. R4-C1 partidas/subpartidas, nivel valorizado único, cálculo determinista; C2 mano de obra/jornadas/logística y generales sin duplicación; C3/R4-D margen sobre venta/subcontrato y borrador; R4-E IA asistida con revisión humana.
8. R6.1–2 correlativo, versión, aprobación, PDF/Excel/anexos; R6.3 emisión manual y OAuth de envío independiente; R7 KPI comercial. R5 complementario.

## 7. Reglas operativas
Trabajar por incrementos, usar MCP GitHub y Supabase/Vercel cuando autorizado, confirmar SHA/CI real y documentar decisiones y limitaciones. No inventar resultados ni esperar en background. Autorización vigente del usuario: iniciar 4A en GitHub, migración solo repositorio, pruebas y CI. A01–A12 aprobadas. No autoriza Cloud, descarga de archivos reales, merge ni producción. Para 4B+ mantener estos límites y obtener autorización de ejecución si se necesita ampliar alcance. No publicar datos privados; fixtures sintéticas. El usuario realiza QA visual autenticado; contrastar persistencia en solo lectura. Integración de toda la cadena de PR y despliegue general requieren autorización expresa. Mantener módulos operativos existentes.

## 8. Evidencia
[PR #139](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/pull/139), [CI 46176658892](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/46176658892), [PR #137](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/pull/137), [PR #138](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/pull/138).

## Revisión final de seguridad R3-GMAIL.4A — 28/11/2026

`PASS_REPOSITORY_LOCAL` en candidato GitHub/CI; PR #139 permanece Draft y no se ha ejecutado migración Cloud. Revisión independiente de ACL, RLS, tenant, audit, idempotencia y concurrencia, contraste con asesor local y consultas Cloud de sólo lectura. Sin bloqueantes demostrados en 4A; pertenencia real al hilo y verificación de actor obligatorias para 4B, binarios/escáner para 4C. Tres diagnósticos TypeScript heredados reconocidos. Evidencia: [revisión de seguridad 4A](ROMAX_R3_GMAIL_4A_SECURITY_FINAL_REVIEW_20261128.md). Próximo gate: autorizar implementación 4B en GitHub, sin Cloud/descargas/merge/producción.


## R3-GMAIL.4C.3 / 4D — excepción de piloto autorizada (28/11/2026)

El usuario aprueba ClamAV pero lo difiere al backlog para operar el piloto asumiendo el riesgo. Modifica A07/A11 exclusivamente para permitir acceso explícito a originales no escaneados: estado separado released_unscanned, scan_status=pending, nunca available/clean; confirmación por cada descarga y auditoría. Owner ROMAX activo solamente (otros roles conservan lectura de metadata); acceso vía Edge autenticado, revalidación tenant/oportunidad, hash/tamaño del objeto, sin URL firmada, sin render inline; respuesta octet-stream attachment. Flags QA/prod separados OFF. Original permanece en ruta privada de cuarentena; sin promoción canónica ni overwrite. PDF/JPEG/PNG/TXT inicialmente elegibles; DOCX/XLSX se conservan pero no se liberan hasta validación estructural de contenedores (no se renuncia a esa garantía); MIME inline sigue metadata-only. Interfaz Documentos: detectar, selección acotada, guardar, estados reales, origen, fecha, aviso y confirmación de riesgo, descargar; contador registrado y fallback read-only si no hay migración. No análisis/extracción automática ni Cloud real. Backlog 4C.2: scanner autoalojado ClamAV, validación profunda, recuperación/reconciliación y liberación normal, revocar excepción cuando disponible. 4C.1 CI 46182661154 PASS (3049 pgTAP, 56 Deno, cuatro carreras y Storage HTTP real sintético). CI candidato pendiente; revisión seguridad y QA controlado antes de activar.


## R3-GMAIL.4F — Cloud DDL activation (28/11/2026)

Authorized explicitly by owner including recoverable backup verification waiver for this increment only. CI 46184300718 PASS on 85413c8 (3065 pgTAP, 58 Deno, four races, real local Storage HTTP). Three exact SQL blobs applied in order and canonical identifiers read from Cloud ledger: 20261128201434_romax_r3_gmail_4a_metadata, 20261128201443_romax_r3_gmail_4c1_quarantine, 20261128201453_romax_r3_gmail_4c3_unscanned_access. Rename only in current stacked branch; preserve exact blob bytes; reconcile ancestor filenames before merges. Postflight: 5 opportunities and 3 review rows identical full-row fingerprints, 4 import audits; 0 documents/events/attempts/objects. Private bucket 10 MiB, restrictive anon/auth Storage policy, 3 tables RLS, public RPCs invoker/service-only, safe view invoker, five sensitive columns denied to authenticated, immutable triggers enabled. No real Gmail reads/downloads. QA-only Edge deploy follows verification; production and merges unchanged. CI re-run for canonical rename required before general integration. Scanner backlog and explicit unscanned risk exception remain.


## R3-GMAIL.4F.2 — Office pilot exception

Owner explicitly authorized XLSX/DOCX unscanned download and deferred deep container validation and ClamAV. 4F real QA: two stored objects with matching attempt hash/size, PDF released and one access audited, XLSX quarantined, six attempts (four historical failures), zero active leases. Prior hotfix CI 46188010459 3/3 PASS. Additive migration extends only private unscanned access MIME allowlist; public service-only RPC, owner/tenant gates, explicit acknowledgement, object hash/size and audit unchanged. Edge and UI accept exact Office MIME types and force .xlsx/.docx extension; macro-enabled formats and generic ZIP remain denied. No inline rendering, automatic execution, extraction or rescan; use protected view and do not enable active content. Scan stays pending; no claim of structural or antivirus validation. QA-only activation authorized, no merge/production. New CI and authenticated Office download pending.


## R3-GMAIL.4F.2 — Cloud activation

CI 46188826642 3/3 PASS: 3077 pgTAP/42 files, 62 Deno, frontend, four concurrency gates and real local Storage HTTP. Exact SQL blob ce97a9f6d0029989b6e05f2b729125b8e18c7e1e applied and canonical ledger version 20261128205944. Postflight full-row fingerprints of opportunities, revisions and documents unchanged; 2 objects, 6 attempts, 16 audit events unchanged, private bucket, both release functions service-only, Office MIME allowlist enabled. Prior definition retained for function-only reversal. No new data or actual file reads. QA Edge update and authenticated Excel retry follow; production and merge unchanged. Deep validation and scanner remain backlog; do not treat MIME as proof of content safety.

## Checkpoint vigente — R3-GMAIL.4F/4F.2 y siguiente 4E (28/11/2026)

Cierre funcional piloto PASS: QA propietario 5/5, CI canonical 46189296140 3/3 PASS (head 556f643a), dos documentos/objetos privados concordantes con intentos exitosos (SHA-256 y tamaño registrados); ambos released_unscanned, scan pending. Tres accesos auditados por owner activo, dos transiciones de liberación, 19 eventos totales, seis intentos (cuatro fallidos históricos, dos conservados), cero duplicados y reservas activas. Cinco oportunidades, tres revisiones de enriquecimiento y cuatro auditorías Gmail intactas. Edge QA v17, Preview READY; producción Edge v11 y Vercel 9117364a sin promoción. Cuatro migraciones canónicas 20261128201434, 20261128201443, 20261128201453, 20261128205944. PR #142 sin merge; DOCX solo QA sintético. Escaneo ClamAV, validación profunda general y reconciliación de huérfanos permanecen backlog. La excepción de descarga manual no habilita procesamiento automático inseguro. Siguiente [diseño R3-GMAIL.4E](ROMAX_R3_GMAIL_4E_EXTRACTION_DESIGN.md), decisiones X01–X12 propuestas; sin código, migración, lectura de binarios, proveedor externo ni despliegue. El nuevo checkpoint prevalece sobre estados previos.


## R3-GMAIL.4E.1 — approved contract and implementation candidate

Owner approved X01–X12, no pending decisions; GitHub-only migration/tests/CI. Private extraction schema (jobs, runs, evidence_blocks, candidates, review_events, receipts), service-only write RPCs, auth.uid-scoped commercial read RPCs, tenant and owner checks, unique active document, short serialized state transactions, per-tenant/global pending/running limits (10/100 queued or running; 1/2 active leases), 120s lease and 3 attempts. Original source bound to successful private attempt, metadata/hash checked at DB boundary, actual bytes must be hashed by future broker. Results bounded/validated and immutable, explicit partial review, optimistic version and request receipts; no integration into analysis yet. Only current PDF/XLSX quarantine-backed pilot sources; clean canonical storage, Word/TXT, worker authentication/flags, sandbox, full cell/range validation and parser execution in later increments. No actual processing, Cloud, merge or prod. Candidate migration timestamp provisional (CLI not available in MCP editing session); CI pinned local Supabase. Tests and independent security review required before closure.
