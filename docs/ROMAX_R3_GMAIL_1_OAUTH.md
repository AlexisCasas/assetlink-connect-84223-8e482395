# R3-GMAIL.1 — Conexión OAuth de One Facility

Estado: candidato Draft, sin aplicar migraciones, sin desplegar Edge Function ni frontend, sin importar mensajes. El conector ChatGPT no se reutiliza. Alcance confirmado: siete días, sincronización manual, clasificación/actualizaciones, confirmación owner, sin envío/modificación, PDF/XLSX/DOCX; se implementan en R3-GMAIL.2–4, no en este incremento.

## Decisiones de implementación
- Edge Function POST autenticada mediante Supabase Auth getUser, CORS exacto, tenant configurado y propietario activo del proveedor comprobado desde DB. El gateway no verifica JWT para esta función; la función exige getUser en cada POST y no permite callback anónimo.
- OAuth web server, gmail.readonly exclusivamente, state aleatorio de 256 bits con hash y caducidad 10 min, PKCE S256, confirmación en callback SPA con sesión vigente y state local. Claim atómico de un solo uso; revalidación de owner antes de almacenar. El perfil de Gmail debe coincidir con el buzón configurado. El código no se conserva en URL tras montar callback.
- Refresh token cifrado AES-256-GCM con IV aleatorio y AAD por organización/propósito; no se devuelve token al navegador ni se guarda access token. Tabla de acceso service-only, RLS, grants explícitos. La clave debe mantenerse separada; rotación requiere procedimiento antes de cambiarla.
- Acciones start/status/complete/verify/disconnect; verify solo refresca y consulta perfil, no lee mensajes. Desconectar intenta revocar en Google antes de limpiar la fila; estado revoking permite reintentar después de 60 segundos para evitar revocaciones concurrentes. No hay scheduler, envío ni importación. El botón sincronizar aparece deshabilitado.
- UI solo propietario de ROMAX; el servidor verifica tenant independientemente. Sin cambios a R2 ni perfiles.

## Configuración manual (después de CI y autorización de despliegue)
1. Google Cloud Console: proyecto controlado por ROMAX, habilitar Gmail API; configurar Google Auth Platform (Branding, Audience, Data Access). Si Google Workspace lo permite, Internal para usuarios de la organización; si External/Testing, agregar exclusivamente el buzón autorizado como test user. gmail.readonly es restringido; verificar requisitos de Google para producción y políticas Workspace. Testing externo puede emitir refresh tokens de 7 días.
2. Clients > Create client > Web application. Registrar URI EXACTA: https://one-facility.vercel.app/gmail/callback (confirmar dominio productivo antes de habilitar).
3. Configurar en Supabase Edge Function Secrets por canal autorizado: ROMAX_GMAIL_CLIENT_ID, ROMAX_GMAIL_CLIENT_SECRET, ROMAX_GMAIL_ORGANIZATION_ID, ROMAX_GMAIL_EXPECTED_EMAIL, ROMAX_GMAIL_APP_ORIGIN (origen HTTPS sin barra final), ROMAX_GMAIL_ENCRYPTION_KEY (32 bytes aleatorios codificados en base64). No pegar valores secretos en chat, GitHub ni variables VITE_. Usar Supabase URL/anon/service role provistos en servidor. No usar credenciales del conector ChatGPT.
4. Aplicar solo migración aditiva versionada tras aprobación y QA, desplegar función al proyecto OneFacility explícito (config.toml local tiene otra ref; nunca config push). Después desplegar frontend con autorización separada.
5. Owner: Oportunidades > Bandeja Gmail > Conectar Gmail, elegir buzón autorizado y consentir solo lectura; Completar conexión; Verificar conexión; desconectar/reconectar para QA. Probar usuario no owner, otra organización, buzón equivocado, state expirado/repetido y sesión perdida. No leer mensajes en QA de este incremento.

## Gate de migración
El CLI no estaba disponible en el entorno de autoría. La primera ejecución del job aislado en GitHub Actions (46063778966, job 140724080366) ejecutó supabase migration new y generó supabase/migrations/20261127205522_romax_r3_gmail_connection.sql. QA SQL: 38 archivos / 2,894 aserciones, PASS, con los 12 checks de ACL nuevos. El SQL y pgTAP ensayados se trasladan sin cambios a las rutas canónicas; la prueba final usa esos archivos directamente. El CI inicial tuvo un fallo de resolución npm en Deno, corregido con --node-modules-dir=none. CI de servidor sobre 67a7b81, run 46063938003, job 140724618556: deno check y seis pruebas PASS (0 fallos). El head final debe volver a pasar todos los gates. No aplicar en Cloud hasta autorización.

## Evidencias esperadas
Deno check + pruebas criptográficas, pgTAP ACL y regresión, TypeScript sin nuevos diagnósticos, ESLint nuevo UI, build. Pruebas de máquina de estados con Google y almacenamiento simulados añadidas (autenticación, tenant, propietario, expiración, concurrencia/replay, buzón y alcance incorrectos, verificación y revocación); falta confirmar CI y QA real OAuth. No declarar seguridad validada hasta completarlas. Revisar errores, revocación, expiración y recuperación de estado, así como política de retención de datos de Google.


Activación autorizada 27-nov-2026: MCP aplicó el SQL idéntico y asignó versión Cloud 20261127205522. Se renombra archivo Git sin cambiar blob; no reejecutar versión original 20261127202747. Tabla vacía, RLS habilitado, anon/authenticated sin lectura, service_role con lectura. Edge Function activa v1; QA OAuth real pendiente.
