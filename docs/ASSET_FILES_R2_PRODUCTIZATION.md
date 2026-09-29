# Fotos y documentos de activos en Cloudflare R2 (Fase 1 · Punto 10)

Convierte la base de R2 del Punto 7 (`docs/R2_FOUNDATION.md`) en una
funcionalidad de producto: foto principal, galería de fotos y documentos PDF
en la ficha del activo (`AssetDetail`), para miembros directos del cliente y
para Facility Managers delegados (9C.1).

- Migración: `supabase/migrations/20260929132425_asset_files_productization.sql`
  (toda la SQL del punto vive solo aquí).
- Pruebas: `supabase/tests/asset_files_productization.test.sql` (suite
  dedicada) y `supabase/tests/asset_file_access_authorization.test.sql`
  (Punto 7, ampliada con casos FM).
- Edge Function: `supabase/functions/asset-files/index.ts`.
- Frontend: `src/lib/assetFiles.ts` (única API), `src/hooks/useAssetFiles.ts`,
  `src/components/assets/AssetFilesPanel.tsx`, `AssetDetail.tsx`,
  `useAssetScope.ts`.

Se mantiene todo lo del Punto 7: bucket privado, URLs firmadas de 300 s,
aislamiento por tenant, ningún secreto de R2 en el frontend, autorización en
el backend y keys generadas en el servidor.

## 1. Modelo de metadata: `asset_documents`

La tabla ya existía (sin uso real: ninguna función ni pantalla la escribía).
Se amplía de forma compatible:

| Columna | Uso |
|---|---|
| `kind` | `photo` / `document`. `NULL` marca una fila legada (pre-R2), que el producto no lista |
| `content_type` | MIME de la intención de subida; se compara con el real |
| `size_bytes` | tamaño **real** (HEAD de R2), nunca el declarado |
| `etag` | ETag real de R2 |
| `status` | `pending` → `available` / `failed`; `deleting` durante el borrado |
| `is_primary` | foto principal del activo |
| `confirmed_at` | momento en que pasó a `available` |
| `updated_at` | con trigger `touch_updated_at()` |
| `storage_path` | la key de R2. **Interna**: nunca sale de la base de datos ni de la Edge Function |
| `file_url` | siempre `NULL` en filas R2 (nunca se persiste una URL) |

Constraints e índices:

- `asset_documents_kind_check`, `_status_check`, `_size_bytes_check`;
- `_primary_photo_check`: solo una foto `available` puede ser principal;
- `_r2_shape_check`: una fila R2 tiene `file_url` NULL, `content_type` y
  `storage_path` presentes, y su key cumple
  `organizations/<org>/assets/<asset>/(photos|documents)/…` con la misma
  organización, activo y tipo de la fila;
- `_available_confirmed_check`: `available` exige `confirmed_at`;
- índice único `asset_documents_storage_path_key`;
- índice único parcial `asset_documents_one_primary_photo` (una principal
  por activo);
- índice `idx_asset_documents_asset_kind_status`.

## 2. Escritura: solo server-side

- Se eliminan las policies raw de INSERT/UPDATE de managers y se hace
  `REVOKE INSERT, UPDATE, DELETE` a `anon` y `authenticated`. Se mantiene la
  policy de SELECT para miembros directos.
- **No existe** una policy raw para el FM sobre `asset_documents`: el FM solo
  llega a los archivos vía RPCs y la Edge Function.
- Las transiciones de estado las hacen funciones ejecutables **solo por
  `service_role`** (`asset_file_mark_available`, `asset_file_begin_delete`,
  `asset_file_finish_delete`, `asset_file_mark_failed`), que la Edge Function
  llama **después** de autorizar el JWT del caller. `service_role` nunca
  decide autorización.
- `organization_id`, `storage_path` y `uploaded_by_user_id` los deriva el
  servidor. Si el navegador los envía, se ignoran.
- **Privilegios explícitos de `service_role`:** `SELECT, INSERT` en
  `asset_documents` y `SELECT` en `assets`, nada más.
  - Con estos privilegios, `asset-files` lee la fila interna y crea la fila
    `pending`.
  - El `SELECT` en `assets` lo exige el trigger histórico
    `check_asset_child_organization` (SECURITY INVOKER, `BEFORE INSERT`).
  - **Hallazgo de la validación final:** el ACL por defecto de las tablas
    varía por entorno. Una base local reseteada con Supabase CLI 2.106 no da
    DML a `service_role`; la 2.118 sí. Sin estos GRANT, `create-upload`
    fallaba con `42501` en el entorno estricto, y las primeras pruebas no lo
    vieron porque corrían sobre un ACL más permisivo.
  - La suite lo prueba con una inserción real como `service_role`, que se
    revierte al final.

## 3. Autorización

`authorize_asset_file_access(asset_id, operation)` (`SECURITY DEFINER`,
`SET search_path = ''`, `anon` sin `EXECUTE`):

