# ROMAX R1-E — Consulta del histórico de cotizaciones en One Facility

**Estado:** implementación frontend en PR, sujeta a QA CI y revisión visual antes de habilitar en producción.

## Objetivo y alcance

Permitir que ROMAX consulte las 25 cotizaciones de 2026 cargadas en R1-D1, sin crear cuentas de clientes externos, solicitudes ni cotizaciones operativas ficticias. La pantalla es **solo lectura** y puede utilizarla un miembro activo de una organización `provider_company`.

- Ruta: `#quote-history`, también accesible desde el menú del proveedor como **Histórico cotizaciones**.
- Búsqueda: cliente comercial, sede homologada, descripción del servicio, fecha desde/hasta y correlativo.
- Los correlativos pueden buscarse explícitamente por **número impreso en PDF** o **número en el nombre del archivo**, porque el lote incluye discrepancias.
- Tabla paginada en Supabase (15 registros por página, conteo exacto), ordenada por fecha descendente e ID estable.
- Detalle: referencia impresa, referencia de archivo, cliente/sede de origen, título del servicio, fecha, estado de validación de importes y documento PDF original.
- Documento: consulta por demanda de metadatos en `commercial_quote_history_documents` y vínculo HTTPS al archivo Drive, protegido **también por los permisos propios de Google Drive**. No hay copia pública ni uso de tokens o service_role.
- Cinco cotizaciones con cliente no homologado aparecen en filtro **Cliente por confirmar**.
- Corrrelativo `RMX-2026-0212` debe devolver dos trabajos distintos; `RMX-2026-0180` aparece por número impreso y `RMX-2026-0199` por nombre de archivo.
- No se muestran importes mientras `price_review` no sea `verified`; los 25 del piloto siguen pendientes.
- El estado comercial `unverified` se muestra como **Sin confirmar**, sin presumir envío, aprobación ni adjudicación.

## Arquitectura y permisos

- `src/lib/commercialQuoteHistory.ts` es el adaptador de lectura con consultas explícitamente filtradas por la `currentOrganization.id` del contexto autenticado, sin recibir IDs arbitrarios de URL.
- El servidor aplica también RLS en `commercial_quote_history`, `commercial_quote_history_documents`, `commercial_clients` y `commercial_client_sites`.
- No hay escritura desde la pantalla: consultas SELECT de datos del propio tenant. Ni `anon` ni organizaciones ajenas reciben los registros.
- La navegación se oculta a `facility_manager`, `subcontractor_company`, `client_company` y `platform_admin`. Un enlace manual `#quote-history` se valida de nuevo en Dashboard, no solamente en Sidebar.
- El cambio de organización limpia filas, filtros, documentos y detalle anterior; los efectos descartan respuestas de consultas obsoletas.
- La lista recupera solo metadatos mínimos; las referencias privadas del PDF se consultan al abrir el detalle. No usar service_role ni document IDs en URLs de la aplicación.

## Criterios de aceptación / QA visual

| QA | Comprobación | Resultado esperado |
| --- | --- | --- |
| E1 | Ingresar como ROMAX proveedor activo | Menú Histórico cotizaciones visible; histórico inicial muestra 25 |
| E2 | Filtro por Makro | 10 cotizaciones |
| E3 | Filtro por Cassinelli | 9 cotizaciones |
| E4 | Filtro por Oechsle | 1 cotización |
| E5 | Filtro Cliente por confirmar | 5 cotizaciones sin asignar empresa ficticia |
| E6 | Correlativo impreso RMX-2026-0212 | 2 resultados distintos |
| E7 | Correlativo impreso RMX-2026-0180 | 1 resultado |
| E8 | Correlativo por nombre de archivo RMX-2026-0199 | 1 resultado, alerta por discrepancia |
| E9 | Filtro por servicio y fechas, paginación | Solo resultados coincidentes, total exacto, navegación estable |
| E10 | Abrir detalle de documento | Nombre de PDF y botón Drive, únicamente si usuario tiene permiso Drive |
| E11 | Importes sin validar | "Sin validar"; ningún precio inventado ni presupuestos marcados como aprobados |
| E12 | Cambiar de ROMAX a otra organización | No quedan datos, filtros ni documentos del tenant anterior |
| E13 | Acceder mediante hash en organización cliente/FM/admin/subcontratista | Denegado aunque se conozca la URL |
| E14 | RLS con owner ROMAX vs usuario de otro tenant | 25/25 vs 0/0, ver QA R1-D1 |
| E15 | Regresión | Solicitudes, OT, métricas e indicadores de FM siguen operativos |

## Fuera de alcance

- No importar más PDF ni validar sus cifras en esta fase; R1-D2 queda pendiente.
- No crear, editar, aprobar ni enviar cotizaciones comerciales.
- No generar propuestas con IA, exportaciones masivas ni vínculos a Drive públicos.
- No resolver automáticamente los cinco clientes pendientes, R1-B (19 contactos excepcionales) o las siglas H16.

## Gates

1. Revisar PR y ejecutar compilación Vite, lint y QA existentes.
2. Inspeccionar previsualización Vercel si está disponible, y ejecutar E1–E15.
3. Solicitar autorización expresa antes de merge y despliegue en producción si no está ya otorgada para esta fase.
4. Verificar tras el deploy que ROMAX lee el histórico y que el menú no aparece en cuentas no proveedoras.
5. Documentar SHA, PR, despliegue y resultado del QA en `docs/ROMAX_PILOT_MASTER_PLAN.md`.

**Referencias:** `docs/ROMAX_R1D_PILOT_IMPORT_QA.md` y `docs/ROMAX_R1D_HISTORICAL_QUOTES.md`.
