# Alertas automáticas (Fase 1 · Punto 8)

Reemplaza la generación "best-effort desde el frontend" de las alertas
dependientes del tiempo (OT próxima a vencer/vencida, inspecciones
próximas/vencidas) por generación **server-side vía `pg_cron`**, y agrega un
tercer tipo de alerta nuevo: vencimiento de mantenimiento preventivo.
Ninguna de las tres depende ya de que alguien tenga la aplicación abierta.

Rama `feature/phase1-automatic-alerts`. Migraciones:

- `supabase/migrations/20260927150951_automatic_alerts.sql` — todo el SQL
  excepto el scheduler (hardening, generadores internos, tabla de
  observabilidad, wrapper).
- `supabase/migrations/20260927150952_automatic_alerts_schedule.sql` —
  `pg_cron` (extensión + los dos `cron.schedule`).

Pruebas: `supabase/tests/automatic_alerts.test.sql` (70 aserciones).

## 1. Por qué dos migraciones separadas

`cleanup_automatic_alert_history()` (ver §5) referencia `cron.job_run_details`,
que no existe hasta que se crea la extensión `pg_cron`. Separar el SQL puro
(idempotente, sin efectos externos) del scheduler (que sí depende de que
`pg_cron` esté disponible en el proyecto) también facilita el rollback: si
algo del scheduler falla en un entorno hospedado, la primera migración
igual queda aplicada y utilizable manualmente.

## 2. Hardening de `organization_notifications`

El trigger `protect_organization_notification_update()` ya impedía cambiar
casi todas las columnas de una notificación al marcarla como leída — pero
**no** `recipient_member_id`, `priority` ni `metadata`. Verificado con una
transacción de prueba (`ROLLBACK`): un miembro común podía convertir su
propia notificación dirigida en broadcast (`recipient_member_id = NULL`,
visible a toda la organización) o alterar `priority`/`metadata` (esto
último es lo que usa la navegación del centro de notificaciones).

Dos capas, ambas necesarias (defensa en profundidad):

1. **Grant de columna** — `REVOKE UPDATE ON TABLE
   public.organization_notifications FROM authenticated;` seguido de
   `GRANT UPDATE (is_read, read_at) ON TABLE ... TO authenticated;` Un
   `UPDATE` que nombre cualquier otra columna falla con `42501` **antes**
   de que el trigger `BEFORE UPDATE` siquiera corra. Esta es la capa que
   realmente ve un cliente PostgREST real.
2. **Trigger ampliado** — `protect_organization_notification_update()`
   ahora también rechaza (`P0001`) cambios a `recipient_member_id`,
   `priority` y `metadata`. Para `authenticated` esta capa es en la
   práctica inalcanzable (el grant de columna ya bloqueó antes), pero
   sigue siendo la única barrera real para cualquier rol con un `GRANT` de
   tabla más amplio (p. ej. `postgres` en un contexto administrativo
   futuro) — es la misma filosofía "no confiar solo en `GRANT`" ya
   establecida en `docs/ORGANIZATION_ACCESS_HARDENING.md`.

Las pruebas cubren las dos capas por separado: como `postgres` (grant de
tabla completo, no `is_platform_admin()` porque no hay `auth.uid()`) se
prueba que el *trigger* rechaza con `P0001`; como `authenticated` se prueba
que el *grant* rechaza con `42501`. `is_read = true` sigue funcionando y
`read_at` se autocompleta.

## 3. `notify_member()` ahora exige membresía activa — globalmente

`notify_role_members()` ya filtraba por `om.is_active`; `notify_member()`
no lo hacía. Se corrigió para las dos funciones de la misma manera:
`SELECT ... FROM organization_members om WHERE om.id = p_member_id AND
om.is_active`. Esto se aplica a **todos** los tipos de evento existentes
(~15 funciones dependen de `notify_member`/`notify_role_members`), no solo
a las tres alertas de este punto — una membresía desactivada no debe
recibir ninguna notificación futura, sin importar el evento.

