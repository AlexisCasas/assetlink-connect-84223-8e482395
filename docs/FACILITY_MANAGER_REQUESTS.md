# Facility Manager: Solicitudes (Fase 1 · Punto 9C.4)

Migración: `supabase/migrations/20260929000641_facility_manager_requests_access.sql`.
Tests: `supabase/tests/facility_manager_requests_access.test.sql`.

## Alcance

9C.4 hace efectivos para un Facility Manager (FM) solo estos permisos:

- `requests.view`
- `requests.create`
- `requests.manage`

Además integra dos flujos que cruzan módulos:

- Aviso de avería → Solicitud.
- Ocurrencia de mantenimiento preventivo → Solicitud.

Siguen cerrados: `quotes.*`, `work_orders.*`, `reports.*`, `providers.manage`,
inventario y R2. El FM nunca es provider-facing y no se crean membresías
ficticias suyas dentro del cliente. `currentOrganization` sigue siendo el FM, y
`?managedClient=` es solo contexto visual, nunca autorización.

El acceso delegado usa el helper de 9C.1
`has_facility_management_operational_access_all`. Exige:

- relación `facility_management` activa;
- cliente y FM activos;
- membresía activa del usuario en ese FM, asignada a esa relación;
- todos los permisos pedidos en esa relación;
- un rol compatible.

## Matriz del FM

| Capacidad | Permisos | Roles del FM |
|---|---|---|
| Ver solicitudes enviadas y su detalle | `requests.view` | owner, admin, manager, requester |
| Crear solicitudes; editar, enviar, eliminar y definir la audiencia de sus **propios** borradores | `view` + `create` | owner, admin, manager, requester |
| Editar y anular solicitudes enviadas (`sent`, `quoted`), incluida la audiencia | `view` + `manage` | owner, admin, manager |
| Convertir un aviso en solicitud | `maintenance_notices.view` + `manage` **y** `requests.view` + `create` | owner, admin, manager |
| Planificar una ocurrencia preventiva en una solicitud | `preventive_maintenance.view` + `manage` **y** `requests.view` + `create` | owner, admin, manager |

Reglas de la matriz:

- `technician`, `viewer`, `quote_manager` y `operator` no ven solicitudes.
- `manage` no exige `create`, y ninguno de los dos sustituye a `view`.
- Un FM solo ve borradores propios. Los borradores del cliente, o los de otro
  usuario del FM, no existen para él.
- Cotizaciones y "Generar OT" nunca se delegan.

El acceso directo del cliente no cambia.

## Backend

### Qué no cambia

- `can_user_read_request`, la RLS y las policies de `requests`,
  `request_details` y `request_provider_access`. La RLS de solicitudes nunca se
  abre al FM.
- Los roster del cliente: `get_coordination_contacts`,
  `get_assignable_technicians` y `get_assignable_planners`.
- `create_internal_work_order_from_request` y
  `get_provider_relationship_directory`.
- El trigger `notify_internal_request_created`.

### Capacidades internas

Estas funciones no son ejecutables por `anon` ni por `authenticated`:

| Función | Qué valida |
|---|---|
| `can_view_requests_as_facility_manager` | `requests.view`, roles o/a/m/requester |
| `can_create_requests_as_facility_manager` | `view` + `create`, roles o/a/m/requester |
| `can_manage_requests_as_facility_manager` | `view` + `manage`, roles o/a/m |
| `can_convert_maintenance_notice_as_facility_manager` | los cuatro permisos de aviso y solicitud, roles o/a/m |
| `can_plan_preventive_request_as_facility_manager` | los cuatro permisos de preventivo y solicitud, roles o/a/m |

También son internas las funciones de minimización:

- `facility_management_safe_person_name`;
- `facility_management_request_payload`;
- `facility_management_can_see_request`;
- `sanitize_preventive_occurrence_for_delegate`;
- `sanitize_maintenance_notice_for_delegate`, ya existente desde 9C.3.

### RPCs delegadas

Todas son `SECURITY DEFINER` con `search_path` vacío. `authenticated` puede
ejecutarlas y `anon` no. Cada una vuelve a autorizar contra el cliente que
recibe.

