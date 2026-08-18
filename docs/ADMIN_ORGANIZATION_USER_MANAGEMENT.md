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

## Contraseña temporal

Al crear o reutilizar un usuario, un platform admin puede indicar una contraseña
temporal de al menos 8 caracteres. Esta opción está pensada para staging y demo,
donde se usan correos ficticios y no es posible completar una invitación por
email. La contraseña se envía únicamente a la Edge Function, no se devuelve ni
se registra, y permite que el usuario inicie sesión de inmediato.

En producción se recomienda usar el flujo de invitación o recuperación de
contraseña por email. La contraseña temporal debe comunicarse al usuario por un
canal seguro y cambiarse después del primer acceso.

## Prueba

1. Iniciar sesión como platform admin.
2. Crear organizaciones cliente y proveedor.
3. Crear usuario cliente (`owner`/`requester`) y proveedor (`quote_manager`).
   Para staging/demo, asigne una contraseña temporal de al menos 8 caracteres.
4. Iniciar sesión con ambos y confirmar organización activa.
5. Confirmar que Administración no aparece para usuarios no platform_admin.