Ninguna firma cambió. `notify_member_counted`/`notify_role_members_counted`
(§4) son wrappers nuevos y separados, creados únicamente para que el
wrapper del §6 pueda contar inserciones — nunca se tocó el tipo de retorno
de las funciones originales.

## 4. Tres generadores internos

Sin `auth.uid()`, sin `GRANT` a `PUBLIC`/`anon`/`authenticated` — solo
invocables por otra función `SECURITY DEFINER` (el wrapper del §6, que
pertenece a `postgres`), igual que `create_notification_once` desde el
Punto 5.

### 4.1 `generate_operational_due_notifications_internal()`

Mismo criterio que la función pública original
(`generate_operational_due_notifications()`, ver
`docs/OPERATIONAL_NOTIFICATIONS.md`): `due_at` entre ahora y +24h →
`work_order_due_soon`; `due_at < now()` → `work_order_overdue`; excluye
`completed`/`closed`. Se agregó `JOIN organizations ... AND status =
'active'`. Destinatarios: owner/admin/manager de la organización operadora
+ técnico asignado si existe.

**Índice parcial**: `idx_work_orders_due_at_active` sobre `work_orders
(due_at) WHERE due_at IS NOT NULL AND status NOT IN ('completed',
'closed')`. Evaluado con `EXPLAIN (ANALYZE, BUFFERS)` real, no supuesto:
se insertaron 100,000 `work_orders` sintéticas (60,009 no terminales) en
una transacción descartable (`ROLLBACK`, sin tocar datos reales), con
`due_at` repartido en ±100 horas de `now()`:

| Consulta | Filas | Plan antes | Plan después | Tiempo antes | Tiempo después |
|---|---|---|---|---|---|
| due-soon (≤24h) | 7,505 (~7.5%) | Seq Scan, cost 4619 | Bitmap Heap Scan, cost 2424 | ~19.4ms | ~8.3ms |
| overdue | 30,066 (~30%) | Seq Scan, cost 3928 | Bitmap Heap Scan, cost 3044 | ~19.6ms | ~12.9ms |

Mejora real y medible en ambos casos. El índice es parcial y autoajustable:
si la proporción de OT vencidas/no-terminales creciera tanto que un Seq
Scan volviera a ser más barato, el planner simplemente dejaría de usarlo —
no hay downside por tenerlo.

### 4.2 `generate_inspection_due_notifications_internal()`

Mismo criterio que la función pública original (ver
`docs/INSPECTION_SCHEDULING_ALERTS.md`): `before_due` con múltiples
umbrales por plan, `overdue`, entidad sintética `md5(plan_id || '|' ||
rule_id || '|' || next_due_at::text)::uuid` para deduplicar por plan +
regla + ciclo. Se agregó `JOIN organizations ... AND status = 'active'`.

**`SET timezone = 'UTC'` a nivel de función.** El hash usa
`next_due_at::text`, cuyo formato de texto depende del huso horario de la
sesión que ejecuta la función. Antes de este punto no importaba porque
siempre corría con la sesión del propio usuario logueado (típicamente ya
en UTC); ahora que corre desde `pg_cron` (sesión `postgres`) y en teoría
podría invocarse manualmente desde cualquier sesión, fijarlo
explícitamente evita que el mismo evento produzca hashes distintos según
quién o qué la ejecute. **Verificado empíricamente**, no solo argumentado:
se creó un plan aislado, se llamó a la función una vez bajo `SET LOCAL
TimeZone = 'UTC'` capturando el `entity_id` resultante, se borró esa
notificación, y se volvió a llamar bajo `SET LOCAL TimeZone =
'America/Lima'` — el `entity_id` fue idéntico en ambos casos.

### 4.3 `generate_preventive_due_notifications()` — nuevo

Dos tipos nuevos: `preventive_maintenance_due` y
`preventive_maintenance_overdue`. Replica el mismo `timing_status` que ya
usa `get_preventive_maintenance_plans` (ver
`docs/PREVENTIVE_MAINTENANCE_PLANS.md`), para que la alerta nunca
contradiga lo que la UI ya muestra como "próximo"/"vencido":

