# Criticidad V2 — Plantillas, Excel y evaluación masiva

Rama `feature/criticality-v2-templates-excel`. Migración
`supabase/migrations/20260915120000_criticality_v2_templates_excel.sql`.
Evoluciona el motor de `docs/CONFIGURABLE_CRITICALITY_MATRIX.md` sin
reconstruirlo y **sin modificar** `20260829190000_configurable_criticality_matrix.sql`:
lo que cambia de aquella fase se hace por `CREATE OR REPLACE` con la **misma
firma**, así que ningún call site existente cambió de contrato.

## Códigos técnicos estables (`code`)

La matriz viva no tenía identificadores estables: un round-trip
exportar → editar → importar solo puede funcionar si cada parámetro/opción
tiene un código que sobrevive a la edición del archivo.

- `criticality_parameters.code` y `criticality_parameter_options.code`,
  `NOT NULL`, backfilleados de forma determinística desde el nombre
  (`criticality_slugify` + desempate por `ROW_NUMBER()` en orden estable
  `sequence, created_at, id`).
- **Unicidad parcial, solo entre filas activas**:
  `UNIQUE (organization_id, LOWER(code)) WHERE is_active` y
  `UNIQUE (parameter_id, LOWER(code)) WHERE is_active`. Es la única forma
  compatible con la regla "nunca borrar, solo desactivar" que impone el mismo
  módulo: al reemplazar una matriz las filas viejas conservan su código
  desactivadas, y si el índice fuera total reimportar la misma matriz
  chocaría contra su propia versión anterior. El código identifica un
  parámetro/opción **dentro de la matriz activa**, que es exactamente lo que
  el contrato Excel necesita.
- Los RPC manuales (`upsert_criticality_parameter`/`upsert_criticality_option`)
  **no cambiaron de firma**: dos triggers
  (`assign_criticality_parameter_code`/`assign_criticality_option_code`)
  generan el código cuando la fila llega sin él. No se crearon overloads.
- `get_criticality_matrix` (misma firma) ahora devuelve `code`.

## Plantilla vs. matriz viva

| | Matriz viva | Plantilla |
| --- | --- | --- |
| Tablas | `criticality_parameters` / `_options` | `criticality_matrix_templates` / `criticality_template_parameters` / `criticality_template_options` |
| Alcance | una organización | `scope='system'` (global, `organization_id IS NULL`) o `scope='organization'` (privada del tenant) |
| Evaluaciones | sí (`asset_criticality_assessments`) | nunca: una plantilla solo copia configuración |

La infraestructura de plantillas `system` existe, pero **esta fase no carga
ninguna plantilla técnica inventada** (HVAC/Refrigeración/etc. quedan
pendientes de validación de negocio). Es válido y esperado que el catálogo
arranque vacío y se llene con "Guardar como plantilla".

### RLS de plantillas

Solo hay policies de `SELECT`; toda escritura pasa por RPC `SECURITY DEFINER`
(mismo patrón que las 4 tablas de criticidad existentes, que tampoco tienen
policies de escritura). Una plantilla `organization` de Cliente A es invisible
para Cliente B por RLS **y** es rechazada por las RPC, que repiten el chequeo
(`can_access_criticality_template`) — probado con el UUID real de la plantilla,
no solo confiando en que la RLS la oculte.

## Motor común de cálculo (lo más importante de esta fase)

`validate_and_score_asset_criticality(p_asset_id, p_answers, p_expected_organization_id)`
es la **única** implementación de "validar respuestas + puntuar" del sistema.
La fórmula (`score = Σ round(option.score * weight / 100, 2)`) y los umbrales
(`<25 low / <50 medium / <75 high / >=75 critical`) viven solo ahí.

```
                    ┌─ calculate_asset_criticality  (individual, API sin cambios)
validate_and_score ─┼─ preview_bulk_asset_criticality (dry run, no escribe)
                    └─ bulk_calculate_asset_criticality (PASADA 1 valida todo)
```

- No escribe nada y **no lanza excepción** por errores de fila: los acumula en
  `errors[]`, para que el preview masivo reporte 100 filas de una sola pasada.
  `calculate_asset_criticality` convierte esos errores en `RAISE`, conservando
  su semántica anterior.
- `p_expected_organization_id` es lo que impide que un UUID de activo de otro
  tenant pegado en el Excel se cuele: nunca se confía en el archivo.
- Helper interno, **sin `GRANT` a `authenticated`** (mismo patrón que
  `resolve_asset_path`/`notify_role_members`).
- El score del preview y el de la evaluación real salen del mismo lugar:
  **nunca hay una fórmula paralela en JavaScript**.