| RPC | Qué hace |
|---|---|
| `get_facility_management_requests(client, scope)` | `sent` = solicitudes enviadas, igual que la vista histórica del cliente; `drafts` = borradores propios (exige `create`) |
| `get_facility_management_request(client, id)` | Solicitud, filas de detalle sin adjuntos y audiencia (solo si el FM puede editarla). Devuelve `NULL` si no existe o no es visible, sin distinguir entre ambos casos |
| `save_facility_management_request(client, id, request, details, submit)` | Guardado transaccional; ver abajo |
| `delete_facility_management_request_draft(client, id)` | Elimina un borrador propio (`create`). Si el borrador está vinculado a un aviso o a un preventivo, devuelve `55000` |
| `annul_facility_management_request(client, id)` | Anula una solicitud `sent` o `quoted` (`manage`) |
| `get_facility_management_request_branches(client)` | Sucursales del cliente: id, nombre, ciudad, sede, dirección e `is_active`. Nunca `client_email` |
| `get_facility_management_request_assets(client)` | Activos no archivados del cliente: id, nombre, código, tipo, padre, sucursal, estado y ruta |
| `get_facility_management_request_providers(client)` | Solo proveedores y subcontratistas con relación **activa** del cliente. Nunca un FM |

Los directorios exigen `create` o `manage`. `requests.*` no implica
`assets.view`, así que la RLS de `assets` y el módulo `#assets` no se abren.

### Guardado transaccional

`save_facility_management_request` sigue los mismos pasos que
`persistRequest`, en una sola transacción:

1. escribe la solicitud;
2. reemplaza el detalle;
3. sincroniza la audiencia;
4. solo después promueve `draft → sent`.

Si falla cualquier paso, no queda nada a medias. Por ejemplo, un proveedor no
homologado deja la solicitud sin crear.

El payload se valida contra una lista blanca:

- Un campo desconocido devuelve `22023`. Entre ellos: `organization_id`,
  `created_by*`, `status`, `id`, `image_urls` y `attachment_urls` en el detalle.
- `request_number` es obligatorio al crear e inmutable al editar (`22023`).
- Sucursal y activo deben ser del cliente (`22023`). Al crear o cambiar,
  también deben estar activos y no archivados.
- Los contactos son del cliente. Si llega `coordination_contact_member_id`,
  `coordination_contact_name`, `coordination_contact_email`,
  `visit_contact_member_id` o `internal_responsible_member_id`, devuelve
  `42501`, incluso para limpiarlos.

Qué queda en la fila:

- **Solicitud nueva del FM:** el contacto de coordinación queda sin miembro,
  con el nombre y el email del propio FM como snapshot. No lleva contacto de
  visita ni responsable interno. `created_by*` es el FM.
- **Solicitud existente:** se conservan en el servidor el contacto, el
  contacto de visita, el responsable interno, `created_by*`,
  `organization_id`, `request_number`, `created_at` y los adjuntos.
- **Tipo de solicitud:** se respeta el bloqueo histórico del tipo
  (`trg_requests_lock_request_type`).
- **Adjuntos protegidos (limitación temporal):** si el detalle existente
  tiene adjuntos del cliente (`attachment_urls`), la edición delegada se
  rechaza con `55000`.
  - **Por qué:** 9C.4 no tiene autorización sobre R2/archivos, y el guardado
    reemplaza `request_details`. Permitirlo borraría adjuntos que el FM no
    conoce.
  - La comprobación ocurre **antes** de cualquier mutación de `requests`,
    `request_details` o la audiencia. El rechazo es atómico: cero cambios, y
    los tests lo verifican fila por fila.
  - Nunca se devuelven ni se copian las URLs. La respuesta solo trae
    `has_client_attachments`, y la UI muestra: "Esta solicitud contiene
    adjuntos protegidos y no puede editarse desde la gestión delegada
    todavía."
  - El cliente directo no cambia.
  - Se revisará en el bloque de Assets/Files/R2.
- **Anulada o completada:** no se edita (`55000`).

### Borrador privado: mismo contrato en todas las superficies

Una solicitud externa privada necesita al menos un proveedor válido, **también
como borrador**. Ya era el contrato de `persistRequest` +
`set_request_audience` en `RequestList`. `DraftList` era la superficie
inconsistente: escribía `is_public` sin sincronizar invitaciones. Ahora usa
`persistRequest`, así que ambas coinciden, en modo directo y delegado:

- borrador público sin proveedores: permitido;
- borrador privado sin proveedores: rechazado;
- borrador privado con un proveedor activo: permitido;
- proveedor no homologado: rechazado;
- un FM como destinatario: rechazado.

`RequestForm` valida antes de enviar, también al guardar como borrador, con el
mensaje existente ("Selecciona al menos un proveedor…").

### Audiencia: una sola lógica

El cuerpo histórico de `set_request_audience` se movió **sin cambios** a
`apply_request_audience_internal`, que es interna y no tiene autorización
propia. Esa lógica cubre:

- el rechazo de un FM como destinatario (`22023`);
- la exigencia de una relación activa;
- el bloqueo para quitar a quien ya cotizó;
- las notificaciones y la auditoría.

`set_request_audience` conserva su autorización histórica, que es solo del
cliente, y delega en esa función. El FM llega a esa lógica solo a través de
`save_facility_management_request`.

Las notificaciones al proveedor llevan la organización del cliente y al FM
como actor. La auditoría queda en el cliente, con el FM como actor.

### Minimización de la respuesta

| Campo | Qué recibe el FM |
|---|---|
| `created_by`, `created_by_user_id`, `created_by_email` | No se envían |
| `created_by_name` | Nombre guardado. Si falta, contiene `@` o es la parte local del email, recibe "Usuario del cliente" |
| `coordination_contact_member_id` y `coordination_contact_email` | No se envían. Queda `coordination_contact_name` (mismo filtro; fallback "Asignado por el cliente") y `has_client_coordination_contact` |
| `visit_contact_member_id` | No se envía. Queda `has_client_visit_contact` |
| `internal_responsible_member_id` | No se envía. Queda la etiqueta `internal_responsible_name` = "Asignado por el cliente" |
| `image_urls`, `document_urls`, `request_details.attachment_urls` | No se envían |
| `notified_at`, ids de cotizaciones y de OT | No se envían |

Además se envían estas banderas calculadas en el servidor: `is_own`,
`can_edit`, `can_delete_draft` y `can_annul`.

### Integraciones

**`convert_maintenance_notice`.** Acepta al FM con
`can_convert_maintenance_notice_as_facility_manager`.

- Para el FM, un borrador ajeno "no existe", con el mismo mensaje que una
  solicitud inexistente.
- Devuelve la fila minimizada.
- El historial del activo registra al FM como actor.
- El camino directo no cambia.

**Aviso sanitizado.** Desde 9C.4, `converted_request_id` y su número son
visibles para el FM con `requests.view`, salvo que la solicitud sea un
borrador ajeno. Aplica tanto en `get_maintenance_notices` como en
`sanitize_maintenance_notice_for_delegate`.

**`plan_preventive_maintenance_occurrence`.** Acepta al FM con
`can_plan_preventive_request_as_facility_manager`, con la misma regla para
borradores ajenos. Devuelve la ocurrencia minimizada.

**Lecturas del preventivo.** `get_preventive_maintenance_plans` y
`get_preventive_maintenance_occurrences` exponen al delegado:

- `request_creation_id`, solo con la capacidad de planificar en solicitud;
- `request_id`, con `requests.view`;
- `work_order_id`, nunca.

**`skip_preventive_maintenance_occurrence`.** Desde 9C.2 devolvía la fila
completa también al delegado. Desde 9C.4 le devuelve la fila minimizada: el
snapshot va sanitizado y los ids siguen las reglas de arriba.

**Responsables de inspecciones y preventivo.** Son del cliente. Los ids
internos de membresía del cliente nunca salen al FM, y el backend los preserva
en el servidor.

- **Inspecciones.** `get_inspection_plans`, `get_inspection_runs` y
  `get_inspection_run_detail` devuelven `responsible_member_id = NULL` al
  delegado, más `has_responsible` y el nombre seguro. `get_inspection_plans` y
  `get_inspection_runs` se recrearon con la columna nueva y los mismos grants.
  - `upsert_inspection_plan`: `NULL` conserva el responsable; cualquier UUID
    devuelve `42501`, incluido el actual. Queda eliminada la regla de 9C.2
    "reenviar exactamente el id".
  - `upsert_inspection_plan`, `create_inspection_run_from_plan` y
    `submit_inspection_run` devuelven la fila minimizada.