- **Calendario**: `due` cuando `due_at - planning_lead_days <= now() <=
  due_at`; `overdue` cuando `now() > due_at`.
- **Medidor**: se toma la última lectura **efectiva** del medidor del plan
  (`voided_at IS NULL`, la más reciente por `recorded_at` — una corrección
  anula la lectura original e inserta otra, y este filtro sigue
  automáticamente a la vigente). `due` cuando esa lectura cae en
  `[due_meter_value - meter_lead_value, due_meter_value]`; `overdue`
  cuando la supera. Un medidor inactivo, o sin ninguna lectura efectiva,
  no genera alerta (no hay con qué evaluar la condición).

Ambos ramales excluyen: ocurrencia en estado terminal (solo se evalúan
`open`/`planned`), plan inactivo, ficha/activo archivado, organización
suspendida o archivada.

Destinatarios: `responsible_member_id` del plan (si existe y está activo,
vía `notify_member_counted`) + owner/admin/manager activos (vía
`notify_role_members_counted`). La deduplicación existente de
`organization_notifications` (índices únicos parciales por
`(organization_id, [recipient_member_id], type, entity_type, entity_id)`)
hace que un responsable que **también** es manager reciba una sola
notificación, no dos — sin necesitar lógica de deduplicación adicional en
el generador.

`entity_id = occurrence.id` (no una entidad sintética como en
inspecciones): como máximo una alerta `due` y una `overdue` por
destinatario y ocurrencia. Al completarse una ocurrencia, la siguiente
tiene su propio `id` y puede volver a alertar desde cero.

`due` usa la prioridad propia del plan (`p.priority`); `overdue` siempre
usa `'urgent'`, sin importar la prioridad configurada del plan — una
alerta vencida nunca debe verse menos urgente que una a tiempo.

Reutiliza `entity_type = 'preventive_maintenance_occurrence'`, el mismo
que ya usan `preventive_maintenance_planned/completed/skipped` — la
navegación (`notificationEntityReference` en
`src/lib/notificationLabels.ts`) no necesitó un caso nuevo.

## 5. `automatic_alert_runs` — observabilidad mínima

```sql
CREATE TABLE public.automatic_alert_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at timestamptz NOT NULL,
  finished_at timestamptz NOT NULL,
  duration_ms integer NOT NULL,
  result jsonb NOT NULL,
  had_errors boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

`RLS` habilitado sin ninguna policy (cero filas visibles salvo
`BYPASSRLS`) + `REVOKE ALL ... FROM PUBLIC, anon, authenticated` — se
consulta desde el SQL Editor o `service_role`, nunca desde el cliente.

**Qué se guarda en `result` cuando un generador falla**: únicamente
`status`, `SQLSTATE` y un mensaje truncado a 500 caracteres
(`left(SQLERRM, 500)`). **Nunca** el texto de la consulta, un stack trace,
el JWT del llamador ni ningún secreto — el wrapper (§6) construye ese
objeto a mano con exactamente esos tres campos, no vuelca ningún objeto de
error completo de Postgres.

Retención: 30 días, purgada por `cleanup_automatic_alert_history()` (§7),
un job diario separado. `cron.job_run_details` **no se limpia
automáticamente** (documentado por Supabase) y crecería sin límite, así
que la misma función también purga esa tabla a los 30 días.

## 6. `run_automatic_alert_generation()` — el wrapper

```sql
IF NOT pg_try_advisory_xact_lock(728471001) THEN
  RETURN jsonb_build_object('skipped', 'already_running');
