# Notificaciones operativas in-app

Amplía el centro de notificaciones ya existente
(`organization_notifications` + `NotificationBell.tsx`/`NotificationList.tsx`/
`useOrganizationNotifications.ts`) con 7 eventos operativos nuevos. **No se
construyó ningún sistema paralelo**: se extendió la misma tabla, el mismo
hook, los mismos componentes que ya mostraban las notificaciones de
cotizaciones desde una fase muy anterior.

## 1. Alcance — solo in-app

Explícitamente fuera de esta fase: email, WhatsApp, push, cualquier canal
externo, preferencias de notificación por usuario, plantillas multi-canal,
colas de envío externas. Todo lo que existe hoy vive en
`organization_notifications` y se muestra dentro de la propia app.

## 2. El modelo existente — qué se reutilizó y qué se extendió

`organization_notifications` (creada en
`20260721184404_quote_notifications_tenant_flow.sql`, usada desde entonces
para `quote_submitted`/`quote_approved`/`quote_rejected` y el
`work_order_created` original) ya tenía exactamente la forma que pedía la
tarea: `organization_id`, `actor_user_id`, `type`, `title`, `message`,
`entity_type`/`entity_id` (equivalente directo a "source_table"/"source_id"
— se reutilizaron esos nombres en vez de duplicar el concepto con uno
nuevo), `is_read`/`read_at`, `created_at`.

Lo único que faltaba, agregado en `20260829150000_operational_notifications.sql`:

- **`recipient_member_id`** (nullable, `references organization_members`):
  `NULL` sigue significando exactamente lo mismo que significaba antes de
  esta fase — "notificación de toda la organización", el comportamiento
  original de cotizaciones queda intacto sin tocar ni una fila existente.
  Un valor no nulo dirige la notificación a un miembro específico
  (técnico asignado, planner puntual, etc.).
- **`priority`** (`low`/`medium`/`high`/`urgent`, default `medium`).
- **`metadata`** (`jsonb`, default `{}`) — datos específicos del evento
  (ej. `work_order_number`) para que la UI arme una referencia textual sin
  tener que volver a consultar la OT/solicitud.

## 3. Cómo se evitan duplicados

Dos índices únicos parciales — uno no basta, porque `NULL` nunca es igual
a `NULL` para efectos de unicidad, así que un solo índice que incluya
`recipient_member_id` dejaría duplicarse libremente a las notificaciones
de toda-la-organización (`recipient_member_id IS NULL`):

```sql
-- Broadcasts (toda la organización)
UNIQUE (organization_id, type, entity_type, entity_id) WHERE recipient_member_id IS NULL AND entity_id IS NOT NULL

-- Dirigidas a un miembro específico
UNIQUE (organization_id, recipient_member_id, type, entity_type, entity_id) WHERE recipient_member_id IS NOT NULL AND entity_id IS NOT NULL
```

`create_notification_once(...)` es el único punto de inserción real —
elige cuál de los dos índices aplica según si `p_recipient_member_id` es
`NULL`, e inserta con `ON CONFLICT ... DO NOTHING` contra el índice
correcto. Toda notificación operativa de esta fase pasa por ahí (directo,
o indirecto vía `notify_role_members`/`notify_member`).

**Verificado end-to-end** (vía `psql`): llamar `generate_operational_due_notifications()`
dos veces seguidas sobre la misma OT vencida/próxima a vencer produce
exactamente las mismas filas la segunda vez — cero duplicados.

## 4. Eventos cubiertos y destinatarios

| # | Evento | `type` | Destinatarios | Disparado desde |
|---|---|---|---|---|
| 1 | Nueva solicitud interna | `internal_request_created` | owner/admin/manager de la organización solicitante | Trigger `trg_notify_internal_request_created` en `requests` (INSERT o UPDATE de `status` a `'sent'`) — las solicitudes se insertan directo desde el frontend, sin RPC de creación, así que no había una función existente para extender |
| 2 | Nueva OT | `work_order_created` | owner/admin/manager de la organización operadora | `create_work_order_from_quote` (externa) y `create_internal_work_order_from_request` (interna) |
| 3 | Técnico asignado | `technician_assigned` | el técnico asignado, solo si cambió (nunca el técnico anterior) | `create_internal_work_order_from_request` (si ya trae técnico al crear), `update_work_order_operations`, `assign_work_order_technician` |
| 4 | Actividad asignada | `activity_assigned` | cada técnico del set final de `work_order_activity_technicians` | `upsert_work_order_activity` — idempotente por `activity_id` + `member_id`, así que un técnico ya notificado para esa actividad no vuelve a notificarse en un guardado posterior, sin necesidad de comparar el set viejo contra el nuevo a mano |
| 5 | OT próxima a vencer | `work_order_due_soon` | owner/admin/manager de la organización operadora + técnico principal si existe | `generate_operational_due_notifications()` |
| 6 | OT vencida | `work_order_overdue` | igual que la anterior | `generate_operational_due_notifications()` |
| 7 | Trabajo completado | `work_completed` | owner/admin/manager de la organización operadora | `technician_update_work_order_progress` (OT completa) y `submit_activity_report` (actividad individual) — dos eventos distintos, ambos válidos |
| 8/9 | Inspección próxima/vencida | `inspection_due_soon_future` / `inspection_overdue_future` | — | **No implementado.** Reservados en el vocabulario de tipos (`src/lib/notificationLabels.ts`), documentados, sin tabla de inspecciones ni lógica alguna — ver §7 |

