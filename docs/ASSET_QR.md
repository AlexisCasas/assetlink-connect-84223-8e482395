# QR de activos

Fase 1 · Punto 4. Rama `feature/phase1-asset-qr`, sobre el merge del Punto 3
(`f5ebfe9`). **No hay migración SQL**: no se necesita ninguna tabla, columna,
RLS ni RPC nueva — todo se resuelve en el frontend con datos que la
aplicación ya lee bajo sesión, tenant y RLS existentes.

## Identidad del QR

La única fuente de identidad es **`assets.id`** (UUID). El payload nunca
depende del nombre, el código, la sede, la jerarquía, el estado ni el
responsable del activo — renombrar, recodificar, mover o archivar el activo
nunca invalida un QR ya impreso.

`assets.qr_code` (columna existente desde la migración de fundación)
**permanece intacta, reservada y sin semántica funcional en este MVP**. No
se lee, no se escribe y no se muestra en ningún lugar de la interfaz. No se
usa `asset.qrCode ?? asset.id` ni ningún otro fallback sobre ella.

## Payload canónico

```
<VITE_PUBLIC_APP_URL>/#assets?org=<organization_uuid>&assetId=<asset_uuid>
```

Se construye con `buildAssetQrUrl` (`src/lib/assetQr.ts`), que reutiliza
`buildEntityHash` — el mismo constructor de hash que usa el resto de la
aplicación para sus deep links — así que el formato de query string nunca
diverge del resto del sistema.

## Deep link: `assetId` sin colisión con `preventiveAssetId`

`EntityNavigationTarget` gana un campo `assetId?: string`, con su propia
clave de query **`assetId`**, deliberadamente distinta de la clave `asset`
que ya usaba `preventiveAssetId`:

| Campo | Clave de URL | Vista | Significado |
|---|---|---|---|
| `preventiveAssetId` | `asset` | `#preventive-maintenance` | "Crea un plan preventivo para este activo" (una acción) |
| `assetId` | `assetId` | `#assets` | "Abre la ficha de este activo" |

Los enlaces preventivos existentes (`#preventive-maintenance?asset=<uuid>`)
no cambian de formato ni de comportamiento. `parseEntityHash(buildEntityHash(...))`
conserva ambos contratos por separado, verificado con round-trips reales.

## Flujo autenticado

1. `Dashboard.tsx` lee el hash (como ya hacía) y pasa `focusAssetId={focus.assetId}`
   a `AssetsView`.
2. `AssetsView` espera a que la consulta de activos de la organización activa
   termine (`!state.loading`) y procesa el foco **una sola vez** por la
   combinación `organizationId + assetId` (mismo patrón de guardia por `ref`
   que ya usan los demás deep links de la aplicación — evita bucles y avisos
   repetidos).
   - Si el activo existe: `selectAsset(id)`. Si está archivado, además
     `setShowArchived(true)`.
   - Si no existe, es de otro tenant o la RLS no lo devuelve: **el mismo
     mensaje genérico** en los tres casos — "No se pudo abrir el activo.
     Puede no existir o no tienes acceso." — nunca se revela cuál de los tres
     ocurrió.
3. `AssetTree` expande automáticamente los ancestros del nodo seleccionado
   (recorriendo `parentAssetId` sobre la lista ya cargada en memoria, **sin
   ninguna consulta adicional**) y hace scroll hasta él la primera vez que
   aparece en el DOM. Una selección manual (clic) sigue funcionando igual;
   el scroll automático no se repite si luego se expande o contrae una rama
   distinta.

## Multiempresa

Se reutiliza tal cual la lógica de `?org=` que Dashboard ya tenía: si el
usuario pertenece a esa organización, cambia de organización activa y luego
abre el activo; si no, muestra el aviso existente "Sin acceso a la
organización del enlace" y `AssetsView` nunca llega a intentar resolver el
`assetId` de un tenant al que el usuario no tiene acceso.

## Login / retorno sin open redirect

- `ProtectedRoute` (en `App.tsx`) ahora usa `useLocation()` y, al redirigir a
  `/login`, guarda `{ from: { pathname, hash } }` en `location.state` — solo
  el pathname y el hash **de esta misma aplicación**, nunca una URL externa.
- `Login.tsx` valida ese `from` con `resolveSafeLoginReturnTarget`
  (`src/lib/entityNavigation.ts`) antes de navegar con él. Solo acepta
  `pathname === '/'` y un hash cuyo segmento de vista esté en
  `ALL_DASHBOARD_VIEWS` (la misma lista blanca que ya usa `parseEntityHash`).
  Cualquier otra cosa — una URL externa, `//host`, `http://…`, `https://…`,
  `javascript:…` o una vista desconocida — devuelve `null` y el destino cae a
  un `/` simple. Al ser una lista blanca de comparación exacta, ninguna
  cadena manipulada puede pasarla.
- Tras iniciar sesión (o en modo demo), `navigate(returnTarget, { replace: true })`
  restaura exactamente `/#assets?org=…&assetId=…`.
- Si el usuario **ya tenía sesión**, `ProtectedRoute` nunca redirige a
  `/login` y el flujo es el mismo que cualquier otro deep link: Dashboard lee
  el hash directamente.