- **Preventivo:**

- `get_preventive_maintenance_plans` devuelve `responsible_member_id = NULL`
  al delegado, más `has_responsible` (booleano, sin identificar a nadie). La UI
  muestra "Asignado por el cliente".
- El `scope_snapshot` delegado deja `plan.responsible` como
  `{"assigned": true}`: sin `membership_id`, `role`, nombre, `user_id` ni
  email. Aplica en planes, ocurrencias, omitir y planificar.
- `save_preventive_maintenance_plan` en modo delegado:
  - el FM envía `NULL` y el servidor conserva el responsable real al editar
    otros campos;
  - cualquier UUID devuelve `42501`, sea del cliente, del FM o el mismo valor
    actual. No es posible cambiarlo ni limpiarlo;
  - devuelve el plan sin `responsible_member_id` ni `created_by_user_id`.
- `set_preventive_maintenance_plan_active` devuelve al delegado el plan
  minimizado igual.
- El cliente directo no cambia: recibe y usa su `responsible_member_id`.

## Frontend

- **Permisos.** `src/lib/facilityManagement.ts` agrega:
  - `canFacilityManagerViewRequests`, `canFacilityManagerCreateRequests` y
    `canFacilityManagerManageRequests`;
  - `canFacilityManagerConvertNoticeToRequest` y
    `canFacilityManagerPlanPreventiveRequest`.

  Los módulos `requests` y `drafts` se suman a `ManagedClientGate`; `drafts` es
  elegible solo con `create`.
- **`RequestScope`** (`src/hooks/useRequestScope.ts`). Incluye `canView`,
  `canCreate`, `canManage`, `canManageOwnDraft`, `canManageAudience`,
  `canViewQuotes`, `canGenerateWorkOrder`, `canUseClientMemberDirectory`,
  `canUseClientTechnicianDirectory` y `managedClientId`.
  - `useDirectRequestScope` reproduce exactamente el comportamiento histórico.
  - `buildDelegatedRequestScope` deja cotizaciones, OT y directorios del
    cliente en `false`.
- **`persistRequest`.** Recibe un `mode` explícito (`direct` o `delegated`) y
  siempre el `organizationId` real del cliente. Tiene una semántica y dos
  transportes; el camino directo no cambia.
- **Lectura** (`src/lib/requestData.ts`):
  - `mapRequestRow` es el mapeo completo, compartido por `RequestList` y
    `DraftList`;
  - `loadDirectRequestForEdit` carga el detalle y las invitaciones;
  - hay wrappers para las RPCs delegadas.
- **`DraftList`.**
  - Guarda con `persistRequest`. Antes escribía `is_public` y el estado sin
    sincronizar invitaciones.
  - Usa el mapeo completo.
  - Al reabrir un borrador carga su audiencia.
- **`RequestList` / `OrderTable` en modo delegado.**
  - Nunca consulta `quotes` ni `work_orders` y no ejecuta `seedDatabase`.
  - No muestra la columna de cotizaciones, "Ver cotizaciones", "Generar OT" ni
    el foro.
  - "Editar" y "Anular" siguen las banderas del servidor.
  - `quote=` del hash se ignora.
  - `useAssets()` recibe `NO_ASSET_ACCESS_SCOPE`, así que no consulta nada.
- **`RequestForm` en modo delegado.**
  - No usa `get_coordination_contacts`, `TechnicianSelect` ni
    `CoordinationContactSelect`.
  - El contacto de coordinación se muestra en solo lectura: el propio FM en
    una solicitud nueva, el del cliente en una existente.
  - El contacto de visita y el responsable interno son etiquetas.
  - "Encargado" es texto libre y no hay adjuntos.
  - Sucursales, activos y proveedores salen de los directorios mínimos:
    `DelegatedRequestAssetPicker`, `DelegatedRequestProviderSelector` y
    `StaticRequestAssetSummary`.
