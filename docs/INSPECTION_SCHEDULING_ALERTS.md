# Programación y alertas de inspección configurables

Extiende el motor genérico de checklists/inspecciones (`docs/GENERIC_CHECKLISTS_INSPECTIONS.md`) con periodicidad personalizada y alertas configurables (ej. ITSE: avisar 90/60/30 días antes de vencer + cuando esté vencido). **ITSE sigue sin ser un módulo**: las alertas funcionan exactamente igual para cualquier plantilla del motor genérico (luces de emergencia, techos, auditoría interna, mantenimiento preventivo…) — nada en el esquema ni en las RPCs es específico de ITSE.

## Periodicidades

`inspection_plans.frequency`: `one_time | weekly | monthly | quarterly | semiannual | annual | custom`.

`daily` se mantiene como valor técnico heredado en el `CHECK` de la base de datos (por compatibilidad con cualquier fila preexistente), pero **el formulario nunca lo ofrece como opción** — no es parte de la periodicidad requerida en esta fase.

### Personalizada

`frequency = 'custom'` requiere `custom_interval` (entero > 0) y `custom_unit` (`days | weeks | months | years`). Ejemplo: "cada 45 días" = `custom_interval = 45, custom_unit = 'days'`. Para cualquier otra periodicidad, ambas columnas son `NULL` — el `CHECK` de la tabla lo exige en los dos sentidos, así que nunca queda un `custom_interval` residual pegado a una periodicidad no personalizada.

## Alertas configurables

Tabla `inspection_plan_alert_rules`, una fila por regla:

- `alert_type = 'before_due'` + `days_before >= 0` — ej. "90 días antes".
- `alert_type = 'overdue'` (sin `days_before`) — "Vencido".

Un plan puede tener múltiples reglas `before_due` (90/60/30…) y como máximo una regla `overdue` (aplicado por un índice único parcial). `replace_inspection_plan_alert_rules(p_plan_id, p_rules)` es la RPC que usa el formulario: reemplaza el conjunto completo de reglas de un plan en una sola llamada (borra las anteriores e inserta las nuevas, dentro de la misma transacción de la función) — mantiene el formulario simple, sin ida y vuelta por cada regla individual. También existen `get_inspection_plan_alert_rules`, `upsert_inspection_plan_alert_rule` y `set_inspection_plan_alert_rule_active` para gestión granular, aunque el formulario MVP solo usa el reemplazo completo.

Las reglas de un plan **no están referenciadas por ninguna otra tabla** (a diferencia de los ítems de checklist, que sí quedan congelados en `inspection_run_answers`), así que el reemplazo por borrado físico es seguro — no rompe ningún historial.

### Default sugerido para un plan nuevo

El formulario pre-llena "30 días antes" + "Vencido" al crear un plan nuevo (nunca al editar uno existente) — un punto de partida razonable que el usuario puede ajustar libremente, por ejemplo agregando 90/60/30 + Vencido para un plan tipo ITSE. Esto es una convención puramente de frontend, no un valor por defecto en la base de datos.

## Cálculo de la ventana de alerta

Para `before_due`: se notifica cuando `now() >= next_due_at - days_before días` **y** `now() < next_due_at` (todavía no venció). Para `overdue`: se notifica cuando `next_due_at < now()`. Ambos se evalúan en `generate_inspection_due_notifications_internal()` (ver Fase 1 · Punto 8, `docs/AUTOMATIC_ALERTS.md`) — copia sin `auth.uid()` de la misma lógica que la función pública original, invocada por el wrapper de `pg_cron` cada hora.

**Fijado a `TimeZone = 'UTC'` a nivel de función** (`SET timezone = 'UTC'` en la declaración de la función): el `entity_id` sintético (ver más abajo) se construye con `next_due_at::text`, cuyo formato depende del huso horario de la sesión que ejecuta la función. Antes del Punto 8 esto no importaba porque siempre corría con la sesión del propio usuario logueado; ahora que corre desde `pg_cron` (sesión `postgres`, huso `UTC` por defecto en Supabase) y también podría invocarse manualmente desde una sesión con otro huso, fijarlo explícitamente garantiza el mismo hash sin importar quién o qué la llame. Verificado empíricamente: la misma alerta produce el mismo `entity_id` bajo `TimeZone = 'UTC'` y bajo `TimeZone = 'America/Lima'`.

Es normal y esperado que, cerca de la fecha de vencimiento, varias reglas `before_due` estén simultáneamente "dentro de ventana" (ej. a 25 días de vencer, las reglas de 90/60/30 días antes están todas activas) — cada una es un umbral independiente, no una selección del "más cercano".

## Idempotencia por plan + ciclo + regla + destinatario

`create_notification_once` deduplica por `(organization_id, [recipient_member_id], type, entity_type, entity_id)`. Como un mismo plan recurre indefinidamente (cada `next_due_at` es un ciclo distinto) y ahora puede tener varias reglas activas a la vez, `entity_id` se construye como:

```
entity_id = md5(plan_id || '|' || rule_id || '|' || next_due_at)::uuid
```

- Incluir `next_due_at` asegura que cada ciclo (cada vez que `next_due_at` avanza, típicamente al completar una ejecución) obtenga su propio espacio de deduplicación — un plan recurrente no deja de notificar después del primer ciclo.
- Incluir `rule_id` asegura que dos reglas distintas del mismo plan y mismo ciclo (ej. "90 días antes" y "60 días antes") no colisionen en una sola notificación — cada una notifica independientemente, y cada una es idempotente por sí misma.
- `entity_id` no referencia ninguna fila real (igual que el resto de `entity_id` en `organization_notifications`, sin `FOREIGN KEY`).

Verificado con `psql`: llamar `generate_inspection_due_notifications()` dos veces seguidas nunca duplica — cada destinatario recibe exactamente una fila por regla y ciclo. También verificado que, tras avanzar `next_due_at` a un nuevo ciclo (por ejemplo al completar una ejecución), la misma regla vuelve a notificar sin quedar bloqueada por el ciclo anterior.

## Destinatarios

- `owner`/`admin`/`manager` de la organización — vía `notify_role_members` (una fila dirigida por cada miembro calificado, nunca un broadcast a toda la organización).
- El responsable del plan (`responsible_member_id`), si existe — vía `notify_member`.
- Ningún otro miembro (viewer, requester, técnico no responsable, etc.) recibe estas alertas.

## Tipos de notificación

Se reutilizan los dos tipos ya reservados — no se crearon tipos nuevos:

- `inspection_due_soon_future` para `before_due`.
- `inspection_overdue_future` para `overdue`.

`notificationEntityReference` en `src/lib/notificationLabels.ts` arma una referencia corta a partir de la metadata: `"Inspección: {plan} · 90 días antes"` para `before_due`, `"Inspección vencida: {plan}"` para `overdue`.

## Metadata de cada notificación

```json
{
  "plan_id": "...",
  "plan_title": "...",
  "template_name": "...",
  "next_due_at": "...",
  "alert_type": "before_due | overdue",
  "days_before": 90,
  "frequency": "custom",
  "custom_interval": 45,
  "custom_unit": "days"
}
```

`plan_title` reemplaza la clave `title` usada en la fase anterior (antes de que las alertas fueran configurables) — ver la nota en `notificationEntityReference`.

## Recalculo de `next_due_at` al completar una inspección

`submit_inspection_run` sigue anclando el nuevo `next_due_at` en `completed_at` (nunca en el `next_due_at` anterior, para no arrastrar atraso), extendido para cubrir todas las periodicidades:

```
weekly     → +7 días
monthly    → +1 mes
quarterly  → +3 meses
semiannual → +6 meses
annual     → +1 año
custom     → + custom_interval custom_unit (make_interval)
one_time   → sin siguiente ciclo (next_due_at no cambia)
```

## Scheduler — pg_cron (Fase 1 · Punto 8)

**Actualizado**: ya no depende de que alguien tenga la app abierta.
`generate_inspection_due_notifications_internal()` corre cada hora vía el
job `automatic-alert-generation` (`pg_cron`) + `run_automatic_alert_generation()`
— ver `docs/AUTOMATIC_ALERTS.md`. `useOrganizationNotifications.ts` dejó de
llamar a la función pública original.

**Deuda temporal documentada**: `generate_inspection_due_notifications()`
(la función pública original) sigue existiendo y **conserva su `GRANT
EXECUTE` a `authenticated`** — deliberadamente no revocado en la migración
del Punto 8, para no romper nada si el cron o el frontend fallaran en
producción antes de verificarse. El frontend ya no la llama. Revocar ese
grant queda para una migración exclusiva posterior — ver
`docs/AUTOMATIC_ALERTS.md`.

**Comportamiento nuevo importante**: un plan sin reglas de alerta configuradas **ya no notifica automáticamente** (la fase anterior tenía una ventana implícita fija de 7 días antes, que desapareció). Un plan creado antes de esta migración, o cualquier plan al que nunca se le hayan asignado reglas, simplemente no genera alertas hasta que alguien le configure al menos una regla desde el formulario.

## Pendientes (fuera de alcance de este MVP)

- Scheduler/cron real — resuelto en Fase 1 · Punto 8, ver `docs/AUTOMATIC_ALERTS.md`.
- Email/WhatsApp/push.
- Calendario avanzado.
- Reglas escalonadas por severidad (ej. prioridad creciente a medida que se acerca el vencimiento).
- Plantillas predefinidas de ITSE (o de cualquier otro tipo) listas para importar.
- Feriados/días hábiles en el cálculo de ventanas.
- Snooze/posponer una alerta puntual.
