# Inventario mínimo + materiales de OT

César pidió que los materiales de una OT vengan del almacén en vez de ser
texto libre. Esto agrega `warehouses` → `materials` → `work_order_materials`,
con el mismo principio que las dos fases anteriores: los materiales cuelgan
de `work_orders` sin importar si esa OT es interna o externa — **no hay un
módulo de "materiales internos" separado de uno "externo"**.

## 1. Alcance explícito — qué NO se construyó

Deliberadamente **no** es SAP MM. En esta fase no existe:

- Kardex (historial de movimientos de stock).
- Valorización / costeo (promedio, FIFO, etc.).
- Órdenes de compra.
- Transferencias entre almacenes.
- Reservas complejas (con expiración, prioridad, etc.).
- Lotes / números de serie.
- Movimientos contables.
- **Descuento automático de stock**: guardar `used_quantity` en una OT
  nunca resta de `materials.stock`. El stock solo cambia cuando alguien lo
  edita manualmente vía `upsert_material` (el mismo camino que crearlo).

Lo que sí existe: almacenes, materiales con un número de stock simple, y
materiales planificados/usados por OT con una advertencia informativa (no
bloqueante) cuando el stock no alcanza.

## 2. Modelo

```
organizations ──< warehouses ──< materials
                                     ▲
                                     │
work_orders ──< work_order_materials┘
```

### `warehouses`

`organization_id` + `branch_id` opcional (validado por trigger contra la
misma organización). Sin `DELETE` — desactivar es `is_active = false` vía
`upsert_warehouse`.

### `materials`

`code`/`name`/`unit` obligatorios, `stock numeric(12,2) >= 0`. `warehouse_id`
validado por trigger contra la misma `organization_id`.

**Decisión de unicidad**: `UNIQUE(organization_id, lower(code))` — el
código es un SKU de catálogo por organización, no por almacén. Dos
almacenes no pueden tener cada uno su propio "ROD-001" significando cosas
distintas; si el mismo material físico vive en dos almacenes a la vez, eso
requeriría un modelo de stock-por-almacén (kardex real) que está
explícitamente fuera de alcance. Sin `DELETE` — desactivar es
`is_active = false` vía `upsert_material`.

### `work_order_materials`

Línea de planificación, no un movimiento de stock. `organization_id` debe
igualar `work_orders.provider_organization_id` (la organización operadora
— para una OT interna, la misma organización cliente; mismo ancla que
`work_order_activities.organization_id`). `material_id` debe pertenecer a
esa misma organización.

- `stock_snapshot`: el stock del material **en el momento de crear la
  línea** (o cuando se cambia de material en una línea existente). Es un
  marcador de "cuánto había cuando se planificó", no un valor vivo — para
  eso está `current_stock`, resuelto en cada lectura por
  `get_work_order_materials`.
- `planned_quantity` / `used_quantity`: ambos `>= 0`, sin relación forzada
  entre ellos (se puede usar más o menos de lo planificado; no hay
  restricción, es un dato de reporte para esta fase).
- `DELETE` físico permitido aquí (a diferencia de `warehouses`/`materials`)
  — es solo la línea de planificación de una OT, nunca el material maestro.

## 3. Advertencias, no bloqueo

`get_work_order_materials` calcula `warning_status` una sola vez,
server-side, con esta regla exacta (la misma que pidió César):

```
stock = 0 Y planned_quantity > 0  → no_stock            ("Sin stock")
stock < planned_quantity          → insufficient_stock  ("Stock insuficiente")
en cualquier otro caso            → ok                  ("Disponible")
```

Verificado end-to-end contra Postgres local con los tres casos exactos del
alcance: stock 10/planificado 5 → `ok`; stock 3/planificado 5 →
`insufficient_stock`; stock 0/planificado 2 → `no_stock`.

`upsert_work_order_material` **nunca** rechaza el guardado por esta razón
— la advertencia es puramente informativa. El frontend además muestra una
vista previa de la advertencia en el formulario (mismo cálculo,
recomputado client-side solo para feedback inmediato antes de guardar; lo
que persiste es siempre lo que devuelve el servidor después).