**Decisión deliberada sobre `work_order_created` (externa)**: la llamada
existente en `create_work_order_from_quote` era un broadcast a *toda* la
organización proveedora (`create_organization_notification`, sin
destinatario). Se reemplazó por `notify_role_members(...,
['owner','admin','manager'], ...)` para cumplir la regla explícita de esta
fase ("no notificar a todos los viewers/requesters si no corresponde") —
el único cambio de comportamiento en una función ya desplegada, hecho a
propósito y documentado aquí.

**Por qué targeted, no broadcast, para "no notificar a todos"**: una fila
`recipient_member_id IS NULL` es visible por RLS a *cualquier* miembro
activo de la organización, sin importar su rol — technician, viewer,
requester incluidos. Por eso `notify_role_members` no inserta una sola
fila de broadcast: inserta una fila **por cada miembro calificado**
(owner/admin/manager activos), cada una dirigida (`recipient_member_id`
= ese miembro), para que RLS la oculte correctamente de cualquier otro
rol de la misma organización.

## 5. `generate_operational_due_notifications()` — superado por pg_cron (Fase 1 · Punto 8)

**Actualizado en Fase 1 · Punto 8** (ver `docs/AUTOMATIC_ALERTS.md`): la
generación de `work_order_due_soon`/`work_order_overdue` ya no depende de
que alguien tenga la app abierta. Un job `pg_cron` (`automatic-alert-generation`,
cada hora) llama a `generate_operational_due_notifications_internal()` —una
copia sin `auth.uid()` del mismo criterio, invocable solo por el wrapper—
a través de `run_automatic_alert_generation()`. El frontend
(`useOrganizationNotifications.ts`) dejó de llamar a la función pública.

Ventana: `due_at` entre ahora y +24 horas → `work_order_due_soon`;
`due_at < ahora` → `work_order_overdue`. Ambas excluyen OT en estado
`completed`/`closed`, y ahora además exigen organización activa y
destinatario activo. Idempotente por diseño (§3) — correr el generador con
la frecuencia que sea nunca duplica.

**Cierre del rollout**:
`generate_operational_due_notifications()` se conserva como función legacy por
compatibilidad interna, pero la migración
`20260927171623_remove_legacy_alert_generation_access.sql` revoca su `EXECUTE`
a `PUBLIC`, `anon` y `authenticated`.

El frontend ya no la invoca. La generación temporal de alertas de OT se ejecuta
server-side mediante `run_automatic_alert_generation()` desde `pg_cron`.

`service_role` y el propietario de la función conservan la capacidad de
ejecución necesaria para operaciones backend.

## 6. Seguridad

- `create_notification_once`/`notify_role_members`/`notify_member`:
  **no otorgadas a `authenticated`** (mismo patrón que la
  `create_organization_notification` preexistente) — toman
  título/mensaje/destinatario como texto libre; exponerlas directo
  permitiría a cualquier usuario autenticado fabricar notificaciones
  arbitrarias dirigidas a cualquier miembro. Solo invocables desde otras
  funciones `SECURITY DEFINER` (mismo mecanismo de "el dueño de la
  función siempre puede ejecutar lo que posee", usado también para
  `resolve_asset_path`).
- `generate_operational_due_notifications()`: sí otorgada a
  `authenticated` — no toma ninguna entrada libre (ningún
  título/mensaje/destinatario que el llamador controle), solo escanea
  las OT reales y notifica a sus destinatarios *correctos* según su
  propia organización; no hay forma de abusarla para notificar a alguien
  incorrecto.
- RLS de `organization_notifications` (`SELECT` y `UPDATE`) reemplazada
  para exigir, además de pertenecer a la organización,
  `recipient_member_id IS NULL` (broadcast) **o** que el llamador *sea*
  ese miembro. **Verificado end-to-end** con `SET ROLE authenticated` (no
  el superusuario, que ignora RLS): César solo ve su propia notificación
  de "técnico asignado", Alexis solo ve las suyas propias, y un owner de
  una organización sin relación no ve ninguna.
