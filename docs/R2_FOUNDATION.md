# Cloudflare R2 Foundation (Fase 1 · Punto 7)

Infraestructura privada, tenant-aware y reutilizable para archivos del SaaS.
**No incluye UI** de fotos/documentos de activos — eso es Fase 1 · Punto 10.
Migración: `supabase/migrations/20260927012526_asset_file_access_authorization.sql`.
Pruebas: `supabase/tests/asset_file_access_authorization.test.sql`.

> **Punto 10 (hecho) reemplaza partes de este documento.** El producto
> (metadata en `asset_documents`, contrato por `file_id`, acceso delegado
> del FM, UI en AssetDetail) está en `docs/ASSET_FILES_R2_PRODUCTIZATION.md`.
> Cambios respecto de lo descrito aquí:
>
> - la Edge Function ya no recibe ni devuelve la `key`: todo después de
>   `create-upload` va por `file_id`, y la key vive solo en
>   `asset_documents.storage_path`, que es interno;
> - `authorize_asset_file_access` suma la rama delegada del FM (9C.1:
>   `assets.view` para leer; `assets.view` + `assets.manage` para escribir)
>   y pasa a `SET search_path = ''`;
> - el Punto 10 sí escribe metadata (`pending` → `available` / `failed`,
>   `deleting`), siempre server-side;
> - la prueba de CORS en un navegador real, pendiente abajo, se ejecutó en
>   el Punto 10 con Chromium sobre `http://localhost:8080`.
>
> El resto (secrets, bucket, key, MIME, magic bytes, firma del PUT) sigue
> vigente.

## Qué es y qué no es

Este punto entrega la capacidad de: pedir una URL firmada de subida, subir
directo a R2, confirmar la subida, pedir una URL firmada de descarga y
borrar — todo autorizado por tenant/rol, sin exponer ninguna credencial de
R2 al navegador. **No toca** `asset_documents`, `assets.image_url`,
`AssetDetail.tsx`, `useAssets.ts` ni los buckets legacy de Supabase Storage
(`request-documents`, `request-images`, `request-detail-attachments`,
`provider-documents`, `provider-logos`), que siguen existiendo sin cambios.
Ambos sistemas de almacenamiento coexisten: Supabase Storage para lo legacy,
R2 para activos y cargas futuras.

## Arquitectura

```
Browser ──JWT──▶ Edge Function asset-files
                    ├─ RPC authorize_asset_file_access (JWT del caller) ─▶ Postgres
                    ├─ genera la key en el servidor
                    └─ firma con aws4fetch (secretos solo aquí)
Browser ◀── URL firmada ──┘
Browser ──PUT/GET directo──▶ R2 (bucket privado)
Edge Function ──HEAD / Range GET / DELETE server-side──▶ R2
```

`asset-files` llama `authorize_asset_file_access` **con el JWT del caller**
(`createCallerClient`, nunca `service_role`) — mismo patrón que Fase 1 ·
Punto 6B: la autorización de tenant/rol vive una sola vez, en SQL, y se
prueba con pgTAP independientemente de este archivo.

## SDK: `npm:aws4fetch@1.0.20`

Verificado antes de usarlo:
```
npm view aws4fetch version      → 1.0.20
npm view aws4fetch license      → MIT
npm view aws4fetch dependencies → (ninguna)
```
Sin dependencias, ~65 KB, API mínima (`AwsClient.sign()` para URLs firmadas,
`AwsClient.fetch()` para HEAD/GET-range/DELETE ejecutados directamente por
el servidor) y es el ejemplo oficial de Cloudflare para R2. Se importa como
`npm:aws4fetch@1.0.20` **únicamente** dentro de `supabase/functions/_shared/r2.ts`
(Edge Runtime) — nunca entra al bundle del frontend (verificado por grep,
ver "Auditoría de seguridad").

## Secrets — `_shared/r2.ts` → `getR2Config()`

Server-side únicamente, sin prefijo `VITE_`: `R2_ACCOUNT_ID`,
`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`.

- **Falla cerrado**: lanza si falta cualquiera, nombrando solo la variable.
- **Nunca registra valores** — ni siquiera en el mensaje de error.
- **Valida formato**: `R2_ACCOUNT_ID` debe ser hex de 32 caracteres en
  minúsculas; `R2_BUCKET_NAME` debe cumplir el naming de buckets S3/R2;
  `R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY` se validan con una heurística
  (longitud mínima, sin espacios) — R2 no publica un formato garantizado
  para estas dos, así que no puede ser una validación de formato estricta.