`bulk_calculate_asset_criticality` hace PASADA 1 (validar todas las filas, sin
escribir; si alguna es inválida aborta el subset entero) y PASADA 2
(delegar cada fila en `calculate_asset_criticality`, el único escritor de
evaluaciones del sistema). Reimportar un activo **siempre crea un assessment
nuevo**; nunca sobrescribe el anterior.

## Reemplazo de matriz

`replace_criticality_matrix(p_organization_id, p_matrix jsonb)`: valida TODO el
payload primero, luego **desactiva** (`is_active = false`, nunca `DELETE`) la
configuración activa y solo entonces inserta la nueva. Todo en una
transacción. `apply_criticality_template` arma el payload desde la plantilla y
delega aquí, así "reemplazar la matriz" tiene una sola implementación.

Peso total ≠ 100 **no bloquea** (solo advertencia en la UI). Sí bloquean:
código vacío/duplicado (case-insensitive), nombre/etiqueta vacíos, peso o
puntaje negativos, orden ≤ 0, y un parámetro activo sin ninguna opción activa
(sería inevaluable, porque `calculate_asset_criticality` exige responder todos
los parámetros activos).

## Nueva matriz en blanco

Migración `20260915130000_criticality_clear_active_matrix.sql` — **separada**
de `20260915120000_criticality_v2_templates_excel.sql` a propósito: esa
migración ya estaba aplicada al proyecto enlazado cuando se pidió este botón,
así que editarla habría dejado el archivo local desincronizado del historial
de migraciones remoto. Mismo principio que ya rige para no tocar
`20260829190000_configurable_criticality_matrix.sql`, aplicado un paso antes
de mergear.

`clear_active_criticality_matrix(p_organization_id)`: deja a la organización
sin parámetros activos, en una sola transacción con **2 `UPDATE`** (opciones
activas de los parámetros activos de la organización, luego esos parámetros),
reutilizando exactamente la misma lógica de desactivación que ya vive dentro
de `replace_criticality_matrix` — sin la inserción posterior. **Nunca
`DELETE`**, nunca toca `criticality_matrix_templates`/`_parameters`/`_options`,
`asset_criticality_assessments`/`_answers` ni `assets.criticality`.
Autorización idéntica al resto del módulo (owner/admin/manager o
platform_admin). Idempotente: sobre una organización sin parámetros activos
devuelve `{"deactivated_parameters": 0, "deactivated_options": 0}` sin error.

En `CriticalityMatrixView.tsx`, el botón **"Nueva matriz en blanco"** solo se
muestra a owner/admin/manager/platform_admin (mismo chequeo que hace la RPC,
la UI es solo cortesía visual — la autoridad real sigue siendo el backend) y
exige confirmación explícita (`AlertDialog`) antes de llamar a la RPC. Tras
confirmar, la matriz activa queda vacía y la organización vuelve al empty
state ya existente ("Aún no hay parámetros de criticidad configurados"),
desde donde puede crear parámetros, importar un Excel o aplicar una plantilla
— incluida la que se acaba de guardar de la configuración recién desactivada.

## Contrato Excel

Dependencia: **ExcelJS 4.4.0** (npm, sin CDN). Ver "Dependencia" abajo.
Import dinámico (`await import('exceljs')`) para que quede en su propio chunk
(~939 KB) y no en el bundle principal.

### Hoja `Matriz` (exportar/importar configuración)

Columnas exactas y estables, una fila por opción (los datos del parámetro se
repiten en cada una de sus opciones):

```
Código parámetro | Parámetro | Descripción | Peso % | Orden parámetro |
Código opción | Opción | Puntaje | Orden opción | Activo
```

Más una hoja `Instrucciones`. Archivo: `criticidad_<organizacion>_<fecha>.xlsx`.

Flujo de importación: seleccionar `.xlsx` → parsear local → validar →
**preview** → confirmar → `replace_criticality_matrix`. Seleccionar el archivo
**nunca escribe nada**. El backend revalida todo de nuevo.

### Hoja `Evaluaciones` (evaluación masiva)

```
ID interno | Código activo | Activo | Ruta | <una columna por parámetro activo> | Notas
```

- **`ID interno` es `assets.id` (UUID real) y es la única identidad técnica**;
  código/nombre/ruta son referencia humana y nunca resuelven un activo.
- Las columnas de parámetros usan el **nombre humano** del parámetro y se
  resuelven contra la matriz viva cargada. Nombre ambiguo (dos parámetros
  activos con el mismo nombre) → error; columna de un parámetro activo
  faltante → error; columna desconocida → warning e ignorada.
- Los valores de celda son etiquetas de opción; se resuelven a `option_id`
  contra las opciones **activas** de ese parámetro (sin distinguir
  mayúsculas/acentos). Opción inexistente → error de fila. Respuesta vacía →
  error (`calculate_asset_criticality` exige todos los parámetros activos).
