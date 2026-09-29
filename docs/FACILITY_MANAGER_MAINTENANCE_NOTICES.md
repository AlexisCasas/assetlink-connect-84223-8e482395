# Facility Manager: acceso operativo a Avisos de avería / Backlog (Fase 1 · Punto 9C.3)

- Migración: `supabase/migrations/20260928224632_facility_manager_maintenance_notices_access.sql`
- Pruebas: `supabase/tests/facility_manager_maintenance_notices_access.test.sql` (112 aserciones)

## Qué se abre

Esta fase vuelve efectivos solo tres permisos delegados:

- `maintenance_notices.view`
- `maintenance_notices.report`
- `maintenance_notices.manage`

Siguen cerrados: `providers.*`, `quotes.*`, `work_orders.*`, `reports.*`,
inventario y R2. Desde 9C.4, convertir un aviso en solicitud sí se delega (ver
`docs/FACILITY_MANAGER_REQUESTS.md`).

El Facility Manager no pasa a ser proveedor y no se crean membresías ficticias
suyas dentro del cliente. `currentOrganization` sigue siendo el FM, y
`?managedClient=` es solo contexto visual, nunca autorización.

La autorización usa la misma fórmula que en 9C.1 y 9C.2, a través de
`has_facility_management_operational_access_all`. Todas estas condiciones
deben cumplirse sobre una misma fila de relación:

- La relación `facility_management` está activa.
- La organización cliente y la del Facility Manager están activas.
- El usuario tiene una membresía activa en ese Facility Manager.
- Esa membresía está asignada a esa relación.
- La relación tiene todos los permisos requeridos.
- El rol interno del usuario es compatible.

## Matriz

| Acción | Permisos delegados | Roles del FM |
|---|---|---|
| Ver el backlog, el detalle, los filtros, los estados y los snapshots | `maintenance_notices.view` | owner, admin, manager, technician, requester, viewer |
| Reportar un aviso: manual, desde la ficha del activo o desde una no conformidad | `view` + `report` | owner, admin, manager, technician, requester |
| Gestionar: revisar, cambiar prioridad, escribir notas, descartar con motivo | `view` + `manage` | owner, admin, manager |
| Convertir en solicitud (desde 9C.4) | `view` + `manage` **y** `requests.view` + `requests.create` | owner, admin, manager |

Reglas de la matriz:

- `viewer` solo lee.
- `technician` y `requester` reportan, pero no gestionan.
- `manage` no exige `report`: un FM puede gestionar avisos existentes sin
  poder crear nuevos.
- `report` y `manage` nunca sustituyen a `view`.

El acceso directo del cliente no cambia:

- Ver: cualquier miembro activo.
- Reportar: owner, admin, manager, technician y requester.
- Gestionar y convertir: owner, admin y manager.

## Backend

### Capacidades

Son funciones internas: no hay `EXECUTE` para PUBLIC, anon ni authenticated.
Cada una combina el acceso directo, idéntico al de antes, con la rama delegada
(`OR`).

| Capacidad | Regla |
|---|---|
| `can_view_maintenance_notices` | platform admin, o miembro del cliente, o delegado con `view` |
| `can_create_maintenance_notice` | `can_report_maintenance_notice` (directa, sin cambios), o delegado con `view` + `report` |
| `can_triage_maintenance_notice` | `can_manage_maintenance_notice` (directa, sin cambios), o delegado con `view` + `manage` |
| `sanitize_maintenance_notice_for_delegate` | Minimiza la fila que devuelven `create`, `triage` y `dismiss` |

### RPCs

Se reemplazaron cuatro RPCs. Se generaron desde la definición vigente,
verificando que cada cambio coincidiera exactamente una vez. Conservan la
firma, `SECURITY DEFINER`, el `search_path` y los grants.

| RPC | Qué cambia |
|---|---|
| `get_maintenance_notices` | Autoriza con `can_view_maintenance_notices` y minimiza la respuesta delegada (ver más abajo) |
| `create_maintenance_notice` | Autoriza con `can_create_maintenance_notice`, más las reglas delegadas de inspección y de activo archivado |
| `triage_maintenance_notice` | Autoriza con `can_triage_maintenance_notice` y protege el responsable |
| `dismiss_maintenance_notice` | Autoriza con `can_triage_maintenance_notice` |

En 9C.3, `convert_maintenance_notice` **no se tocó**: la protegía solo
`can_manage_maintenance_notice`, que es directa. **Desde 9C.4** acepta además
al FM con `can_convert_maintenance_notice_as_facility_manager` (permisos de
avisos y de solicitudes). Para el FM, un borrador ajeno no existe, y la
respuesta va minimizada. Ver `docs/FACILITY_MANAGER_REQUESTS.md`.