END IF;
```

Un único scheduler (§7) lo llama cada hora. El advisory lock evita que dos
ejecuciones se solapen (dos "ticks" de cron consecutivos si uno se demora,
o una llamada manual mientras el cron corre) — la segunda no hace nada y
devuelve `{"skipped": "already_running"}` de inmediato. El lock es
transaccional (`pg_try_advisory_xact_lock`, no `pg_advisory_lock`): se
libera solo al terminar la transacción de la llamada, así que nunca puede
quedar "pegado" por una conexión que murió a medias.

**Aislamiento por generador**: cada uno corre en su propio bloque
`BEGIN ... EXCEPTION WHEN OTHERS` (equivalente a un `SAVEPOINT` implícito)
— un fallo en, por ejemplo, el generador de inspecciones **no** impide que
OT o preventivo ya hayan insertado sus notificaciones en esa misma
corrida. El resultado JSON reporta el estado de cada generador por
separado:

```json
{
  "started_at": "...", "finished_at": "...", "duration_ms": 12,
  "generators": {
    "operational": { "status": "ok", "inserted": 3 },
    "inspection": { "status": "error", "sqlstate": "42P01", "error": "..." },
    "preventive": { "status": "ok", "inserted": 0 }
  }
}
```

Nota de diseño: si un generador falla **después** de haber insertado
algunas notificaciones en esa misma corrida, `EXCEPTION WHEN OTHERS`
revierte también esas inserciones (todo el bloque `BEGIN` de ese
generador es una unidad) — el aislamiento garantizado es *entre*
generadores, no fila por fila dentro de uno. Es el comportamiento
aceptado: preferible perder una corrida completa de un generador roto
antes que dejar datos parciales de una ejecución que no terminó bien.

## 7. Scheduler — `pg_cron`, sin `pg_net` ni Edge Function

```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule('automatic-alert-generation', '5 * * * *',
  $$SELECT public.run_automatic_alert_generation();$$);

SELECT cron.schedule('automatic-alert-history-cleanup', '30 3 * * *',
  $$SELECT public.cleanup_automatic_alert_history();$$);
