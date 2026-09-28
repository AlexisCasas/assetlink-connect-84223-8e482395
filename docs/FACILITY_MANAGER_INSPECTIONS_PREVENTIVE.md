# Facility Manager: acceso operativo a Inspecciones y Mantenimiento preventivo (Fase 1 · Punto 9C.2)

- Migración: `supabase/migrations/20260928170418_facility_manager_inspections_preventive_access.sql`
- Pruebas: `supabase/tests/facility_manager_inspections_preventive_access.test.sql` (242 aserciones)

## Qué se abre

Esta fase vuelve efectivos solo cuatro permisos delegados:

- `inspections.view`
- `inspections.manage`
- `preventive_maintenance.view`
- `preventive_maintenance.manage`

Siguen sin abrir nada: `maintenance_notices.*`, `requests.*`, `providers.*`,
`quotes.*`, `work_orders.*`, `reports.*`, inventario y R2.

El Facility Manager no pasa a ser proveedor. Tampoco se crean membresías
ficticias suyas dentro del cliente.

La autorización usa la misma fórmula que 9C.1, a través de
`has_facility_management_operational_access_all`. Todas estas condiciones
deben cumplirse sobre una misma fila de relación:

- La relación `facility_management` está activa.
- La organización cliente y la del Facility Manager están activas.
- El usuario tiene una membresía activa en ese Facility Manager.
- Esa membresía está asignada a esa relación.
- La relación tiene todos los permisos requeridos.
- El rol interno del usuario es compatible.

No se crea un sistema de delegación paralelo.

## Matriz

Roles: o = owner, a = admin, m = manager, t = technician.

| Módulo | Acción | Permisos delegados | Roles del FM |
|---|---|---|---|
| Inspecciones | Ver plantillas, ítems, opciones, planes, alertas, ejecuciones e historial | `inspections.view` | o/a/m/t |
| Inspecciones | Planificar: plantillas, ítems, opciones, planes y alertas | `inspections.view` + `inspections.manage` | o/a/m |
| Inspecciones | Ejecutar: crear una ejecución desde un plan, responder y finalizar | `inspections.view` + `inspections.manage` | o/a/m/t |
| Preventivo | Ver fichas, planes, ciclos, medidores y lecturas | `preventive_maintenance.view` | o/a/m/t |
| Preventivo | Gestionar fichas y planes, y omitir un ciclo | `.view` + `.manage` | o/a/m |
| Preventivo | Administrar medidores: crear, corregir, retirar y reemplazar | `.view` + `.manage` | o/a/m |
| Preventivo | Registrar una lectura nueva | `.view` + `.manage` | o/a/m/t |

Un permiso `.manage` nunca sustituye al `.view` correspondiente.

El technician ejecuta, pero no planifica. En preventivo solo puede consultar y
registrar lecturas: no toca fichas ni planes, no omite ciclos y no administra
medidores.

## Backend

### Capacidades

Las capacidades son internas: no hay `EXECUTE` para PUBLIC, anon ni
authenticated. Cada una combina el acceso directo histórico, idéntico al de
antes, con la rama delegada (`OR`).

| Capacidad | Regla |
|---|---|
| `can_view_inspections` | platform admin, o miembro del cliente, o delegado con `inspections.view` (o/a/m/t) |
| `can_plan_inspections` | platform admin, o owner/admin/manager del cliente, o delegado con view + manage (o/a/m) |
| `can_execute_inspections_as_facility_manager` | Solo la rama delegada: view + manage (o/a/m/t). La ejecución directa conserva su regla dentro de cada RPC: platform admin, owner/admin/manager, o el responsable del plan o la ejecución. |
| `can_view_preventive_maintenance` | platform admin, o miembro del cliente, o delegado con `preventive_maintenance.view` (o/a/m/t) |
| `can_plan_preventive_maintenance` | `can_manage_preventive_maintenance` (directa, sin cambios), o delegado con view + manage (o/a/m) |
| `can_record_preventive_meter_reading` | `can_record_asset_meter_reading` (directa, sin cambios), o delegado con view + manage (o/a/m/t) |

### RPCs reemplazadas

Son 30 RPCs. En cada una solo cambia la línea de autorización, más las reglas
delegadas descritas en las secciones siguientes.

Cada reemplazo se generó a partir de la definición vigente (`pg_get_functiondef`)
y se verificó que coincidiera exactamente una vez. Se conservan la firma,
`SECURITY DEFINER`, el `search_path`, los grants, las validaciones, la
atomicidad y el historial.

