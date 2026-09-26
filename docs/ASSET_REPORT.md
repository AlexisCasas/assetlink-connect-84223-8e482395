# Reporte del activo (PDF)

Fase 1 · Punto 5. Rama `feature/phase1-asset-report`, sobre el merge del
Punto 4 (fix de overflow del diálogo QR incluido). **No hay migración SQL**:
todas las secciones se componen a partir de RPCs/tablas que ya existían y ya
estaban protegidas por RLS/`SECURITY DEFINER`.

## Qué es y qué no es

Un PDF **generado bajo demanda** al hacer clic en "Generar Reporte" en la
ficha del activo: una fotografía de su estado en ese instante. No es un
documento persistido, no es un evento, no es un reemplazo del historial.

Generarlo o descargarlo **nunca**:
- inserta una fila en `asset_events`;
- modifica `assets.updated_at`;
- sube nada a Supabase Storage ni a R2;
- crea una fila en `asset_documents`;
- modifica el historial.

Es una operación 100% de lectura + generación local en el navegador. Ver
`src/lib/assetReport/` — ningún archivo de ese módulo contiene `.insert(`,
`.update(`, `.delete(` ni `.upsert(` (verificado por grep, y por los tests
descritos más abajo).

## Snapshot: `AssetReportData`

`src/lib/assetReport/types.ts` define el modelo. Se construye una sola vez
por clic, nunca se guarda, nunca se reutiliza entre generaciones:

```ts
interface AssetReportData {
  generatedAt: string;
  generatedByName: string | null;
  organizationName: string;
  asset: Asset;
  pathNames: string[];
  branchName: string | null;
  categoryName: string | null;
  responsible: AssetReportResponsible;
  technicalFields: AssetReportTechnicalField[];
  criticality: AssetReportCriticality;
  trafficLight: AssetReportTrafficLight;
  preventivePlans: AssetReportPreventivePlan[];
  inspectionPlans: AssetReportInspectionPlan[];
  notices: AssetReportNotice[];
  history: AssetReportHistoryItem[];
  qr: AssetReportQr;
  photoUrl: string | null;
}
```

## Fuentes — una por sección, nunca reconstruidas

| Sección | Fuente | Filtro aplicado |
|---|---|---|
| Ficha / identificación / técnica | `assets` (relectura fresca por `id`) | — |
| Sede | `client_branches` por `branch_id` | Se lee directo por id (no solo activas) para no perder el nombre de una sede histórica desactivada |
| Categoría | `asset_categories` por id | idem |
| Responsable predeterminado / responsable de planes preventivos | `get_assignable_planners` | Solo se genera el reporte con permisos owner/admin/manager, así que siempre se resuelve contra ese mismo directorio (igual que `AssetDetail`) |
| Criticidad | `get_asset_criticality_assessments` | Última evaluación (`[0]`) |
| Semáforo | `get_asset_traffic_light` (por organización) | Filtrado a `assetId === asset.id` |
| Preventivo | `get_preventive_maintenance_plans` (por organización) | `plan.asset_id === asset.id` exacto |
| Inspecciones (planes) | `get_inspection_plans` (por organización, incluye inactivos) | `plan.assetId === asset.id` exacto — **nunca** `areaAssetId` ni `branchId` |
| Inspecciones (última ejecución) | `get_inspection_runs` (por organización) | Correlacionado por `run.planId === plan.id` (UUID, no por nombre de texto); la "última" se elige por comparación explícita de fechas (`completedAt ?? startedAt ?? scheduledFor`), nunca por orden del array |
| Avisos | `get_maintenance_notices` (por organización) | `notice.assetId === asset.id` exacto |
| Historial operativo | `get_asset_integrated_history` | Única fuente — nunca se reconstruye desde `requests`/`work_orders`/intervenciones; conserva el `ORDER BY event_date DESC` de la RPC |
| QR | `buildAssetQrUrl` (Punto 4) | — |

Las RPC de preventivo/inspecciones/avisos no aceptan un parámetro por
activo — se leen a nivel de organización y se filtran en memoria, replicando
el mismo patrón que `usePreventiveMaintenance` ya usa.

`src/lib/assetReport/sources.ts` reimplementa el fetch + mapeo de cada una
de estas RPC de forma standalone (no reutiliza los hooks de React
directamente: un hook trae su propio ciclo de vida — `useEffect`,
suscripciones, refresco — que no tiene sentido para una carga de una sola
vez). El mapeo fila→dominio es una copia mecánica y mínima del que cada
hook ya hace, produciendo exactamente los mismos tipos (`Asset`,
`PreventivePlan`, `InspectionPlan`, `MaintenanceNotice`, etc.) — cero deriva
de forma respecto a la fuente real.