- **Rechaza explícitamente los 4 placeholders literales de `.env.example`**
  (`your-r2-account-id`, etc.), descubierto durante las pruebas unitarias:
  `your-r2-bucket-name` es, por accidente, un nombre de bucket
  sintácticamente válido, y `your-r2-access-key-id` tiene longitud
  suficiente para pasar la heurística de la access key — la validación de
  formato por sí sola NO los habría atrapado a los dos.
- **`R2_PUBLIC_BASE_URL` fue eliminada de `.env.example`**: un bucket
  privado no tiene URL pública, y su sola presencia invitaba a usarla.

## Bucket, CORS y convención de keys

Recomendado (no creado en esta rama): `one-facility-prod-private` +
`one-facility-dev-private`, ambos completamente privados, sin dominio
`r2.dev` ni dominio personalizado (las URLs firmadas de R2 no funcionan con
dominio personalizado).

**CORS** (solo necesario para el PUT/GET directo del navegador contra R2 —
HEAD y DELETE los ejecuta el servidor y no necesitan CORS):
```json
[{
  "AllowedOrigins": ["https://one-facility.vercel.app"],
  "AllowedMethods": ["PUT", "GET"],
  "AllowedHeaders": ["content-type"],
  "ExposeHeaders": ["ETag"],
  "MaxAgeSeconds": 3600
}]
```
En el bucket de dev, `AllowedOrigins` añade `http://localhost:8080` y
`http://127.0.0.1:8080` (puerto real de Vite — no 5173).

**Object key**, generada exclusivamente en el servidor
(`_shared/assetFileKeys.ts` → `buildAssetFileKey`):
```
organizations/<organization_id>/assets/<asset_id>/photos/<uuid>.<ext>
organizations/<organization_id>/assets/<asset_id>/documents/<uuid>.<ext>
```
El cliente en `create-upload` solo envía `asset_id`, `kind`, `content_type`
y `size_bytes` — nunca una key. `parseAssetFileKey` es el único punto de
entrada para toda acción posterior sobre una key recibida del cliente: dos
patrones **totalmente anclados** (`^...$`), uno por `kind`, construidos
sobre un patrón UUID estricto en minúsculas y un conjunto cerrado de
extensiones — de forma que la propia forma de la key impide un
`photos/<uuid>.pdf` o un `documents/<uuid>.jpg`. Rechaza explícitamente
además `..`, `%`, `//` y espacios en blanco como defensa adicional antes de
intentar el match (aunque el regex anclado ya no podría matchear esos
casos por sí solo).

## Autorización: `authorize_asset_file_access(p_asset_id, p_operation)`

`SECURITY DEFINER`, `SET search_path = public`, `STABLE`. Replica
exactamente las reglas RLS ya existentes de `assets`
(`20260826234732_assets_tenant_aware_foundation.sql`):

| Operación | Regla |
|---|---|
| `read` | `is_platform_admin()` OR `is_organization_member(organization_id)` — cualquier miembro activo, incluido technician/viewer. Un activo archivado sigue siendo legible. |
| `write` / `delete` | `is_platform_admin()` OR `has_organization_role(organization_id, ['owner','admin','manager'])`. Un activo archivado **siempre** rechaza, incluso para el owner. |

También rechaza: sin autenticar, activo inexistente, organización no
`active` o de tipo `platform_admin`, y una operación fuera de
`{read, write, delete}`. `REVOKE ALL FROM PUBLIC, anon` + `GRANT EXECUTE`
solo a `authenticated` — `anon` no tiene ni siquiera el privilegio de
ejecutar la función (falla con `42501` de Postgres antes de que la lógica
interna corra; `asset-files` mapea ese código a 403).

## `asset-files` — única Edge Function

Una sola función, `verify_jwt = true`, con 4 acciones — no cuatro
funciones separadas: la autorización, el parseo de keys y la configuración
de R2 son idénticas entre acciones, así que hay un solo lugar que auditar.

