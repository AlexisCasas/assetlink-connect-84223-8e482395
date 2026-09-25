# Matriz de criticidad configurable por organización

MVP que evoluciona el campo manual `assets.criticality` — no lo elimina ni lo reemplaza. Cada organización cliente puede configurar sus propios parámetros ponderados y opciones puntuadas, y evaluar un activo contra esa matriz para obtener una criticidad calculada.

## Relación con `assets.criticality`

`assets.criticality` sigue siendo la única columna de criticidad que un activo tiene, exactamente como antes:

- **Sin matriz configurada**: `assets.criticality` se comporta exactamente igual que hoy — un campo manual, editable desde `AssetDetail.tsx` vía `useAssets.ts`, sin ningún cambio de flujo.
- **Con matriz configurada y evaluación ejecutada**: `calculate_asset_criticality` calcula un resultado y **sobrescribe** `assets.criticality` con ese valor calculado. Esa es la "criticidad efectiva": la que se muestra en `AssetTree`, en el resumen de `AssetDetail`, y en cualquier otro lugar que ya leía `assets.criticality` — ningún lector existente necesitó cambiar.
- Un planner puede seguir editando `assets.criticality` manualmente en cualquier momento (el formulario de edición de `AssetDetail.tsx` no cambió). Eso simplemente sobrescribe el valor otra vez, como una edición manual normal — no crea una nueva evaluación.
- Cada evaluación queda congelada históricamente en `asset_criticality_assessments`/`asset_criticality_assessment_answers`, incluyendo un snapshot (`manual_criticality`) de lo que era `assets.criticality` justo antes de esa evaluación — así queda trazabilidad aunque `assets.criticality` en sí solo guarde el valor más reciente.
- `effective_criticality` en cada evaluación es siempre igual a `calculated_criticality` en este MVP — no existe todavía un override manual de un resultado calculado (ver "Próximos pasos").

`AssetDetail.tsx` muestra "Criticidad (efectiva)" con el valor de `assets.criticality`, y solo agrega el badge "Score: X (última evaluación)" cuando la evaluación más reciente sigue coincidiendo con el valor actual — si alguien editó manualmente la criticidad después de esa evaluación, el badge de score desaparece automáticamente (deja de "mentir" sobre un score que ya no corresponde al valor mostrado).

## Fórmula

Por cada parámetro activo respondido en una evaluación:

```
weighted_score = option_score * weight / 100
score = SUM(weighted_score) de todos los parámetros activos
```

Ejemplo con los 5 parámetros de referencia:

| Parámetro | Peso | Opción elegida | Puntuación | Aporte |
|---|---|---|---|---|
| Sin equipo de respaldo | 30% | No | 50 | 15.0 |
| Impacto operacional | 25% | Alto | 100 | 25.0 |
| Tiempo detenido | 20% | Corto | 0 | 0.0 |
| Frecuencia de falla | 15% | Ocasional | 50 | 7.5 |
| Disponibilidad de repuesto | 10% | No disponible | 100 | 10.0 |
| **Score total** | | | | **57.5** |

## Umbrales de clasificación (configurables por organización)

Migración `20260925120000_criticality_configurable_thresholds.sql` (Fase 1 · Punto 2). Cada organización configura tres puntos de corte; cada uno es el límite **inferior inclusivo** de su categoría:

```
score < medium_min                 → low (Baja)
medium_min <= score < high_min     → medium (Media)
high_min <= score < critical_min   → high (Alta)
score >= critical_min              → critical (Muy Alta)
```

