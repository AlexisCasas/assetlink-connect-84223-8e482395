# Solicitudes internas y externas

Agrega un segundo flujo de ejecución (Solicitud → orden de trabajo directa,
sin proveedores) al flujo externo ya existente (Solicitud → proveedores →
cotizaciones → selección → orden de trabajo), sin tocar ni deprecar el
externo.

## 1. Flujo externo (sin cambios de comportamiento)

`requests` (request_type = 'external', default) → proveedores ven la
solicitud en `PublicRequestList.tsx`/`ProviderRequestList.tsx` → cotizan →
`create_work_order_from_quote` genera la orden. Todo el código de este
camino sigue intacto; los únicos cambios que lo tocan son **filtros
adicionales** (nunca relajaciones) para excluir solicitudes internas de las
vistas de marketplace/proveedores.

Las solicitudes existentes antes de esta fase no tienen `request_type`
guardado; la migración las backfillea a `'external'` automáticamente (ver
§3), así que ninguna solicitud legacy cambia de comportamiento.

## 2. Flujo interno (nuevo)

`requests` (request_type = 'internal') → sin proveedores, sin marketplace,
sin cotizaciones, sin sobre cerrado → owner/admin/manager de la organización
cliente presiona "Generar OT" → RPC `create_internal_work_order_from_request`
crea la orden de trabajo directamente, opcionalmente con un técnico asignado
desde el momento de la creación de la solicitud.

- `RequestForm.tsx`: campo "Tipo de gestión" (Externa/Interna, default
  Externa). En Interna: se oculta "Cotizaciones mínimas requeridas" y toda la
  sección de selección de proveedores/marketplace; aparece un selector
  opcional "Responsable interno / técnico" (reutiliza `TechnicianSelect`,
  ya construido para la asignación de técnicos en órdenes de trabajo) con el
  mensaje `"Puedes asignar responsable al generar la OT o posteriormente"`
  cuando la organización no tiene técnicos activos aún.
- `RequestList.tsx` / `OrderTable.tsx`: badge Interna/Externa (columna
  `type`, nueva, se integra al sistema de columnas configurables existente).
  Para solicitudes internas la columna "Cotizaciones" muestra "No aplica" en
  vez de la barra de progreso, y la columna de acciones reemplaza el botón
  de cotizaciones ($) por "Generar OT" (o un check "OT generada" si ya
  existe una).
- `WorkOrdersList.tsx` / `WorkOrderDetailDialog.tsx`: una orden interna
  (`quote_id IS NULL`) se identifica con el badge "Solicitud interna" y
  muestra `"No aplica (solicitud interna)"` en el campo de cotización
  asociada; el resto de la vista (estado, importe, técnico asignado,
  trazabilidad a `request_id`) funciona igual que una orden externa, sin
  ninguna rama de código nueva que asuma `quote_id` no nulo.

## 3. Decisiones de schema

### `requests.request_type text NOT NULL DEFAULT 'external' CHECK IN ('external','internal')`

`NOT NULL DEFAULT` hace que Postgres backfillee todas las filas existentes a
`'external'` en el momento de aplicar la migración — cero solicitudes
legacy quedan en `null`, y por lo tanto el frontend no necesita ninguna
rama `request_type ?? 'external'`: el dato ya viene siempre poblado. (El
mapeo defensivo `req.request_type === 'internal' ? 'internal' : 'external'`
en `RequestList.tsx` es solo una segunda capa de seguridad, no la fuente de
verdad del backfill.)

### `requests.internal_responsible_member_id uuid NULL REFERENCES organization_members(id)`

Opcional. Un trigger (`check_request_internal_responsible`,
`BEFORE INSERT OR UPDATE`) valida que, si se define, el miembro:
pertenezca a la misma `organization_id` de la solicitud, esté activo, y
tenga rol `technician` — mismo patrón que el trigger de asignación de
técnico en `work_orders` de la fase anterior
([[operation-members-roles]]).

### `work_orders.quote_id` pasa a nullable

