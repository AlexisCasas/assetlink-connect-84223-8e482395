# Motor genérico de checklists e inspecciones

MVP de un motor de checklists/inspecciones reutilizable por cualquier organización cliente. **ITSE no es un módulo**: es simplemente una plantilla ("Plantilla ITSE") que una organización puede crear dentro de este motor, exactamente igual que "Inspección de techos", "Inspección gerencial", "Mantenimiento preventivo", "Auditoría interna" o "Inspección de luces de emergencia". Nada en el esquema, en las RPCs ni en el frontend hace referencia a ITSE de forma especial — cualquier mención a ITSE en este documento es solo un ejemplo de plantilla.

## Flujo

```
checklist_templates (+ items + response_options)
        │
        ▼
inspection_plans  — sede/área/activo + responsable + periodicidad + próxima inspección
        │  (Crear ejecución)
        ▼
inspection_runs   — una ejecución concreta
        │  (Guardar ejecución)
        ▼
inspection_run_answers / inspection_run_evidences — snapshot congelado
```

- **Plantilla**: nombre, descripción, categoría libre (`inspeccion`, `auditoria`, `preventivo`, `itse`, `seguridad`, `gerencial`, o cualquier otra — texto libre, nunca una lista cerrada), con ítems (preguntas) y opciones de respuesta (ej. Cumple / No cumple / No aplica).
- **Plan**: programa una plantilla contra una sede (`client_branches`), un área (`assets`, típicamente `node_type='area'`) y/o un activo específico (`assets`) — al menos uno de los tres es obligatorio. Tiene responsable, periodicidad y `next_due_at`.
- **Ejecución (run)**: se crea desde un plan (`create_inspection_run_from_plan`), copiando plantilla/objetivo/responsable. Al guardarla (`submit_inspection_run`) se congela cada respuesta y se calcula el resultado.

## Relación con sede/área/activo

- **Sede** = `client_branches` (ya existente, sin cambios).
- **Área** = una fila de `assets`, típicamente con `node_type = 'area'` — pero `upsert_inspection_plan` no obliga ese `node_type` exacto (solo exige que pertenezca a la misma organización), documentado así porque la jerarquía de `assets` ya usa varios niveles (`structure/site/area/system/fleet/equipment/component/subcomponent`) y una organización podría razonablemente programar una inspección contra cualquiera de ellos.
- **Activo** = `assets.id` directamente (típicamente `node_type='equipment'` o más específico).
- Un plan puede combinar sede + área + activo simultáneamente, o usar solo uno.

## Periodicidad y `next_due_at`

`frequency`: `one_time | daily | weekly | monthly | quarterly | semiannual | annual`.

Al guardar una ejecución (`submit_inspection_run`), si el run proviene de un plan activo, `next_due_at` de ese plan se recalcula como `completed_at + intervalo_de_frequency` (por ejemplo, `+1 month` para `monthly`). Se ancla en el momento de finalización, no en el `next_due_at` anterior, para no acumular atraso si una inspección se ejecuta tarde. Los planes `one_time` no tienen "siguiente ciclo" — su `next_due_at` no se toca.

## Resultado de una ejecución

`submit_inspection_run` exige una respuesta por cada ítem **activo y obligatorio** (`is_required = true`) de la plantilla — ni de más ni de menos, sin duplicados — antes de guardar nada. El resultado se calcula así:

```
si alguna respuesta usa una opción con is_failure = true  → failed
si no, y todas las respuestas usan value = 'not_applicable' → not_applicable
si no                                                        → passed
```

`is_failure` se marca por opción de respuesta (ej. "No cumple" = `true`). `value = 'not_applicable'` es una convención de texto (no un booleano dedicado) — al crear una opción "No aplica" para una plantilla, su `value` debe ser exactamente `not_applicable` para que el cálculo de resultado la reconozca como tal.

## Historial congelado

`inspection_run_answers` copia `item_question`/`response_label`/`response_value`/`is_failure` al momento de guardar la ejecución — nunca los vuelve a leer desde `checklist_template_items`/`checklist_template_response_options`. Editar o desactivar un ítem/opción de la plantilla **nunca** reescribe una ejecución histórica. Mismo patrón ya usado para `asset_criticality_assessment_answers`.

## Integración con el activo

Si el run tiene `asset_id`, `submit_inspection_run` inserta un `asset_events` con `event_type = 'inspection_completed'` (payload: `result`, `template_id`, `template_name`, `run_id`). `get_asset_integrated_history` ya lo muestra automáticamente (misma rama genérica `asset_event` que ya mostraba `created/updated/archived/restored/criticality_assessed`), con la etiqueta "Inspección completada".

## Evidencias

`inspection_run_evidences` es solo metadata/link (`file_name`, `file_url`, `file_path`, `mime_type`, `size_bytes`, `notes`) — **no existe upload real** en esta fase, igual que `work_order_activity_report_evidences`. El formulario de ejecución solo pide un nombre y un link opcional por ítem.

