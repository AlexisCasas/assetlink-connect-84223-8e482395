# Despliegue de staging

Este documento prepara el despliegue; no ejecuta despliegues ni contiene secretos.

## Arquitectura

- Frontend: Vercel.
- Backend, Auth, PostgreSQL y Storage: Supabase Cloud.
- Cloudflare R2: fundación desplegada (Fase 1 · Punto 7, `asset-files`),
  sin UI todavía (Punto 10). Requerido para que esa Edge Function funcione,
  pero no bloquea el resto de staging.

## Variables de Vercel

Configurar en el proyecto de Vercel, para el entorno **Preview/Staging**:

```dotenv
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon-o-publishable-key-del-proyecto-staging>
VITE_APP_ENV=staging
VITE_ENABLE_DEMO_SEED=false
```

Las variables con prefijo `VITE_` llegan al navegador. La anon/publishable key
es una clave pública de cliente y el control de datos debe mantenerse en RLS.
Nunca definir `SUPABASE_SERVICE_ROLE_KEY`, secretos R2 ni otros secretos de
backend como variables `VITE_*` o variables cliente de Vercel.

## Variables de Edge Functions

Si se despliegan Edge Functions, configurar sus secretos en Supabase Cloud:

```dotenv
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=<anon-o-publishable-key>
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
```

`SUPABASE_SERVICE_ROLE_KEY` solo se usa en funciones/backend cuando sea
estrictamente necesario; nunca va al frontend. Supabase provee secretos por
defecto a las funciones alojadas, pero deben verificarse antes de desplegar.

No subir `.env`, `.env.local`, archivos de secretos ni claves reales a Git.
Usar únicamente `.env.example` como plantilla segura.

## Publicar schema y funciones

Desde una estación autorizada, con el proyecto de Supabase correcto:

```bash
supabase link --project-ref <ref>
supabase db push
supabase functions deploy <function-name>
```

Antes de desplegar funciones, cargar sus secretos en Supabase Cloud. Luego:

- Confirmar las Auth Redirect URLs de staging y preview de Vercel.
- Verificar Site URL y proveedores OAuth si aplican.
- Probar RLS con usuarios reales; no usar service role para simular el frontend.
- Confirmar que todas las migraciones locales aparecen aplicadas en Cloud.

## Checklist funcional de staging

1. Crear usuarios cliente y proveedor en Supabase Auth.
2. Crear sus organizaciones y memberships activos.
3. Crear una sucursal de la organización cliente.
4. Cliente crea una solicitud pública.
5. Proveedor ve la solicitud pública y guarda/envía una cotización.
6. Cliente ve la cotización y la aprueba o rechaza.
7. Cliente crea la orden de trabajo desde la cotización aprobada.
8. Cliente y proveedor verifican la orden en **Órdenes de trabajo**.
9. Confirmar en consola que el flujo no genera 403 de `providers`,
   `assignments` ni tablas legacy de chat.

## Invitaciones productivas de usuarios (Fase 1 · Punto 6B)

Antes de invitar usuarios reales en staging/producción, ver
`docs/USER_INVITATIONS.md` para el detalle completo. Checklist mínimo:

1. **SMTP propio configurado** en Auth → SMTP Settings. El servicio integrado
   de Supabase solo entrega a direcciones del equipo del proyecto y tiene un
   límite de 2 correos/hora — no sirve para usuarios externos reales.
2. **Site URL** = dominio productivo/staging real.
3. **Redirect URLs** incluye `<dominio>/invitations/accept`.
4. **Plantillas** "Invite user" y "Magic Link" configuradas con el patrón
   `{{ .RedirectTo }}&token_hash={{ .TokenHash }}&type=invite` (o
   `type=magiclink`) — nunca el enlace `{{ .ConfirmationURL }}` por defecto.
5. **OTP expiry** = 86400 (24h).
6. **"Confirm email"** activado y **"Allow new users to sign up"
   desactivado** — crítico: sin esto, cualquiera podría autoregistrarse con
   el correo invitado y aceptar la invitación.
