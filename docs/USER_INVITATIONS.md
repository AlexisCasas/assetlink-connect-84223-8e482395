# Invitación productiva de usuarios (Fase 1 · Punto 6B)

Construida sobre el hardening de `docs/ORGANIZATION_ACCESS_HARDENING.md`.
Migración: `supabase/migrations/20260926205830_production_user_invitations.sql`.
Pruebas: `supabase/tests/organization_invitations.test.sql`.

## Principio rector

```
owner/admin → crea invitación → correo real → usuario se autentica → acepta → membership
```

La membership **solo se crea al aceptar**, nunca por enviar el correo, ni por
que el admin la haya "creado". Esto reemplaza el patrón anterior
(`admin-create-user-and-add-member`: crear usuario confirmado + contraseña
temporal + membership automática), que ahora es explícitamente **legacy,
solo staging/demo** — ver `docs/ADMIN_ORGANIZATION_USER_MANAGEMENT.md`.

## Modelo de datos

`organization_invitations` (ya existía desde `20260721045641`), con columnas
nuevas de esta fase: `invited_name`, `last_sent_at`, `last_send_attempt_at`,
`send_count`, `revoked_by`. `expires_at` ahora es `NOT NULL` con default
`now() + 7 days`.

**Intento vs. envío confirmado** — tres columnas con semánticas distintas y
que no deben mezclarse:

| Columna | Significa | Quién la escribe |
|---|---|---|
| `last_send_attempt_at` | último intento de envío **reservado** (puede haber fallado después) | `create_organization_invitation` y `resend_organization_invitation`, dentro del lock de la fila |
| `last_sent_at` | último envío **confirmado** (Supabase Auth aceptó el correo) | solo `mark_invitation_sent` |
| `send_count` | número de envíos **confirmados** | solo `mark_invitation_sent` |

El cooldown de 1 minuto se evalúa contra el más reciente de los dos
timestamps (`GREATEST(last_send_attempt_at, last_sent_at)`). Un fallo de
envío nunca libera el intento: `last_send_attempt_at` no vuelve a `NULL`,
así que el reintento solo es posible pasado el minuto (sin retry storms).

**`token_hash` es legacy/no usado.** La seguridad de aceptar una invitación
no depende de la posesión de un token propio — el uuid de la invitación en
la URL no es secreto. Depende de tener una **sesión de Supabase Auth
autenticada, con email confirmado, cuyo email coincide (en minúsculas) con
el de la invitación**. Un token propio adicional no aportaría seguridad
real y sí un segundo secreto que gestionar.

**Estado efectivo** (nunca depende de un cron): una invitación con
`status='pending'` y `expires_at <= now()` se trata como **vencida** en
todas las lecturas (`accept_organization_invitation`,
`list_organization_access`, `get_my_pending_invitations`), aunque la columna
siga diciendo `pending`. `create_organization_invitation` y
`resend_organization_invitation` normalizan la fila físicamente cuando
tienen éxito. **`accept_organization_invitation` NO puede hacerlo**: un
`RAISE EXCEPTION` deshace cualquier escritura hecha en la misma llamada
(semántica de subtransacción de Postgres) — verificado explícitamente con
una prueba pgTAP que lo confirma.

## Jerarquía de roles — `can_manage_organization_role`

Función SQL centralizada, usada por `create_organization_invitation`,
`resend_organization_invitation`, `revoke_organization_invitation` y
`update_organization_member`:

| Actor | Puede gestionar |
|---|---|
| platform admin | cualquier rol, en cualquier organización no `platform_admin` |
| owner | cualquier rol, incluido `owner` |
| admin | cualquier rol **excepto** `owner` |
| manager o inferior | ninguno |

Reglas adicionales, aplicadas en `update_organization_member`:
- Un admin (no owner, no platform admin) **no puede modificar su propia
  membresía** (ni cambiarse el rol ni desactivarse).
- El **último owner activo** de una organización no puede ser degradado ni
  desactivado — con `SELECT ... FOR UPDATE` real sobre las filas de owners
  antes de contar, para que dos solicitudes concurrentes no puedan dejar la
  organización sin ningún owner.