Era `NOT NULL UNIQUE`. Se le quita el `NOT NULL`: una orden interna no tiene
cotización de origen. La `UNIQUE` se mantiene — Postgres permite múltiples
`NULL` bajo una constraint `UNIQUE`, así que muchas órdenes internas pueden
coexistir sin chocar entre sí ni con las externas.

### `work_orders.provider_organization_id = client_organization_id` para órdenes internas

El trabajo interno no tiene proveedor externo: la organización cliente es
también quien ejecuta. En vez de dejar `provider_organization_id` en null
(la columna no lo permite, por diseño previo), la RPC lo setea igual a
`client_organization_id`. Esto es deliberado y tiene dos efectos colaterales
que se buscan explícitamente:

1. La policy `SELECT` existente de `work_orders`
   (`is_organization_member(client_organization_id) OR
   is_organization_member(provider_organization_id)`) sigue siendo correcta
   sin ningún cambio de RLS.
2. El trigger existente `check_work_order_assigned_technician` (valida que
   `assigned_member_id` pertenezca a `provider_organization_id`) valida
   gratis que el responsable asignado sea un técnico de la propia
   organización cliente — sin duplicar lógica.

### Deduplicación de OT por solicitud interna

No se agregó un `UNIQUE(request_id)` global en `work_orders` (rompería un
futuro escenario externo de múltiples órdenes por solicitud). En su lugar,
la RPC busca una orden existente con `request_id = target_request_id AND
quote_id IS NULL` antes de crear una nueva; si existe, la devuelve tal cual
en vez de duplicar.

## 4. RPC `create_internal_work_order_from_request(target_request_id uuid, target_assigned_member_id uuid default null)`

`SECURITY DEFINER`, mismo patrón que `create_work_order_from_quote` y
`assign_work_order_technician`. Validaciones, en orden:

1. `auth.uid()` presente.
2. La solicitud existe.
3. `request_type = 'internal'` (una solicitud externa no puede generar OT
   por esta vía).
4. La organización cliente de la solicitud existe y está `active`.
5. El llamador es `owner`/`admin`/`manager` de esa organización (vía
   `has_organization_role`, ya existente) o `platform_admin` (vía
   `is_platform_admin`).
6. Si ya existe una OT interna (`quote_id IS NULL`) para esa solicitud, se
   devuelve esa misma fila (idempotente, sin duplicar).
7. Si no, inserta la orden (`quote_id = NULL`, `client_organization_id =
   provider_organization_id = requests.organization_id`, `status =
   'created'`, título/descripción heredados de la solicitud,
   `assigned_member_id = target_assigned_member_id`) y la devuelve.

`REVOKE ALL ... FROM PUBLIC; GRANT EXECUTE ... TO authenticated;` — mismo
candado que el resto de RPCs del proyecto. **No se agregó ninguna policy
`INSERT`/`UPDATE` genérica sobre `work_orders`**: esta RPC sigue siendo la
única forma de crear una orden interna, igual que `create_work_order_from_quote`
es la única forma de crear una externa.

## 5. Permisos y visibilidad

| Vista | Solicitudes externas | Solicitudes internas |
|---|---|---|
| `PublicRequestList.tsx` (marketplace) | Visibles (sin cambio) | **Nunca** (`request_type = 'external'` agregado al query) |
| `ProviderRequestList.tsx` | Visibles (sin cambio) | **Nunca** (mismo filtro) |
| `RequestList.tsx` (organización cliente) | Visibles, flujo de cotizaciones intacto | Visibles, sin cotizaciones/proveedores; botón "Generar OT" |
| `WorkOrdersList.tsx` | Sin cambios | Aparecen igual que las externas, marcadas "Solicitud interna" |
| Generar OT interna | No aplica | Solo `owner`/`admin`/`manager` de la organización cliente, o `platform_admin` |

Nada de esto se implementó relajando RLS: los filtros de marketplace/
proveedores son condiciones de `SELECT` adicionales a nivel de query, y la
autorización real de "Generar OT" vive en la RPC (revalida en cada
llamada), igual que el resto de escrituras privilegiadas del proyecto.

## 6. Validaciones ejecutadas

- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores sobre el resto del historial.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; `requests.request_type`, `requests.internal_responsible_member_id`,
  `work_orders.quote_id` (nullable) y `create_internal_work_order_from_request`
  presentes con sus tipos.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- `npx tsc -p tsconfig.app.json --noEmit`: mismos 6 errores preexistentes ya
  documentados en fases anteriores (`AdminConsole.tsx`, `BranchesList.tsx`,
  `QuoteListDialog.tsx`, 3× `src/pages/Index.tsx`, página fuera del router),
  ningún error nuevo.

## 7. Checklist manual

### Caso A — Solicitud externa (no debe haber regresión)

1. Crear una solicitud dejando "Tipo de gestión" en su valor por defecto
   (Externa) → confirmar que "Cotizaciones mínimas requeridas" y la sección
   de proveedores siguen visibles igual que antes de esta fase.
2. Enviarla sin seleccionar proveedores → confirmar que sigue apareciendo en
   `PublicRequestList.tsx` (marketplace) para otras organizaciones
   proveedoras.
3. Cotizar desde una organización proveedora y aprobar la cotización →
   confirmar que `create_work_order_from_quote` sigue generando la OT como
   antes (con `quote_id` poblado).
4. En `RequestList.tsx`, confirmar que la fila muestra el badge "Externa" y
   que el botón de cotizaciones ($) sigue funcionando igual que antes.
5. En `WorkOrdersList.tsx`, confirmar que la OT generada **no** muestra el
   badge "Solicitud interna" y que "Cotización aprobada" muestra el UUID de
   la cotización, no "No aplica".

### Caso B — Solicitud interna

1. Crear una solicitud con "Tipo de gestión" = Interna → confirmar que
   desaparecen "Cotizaciones mínimas requeridas" y toda la sección de
   proveedores/marketplace.
2. Sin técnicos activos en la organización, confirmar que el selector de
   responsable interno muestra el mensaje "Puedes asignar responsable al
   generar la OT o posteriormente" y que la solicitud puede enviarse igual
   (el responsable es opcional).
3. Enviarla → confirmar que **no** aparece en `PublicRequestList.tsx` ni en
   `ProviderRequestList.tsx` de ninguna organización proveedora.
4. En `RequestList.tsx`, confirmar el badge "Interna", que la columna
   "Cotizaciones" muestra "No aplica" y que no hay botón de cotizaciones ($).
5. Presionar "Generar OT" como owner/admin/manager de la organización
   cliente → confirmar toast de éxito y que el botón cambia a "OT generada".
6. Presionar "Generar OT" una segunda vez (o refrescar y volver a intentar)
   → confirmar que no se crea una segunda orden (la RPC devuelve la
   existente).
7. Iniciar sesión con un rol `requester`/`viewer`/`technician` de la misma
   organización → confirmar que la RPC rechaza la generación de OT (no
   autorizado) si se intenta forzar la llamada.
8. En `WorkOrdersList.tsx`, confirmar que la orden interna aparece marcada
   "Solicitud interna", que "Cotización aprobada" muestra "No aplica
   (solicitud interna)", y que `request_id` referencia la solicitud
   original.
9. Si se asignó un responsable interno al crear la solicitud, confirmar que
   `WorkOrderDetailDialog.tsx` muestra ese técnico ya asignado en la orden
   recién creada.
10. Confirmar en `git grep -n "service_role" src` (sin resultados) y en el
    editor SQL/Studio local que no existe ninguna policy `INSERT`/`UPDATE`
    genérica nueva sobre `work_orders`.

## 8. Pendiente (documentado, no construido en esta fase)

- No se migró `QuoteListDialog.tsx` ni `AssignmentDialog.tsx` — quedan
  alcanzables solo desde el flujo externo (el botón que los abre ya no
  existe para solicitudes internas), no fue necesario tocarlos.
- No existe todavía una vista "Mis solicitudes internas" filtrada para
  técnicos — igual que documentado en [[operation-members-roles]], un
  técnico ve el mismo listado de solicitudes/órdenes que el resto de su
  organización, no uno acotado a las que tiene asignadas.