`maintenance_notices` conserva su única policy `SELECT`, y `authenticated` no
tiene `INSERT`, `UPDATE` ni `DELETE` sobre la tabla. Todas las escrituras van
por RPC. No hay estados nuevos: siguen `open`, `triaged`, `converted` y
`dismissed`.

### Responsable del aviso

`responsible_member_id` pertenece a las membresías del CLIENTE. Un FM revisa
el aviso (prioridad y notas), pero `triage_maintenance_notice` responde `42501`
si intenta:

- asignar un responsable;
- cambiarlo;
- limpiarlo;
- apuntarlo a una membresía del FM;
- reenviar un UUID, aunque sea el mismo que ya tiene.

"No cambiar el responsable" se expresa con los parámetros de la RPC
(`NULL` y `clear = false`), sin reenviar ningún UUID. El responsable existente
se conserva.

`get_assignable_planners` no se amplía: el FM no recibe el roster del cliente.

### Aviso manual

- El correlativo `AV-*`, los snapshots del activo y la sede y el
  `organization_id` los resuelve siempre el servidor.
- `reported_by_user_id` es el `auth.uid()` real del FM. No se convierte en una
  membresía del cliente.
- El activo debe pertenecer al cliente autorizado.
- En modo delegado no se puede reportar manualmente sobre un activo archivado
  (`22023`). El selector directo tampoco ofrece activos archivados; el backend
  directo nunca los rechazó y conserva su semántica.

### Aviso desde una inspección

Con `source_type = 'inspection_run'`, el FM necesita además `inspections.view`
(`can_view_inspections`); si no, recibe `42501`. No se exige
`inspections.manage`: reportar una no conformidad no es ejecutar ni configurar
la inspección.

Se siguen validando las mismas condiciones que antes:

- la ejecución es del mismo cliente;
- la respuesta es de esa ejecución;
- la respuesta está marcada como no conformidad;
- el activo es del mismo cliente.

Nunca se crea un aviso automáticamente: siempre es una acción explícita del
usuario.

### Respuesta minimizada para el FM delegado

Para el cliente directo la respuesta es la histórica, exacta. Para un FM
delegado:

| Campo | Qué recibe el FM |
|---|---|
| `source_id` (id crudo de la ejecución) | `NULL` |
| `source_metadata` | `template_name`, `item_question` y `response_label`, sin `item_id` |
| `converted_request_id` y `converted_request_number` | `NULL` (9C.3). Se conservan `status = 'converted'` y `converted_at`. Desde 9C.4 son visibles con `requests.view`, salvo que la solicitud sea un borrador ajeno. |
| `reported_by_user_id` y `responsible_member_id` | `NULL` |
| Nombres (`reported_by`, `responsible`, `triaged_by`, `converted_by`, `dismissed_by`) | Solo el nombre guardado del usuario; si no hay, `NULL`. Nunca el email ni la parte local del email. |
| `responsible_name` sin nombre guardado | La etiqueta genérica "Asignado por el cliente" |
| `asset_current_criticality` (dato vivo de Criticidad) | Solo con `criticality.view` efectivo según la matriz 9C.1 (`can_view_criticality_matrix`); si no, `NULL`. `view` no abre el módulo #criticality. |
| Snapshots del activo y la sede, título, descripción, prioridad, estado, fechas, origen | Se conservan |

El snapshot congelado del origen forma parte del AVISO: se ve con
`maintenance_notices.view` aunque el FM ya no tenga `inspections.view`. Eso no
da acceso al módulo de Inspecciones, no expone el id de la ejecución y no
ofrece navegación hacia ella.

`create`, `triage` y `dismiss` devuelven al FM la misma fila minimizada: sin
`source_id`, `item_id`, request id ni ids de usuario o membresía.

### Directorio mínimo de activos

`maintenance_notices.report` no implica `assets.view`. Para elegir el activo
de un aviso nuevo existe
`get_facility_management_maintenance_notice_assets(client_id)`:

- **Devuelve:** `id`, `name`, `code` y `status` de los activos no archivados
  de ese cliente.
- **Requiere:** `view` + `report`, con rol owner, admin, manager, technician o
  requester.
- **Grants:** es `SECURITY DEFINER` con `search_path = ''`; `authenticated`
  tiene `EXECUTE`, PUBLIC y anon no.
- **No devuelve:** metadata, datos técnicos, imagen, QR, responsable,
  criticidad, inventario ni R2.
- **No abre:** la RLS de `assets` ni el módulo #assets.

### Notificaciones y eventos

`create` y `dismiss` siguen escribiendo sus `asset_events` y notificando a
owner, admin y manager del cliente, como antes. El FM no pasa a recibir las
notificaciones del cliente.

