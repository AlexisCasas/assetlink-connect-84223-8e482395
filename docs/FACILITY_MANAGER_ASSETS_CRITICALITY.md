# Facility Manager — acceso operativo a Activos + Criticidad (Fase 1 · Punto 9C.1)

Primer módulo operativo sobre la delegación Cliente → Facility Manager
(9A/9B, ver `docs/FACILITY_MANAGER_DELEGATED_PERMISSIONS.md`).

- Migración: `supabase/migrations/20260928042257_facility_manager_assets_criticality_access.sql`
- Pruebas: `supabase/tests/facility_manager_assets_criticality_access.test.sql` (188 aserciones)

Solo se hacen efectivos `assets.view`, `assets.manage`, `criticality.view` y
`criticality.manage`. Todos los demás permisos delegados (`inspections.*`,
`preventive_maintenance.*`, `maintenance_notices.*`, `requests.*`,
`providers.*`, `quotes.*`, `work_orders.*`, `reports.*`) siguen sin abrir
nada. **9C.2 será Inspecciones + Preventivo.**

## 1. Fórmula de autorización

```
relación facility_management ACTIVE
AND cliente ACTIVE (client_company)
AND Facility Manager ACTIVE (facility_manager)
AND membresía ACTIVA del usuario en ESE FM
AND ESA membresía asignada a ESA relación
AND el/los permiso(s) delegado(s) en ESA relación
AND rol interno permitido
```

Todo se evalúa sobre la **misma** fila de relación: un usuario que es
miembro de dos FM nunca combina la relación de uno con el rol/membresía del
otro. La implementa un único helper backend:

- `has_facility_management_operational_access_all(_client, _permissions[], _allowed_roles[])`
  — exige **todos** los permisos en la misma relación (array vacío ⇒ false).
- `has_facility_management_operational_access(_client, _permission, _allowed_roles[])`
  — atajo de un solo permiso.

Ambos `STABLE SECURITY DEFINER`, `search_path = ''`, sin parámetros de
`user_id` / FM / membership (usan `auth.uid()`), `EXECUTE` solo para
`authenticated` (lo necesitan las policies RLS), nada para `PUBLIC`/`anon`.

## 2. Matriz de roles del FM (solo acceso delegado)

| Capacidad efectiva | Permisos requeridos (misma relación) | Roles FM |
|---|---|---|
| Ver activos | `assets.view` | owner, admin, manager, technician |
| Crear/editar/archivar/restaurar activos | `assets.view` + `assets.manage` | owner, admin, manager |
| Cambiar a mano `assets.criticality` (INSERT o UPDATE) | `assets.view` + `assets.manage` + `criticality.view` + `criticality.manage` | owner, admin, manager |
| Ver matriz, umbrales, plantillas | `criticality.view` | owner, admin, manager |
| Modificar matriz/umbrales/plantillas/importar/limpiar | `criticality.view` + `criticality.manage` | owner, admin, manager |
| Ver historial de evaluaciones de un activo | `assets.view` + `criticality.view` | owner, admin, manager |
| Evaluar criticidad (individual, preview, masiva) | `assets.view` + `criticality.view` + `criticality.manage` | owner, admin, manager |

- `*.manage` **nunca** sustituye a `*.view`: si el cliente concedió solo
  `assets.manage`, el FM no ve ni escribe activos (igual para criticidad).
- Evaluar no exige `assets.manage` (`criticality.manage` es la capacidad
  específica), pero sí poder ver el activo.
- Un technician del FM puede ver activos pero nunca la matriz, el historial
  de evaluaciones ni evaluar. requester/quote_manager/operator/viewer: nada.
- El acceso **directo** de los miembros del cliente no cambia en absoluto
  (todas las reglas nuevas son una rama `OR` adicional).

## 3. Backend

### Activos (RLS, policies permisivas **adicionales**)

