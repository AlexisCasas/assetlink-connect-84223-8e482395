## Objetivo

Reemplazar el login simulado (localStorage) por autenticación real de Lovable Cloud (Supabase Auth) manteniendo el comportamiento de mockup: cuentas demo de un solo clic, datos sembrados, y los tres roles existentes (`cliente`, `proveedor`, `team_member`). Esto habilita cerrar las políticas RLS abiertas detectadas por el escaneo de seguridad.

## Alcance

### 1. Base de datos (migración)

- Crear enum `public.app_role` con valores `cliente`, `proveedor`, `team_member`.
- Crear tabla `public.profiles` (`id` = `auth.users.id`, `email`, `name`, `provider_id`).
- Crear tabla `public.user_roles` (`user_id`, `role`) — roles **siempre** en tabla aparte (nunca en `profiles`).
- Función `SECURITY DEFINER` `public.has_role(_user_id uuid, _role app_role)`.
- Función `SECURITY DEFINER` `public.get_user_email(_user_id uuid)` para usar en políticas (lee `auth.users.email`).
- Trigger `on_auth_user_created` que inserta en `profiles` y asigna rol por defecto desde `raw_user_meta_data`.
- RLS en `profiles` y `user_roles` (cada usuario lee lo suyo; nadie puede auto-asignarse roles).

### 2. Reemplazar políticas RLS abiertas

Sustituir todas las políticas `USING (true)` por reglas basadas en `auth.uid()` y `has_role()`:

- `requests`, `request_details`, `request_providers`: lectura pública para autenticados; insert/update/delete restringido a dueño (`created_by = email del usuario`) o a proveedores asignados.
- `quotes`, `quote_templates`, `assignments`: el proveedor solo gestiona las suyas; el cliente solo ve las de sus solicitudes.
- `chat_messages`, `request_chat_participants`: solo participantes del chat.
- `providers`, `team_members`: lectura pública autenticada; escritura solo dueño.
- `client_approved_providers`, `client_specialties`: solo el cliente dueño (`client_email = email del usuario`).
- `notifications`: solo destinatario.
- `technical_visits`, `technical_visit_documents`: cliente dueño + proveedor involucrado.
- Buckets de storage (`request-documents`, `request-images`, `request-detail-attachments`): solo autenticados; escritura restringida por carpeta-usuario.

### 3. Auth de Supabase

- Habilitar email/password con `auto_confirm_email = true` (es mockup, sin verificación de correo).
- Habilitar Google OAuth gestionado.
- Deshabilitar signup anónimo.

### 4. Refactor de `AuthContext`

- Usar `supabase.auth.signUp` / `signInWithPassword` / `signInWithOAuth` / `signOut`.
- Patrón estándar: registrar `onAuthStateChange` **antes** de `getSession()`.
- Cargar rol desde `user_roles` después de obtener sesión.
- Mantener API actual (`user`, `login`, `register`, `logout`, `isAuthenticated`) para no romper consumidores.
- Las cuentas demo (`cliente@test.com`, `proveedor@test.com`, `equipo@test.com`) se auto-registran la primera vez con su rol y datos sembrados.

### 5. Sembrado de datos demo

- Mover `initializeClientTestData` / `initializeProviderTestData` / `initializeTeamMemberTestData` a inserts en Supabase (idempotentes) en lugar de localStorage.
- Ejecutarse después del primer login de cada cuenta demo.

### 6. UI

- `Login.tsx`: añadir botón "Continuar con Google" y mantener tabs de rol solo como hint para signup (el rol real viene de `user_roles`).
- `ProviderProfile.tsx` y otros que leen `localStorage.getItem('providers')`: migrar a leer de la tabla `providers` (cambio mínimo para que no rompa).

### 7. Cerrar hallazgos de seguridad

Marcar como `mark_as_fixed` los findings de RLS abierta una vez aplicadas las políticas nuevas; actualizar `security-memory` documentando que la app es mockup pero ya usa auth real.

## Detalles técnicos

- Storage del cliente Supabase: ya configurado en `client.ts`, no tocar.
- `redirectTo` en signup/OAuth: `window.location.origin`.
- `created_by` en `requests` actualmente es `text` (email). Conservarlo y usar `auth.email()` en las políticas para evitar migración de datos.
- Para tablas que referencian `provider_id` / `team_member_id` (uuid), las políticas usarán joins vía `EXISTS (SELECT 1 FROM providers WHERE id = ... AND email = auth.email())`.

## Fuera de alcance

- Pantalla de roles administrables (vendrá después según el usuario).
- Verificación de email real, recuperación de contraseña.
- Migración de datos existentes en localStorage de los navegadores de los usuarios actuales.
