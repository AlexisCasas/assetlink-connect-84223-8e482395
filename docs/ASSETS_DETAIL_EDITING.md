# Activos: edición avanzada del detalle

Agrega edición real al panel derecho del módulo Activos (`AssetDetail.tsx`),
sobre el hook productivo `useAssets()` (`docs/ASSETS_PRODUCTIVE_HOOK.md`) y la
fundación tenant-aware (`docs/ASSETS_TENANT_AWARE_FOUNDATION.md`).
**Frontend/data layer únicamente**: sin cambios de RLS, Edge Functions,
`service_role` ni modelo multi-tenant.

## Diagnóstico: ¿hizo falta migración?

**No.** `public.assets` (migración `20260826234732_assets_tenant_aware_foundation.sql`,
Fase 1) ya incluía las 7 columnas técnicas necesarias:

| Columna | Tipo | Ya existía |
|---|---|---|
| `manufacturer` | `text` | ✅ |
| `model` | `text` | ✅ |
| `serial_number` | `text` | ✅ |
| `purchase_date` | `date` | ✅ |
| `warranty_until` | `date` | ✅ |
| `barcode` | `text` | ✅ |
| `location_text` | `text` | ✅ |

Confirmado tanto en la migración como en `src/integrations/supabase/types.ts`
(ya generado con estas columnas desde Fase 1). No se creó ninguna migración
nueva, no se ejecutó `supabase db reset` ni `supabase gen types` en esta fase.

## Campos editables

Todos manejados por un único formulario en `AssetDetail.tsx`, organizado en 3
pestañas (shadcn `Tabs`) para no alargar el panel:

| Pestaña | Campos |
|---|---|
| **General** | `name` (obligatorio), `nodeType`, `status` (activo/mantenimiento/inactivo — archivar/restaurar usan sus propias acciones, no este selector), `code`, `description` |
| **Técnica** | `manufacturer`, `model`, `serialNumber`, `barcode`, `criticality`, `purchaseDate`, `warrantyUntil` |
| **Ubicación / clasificación** | `branchId` (sucursales activas de la organización), `assetCategoryId` (solo si hay categorías cargadas), `locationText` |

`parentAssetId` no se expone en este formulario (mover un nodo en el árbol
queda fuera de alcance de esta fase; no se pidió y agrega riesgo de ciclos).

## Flujo de UI

- **Lectura (default)**: igual que antes — no se rediseñó el panel de solo
  lectura. Se agregó únicamente el botón **"Editar"**, visible solo si
  `canManageAssets` es `true` y `asset.status !== 'archived'`.
- **Edición**: clic en "Editar" reemplaza el contenido por el formulario en
  pestañas con los valores actuales precargados. Botones **"Guardar
  cambios"** (deshabilitado si `name` está vacío o si `state.saving` es
  `true`, con texto "Guardando…") y **"Cancelar"** (descarta cambios, vuelve
  a modo lectura sin llamar a Supabase).
- **Activo archivado**: no se muestra "Editar". Solo aparece "Restaurar" (ya
  existente desde la fase anterior) si `canManageAssets`.
- **`canManageAssets = false`**: solo lectura, sin "Editar"/"Archivar"/
  "Restaurar" — sin cambios respecto a las fases previas.
- **Cambio de selección durante edición**: si el usuario selecciona otro
  activo en el árbol mientras edita, el formulario se descarta
  automáticamente (`useEffect` sobre `selectedAsset?.id`) para no mostrar un
  formulario de un activo distinto al que ahora se ve.

## Hook (`useAssets.ts` / `types/asset.ts`)

- `CreateAssetInput` (y por lo tanto `UpdateAssetInput = Partial<CreateAssetInput>`)
  ganó `manufacturer`, `model`, `serialNumber`, `barcode`, `purchaseDate`,
  `warrantyUntil`, `locationText`.
- `createAsset()`/`updateAsset()` mapean estos campos camelCase → columnas
  snake_case reales (`serial_number`, `purchase_date`, etc.).
- Validaciones agregadas en `validateAssetInput` (compartida por create y
  update): `purchaseDate`/`warrantyUntil`, si se envían, deben ser fechas
  parseables (`Date.parse`) o se rechaza con "La fecha de compra/garantía no
  es válida." — igual que las validaciones ya existentes de `name`,
  `nodeType`, `status`, `criticality`, `parentAssetId`.
- `updateAsset()` sigue bloqueado por `canManageAssets` igual que antes (sin
  cambios en esa guardia); `archiveAsset`/`restoreAsset` siguen reusando la
  misma mutación de actualización con su propio `event_type`/mensaje de
  fallo, sin tocarse en esta fase.
- Guardar exitoso: `invalidateQueries(['assets', organizationId])` (mecanismo
  ya existente) + evento `event_type: 'updated'` en `asset_events`
  (best-effort, no bloquea el resultado si falla, no loguea el payload).

## Nuevo: `src/lib/assetLabels.ts`

