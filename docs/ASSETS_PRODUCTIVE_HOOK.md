# Activos: hook productivo (Fase 2)

Endurece la capa de datos del módulo Activos sobre la fundación creada en
`docs/ASSETS_TENANT_AWARE_FOUNDATION.md`. **Sin cambios de backend**: ninguna
migración, RLS, Edge Function ni `service_role` nuevos. Frontend/data layer
únicamente.

## API de `useAssets()`

```ts
const {
  assets,            // Asset[] — lista plana de la organización activa
  assetTree,         // AssetTreeNode[] — árbol ya filtrado por showArchived
  selectedAsset,     // Asset | null
  selectedAssetId,   // string | null
  categories,        // AssetCategory[]
  branches,          // ClientBranch[] (client_branches activas de la organización)
  loading,           // boolean combinado (assets + categories + branches)
  error,             // string | null, siempre un mensaje legible
  canViewAssets,     // boolean
  canManageAssets,   // boolean
  accessReason,      // string | undefined — por qué no puede ver/gestionar
  showArchived,      // boolean
  setShowArchived,   // (value: boolean) => void
  selectAsset,       // (assetId: string) => void
  clearSelection,    // () => void
  createAsset,       // (input: CreateAssetInput) => Promise<Asset | null>
  updateAsset,       // (assetId: string, changes: UpdateAssetInput) => Promise<boolean>
  archiveAsset,      // (assetId: string) => Promise<boolean>
  restoreAsset,      // (assetId: string) => Promise<boolean>
  refreshAssets,     // () => Promise<void>
  saving,            // boolean — alguna mutación en curso
} = useAssets();
```

`AssetsView` es el único componente que llama a `useAssets()`; pasa el
resultado completo como prop `state` a `AssetTree`/`AssetDetail`, que ya no
hacen fetch propio ni duplican permisos o selección. Esto evita la
desincronización que existía antes (archivar desde el detalle no siempre se
reflejaba igual en el árbol).

## React Query vs. `useState`/`useEffect`

Se migró a TanStack Query (`useQuery` para `assets`/`asset_categories`/
`client_branches`, `useMutation` para crear/actualizar/archivar/restaurar).
El proyecto ya tenía `QueryClientProvider` en `App.tsx` pero **ningún** hook
lo usaba todavía — esta es la primera vez que se aprovecha. Motivo:

- Claves de query por `organizationId` (`['assets', organizationId]`, etc.):
  cambiar de organización activa dispara refetch automático, sin efectos
  manuales.
- `invalidateQueries` tras cada mutación exitosa mantiene `assets` (y por lo
  tanto `assetTree`) consistente sin lógica de parcheo manual del estado.
- `useMutation` expone `isPending` de forma nativa, usado en `saving`.

No se tocó ningún otro hook del proyecto ni se agregó una dependencia nueva
(`@tanstack/react-query` ya estaba en `package.json`).

## Permisos

Derivados exclusivamente de `currentOrganization` y `currentMembership`
(`useAuth()`), sin tocar `AuthContext.tsx`:

| Condición | `canViewAssets` | `canManageAssets` |
|---|---|---|
| Sin `currentOrganization` | false | false |
| `organizationType` ≠ `client_company` (incluye `platform_admin` y `provider_company`) | false | false |
| `client_company` sin membresía activa | false | false |
| `client_company`, membresía activa, rol `requester`/`viewer`/etc. | **true** | false |
| `client_company`, membresía activa, rol `owner`/`admin`/`manager` | **true** | **true** |

`accessReason` trae el mensaje exacto a mostrar cuando `canViewAssets` es
`false` (usado por `AssetsView` para el estado "sin acceso"). Estas reglas
son un espejo de la RLS ya existente (`is_organization_member` para
`SELECT`, `has_organization_role(['owner','admin','manager'])` para
`INSERT`/`UPDATE`) — no abren nada que la base de datos ya no permitiera.

Una organización `platform_admin` nunca ve Activos como si fuera cliente: no
hay ningún atajo que la deje operar sobre "su propia" organización de
plataforma como si fuera `client_company`. Si en el futuro un platform admin
necesita entrar al perfil de una organización cliente, será un flujo nuevo
(no implementado aquí).

## Árbol y archivados

- Construcción O(n) desde `parent_asset_id`: cada asset se cuelga del
  `children[]` de su padre si el padre está en el set cargado; si no, se
  vuelve raíz. Esto ya cubre "padre no cargado/huérfano" sin romper nada.
- **Datos corruptos (ciclos)**: se agregó un recorrido acotado (pila +
  `Set` de visitados) desde las raíces reales. Cualquier nodo no alcanzado
  (solo posible si su cadena de padres forma un ciclo) se agrega como raíz
  extra en vez de desaparecer en silencio o arriesgar una recursión que no
  termine. La UI nunca puede colgarse por esto.
- Orden estable: `localeCompare(name)` con `id` como criterio de desempate,
  aplicado recursivamente en cada nivel.
