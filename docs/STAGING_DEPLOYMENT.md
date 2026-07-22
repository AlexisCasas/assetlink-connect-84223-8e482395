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

## Comportamiento ante configuración incompleta

La aplicación valida `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` al cargar.
Si falta alguna, en vez de pantalla blanca muestra una pantalla de configuración
pendiente. En desarrollo también registra un error claro en la consola. R2 no
se valida porque todavía es opcional.