- Nunca se confía en el rol enviado por el frontend: `accept_organization_invitation`
  **no recibe ningún parámetro de rol** — siempre lo toma de la invitación
  ya validada en el servidor.

### `can_manage_invitation_target` — protección de owner inactivo

Encontrado en la auditoría final: si el correo invitado ya tenía una
membership **inactiva** en la organización, aceptar la invitación la
reactivaba con el rol de la invitación. Un admin podía así invitar a un
**owner desactivado** con rol `viewer` y, al aceptar, esa membership owner
quedaba reescrita como `viewer` activa — justo lo que
`update_organization_member` le prohíbe a un admin.

`can_manage_invitation_target(organization_id, email)` busca una membership
existente para ese correo y, si la hay, exige que el caller pueda gestionar
también su **rol actual** (vía `can_manage_organization_role`). Sin
membership previa devuelve `true`. Se aplica en
`create_organization_invitation` y se re-evalúa en
`resend_organization_invitation`. Resultado: un admin no puede invitar ni
reenviar a un owner inactivo; un owner sí. Es interna (sin `EXECUTE` para
`authenticated`/`anon`/`service_role`); solo la llaman otras funciones
`SECURITY DEFINER`.

Auto-gestión (cubierta por pgTAP): un admin activo no puede invitar su
propio correo (ya es miembro activo); un admin inactivo no puede invitar ni
reactivarse con `update_organization_member` (la jerarquía exige membership
activa).

## RPCs (todas `SECURITY DEFINER`, `SET search_path = public`)

| RPC | Quién la ejecuta | Qué hace |
|---|---|---|
| `create_organization_invitation` | authenticated (owner/admin/platform admin) | Valida jerarquía (rol pedido **y** rol de una membership inactiva existente, vía `can_manage_invitation_target`), organización activa y no `platform_admin`, sin duplicado pendiente ni miembro activo con ese correo. Inserta `pending`, `expires_at = now()+7d`, `last_send_attempt_at = now()` (reserva el primer envío); `send_count` sigue en 0. Audita. |
| `resend_organization_invitation` | authenticated | `SELECT ... FOR UPDATE`; re-evalúa jerarquía; solo si efectiva `pending`/`expired`; cooldown de 1 minuto **dentro del lock** contra `GREATEST(last_send_attempt_at, last_sent_at)`. Reutiliza la misma fila: pone `pending`, renueva `expires_at`, reserva `last_send_attempt_at = now()`. No toca `send_count`/`last_sent_at`. |
| `can_manage_invitation_target` | interna (ningún rol) | Si el correo ya tiene membership en la organización, exige poder gestionar su rol actual. |
| `mark_invitation_sent` | **solo `service_role`** | Se llama tras confirmar que Supabase Auth aceptó enviar el correo. Incrementa `send_count`, fija `last_sent_at`, audita `sent`/`resent`. Si el envío falla, nunca se llama — la fila queda intacta y reintentable. |
| `revoke_organization_invitation` | authenticated | Solo si efectiva `pending`/`expired`. Fija `revoked_at`/`revoked_by`. Un enlace anterior no vuelve a servir. |
| `accept_organization_invitation` | authenticated | La operación crítica — ver abajo. |
| `get_my_organization_invitation` | authenticated | Lectura propia por id; responde vacío (nunca error) si no es la cuenta correcta — no revela a quién iba dirigida una invitación ajena. |
| `get_my_pending_invitations` | authenticated | Invitaciones pendientes por el email confirmado del propio usuario — alimenta `NoOrganizationScreen`. |
| `list_organization_access` | authenticated (owner/admin/platform admin) | Miembros + invitaciones (excepto aceptadas; revocadas solo de 30 días) de una organización, en una sola lectura — sin N+1. |
| `update_organization_member` | authenticated | Sustituye la lógica que antes vivía inline en la Edge Function. Aplica toda la jerarquía de arriba con locks reales. |
| `get_auth_user_state_by_email` | **solo `service_role`** | Reemplaza `auth.admin.listUsers({perPage:1000})` (se truncaba a 1000 usuarios) para saber si un correo ya tiene cuenta. Nunca expuesta a `authenticated`: un owner/admin de tenant no puede enumerar cuentas de toda la plataforma. |