Antes `AssetTree.tsx` y `AssetDetail.tsx` (y ahora también el formulario de
edición) necesitaban las mismas listas de tipos de nodo/criticidad. Se
centralizaron en un archivo compartido: `ASSET_NODE_TYPE_ORDER`,
`ASSET_NODE_TYPE_LABELS`, `ASSET_EDITABLE_STATUSES`, `ASSET_STATUS_LABELS`,
`ASSET_CRITICALITY_ORDER`, `ASSET_CRITICALITY_LABELS`,
`getAssetStatusBadgeClass`. El badge de solo-lectura de `AssetDetail`
mantiene su propio texto ("Habilitado" en vez de "Activo"), una decisión de
presentación ya existente de fases anteriores que esta fase no tocó.

## UX de feedback

- **Éxito**: toast (`useToast`, patrón ya usado en 18+ archivos del
  proyecto — `Login.tsx`, `RequestForm.tsx`, etc.) con confirmación, y el
  formulario vuelve a modo lectura automáticamente.
- **Error**: toast destructivo genérico ("Revisa los datos e inténtalo
  nuevamente.") — evita depender de leer `state.error` justo después de un
  `await` dentro del mismo callback (closure obsoleta), que sí se resuelve
  correctamente al re-renderizar. Por eso, además del toast, el mensaje
  preciso de `state.error` (p. ej. "El nombre es obligatorio.", "No tienes
  permisos para gestionar activos.", "No se pudo actualizar el activo.") se
  muestra en línea dentro del formulario mientras `isEditing` es `true`.
- **Guardando**: el botón "Guardar cambios" usa `state.saving` (ya expuesto
  por el hook) para deshabilitarse y mostrar "Guardando…".

## Permisos (sin cambios respecto a la fase anterior)

| Rol / organización | Ver Activos | Editar/Archivar/Restaurar |
|---|---|---|
| `owner`/`admin`/`manager` de `client_company` | ✅ | ✅ |
| `requester`/`viewer`/otros de `client_company` | ✅ | ❌ (solo lectura) |
| `provider_company` | ❌ | ❌ |
| `platform_admin` (sobre su propia organización) | ❌ | ❌ |

Reglas derivadas de `canViewAssets`/`canManageAssets` del hook (sin tocar
`AuthContext.tsx`), espejo de la RLS ya existente
(`is_organization_member`/`has_organization_role(['owner','admin','manager'])`).
No se modificó ninguna policy.

## Pendiente / riesgos conocidos

- No hay edición de `parentAssetId` (mover un nodo) — fuera de alcance.
- El botón "Editar" no está disponible para archivados; si se necesita editar
  un archivado en el futuro habría que decidir el flujo (¿restaurar primero?).
- `src/pages/Index.tsx` (código muerto, no enrutado) sigue sin actualizarse a
  las firmas de `AssetTree`/`AssetDetail` — mismo caso ya documentado en
  fases anteriores, confirmado que no generó *nuevos* errores de tipos.

## Validaciones ejecutadas

- `git status --short`: working tree limpio al iniciar, rama correcta
  (`feature/assets-detail-editing`, descendiente de `productization/mvp`
  post PR #31).
- `npm run build`: ✅ exitoso.
- `git diff --check`: ✅ sin errores reales.
- `git grep -n "SUPABASE_SERVICE_ROLE_KEY\|service_role" src`: ✅ sin resultados.
- No aplica `supabase db reset --local` ni `supabase gen types typescript
  --local` — no hubo migración.
- Extra (no pedido, usado para verificar que no se rompió nada):
  `npx tsc -p tsconfig.app.json --noEmit` — mismos errores preexistentes ya
  documentados (`AdminConsole.tsx`, `BranchesList.tsx`,
  `QuoteListDialog.tsx`, `src/pages/Index.tsx`), ningún error nuevo.

## Checklist manual de prueba

Con un usuario **owner/admin/manager** de una organización `client_company`:

1. Entrar a `#assets`, seleccionar un activo no archivado.
2. Confirmar que aparece el botón "Editar" junto a "Archivar".
3. Clic en "Editar" → se abren las 3 pestañas (General / Técnica /
   Ubicación y clasificación) con los valores actuales precargados.
4. Cambiar nombre, tipo de nodo, estado, fabricante, modelo, N° de serie,
   código de barras, criticidad, fecha de compra, garantía, sucursal,
   categoría (si hay) y ubicación en texto libre.
5. Clic en "Guardar cambios" → botón muestra "Guardando…", luego toast de
   éxito, el panel vuelve a modo lectura mostrando los valores nuevos, y el
   nombre/estado actualizados también se reflejan en el árbol de la
   izquierda (sin recargar la página).
6. Repetir con "Cancelar" en vez de guardar → confirmar que no se persiste
   nada y el panel vuelve a mostrar los valores originales.
7. Intentar guardar con el nombre vacío → toast de error, no se llama a
   Supabase.
8. Seleccionar otro activo mientras se está editando el primero → confirmar
   que el formulario se cierra solo (no queda mezclado con el activo nuevo).
9. Archivar un activo → confirmar que "Editar" desaparece y solo queda
   "Restaurar".
10. Restaurar el activo → confirmar que "Editar" vuelve a aparecer.

Con un usuario **requester/viewer** de la misma organización:

11. Confirmar que puede ver el detalle del activo pero no aparece ningún
    botón "Editar"/"Archivar"/"Restaurar".

Con una organización **provider_company** o **platform_admin** activa:

12. Confirmar que el módulo "Activos" no aparece (sin cambios respecto a
    fases anteriores).