- **Rutas.**
  - `#requests?managedClient=` y `#requests?request=&managedClient=` montan
    `DelegatedRequestsModule`.
  - `#drafts?managedClient=` monta `DelegatedDraftsModule`, solo con `create`.
  - La barra lateral muestra "Solicitudes de clientes" (`view`) y "Borradores
    de clientes" (`create`).
- **Backlog.**
  - "Convertir en solicitud" aparece con la capacidad combinada y guarda con
    el transporte delegado.
  - Un aviso convertido ofrece "Ver solicitud", que abre
    `#requests?request=…&managedClient=…`.
- **Preventivo.** "Planificar" aparece con la capacidad combinada.
  `PreventiveRequestDialog` verifica la solicitud reservada con la RPC de
  detalle, nunca leyendo la tabla.

## Validación

- **pgTAP dedicado:** 193/193.
- **Regresión pgTAP:** 1882/1882, verde con y sin GRANT CRUD de tabla (ver la
  nota de abajo).
- **Controles negativos:** se mutó temporalmente la función viva, se corrió la
  suite y se restauró byte a byte.

  | Control | Fallos |
  |---|---|
  | A. technician/viewer ven | 4 |
  | B. create sin view | 2 |
  | C. requester gestiona | 3 |
  | D. `can_user_read_request` ampliado al FM | 3 |
  | E. payload expone `created_by_email` | 3 |
  | F. nombre derivado del email | 2 |
  | G. el FM asigna contactos del cliente | 6 |
  | H. sin lista blanca | 5 |
  | I. borradores ajenos visibles | 4 |
  | J. editar borradores ajenos | 2 |
  | K. sin frontera de tenant al guardar | 1 |
  | L. activo de otro cliente | 1 |
  | M. `set_request_audience` abierto al FM | 2 |
  | N. convertir un aviso sin `requests.create` | 1 |
  | O. `request_creation_id` sin capacidad | 2 |
  | P. anular con `create` | 3 |
  | Q. `responsible_member_id` preventivo expuesto al FM | 3 |
  | R. snapshot con `responsible.membership_id` | 3 |
  | S. edición delegada con adjuntos protegidos | 5 |
  | T. smoke 9B con la expectativa antigua de `#requests` | 1 (45/46) |

- **Smoke visual local:** 40/40, con Chromium headless, Vite forzado al
  Supabase local y bloqueo de `*.supabase.co`.
- **Regresión de smokes:** 9C.3 39/39, 9C.2 47/47, 9C.1 35/35 y 9B 46/46.
  - El smoke 9B se actualizó: `#requests` de un FM ahora es la puerta delegada.
  - El FM owner sin cliente elegible no obtiene acceso ni consultas.
  - El FM manager elegible entra a las solicitudes de su cliente, con la
    organización activa todavía en el FM.
  - En ambos casos no hay `ProviderRequestList`, `PublicRequestList` ni
    consultas crudas a `requests`/`quotes`.

**GRANT SQL ≠ autorización.** Los GRANT CRUD de tabla varían por entorno.
Producción otorga CRUD a `authenticated` sobre `assets`, `client_branches`,
`asset_criticality_assessments` y `maintenance_notices`; el contenedor local
puede otorgarlo o no. La autorización real es RLS/RPC/triggers.

Las tres aserciones antiguas que exigían ausencia de CRUD se reescribieron
para probar la invariante real:

- **9C.1 "no DELETE":** un `DELETE` directo no borra filas, haya o no
  privilegio SQL.
- **9C.1 "grants":** la migración 9C.1 no emite GRANT DML de tabla, y no hay
  policies delegadas de escritura más allá de crear/actualizar activos.
- **9C.3:** `INSERT`, `UPDATE` y `DELETE` directos sobre `maintenance_notices`
  (FM gestor y owner directo) no escriben nada; el aviso queda intacto.

Los meta-privilegios de 9C.1H (`TRUNCATE`, `REFERENCES`, `TRIGGER`,
`MAINTAIN`) siguen prohibidos para `anon`/`authenticated`, y su suite no
cambió. La suite completa se verificó verde en ambos baselines: con CRUD, como
producción, y sin CRUD en esas tablas, revocado temporalmente y restaurado
byte a byte.

## Siguiente

Cotizaciones (`quotes.*`), OT (`work_orders.*`) y reportes.
