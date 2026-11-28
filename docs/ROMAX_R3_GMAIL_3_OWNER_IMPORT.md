# R3-GMAIL.3 — importación con confirmación del propietario

Estado: candidato GitHub, no aplicado ni desplegado. Depende de PR #132 (R3-GMAIL.2.2.1 PASS manual). Decisiones D01–D12 aprobadas el 28/11/2026.

## Contrato
- Solo new_candidate (quote_request sin lectura limitada ni fecha ambigua) recibe confirmación cifrada de cinco minutos. La confirmación se liga al tenant, usuario, conexión, origen, hilo, mensaje y digest del candidato.
- Revisar e importar abre confirmación explícita individual; cancelar no escribe. No hay importación automática ni masiva. link_existing abre análisis de la oportunidad ya existente, sin crear ni alterar registros; review_required y not_importable no se importan.
- El servidor verifica JWT contra Auth, owner activo, tenant configurado, conexión y buzón, vuelve a leer el hilo exacto mediante Gmail readonly y compara el digest. Ignora contenido de candidato enviado por el navegador. Cambio en conversación, expiración o autorización implica rechazo.
- RPC SECURITY INVOKER con ejecución exclusiva service_role; lock de conexión y comprobación transaccional de owner y proveedor activo. Oportunidad y auditoría insertadas en una transacción; índices únicos existentes de mensaje/hilo y nonce de auditoría hacen idempotentes las repeticiones. Auditoría no accesible desde navegador; no permite update/delete/truncate. Protección de origen e identidad Gmail; descarte lógico en lugar de borrado.
- Se conserva solamente asunto, remitente, fecha de recepción, extracto de hasta 500 caracteres, clasificación y razón, identificadores de origen y evidencia de confirmación. Estado new, match_status unmatched. No se descargan ni crean adjuntos ni se guardan cuerpos completos; plazos/referencias quedan en la vista previa (su persistencia estructurada y adjuntos son posteriores).
- Permisos manuales existentes conservados. Al registrar se refresca la bandeja; resultado de duplicado abre la oportunidad existente. No hay asignación automática de cliente, sede ni contacto.

## Gates
- Flags server-side deshabilitados por defecto: ROMAX_GMAIL_IMPORT_ENABLED (producción) y ROMAX_GMAIL_QA_IMPORT_ENABLED (QA). QA mantiene OAuth lifecycle bloqueado. El frontend depende del token emitido por servidor. Para QA v4 se requiere origin exacto de la rama nueva y variable Vercel Preview branch-only previamente autorizadas; QA comparte DB, por lo que el primer ensayo real requiere autorización explícita y confirmación del propietario.
- CI local desechable: paridad Edge, Deno, pgTAP completo, concurrencia mediante dos sesiones PostgreSQL, TypeScript/ESLint, test de guard visual y build. No link Cloud. Fixtures sintéticos.
- PR apilado sobre PR #132; el workflow Gmail acepta ambas ramas base para probarlo. Reorientar a productization/mvp después de merge autorizado del #132 y ejecutar todos los checks de integración.
- No autoriza migración Cloud, Edge QA v4, cambios de secretos/variables, merge, producción o importación real. Antes de QA: revisar advisors y CI, verificar migración canónica (CLI no disponible en el entorno de edición GitHub), autorizar aplicación y activar exclusivamente QA. Producción permanece deshabilitada.