### `accept_organization_invitation(p_invitation_id)`

Transaccional, con `SELECT ... FOR UPDATE` sobre la invitación. Valida, en
orden: usuario autenticado → email de `auth.users` coincide (minúsculas) →
email confirmado → no revocada → no ya aceptada por otra cuenta → `pending`
→ no vencida → organización activa y no `platform_admin`. Luego:
- Inserta o reactiva `organization_members` (`ON CONFLICT (organization_id,
  user_id) DO UPDATE`), con el **rol de la invitación**, nunca del cliente.
- Marca la invitación `accepted`, con `accepted_by`/`accepted_at`.
- Audita `organization_invitation.accepted` y `organization_member.created`
  o `.reactivated`.

**Idempotente**: si la misma cuenta ya la aceptó, devuelve
`{status:'already_accepted', organization_id}` sin crear una segunda fila ni
lanzar error.

**Gotcha de PL/pgSQL descubierto y corregido**: `RETURNS TABLE(status text,
organization_id uuid)` declara implícitamente `organization_id` como
variable en el cuerpo de la función, lo que colisiona con
`organization_members.organization_id` — de forma más aguda en `ON CONFLICT
(organization_id, user_id)`, una posición sintáctica que no admite alias de
tabla. Se resolvió con la directiva `#variable_conflict use_column` al
inicio del cuerpo (y de forma análoga en `list_organization_access`, que
tiene el mismo problema con su columna `kind`).

## Flujo usuario nuevo

1. Owner/admin invita desde **Usuarios** → `send-organization-invitation
   {action:'create'}`.
2. La Edge Function ejecuta `create_organization_invitation` **con el JWT
   del caller** (nunca `service_role`) — la autorización vive una sola vez,
   en SQL.
3. Con `service_role`, consulta `get_auth_user_state_by_email`. Si no existe:
   `auth.admin.inviteUserByEmail(email, { redirectTo, data: { name } })`.
   Solo el nombre va en `data` — nunca un rol, que siempre se resuelve
   server-side desde la invitación.
4. Supabase envía la plantilla **Invite user**, que apunta a
   `<PUBLIC_APP_URL>/invitations/accept?invitation=<uuid>&token_hash={{ .TokenHash }}&type=invite`
   — nunca al endpoint `/verify` directo, para que un escáner de enlaces de
   correo corporativo no consuma el OTP con un GET.
5. `AcceptInvitation.tsx` llama `verifyOtp({token_hash, type:'invite'})`,
   borra `token_hash`/`type` de la URL de inmediato (`history.replaceState`
   vía `setSearchParams`), y muestra **"Crea tu contraseña"**
   (`updateUser({password})`, mínimo 8 caracteres, con confirmación).
6. Luego muestra la invitación (organización + rol) y el botón **"Aceptar
   invitación"** — nunca se acepta automáticamente solo por abrir el correo.
7. Al aceptar, si el envío del correo hubiera fallado en el paso 3-4, la fila
   de invitación sigue intacta y reintentable — nunca una segunda fila.

Verificado end-to-end en local con Mailpit: el usuario nuevo queda
`email_confirmed`, sin membership hasta aceptar explícitamente, y con
exactamente una fila en `organization_members` tras aceptar.

## Flujo usuario existente

Comparado en el diagnóstico: añadir membership de inmediato (inseguro, sin
consentimiento), magic link, o aceptación solo dentro de la app. Se eligió
**magic link como notificación + aceptación dentro de la app**:

- `service_role` no se usa para el envío del magic link — un cliente
  **anon-key dedicado** (`createAnonClient()` en `_shared/invitationEmail.ts`)
  llama `signInWithOtp({ email, options: { shouldCreateUser: false,
  emailRedirectTo } })`, exactamente como lo haría un usuario real.
- Plantilla **Magic Link**, mismo patrón de enlace con `type=magiclink`.
- **`type` real verificado en local, no asumido** (instrucción explícita del
  punto 17): un usuario nuevo recibe `type=invite`; un usuario existente
  confirmado recibe `type=magiclink`. Confirmado con un correo real
  capturado por Mailpit y decodificado con `new URL(...)`. Documentado aquí
  porque no está garantizado por ninguna referencia estática de Supabase.