- Hoja `Opciones` (Código parámetro / Parámetro / Valores permitidos) + dropdown
  por columna cuando la lista cabe en el límite de Excel (255 caracteres); si
  no cabe, la hoja `Opciones` sigue documentándola. Los dropdowns nunca fueron
  requisito de cierre.
- Activos incluidos: los **no archivados**, exactamente la misma regla que ya
  usa el árbol de activos (`filterArchived` en `useAssets`). No se inventó un
  filtro nuevo.

Solo se leen archivos con el contrato que genera OneFacility; no se intenta
interpretar hojas arbitrarias.

### Preview y resultado

`preview_bulk_asset_criticality` devuelve por fila: `row_number`, `asset_id`,
`asset_code`, `asset_name`, `valid`, `score`, `calculated_criticality`,
`errors[]`, `warnings[]`. El frontend hace solo validación **estructural**
(UUID, resolución de etiquetas) y muestra el score que devolvió el servidor.

Con 100 filas / 92 válidas / 8 inválidas el usuario elige **Cancelar y
corregir** o **Importar 92 válidas** (solo esas 92 se envían a
`bulk_calculate_asset_criticality`). Al terminar se muestra el resumen
(evaluados / omitidos / críticos / altos / medios / bajos) y queda disponible
**Descargar errores** (.xlsx).

Excel nunca aporta criticidad: aporta respuestas, OneFacility calcula
score y criticidad.

## Dependencia Excel — por qué ExcelJS

| Candidata | Decisión |
| --- | --- |
| `xlsx` (SheetJS) | **Descartada**: la versión publicada en npm es 0.18.5, con advisories **high** sin fix en npm (prototype pollution y ReDoS) *en el parser mismo* — justo el código que procesaría archivos subidos por usuarios. Las versiones corregidas se distribuyen solo por su CDN, y el enunciado prohíbe CDN. |
| `write-excel-file` + `read-excel-file` | Descartada: serían dos dependencias para lo que una resuelve. |
| **`exceljs@4.4.0`** | **Elegida**: lee y escribe `.xlsx`, múltiples hojas, data validation (dropdowns), funciona en Vite/browser, sin Office, una sola dependencia. |

Honestidad sobre `npm audit`: ExcelJS aporta **2** entradas al listado
(`exceljs` y su transitiva `uuid`), ambas **moderate**, por
GHSA-w5hq-g745-h8pq — un fallo de bounds check de `uuid` v3/v5/v6 *cuando se
pasa un `buf` propio*, ruta que ExcelJS no usa. El "fix" que propone npm es
degradar a `exceljs@3.4.0` (major hacia atrás), peor remedio que la
enfermedad. Las otras 21 entradas del audit son preexistentes del proyecto
(vite, esbuild, react-router, postcss…). El perfil de riesgo sigue siendo
claramente mejor que el de `xlsx@0.18.5`.

## Preservación histórica

- Las evaluaciones y sus snapshots (`parameter_name`, `option_label`,
  `weight`, `option_score`, `weighted_score`) **no cambian nunca** al aplicar
  una plantilla o importar una matriz: verificado comparando el snapshot antes
  y después de un reemplazo (0 diferencias).
- La configuración anterior queda con `is_active = false`, **no se borra**:
  tras dos reemplazos la organización tenía 2 parámetros activos y 6 filas
  totales.

## Multitenancy

- Cliente B no ve (RLS), no puede leer por RPC ni aplicar una plantilla
  privada de Cliente A — probado con el UUID real.
- Cliente B no puede hacer preview ni bulk sobre la organización de A.
- Un UUID de activo de otro tenant escrito a mano en el Excel es rechazado por
  el backend (`El activo no pertenece a esta organización.`), no por el
  frontend.
- Sin `service_role` en frontend, sin bypass de RLS, sin policies nuevas de
  escritura.

## Limitaciones conocidas

- Cero plantillas `system` cargadas (a propósito, pendiente de negocio).
- Umbrales siguen fijos (25/50/75) — configurables sigue fuera de alcance.
- Sin versionado formal de matrices ni workflow de aprobación.
- Los dropdowns de Excel se omiten cuando la lista de opciones supera el
  límite de 255 caracteres de la lista inline.
- Las pruebas de UI (clics reales en el navegador) no se ejecutaron: este
  entorno no tiene herramienta de automatización de navegador. Lo que sí se
  ejecutó de verdad: la migración + 17 checks SQL contra el proyecto remoto en
  una transacción con `ROLLBACK`, y el contrato Excel end-to-end (export →
  import → validación) corriendo los módulos reales en Node.
