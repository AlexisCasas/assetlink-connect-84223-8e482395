# Backlog de mantenimiento — Avisos de avería

> **UN AVISO NO ES UNA SOLICITUD. UN AVISO NO ES UNA OT.**

Un aviso de avería (`AV-2026-000001`) es el reporte de que algo falla, hecho
**antes** de decidir si se va a intervenir. Es el paso que hoy falta entre
"alguien nota un problema" y "existe una solicitud formal de servicio".

Por eso vive en su propio dominio, `maintenance_notices`, y **no** es un
estado de `requests`. Reutilizar `requests(status='backlog')` habría metido
en el embudo de cotizaciones/OT cosas que todavía nadie decidió atender, y
habría contaminado correlativos, notificaciones y métricas de solicitudes con
reportes que muchas veces se descartan.

Migración: `supabase/migrations/20260916120000_maintenance_backlog_notices.sql`.

## Ciclo de vida

```
        crear                revisar               convertir
  ──────────────▶ open ──────────────▶ triaged ──────────────▶ converted
                   │                     │                    (+ requests)
                   └────────┬────────────┘
                            ▼
                        dismissed  (con motivo obligatorio, nunca DELETE)
```

- `open` — reportado, sin revisar.
- `triaged` — revisado: prioridad confirmada o corregida, notas y responsable
  de seguimiento. Revisar **no** planifica nada.
- `converted` — ya generó una solicitud (`converted_request_id`). Esa
  solicitud sigue su flujo normal sin cambios: interna → OT directa,
  externa → cotizaciones → OT.
- `dismissed` — descartado con motivo en texto libre. **No hay DELETE
  funcional**: el aviso queda archivado con su motivo, su autor y su fecha.

Un aviso convertido no se puede descartar, y un descartado no se puede
convertir.

## Correlativo `AV-<año>-<6 dígitos>`

Único **por organización y año** (`UNIQUE(organization_id, notice_number)`).

No se reutilizó el patrón de `work_order_number` (`work_order_number_seq`)
porque esa secuencia es **global**: produce una sola serie compartida por
todos los tenants y no puede expresar una serie por organización.

Se usa una tabla contador con *upsert*:

```sql
INSERT INTO maintenance_notice_counters (organization_id, year, last_number)
VALUES (p_organization_id, v_year, 1)
ON CONFLICT (organization_id, year)
DO UPDATE SET last_number = mnc.last_number + 1
RETURNING mnc.last_number;
```

El `DO UPDATE` toma un lock de fila, así que dos transacciones simultáneas de
la misma organización se serializan sobre esa fila y nunca obtienen el mismo
número. Esto es justamente lo que `COUNT(*)+1` o `MAX()+1` no garantizan, y
`Date.now()` en el cliente menos todavía. La tabla contador no tiene GRANT ni
policies: solo la alcanza la RPC `SECURITY DEFINER`.

## Snapshots: qué se congela y qué no

`create_maintenance_notice` resuelve **en el servidor**, desde la base:

| Campo | Origen |
|---|---|
| `asset_name_snapshot`, `asset_code_snapshot` | fila real de `assets` |
| `asset_path_snapshot` | `resolve_asset_path()` (reutilizada, no reimplementada) |
| `branch_id_snapshot`, `branch_name_snapshot` | `resolve_asset_branch()` — la sede del activo o la del ancestro más cercano que la tenga |
| `source_metadata` | `inspection_run_answers` + `checklist_templates` |

El frontend **solo manda ids y el texto del problema**. No puede falsificar
un snapshot ni un tenant aunque lo intente.

El snapshot de sede es indispensable: con solo `assets.branch_id`, un aviso
histórico "se mudaría" de sede al mover el activo, y el backlog filtra
justamente por sede.

**La criticidad NO se congela**, a propósito: `get_maintenance_notices`
devuelve `assets.criticality` en vivo, porque en el backlog la criticidad es
contexto para priorizar hoy, no un dato histórico del aviso.

## Permisos

Dos niveles, definidos una sola vez en
`can_report_maintenance_notice` / `can_manage_maintenance_notice`, para que
las cuatro RPC no repitan la regla:

| Acción | Roles |
|---|---|
| Ver el backlog | cualquier miembro activo de la organización |
| Crear un aviso | owner, admin, manager, technician, requester (**viewer no**) |
| Revisar / descartar / convertir | owner, admin, manager |

Ambos niveles exigen además que la organización sea `client_company`: el
backlog es de quien opera los activos. Un proveedor no ve ni crea avisos.

## RLS

`maintenance_notices` tiene **solo policy de SELECT** (miembros de la
organización o platform admin) y `GRANT SELECT`. No hay policies de
INSERT/UPDATE/DELETE: toda escritura pasa por las RPC `SECURITY DEFINER`,
mismo patrón que criticidad, inventario e inspecciones. Un cliente no puede
insertar una fila con el `organization_id` de otro, ni saltarse el
correlativo, ni marcar un aviso como convertido a mano.