## 4. RPCs

Todas `SECURITY DEFINER`, con el mismo cuidado de alias que la migración
correctiva anterior (`20260827170000_fix_work_order_activities_rpc_ambiguity.sql`):
toda tabla referenciada usa alias corto (`wo`, `wh`, `m`, `wom`, `cb`), y
`get_work_order_materials`/`get_inventory_catalog` — que exponen columnas
de salida con nombres que coinciden con columnas reales (`id`, etc.) —
califican **cada** referencia desde la primera línea, para no repetir el
mismo bug 42702.

- **`get_inventory_catalog(p_organization_id)`**: almacenes y materiales
  **activos** de una organización, como un único `jsonb` (`{warehouses:
  [...], materials: [...]}`) — un solo round trip. Exige ser miembro
  activo de esa organización o `platform_admin`.
- **`upsert_warehouse(...)`** / **`upsert_material(...)`**: crear/editar.
  Exigen owner/admin/manager de la organización o `platform_admin`.
  `upsert_material` valida que el almacén pertenezca a la misma
  organización.
- **`get_work_order_materials(p_work_order_id)`**: líneas de la OT +
  `current_stock` en vivo + `warning_status` calculado. Autorización
  **más estricta que `work_orders` en sí** — igual decisión que
  `work_order_activities`: solo miembros de la organización operadora
  (`provider_organization_id`) o `platform_admin`; el cliente del otro
  lado de una OT externa no ve el detalle de materiales.
- **`upsert_work_order_material(...)`**: crea o actualiza una línea.
  Exige owner/admin/manager de la organización operadora. Llena
  `stock_snapshot` solo si la línea es nueva o si cambia el material.
- **`delete_work_order_material(p_work_order_material_id)`**: borra solo
  la línea de planificación (nunca el material maestro — no existe
  `delete_material`).

Ninguna de las tres tablas tiene policy `INSERT`/`UPDATE`/`DELETE` —
escritura exclusivamente vía estas RPCs. `SELECT` sí es por RLS directa
(no por RPC): cualquier miembro activo de la organización puede leer su
propio catálogo de almacenes/materiales sin pasar por
`get_inventory_catalog` si lo necesitara; esa RPC existe por conveniencia
(un solo round trip para catálogo + materiales combinados), no porque el
`SELECT` directo esté bloqueado.

## 5. Frontend

- `src/types/inventory.ts`, `src/types/workOrderMaterial.ts`.
- `src/hooks/useInventoryCatalog.ts`: catálogo de una organización +
  `saveWarehouse`/`saveMaterial`. Traduce el error de `UNIQUE` de código
  duplicado a un mensaje legible.
- `src/hooks/useWorkOrderMaterials.ts`: materiales de una OT +
  `saveMaterial`/`deleteMaterial`, mismo patrón "refrescar desde el
  servidor tras cada mutación" que `useWorkOrderActivities.ts`.
- `src/components/inventory/InventoryView.tsx` (+ `WarehouseEditorDialog.tsx`,
  `MaterialEditorDialog.tsx`): módulo de inventario, agrupado por almacén.
  Nuevo ítem de Sidebar "Inventario" (`Sidebar.tsx`/`Dashboard.tsx`),
  visible solo para owner/admin/manager de una organización operadora
  (`client_company`/`provider_company`/`facility_manager`, nunca
  `platform_admin` — mismo set que "Órdenes de trabajo").
- `src/components/work-orders/WorkOrderMaterialsSection.tsx` (+
  `WorkOrderMaterialEditorDialog.tsx`, con buscador de material tipo
  combobox igual al de activo en `RequestAssetPicker.tsx`): integrada en
  `WorkOrderDetailDialog.tsx` junto a la sección de Actividades, con la
  misma visibilidad restringida a la organización operadora
  (`canViewOperatingDetails`, la misma condición ya usada para
  Actividades — renombrada de `canViewActivities` porque ahora gatea
  ambas secciones).
