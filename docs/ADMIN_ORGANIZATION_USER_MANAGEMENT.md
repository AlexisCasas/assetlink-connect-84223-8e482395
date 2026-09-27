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
supabase functions deploy admin-create-organization
supabase functions deploy admin-archive-organization
supabase functions deploy send-organization-invitation
```

Secrets requeridos en Supabase Functions: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` y, desde Fase 1 · Punto 6B, `PUBLIC_APP_URL` (ver `docs/USER_INVITATIONS.md`). La service role nunca se configura en Vercel ni frontend.

`admin-add-existing-member` es **solo para platform admin** (activa una
membership de inmediato, sin invitación ni aceptación) — no está conectada a
ninguna UI de tenant. `admin-invite-organization-member` está **retirada**
(responde 410); el flujo productivo de invitación es
`send-organization-invitation`.

`admin-update-organization-member` ya no contiene lógica de autorización
propia: reenvía la llamada a la RPC `update_organization_member` usando el
JWT de quien llama (nunca `service_role`), que es donde vive toda la
jerarquía de roles y la protección del último owner.

## Contraseña temporal (legacy — solo staging/demo)

**Desde Fase 1 · Punto 6B, este NO es el flujo productivo.** El flujo
productivo real para una organización normal es **Invitación de usuarios**
(`docs/USER_INVITATIONS.md`): siempre requiere el consentimiento explícito
del invitado (aceptar) antes de crear cualquier membership.

Al crear o reutilizar un usuario con `admin-create-user-and-add-member`, un
platform admin puede indicar una contraseña temporal de al menos 8
caracteres. Esta opción sigue existiendo solo para **staging y demo**, donde
se usan correos ficticios y no es posible completar una invitación por
email real. La contraseña se envía únicamente a la Edge Function, no se
devuelve ni se registra, y permite que el usuario inicie sesión de
inmediato — la membership queda activa sin ningún paso de aceptación.

**Cambio de seguridad importante:** esta función **ya no sobrescribe la
contraseña de un usuario existente**. Si el correo ya tiene una cuenta en
Supabase Auth, `temporary_password` se ignora por completo (antes permitía
que cualquier platform admin tomara el control de cualquier cuenta
existente cambiándole la contraseña — ver `docs/USER_INVITATIONS.md` para el
detalle de esa vulnerabilidad y su corrección).

El panel "Crear usuario" en AdminConsole está oculto cuando
`VITE_APP_ENV === 'production'`. En producción, use siempre "Invitar
usuario" desde la vista Usuarios de la organización correspondiente.

## Prueba

1. Iniciar sesión como platform admin.
2. Crear organizaciones cliente y proveedor.
3. Crear usuario cliente (`owner`/`requester`) y proveedor (`quote_manager`).
   Para staging/demo, asigne una contraseña temporal de al menos 8 caracteres.
4. Iniciar sesión con ambos y confirmar organización activa.
5. Confirmar que Administración no aparece para usuarios no platform_admin.
