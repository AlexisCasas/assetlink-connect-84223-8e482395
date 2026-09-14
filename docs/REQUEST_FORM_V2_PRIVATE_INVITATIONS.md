# Formulario de Solicitud v2 + Invitaciones Privadas

Rama `feature/request-form-v2-private-invitations`. Migración
`supabase/migrations/20260914120000_request_form_v2_private_invitations.sql`.

No crea catálogo paralelo de proveedores ni tabla nueva de invitaciones:
reutiliza `request_provider_access` (Fase 16,
`20260721172541_provider_request_visibility.sql`) como única ACL de audiencia
privada, y `organization_relationships` + `get_provider_relationship_directory`
(Fase 18, `20260831110000_tenant_aware_provider_homologation.sql`) como único
directorio de proveedores homologados. Ambas ya existían con exactamente la
forma que esta fase necesitaba.

## Qué ya existía (y no se tocó)

- **RLS de lectura de `requests`/`quotes` para proveedores** (`can_user_read_request`,
  `can_provider_quote_request`, Fase 16/17): ya evaluaba
  `request.is_public IS TRUE OR EXISTS (request_provider_access activo)`. Una
  solicitud privada con un proveedor invitado ya era, desde antes de esta
  fase, invisible por RLS para cualquier organización sin ese acceso — este
  archivo no modifica ninguna policy ni función de esas dos migraciones.
- `request_provider_access` (id, request_id, provider_organization_id,
  access_type, status, invited_by_user_id, timestamps), con
  `UNIQUE(request_id, provider_organization_id)`.
- `organization_relationships` + `get_provider_relationship_directory`/
  `set_provider_relationship_status` (Fase 18): homologación
  cliente→proveedor ya modelada, ya consumida por
  `ApprovedProvidersList.tsx`/`useProviderRelationships.ts`.
- `organization_profiles.specialties`.

## Qué se agregó

### `requests` (columnas nuevas)

- `coordination_contact_member_id` (FK `organization_members`, nullable) +
  snapshot `coordination_contact_name`/`coordination_contact_email`: el
  contacto vive editable; el snapshot es lo que una solicitud histórica
  conserva aunque el perfil del miembro cambie después. **Sin
  `coordination_contact_phone`**: `organization_members`/`auth.users` no
  tienen ningún campo de teléfono que snapshotear — agregar la columna sin
  una fuente real habría violado la regla de no construir para escenarios
  que no pueden pasar.
- `service_address`: snapshot de `client_branches.address` al momento de
  seleccionar sucursal. `branch_id` sigue siendo la referencia viva para el
  desplegable; el texto mostrado nunca depende de ella después.
- `visit_schedule_mode` (`'scheduled' | 'to_schedule'`, nullable) +
  `visit_contact_member_id` (FK `organization_members`, nullable). CHECK
  constraint nuevo (`requests_visit_schedule_mode_check`) hace imposible el
  estado inconsistente:
  - `requires_visit = false` ⇒ `visit_schedule_mode` y `visit_date` deben ser
    `NULL`.
  - `requires_visit = true` + `scheduled` ⇒ `visit_date` obligatorio.
  - `requires_visit = true` + `to_schedule` ⇒ `visit_date` debe ser `NULL`.
  - Filas legacy se backfillean antes de agregar el CHECK (incluida una
    limpieza defensiva de `visit_date` huérfano con `requires_visit=false`).
- Trigger `trg_requests_check_contact_members` (mismo patrón que
  `check_request_internal_responsible` de Fase 15, sin la restricción de rol):
  ambos `*_member_id` nuevos deben pertenecer a la organización de la
  solicitud y estar activos.

### Activo — ruta jerárquica completa (sin columna nueva)

`RequestForm.tsx` ya calculaba `assetPath` (breadcrumb "›" completo, vía
`RequestAssetPicker`/`buildAssetPathMap`) pero solo persistía
`"<Tipo>: <Nombre>"` en el snapshot legacy `requests.asset`. Ahora persiste el
`assetPath` completo — el mismo texto que ya se le mostraba al proveedor sin
RLS sobre `assets`, ahora con la ruta completa en vez de solo tipo+nombre. No
hizo falta ninguna columna ni migración: es el mismo mecanismo de snapshot que
ya existía desde `feature/assets-requests-integration`.