- **Nota para una futura OAuth externa real** (`loginWithGoogle` en
  `AuthContext`, no usado hoy desde `Login.tsx`): ese flujo sale del dominio
  de la aplicación y `location.state` de react-router **no sobrevive** ese
  viaje de ida y vuelta. Si se activa, el destino de retorno tendría que
  persistirse aparte (por ejemplo `sessionStorage`) antes de iniciar esa
  redirección, no en el estado de react-router.

## Activo archivado

Un QR válido de un activo archivado abre su ficha y su historial para un
usuario autorizado: `AssetsView` activa "Ver archivados" automáticamente
antes de seleccionarlo. No habilita nada de edición que las reglas actuales
ya no permitieran (la edición sigue gobernada por `canManageAssets`, sin
cambios).

## URL pública: `VITE_PUBLIC_APP_URL`

Variable **no secreta**, documentada en `.env.example`. Debe ser un origen
puro: `http://` o `https://`, sin ruta distinta de `/`, sin query y sin hash.
Se valida con `new URL(...)` en `src/lib/env.ts` (`normalizeConfiguredPublicAppUrl`).

- **Si falta o es inválida**: se usa `window.location.origin` como respaldo
  — así funciona en local sin configurar nada. Solo se emite `console.warn`
  en desarrollo cuando el valor **está configurado pero es inválido** (no
  cuando simplemente falta, para no ser ruidoso en cada arranque local); ese
  aviso nunca imprime UUID ni el payload completo de ningún activo.
- `http://` se acepta también para dominios no locales (la validación no
  distingue por host); lo que sí distingue por host es la detección de
  origen local/desarrollo (`isLocalOrDevOrigin`): `localhost`, `127.0.0.1`,
  `::1`, `*.localhost` y los rangos privados `10.0.0.0/8`, `172.16.0.0/12`,
  `192.168.0.0/16`. Cuando el origen resuelto cae en esa detección, el modal
  del QR muestra la advertencia "QR de desarrollo…", **sin bloquear** la
  descarga ni la impresión (se necesitan igualmente para probar en local).
  Esta detección es independiente de si el origen vino de la variable
  configurada o del respaldo: un `VITE_PUBLIC_APP_URL=http://localhost:4000`
  configurado a propósito también se marca como local.

## Generación del QR

`qrcode.react@4.2.0` (verificada antes de instalar: licencia ISC, sin
dependencias en tiempo de ejecución, peer `react` compatible con React 18).
Sin servicios externos: todo se genera en el navegador.

- **Pantalla y descarga SVG**: `QRCodeSVG`, 256 px, nivel de corrección `M`,
  `marginSize={4}` (zona de silencio de 4 módulos).
- **Descarga PNG**: `QRCodeCanvas` oculto, 1024×1024 px, `canvas.toBlob('image/png')`.
- Ambos codifican exactamente el mismo `buildAssetQrUrl(...)`.

## Descarga

- **PNG** ~1024×1024 px, **SVG** vectorial — ambos generados localmente, sin
  subir nada a Supabase Storage, R2 ni ninguna base de datos.
- Nombre: `qr-activo-<código-o-nombre-normalizado>-<8 primeros caracteres del UUID>.png|svg`
  (`buildAssetQrFilename`), con el código priorizado sobre el nombre y acentos
  normalizados.

## Impresión

Etiqueta fija de **70mm × 40mm** (`buildAssetLabelHtml`): QR de ~30mm a la
izquierda, logo local (`/brand/logo-primary.png`), nombre, código si existe y
"Escanea para abrir el activo" a la derecha. Se imprime con un `<iframe>`
oculto (`srcdoc` + `contentWindow.print()`), sin ventanas emergentes ni
escritura alguna en base de datos. El nombre y el código del activo —
texto libre que el usuario escribió — se escapan estrictamente
(`escapeHtml`) antes de insertarse en el HTML de la etiqueta; el propio QR
(SVG generado por la aplicación) se inserta tal cual, porque no es texto de
usuario.

## Permisos

- **Ver el QR y copiar el enlace**: cualquier miembro con acceso al módulo de
  Activos. El enlace no es sensible por sí mismo; abrirlo sigue exigiendo
  sesión, tenant y RLS.
- **Descargar (PNG/SVG) e imprimir**: solo owner/admin/manager
  (`canManageAssets`, el mismo criterio que ya gobierna la edición de
  activos). No se amplía ni se modifica ninguna policy de RLS por esto.

## Seguridad

- El payload nunca contiene JWT, `access_token`, `refresh_token`, service
  role ni ningún dato personal — solo un origen público, una vista y dos
  UUID. Ni el UUID del activo ni el de la organización son considerados
  autorización: toda lectura real pasa por sesión + organización activa +
  RLS de `assets`, exactamente igual que cualquier otro deep link.
- No se crea ninguna ruta pública: `/` sigue protegida por `ProtectedRoute`
  y no existe ninguna consulta de activos sin autenticación.
- El retorno tras el login usa exclusivamente navegación interna de
  react-router con una lista blanca — no puede convertirse en un open
  redirect (ver sección de login más arriba).
- El fragmento (`#...`) de la URL nunca llega al servidor ni a los logs.

## Fuera de alcance (no implementado en este punto)

Reporte PDF del activo, fotos/documentos, Cloudflare R2, QR públicos sin
login, lector de cámara dentro de la aplicación, formulario público de
avería desde QR, NFC, etiquetas masivas, QR rotatorios, nuevos permisos y
migración/activación de `assets.qr_code`.