- **Por defecto 25 / 50 / 75**, exactamente el comportamiento anterior. Una organización sin fila en `criticality_thresholds` usa esos valores; no se insertó ninguna fila al migrar.
- `is_default` se decide por **valores**, no por la existencia de la fila: "Restablecer valores por defecto" guarda 25/50/75 explícitos y sigue siendo `is_default = true`.
- Validación (en SQL, repetida en la UI solo como ayuda): numéricos, `>= 0`, máximo 2 decimales (se rechaza, nunca se redondea en silencio), estrictamente ascendentes. `medium_min = 0` está permitido, con advertencia porque "Baja" queda inalcanzable.
- Enum interno sin cambios (`low/medium/high/critical`); en la interfaz `critical` se muestra como **"Muy Alta"** (`ASSET_CRITICALITY_LABELS`, fuente única de etiquetas).
- **Fuente única de verdad**: `classify_criticality_score` es el único `CASE` de clasificación y solo lo usa `validate_and_score_asset_criticality`. `CriticalityAssessmentDialog` ya no calcula score ni clasifica: su vista previa llama a `preview_bulk_asset_criticality` con una sola fila (`previewAssessment`), solo cuando todos los parámetros están respondidos (sin score parcial) y descartando respuestas fuera de orden.
- **Snapshot histórico**: cada evaluación guarda `threshold_medium_min/high_min/critical_min`. Las evaluaciones anteriores se rellenaron con 25/50/75, exacto porque `calculate_asset_criticality` es el único escritor y siempre usó esos valores. Cambiar los umbrales **nunca** recalcula evaluaciones ni `assets.criticality`.
- Eventos nuevos (`criticality_assessed`): descripción en español ("Criticidad evaluada: Muy Alta (score 80.00)") y umbrales en el payload. Los eventos históricos no se modifican.
- RPC: `get_criticality_thresholds` (miembro activo o platform_admin; devuelve también el rango de score posible de la matriz activa y las categorías inalcanzables, calculados en SQL) y `set_criticality_thresholds` (owner/admin/manager o platform_admin). RLS de `criticality_thresholds` solo `SELECT`; sin escritura directa.

## `calculate_asset_criticality`: todas las respuestas o ninguna

`calculate_asset_criticality(p_asset_id, p_answers, p_notes)` exige que `p_answers` contenga exactamente una respuesta por cada parámetro **activo** de la organización del activo (ni de más, ni de menos, sin duplicados) — si falta alguno o sobra alguno, la función rechaza la evaluación completa antes de escribir nada. Esto evita que quede guardada una evaluación parcial que luego se lea como si fuera un score completo.

La función valida en dos pasadas: la primera solo valida y acumula el score (sin escribir nada); la segunda, una vez que el payload completo es válido, inserta el encabezado de la evaluación (con su score final ya calculado) y luego las respuestas congeladas.

## Fuentes de datos

| Tabla | Rol |
|---|---|
| `criticality_parameters` | Parámetros configurables por organización (nombre, peso, orden, activo/inactivo) |
| `criticality_parameter_options` | Opciones puntuadas de cada parámetro |
| `asset_criticality_assessments` | Una fila por evaluación ejecutada (score, criticidad calculada, snapshot de la manual, notas) |
| `asset_criticality_assessment_answers` | Snapshot congelado de la respuesta a cada parámetro en esa evaluación (nombre/etiqueta/peso/puntuación copiados, no referenciados en vivo) — así una evaluación pasada nunca cambia aunque después se edite o desactive un parámetro/opción |
| `assets.criticality` | Sigue siendo la criticidad efectiva mostrada en toda la app |
| `asset_events` (`event_type = 'criticality_assessed'`) | Un evento por evaluación, integrado automáticamente en `get_asset_integrated_history` |

## No bloqueo si la suma de pesos no es 100%

`CriticalityMatrixView.tsx` muestra la suma de pesos de los parámetros activos y una advertencia visual si no es 100% — **nunca bloquea** la creación de parámetros ni la ejecución de una evaluación. Es una decisión deliberada del MVP: forzar la suma exacta habría complicado el flujo de configuración inicial (crear parámetros uno por uno, ajustar pesos) sin aportar seguridad real — el cálculo de `calculate_asset_criticality` funciona correctamente con cualquier suma de pesos, simplemente el score deja de tener una interpretación "sobre 100" tan limpia si la suma no es 100%.

## Permisos