- `shouldCreateUser: false` evita duplicar `auth.users` — verificado
  contando las filas por email antes y después del `verifyOtp`.
- La organización y el rol **nunca** vienen del correo/metadata: se resuelven
  siempre desde la fila de `organization_invitations` en el servidor.

## Expiración y reenvío

- Duración: **7 días**. OTP de Supabase Auth: **24 horas** (el máximo
  posible) — la invitación dura más que el enlace de un correo individual;
  reenviar genera un OTP nuevo sin tocar la ventana de 7 días de la
  invitación.
- Reenvío reutiliza la misma fila (no revoca+crea otra): el uuid no es
  secreto, así que no hay ganancia de seguridad en rotarlo, y mantiene un id
  estable para la UI y el historial de auditoría.
- **Reenvío a un usuario creado por Invite que aún no confirmó**: recibe de
  nuevo la plantilla **Invite**, no Magic Link. `resolveInvitationRecipientKind`
  solo manda Magic Link a una cuenta **confirmada**. Bug encontrado en la
  auditoría: antes toda cuenta existente iba por Magic Link, y
  `signInWithOtp({shouldCreateUser:false})` falla para una cuenta sin
  confirmar ("Signups not allowed") — el reenvío a un invitado que aún no
  había hecho clic fallaba siempre. `inviteUserByEmail` sí reenvía a esa
  cuenta: mismo `auth.users.id`, sin duplicar (verificado en local). Para una
  cuenta confirmada, en cambio, `inviteUserByEmail` devuelve `email_exists`.
- Límite de 1 reenvío por minuto — ver "Concurrencia" abajo.

## Concurrencia de reenvíos

**Carrera encontrada en la auditoría**: el cooldown solo miraba
`last_sent_at`, que se fija en `mark_invitation_sent`, **fuera** de la
transacción del reenvío (después de enviar el correo). N reenvíos
simultáneos pasaban todos el chequeo y enviaban N correos (medido con
Mailpit: 2 → 2 correos, 5 → 5 correos). El conteo era veraz, pero la persona
recibía correos duplicados y probablemente solo el último enlace funcionaba.

**Solución — `last_send_attempt_at`**: `resend_organization_invitation`
toma el lock de la fila (`SELECT ... FOR UPDATE`), evalúa el cooldown dentro
del lock contra el intento más reciente y, si pasa, reserva
`last_send_attempt_at = now()` en la misma transacción. Un segundo request
concurrente espera el lock y, al continuar, relee la fila (READ COMMITTED
re-evalúa la fila bloqueada), ve el intento recién reservado y es
rechazado. `create_organization_invitation` reserva el primer intento del
mismo modo, así que un reenvío que llegue mientras el primer correo aún se
está enviando también es rechazado.

Verificado con Edge Function real + Mailpit, esperando el cooldown real
(61 s, sin tocar timestamps) y lanzando 5 reenvíos con `Promise.allSettled`:

| Caso | Éxitos | Rechazados (400 cooldown) | Correos nuevos | `send_count` | `auth.users` |
|---|---|---|---|---|---|
| Usuario existente confirmado (Magic Link) | 1 | 4 | 1 | 1 → 2 | mismo id, 1 fila |
| Usuario creado por Invite, sin confirmar (Invite) | 1 | 4 | 1 | 1 → 2 | mismo id, 1 fila |

Fallo de entrega verificado en vivo (sin `PUBLIC_APP_URL`): la creación
devuelve 502 con `invitation_id`; la fila queda `pending`, `send_count = 0`,
`last_sent_at = NULL`, `last_send_attempt_at` conservado; un reintento
inmediato devuelve 400 (cooldown) y no altera nada.

## UI — vista "Usuarios" (`#users`)

Visible solo para owner/admin de una organización que **no** es
`platform_admin` (`Sidebar.tsx`, `canViewUsers`) — nunca en el tenant de
plataforma, que sigue usando **Administración** (AdminConsole) para
gestionar otras organizaciones.

- **Miembros**: nombre, email, rol, estado, fecha de ingreso. Cambiar rol y
  activar/desactivar, con las opciones de rol filtradas según quién actúa
  (`assignableRoles` en `OrganizationUsersView.tsx`) — un admin nunca ve
  `owner` como opción. El gate real es siempre `update_organization_member`
  en el servidor; esto solo evita ofrecer un botón que el backend rechazaría.