| Categoría | RPCs |
|---|---|
| Lectura de inspecciones | `get_checklist_templates`, `get_inspection_plans`, `get_inspection_runs`, `get_inspection_run_detail`, `get_inspection_plan_alert_rules` |
| Planificación de inspecciones | `upsert_checklist_template`, `upsert_checklist_template_item`, `set_checklist_template_item_active`, `upsert_checklist_response_option`, `set_checklist_response_option_active`, `upsert_inspection_plan`, `replace_inspection_plan_alert_rules`, `upsert_inspection_plan_alert_rule`, `set_inspection_plan_alert_rule_active` |
| Ejecución de inspecciones | `create_inspection_run_from_plan`, `submit_inspection_run` |
| Lectura de preventivo | `get_maintenance_cards`, `get_preventive_maintenance_plans`, `get_preventive_maintenance_occurrences`, `get_asset_meters` |
| Gestión de preventivo | `save_maintenance_card`, `set_maintenance_card_active`, `save_preventive_maintenance_plan`, `set_preventive_maintenance_plan_active`, `skip_preventive_maintenance_occurrence`, `create_asset_meter`, `correct_asset_meter_reading`, `retire_asset_meter`, `replace_asset_meter` |
| Registro de lecturas | `record_asset_meter_reading` |
| Cruza con otro módulo; no se toca | `plan_preventive_maintenance_occurrence`, que vincula una Solicitud (9C.4) |
| Internas; sin cambios | `build_preventive_scope_snapshot`, `create_preventive_occurrence_locked`, `notify_preventive_occurrence`, triggers, `generate_*_due_notifications` |

No se tocan RLS ni policies. El frontend lee estos módulos solo por RPC, y las
tablas de inspecciones y preventivo mantienen su policy `SELECT` de miembros.

La frontera entre clientes se conserva:

- Plantillas, planes y ejecuciones se validan contra el `organization_id` de
  la RPC.
- Medidores, ocurrencias y fichas derivan su organización de la fila misma.
- Los triggers de consistencia ya existentes siguen activos.

### Directorios mínimos de referencia

Estas RPCs solo sirven al modo delegado; el acceso directo conserva su flujo
propio.

| RPC | Devuelve | Requiere |
|---|---|---|
| `get_facility_management_inspection_targets` | Sedes activas: `id`, `name`, `is_active`. Activos no archivados: `id`, `name`, `code`, `node_type`, `parent_asset_id`, `branch_id`, `status`. | `inspections.view` + `inspections.manage`, roles o/a/m (solo para planificar) |
| `get_facility_management_preventive_assets` | Activos no archivados: `id`, `name`, `code`, `status` | `preventive_maintenance.view`, roles o/a/m/t |

Ninguna de las dos devuelve el email ni el contacto de la sede, ni
`metadata`, `technical_data`, responsables, R2 o inventario.

`inspections.*` y `preventive_maintenance.*` no implican `assets.view`: no dan
acceso a la RLS de `assets` ni de `client_branches`, ni al módulo `#assets`.

## Reglas propias del modo delegado

### `responsible_member_id` pertenece al cliente

Aplica igual en inspecciones y en preventivo:

- En un plan nuevo, el FM debe enviarlo en `NULL`.
- En un plan existente, debe enviar exactamente el valor actual. No puede
  cambiarlo ni limpiarlo.
- Si no cumple, la RPC responde `42501`.
- Nunca apunta a una membresía del FM.

Las RPCs `get_assignable_technicians` y `get_assignable_planners` no se
amplían, así que el FM no recibe el roster del cliente.

En la UI, el responsable aparece como "Asignado por el cliente" y, en
inspecciones, con el `responsible_name` que ya trae el plan. No hay selector.

### El nombre del responsable nunca se deriva del email

Para el acceso directo, `responsible_name` conserva su regla de siempre: el
nombre del usuario o, si falta, la parte local de su email.

Para un Facility Manager delegado:

- `get_inspection_plans`, `get_inspection_runs` y `get_inspection_run_detail`
  devuelven solo el nombre ya guardado del usuario. Si no hay, devuelven
  `NULL`. Nunca el email ni una parte de él.
- En preventivo, el `scope_snapshot` delegado quita
  `plan.responsible.name`, porque pudo haberse derivado del email al
  capturarlo. Conserva `membership_id` y `role`, igual que
  `responsible_member_id`.
- La UI muestra "asignado por el cliente" cuando existe un responsable sin
  nombre delegable.

### Technician FM en inspecciones

No existe asignación del FM por ejecución. Su alcance operativo es estar
asignado a la relación con `inspections.view` + `inspections.manage`.

- No se compara su membresía del FM con el `responsible_member_id` del
  cliente, y la UI delegada no aplica ese filtro.