## Frontend

### Contexto y matriz

- `FacilityManagementOperationalModule` agrega `backlog` y reutiliza
  `ManagedClientGate`.
- Contexto canónico: `#backlog?managedClient=<cliente>`.
- Deep link a un aviso: `#backlog?notice=<aviso>&managedClient=<cliente>`.
- En modo directo se mantiene `#backlog?notice=…&org=…`. `org=` nunca se
  interpreta como cliente operado.

La matriz vive en `src/lib/facilityManagement.ts`:

- `canFacilityManagerViewMaintenanceNotices`
- `canFacilityManagerReportMaintenanceNotice`
- `canFacilityManagerManageMaintenanceNotices`

`canFacilityManagerOpenModule` incluye `backlog`. Todo esto es UX: el backend
vuelve a validar.

### Scope del backlog

`MaintenanceNoticeScope` (`src/hooks/useMaintenanceNoticeScope.ts`) tiene:
`canView`, `canReport`, `canManage`, `canConvertToRequest` (siempre `false` en
modo delegado), `canChooseResponsible`, `canViewCriticality` y
`assetDirectoryClientId`.

Sin scope explícito, `BacklogView` aplica exactamente las reglas anteriores.

### Pantallas

- **Sidebar del FM:** "Backlog de clientes" aparece solo si algún cliente
  operativo permite verlo. Dashboard monta `DelegatedBacklogModule`, así que
  el hash directo queda protegido igual.
- **Backlog delegado:**
  - "Nuevo aviso" requiere `canReport` y elige el activo del directorio
    mínimo.
  - "Revisar" y "Descartar" requieren `canManage`.
  - "Convertir en solicitud" no se mostraba en 9C.3. Desde 9C.4 aparece con
    la capacidad combinada y guarda con el transporte delegado de
    `persistRequest()`. Un aviso convertido ofrece "Ver solicitud".
  - La criticidad viva solo aparece con `canViewCriticality`.
- **Revisión:** en modo delegado no se carga `useOrganizationPlanners`. El
  responsable se muestra en solo lectura ("… — lo asigna el cliente"), y se
  editan solo la prioridad y las notas.
- **Ficha del activo:** "Crear aviso" vuelve en modo delegado cuando el FM ya
  está en la ficha (con `assets.view`) y además puede reportar. El activo
  queda fijado. Sin `assets.view` no hay ficha, pero se puede reportar desde el
  Backlog. Semáforo, historial integrado, reporte y QR siguen ocultos.
- **Ejecución de inspección:** "Crear aviso de avería" aparece en una no
  conformidad de una ejecución completada si el FM también puede reportar.
  Estar en el módulo ya implica `inspections.view`.
  - Si la ejecución tiene activo o área, se usa ese activo.
  - Si solo tiene sede, el FM elige del directorio mínimo, sin usar el árbol
    de activos del cliente.

## Verificación

**pgTAP dedicado: 112/112.** Cubre:

- estructura y grants;
- ver, reportar y gestionar, por rol;
- aviso manual y aviso desde inspección;
- responsable;
- que la conversión queda fuera;
- la minimización de la respuesta;
- criticidad;
- directorio mínimo;
- aislamiento entre clientes y entre módulos;
- regresión del modo directo.

**Controles negativos.** Son mutaciones temporales de las definiciones vivas;
cada original se restauró y verificó byte a byte.

| Control | Fallos |
|---|---|
| A. Sin el requisito de asignación | 4 |
| B. `viewer` puede reportar | 2 |
| C. `requester` puede gestionar | 1 |
| D. `report` o `manage` sin `view` | 2 |
| E. El FM puede cambiar el responsable | 4 |
| F. `convert_maintenance_notice` abierto al FM | 3 |
| G. Sin la frontera de cliente al crear | 1 |
| H. `converted_request_id` visible | 2 |
| I. `source_id` visible | 2 |
| J. Criticidad sin `criticality.view` | 1 |
| K. Aviso desde inspección sin `inspections.view` | 2 |
| L. Roster de planners abierto al FM | 2 |

**Regresión completa:** 1683/1683 (1571 + 112).

**Smoke visual local.** Se corrió con Chromium headless contra el Supabase
local, con Vite forzado a la URL y la anon key locales y bloqueo de
`*.supabase.co`. Resultado: 39/39 en 9C.3, más la regresión de 9C.2 (47/47),
9C.1 (35/35) y 9B (46/46).

## Siguiente

9C.4 (hecho): Solicitudes, que incluye convertir un aviso en solicitud y la
solicitud preventiva. Ver `docs/FACILITY_MANAGER_REQUESTS.md`.