- Todas las funciones nuevas/modificadas: alias corto por tabla desde la
  primera línea (`n`/`om`/`au`/`r`/`wo`/`woa`/`woat`/`woar`), parámetros
  `p_`, variables `v_` — mismo estándar que dejó establecido
  `20260827170000_fix_work_order_activities_rpc_ambiguity.sql`.
- Ninguna de las siete funciones RPC modificadas cambió de firma (mismos
  parámetros, mismos nombres) — todas se reemplazaron con `CREATE OR
  REPLACE FUNCTION` simple, sin necesitar `DROP FUNCTION`.

## 7. Frontend

- `src/lib/notificationLabels.ts`: labels de `type`/`priority`, filtro
  "es operativa", y `notificationEntityReference` (texto tipo "OT:
  OT-2026-000001" a partir de `entity_type` + `metadata` — referencia
  textual, no un link real todavía).
- `useOrganizationNotifications.ts`: **sin cambios en su API pública** —
  `notifications`/`unreadCount`/`markAsRead`/`markAllAsRead` ya
  funcionaban correctamente para el modelo nuevo sin tocarlos (la
  consulta sigue siendo por `organization_id`; RLS ya filtra por
  destinatario de forma transparente). Desde Fase 1 · Punto 8 es un hook
  de solo lectura/marcado — ya no dispara ninguna generación de alertas
  (eso corre server-side vía `pg_cron`, ver §5 y `docs/AUTOMATIC_ALERTS.md`).
- `NotificationList.tsx`: badge de prioridad, referencia textual a la
  entidad, filtro "Todas" / "Operativas" (cliente-side, sobre los datos ya
  cargados — sin nueva consulta).
- `NotificationBell.tsx`: mismo badge de prioridad y referencia, versión
  compacta para el dropdown del Sidebar. El contador `unreadCount` ya
  existía y sigue funcionando sin cambios — ahora también refleja las
  notificaciones operativas dirigidas al usuario actual.

## 8. Cómo probar manualmente

1. Como planner/admin, crear una solicitud interna → confirmar
   "Nueva solicitud interna".
2. Generar la OT → confirmar "Nueva orden de trabajo".
3. Asignar a César como técnico → cerrar sesión, entrar como César →
   confirmar "Te asignaron una orden de trabajo" (y que Alexis no la ve
   en su propio centro).
4. Asignar una actividad a César → confirmar "Te asignaron una
   actividad".
5. Editar la OT con `due_at` dentro de 24h, abrir el centro de
   notificaciones o el Dashboard → confirmar "OT próxima a vencer" tanto
   para el planner como para César.
6. Editar la OT con `due_at` en el pasado → confirmar "OT vencida".
7. César finaliza la actividad/OT → confirmar que el planner recibe
   "Trabajo completado".
8. Marcar notificaciones como leídas, cerrar sesión y volver a entrar →
   confirmar que el estado leído/no leído persiste.
9. Repetir la generación de vencimientos (recargar el Dashboard varias
   veces) → confirmar que no se duplican notificaciones.

## 9. Validaciones ejecutadas

- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores.
- Smoke test manual completo vía `psql` (bypaseando auth con
  `request.jwt.claim.sub`, y verificando RLS real con `SET ROLE
  authenticated`, no como superusuario): los 7 eventos disparados en
  secuencia con los destinatarios correctos, visibilidad
  correctamente aislada por destinatario y por organización, y ninguna
  duplicación al repetir `generate_operational_due_notifications()`.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; `organization_notifications` (columnas nuevas) y
  `generate_operational_due_notifications` presentes con sus tipos.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- `npx tsc -p tsconfig.app.json --noEmit`: mismos errores preexistentes ya
  documentados en fases anteriores, ningún error nuevo.

## 10. Pendiente (documentado, no construido en esta fase)

- **Email, WhatsApp, push, cualquier canal externo** — fuera de alcance
  explícito de esta fase.
- **Scheduler/cron real** — resuelto en Fase 1 · Punto 8, ver
  `docs/AUTOMATIC_ALERTS.md`.
- **Preferencias de notificación** (silenciar tipos, elegir canal, etc.)
  — no implementado.
- **Inspecciones próximas/vencidas** — implementado en Fase 1 · Punto 8
  (`inspection_due_soon_future`/`inspection_overdue_future`), ver
  `docs/INSPECTION_SCHEDULING_ALERTS.md` y `docs/AUTOMATIC_ALERTS.md`.
**Cierre del rollout**:
`generate_operational_due_notifications()` se conserva como función legacy por
compatibilidad interna, pero la migración
`20260927171623_remove_legacy_alert_generation_access.sql` revoca su `EXECUTE`
a `PUBLIC`, `anon` y `authenticated`.

El frontend ya no la invoca. La generación temporal de alertas de OT se ejecuta
server-side mediante `run_automatic_alert_generation()` desde `pg_cron`.

`service_role` y el propietario de la función conservan la capacidad de
ejecución necesaria para operaciones backend.