- El technician directo del cliente mantiene su regla y su filtro: solo el
  responsable del plan o de la ejecución.
- Si más adelante hiciera falta una asignación por ejecución, se modelará de
  forma explícita.

### Evidencias y R2

El flujo actual de evidencias solo guarda metadata que escribe el usuario:
`file_name`, `file_url` (un enlace), `file_path` como texto, `mime_type`,
`size_bytes` y `notes`. No hay subida de archivos y ninguna Edge Function
consume `inspection_run_evidences`.

El FM puede enviar esa misma metadata. No se amplía
`authorize_asset_file_access` ni se conceden permisos de storage: tener
`inspections.manage` no da acceso a R2.

"Crear aviso de avería" dentro de una ejecución sigue oculto en modo delegado,
porque los avisos son 9C.3.

### Solicitudes preventivas (fuera de 9C.2)

`plan_preventive_maintenance_occurrence` sigue protegida por
`can_manage_preventive_maintenance`, que es directa. En la UI delegada no se
muestra "Planificar", no se abre `PreventiveRequestDialog` y no se llama a
`persistRequest()`. El FM con permiso de gestión sí puede omitir un ciclo. La
integración con solicitudes llega en 9C.4.

Tampoco se revelan los ids de otros módulos. Para un FM delegado,
`request_creation_id`, `request_id` y `work_order_id` llegan en `NULL`, tanto
en `get_preventive_maintenance_occurrences` como en el `current_occurrence`
de `get_preventive_maintenance_plans`. El cliente directo los sigue
recibiendo.

En el frontend, `PreventiveOccurrence.request_creation_id` pasa a
`string | null`. `PreventiveRequestDialog`, que solo existe en modo directo,
exige el id no nulo mediante un type guard.

### Destinos históricos (sede inactiva o activo archivado)

Un plan de inspección puede apuntar a una sede que después se inactivó o a un
activo que se archivó. El directorio mínimo ya no los ofrece: solo lista
sedes activas y activos no archivados.

- Al editar otros campos de ese plan, el FM conserva el destino. En el
  diálogo se muestra como una opción deshabilitada "(histórico)", con el
  nombre que ya trae el plan, y se reenvía sin cambios. El backend lo
  acepta.
- El FM no puede asignar como destino nuevo una sede inactiva ni un activo o
  área archivados, ni en un plan nuevo ni cambiando uno existente. Recibe
  `22023`.
- El cliente directo conserva su semántica anterior: el backend nunca
  rechazó destinos archivados.
- En preventivo, el activo de un plan es inmutable. Si ya no está en el
  directorio, el diálogo lo muestra como "(histórico)" deshabilitado.

### Inventario y materiales

Inventario no es un permiso delegado.

**Lecturas delegadas.** `get_maintenance_cards` y el `scope_snapshot` de
ocurrencias y planes, que pasa por `sanitize_preventive_scope_snapshot`, no
devuelven `material_id`, stock ni código, nombre o estado del catálogo. Cada
línea solo indica `client_linked_material: true|false`.

**Escrituras delegadas.** `save_maintenance_card` rechaza cualquier
`material_id` distinto de `NULL` con `42501`. Además:

- Al editar una ficha, conserva intactas las líneas que el cliente vinculó a
  su catálogo.
- Solo reemplaza las líneas de descripción libre.
- Las líneas nuevas se agregan después de las vinculadas, respetando
  `(card_id, sequence)`.

**UI delegada.** No llama a `useInventoryCatalog` y no hay selector de
catálogo. Las líneas vinculadas por el cliente aparecen en solo lectura
("vinculado al inventario del cliente") y no se reenvían.

El modo directo no cambia.

## Frontend

### Contexto del cliente operado (el de 9C.1)

`FacilityManagementOperationalModule` agrega `inspections` y
`preventive-maintenance`. Se reutilizan `useFacilityManagementOperationalClients`,
`useManagedClient` y `ManagedClientGate`.

- `currentOrganization` sigue siendo el FM.
- `?managedClient=` es solo contexto visual. Un id no autorizado muestra
  "Cliente no disponible" y el módulo no se monta, así que no hay consultas.
- Si hay 0 clientes se muestra un estado vacío; con 1 se selecciona solo; con
  varios aparece un selector.
- Los clientes se filtran por el FM activo.

### Matriz frontend

La matriz vive en `src/lib/facilityManagement.ts`:

- `canFacilityManagerViewInspections`
- `canFacilityManagerManageInspections`
- `canFacilityManagerExecuteInspections`
- `canFacilityManagerViewPreventive`
- `canFacilityManagerManagePreventive`
- `canFacilityManagerRecordMeterReading`
- `canFacilityManagerManageMeters`