```

Los tres generadores son SQL puro — no necesitan salir del proceso de
Postgres, así que no hace falta `pg_net` (HTTP saliente) ni una Edge
Function. `cron.schedule` hace *upsert* por nombre de job: reaplicar esta
migración, o un futuro cambio de cadencia, reemplaza el job existente,
nunca lo duplica. Los horarios están en **UTC/GMT** (documentado por
Supabase), no en la zona horaria del navegador ni del servidor de
aplicación.

**Verificado que `pg_cron` dispara de verdad en local**, no solo que la
fila existe en `cron.job`: se reprogramó temporalmente el job a `* * * *
*`, se esperó a que el minuto cambiara, y se confirmó en
`cron.job_run_details` una fila real con `status = 'succeeded'` y su
`start_time`/`end_time`, junto con la fila correspondiente insertada en
`automatic_alert_runs` por esa ejecución. El horario se restauró a `5 * *
* *` con `supabase db reset --local` (que vuelve a aplicar la migración
desde el archivo).

En un proyecto Supabase hospedado, `pg_cron` debe estar habilitado para el
proyecto (Database → Extensions) — si el primer `db push` falla en el
`CREATE EXTENSION`, hay que habilitarla ahí antes de reintentar. Ver
checklist en `docs/STAGING_DEPLOYMENT.md`.

## 8. Cierre del rollout y hardening final

El rollout conservador de los generadores legacy quedó cerrado mediante la
migración:

`20260927171623_remove_legacy_alert_generation_access.sql`

Las funciones públicas legacy:

- `generate_operational_due_notifications()`
- `generate_inspection_due_notifications()`

ya no pueden ser ejecutadas por `PUBLIC`, `anon` ni `authenticated`.

La migración deja explícitamente `EXECUTE` únicamente para `service_role`
además del propietario de las funciones (`postgres`).

El frontend ya no depende de estos generadores: `useOrganizationNotifications.ts`
se limita a leer notificaciones y marcarlas como leídas.

La generación productiva depende exclusivamente del flujo backend:

`pg_cron`
→ `run_automatic_alert_generation()`
→ generadores internos
→ `organization_notifications`

El cierre fue verificado con una suite específica de 6 pruebas pgTAP que
comprueba:

- bloqueo real para `authenticated`;
- `service_role` conserva `EXECUTE`;
- `postgres` conserva `EXECUTE`;
- el wrapper automático continúa operativo;
- el job `automatic-alert-generation` permanece activo y apunta al wrapper.

También se verificó en producción que el cron horario ejecuta el wrapper con
`status = 'succeeded'`.

## 9. Frontend

- `useOrganizationNotifications.ts`: se eliminaron las dos llamadas
  best-effort a `supabase.rpc('generate_operational_due_notifications')` /
  `supabase.rpc('generate_inspection_due_notifications')` — el hook ahora
  es puramente de lectura y marcado como leído (`loadNotifications`,
  `markAsRead`, `markAllAsRead`). La generación corre server-side.
- `NotificationBell.tsx`/`NotificationList.tsx`: sin cambios — ya
  mostraban cualquier fila de `organization_notifications` sin importar
  quién la generó.
- `src/lib/notificationLabels.ts`: se agregaron las etiquetas de
  `preventive_maintenance_due`/`preventive_maintenance_overdue` a
  `NOTIFICATION_TYPE_LABELS` y al set de tipos operativos. La navegación
  (`notificationEntityReference`) no necesitó un caso nuevo — reutiliza el
  mapeo existente de `preventive_maintenance_occurrence`.

## 10. Verificación

- **pgTAP** (`automatic_alerts.test.sql`, 70 aserciones): fixture
  multi-tenant (2 organizaciones activas + 1 que se suspende después de
  crear su plan, porque `can_manage_preventive_maintenance` exige
  organización activa al crear); cubre OT (due-soon/overdue/terminal),
  inspecciones (umbral simple, múltiples umbrales, overdue, siguiente
  ciclo, hash estable entre husos horarios), preventivo (calendario y
  medidor, due y overdue, cada exclusión por separado: plan inactivo,
  ocurrencia terminal, activo archivado, organización suspendida,
  responsable desactivado después de la asignación, medidor inactivo,
  medidor sin lectura efectiva, lectura anulada ignorada), aislamiento
  entre tenants, deduplicación (2 corridas secuenciales), 10 conexiones
  `dblink` concurrentes reales (prueba de que no se duplica nada bajo
  concurrencia real) + una prueba determinística separada del advisory
  lock (una sesión externa lo mantiene tomado; la corrida bajo prueba
  recibe `skipped` siempre, sin depender de ningún azar de tiempo),
  aislamiento de errores por generador (se fuerza una falla real
  renombrando una tabla dentro de un `SAVEPOINT`, revertido después), las
  dos capas del hardening de `organization_notifications`, grants finales, incluyendo la revocación del acceso legacy a authenticated,
  y existencia/actividad de los dos cron jobs.
- **Control negativo** sobre el hardening: reabriendo el `GRANT UPDATE`
  general y revirtiendo el trigger a su forma anterior (sin
  `recipient_member_id`/`priority`/`metadata`), 6 de las 70 aserciones
  fallan — las que verifican precisamente esas dos capas. Las pruebas
  detectan la regresión; no pasan por construcción.
- **Robustez de la propia suite**: las conexiones `dblink` hacen su propio
  `COMMIT` real (a diferencia del resto del archivo, que vive en un único
  `BEGIN/ROLLBACK`), así que las filas que insertan en
  `automatic_alert_runs` sobreviven al `ROLLBACK` final. Corregido para
  que la sección de observabilidad mida un **delta** desde una marca de
  `clock_timestamp()`, no un conteo absoluto — verificado corriendo el
  archivo 3 veces seguidas contra la misma base local sin `db reset` de
  por medio, sin fallos.
- **`supabase db reset --local`**: ambas migraciones aplican limpio.
- **`supabase test db --local`**: 705/705 (699 previos + 6 checks del hardening final).
- `npm run build`, `npx tsc --noEmit -p tsconfig.app.json`, `npm run
  lint`, `git diff --check`: ver el reporte de cierre de esta fase para
  los números exactos.

## 11. Pendiente (documentado, no construido en esta fase)


- Email/WhatsApp/push para estas alertas — fuera de alcance, igual que en
  `docs/OPERATIONAL_NOTIFICATIONS.md`.
- Preferencias de notificación (silenciar tipos, elegir canal) — no
  implementado.
- Cadencia configurable del cron (hoy fija en el código de la migración,
  cada hora) — cambiarla requiere una nueva migración con otro
  `cron.schedule`.
