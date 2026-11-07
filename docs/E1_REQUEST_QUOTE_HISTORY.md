# E1-FIX02 — Solicitudes cotizadas y completadas

## Diagnóstico
El listado de Solicitudes consultaba únicamente `status = sent`. En el cliente Makro Test
la solicitud `SOL-MAKRO-006` existe con `status = quoted`, una cotización
`approved` y mínimo de 1/1; la RPC individual de cotizaciones sí era legible,
pero el listado la omitía. Lo mismo ocurría con solicitudes completadas.

## Cambio autorizado
- Vista de solicitudes: `sent`, `quoted`, `completed` con filtro visible por estado.
- Borradores continúan separados; `draft` y `anulado` no aparecen.
- Nueva opción `history` en `get_facility_management_requests(uuid,text)`:
  `sent` y `drafts` mantienen exactamente su semántica previa.
- Misma comprobación de `requests.view`, relación activa, membresía,
  asignación y aislamiento de cliente en el scope `history`.
- `get_facility_management_quote_counts` conserva `submitted_quotes`
  y agrega `received_quotes`: suma `submitted`, `approved`, `rejected`.
  El frontend muestra el recuento recibido; no se exponen importes.
- Filas `quoted` y `completed` se muestran solo lectura en `RequestList`.
  No se amplían operaciones de edición/anulación desde esa vista.
- Sin cambios en `quotes` RLS, reglas de aprobación, bloqueos de
  concurrencia, reglas `min_quotes`, payload de importes ni datos de negocio.

## Migración
`20261107233000_e1_request_quote_history.sql`

El helper `facility_management_quote_payload` de HF01 debe permanecer intacto.
La migración se aplica **antes** del merge a la rama productiva, después de
respaldo verificable y de pasar las pruebas de regresión.

## Pruebas
- `supabase test db --local`: toda la suite pgTAP; en particular
  `facility_manager_requests_access.test.sql` y
  `facility_manager_quotes_access.test.sql`.
- Verificar roles negativos: usuario no asignado, relación suspendida y otro cliente.
- Verificar en servidor la solicitud `SOL-MAKRO-006` visible en `history`
  y excluida en `sent`, y `SOL-595136` visible en ambos.
- Verificar importes protegidos: la RPC de cotizaciones de `SOL-595136`
  sigue enviando `amount = null`, `description = null`.
- `vite build` y comprobación de Vercel Preview.
- En Production, cuenta FM sin membresía directa: estados y detalles en
  `Solicitudes de Makro Test` y `SOL-MAKRO-006` con importe autorizado.
- Los borradores, anuladas y acceso a otros clientes deben seguir invisibles.

## Rollback
Si falla el frontend, revertir con el deployment anterior de Vercel.
La nueva RPC es aditiva: el frontend anterior continúa utilizando el scope
`sent` y el campo `submitted_quotes` anteriores. Por ello, en caso de
incidencia, **priorizar rollback del frontend**; no revertir funciones ni
historial de migraciones precipitadamente.

No alterar solicitudes, cotizaciones, permisos ni relaciones para la prueba.
