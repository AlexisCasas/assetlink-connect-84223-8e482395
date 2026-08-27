# Activos ↔ Solicitudes: integración productiva

Conecta el módulo productivo de Activos (`docs/ASSETS_TENANT_AWARE_FOUNDATION.md`,
`docs/ASSETS_PRODUCTIVE_HOOK.md`, `docs/ASSETS_DETAIL_EDITING.md`) con el flujo
de Solicitudes, para que una solicitud pueda apuntar a un `asset` real en vez
de depender solo de texto libre (`equipo`/`subequipo`).

## Diagnóstico

### Estructura real encontrada

- `public.requests`: sin columna para relacionar con un activo. Tenía
  `asset text NOT NULL` (texto libre, poblado hoy desde
  `details[0].equipment`, que a su vez sale de un picklist hardcodeado en
  `RequestForm.tsx`: `EQUIPMENT_OPTIONS`/`SUB_EQUIPMENT_OPTIONS`).
- `public.request_details`: `equipment`/`sub_equipment` como texto libre,
  por línea (1 a muchos por solicitud). Sin relación con `assets`.
- `public.quotes`, `public.work_orders`: no referencian ni activo ni equipo
  en absoluto; no hace falta tocarlos para esta fase.
- **No existía ninguna columna `asset_id` ni equivalente** en ninguna tabla
  de solicitudes. Confirmado con `git grep` sobre `supabase/migrations/` y
  `src/integrations/supabase/types.ts` antes de escribir la migración.

### RLS relevante (antes de esta fase)

- `requests` SELECT: policy `"authorized users can view requests"` →
  `can_user_read_request(id)` — permite: miembro activo de la organización
  dueña, `platform_admin`, o una organización `provider_company`/
  `facility_manager` cuando la solicitud es pública o tiene
  `request_provider_access` activo.
- `requests` INSERT: policy `"request creators can create organization
  requests"` → ya permite roles `owner`/`admin`/`manager`/`requester` de la
  organización (`client_company` en la práctica, ya que solo `RequestForm`
  las crea). **Ya cumplía el requisito de "owner/admin/manager/requester
  puede crear solicitudes"** — verificado leyendo la migración, no había que
  cambiar nada.
- `assets` SELECT: `is_organization_member(organization_id)` OR
  `is_platform_admin()` — **un proveedor nunca cumple esta condición**
  (no es miembro de la organización cliente), así que no puede leer la fila
  completa de `assets` aunque conozca su `asset_id` (que sí ve, porque es
  una columna más de `requests`, tabla que él sí puede leer vía
  `can_user_read_request`). Esto es exactamente el comportamiento deseado.

### Decisión de modelo: `requests.asset_id`

Se evaluaron tres opciones:

1. **`requests.asset_id`** (elegida) — un activo principal por solicitud,
   igual patrón que el ya existente `requests.branch_id`. Simple, MVP,
   coherente con que hoy una solicitud ya tiene "una" sucursal top-level.
2. `request_details.asset_id` — permitiría un activo distinto por línea,
   pero `request_details` sigue siendo texto libre legacy en esta fase y no
   se tocó (fuera de alcance); habría mezclado ambos modelos sin necesidad.
3. Tabla puente `request_assets` (N:M) — sobre-ingeniería para el caso de
   uso actual (una solicitud casi siempre refiere a un único activo/equipo
   físico); no hay ningún requisito de negocio hoy que pida múltiples
   activos por solicitud.

**Se usó la opción 1**, tal como sugería la decisión preferida del encargo.

## Migración

`supabase/migrations/20260827012124_requests_asset_id.sql`:

```sql
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS asset_id uuid NULL REFERENCES public.assets(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_requests_asset_id ON public.requests (asset_id);
```

Más un trigger `check_request_asset_organization` (`BEFORE INSERT OR
UPDATE` en `requests`), mismo patrón que `check_asset_consistency` de la
fundación de Activos: si `asset_id` no es nulo, exige que el activo
pertenezca al mismo `organization_id` que la solicitud. `SECURITY INVOKER`
(no `DEFINER`) — quien crea/edita la solicitud ya tiene acceso de lectura a
los `assets` de su propia organización, así que no hace falta escalar
privilegios.

