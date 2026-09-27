# Despliegue de staging

Este documento prepara el despliegue; no ejecuta despliegues ni contiene secretos.

## Arquitectura

- Frontend: Vercel.
- Backend, Auth, PostgreSQL y Storage: Supabase Cloud.
- Cloudflare R2: pendiente y opcional; no bloquea staging.

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

## Comportamiento ante configuración incompleta

La aplicación valida `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` al cargar.
Si falta alguna, en vez de pantalla blanca muestra una pantalla de configuración
pendiente. En desarrollo también registra un error claro en la consola. R2 no
se valida porque todavía es opcional.