Consistencia de tenant reforzada por el trigger genérico
`check_asset_child_organization()` (reutilizado, no duplicado):
`organization_id` debe coincidir con el del `asset_id`.

## RPC

| RPC | Qué hace |
|---|---|
| `create_maintenance_notice(org, asset, title, description, priority, source_type, source_id, source_item_id)` | Crea el aviso, genera correlativo y snapshots, escribe `asset_events`, notifica. |
| `triage_maintenance_notice(notice, priority, notes, responsible_member)` | Revisa. Parámetros `NULL` = "no cambiar ese campo". El responsable debe ser owner/admin/manager activo del mismo tenant. |
| `dismiss_maintenance_notice(notice, reason)` | Descarta con motivo obligatorio. Idempotente: descartar dos veces no pisa el motivo original. |
| `convert_maintenance_notice(notice, request)` | Vincula el aviso con una solicitud **ya guardada**. |
| `get_maintenance_notices(org)` | Lee el backlog resolviendo nombres, número de solicitud y criticidad vigente. Orden: urgent > high > medium > low y, dentro de cada prioridad, el más antiguo primero. |

Todas llevan `GRANT EXECUTE ... TO authenticated` explícito, obligatorio desde
el hardening de `ALTER DEFAULT PRIVILEGES` (Fase 17).

### Idempotencia de la conversión

`convert_maintenance_notice` es idempotente **para el mismo par
aviso/solicitud** y sólo para ese:

- mismo `request_id` → devuelve la fila tal cual, sin error (no-op);
- `request_id` distinto → error `Este aviso ya fue convertido en otra solicitud`.

El motivo es concreto: si la solicitud se guardó bien pero la vinculación
falló por red, reintentarla tiene que funcionar, porque si no el usuario
crearía una segunda solicitud duplicada para el mismo problema. Un índice
único parcial sobre `converted_request_id` impone además 1 aviso ↔ 1
solicitud a nivel de base (consolidar varios avisos en una solicitud queda
fuera de alcance en este MVP).

La conversión también valida que la solicitud sea del **mismo tenant**, del
**mismo activo** y que no esté anulada.

## Reutilización del guardado de solicitudes

`convert_maintenance_notice` **no crea la solicitud**. El frontend usa el
mismo formulario (`OrderForm`) y la misma persistencia que el módulo de
Solicitudes, y sólo después llama a la RPC para vincular.

Esa persistencia se extrajo tal cual de `RequestList.handleSaveRequest` a
**`src/lib/requestPersistence.ts`** (`persistRequest`), que ahora es la única
implementación del flujo y la usan los dos lugares. Duplicarlo habría
significado dos copias divergiendo justo en lo delicado: la garantía de
atomicidad `draft → set_request_audience → promoción a 'sent'` (ver
`docs/REQUEST_FORM_V2_PRIVATE_INVITATIONS.md`).

Orden en `MaintenanceNoticePlanningDialog`: primero `persistRequest`, después
`convert`. Si lo segundo falla, el toast dice explícitamente que **la
solicitud sí se guardó**, para que nadie la cree de nuevo.

## Integración con activos e inspecciones

**Ficha del activo** (`AssetDetail`): botón "Crear aviso" con el activo ya
fijado. Visible para quien puede reportar; el backend revalida igual.

**Inspecciones** (`InspectionRunDialog`): en una ejecución **completada**,
**toda** respuesta guardada marcada como no conformidad ofrece "Crear aviso
de avería" — el botón nunca se oculta por falta de contexto — con la
pregunta, la respuesta y la observación precargadas.

Reglas explícitas ahí:

1. **Nunca automático.** Detectar una no conformidad y decidir reportarla son
   actos distintos; el aviso se crea sólo si alguien pulsa el botón.
2. **Nunca se inventa un activo.** El activo del aviso se resuelve con esta
   prioridad, sin inventar nada:
   1. `inspection_runs.asset_id`, si existe — se preselecciona y se
      **bloquea** (no tiene sentido reportar sobre un activo distinto al
      inspeccionado).
   2. `inspection_runs.area_asset_id`, si existe y no hay `asset_id` — es una
      fila **real** de `assets` (mismo FK y mismo guardia de organización que
      `asset_id`; `create_maintenance_notice` no restringe `node_type`), así
      que se reutiliza igual de bloqueada en vez de pedir una selección
      manual redundante.
   3. Si la ejecución sólo tiene contexto de sede (ni `asset_id` ni
      `area_asset_id`) — se abre el selector real de activos de la
      organización (`RequestAssetPicker`, el mismo de Solicitudes) y el
      activo es **obligatorio** antes de crear.

El backend no confía en el cliente: valida contra `inspection_run_answers`
que esa respuesta exista, pertenezca a la organización y sea realmente
`is_failure`, y por separado valida que el `asset_id` elegido (cualquiera de
los tres casos) sea una fila real de esa misma organización —
`create_maintenance_notice` no ata el `asset_id` del aviso al scope del run,
así que la selección manual del caso 3 no es una puerta trasera entre
tenants (checks E4–E6).