- **Lectura de la matriz** (`get_criticality_matrix`) y **del historial de evaluaciones** (`get_asset_criticality_assessments`): cualquier miembro activo de la organización, o `platform_admin`. Esto incluye a `technician` — puede ver la matriz si de algún otro flujo llegara a necesitarla, pero no tiene acceso a la navegación de configuración (ver abajo).
- **Escritura** (`upsert_criticality_parameter`, `upsert_criticality_option`, `set_criticality_parameter_active`, `set_criticality_option_active`, `calculate_asset_criticality`): solo `owner`/`admin`/`manager` de la organización, o `platform_admin`.
- Ninguna de las 4 tablas nuevas tiene política de `INSERT`/`UPDATE`/`DELETE` — todas las escrituras pasan exclusivamente por las RPCs `SECURITY DEFINER` de arriba (mismo patrón más estricto ya usado para `warehouses`/`materials`). No hay `DELETE` físico de parámetros/opciones, solo `is_active = false`.
- En el frontend, el ítem de navegación "Criticidad" solo aparece para `owner`/`admin`/`manager` de una organización `client_company` (el mismo universo de organizaciones que ya tiene "Activos" — los activos, y por lo tanto su matriz de criticidad, no existen para `provider_company`/`facility_manager` en este código). No aparece para `technician` ni para la organización `platform_admin`.
- Aislamiento entre organizaciones verificado: una organización no puede leer ni escribir la matriz ni las evaluaciones de otra.

## Historial de evaluaciones

`get_asset_criticality_assessments(p_asset_id)` devuelve todas las evaluaciones de un activo, más recientes primero, cada una con sus respuestas anidadas (`answers`, un `jsonb`) para no necesitar una segunda llamada al mostrar el detalle de una evaluación pasada. `CriticalityAssessmentHistory.tsx` lo muestra en la pestaña "Historial" de `AssetDetail.tsx`, junto al historial operativo general (`AssetHistory.tsx`).

## Limitación de interpretación

Igual que los indicadores de eficiencia (ver `docs/EFFICIENCY_DEVIATIONS.md`), esto es información operativa para apoyar una decisión, no una verdad absoluta: la matriz depende enteramente de cómo la organización configure sus parámetros y puntuaciones. Un score alto refleja la configuración elegida, no una medición objetiva externa.

## Continuación: Criticidad V2

Plantillas, contrato Excel (exportar/importar matriz, evaluación masiva) y el
refactor del motor de cálculo a un helper SQL común
(`validate_and_score_asset_criticality`) están documentados en
`docs/CRITICALITY_V2_TEMPLATES_EXCEL.md` (migración
`20260915120000_criticality_v2_templates_excel.sql`). Cambios relevantes para
lo descrito en este documento:

- `criticality_parameters`/`criticality_parameter_options` ganaron `code`
  (identificador técnico estable, único entre las filas **activas**);
  `get_criticality_matrix` lo devuelve. Los RPC manuales conservan su firma —
  un trigger genera el código cuando no se envía.
- `calculate_asset_criticality` mantiene exactamente su API pública, pero la
  validación y la fórmula ya no viven dentro: las delega al helper común, que
  también usan el preview y la evaluación masiva. La fórmula y los umbrales
  existen en un único lugar.
- Reemplazar la matriz (por plantilla o por Excel) sigue la misma regla de
  siempre: desactivar (`is_active = false`), nunca borrar; las evaluaciones
  históricas y sus snapshots quedan intactos.

## Próximos pasos (fuera de alcance de este MVP)

- ~~Umbrales configurables por organización~~ — implementado en Fase 1 · Punto 2 (ver "Umbrales de clasificación").
- Plantillas de matriz por industria — la infraestructura ya existe en V2 (`scope='system'`), pendiente solo la validación de negocio del contenido.
- Criticidad automática alimentada por datos reales de fallas (frecuencia real de reportes técnicos, tiempo de parada real desde `work_order_activity_reports`, en vez de una opción elegida manualmente).
- Recomendación automática de parámetros/pesos con IA.
- Simulación de escenarios ("¿qué pasaría si el peso de X subiera a 40%?") antes de guardar cambios en la matriz.
- Override manual explícito de `effective_criticality` distinto de `calculated_criticality`, con su propia trazabilidad — no implementado en este MVP.