| Operación | Directo (sin cambios desde el Punto 7) | FM delegado (9C.1) |
|---|---|---|
| `read` | platform admin o cualquier miembro activo del cliente | `assets.view`, roles FM owner/admin/manager/technician |
| `write` / `delete` | platform admin o owner/admin/manager del cliente | `assets.view` + `assets.manage`, roles FM owner/admin/manager |

- La rama FM usa `has_facility_management_operational_access_all`, que
  exige relación activa, miembro asignado, membresía activa, rol y **todos**
  los permisos en la misma relación.
- Viewer y requester del FM no acceden, y tampoco un miembro no asignado.
- **Archivado:** se puede leer; nunca se puede escribir, borrar ni marcar
  principal, para nadie (incluido el owner y el platform admin).
- `authorize_asset_file_operation(file_id, operation)`: contrato por
  archivo. Un archivo inexistente y un archivo de un activo que el caller no
  puede leer responden igual (`File not found`), así que no hay enumeración
  entre tenants.
- `can_access_asset_files` es un envoltorio booleano interno, sin grants a
  roles de API.

## 4. RPCs

- `get_asset_files(asset_id)`: listado minimizado (`id, kind, name,
  content_type, size_bytes, status, is_primary, created_at, confirmed_at`).
  Nunca `storage_path`, `file_url` ni `uploaded_by_user_id`. Todos ven los
  `available`; quien puede escribir en el activo ve además
  `pending`/`failed`/`deleting` para poder gestionarlos.
- `set_asset_primary_photo(file_id)`: autoriza `write`, bloquea el activo
  (`FOR UPDATE`) y cambia la principal de forma atómica. Solo acepta una foto
  `available`.

## 5. Edge Function `asset-files`: contrato por `file_id`

| Acción | Entrada | Resultado |
|---|---|---|
| `create-upload` | `asset_id, kind, name, content_type, size_bytes` | valida nombre, MIME y tamaño declarado → autoriza `write` → key en servidor → fila `pending` → PUT firmado (300 s). Devuelve `{file_id, upload_url, expires_at, required_headers}`, nunca la key |
| `confirm-upload` | `file_id` | HEAD real → tamaño real → `Content-Type` real → magic bytes → `available` |
| `create-download` | `file_id` | solo `available`; GET firmado (300 s). Foto `inline`; PDF `attachment` con nombre ASCII seguro (se quitan los acentos: `Manual técnico.pdf` → `Manual tecnico.pdf`) |
| `delete` | `file_id` | `deleting` → DELETE en R2 (server-side, nunca firmado) → fila eliminada |

- Errores: `42501` → 403, `File not found`/`Asset not found` → 404, un estado
  no válido → 409, contenido inválido → 422, error de R2 en el borrado → 502.
- Nunca se registran URLs firmadas, secretos ni la cabecera Authorization.
- `authorizeFile` cruza la organización de la fila con la organización
  autorizada, y la key parseada (organización, activo, tipo y extensión)
  con la fila.

## 6. Ciclo de vida y reconciliación

```
create-upload ─▶ pending ──PUT──▶ confirm-upload ─▶ available ─▶ delete ─▶ deleting ─▶ (fila borrada)
                    │                   │
                    │ (URL no usada)     └─ tamaño/tipo/bytes inválidos ─▶ objeto borrado + failed
                    └─ sigue pending (confirm = 404, nunca available)
```

- **PUT no usado:** `confirm-upload` responde 404 y la fila queda `pending`.
  Nunca aparece en la galería; se ve como "En proceso" para quien gestiona.
- **Contenido inválido:** se borra el objeto de R2 y la fila pasa a `failed`
  (422). Un `failed` nunca se puede descargar.
- **Fallo de la BD tras un PUT válido:** 500 y la fila sigue `pending`; el
  objeto es detectable y reintentar `confirm-upload` es idempotente.
- **Fallo de R2 al borrar:** 502 y la fila queda `deleting`; reintentar
  `delete` lo completa.
- **Objeto ya ausente en R2:** el borrado se completa igual (idempotente).
- Un barrido de reconciliación (`pending`/`deleting` antiguos, objetos
  huérfanos) queda como deuda; hoy es manual.

## 7. Foto principal

- La primera foto `available` de un activo pasa a ser principal
  automáticamente.
- Al borrar la principal se promueve la foto `available` más antigua
  (`created_at`, `id`).
- Se cambia con `set_asset_primary_photo`. Los documentos nunca pueden ser
  principales (constraint).

## 8. Frontend

- `AssetScope` suma `canViewFiles` y `canManageFiles`:
  - directo: `canViewAssets` / `canManageAssets`;
  - delegado: `assets.view` / capacidad de gestión de activos del cliente.
  - En la ficha, además, `canManageFiles` exige que el activo no esté
    archivado.
- **Cabecera de AssetDetail:** foto principal R2 → `assets.image_url` legado
  → `/placeholder.svg`. El botón de cámara sube una foto solo con
  `canManageFiles`.
