# Activos: fundación tenant-aware (Fase 1)

Convierte el módulo Activos de mock/local a un modelo productivo, tenant-aware,
sin integrarlo todavía con Solicitudes. Migración:
`supabase/migrations/20260826234732_assets_tenant_aware_foundation.sql`.

## Modelo de datos

Jerarquía flexible en una única tabla auto-referenciada, no una tabla por nivel:

```
organizations (tenant real)
└── client_branches (sucursal/sede, opcional por nodo)
    └── assets (parent_asset_id, niveles ilimitados)
        ├── node_type: structure | site | area | system | fleet
        │              | equipment | component | subcomponent
```

- `asset_categories`: catálogo opcional de clasificación por organización,
  también jerárquico (`parent_category_id`). Único por
  `(organization_id, lower(name))`.
- `assets`: nodo del árbol. `organization_id` (tenant), `branch_id` (FK a
  `client_branches`, nullable), `parent_asset_id` (FK a sí misma, nullable),
  `asset_category_id` (nullable), `node_type`/`status`/`criticality`
  restringidos por `CHECK`, datos técnicos fijos comunes (fabricante, modelo,
  N° serie, código de barras, QR, fechas) + `technical_data`/`metadata` en
  `jsonb` para lo específico de cada tipo de activo.
- `asset_documents`: adjuntos por activo (aún sin subida real de archivos en
  esta fase).
- `asset_events`: bitácora (`created`, `archived`, y lo que se agregue luego).

**"Empresa/sector/flota" del árbol de negocio NO son `organizations`.** Son
simplemente nodos `assets` con distinto `node_type` bajo el mismo
`organization_id`. `organizations` sigue siendo exclusivamente el tenant real.

### Trigger de consistencia

`check_asset_consistency` (en `assets`, `BEFORE INSERT OR UPDATE`) exige que,
si están presentes, `parent_asset_id`, `asset_category_id` y `branch_id`
pertenezcan al mismo `organization_id` que la fila. `check_asset_child_organization`
aplica el mismo control en `asset_documents`/`asset_events` contra el
`organization_id` del `asset_id` referenciado. Ambos corren como
`SECURITY INVOKER` (no `DEFINER`): las mismas policies de `SELECT` que ya
aplican al usuario son suficientes para resolver estas validaciones, así que no
se introduce ninguna escalación de privilegios.

## RLS

Habilitada en las 4 tablas. Reutiliza las funciones ya existentes de
`20260717224621_multitenant_foundation.sql`:

- `SELECT`: `is_platform_admin()` OR `is_organization_member(organization_id)`.
- `INSERT`/`UPDATE`: `is_platform_admin()` OR
  `has_organization_role(organization_id, ['owner','admin','manager'])`.
- Sin policy de `DELETE` en ninguna tabla. El archivado es lógico:
  `assets.status = 'archived'`.

Grants: `SELECT, INSERT, UPDATE` a `authenticated` en las 4 tablas (necesario
para que PostgREST evalúe RLS). **Nada** a `anon`.

## Frontend

- `src/types/asset.ts`: tipos limpios (`Asset`, `AssetCategory`,
  `AssetDocument`, `AssetEvent`, `AssetNodeType`, `AssetStatus`,
  `AssetCriticality`, `AssetTreeNode`), independientes del `Database` generado
  (mismo patrón que `src/types/organization.ts`).
- `src/hooks/useAssets.ts`: carga `assets`/`asset_categories` de
  `currentOrganization`, arma el árbol en memoria desde `parent_asset_id`,
  expone `createAsset`, `updateAsset`, `archiveAsset`, `createCategory`.
  Inserta un `asset_events` básico al crear (`created`) y archivar
  (`archived`). Sin `service_role`, sin tablas legacy.
- `src/components/assets/AssetsView.tsx` (nuevo): dueño único de la instancia
  de `useAssets()` para que el árbol y el detalle no se desincronicen (p. ej.
  archivar desde el detalle se refleja de inmediato en el árbol). Carga además
  las sucursales activas de la organización para el selector opcional del
  formulario de alta.