7. Secreto de Edge Function `PUBLIC_APP_URL` cargado (dominio real, con
   `https://`). Sin él, `send-organization-invitation` falla cerrado.
8. Desplegar `send-organization-invitation` y las Edge Functions `admin-*`
   modificadas (`admin-update-organization-member`,
   `admin-create-organization`, `admin-create-user-and-add-member`,
   `admin-add-existing-member`); `admin-invite-organization-member` puede
   seguir desplegada (responde 410) o retirarse.
9. Probar el flujo completo con un correo real (no ficticio): invitar,
   aceptar como usuario nuevo, invitar a un usuario ya existente, aceptar.

## Alertas automáticas (Fase 1 · Punto 8)

Antes de desplegar en staging/producción, ver `docs/AUTOMATIC_ALERTS.md`
para el detalle completo. Checklist mínimo:

1. La migración `20260927150952_automatic_alerts_schedule.sql` hace
   `CREATE EXTENSION IF NOT EXISTS pg_cron` — en un proyecto Supabase
   hospedado esto requiere que `pg_cron` esté disponible/habilitado para el
   proyecto (Database → Extensions). Si el `db push` falla en ese paso,
   habilitar la extensión desde el dashboard antes de reintentar.
2. Los horarios de `cron.schedule` están en **UTC/GMT** (documentado por
   Supabase), no en la zona horaria local del servidor ni del navegador.
3. Después de desplegar, confirmar en `cron.job` que existen y están
   activos `automatic-alert-generation` (`5 * * * *`) y
   `automatic-alert-history-cleanup` (`30 3 * * *`), y tras la primera hora
   confirmar en `cron.job_run_details` que `automatic-alert-generation`
   corrió con `status = 'succeeded'`.
4. **Deuda temporal a revocar después**: `generate_operational_due_notifications()`
   y `generate_inspection_due_notifications()` (las funciones públicas
   originales) conservan su `GRANT EXECUTE` a `authenticated` en esta
   migración a propósito — el frontend ya no las llama, pero el grant no se
   revoca todavía. Una vez verificado que el cron + frontend funcionan
   correctamente en producción, aplicar una migración exclusiva que las
   revoque (ver `docs/AUTOMATIC_ALERTS.md`).

## Comportamiento ante configuración incompleta

La aplicación valida `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` al cargar.
Si falta alguna, en vez de pantalla blanca muestra una pantalla de configuración
pendiente. En desarrollo también registra un error claro en la consola.

Los 4 secretos R2 (`R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
`R2_BUCKET_NAME`) son server-side (Edge Function `asset-files`) y fallan
cerrado: si falta alguno o tiene un formato inválido, la función responde
500 sin loguear ningún valor — nunca cae a un bucket o cuenta por defecto.
Ver `docs/R2_FOUNDATION.md`.

## Cloudflare R2 (Fase 1 · Punto 7)

Antes de que `asset-files` pueda operar contra un R2 real:

1. Crear el bucket **completamente privado** (`one-facility-prod-private`;
   opcionalmente `one-facility-dev-private` para staging/dev). Nunca
   público, nunca con dominio `r2.dev` ni dominio personalizado.
2. Crear un token de API "Object Read & Write" **limitado a ese bucket**
   (nunca un token de cuenta completo), uno distinto por entorno.
3. Configurar CORS del bucket — ver `docs/R2_FOUNDATION.md` para el JSON
   exacto (métodos `PUT`/`GET` únicamente; `HEAD`/`DELETE` los ejecuta el
   servidor y no pasan por el navegador).
4. Cargar los 4 secretos en Supabase Functions (nunca en Vercel, nunca con
   prefijo `VITE_`).
5. Desplegar `asset-files` (`supabase functions deploy asset-files`).
6. No hay UI todavía (Punto 10) — validar con las pruebas descritas en
   `docs/R2_FOUNDATION.md`.