**No se borró ninguna columna legacy** (`asset`, `request_details.equipment`/
`sub_equipment` siguen intactas). **No se agregaron permisos nuevos**: los
`GRANT` existentes sobre `public.requests` (tabla completa) ya cubren la
columna nueva.

## RLS: sin cambios

Justificado arriba — ni `requests` ni `assets` necesitaron nuevas policies.
La única policy que sí importa para la seguridad de esta integración es la
ya existente de `assets` (SELECT limitada a miembros de la organización): es
lo que garantiza que un proveedor nunca pueda leer la fila completa del
activo (fabricante, N° de serie, `technical_data`, etc.) aunque vea el
`asset_id` en la solicitud.

## Implementación

### `RequestForm.tsx` (clientes)

- Nuevo `src/components/requests/RequestAssetPicker.tsx`: combobox
  (Popover + Command, ya en el proyecto vía shadcn/ui, sin dependencias
  nuevas) que:
  - Llama a `useAssets()` (React Query dedupe la carga con cualquier otra
    instancia montada, p. ej. el módulo Activos, por clave de query).
  - Lista el árbol ya filtrado de archivados (`assetTree`, por defecto sin
    archivados) aplanado con ruta jerárquica (`src/lib/assetTree.ts`,
    `flattenAssetTree`/`buildAssetPathMap`, reutilizado también en
    `RequestList.tsx`).
  - Busca por nombre, código o N° de serie (valor compuesto pasado a cada
    `CommandItem`, filtrado por `cmdk`).
  - Permite dejar "Sin activo específico".
  - Si no hay activos: mensaje exacto pedido — *"Aún no tienes activos
    registrados. Puedes crear una solicitud sin activo o registrar activos
    desde el módulo Activos."*
  - Muestra loading/error del hook.
- Al guardar (`handleSubmit`): guarda `assetId`. Si el usuario tocó el
  selector en esta sesión (`assetTouched`), sobreescribe el campo legacy
  `asset` con `"<Tipo de nodo>: <Nombre>"` (p. ej. *"Equipo: BUS MERCEDES
  BENZ - 01"*); si no lo tocó (edición de una solicitud ya existente sin
  cambiar el activo), conserva el texto ya guardado en vez de pisarlo con el
  detalle de línea.

### `RequestList.tsx` / `OrderTable.tsx` (clientes — "Mis solicitudes")

- Nueva columna `asset` ("Activo asociado"), integrada al sistema existente
  de columnas visibles/orden persistido en `localStorage` (compatible con
  configuraciones ya guardadas: las claves nuevas caen a su default sin
  romper lo existente).
- Si `assetId` existe: usa `useAssets()` (mismo dedupe de React Query) para
  mostrar el **nombre actual** del activo (autocorrectivo si se renombra
  después) + su **ruta jerárquica corta**, con un ícono de paquete.
- Si no hay `assetId`: se comporta exactamente igual que antes (texto libre
  `asset` o "-").

### `ProviderRequestList.tsx` (proveedores) — sin nueva consulta

- La columna "Equipo" ya mostraba `request.asset` (ahora más descriptivo
  cuando viene de un activo real). Único cambio: un ícono junto al texto
  cuando `asset_id` no es nulo, para indicar visualmente "esto es un activo
  real del cliente" — dato ya presente en la fila (`select('*')` sobre
  `requests`, que el proveedor ya podía leer vía RLS), sin unir con
  `assets`.
- **No se expone** número de serie, fabricante, modelo ni `technical_data`
  al proveedor en ningún punto de este flujo.

### `QuoteListDialog.tsx` / cotizaciones / `work_orders`