### `get_coordination_contacts(p_organization_id)`

Espejo de `get_assignable_technicians` sin el filtro `role = 'technician'`:
cualquier miembro activo de la organización es un contacto de coordinación o
de visita válido. `organization_members` no tiene `name`/`email` (viven en
`auth.users`), misma razón por la que la RPC de técnicos necesita ser
`SECURITY DEFINER`.

### `set_request_audience(p_request_id, p_is_public, p_provider_organization_ids)`

Único punto de escritura transaccional para la audiencia de una solicitud
externa. El frontend sigue insertando/actualizando la fila de `requests`
directamente (sin cambios en ese flujo); esta RPC se llama justo después, y
si falla, ninguno de sus efectos internos (ACL, notificaciones, auditoría,
`is_public`) queda aplicado — todo corre dentro de la misma función
PL/pgSQL, sin puntos intermedios de confirmación desde el cliente.

En una sola llamada:

1. Valida `auth.uid()`, que la solicitud exista, que sea `request_type =
   'external'`, y que el llamante sea owner/admin/manager/requester de la
   organización dueña (o `platform_admin`) — un intento de Cliente B sobre
   una solicitud de Cliente A se rechaza aquí.
2. Si `p_is_public = false`, exige al menos un proveedor
   (`"Selecciona al menos un proveedor para enviar una invitación
   privada."`) y valida cada uno desde cero contra `organizations` +
   `organization_relationships` (nunca confía en organization_type/nombre/
   estado enviados por el frontend): debe ser una organización
   proveedora activa **y** tener `status = 'active'` (homologada) con esa
   misma organización cliente.
3. Calcula el delta contra el `request_provider_access` actual
   (`access_type = 'invited', status = 'active'`): altas y bajas.
4. Si alguna baja corresponde a un proveedor que ya tiene una cotización
   sobre esa solicitud, rechaza toda la llamada con el mensaje exacto
   pedido: *"Este proveedor ya presentó una cotización y no puede
   eliminarse de la convocatoria sin anular formalmente su participación"*
   — no se implementa anulación formal en esta fase.
5. Para cada alta: upsert en `request_provider_access`, notificación vía
   `notify_role_members` (owner/admin/manager/quote_manager del proveedor —
   mismo set de roles que ya exige `can_provider_quote_request` para
   cotizar) con `type = 'request_private_invitation'`, y una fila en
   `audit_logs`. La idempotencia de `notify_role_members`/
   `create_notification_once` (índices únicos parciales ya existentes desde
   `20260829150000_operational_notifications.sql`) garantiza que
   re-guardar la misma invitación nunca duplica la notificación — solo un
   proveedor realmente nuevo la recibe.
6. Para cada baja (sin cotización): `status = 'revoked'` (nunca `DELETE`) +
   fila en `audit_logs`.
7. Actualiza `requests.is_public` solo si cambió, con su propia fila de
   auditoría.

## Frontend

- `RequestForm.tsx`: sección **Coordinación** nueva
  (`CoordinationContactSelect.tsx` + `useCoordinationContacts.ts`,
  combobox buscable sobre `get_coordination_contacts`, con el miembro del
  propio usuario preseleccionado en una solicitud nueva) y sección
  **Convocatoria** nueva, solo para `request_type = external`
  (`RadioGroup` "Marketplace público" / "Invitación privada" +
  `RequestProviderSelector.tsx` cuando es privada). Reemplaza por completo
  el bloque muerto (`{false && (...)}`) de selección directa de proveedores
  legacy y el mock `setClientUsers(['Juan Pérez', 'María García', 'Carlos
  López', 'Ana Rodríguez'])` — el selector "Encargado" del detalle ahora usa
  el mismo directorio real de `get_coordination_contacts`.