`canFacilityManagerOpenModule` usa un mapa por módulo. Todo esto es UX: el
backend vuelve a validar.

### Scopes

Siguen el patrón de `AssetScope`, sin duplicar vistas.

**`InspectionScope`** (`src/hooks/useInspectionScope.ts`): `canView`,
`canPlan`, `canExecute`, `runsResponsibleMemberId`, `preferRunsTab`,
`canChooseResponsible` y `draftScopeKey`.

**`PreventiveScope`** (`src/hooks/usePreventiveScope.ts`): `canView`,
`canManage`, `canRecordMeterReading`, `canManageMeters`, `canPlanRequest`
(siempre `false` en modo delegado), `canChooseResponsible` y
`canUseInventory`.

Sin scope explícito, `InspectionsView` y `PreventiveMaintenanceView` aplican
exactamente las reglas anteriores.

### Navegación

- **Sidebar del FM:** "Inspecciones de clientes" y "Preventivo de clientes"
  aparecen solo si al menos un cliente operativo cumple la capacidad de ver.
  Se eligió "Preventivo de clientes" por ser corto y seguir el patrón de
  "Activos de clientes".
- **Dashboard:** `#inspections` y `#preventive-maintenance` montan
  `DelegatedInspectionsModule` y `DelegatedPreventiveMaintenanceModule` cuando
  la organización activa es un FM. El hash directo queda protegido igual que
  el Sidebar.
- **Deep links conservados:** `inspectionPlanId`, `inspectionRunId`,
  `preventivePlanId`, `preventiveOccurrenceId` y `preventiveAssetId`.

### Ficha del activo

La pestaña "Preventivo" de `AssetDetail` vuelve a mostrarse en modo delegado,
pero con su propio permiso (`canViewPreventive` en `AssetScope`).

- "Crear plan" exige `canManagePreventive`.
- "Ver planes" y "Crear plan" conservan `managedClient`.
- Siguen ocultos: semáforo, historial integrado, avisos, reporte, QR, R2 y
  solicitudes. Mezclan módulos que aún no se delegan.

### Otros detalles

- **Borrador de plan de inspección.** Es solo UX en `sessionStorage`. Su clave
  en modo delegado es `inspection-plan-draft:fm:<FM>:<cliente>:<plan|new>`, así
  que dos FMs que operan el mismo cliente no comparten borrador. En modo
  directo la clave no cambia.
- **Solo lectura.** `InspectionRunDialog` tiene `readOnly`: con `view` sin
  `manage` una ejecución pendiente se puede ver, pero no responder. En
  preventivo, "Registrar lectura" se ofrece solo con `canRecordMeterReading`.
- **Métricas.** `PreventiveMaintenanceSummaryCard` y las métricas del
  dashboard no se extienden: no hay dashboard multi-cliente.

## Verificación

**pgTAP dedicado:** 242/242. Cubre estructura y grants, lectura, planificación
y ejecución por rol, responsable, evidencias, inventario, directorios,
aislamiento de solicitudes, entre clientes, regresión del modo directo y que
no se abran otros módulos.

**Controles negativos.** Son mutaciones temporales de las definiciones vivas.
Cada original se restauró y se verificó byte a byte.

| Control | Fallos |
|---|---|
| A. Sin el requisito de asignación | 3 |
| B. Technician habilitado para planificar inspecciones | 13 |
| C. `inspections.manage` sin `view` | 2 |
| D. Technician habilitado para planificar o administrar preventivo | 12 |
| E. `preventive_maintenance.manage` sin `view` | 2 |
| F. El FM puede cambiar `responsible_member_id` | 12 |
| G. `plan_preventive_maintenance_occurrence` abierta al FM | 3 |
| H. Inventario o `material_id` abierto al FM | 8 |
| I. Sin frontera de cliente en la ejecución de inspecciones | 5 |
| J. Sin frontera de cliente en medidores | 4 |
| K. Ids de Solicitud y OT visibles para el FM | 4 |
| L. `responsible_name` derivado del email para el FM | 4 |
| M. Sin la guarda de destino archivado o inactivo | 2 |

**Regresión completa:** 1571/1571 (1329 + 242).

**Smoke visual local.** Se corrió con Chromium headless contra el Supabase
local, con Vite forzado a la URL y la anon key locales y bloqueo de
`*.supabase.co`. Resultado: 47/47 en 9C.2, más 35/35 de la regresión de 9C.1
y 46/46 de 9B.

## Siguiente

9C.3: Avisos de avería y backlog.