- **Sin cambios.** No dependen de `asset`/`asset_id` para funcionar.
- Trazabilidad hasta `work_orders`: **ya alcanzable** sin ninguna columna
  nueva, vía `work_orders.request_id → requests.asset_id → assets`, para
  quien tenga permiso de leer ambas tablas (el cliente dueño, o
  `platform_admin`). No se agregó `asset_id` a `work_orders` porque sería
  redundante.

## Compatibilidad con solicitudes existentes

Toda solicitud creada antes de esta fase tiene `asset_id = NULL` (columna
nueva, `NULL` por defecto, sin backfill). Se comportan exactamente igual que
antes: la columna "Activo asociado" muestra el texto legacy (`asset` o "-"),
sin romper nada.

## Corrección: activo asociado en la vista detalle

La primera versión de esta integración guardaba y editaba `asset_id`
correctamente, pero **ninguna vista de detalle lo renderizaba** — el dato ya
llegaba completo (`selectedRequest.assetId` en el diálogo inline de
`RequestList.tsx`, `request.asset_id` en `RequestDetailDialog.tsx` vía
`select('*')`), solo faltaba el bloque visual. Se agregó
`src/components/requests/RequestAssetSummary.tsx`, un componente compartido
que:

- Llama a `useAssets()` (dedupe de React Query, sin nueva consulta insegura).
  Para el cliente dueño resuelve nombre actual + badge de tipo + ruta
  jerárquica. Para un proveedor, `canViewAssets` es `false` en su hook (no es
  `client_company`), así que la query ni siquiera se dispara y el componente
  cae automáticamente al texto denormalizado `request.asset` — nunca hay
  riesgo de exponer `serial_number`/`technical_data`.
- Si `assetId` existe pero no se puede resolver (proveedor, o carga en
  curso), muestra `request.asset` con la etiqueta pequeña "Activo vinculado".
- Si no hay `assetId` pero sí `asset` (legacy), muestra el texto tal cual.
- Si no hay ninguno, no renderiza nada (mismo comportamiento que antes).

Se integró en `RequestList.tsx` (diálogo "Ver solicitud" del cliente, entre
"Datos de Cabecera" y "Descripción") y en `RequestDetailDialog.tsx`
(proveedor, entre "Información General" e "Información Técnica" — se quitó
el campo "Equipo/Activo" duplicado de esa segunda card). Sin migración, sin
cambios de RLS, sin tocar el flujo de guardado.

## Limpieza del modal de detalle (Equipo/Subequipo/Área/Subárea)

El modal "Agregar Nuevo Detalle" pedía manualmente Equipo/Subequipo/Área/
Subárea desde picklists hardcodeados (`EQUIPMENT_OPTIONS`, etc., ya
eliminados), redundante ahora que la solicitud tiene un activo real via
`asset_id`. Cambios, todos en frontend, **sin migración nueva**
(`request_details.equipment/sub_equipment/area/sub_area` siguen existiendo
en la tabla, solo dejaron de pedirse en la UI):

- **UI eliminada**: los 4 selects desaparecen del modal. Queda solo
  Actividad/Partida, Materiales, Cantidad, U.M, Observación, Encargado,
  Delegado, Anexos (estos últimos cuatro sin cambios, siguen en el modelo).
- **Contexto de solo lectura**: si la solicitud tiene `assetId`, el modal
  muestra arriba "Detalle asociado a" (reutiliza `RequestAssetSummary` con
  `title` configurable) con nombre, badge de tipo y ruta — sin poder
  cambiar el activo desde ahí (eso sigue siendo exclusivo del selector de
  cabecera).
- **Payload de compatibilidad**: al guardar, `RequestForm.tsx` calcula una
  vez por solicitud `detailEquipmentFallback` (nombre del activo elegido, o
  el texto legado `request.asset` si no se tocó el selector) y
  `detailAreaFallback` (ruta jerárquica del activo recién elegido, o
  vacío), y los aplica **uniformemente a cada fila** de `request.details`
  en vez de pedirlos por fila. `sub_equipment`/`sub_area` siempre viajan
  vacíos. `RequestList.tsx` no cambió su inserción a `request_details` —
  ya recibe estos valores calculados desde `RequestForm`.
