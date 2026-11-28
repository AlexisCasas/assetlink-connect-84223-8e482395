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
Migración candidata GitHub: supabase/migrations/20261128190000_romax_r3_gmail_4a_metadata.sql (identificador provisional, sin aplicación Cloud; CLI no disponible en runtime MCP de edición). Tabla existente, FK compuesta tenant/oportunidad, columnas de disponibilidad/escaneo/revisión, vista public.romax_attachment_metadata security_invoker, grants por columna, inserción manual acotada, RPC public.romax_register_gmail_attachment_metadata(uuid,uuid,uuid,timestamptz,text,jsonb) service-only; esquema privado romax_docs_private, auditoría append-only. Identidad única existente tenant/mensaje/adjunto (más estricta que per-opportunity); MIME part namespace part:. Lote atómico <=50, validación preliminar MIME/extensión/tamaño, sin prometer validación binaria. No bucket, descarga, scanner, leases de lifecycle ni extracción. 4B debe comprobar pertenencia real de mensaje/parte al hilo en Gmail; RPC solo comprueba hilo de oportunidad y actor/conexión, no llama Gmail.
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