- `RequestProviderSelector.tsx`: fuente exclusiva
  `useProviderRelationships()` (Fase 18) — nunca `provider_profiles` legacy,
  nunca email, nunca mock. Búsqueda por nombre, filtro de especialidad,
  filtro de estado, "seleccionar todos los resultados filtrados" (nunca
  automático), y solo permite marcar organizaciones con relación `active`;
  el resto se muestra deshabilitado con su estado real
  (pendiente/inactivo/finalizado/disponible).
- `RequestList.tsx`: `handleSaveRequest` persiste las columnas nuevas y
  llama `set_request_audience` después del insert/update de `requests`
  (solo para `external`); `handleEditRequest` carga la audiencia actual
  desde `request_provider_access` para precargar el selector.
- `ProviderRequestList.tsx`: nueva columna/badge "Invitación privada" vs
  "Marketplace" (`isPrivateInvitation`, derivado del mismo
  `request_provider_access` que ya se consultaba para filtrar visibilidad —
  ninguna consulta nueva).

## Reglas de edición de destinatarios (Bloque G)

Sin distinción especial de código entre "borrador" y "enviada sin
cotizaciones": `set_request_audience` siempre calcula el delta contra el
estado real de `request_provider_access` y siempre bloquea la baja de un
proveedor con cotización existente — en un borrador nunca hay cotizaciones
todavía, así que la regla más estricta ya cubre ambos casos sin
bifurcación.

## Atomicidad request + audiencia (hallazgo corregido)

Auditoría posterior encontró que `RequestList.tsx` escribía `status`/
`is_public` en la fila de `requests` **antes** de llamar
`set_request_audience`: si esa RPC fallaba (relación revocada entre carga y
envío, error de red, etc.), la solicitud podía quedar observada como
`request_type=external`, `status='sent'`, `is_public=false` y **0** filas en
`request_provider_access` — exactamente el estado prohibido.

Corregido sin tocar la RPC ni reconstruir el guardado: toda transición hacia
`sent` ahora escribe primero `status='draft'` (invisible para cualquier
proveedor sea cual sea `is_public`, igual que hoy) y solo se promueve a
`sent` en un paso final, después de que `set_request_audience` ya haya
confirmado éxito. Si esa RPC lanza una excepción, la promoción nunca ocurre
y la solicitud queda como borrador editable normal. `is_public` dejó de
escribirse desde el insert/update directo — `set_request_audience` es ahora
su único escritor.

## Pruebas reales de RLS (ejecutadas contra el proyecto Supabase enlazado)

Ejecutadas el 2026-09-14 vía `supabase db query --linked -f <script>.sql`,
dentro de una única transacción con `ROLLBACK` final — cero filas
persistidas (verificado por conteo posterior de las organizaciones/usuarios/
solicitudes/cotizaciones `ZZTEST*`, todas en 0). Fixture: Cliente A, Cliente
B, Proveedor X (homologado A y B), Proveedor Y (homologado A), Proveedor Z
(NO homologado A inicialmente). Resultado de los 20 checks: **todos PASS**,
incluyendo el caso bloqueante:

- Proveedor Z, `SELECT * FROM requests WHERE id = '<SOL-PRIVATE-TEST>'` → **0 filas**.
- Proveedor Z, `can_provider_quote_request(...)` → **false**; intento de
  `INSERT` directo en `quotes` → rechazado por RLS
  (`new row violates row-level security policy for table "quotes"`).
- Proveedores X/Y → 1 fila visible, `can_provider_quote_request` → true.
- Cliente B → 0 filas; `set_request_audience` sobre la solicitud de Cliente A
  → rechazado (`Not authorized to manage this request's audience`).
- Re-guardar X+Y → sin duplicar `request_provider_access` ni notificaciones.
- Homologar y agregar Z → solo Z recibe fila de acceso y notificación nueva.
- X con cotización existente → intento de audiencia sin X rechazado
  (`Este proveedor ya presentó una cotización...`), X conserva su acceso
  `active` sin cambios.

## Fuera de alcance (sin construir)

Email/WhatsApp/push, visita técnica completa (check-in, DNI, SST,
reprogramación, evidencia), anulación formal de la participación de un
proveedor, transición post-envío interna↔externa, chat, Cloudflare/PDF/TDR,
matching automático por IA — igual que las fases anteriores del proyecto.