| Acción | Entrada | Flujo | Salida |
|---|---|---|---|
| `create-upload` | `asset_id, kind, content_type, size_bytes` | valida MIME/tamaño declarado → `authorize(write)` → genera key → firma PUT (300 s) | `{ key, upload_url, expires_at, required_headers }` |
| `confirm-upload` | `key` | parsea → `authorize(write)` → cross-check org de la key vs. RPC → HEAD real → tamaño real → Content-Type real → Range GET + magic bytes | `{ key, size_bytes, content_type, etag }` |
| `create-download` | `key` | parsea → `authorize(read)` → cross-check → firma GET (300 s) con `response-content-type`/`response-content-disposition` | `{ download_url, expires_at }` |
| `delete` | `key` | parsea → `authorize(delete)` → cross-check → DELETE server-side (idempotente) | `{ key, deleted: true }` |

**DELETE nunca es firmado** — se ejecuta server-side. Una URL de borrado
firmada sería una capacidad destructiva al portador; ejecutarla en el
servidor permite auditar y autorizar en el momento exacto del borrado.

**Cross-check org/asset de la key**: en toda acción salvo `create-upload`,
`organizationId` embebido en la key se compara contra el `organization_id`
que devuelve `authorize_asset_file_access` para el `assetId` **también
embebido en esa misma key** — nunca contra un `asset_id` separado enviado
por el cliente. Esto cierra el caso de una key cuyo segmento de
organización fue editado a mano para apuntar a otro tenant mientras
conserva un uuid de asset real de otro lado. Verificado en vivo: una key
así devuelve 403 "Object key does not match the asset's organization".

**Content-Type en la firma**: el PUT firmado incluye `Content-Type` como
parte de lo firmado — R2 devuelve 403/`SignatureDoesNotMatch` si el
navegador envía un valor distinto. **Verificado contra R2 real y corregido
durante el E2E**: el comportamiento por defecto de `aws4fetch` con
`signQuery: true` únicamente firma la cabecera `host`
(`X-Amz-SignedHeaders=host`), así que un PUT con un `Content-Type` distinto
al firmado era aceptado por R2 (200), contradiciendo la documentación de
Cloudflare y el comentario original de este archivo. `signPutUrl` ahora pasa
también `allHeaders: true`, con lo que `X-Amz-SignedHeaders` pasa a
`content-type;host` y R2 rechaza correctamente (403,
`SignatureDoesNotMatch`) un `Content-Type` distinto — confirmado con una
subida real. Ver "Prueba E2E real contra R2" más abajo.

## Confirmación de upload — sin inconsistencias DB↔R2

El Punto 7 **no escribe nada en la base de datos** (`asset_documents` no se
toca). `confirm-upload` solo valida el objeto real en R2:

1. `HEAD` — si no existe, 404 "nada que confirmar" (un PUT emitido y nunca
   usado no deja rastro; la URL caduca a los 300 s).
2. Tamaño real (`Content-Length` del HEAD) contra el límite del `kind` —
   **nunca** un `size_bytes` que reenvíe el cliente.
3. `Content-Type` almacenado en R2 contra el esperado por la extensión de
   la key.
4. `Range GET` de los primeros 16 bytes (suficiente para el firma más larga,
   WEBP, de 12 bytes) contra la firma real del formato.
5. Si 2, 3 o 4 fallan: `DELETE` server-side del objeto y error 422 — nunca
   se deja un objeto a medio validar bajo una key con forma legítima.

Para el Punto 10 (cuando exista una fila de BD por archivo): registrar en
BD **antes** de subir (fila `pending`), y que la confirmación la pase a
`available` solo tras este mismo HEAD+bytes. Así un PUT exitoso pero con
fallo de metadata sigue siendo reconciliable (la fila `pending` sin objeto
o el objeto sin fila `available` son ambos detectables), y un DELETE en R2
exitoso con fallo en BD se resuelve con un estado `deleting` intermedio.
Ninguno de estos casos requirió cambios de esquema en el Punto 7.

## MIME y tamaños

| Kind | MIME permitidos | Límite |
|---|---|---|
| `photo` | `image/jpeg`, `image/png`, `image/webp` | 10 MB |
| `document` | `application/pdf` | 25 MB |

