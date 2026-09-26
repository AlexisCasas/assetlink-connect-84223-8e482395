# Organization access hardening

Prerrequisito de seguridad del Fase 1 · Punto 6 (invitación productiva de
usuarios). Migración: `supabase/migrations/20260926203242_organization_access_hardening.sql`.
Pruebas: `supabase/tests/organization_access_hardening.test.sql`.

Esta rama cierra **solo** la superficie de escritura directa (PostgREST) sobre
las tablas de organización, membresías, invitaciones y auditoría. No agrega
invitaciones productivas, correo, aceptación ni UI nueva.

## Vulnerabilidad

`organizations`, `organization_members`, `organization_invitations`,
`activity_logs` y `audit_logs` heredaron los *default privileges* de Supabase:
`anon` y `authenticated` tenían `SELECT, INSERT, UPDATE, DELETE, TRUNCATE,
REFERENCES, TRIGGER` sobre las cinco. Además,
`20260717224621_multitenant_foundation.sql` creó policies RLS que permiten a
cualquier owner/admin de un tenant escribir directamente:

- `organization_members`: `INSERT`, `UPDATE` y `DELETE` para owner/admin.
- `organizations`: `UPDATE` para owner/admin **sobre cualquier columna**.
- `activity_logs`: `INSERT` para cualquier miembro, con su propio `actor_user_id`.

Con eso, un **admin de un tenant** podía, con una sola llamada PostgREST:

| Ataque | Efecto |
|---|---|
| `UPDATE organization_members SET role = 'owner'` sobre sí mismo | autopromoción a owner |
| `UPDATE organization_members SET is_active = false` sobre el owner | desactiva o degrada al owner, salteando la protección de "último owner" (solo existe en `admin-update-organization-member`) |
| `INSERT INTO organization_members` | añade a cualquier usuario, con cualquier rol, sin invitación |
| `UPDATE organizations SET organization_type = 'platform_admin'` | `is_platform_admin()` pasa a `true`, lo que da lectura cross-tenant de toda la plataforma |
| `UPDATE/DELETE activity_logs`, `audit_logs` | borra o reescribe la auditoría |

Se reprodujo en local con usuarios sintéticos y el estado del remoto se
confirmó mediante una lectura de sus privilegios.

## Superficie eliminada

Privilegios de tabla para `anon` y `authenticated` sobre las cinco tablas
(`information_schema.role_table_grants`):

| Tabla | Antes (anon y authenticated) | Después: authenticated | Después: anon |
|---|---|---|---|
| organizations | todos | `SELECT` + `UPDATE (name, legal_name, tax_id)` | ninguno |
| organization_members | todos | `SELECT` | ninguno |
| organization_invitations | todos | `SELECT` | ninguno |
| activity_logs | todos | `SELECT` | ninguno |
| audit_logs | todos | `SELECT` | ninguno |

Policies eliminadas (defensa en profundidad: aunque un `GRANT` se reabra por
accidente en el futuro, no vuelve a haber una policy que permita escribir):

- `organization_members`: "organization administrators can add memberships",
  "… can update memberships", "… can remove memberships".
- `activity_logs`: "members can write their own activity logs".

Policies que se conservan sin cambios:

- `SELECT` de las cinco tablas: miembros, owner/admin o platform admin, según
  la tabla.
- `organizations` "organization administrators can update organizations":
  sigue exigiendo owner/admin del tenant. Ahora solo alcanza tres columnas.

`service_role` recibe explícitamente `SELECT, INSERT, UPDATE, DELETE` sobre las
cinco tablas. En el remoto ya los tenía, así que es un no-op. La razón es no
depender de *default privileges*: con Supabase CLI (verificado en v2.106) y
`[api] auto_expose_new_tables` sin definir, un `supabase db reset` local crea
las tablas de `public` sin DML para `anon`, `authenticated` ni `service_role`.

## Escrituras legítimas que siguen funcionando