## Historial del activo

Cada acción escribe **una** fila en `asset_events`
(`maintenance_notice_created` / `_converted` / `_dismissed`), y
`get_asset_integrated_history` sólo añade tres etiquetas en español a su rama
genérica de `asset_events`.

Deliberadamente **no** se agregó una UNION que leyera `maintenance_notices`:
eso mostraría cada aviso dos veces, una por el evento y otra por la tabla.

## Notificaciones y deep link

`notify_role_members` (reutilizada) notifica a owner/admin/manager de la
organización con `type='maintenance_notice_created'`,
`entity_type='maintenance_notice'` y `entity_id` = id real del aviso. La
prioridad del aviso y la de `organization_notifications` comparten los mismos
cuatro valores, así que el mapeo es identidad.

Deep link canónico: `#backlog?notice=<uuid>&org=<uuid>`, resuelto por
`resolveNotificationTarget` en `src/lib/entityNavigation.ts` (ver
`docs/NOTIFICATION_DEEP_LINKS.md`).

**El deep link no es autorización.** Si quien hace clic no es miembro del
tenant dueño del aviso, la RLS devuelve 0 filas y el backlog muestra "no se
pudo abrir". Lo mismo vale para el ítem del sidebar: ocultarlo es cortesía
visual, no seguridad — `BacklogView` se defiende sola de un `#backlog`
directo desde una organización que no es cliente, y el backend rechaza igual.

## Archivos

| Archivo | Rol |
|---|---|
| `supabase/migrations/20260916120000_maintenance_backlog_notices.sql` | Tablas, RLS, RPC, historial |
| `src/types/maintenanceNotice.ts` | Tipos y etiquetas del dominio |
| `src/hooks/useMaintenanceNotices.ts` | Lectura + las cuatro escrituras |
| `src/lib/requestPersistence.ts` | Persistencia compartida de solicitudes |
| `src/components/backlog/BacklogView.tsx` | Vista principal, filtros, deep link |
| `src/components/backlog/MaintenanceNoticeDialog.tsx` | Crear aviso (también desde activo/inspección) |
| `src/components/backlog/MaintenanceNoticeTriageDialog.tsx` | Revisar |
| `src/components/backlog/MaintenanceNoticeDetailDialog.tsx` | Detalle + descartar |
| `src/components/backlog/MaintenanceNoticePlanningDialog.tsx` | Convertir en solicitud |
| `src/components/backlog/BacklogFilters.tsx` | Filtros |

## Verificación ejecutada

33 checks SQL contra el proyecto remoto enlazado, dentro de una transacción
con `ROLLBACK` (fixtures: Cliente A con owner/manager/technician/requester/
viewer, Cliente B, un proveedor, árbol de activos con sede heredada, una
inspección con una respuesta conforme y una no conformidad, y cuatro
solicitudes). **33/33 PASS**:

- **A** correlativo consecutivo en Cliente A y serie independiente en Cliente B;
- **B** snapshots resueltos en servidor, sede heredada del ancestro, y
  snapshot inmutable tras renombrar el activo;
- **C** Cliente B no ve avisos de Cliente A ni por SELECT directo ni por RPC;
  un proveedor no ve ni crea; un viewer del propio tenant sí lee;
- **D** viewer no crea; requester y technician sí crean pero no revisan ni
  descartan; manager revisa; el responsable debe tener rol de seguimiento;
- **E** no se puede crear un aviso desde una respuesta conforme; sí desde una
  no conformidad, con trazabilidad congelada; origen incompleto rechazado;
- **F** conversión, idempotencia del reintento, error con otra solicitud,
  rechazo de solicitud de otro activo y de otro tenant;
- **G** motivo obligatorio, descarte sin DELETE, idempotencia, y un aviso
  convertido no se puede descartar;
- **H** un evento por acción en `asset_events` y una sola fila por evento en
  el historial integrado, con etiquetas en español;
- **I** sólo owner/admin/manager reciben la notificación, con
  `entity_type='maintenance_notice'`.

3 checks adicionales (E4–E6), en una segunda transacción con `ROLLBACK`
independiente, para la resolución del activo cuando la inspección de origen
no tiene `asset_id` propio: reutilizar `area_asset_id` real sin inventar
nada, aceptar una selección manual con trazabilidad de origen intacta cuando
sólo hay sede, y rechazar esa selección manual si el activo no pertenece a
la organización. **36/36 PASS** en total.

También ejecutados: `npm run build` (OK) y
`npx tsc -p tsconfig.app.json --noEmit` (sin errores nuevos; se mantienen los
6 preexistentes del baseline).

**No ejecutado**: QA en navegador real (este entorno no tiene automatización
de navegador ni Docker para un Supabase local).