- **Listados/detalles existentes**: las columnas Equipo/Subequipo/Área/
  Subárea se quitaron de las tablas de detalle en `RequestForm.tsx`,
  `RequestList.tsx`, `OrderTable.tsx` (fila expandible) y
  `RequestDetailDialog.tsx`. Donde una fila antigua todavía tiene
  `equipment`/`area` guardados, se muestran como texto secundario pequeño
  bajo "Actividad", no como columnas — nada se borra ni se rompe.
- **`RequestAssetPicker`**: confirmado que ya no estaba limitado a
  `node_type = 'equipment'` (nunca filtró por tipo); solo se extendió su
  `onChange` para exponer también la ruta jerárquica del activo elegido,
  reutilizada en el cálculo de `detailAreaFallback`.

## Pendiente

- `request_details` (multi-línea, texto libre `equipment`/`sub_equipment`)
  no se integró — fuera de alcance de esta fase, ver "Decisión de modelo"
  arriba.
- No hay backfill de solicitudes históricas hacia activos reales (no hay
  forma automática de inferir cuál activo correspondía a un texto libre
  previo).
- Si en el futuro se necesita más de un activo por solicitud, la migración
  natural sería introducir `request_assets` (tabla puente) sin tocar
  `requests.asset_id` (se podría mantener como "activo principal").

## Validaciones ejecutadas

- `git status --short`: working tree limpio al iniciar, rama
  `feature/assets-requests-integration` correcta (descendiente exacta de
  `productization/mvp` tras el merge de PR #32).
- `supabase db reset --local --no-seed --yes`: migración aplicada sin
  errores sobre el resto del historial.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; `requests.asset_id: string | null` presente con su
  `Relationships` hacia `assets`.
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- Extra (no pedido, para verificar que no se rompió nada):
  `npx tsc -p tsconfig.app.json --noEmit` — mismos errores preexistentes ya
  documentados en fases anteriores (`AdminConsole.tsx`, `BranchesList.tsx`,
  `QuoteListDialog.tsx`, `src/pages/Index.tsx` código muerto), ningún error
  nuevo.

## Checklist manual de prueba

Con un usuario **owner/admin/manager/requester** de una organización
`client_company`:

1. Ir a "Mis solicitudes" → "Nueva solicitud".
2. Ver el selector "Activo asociado (opcional)". Si la organización no tiene
   activos: confirmar el mensaje exacto de empty state.
3. Con activos registrados: abrir el combobox, buscar por nombre, por
   código y por N° de serie; confirmar que los archivados no aparecen.
4. Seleccionar un activo → confirmar que el resumen (nombre + ruta) se
   muestra bajo el selector.
5. Completar el resto del formulario y enviar la solicitud.
6. En "Mis solicitudes", confirmar que la columna "Activo asociado" muestra
   el nombre y la ruta corta del activo elegido.
7. Editar esa misma solicitud sin tocar el selector de activo → guardar →
   confirmar que el activo asociado se mantiene igual.
8. Editar la solicitud y cambiar a "Sin activo específico" → guardar →
   confirmar que la columna vuelve a mostrar el texto libre/"-".
9. Crear una solicitud sin seleccionar ningún activo → confirmar que se
   comporta exactamente igual que antes de esta fase.

Con un usuario de una organización **provider_company**/**facility_manager**
con acceso a una solicitud pública o invitada:

10. En "Solicitudes", confirmar que la columna "Equipo" muestra el nombre
    del activo (vía el texto ya guardado) con el ícono indicador, **sin**
    poder ver número de serie, fabricante ni otros datos técnicos del
    activo (esos campos no aparecen en ningún diálogo de esta vista).

Con solicitudes creadas **antes** de esta fase (sin `asset_id`):

11. Confirmar que siguen abriéndose, editándose y mostrando su texto legacy
    con normalidad, sin errores.