| Escritura | Vía | Por qué sigue funcionando |
|---|---|---|
| Perfil de organización (`OrganizationProfile.tsx`): `organizations.update({ name, legal_name, tax_id }).eq('id', …)` | PostgREST, rol `authenticated` | Privilegio de columna `UPDATE (name, legal_name, tax_id)` + la policy owner/admin existente. `updated_at` lo fija el trigger `touch_updated_at`, que no requiere privilegio de columna. |
| Crear organización, añadir/crear/actualizar miembros, invitar, listar, archivar, auditar | Edge Functions `admin-*` | Usan `service_role` (BYPASSRLS) con grants explícitos. |
| `audit_logs` al cambiar audiencia de una solicitud | `set_request_audience` | Es `SECURITY DEFINER` y escribe como su owner, no como `authenticated`. |

Se revisaron `src/` y `supabase/functions/`. Ningún código cliente inserta,
actualiza ni borra filas de `activity_logs`, `audit_logs`,
`organization_members` ni `organization_invitations`. La única escritura
cliente sobre estas tablas es la de `organizations` descrita arriba.

## Por qué `organizations` conserva solo tres columnas actualizables

`name`, `legal_name` y `tax_id` son datos de perfil que el propio tenant
administra. Todas las demás columnas son estructurales o de seguridad:

- `organization_type` decide `is_platform_admin()` y el tipo de operación
  (cliente, proveedor…).
- `status` decide si la organización está activa o archivada; solo lo cambia
  `admin-archive-organization`.
- `settings`, `created_by`, `id` y los timestamps no tienen un caso de edición
  cliente.

Un `UPDATE` que mezcla una columna permitida con una no permitida falla
completo con `42501`. No se aplica "a medias".

Un platform admin que edita el perfil de otra organización sigue guardando
`organization_profiles`, pero no `organizations`. Es el mismo comportamiento
que antes: la policy de `organizations` nunca incluyó a platform admins.

## Regla a partir de ahora

- Las escrituras de membresías e invitaciones pasan **exclusivamente** por
  funciones controladas: Edge Functions con `service_role` o RPCs
  `SECURITY DEFINER` con validación de rol y jerarquía. Nunca por
  `INSERT/UPDATE/DELETE` directo desde el cliente.
- Esta rama **no** modifica `ALTER DEFAULT PRIVILEGES` para `public`. Cambiarlo
  globalmente podría romper otras áreas. En su lugar, **toda tabla sensible
  nueva debe declarar explícitamente su `REVOKE`/`GRANT`** para `anon`,
  `authenticated` y `service_role`, como hace esta migración. No se debe
  confiar en los defaults, que difieren entre el remoto y un reset local
  reciente.

## Qué NO cambia en esta rama

- La lógica de las Edge Functions `admin-*`. Las reglas de jerarquía de roles
  (admin asignando owner, etc.) se abordan en el PR de invitaciones
  productivas.
- Invitaciones productivas, correo o SMTP, aceptación, reenvío, revocación,
  expiración, vista de usuarios y `AuthContext`.

## Verificación

- **pgTAP** (`organization_access_hardening.test.sql`, 103 checks).
  - Cada intento se ejecuta como `authenticated` o `anon` con un `auth.uid()`
    sintético. El estado se verifica después como `postgres`.
  - Cubre: autopromoción, degradar o desactivar al owner, insertar y borrar
    membresías, cambiar `organization_type`/`status`/`settings`, convertirse en
    `platform_admin`, insertar/actualizar/borrar invitaciones, forjar o borrar
    `activity_logs`/`audit_logs`, y acceso `anon`.
  - Comprueba que `is_platform_admin()` sigue `false`, inmediatamente después
    del intento `platform_admin` y al final.
  - Comprueba las escrituras legítimas: perfil por owner y admin; otro tenant
    y un viewer no pueden.
  - Comprueba que las lecturas por RLS de miembro, admin y platform admin
    siguen funcionando, y que `service_role` crea, actualiza, invita, audita
    y archiva.
- **Control negativo:** con los grants y policies anteriores reabiertos dentro
  de una transacción, la misma suite falla (54 de 103 checks), incluida la
  aserción de `is_platform_admin()`. Las pruebas detectan la vulnerabilidad;
  no pasan por construcción.
- **E2E local**, con script temporal fuera del repo y `supabase functions
  serve`:
  - Las 7 Edge Functions `admin-*` funcionan con JWT reales.
  - La consulta exacta de `OrganizationProfile` funciona para owner y admin.
  - Los 10 intentos de escalamiento vía PostgREST devuelven `42501`.
  - `anon` recibe `42501` en las cinco tablas.
