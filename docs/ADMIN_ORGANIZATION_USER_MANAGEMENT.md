# Administración de organizaciones

El Admin Console usa Edge Functions; nunca usa `service_role` desde el frontend.

## Primer platform admin

En Supabase SQL Editor, cree una organización `platform_admin` y una membresía activa `owner` para el UUID del usuario Auth inicial. Hágalo sólo con un operador autorizado.

## Deploy

```bash
supabase functions deploy admin-list-organization-members
supabase functions deploy admin-create-user-and-add-member
supabase functions deploy admin-update-organization-member
supabase functions deploy admin-add-existing-member
```

Secrets requeridos en Supabase Functions: `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY`. La service role nunca se configura en Vercel ni frontend.

## Prueba

1. Iniciar sesión como platform admin.
2. Crear organizaciones cliente y proveedor.
3. Crear usuario cliente (`owner`/`requester`) y proveedor (`quote_manager`).
4. Iniciar sesión con ambos y confirmar organización activa.
5. Confirmar que Administración no aparece para usuarios no platform_admin.