Nunca SVG, HTML, JS ni formatos Office en esta fase. `Content-Type` es
parte de la firma del PUT (control real). El tamaño declarado en
`create-upload` es solo un rechazo temprano — el control real es el
`Content-Length` verdadero que reporta R2 en el HEAD de `confirm-upload`,
nunca un segundo tamaño que reenvíe el cliente. Los primeros bytes reales
se comparan contra la firma de cada formato (JPEG `FF D8 FF`, PNG con sus 8
bytes de cabecera, WEBP `RIFF....WEBP`, PDF `%PDF-`) para detectar un
`Content-Type` correcto en la firma pero con bytes reales distintos.

## Cliente frontend: `src/lib/assetFiles.ts`

Sin UI — fija el contrato para el Punto 10. Cuatro funciones tipadas
(`createAssetUpload`, `confirmAssetUpload`, `createAssetDownload`,
`deleteAssetFile`) más `putFileToUploadUrl(uploadUrl, file, requiredHeaders)`,
que hace el PUT real enviando **exactamente** los headers devueltos por
`createAssetUpload` — ni uno más, ni uno menos, porque ese conjunto de
headers es parte de lo firmado. Ningún secreto de R2 existe en este
archivo ni en ningún otro de `src/` (verificado por grep).

## Auditoría de seguridad

| Riesgo | Mitigación |
|---|---|
| Path traversal / keys de otro tenant | Keys generadas en servidor; parser anclado; cross-check org/asset contra la RPC |
| MIME spoofing | `Content-Type` firmado + verificación de bytes reales tras la subida |
| Sobrescritura | Key con UUID de servidor, PUT firmado de 300 s para esa key exacta |
| Ejecutables / HTML / SVG | Fuera de la allowlist de MIME→extensión |
| DELETE firmado filtrado | Nunca existe — DELETE siempre server-side |
| Enumeración | Sin LIST desde el frontend; UUIDs no adivinables |
| Secretos | Solo en `_shared/r2.ts`, sin `VITE_`, falla cerrado, nunca logueados |
| Bucket público | Bucket privado únicamente; sin `R2_PUBLIC_BASE_URL` |
| URLs persistidas | Nunca se guarda una URL firmada — solo la `key`, en `asset_documents.storage_path` (Punto 10, interno) |

Verificado con grep, con el bucket real conectado (cero resultados en todos
los casos):
```
grep -rn "R2_ACCESS_KEY_ID" src
grep -rn "R2_SECRET_ACCESS_KEY" src
grep -rlE "R2_ACCESS_KEY_ID|R2_SECRET_ACCESS_KEY|r2\.cloudflarestorage|aws4fetch|AWS4-HMAC-SHA256" dist/assets/*.js
```
Y, tras el E2E real (68 URLs firmadas emitidas y usadas), un barrido
completo de **todas** las columnas `text`/`varchar`/`jsonb`/`json` del
esquema `public` en la base local buscando el literal `X-Amz-Signature` —
**0 coincidencias en todo el esquema**, confirmando que ninguna URL firmada
quedó persistida en ninguna tabla.

## Deuda técnica registrada, no corregida en esta rama

Los buckets legacy de Supabase Storage `request-documents` y
`request-images` tienen policies `"Anyone can…"` que permiten a `anon`
leer, subir y borrar cualquier objeto, sin distinción de tenant. Hoy nada
los escribe activamente (los componentes que los usaban no están montados
en ninguna vista), pero la superficie sigue abierta. Requiere un PR de
hardening propio — fuera de alcance del Punto 7, que es exclusivamente
sobre R2.

## Pruebas

- **pgTAP** (`asset_file_access_authorization.test.sql`, 30 checks): owner/
  admin/manager con `write`/`delete`; technician/viewer rechazados en
  `write` pero permitidos en `read`; membership inactiva rechazada incluso
  en `read`; cross-tenant rechazado; activo archivado (`read` permitido,
  `write`/`delete` rechazado, incluso para el owner); organización
  suspendida rechazada incluso para su propio owner; activo inexistente;
  operación inválida; platform admin con acceso completo, incluido a un
  tenant ajeno, pero igual bloqueado en un activo archivado; `anon` sin
  `EXECUTE`; grants exactos; `SECURITY DEFINER` + `search_path=public`
  confirmados en el catálogo. Total del proyecto: **629/629** (599 previos
  + 30 nuevos). Control negativo: neutralizando la lógica de la función,
  15 de los 30 checks detectan la regresión.
