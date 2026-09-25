# Responsable predeterminado por activo

Fase 1 · Punto 3. Rama `feature/phase1-asset-default-responsible`. Migración
`supabase/migrations/20260926120000_asset_default_responsible.sql`. Tests:
`supabase/tests/asset_default_responsible.test.sql`.

## Qué es (y qué no es)

El **responsable predeterminado** es el responsable de **seguimiento/gestión**
del activo (ej.: Grupo electrógeno → Raúl). Se guarda en
`assets.default_responsible_member_id` (`organization_members.id`).

- **No es** el técnico de una OT, ni el creador del activo, ni quien reporta
  un aviso. Las asignaciones de técnicos de OT y
  `requests.internal_responsible_member_id` (ejecutor) no se tocan.
- **Solo owner / admin / manager** pueden ser responsable predeterminado —
  el mismo directorio que `get_assignable_planners`, el triage del backlog y
  el responsable de los planes preventivos. technician/requester/viewer no.
- **Es un valor inicial para procesos NUEVOS.** Cada proceso guarda después
  su propio responsable. **Los procesos existentes nunca se sincronizan
  automáticamente**: cambiar el responsable del activo no altera avisos,
  planes preventivos, planes de inspección ni OT ya creados.
- **No hay herencia jerárquica.** Nunca se busca responsable en
  `parent_asset_id` ni en ancestros. Cada nodo del árbol (planta, sistema,
  equipo…) es un activo y puede tener su propio responsable explícito.

## Integridad (servidor)

- FK a `organization_members(id)` **ON DELETE SET NULL** + índice. Sin
  backfill: todos los activos existentes quedaron en NULL.
- `is_eligible_follow_up_responsible(member_id, organization_id)` — única
  regla de elegibilidad: mismo tenant, `is_active`, rol owner/admin/manager.
  Helper interno, sin `EXECUTE` para `authenticated`/`anon`.
- Trigger `trg_assets_check_default_responsible` (BEFORE INSERT/UPDATE): valida
  en INSERT o cuando cambia el responsable u `organization_id`. NULL siempre
  se permite (quitar el responsable). Error genérico que no revela si un UUID
  existe en otro tenant. El CRUD de activos sigue siendo escritura directa
  bajo la RLS existente (sin cambios): el trigger protege cualquier escritor.
- **Un UPDATE que no cambia el responsable ni el tenant no lo revalida**: un
  responsable que después quedó inactivo no impide editar otros campos del
  activo (ni updates de servidor como la criticidad).

## Miembro inactivo o que dejó de ser elegible

- La referencia **se conserva** en el activo (historial); no se pone en NULL
  automáticamente.
- **Nunca se reutiliza** en procesos nuevos: los avisos lo revalidan con el
  helper y preventivo/inspecciones solo lo precargan si aparece en el
  directorio de elegibles.
- La ficha muestra **"Responsable no disponible (inactivo o ya no
  elegible)"**. Los managers comparan contra `get_assignable_planners`; el
  resto de miembros contra `get_coordination_contacts` (miembros activos),
  porque `get_assignable_planners` solo lo puede consultar owner/admin/manager.
  No se creó una RPC para recuperar nombres de miembros históricos.
- Borrar una membresía asignada pone el responsable en NULL (FK) y queda
  auditado con nombre "Miembro no disponible" — nunca hace fallar el borrado.

## Avisos de avería

`create_maintenance_notice` (misma firma) copia el responsable predeterminado
del activo a `maintenance_notices.responsible_member_id` **solo si sigue
siendo elegible**; si no, NULL. El aviso nace siempre `open` y sin `triaged_*`.
Aplica a avisos manuales y a los creados desde una inspección.

Notificación: tras `notify_role_members` (owner/admin/manager), se llama a
`notify_member` con el **mismo** `type` (`maintenance_notice_created`),
`entity_type` y `entity_id`: el índice único
`idx_organization_notifications_targeted_dedup` descarta el duplicado si ese
miembro ya fue notificado por su rol. No existe un tipo de notificación nuevo.

### Triage: "Sin asignar" ahora desasigna

`triage_maintenance_notice(p_notice_id, p_priority, p_triage_notes,
p_responsible_member_id, p_clear_responsible boolean DEFAULT false)` — la
versión de 4 argumentos se eliminó (no coexisten sobrecargas).

| Llamada | Efecto |
| --- | --- |
| `p_clear_responsible = true` | `responsible_member_id = NULL` |
| `p_responsible_member_id = UUID` | se valida (si cambia) y se asigna |
| ninguno | se conserva el actual **sin revalidarlo** |

Así un aviso cuyo responsable heredado quedó inactivo todavía puede
triagearse (prioridad/notas). En TypeScript `responsibleMemberId`:
`undefined` = conservar, `null` = desasignar, UUID = asignar; el hook calcula
`p_clear_responsible`.

## Preventivo

Solo **precarga de interfaz** para planes **nuevos**: al elegir el activo (o
al llegar desde "Crear plan" en la ficha) se propone su responsable
predeterminado si aparece en el directorio de planners elegibles. El usuario
puede conservarlo, cambiarlo o elegir "Sin asignar"; una elección manual
nunca se sobrescribe. `save_preventive_maintenance_plan` no aplica defaults
en backend (NULL sigue siendo un "Sin asignar" legítimo).

Bug preexistente corregido: `check_preventive_plan_consistency` revalidaba el
responsable en todo UPDATE, así que un plan cuyo responsable quedó inactivo
no podía desactivarse, reactivarse ni editarse. Ahora se valida solo en
INSERT o cuando cambian `responsible_member_id`/`organization_id`. Activo,
ficha, medidor, baseline y tenant se validan igual que antes.

## Inspecciones

Precarga solo para planes **nuevos** y solo cuando el usuario elige un
**`assetId` específico**. No se precarga por `branchId` ni por `areaAssetId`;
si hay varios targets y existe `assetId`, manda `assetId`. No se sobrescribe
una selección manual (incluido "Sin asignar") ni un borrador restaurado de
`sessionStorage`. Los planes existentes no cambian.

## Auditoría

Trigger `trg_assets_log_default_responsible_change` (AFTER UPDATE, solo si
`OLD.default_responsible_member_id IS DISTINCT FROM NEW...`) inserta en
`asset_events`:

- `event_type`: `asset_default_responsible_changed`
- `payload`: `previous_member_id`, `new_member_id`, `previous_name`, `new_name`
- `description`: `Responsable predeterminado: <anterior> → <nuevo>`

La resolución de nombres es best-effort (`member_display_name`): nunca hace
fallar el UPDATE. `get_asset_integrated_history` (definición más reciente,
wrapper de `20260918051511`) solo ganó la etiqueta "Responsable
predeterminado actualizado".

## Interfaz

- **AssetDetail**, lectura: nombre / "Sin responsable" / "Responsable no
  disponible (inactivo o ya no elegible)". Edición: `PlannerSelect` (con una
  opción deshabilitada para representar un valor actual que ya no es
  elegible); el campo solo se envía si cambió.
- No está en el diálogo de creación de activos en este MVP: se asigna
  editando el activo.

## Fuera de alcance

Técnicos/asignaciones de OT, `requests.internal_responsible_member_id`,
permisos de Facility Manager, múltiples responsables, herencia jerárquica,
alertas automáticas futuras y Edge Functions.