- Badge nuevo `WorkOrderMaterialWarningBadge` en `StatusBadge.tsx`
  (`ok` → verde "Disponible", `no_stock` → rojo "Sin stock",
  `insufficient_stock` → naranja "Stock insuficiente").

## 6. Permisos

| Quién | Ve inventario (módulo) | Ve materiales de una OT | Gestiona (crear/editar/eliminar) |
|---|---|---|---|
| owner/admin/manager de la organización operadora | Sí | Sí | Sí |
| `technician`/`viewer`/`requester` de esa misma organización | Sí (solo lectura) | Sí (solo lectura) | No |
| Cliente viendo una OT externa que no opera | No aplica | No (sección oculta) | No aplica |
| `platform_admin` | No (nunca opera desde su propia organización) | Sí (autorización explícita en la RPC) | Sí (autorización explícita en la RPC) |

## 7. Cómo probar manualmente

**Inventario:**
1. Crear almacén "Almacén Central".
2. Crear ROD-001 (Rodamiento, unidad, stock 10), LUB-001 (Lubricante,
   litro, stock 3), PRB-001 (Kit prueba, unidad, stock 0).
3. Confirmar que los tres aparecen en Inventario, agrupados bajo el
   almacén.
4. Cambiar a Organización B → confirmar que no ve los materiales de
   Organización A (ni en el módulo Inventario ni en el buscador de
   materiales de una OT).

**OT:**
1. Abrir una OT (interna o externa) como owner/admin/manager de su
   organización operadora.
2. Agregar ROD-001 planificado 5 → **Disponible**.
3. Agregar LUB-001 planificado 5 → **Stock insuficiente**.
4. Agregar PRB-001 planificado 2 → **Sin stock**.
5. Guardar, cerrar el diálogo, reabrirlo → confirmar que las 3 líneas
   persisten con técnico, cantidades y advertencia intactos.
6. Confirmar que ningún guardado fue bloqueado por la advertencia.
7. Iniciar sesión como técnico → confirmar que ve la sección de
   materiales pero sin botones de agregar/editar/eliminar.
8. Repetir con una OT interna y una externa → confirmar que ambas usan
   exactamente la misma sección `WorkOrderMaterialsSection`.

## 8. Validaciones ejecutadas

- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores.
- Smoke test manual contra Postgres local (vía `psql` en el contenedor,
  bypaseando auth con `request.jwt.claim.sub`) ejercitando el flujo
  completo: crear organización → almacén → 3 materiales → OT interna →
  3 líneas de `work_order_materials` → `get_work_order_materials` →
  confirmó `ok`/`insufficient_stock`/`no_stock` exactamente como se
  esperaba, sin ningún error de ambigüedad de columnas.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; `warehouses`, `materials`, `work_order_materials` y las 6
  RPCs presentes con sus tipos.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- `npx tsc -p tsconfig.app.json --noEmit`: mismos errores preexistentes ya
  documentados en fases anteriores, ningún error nuevo.

## 9. Pendiente (documentado, no construido en esta fase)

- **Reactivar un almacén/material desactivado**: `upsert_warehouse`/
  `upsert_material` ya soportan `is_active`, pero la UI de esta fase no
  expone un control para reactivar uno ya desactivado (tampoco los lista
  — `get_inventory_catalog` solo devuelve activos). Extensión natural
  cuando se necesite.
- **Descuento real de stock al ejecutar la OT**: `used_quantity` es hoy
  solo un dato de reporte; nada resta `materials.stock`
  automáticamente. Es el primer paso natural hacia un kardex real, pero
  está fuera de alcance de esta fase por decisión explícita.
- **Múltiples almacenes con el mismo material**: no soportado (ver
  decisión de unicidad en §2) — requeriría un modelo de stock por
  almacén.
- **Reservas / bloqueo duro por stock insuficiente**: no implementado a
  propósito; la advertencia es y seguirá siendo informativa hasta que se
  decida lo contrario en una fase posterior.