## Carga: nada se pide hasta el clic

`AssetDetail` no importa `@react-pdf/renderer` de forma estática. El botón
"Generar Reporte" dispara:

```
clic → import() dinámico de generateAssetReport
     → loadAssetReportData (Promise.allSettled sobre 11 fuentes)
     → si CUALQUIERA falló: mostrar qué secciones y detener (sin PDF)
     → buildAssetReportData (transform puro)
     → render con @react-pdf/renderer
     → descarga del Blob
```

`loadAssetReportData` usa `Promise.allSettled`, no `Promise.all`: así puede
reportar **todas** las secciones que fallaron en un mismo intento, no solo
la primera. Un resultado vacío (0 filas) nunca cuenta como fallo — es dato
válido ("sin planes preventivos", "sin avisos"). Solo un `reject` real
cuenta, y cualquier sección fallida aborta el reporte completo: nunca se
genera un PDF parcial.

## Historial completo, sin truncar

`get_asset_integrated_history` no tiene `LIMIT`; el reporte lo respeta tal
cual. Probado con 520 eventos sintéticos: **39 páginas**, ~285 KB, sin
truncar nada. El motor de PDF pagina automáticamente — no se creó ninguna
paginación nueva en el backend.

## QR: vectorial, sin rasterizar

El reporte reutiliza exactamente `buildAssetQrUrl` (Punto 4) — nunca
`assets.qr_code`. Para incrustar el QR en el PDF sin duplicar la lógica de
generación ni depender de un `<canvas>`:

1. Se renderiza `<QRCodeSVG>` (la misma librería y props que `AssetQrDialog`)
   a una cadena estática con `react-dom/server`.
2. `src/lib/assetReport/qr.ts` extrae el `viewBox` y los dos `<path>`
   (fondo y trazo) de esa cadena — no un parser SVG genérico: depende del
   shape exacto que `qrcode.react@4.2.0` emite (verificado leyendo su
   fuente), documentado en el propio archivo.
3. `AssetReportDocument` los redibuja con `<Svg>`/`<Path>` de
   `@react-pdf/renderer` — vectorial, nítido a cualquier tamaño, cero
   peticiones de red.

Verificado con un render real + rasterizado (`sharp`) + decodificación con
un lector real (`jsQR`): el QR embebido en el PDF decodifica exactamente a
la misma URL canónica que genera `buildAssetQrUrl`.

## Librería de PDF: `@react-pdf/renderer`

Verificado antes de instalar (`npm view`): versión `4.9.0`, licencia MIT,
peer `react ^16 || ^17 || ^18 || ^19` (compatible con React 18 de este
proyecto). Instalado con versión exacta (`--save-exact`).

Motivo de la elección frente a jsPDF+autotable/pdfmake/pdf-lib: paginación
automática con encabezado/pie repetibles (`fixed`) y "Página X de Y"
nativos, `<Svg>/<Path>` para el QR vectorial sin capa adicional, y una API
declarativa en JSX coherente con el resto del código React del repo.

**Sin fuentes embebidas** (decisión explícita, no se instaló ningún
`.ttf`/`.otf`): se usan las fuentes estándar del motor. Los únicos símbolos
que esas fuentes no representan bien (`→`, `≤`, `≥`) se normalizan
SOLO al construir el PDF (`pdfText` en `utils.ts`) — nunca se toca el dato
almacenado ni ningún texto de la aplicación.

Todo el módulo (`@react-pdf/renderer`, `react-dom/server`, y el propio
código del reporte) se carga vía `import()` dinámico desde `AssetDetail`,
quedando en su propio chunk separado del bundle inicial (`generateAssetReport-*.js`,
confirmado en `npm run build`).

## Diseño A4

Encabezado fijo (logo + nombre/código del activo) en todas las páginas.
Bloque "hero" completo (título, organización, fecha de generación, QR) solo
al inicio de la página 1. Pie fijo con organización, quién y cuándo se
generó, "Página X de Y", y la leyenda "Estado al momento de generación, no
es un registro histórico" — con el UUID técnico en letra pequeña, nunca
protagonista.

Orden de secciones: Identificación → Información técnica → Criticidad →
Estado operativo → Preventivo → Inspecciones → Avisos → Historial operativo
(esta última siempre en página nueva, vía `break`).

Cada fila/ítem se dibuja como una tarjeta con borde (`wrap={false}` para no
partirse entre páginas) en vez de una tabla de cuadrícula clásica:
`@react-pdf/renderer` no repite el encabezado de una tabla entre páginas de
forma nativa, y esta forma reflowa sin trabajo extra manteniendo la
legibilidad. Todo color (semáforo, criticidad, prioridad) siempre va
acompañado de una etiqueta de texto — el PDF se entiende igual impreso en
blanco y negro.