- `showArchived = false` (default): oculta los activos archivados **y** todo
  lo que cuelgue de un padre archivado (un hijo activo no puede quedar
  "flotando" bajo un padre oculto). `showArchived = true`: se ve la
  jerarquía completa, incluida cualquier rama archivada.

## Validaciones antes de insertar/actualizar

En `createAsset`/`updateAsset` (y por extensión `archiveAsset`/
`restoreAsset`, que reutilizan la misma mutación de actualización):

- `name` obligatorio y no vacío (trim).
- `organization_id` siempre sale de `currentOrganization.id` — nunca del
  input del llamador, no existe forma de pasarlo desde afuera.
- `parent_asset_id`: si se especifica, debe existir en el `assets` ya
  cargado de la organización y no puede ser el propio activo.
- `node_type`, `status`, `criticality` (si viene) se validan contra las
  listas permitidas (las mismas que los `CHECK` de la migración).
- Sin `canManageAssets`, `createAsset`/`updateAsset`/`archiveAsset`/
  `restoreAsset` fallan de inmediato con "No tienes permisos para gestionar
  activos." sin llegar a Supabase.

## Eventos (`asset_events`)

- `createAsset` → `event_type = 'created'`.
- `updateAsset` (genérico) → `event_type = 'updated'`.
- `archiveAsset` → `event_type = 'archived'`.
- `restoreAsset` → `event_type = 'restored'`.

La inserción del evento es "best effort": va en un `try/catch` separado de
la operación principal, solo hace `console.error` con el mensaje de error de
Postgres (nunca el payload/input), y jamás hace que `createAsset`/
`updateAsset`/`archiveAsset`/`restoreAsset` devuelvan `false`/`null` por un
fallo de logging.

## Mensajes de error

`error` del hook siempre es texto legible, nunca el error crudo de
Supabase/PostgREST:

- "No se pudieron cargar los activos." / "...las categorías de activos." /
  "...las sucursales." (fallas de carga, una por recurso).
- "No tienes permisos para gestionar activos."
- "Selecciona una organización cliente."
- Mensajes de validación (`"El nombre es obligatorio."`, etc.).
- "No se pudo crear el activo." / "No se pudo actualizar el activo." /
  "No se pudo archivar el activo." / "No se pudo restaurar el activo."
  (fallback específico por operación si Supabase devuelve un error genérico).

## Componentes

`AssetTree`/`AssetDetail` ahora reciben una sola prop `state:
UseAssetsResult` en vez de ~8 props sueltas. Conservan solo estado de UI que
no pertenece a la capa de datos: nodos expandidos, apertura del diálogo de
alta y sus campos de formulario. No se rediseñó nada visualmente; el único
agregado funcional es el botón "Restaurar" en `AssetDetail` cuando el activo
seleccionado está archivado (para poder probar `restoreAsset` end-to-end).

## Pendiente

- Integración con `requests`/`request_details` (`asset_id`) — no tocado,
  como pedía esta fase.
- UI dedicada para `asset_categories` (el hook ya soporta `categories`, pero
  no hay pantalla de alta; sigue igual que en Fase 1).
- Limpieza de `src/pages/Index.tsx` y `src/components/tickets/TicketList.tsx`
  (código muerto, no enrutado): siguen sin actualizarse a la firma nueva de
  `AssetTree`/`AssetDetail` porque esta fase tampoco debía tocar/borrar
  legacy. `npx tsc -p tsconfig.app.json --noEmit` lo confirma como el único
  error de tipos *nuevo* introducido por este cambio (ver más abajo).

## Validaciones ejecutadas

- `git status --short`: working tree limpio al iniciar (ver nota sobre la
  rama base más abajo).
- `npm run build`: exitoso.
- `git diff --check`: sin errores reales (solo avisos de normalización
  LF→CRLF de git).
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: sin resultados.
- `npx tsc -p tsconfig.app.json --noEmit` (extra, no pedido por la
  validación obligatoria pero usado para confirmar que no se introdujeron
  errores de tipos nuevos): mismos 3 errores preexistentes y no relacionados
  (`AdminConsole.tsx`, `BranchesList.tsx`, `QuoteListDialog.tsx`) más los 3
  ya esperados en `src/pages/Index.tsx` (código muerto). Ningún error nuevo
  fuera de esos.

### Nota sobre la rama base

`feature/assets-productive-hook` se había creado desde el commit anterior a
la Fase 1 (no descendía de `feature/assets-tenant-aware-foundation`), por lo
que en disco no existían todavía `useAssets.ts`, `types/asset.ts`,
`AssetsView.tsx` ni la migración. Se detuvo el trabajo, se reportó, y con
confirmación explícita se hizo `git merge feature/assets-tenant-aware-foundation
--ff-only` (fast-forward limpio, sin conflictos, sin crear ninguna migración
nueva) antes de empezar la Fase 2.