- **Pestaña "Fotos y documentos"** (`AssetFilesPanel`):
  - galería con insignia "Principal" y acciones Abrir / Marcar como
    principal / Eliminar;
  - lista de PDFs con Descargar / Eliminar;
  - sección "En proceso o con errores" para quien gestiona;
  - el borrado pide confirmación.
- **Etapas reales de subida:** Preparando → Subiendo → Validando →
  Completado (sin porcentajes ficticios).
- **Validación temprana en UI:** JPG/PNG/WEBP hasta 10 MB y PDF hasta 25 MB.
  El backend lo vuelve a validar todo con el objeto real.
- **URLs firmadas solo en memoria** (React Query, 4 min):
  - nunca en la BD, en `localStorage` ni en `sessionStorage`;
  - cada "Descargar" y cada "Abrir" firma una URL nueva;
  - si una foto falla (p. ej. URL vencida), se vuelve a firmar **una sola
    vez**, y el `<img>` se desmonta durante esa nueva firma, de modo que el
    navegador siempre repite la petición aunque la nueva URL coincida
    byte a byte con la anterior (`X-Amz-Date` tiene resolución de 1 s).

## 9. Formatos y límites

| Tipo | MIME | Límite |
|---|---|---|
| Foto | `image/jpeg`, `image/png`, `image/webp` | 10 MB |
| Documento | `application/pdf` | 25 MB |

Nunca SVG, HTML, JS ni Office. El nombre visible (hasta 255 caracteres, sin
caracteres de control) es solo metadata: nunca forma parte de la key.

## 10. `assets.image_url` legado

Se mantiene como **fallback de compatibilidad**: no se borra y el producto no
escribe valores nuevos. Hoy producción tiene 0 valores, pero la seguridad no
depende de eso. El PDF del activo (`buildAssetReportData`) todavía usa solo
este campo (deuda).

## 11. Verificación

- **pgTAP:**
  - suite dedicada: 101/101, en estas secciones: estructura y grants
    (incluida la inserción `pending` real como `service_role`), acceso
    directo, lectura FM, escritura FM, autorización por archivo sin
    enumeración, `get_asset_files`, foto principal, hardening raw (DML
    real), invariantes y ciclo de vida como `service_role`;
  - suite del Punto 7 ampliada a 36 (6 casos FM nuevos);
  - las suites 9C.1 y 9C.2 se actualizaron para el nuevo contrato.
- **Unitarias** (código real de `_shared/`, esbuild + Node, sin red): 69
  del Punto 7 + 14 del Punto 10 (nombre visible, allowlist cerrada, límites).
- **E2E real contra R2 DEV** (`one-facility-dev-private`, `supabase functions
  serve`, fixtures solo en Supabase local), que cubre:
  - happy path del owner con hash idéntico;
  - segunda foto, cambio de principal y PDF;
  - ciclo completo del FM manager;
  - FM technician (descarga sí, escritura no);
  - FM no asignado y cross-tenant (404 idéntico al de un id aleatorio);
  - entradas inválidas;
  - magic bytes, PUT no usado, `Content-Type` distinto (403 de R2), objeto
    ausente y reintento desde `deleting`;
  - activo archivado;
  - auditoría de persistencia;
  - limpieza con `ListObjectsV2` → 0 objetos.
- **CORS en navegador real + smoke de UI** (Chromium, Vite en
  `http://localhost:8080`, Supabase local, bloqueo de `*.supabase.co` y de
  cualquier R2 que no sea el bucket DEV):
  - preflight + PUT 200 y GET de fotos directo a R2, sin errores de CORS;
  - owner directo, technician directo, FM manager, FM technician, archivado
    y fallback legado;
  - entradas inválidas rechazadas antes de cualquier petición, y HTML
    disfrazado de PNG marcado "Fallido";
  - nueva firma única tras fallo;
  - nada persistido en el almacenamiento web.
- Todo lo anterior se ejecutó sobre la base con el ACL **estricto** (CLI
  2.106): pgTAP 101/101 dedicada y 2007/2007 total; E2E real 69/69; smoke
  de UI 21/21. Las regresiones 9C.4, 9C.3, 9C.2, 9C.1 y 9B pasan.
- **Controles negativos A–N** (y O, el GRANT de `service_role`): cada
  mutación temporal hace fallar las pruebas, y todo se restauró.
  - K (persistir la URL firmada) solo se puede provocar si `service_role`
    tiene `UPDATE`, como en un ACL permisivo; con el ACL estricto el propio
    privilegio bloquea la escritura.

## 12. Fuera de alcance

- Adjuntos de solicitudes (`requests.image_urls`, `requests.document_urls`,
  `request_details.attachment_urls`), inspecciones, OT, proveedores y chat:
  no usan R2 todavía. El bloqueo 55000 de adjuntos de 9C.4 se mantiene.
- Hardening de los buckets legacy de Supabase Storage (ver
  `docs/R2_FOUNDATION.md`).
- Cotizaciones, OT y reportes delegados. 9C.5 / 9C.6 / 9C.7 siguen
  congelados: esta rama no toca nada de ellos.