## Foto

Solo se muestra si `assets.image_url` tiene un valor real. Nunca se usa
`/placeholder.svg` (ese fallback es exclusivamente de la UI de
`AssetDetail`, nunca un dato almacenado). No se desarrolló ninguna
funcionalidad de carga de fotos en este punto — eso queda para cuando el
módulo de documentos/R2 exista.

## Nombre del archivo

```
reporte-activo-<codigo-o-nombre>-<uuid8>-YYYYMMDD.pdf
```

`buildAssetReportFilename` (`src/lib/assetReport/utils.ts`) reutiliza
`sanitizeFilenameSegment` de `assetQr.ts` (Punto 4) para el slug, y añade
los primeros 8 caracteres del UUID para evitar colisiones entre dos activos
con el mismo nombre/código generados el mismo día.

## Permisos

El botón "Generar Reporte" solo se muestra a **owner/admin/manager**
(`canManageAssets`, el mismo gate que ya usa `AssetDetail` para editar). Es
gobierno de producto, no una frontera de seguridad nueva: cada fuente sigue
protegida exactamente por su RLS/RPC de siempre, y no se creó ninguna RPC
nueva solo para bloquear a technician/requester/viewer — ellos ya pueden
leer estos mismos datos dentro de la app; lo único que este punto restringe
es quién puede exportarlos a un archivo.

## Seguridad

- Cero service role en el frontend; cada fuente pasa por sesión + tenant +
  RLS/`SECURITY DEFINER` normal.
- El PDF nunca incluye: `actorEmail`, `file_url`/URLs firmadas, `metadata`
  o `payload` crudos, tokens, ni `assets.qr_code`.
- Del historial solo se muestran los campos explícitamente permitidos por
  tipo de evento (horas y fechas de intervención, código/cantidad de
  material, número de solicitud/OT, nombre de archivo de evidencia) — nunca
  el objeto `metadata` completo.
- `technicalData`: solo valores primitivos, con clave humanizada; objetos,
  arrays, `null`/`undefined` y cadenas vacías se omiten. Nunca se imprime
  JSON crudo.

## Tests

No se añadió Vitest ni otro runner al repositorio. Se usó un proyecto
temporal fuera del repo (mismo patrón que el Punto 4) que:

1. Empaqueta con `esbuild` los archivos reales de
   `src/lib/assetReport/{buildAssetReportData,utils,qr}.ts` y
   `AssetReportDocument.tsx` (alias `@` → `src/`, `@/integrations/supabase/client`
   sustituido por un stub — ese módulo nunca se invoca en estos caminos,
   solo se importa transitivamente por tipos/valores no usados aquí).
2. Corre 22 aserciones en Node contra el código real: snapshot mínimo y
   completo, campos NULL, caracteres especiales, nombre de archivo,
   `technicalData` primitivo vs. complejo, criticidad vigente/no vigente,
   semáforo verde/ámbar/rojo/archivado (nunca "verde" por archivado),
   preventivo filtrado por `asset_id` exacto, inspecciones excluyendo
   `areaAssetId`/`branchId`, selección de última ejecución por fecha
   explícita (no por orden de array), avisos filtrados, e historial sin
   `actorEmail`/`file_url`/metadata cruda.
3. Renderiza el QR con el `qrcode.react` real instalado, lo rasteriza con
   `sharp` y lo decodifica con `jsQR`: el resultado es exactamente la URL
   canónica esperada.
4. Renderiza un PDF real de 520 eventos con `@react-pdf/renderer` y lo
   inspecciona con `pdf-parse`: 39 páginas, pie/página repetidos, y sin
   ningún `→`/`≤`/`≥` sin normalizar en el texto extraído.

Regresión: `supabase db reset --local` + **412 pruebas pgTAP** (sin cambios
de esquema en este punto). El aislamiento por tenant de cada RPC reutilizada
ya está cubierto por esas mismas 412 pruebas (no se creó ninguna RPC nueva
que probar de cero).

## Riesgos conocidos / limitaciones

- El chunk `generateAssetReport-*.js` pesa ~487 KB gzip (incluye
  `@react-pdf/renderer` + `pdfkit`) — aceptable porque se carga diferido,
  solo al generar un reporte, nunca en la carga inicial de la app.
- El snapshot no es transaccional: las ~10 lecturas ocurren en paralelo, no
  dentro de una única transacción de base de datos. Un desfase de
  milisegundos entre secciones es posible en el caso extremo de una edición
  concurrente exacta durante la generación.
- `technicalData` sigue sin ningún flujo de UI que lo escriba (dato legado)
  — la sección técnica del reporte reflejará eso mientras no exista una UI
  de edición para ese campo.