- **Unitarias puras** (script temporal fuera del repo, esbuild + Node,
  código real de `_shared/assetFileKeys.ts` y `_shared/r2.ts`, sin red):
  **69/69** — construcción y round-trip de keys, 20 variantes de rechazo
  (traversal, `%2e%2e`, doble slash, segmento extra, UUID inválido,
  mayúsculas, extensión no permitida, mezcla kind/extensión, no-string),
  allowlist MIME→extensión (incluidos SVG/HTML/JS/Office explícitamente
  rechazados), límites de tamaño, magic bytes (positivos, negativos y un
  caso de "PNG renombrado a .jpg"), y `getR2Config` (faltante, formato
  inválido, los 4 placeholders literales de `.env.example`, y que ningún
  mensaje de error revele el valor real de ningún secreto).
- **Wiring smoke local** (`supabase functions serve` real, Postgres real,
  credenciales R2 sintácticamente válidas pero falsas — nunca Cloudflare
  real): **21/21** — autorización real por rol (owner/admin/manager
  permitidos, technician/viewer rechazados), cross-tenant real, activo
  archivado real, validación de MIME/tamaño antes de tocar R2, manipulación
  real de keys (traversal y org editada) rechazada, `anon` rechazado con
  403 (`42501` de Postgres — hallazgo: el mensaje no coincidía con ningún
  patrón mapeado y caía a 400; corregido para mapear `42501` a 403
  explícitamente), y una URL de PUT realmente firmada (SigV4 verificable,
  `X-Amz-Signature` presente). El `DELETE` contra el endpoint falso de R2
  se registró como información, no como pass/fail: falla en la capa de red,
  no en autorización — es exactamente lo que cubriría el E2E real.
### E2E real contra Cloudflare R2 (`one-facility-dev-private`)

Ejecutado con el bucket real, credenciales reales cargadas en
`supabase/functions/.env`, y `supabase functions serve --env-file
supabase/functions/.env` sirviendo la Edge Function real. Fixtures
(usuarios, organizaciones, memberships, activos) únicamente en Supabase
local — nunca datos del proyecto remoto. Script temporal fuera del repo.
**68/68 checks.**

- **Happy path (owner, PNG real):** `create-upload` → PUT real → `confirm-upload`
  (tamaño real, `Content-Type` real, ETag real) → `create-download` → GET
  real → **SHA-256 idéntico** entre el archivo original y el descargado →
  `delete` → una nueva petición real contra esa key devuelve **404**.
- **Manager:** ciclo completo (`create-upload` → PUT real de un PDF →
  `confirm-upload` → `delete`) correcto.
- **Technician:** `create-upload` rechazado (403), nunca se emitió una URL.
- **Lectura (viewer):** `create-download` permitido; `create-upload`
  rechazado (403).
- **Cross-tenant:** el owner de la organización B no obtiene URL de
  `create-upload`, `create-download` ni `delete` sobre un activo de la
  organización A — ninguna URL firmada se devuelve en ningún caso.
- **Manipulación de key:** organización, activo, `kind`, extensión,
  segmento extra, `%2e%2e`, `../` y `../` vía el segmento de organización —
  las 8 variantes rechazadas tanto en `confirm-upload` como en
  `create-download`.
- **Allowlist MIME (subida real):** `image/png`, `image/jpeg`,
  `image/webp` y `application/pdf` — las 4 completan `create-upload` + PUT
  real + `confirm-upload` correctamente.
- **MIME inválido:** `text/html`, `image/svg+xml`, `application/javascript`
  — las 3 rechazadas con 400 en `create-upload`, antes de firmar nada.
- **MIME spoof:** `create-upload` para `image/png` con bytes reales de HTML.
  El PUT llega a R2 sin problema (el `Content-Type` de la cabecera coincide
  con lo firmado). `confirm-upload` detecta el mismatch de magic bytes,
  borra el objeto server-side, y una petición real posterior confirma
  **404** — nunca queda un objeto inválido bajo una key con forma legítima.
- **`Content-Type` firmado — hallazgo real y corrección de código:** ver
  más abajo.
- **`Content-Length` — comportamiento observado, sin cambio de arquitectura:**
  ver más abajo.
- **Oversize:** foto > 10 MB y documento > 25 MB declarados en
  `create-upload` — ambos rechazados con 400, sin firmar ninguna URL.
- **Expiración:** una URL firmada con `X-Amz-Expires=1` (solo para esta
  prueba; los 300 s de producción no cambiaron), usada 2.5 s después,
  devuelve **403** real de R2.
