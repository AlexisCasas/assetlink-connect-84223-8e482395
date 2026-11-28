# ROMAX R3-GMAIL.4A — Revisión final independiente de seguridad (28/11/2026)

**Decisión:** `R3_GMAIL_4A_SECURITY_REVIEW=PASS_REPOSITORY_LOCAL`, sin bloqueantes demostrados dentro del alcance 4A. **No** equivale a aprobación Cloud, despliegue, Gmail real ni habilitación de descarga. PR #139 sigue Draft, sin merge. R3-GMAIL.4B queda por implementar y sujeto a autorización por incremento.

## Línea base verificada

- Repositorio: `AlexisCasas/assetlink-connect-84223-8e482395`; rama `feature/romax-r3-gmail-4a`; PR https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/pull/139
- Commit código `d5a7612e675972c6cec6214a40175bfabcc0dc28`; commit documental previo `4c92d7ec6709d8e8d353871376fccb4cee3e1468`. Comparación GitHub: este último sólo cambia documentación, sin código/migraciones.
- Migración candidata `supabase/migrations/20261128190000_romax_r3_gmail_4a_metadata.sql`; test `supabase/tests/romax_r3_gmail_4a_metadata.test.sql`; carrera `scripts/qa/romax_gmail4a_concurrency.sh`.
- CI https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/46176658892 : tres jobs `database`, `edge`, `frontend` en success; 3018 pgTAP / 41 archivos (50 nuevos), 38 Deno, 21 frontend y tres carreras reales en stack aislado (importación, revisión SOL2, metadatos adjuntos).
- Vercel: Preview de la rama y commit documental `4c92d7e` en `READY`, `target=null`. Sin prueba autenticada ni producción.

## Revisión de controles y evidencias

| Control | Inspección y resultado |
|---|---|
| Aislamiento tenant/oportunidad | FK compuesta `(organization_id,opportunity_id)` a oportunidad; RLS comercial heredado más políticas restrictivas de organización proveedora activa. Pruebas tenant cruzado/viewer/suspendido pasan en CI local. |
| Datos visibles | `GRANT SELECT` por columnas y vista `public.romax_attachment_metadata` con `security_invoker=true`; sin permiso a `source_message_id`, `source_attachment_id`, `storage_path`, checksum o error crudo para `authenticated`. |
| Mutaciones directas | `REVOKE ALL` y `GRANT INSERT` sólo columnas seguras para modalidad manual; políticas restrictivas impiden Gmail desde navegador y UPDATE/DELETE; `service_role` no conserva INSERT/UPDATE/DELETE directos. |
| RPC de registro | Wrapper `public.romax_register_gmail_attachment_metadata` invoker sólo ejecutable por `service_role` y definer privado con `search_path=''`; exige conexión Gmail coincidente/activa, proveedor activo, propietario activo y oportunidad Gmail con thread exacto. |
| Input y disponibilidad | JSON exacto, máximo 50 ítems y 256 KiB; control de locator, fecha, nombre, tipo/tamaño y allowlist solamente de metadatos. Nunca convierte un adjunto en `available` sin `scan_status='clean'`, ruta generada, hash, tamaño y estado de procesamiento; no existe writer de estados en 4A. |
| Identidad e idempotencia | Índice único legado por organización/mensaje/identificador de adjunto, extensión `part:` para MIME inline. Relectura idéntica es `unchanged`; conflicto de metadatos u oportunidad aborta. Oportunidad bloqueada `FOR UPDATE`; dos sesiones reales registran 1 fila y 1 evento. |
| Auditoría/inmutabilidad | Eventos privados insertados por trigger definer, sin grants directos y RLS habilitado; trigger bloquea UPDATE/DELETE/TRUNCATE; trigger de adjuntos bloquea cambio de identidad/contenido y borrado físico. Conserva registros manuales sin backfill. |
| Ausencia de contenido | Sin binarios, bucket, URLs firmadas, escaneo, parser, descargas o extracción. R3-GMAIL.4A no debe declararse documentalmente operativo. |

## Advisors

- **CI local desechable:** 0 ERROR, 11 WARN, 9 INFO según log. La alerta nueva `rls_enabled_no_policy` sobre `romax_docs_private.attachment_events` es intencional: lectura/escritura directa denegadas; sólo trigger privilegiado inserta. Otros WARN de módulos heredados no se atribuyen a 4A.
- La acción ejecuta `supabase db advisors --local --type security --level info --fail-on none`: los lints no hacen fallar CI; la revisión humana y las dispensas documentadas son necesarias.
- **Supabase Cloud OneFacility, sólo lectura:** migraciones aplicadas hasta `20261128164558_romax_r3_sol_2_review`, sin 4A; `romax_opportunity_attachments` 0 filas, 0 incongruencias tenant; sin tabla privada ni RPC 4A. El asesor Cloud devuelve 8 INFO por tablas privadas/sin políticas y WARN heredados sobre funciones SECURITY DEFINER ejecutables y protección de contraseñas. **Estos resultados no certifican el candidato 4A** ni autorizan alterar configuraciones de otros módulos.
- Consulta de dependencias en Cloud sobre la tabla actual no devolvió vistas ni funciones de acceso indirecto adicionales.

## Observaciones y tratamiento

1. **Obligatorio en 4B:** comprobar cada `message_id` y `attachmentId`/parte MIME frente a los datos obtenidos del hilo Gmail autorizado por servidor antes de llamar a la RPC. El simple texto `p_thread` no prueba pertenencia remota; 4A deliberadamente no hace llamadas Gmail.
2. **Obligatorio en 4B:** derivar `p_actor` de usuario autenticado y verificado, nunca de parámetros del navegador; confirmar owner activo y conexión vigente, controlar token caducado/desconexión/cambio de cuenta y no devolver identificadores internos.
3. **Endurecimiento 4B:** sanitizar presentación del nombre con caracteres Unicode de control bidireccional/invisibles y evitar su uso en rutas o decisiones de confianza. No es explotación de almacenamiento en 4A: todavía no se descargan archivos y la ruta futura será UUID.
4. **Obligatorio en 4C:** validar firma/contenido/tamaño reales, Office/ZIP y escáner en cuarentena antes de `available`. Un nombre/MIME compatible por metadatos no valida un archivo.
5. **Deuda de CI heredada, no bloqueo 4A:** el paso TypeScript admite de forma explícita tres diagnósticos conocidos de `src/pages/Index.tsx` si su hash coincide. No describir esto como TSC completamente limpio; resolver en ticket independiente.
6. **Antes de una futura Cloud:** revalidar migrations drift, privileges y advisors en el entorno destino; correr pruebas de una migración aislada y auditoría SQL; requiere autorización expresa. La política de `--fail-on none` debe reevaluarse al definir gates de Cloud.

## Decisión de cierre y siguiente incremento

**4A cerrado en revisión de seguridad del candidato GitHub/local**; no se identifican bloqueantes de 4A que requieran correctivo SQL inmediato. No cerrar implantación Cloud, no merge, no producción, no reales. **4B** debe implementar detección dirigida sin descargar binarios, con límites 80 mensajes / 50 adjuntos por exploración, filtros de adjuntos reales vs inline/firma/links/outgoing, validación completa de pertenencia al hilo, bloqueo de reuso cross-tenant, relectura idempotente, salidas parciales y reintentos. Edge QA aislada, Deno + pgTAP + concurrencia + regresión; PR apilado en #139 sólo cuando se autorice desarrollo 4B. Ningún cambio de 4A se aplicó en Supabase Cloud.