| Tabla | Delegado | Directo |
|---|---|---|
| `assets` | SELECT con `assets.view`; INSERT/UPDATE con `assets.view`+`assets.manage` (o/a/m) | sin cambios |
| `asset_categories` | SELECT con `assets.view`; sin escritura | sin cambios |
| `asset_events` | solo INSERT del evento del propio flujo (`created/updated/archived/restored`), del mismo actor (`created_by_user_id = auth.uid()`), sobre un activo del mismo cliente, con `assets.view`+`assets.manage` (o/a/m); sin lectura | sin cambios |
| `client_branches` | **sin RLS nueva**: RPC `get_facility_management_client_branches(_client)` devuelve solo `id, name, city, site, address, is_active` (la fila incluye `client_email`) | sin cambios |

- Sin `DELETE`: archivar/restaurar sigue siendo un `UPDATE`.
- La policy delegada autoriza una **fila**, no columnas. El trigger
  `trg_assets_enforce_delegated_write_limits` (`BEFORE INSERT OR UPDATE`)
  define qué columnas puede escribir el FM. Actúa solo en escrituras vía
  PostgREST (`current_user = 'authenticated'`) de alguien que **no es
  miembro directo** del cliente ni platform_admin; postgres, service_role y
  las RPCs `SECURITY DEFINER` (p. ej. `calculate_asset_criticality`, que
  trae su propia autorización) no pasan por él. El cliente directo no
  cambia.

  | Clase | Columnas | Regla FM |
  |---|---|---|
  | Escribibles (flujo de Activos) | `name`, `node_type`, `status`, `parent_asset_id`, `branch_id`, `asset_category_id`, `code`, `description`, `manufacturer`, `model`, `serial_number`, `barcode`, `purchase_date`, `warranty_until`, `location_text` | libres (con `assets.view`+`assets.manage`) |
  | Condicionada | `criticality` | cambiarla (INSERT no nulo o UPDATE distinto) exige además `criticality.view`+`criticality.manage` en la misma relación, rol o/a/m |
  | Sistema | `updated_at` | la fija `touch_updated_at`; en INSERT `created_at`/`updated_at` se normalizan a `now()` |
  | Reservadas | `id`, `organization_id`, `default_responsible_member_id`, `created_by_user_id`, `created_at`, `qr_code`, `image_url`, `metadata`, `technical_data` | UPDATE: nunca; INSERT: `created_by_user_id = auth.uid()`, responsable `NULL`, `qr_code`/`image_url` `NULL`, `metadata`/`technical_data` `'{}'` |

  En UPDATE la comparación es sobre la fila completa (`to_jsonb(NEW)` vs
  `to_jsonb(OLD)`): cualquier columna fuera de la lista escribible —
  **incluida una futura** — queda protegida automáticamente. Re-enviar el
  mismo valor de `criticality` (lo hace el formulario) no cuenta como
  cambio. `organization_id` en INSERT ya lo exige la policy (cliente
  autorizado).
- `check_asset_consistency` pasa a `SECURITY DEFINER` con `search_path = ''`
  y el mismo cuerpo (ya usaba solo `public.assets`, `public.asset_categories`
  y `public.client_branches` explícitos). Sin `EXECUTE` para PUBLIC, anon ni
  authenticated: solo corre como trigger. Antes validaba con la RLS del que
  escribe y el FM no lee `client_branches` por RLS; para un miembro directo
  el resultado es idéntico (una referencia a otro tenant sigue fallando).

### Criticidad (RPCs)

La criticidad se consume solo por RPC (sus tablas no ganan RLS). Se
reemplazó **únicamente la llamada de autorización** de cada RPC pública (el
resto del cuerpo es el vigente), delegando en cuatro capacidades internas
(sin `EXECUTE` para roles cliente), que conservan la condición directa
histórica y añaden la rama delegada:

| Capacidad | Directo (sin cambios) | Delegado | RPCs |
|---|---|---|---|
| `can_view_criticality_matrix` | platform_admin o miembro | `criticality.view`, o/a/m | `get_criticality_matrix`, `get_criticality_templates`, `get_criticality_thresholds`, `can_access_criticality_template` (interna → `get_criticality_template`, `apply_criticality_template`) |
| `can_manage_criticality_matrix` | platform_admin o owner/admin/manager | `criticality.view`+`criticality.manage`, o/a/m | `upsert_criticality_parameter/option`, `set_criticality_parameter/option_active`, `set_criticality_thresholds`, `replace_criticality_configuration`, `replace_criticality_matrix`, `clear_active_criticality_matrix`, `apply_criticality_template`, `create_template_from_current_matrix` |
| `can_view_asset_criticality_assessments` | platform_admin o miembro | `assets.view`+`criticality.view`, o/a/m | `get_asset_criticality_assessments` |
| `can_evaluate_asset_criticality` | platform_admin o owner/admin/manager | `assets.view`+`criticality.view`+`criticality.manage`, o/a/m | `calculate_asset_criticality`, `preview_bulk_asset_criticality`, `bulk_calculate_asset_criticality` |

Internas sin cambios: `validate_and_score_asset_criticality`,
`write_criticality_thresholds`, helpers `criticality_*`.

**No se ampliaron** `get_asset_traffic_light`, `get_branch_traffic_light`
ni `get_asset_integrated_history`: mezclan OT, inspecciones, preventivo y
avisos, módulos todavía no delegados.

## 4. Frontend

### Contexto de cliente operado ("managed client")

- `currentOrganization` **sigue siendo el FM**. Nunca se llama
  `setCurrentOrganization(cliente)` ni se crea una membresía ficticia.
- `useFacilityManagementOperationalClients()` consulta
  `get_my_facility_management_clients()` (React Query), filtrado al FM
  activo. Nada se persiste en localStorage como autorización.
- `useManagedClient(module, managedClientId)` resuelve el cliente: el query
  param `managedClient=<uuid>` (en `#assets` / `#criticality`) es **solo
  contexto visual**; debe coincidir con un cliente devuelto por el backend
  para ese módulo o la vista muestra "Cliente no disponible" y **no monta
  nada** (0 consultas). 0 clientes ⇒ estado vacío; 1 ⇒ autoselección; varios
  ⇒ selector. Cambiar de cliente cambia el hash (URL compartible).
- `ManagedClientGate` + `DelegatedAssetsModule` / `DelegatedCriticalityModule`
  (`src/components/facility-management/`) son reutilizables para 9C.2+.
- Matriz de capacidades frontend única en `src/lib/facilityManagement.ts`
  (`canFacilityManagerViewAssets`, `...ManageAssets`, `...ViewCriticality`,
  `...ManageCriticality`, `...ViewAssetCriticalityAssessments`,
  `...EvaluateAssetCriticality`). Es UX: RLS/RPCs son la autoridad.

### Activos sin duplicar la UI

- `AssetScope` (`src/hooks/useAssetScope.ts`): `mode` (`direct` |
  `facility_manager`), `organizationId`, `canViewAssets`, `canManageAssets`,
  `canViewCriticality`, `canEvaluateCriticality`, `includesCrossModuleData`,
  `canEditDefaultResponsible`.
- `useAssets(scope?)`: sin argumento = modo directo exactamente como antes
  (Inspecciones, Solicitudes y OT siguen llamándolo así). En modo delegado
  las sucursales vienen de la RPC dedicada.
- `AssetsView`, `AssetDetail`, `CriticalityMatrixView` y
  `CriticalityBulkAssessmentDialog` reciben el scope; ningún componente se
  duplicó.

### Qué NO se muestra en modo delegado (evita fugas cross-module)

Los hooks siguen llamándose (Rules of Hooks), pero con id `null` para no
consultar:

| Sección | Delegado | Motivo |
|---|---|---|
| Semáforo operativo (árbol y ficha) | oculto | mezcla OT/inspecciones/avisos |
| Pestaña Preventivo | visible solo con `preventive_maintenance.view` (desde 9C.2) | ver `docs/FACILITY_MANAGER_INSPECTIONS_PREVENTIVE.md` |
| "Crear aviso" | visible solo con `maintenance_notices.view` + `report` (desde 9C.3) | activo fijo; ver `docs/FACILITY_MANAGER_MAINTENANCE_NOTICES.md` |
| Historial integrado del activo | oculto | mezcla módulos no delegados |
| "Generar Reporte" | oculto | `reports.view` pendiente; el PDF carga preventivo/inspecciones/avisos |
| Código QR | oculto | el enlace exige membresía directa del cliente (deep link delegado fuera de 9C.1) |
| Fotos/documentos R2 | sin cambios (no ampliado) | Punto 10 |
| Directorio de miembros del cliente (planners/contactos) | no se consulta | el responsable muestra "Asignado por el cliente" / "Sin responsable" |
| Historial de evaluaciones de criticidad | solo con `assets.view`+`criticality.view` (o/a/m) | |
| "Evaluar criticidad" | solo con la capacidad de evaluar | |

### Criticidad manual del activo

En modo delegado el campo "Criticidad" del formulario de edición solo es
editable con `assets.manage` + `criticality.view` + `criticality.manage`
(rol o/a/m); si no, se muestra en solo lectura y no se envía en el payload.
El backend lo exige igual (trigger). Modo directo sin cambios.

### Responsable predeterminado

Sigue siendo **CLIENT-ONLY**: el formulario delegado lo muestra en solo
lectura y el backend (trigger del punto 3) rechaza cualquier intento del FM
de fijarlo o cambiarlo. El modelo no cambia (sigue apuntando a miembros del
cliente).

### Criticidad

En modo delegado todos los controles de mutación (crear/editar/activar
parámetros y opciones, umbrales, importar, plantillas, nueva matriz, guardar
plantilla, evaluación masiva) solo aparecen con la capacidad de gestión /
evaluación. En modo directo esos mismos botones ahora se ocultan también a
quien no es owner/admin/manager (antes eran visibles y el backend los
rechazaba); para owner/admin/manager no cambia nada.

### Sidebar y hash directo

Para una organización `facility_manager` (además de "Clientes
administrados" para owner/admin):

- **Activos de clientes** si al menos un cliente operativo concede
  `assets.view` a su rol.
- **Criticidad de clientes** si al menos uno concede `criticality.view` a un
  rol owner/admin/manager.

Se eligieron etiquetas "… de clientes" porque el FM no tiene activos ni
matriz propios: deja claro que opera datos de un cliente. Dashboard aplica
el mismo gate en `#assets` y `#criticality` (hash directo) y nunca muestra
nada sin un cliente validado. Modo directo y platform_admin sin cambios.

## 5. Verificación

- pgTAP dedicado: 188/188 (incluye llamadas directas a tabla que simulan un
  PostgREST manual). Controles negativos (transacciones descartables, nada
  queda en el repo):
  - A. helper sin condición de asignación → 3 fallos;
  - B. technician permitido en `assets.manage` → 2 (el trigger bloquea
    además su INSERT sin `created_by_user_id`: segunda capa);
  - C. technician permitido en criticidad view/manage → 8;
  - D. sin restricción de organización cliente → 31;
  - E. `criticality.manage` sin `criticality.view` → 2;
  - F. sin la condición de criticidad en el trigger → 5;
  - G. sin la allowlist de columnas → 7;
  - H. sin los controles de INSERT delegado → 10.
- Regresión completa sin cambios en las suites previas.
- Smoke visual local (Chromium headless contra Supabase local, fixtures
  temporales, bloqueo de `*.supabase.co`): 35/35 checks 9C.1 + 46/46 de 9B.

## 6. Fuera de alcance / pendientes

- Deep link QR delegado (hoy exige membresía directa del cliente).
- R2 (`authorize_asset_file_access`, `asset-files`): Punto 10.
- Reporte PDF del activo para FM: requiere `reports.view` y los módulos que
  incluye.
- Semáforo e historial integrado para FM: cuando se deleguen OT,
  inspecciones, preventivo y avisos.
- 9C.2 (hecho): Inspecciones + Preventivo, ver
  `docs/FACILITY_MANAGER_INSPECTIONS_PREVENTIVE.md`.