- **Activo archivado:** `read` autorizado (se emite una URL de descarga);
  `write` y `delete` rechazados con 403.
- **CORS:** ver más abajo.
- **Cleanup:** las 12 keys reales creadas por la corrida se borraron (0
  fallos); una verificación `ListObjectsV2` directa (credenciales reales,
  fuera de la app — nunca una capacidad de LIST expuesta por `asset-files`)
  con el prefijo de cada organización de prueba confirma **cero objetos
  remanentes** en el bucket tras la corrida.

#### Hallazgo real: `Content-Type` no estaba realmente firmado — corregido

Verificado con `X-Amz-SignedHeaders` de una URL real: el comportamiento por
defecto de `aws4fetch` con `signQuery: true` firma **únicamente** la
cabecera `host`. Un PUT con `Content-Type: image/jpeg` contra una URL
firmada para `image/png` era **aceptado por R2 (200)** — contradiciendo la
documentación de Cloudflare y el comentario original de `signPutUrl`.

**Corrección aplicada** (`supabase/functions/_shared/r2.ts`): se añadió
`allHeaders: true` a las opciones de `sign()` en `signPutUrl`. Con eso,
`X-Amz-SignedHeaders` pasa a `content-type;host`, y una petición real
confirma que R2 ahora sí rechaza (403, `SignatureDoesNotMatch`) un
`Content-Type` distinto al firmado, aceptando únicamente el correcto contra
la misma URL. `confirm-upload` (Content-Type real + magic bytes) sigue
siendo el control real e independiente — esta corrección es defensa en
profundidad adicional, verificada, no un reemplazo.

#### `Content-Length`: comportamiento observado

- **Firma de producción actual** (`Content-Type` + `allHeaders: true`, sin
  `Content-Length`): un PUT con un cuerpo más grande que el `size_bytes`
  declarado en `create-upload` es aceptado por R2 (200) — la firma no dice
  nada sobre el tamaño real del cuerpo.
- **Prueba ad-hoc** (fuera de `r2.ts`, solo para esta observación): firmando
  también `Content-Length` con `allHeaders: true`, R2 sí compara el tamaño
  real del cuerpo contra el valor firmado — un cuerpo de tamaño distinto
  devuelve 403 (`SignatureDoesNotMatch`); el tamaño exacto firmado se
  acepta (200).
- **Conclusión, sin cambio de arquitectura** (por instrucción explícita):
  sería técnicamente posible que R2 exigiera el tamaño exacto declarado por
  el cliente, pero no se implementó. La garantía real y definitiva de
  tamaño sigue siendo, sin cambios, el `HEAD` real de `confirm-upload`
  contra el límite de `kind` — que ya se ejerce con tamaños reales en el
  happy path y en el caso de MIME spoof de este mismo E2E.

#### CORS

Verificado a nivel HTTP desde Node (no un navegador real): preflight
`OPTIONS` con `Origin: http://localhost:8080` contra la URL de PUT firmada
(responde `Access-Control-Allow-Origin: http://localhost:8080` y
`Access-Control-Allow-Methods` incluye `PUT`) y contra la URL de GET
firmada (mismo `Allow-Origin`); una petición GET real con ese `Origin`
devuelve `Access-Control-Allow-Origin` y `Access-Control-Expose-Headers:
ETag`, con un `ETag` real presente; un PUT real con ese mismo `Origin`
también se completa. Esto verifica exactamente las cabeceras HTTP que un
navegador real recibiría y sobre las que aplicaría su propia política de
CORS — pero **no sustituye una prueba real en un navegador**. **Hecho en
el Punto 10:** la app en `http://localhost:8080` con Chromium real sube
(preflight + PUT 200) y muestra fotos (GET) directamente contra
`one-facility-dev-private`, sin errores de CORS; ver
`docs/ASSET_FILES_R2_PRODUCTIZATION.md`. El procedimiento manual original
era: abrir
`http://localhost:8080` (o cualquier página servida desde ese origen),
ejecutar `fetch(uploadUrl, {method:'PUT', headers: requiredHeaders, body})`
y `fetch(downloadUrl)` desde la consola del navegador, y confirmar que no
aparece ningún error de CORS en la consola y que `response.headers.get('etag')`
es accesible desde JavaScript.