- `src/components/assets/AssetTree.tsx` y `AssetDetail.tsx`: ahora reciben los
  datos por props (ya no llaman a Supabase ni usan `mockAssets`). El árbol
  permite crear nodo raíz o subactivo (con Nombre, Tipo de nodo, Estado,
  Sucursal y Categoría opcionales), oculta archivados por defecto (toggle "Ver
  archivados"), y traduce los estados a español. El detalle muestra los campos
  reales del activo seleccionado y permite archivar (`status = 'archived'`).
  No se implementa subida de imagen ni generación real de QR — el bloque QR
  queda como placeholder si `qr_code` está vacío.

### Acceso

- `Sidebar.tsx` / `Dashboard.tsx`: el ítem "Activos" y la vista ya no dependen
  del rol legacy `'cliente'`. Se muestran solo si
  `currentOrganization.organizationType === 'client_company'`.
- Dentro del módulo, `owner`/`admin`/`manager` de esa organización pueden
  crear/editar/archivar; el resto de roles activos (`requester`, `viewer`,
  etc.) solo pueden ver — coincide exactamente con la RLS de `INSERT`/`UPDATE`.
- Una organización `platform_admin` o `provider_company` no ve "Activos" en
  esta fase.

## Pendiente para fases posteriores

- Integración con `requests`/`request_details`: agregar `asset_id` y
  reemplazar los `EQUIPMENT_OPTIONS`/`SUB_EQUIPMENT_OPTIONS` hardcodeados de
  `RequestForm.tsx` por un selector de activos reales. No se tocó en esta fase.
- Subida real de documentos/imágenes (Storage), generación y lectura de QR.
- UI para `asset_categories` (por ahora solo `createCategory` existe en el
  hook; no hay pantalla dedicada de alta de categorías).
- Limpieza de código muerto: `src/pages/Index.tsx` y
  `src/components/tickets/TicketList.tsx` no están en las rutas de `App.tsx` y
  no se actualizaron a la nueva firma de `AssetTree`/`AssetDetail` (ver nota en
  "Validaciones" más abajo). Se recomienda eliminarlos en una fase de limpieza
  dedicada, no en esta.

## Validaciones ejecutadas

- `supabase db reset --local --no-seed --yes`: aplicó la migración nueva sin
  errores sobre el resto del historial de migraciones.
- `supabase gen types typescript --local > src/integrations/supabase/types.ts`:
  regenerado; incluye `assets`, `asset_categories`, `asset_documents`,
  `asset_events` con sus `Relationships` (incluye `branch_id → client_branches`
  y `parent_asset_id → assets`).
- `npm run build`: exitoso.
- `npx tsc -p tsconfig.app.json --noEmit`: confirma que los únicos errores de
  tipos nuevos introducidos están en `src/pages/Index.tsx` (código muerto, no
  enrutado), por seguir usando la firma anterior de `AssetTree`/`AssetDetail`.
  No se corrigió a propósito: esta fase tiene prohibido borrar o tocar código
  legacy/muerto. `npm run build` no falla porque Vite no type-checka todo el
  grafo como lo hace `tsc`. Los demás errores que reporta `tsc` (en
  `AdminConsole.tsx`, `BranchesList.tsx`, `QuoteListDialog.tsx`) son
  preexistentes y no están relacionados con este cambio.
- `git diff --check`: sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: sin resultados.

## Prueba manual sugerida

1. Iniciar sesión como usuario con membresía activa en una organización
   `client_company` (owner/admin/manager).
2. Verificar que "Activos" aparece en el Sidebar y que la vista carga el
   estado vacío ("Aún no tienes activos registrados...").
3. Crear un activo raíz (p. ej. "EMPRESA SECTOR TRANSPORTE"), luego un
   subactivo bajo ese nodo (p. ej. "FLOTA DE AUTOBUSES"), y un tercer nivel
   (p. ej. "BUS MERCEDES BENZ - 01").
4. Seleccionar el activo hoja y confirmar que el panel de detalle muestra sus
   datos reales.
5. Archivar el activo hoja y confirmar que desaparece del árbol por defecto,
   y que reaparece marcado como "Archivado" al activar "Ver archivados".
6. Iniciar sesión con un rol `requester`/`viewer` de la misma organización y
   confirmar que puede ver el árbol pero no tiene botones de alta/archivado.
7. Iniciar sesión con una organización `provider_company` o `platform_admin`
   activa y confirmar que "Activos" no aparece en el Sidebar.