- **Invitaciones**: email, nombre, rol, estado efectivo, enviada, vence,
  aceptada. Reenviar/cancelar solo si el estado efectivo es `pending` o
  `expired` (`isInvitationActionable`).
- **Diálogo "Invitar usuario"**: email, nombre opcional, rol — mismo filtro
  de roles asignables.

`AdminConsole` (`Crear usuario + contraseña temporal`) queda oculto en
producción (`VITE_APP_ENV === 'production'`) — ver
`docs/ADMIN_ORGANIZATION_USER_MANAGEMENT.md`.

## Ruta `/invitations/accept` y routing

- **Fuera de `ProtectedRoute`** (`App.tsx`): un usuario recién invitado tiene
  sesión válida pero cero memberships — si esta ruta estuviera protegida,
  `NoOrganizationScreen` lo bloquearía antes de poder aceptar. Funciona con o
  sin sesión.
- `resolveSafeLoginReturnTarget` (`entityNavigation.ts`) se amplió para
  aceptar **exactamente** `pathname: '/invitations/accept'` con
  `search: '?invitation=<uuid>'` — un solo parámetro, ese nombre, un uuid
  válido, nada más. Sigue rechazando cualquier otro destino (open redirect,
  `javascript:`, orígenes externos, parámetros extra).
- `ProtectedRoute` ahora conserva `location.search` (antes solo
  `pathname`/`hash`) al armar el `state.from` para el login.
- `NoOrganizationScreen` consulta `get_my_pending_invitations()` y muestra
  "Tienes una invitación pendiente · Organización · Rol" con un enlace
  directo a `/invitations/accept?invitation=<uuid>`.

## `AuthContext.refreshOrganizations`

Reutiliza el mismo `loadOrganizations` single-flight que ya protegía
`hydrateSession` contra cargas duplicadas concurrentes. Tras aceptar:
`refreshOrganizations(organization_id)` → `setCurrentOrganization(id)` →
`navigate('/')`. Sin F5.

`loadOrganizations` ahora también **descarta organizaciones
archivadas/suspendidas** de ambos arreglos (`organizations` y
`memberships`) — nunca solo de uno, para no dejar una membership huérfana
apuntando a una organización que ya no aparece. Un platform admin no se ve
afectado mientras su propia organización siga `active` (caso normal).

## Email / SMTP / configuración

- **Servicio integrado de Supabase**: solo entrega a direcciones del equipo
  del proyecto, límite de 2/hora. **No sirve para QA con usuarios externos
  reales** — se necesita SMTP propio antes de esa etapa (ver
  `docs/STAGING_DEPLOYMENT.md`).
- **`PUBLIC_APP_URL`** — nuevo secreto de Edge Function, **no**
  `VITE_PUBLIC_APP_URL`: ese es un valor del bundle del frontend, sin
  ninguna autoridad para decidir un redirect de backend con implicaciones de
  seguridad. Validado como origen puro (sin path/query/hash), `https://`
  obligatorio fuera de local, **falla cerrado** si falta o es inválido —
  nunca cae a `localhost` ni confía en `Origin`/`Referer` del request.
  Verificado en vivo: sin el secreto, `send-organization-invitation`
  devuelve 502 con `invitation_id` (para reintentar) y la fila de invitación
  queda sin tocar.
- Local: `supabase/config.toml` (`[auth]`, `[auth.email]`,
  `[auth.email.template.invite]`, `[auth.email.template.magic_link]`) +
  `supabase/templates/invite.html` / `magic_link.html`. Nunca se hizo
  `supabase config push` — Auth de staging/producción se configura
  directamente en el dashboard.

## Seguridad

- Ninguna escritura de membership/invitación pasa por PostgREST directo
  (hardening previo) — todo por estas RPC o por Edge Functions con
  `service_role`.
- `accept_organization_invitation` nunca recibe un rol del cliente.
- `get_auth_user_state_by_email`/`mark_invitation_sent`: **solo
  `service_role`**, verificado con `throws_ok(..., '42501', ...)` tanto para
  `authenticated` como para `anon`.