## Notificaciones in-app

`generate_inspection_due_notifications()` reutiliza los helpers de `operational_notifications` (`notify_role_members`, `notify_member`) para emitir los dos tipos ya reservados:

- `inspection_due_soon_future`: `next_due_at` dentro de los próximos 7 días.
- `inspection_overdue_future`: `next_due_at` ya pasado.

Se llama best-effort desde `useOrganizationNotifications.ts`, junto a `generate_operational_due_notifications()`. Solo in-app — sin email/WhatsApp/push, sin cron/scheduler real.

**Idempotencia por ciclo**: a diferencia de una OT (que llega a su `due_at` una sola vez), un mismo `inspection_plans.id` recorre muchos ciclos, cada uno con su propio `next_due_at`. Reutilizar `plan.id` tal cual como `entity_id` habría hecho que un plan recurrente solo reciba **una** notificación de cada tipo en toda su vida (el índice de deduplicación de `create_notification_once` no tiene dimensión de tiempo). Para evitarlo sin tocar ese helper compartido, `entity_id` aquí es `md5(plan_id || ciclo || next_due_at)::uuid` — determinístico, y distinto en cada ciclo porque cambia junto con `next_due_at`. Este id no referencia ninguna fila real (igual que el resto de `entity_id` en `organization_notifications`, sin FK).

## Permisos

- **Lectura** (plantillas, planes, ejecuciones): cualquier miembro activo de la organización, o `platform_admin`. Incluye a `technician` — necesita ver sus propias inspecciones asignadas.
- **Escritura de plantillas/ítems/opciones/planes**: solo `owner`/`admin`/`manager`, o `platform_admin`.
- **Ejecutar/guardar un run**: el propio responsable asignado (`responsible_member_id`), o `owner`/`admin`/`manager`, o `platform_admin`.
- Ninguna de las 7 tablas nuevas tiene política de `INSERT`/`UPDATE`/`DELETE` — toda escritura pasa por las RPCs `SECURITY DEFINER`. "Eliminar" una plantilla/ítem/opción/plan es siempre `is_active = false`, nunca un `DELETE` físico.
- En el frontend, "Inspecciones" es visible para `owner`/`admin`/`manager` **y** `technician` de organizaciones `client_company` (a diferencia de "Criticidad", que es solo para roles de gestión) — dentro de la vista, la gestión de plantillas/planes queda oculta para `technician` (gated por `canPlanWork`), que solo ve y ejecuta sus propias inspecciones asignadas.
- Aislamiento entre organizaciones verificado: una organización no puede leer ni escribir plantillas/planes/ejecuciones de otra.

## RPC añadida más allá de la lista original

`get_inspection_runs(p_organization_id, p_status)` no estaba en la lista original de RPCs — se añadió porque no existe otra forma limpia de listar `inspection_runs` con los nombres de plantilla/sede/área/activo/responsable ya resueltos: la tabla tiene dos FKs distintas hacia `assets` (`area_asset_id` y `asset_id`), lo que vuelve ambiguo un `select` embebido de PostgREST, y el nombre del responsable requiere un segundo join hacia `auth.users`. Mismo patrón que `get_inspection_plans`.

## Draft de "Nuevo plan de inspección"

`InspectionPlanDialog.tsx` guarda un espejo del formulario en `sessionStorage` mientras el diálogo está abierto (clave `inspection-plan-draft:{organizationId}:{planId|"new"}`), sin datos sensibles — solo la configuración del plan que ya es visible en pantalla. Se restaura al reabrir el diálogo (si no se guardó ni se canceló antes) y se limpia solo al guardar con éxito o al pulsar "Cancelar" explícitamente; cerrar con Escape o clic afuera conserva el draft. La inicialización del formulario está deliberadamente desacoplada de las props `templates`/`branches`/`assets` (que pueden llegar como un array con nueva identidad en cualquier re-render ajeno, p. ej. el refresh de token de Supabase Auth al recuperar foco) — solo se dispara en la transición cerrado→abierto o cuando cambia el `id` del plan editado, rastreado con `useRef`.

## Pendientes (fuera de alcance de este MVP)

- Plantillas predefinidas de ITSE (o de cualquier otro tipo) listas para importar.
- Generación automática de una orden de trabajo cuando una ejecución resulta `failed` — documentado como pendiente explícito en `submit_inspection_run`.
- Checklist móvil avanzado (offline, cámara integrada).
- Upload real de evidencias (hoy solo metadata/link).
- Firmas digitales de responsable/supervisor.
- Vista de calendario para planes/próximas inspecciones.
- Scheduler/cron real para `generate_inspection_due_notifications()` (hoy se dispara desde el frontend, best-effort, igual que las notificaciones operativas de OT).