- `admin-create-user-and-add-member` **ya no sobrescribe la contraseña de un
  usuario existente** (era un vector real de toma de cuenta: cualquier
  platform admin podía "crear" un usuario con un email ya existente y una
  contraseña propia). Ver `docs/ADMIN_ORGANIZATION_USER_MANAGEMENT.md`.
- `admin-add-existing-member` restringida a platform admin únicamente.
- `admin-invite-organization-member` retirada (410) — solo insertaba una
  invitación sin correo ni ciclo de vida.
- Auditoría (`activity_logs`): `created`, `sent`/`resent`, `revoked`,
  `accepted`, `role_changed`, `activated`/`deactivated`,
  `created`/`reactivated` de membership. Verificado que ninguna fila
  contiene `token`/`password` (`metadata::text ILIKE '%token%'` = 0 filas).
- **Respuesta de `send-organization-invitation`**: DTO explícito
  (`toInvitationDto`), nunca la fila completa. Claves exactas: `id`,
  `organization_id`, `email`, `invited_name`, `role`, `status`,
  `effective_status`, `expires_at`, `last_sent_at`, `send_count`. Nunca
  `token_hash`, `invited_by`, `accepted_by`, `revoked_by`,
  `last_send_attempt_at`, JWT, OTP ni contraseñas. Añadir una columna a la
  tabla nunca la añade a la respuesta. `last_sent_at`/`send_count` reflejan
  el envío ya confirmado (fila devuelta por `mark_invitation_sent`).

## Pruebas

- **pgTAP** (`organization_invitations.test.sql`, **84 checks**):
  owner/admin/manager invitan (o no), cross-tenant rechazado, duplicado
  pendiente, miembro activo duplicado, vencida → reenviable, revocada → no
  reenviable/no aceptable, aceptación con rol correcto (nunca manipulable),
  doble aceptación idempotente, cuenta incorrecta, email sin confirmar,
  organización inactiva, reactivación de membership, owner inactivo
  protegido frente a un admin (crear y reenviar) y reactivable por un owner,
  auto-gestión de admin activo/inactivo bloqueada, último owner protegido,
  aislamiento de tenant en `list_organization_access`, funciones
  service-only inaccesibles, auditoría sin secretos. Intento vs. envío:
  create reserva `last_send_attempt_at` sin contar un envío; reenvío dentro
  de 60 s rechazado incluso sin envío confirmado; fallo de entrega simulado
  no altera `last_sent_at`/`send_count`; reenvío tras el cooldown permitido
  y reserva un nuevo intento; `mark_invitation_sent` es lo único que cuenta
  un envío; un envío confirmado viejo no salta un intento reciente.
  Total del proyecto: **599/599** (515 previos + 84).
- **E2E local real** (`supabase functions serve` + Mailpit, scripts
  temporales fuera del repo):
  - flujo principal (30 checks): Invite y Magic Link reales con el enlace
    extraído del correo, `verifyOtp` real, contraseña, aceptación, claves
    exactas del DTO en create y resend, cooldown, reenvío a usuario sin
    confirmar (Invite de nuevo, enlace válido), invitación revocada
    rechazada con una sesión válida;
  - concurrencia (14 checks): 5 reenvíos simultáneos por caso, ver
    "Concurrencia de reenvíos";
  - fallo de entrega y fail-closed de `PUBLIC_APP_URL` apagando el secreto.
- **Nota de entorno local**: tras `supabase db reset` con `functions serve`
  ya lanzado, Auth puede dejar de encontrar las plantillas (Kong `:8088`) y
  enviar las de fábrica. Para QA de correos: `supabase stop` →
  `supabase start` → `supabase functions serve`.
- **Build/typecheck/lint**: sin regresiones sobre el baseline (3 errores
  legacy de `Index.tsx`; 61 errores/38 warnings de lint).

## Fuera de alcance de esta fase

SCIM, SSO corporativo, provisioning de Azure AD/Google Workspace,
importación masiva, MFA obligatorio, grupos, recuperación de contraseña
("olvidé mi contraseña" — el usuario invitado la define en la aceptación,
pero no hay flujo de reset posterior todavía).
