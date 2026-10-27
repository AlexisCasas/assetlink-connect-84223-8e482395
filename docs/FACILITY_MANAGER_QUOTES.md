# Facility Manager · Cotizaciones delegadas (Fase 1 · Punto 9C.5)

- Migración: `supabase/migrations/20260930120000_facility_manager_quotes_access.sql`.
- Pruebas: `supabase/tests/facility_manager_quotes_access.test.sql` (162 aserciones).
- Frontend: `src/lib/quoteData.ts`, `QuoteListDialog` (modo `delegated`),
  `RequestList`, `useRequestScope`, `facilityManagement.ts`.

## 1. Qué es (y qué no es)

El Facility Manager **representa al cliente**: consulta las cotizaciones que
recibieron las solicitudes del cliente que administra y, si tiene autorización,
las aprueba o rechaza. **Nunca cotiza como proveedor**: las policies de
`INSERT/UPDATE/DELETE` de `quotes`, `can_provider_quote_request` e
`is_provider_facing_organization` no cambian y siguen dando `false` a un FM.

Mismo patrón que 9C.1–9C.4:

- La RLS de `quotes` **no se abre**. `can_user_read_quote` sigue exigiendo ser
  miembro del cliente o del proveedor.
- Todo pasa por RPCs `SECURITY DEFINER` (`search_path` vacío, `authenticated`,
  no `anon`) con respuesta minimizada.
- Acceso = relación `active` + cliente y FM activos + membresía activa
  **asignada** a esa relación + permisos + rol (helper de 9C.1).

## 2. Matriz

| Capacidad | Permisos (todos en la misma relación) | Roles del FM |
|---|---|---|
| Ver cotizaciones (`can_view_quotes_as_facility_manager`) | `requests.view` + `quotes.view` | owner, admin, manager, requester |
| Aprobar / rechazar (`can_approve_quotes_as_facility_manager`) | `requests.view` + `quotes.view` + `quotes.approve` | owner, admin, manager |

- technician, viewer, quote_manager y operator del FM no acceden.
- `quotes.approve` nunca sustituye a `quotes.view`; `requests.view` es requisito.
- **`quotes.manage` no abre ninguna operación** (ver §6). Concederlo no cambia
  nada.
- Relación `suspended`/`ended`, membresía inactiva o persona no asignada: `42501`
  de inmediato.

## 3. RPCs

| RPC | Qué hace |
|---|---|
| `get_facility_management_request_quotes(client, request)` | Resumen + lista de cotizaciones `submitted`/`approved`/`rejected` de una solicitud **externa y no borrador**. `NULL` si no existe, es de otro cliente, es interna o borrador (no distingue). |
| `get_facility_management_quote(client, quote)` | La misma respuesta filtrada a una cotización (deep link), bajo la clave `quote`. `NULL` si no es visible. |
| `get_facility_management_quote_counts(client)` | `[{request_id, submitted_quotes}]` para la columna "Cotizaciones". Sin importes. |
| `approve_facility_management_quote(client, quote)` | Aprueba. Misma lógica que `approve_quote`: las demás en revisión pasan a rechazadas ("Not selected"). |
| `reject_facility_management_quote(client, quote, reason?)` | Rechaza una cotización en revisión; razón opcional (recortada, máx. 1000). |

Helpers internos (no ejecutables por clientes):
`can_view_quotes_as_facility_manager`, `can_approve_quotes_as_facility_manager`,
`facility_management_quote_prices_visible`, `facility_management_quote_payload`,
`facility_management_request_quotes_payload`.

Errores: `42501` sin permiso **o** cotización inexistente/de otro cliente/de un
borrador (misma respuesta, sin enumeración por UUID); `55000` estado no
permitido; `22023` razón demasiado larga.

## 4. Ocultación de importes (en el servidor)

`amount` solo se devuelve cuando las cotizaciones recibidas
(`submitted` + `approved` + `rejected`, sin borradores) alcanzan
`requests.min_quotes`. Es la regla que la UI directa aplica al recargar
(`QuoteListDialog.loadQuotes`), ahora aplicada **en el backend** a listados,
detalle, aprobación y rechazo. Mientras estén ocultos:

- `amount` es `null` y no aparece en ninguna otra parte de la respuesta;
- `can_approve` es `false` y `approve`/`reject` responden `55000`
  ("decidir a ciegas" anularía el propósito de la regla).

La respuesta sí informa `min_quotes`, `quotes_received`, `quotes_closed` y
`prices_visible`. `quotes_closed` **no** revela importes (igual que el flujo
directo tras recargar).

## 5. Qué devuelve y qué no

Cotización: `id, request_id, status, description, created_at, amount (o null),
approved_at, approval_reason (solo aprobadas), rejected_at, rejection_reason,
can_approve`. El nombre del proveedor tampoco se entrega (la UI directa ya
muestra "Proveedor").

Nunca: `provider_id`, `provider_organization_id`, `team_member_id`,
`created_by_user_id`, `approved_by_user_id`, `rejected_by_user_id`,
`client_observation`, `subtotal`, `igv_amount`, `utilities_*`,
`general_expenses_*`, `base_subtotal`, `quote_sections`, `sales_conditions`,
`emailed_at`, ni id de orden de trabajo.

Aprobar/rechazar bloquean la fila de la solicitud (`FOR UPDATE`) para
serializar decisiones concurrentes y escriben `audit_logs`
(`facility_management.quote_approved` / `quote_rejected`) con
`organization_id` = cliente y **sin importes**.

## 6. `quotes.manage` y `client_observation` (investigado)

- `client_observation` solo se escribe desde `QuoteListDialog.handleSaveObservation`
  con un `UPDATE` directo a `quotes`.
- El botón "Agregar/Editar observaciones" está **`disabled`** en el flujo directo
  y la única policy de `UPDATE` de `quotes` es del proveedor
  (`has_organization_role(provider_organization_id, …)`). Un cliente que lo
  intentara afectaría 0 filas **sin error**.
- Conclusión: es una función ya inoperante para el cliente directo (fallo
  heredado confirmado por lectura de policies y UI). No hay operación de
  gestión validada que delegar, así que **no se creó ninguna** y `quotes.manage`
  queda sin efecto hasta definir su alcance.
- El otro candidato — "Cerrar envío de cotizaciones" — escribe
  `requests.quotes_closed` sobre `requests`; pertenece a `requests.manage` y no
  se tocó.

## 7. Frontend

- `canFacilityManagerViewQuotes` / `canFacilityManagerApproveQuotes`
  (`facilityManagement.ts`).
- `RequestScope.canViewQuotes` pasa a depender de `quotes.view`; nuevo
  `canApproveQuotes`. `canGenerateWorkOrder` sigue en `false`.
- `RequestList` delegado carga solo los conteos (`get_facility_management_quote_counts`)
  y abre `QuoteListDialog` con `delegated={{ clientOrganizationId }}`.
- `QuoteListDialog` en modo delegado: lee con la RPC, no consulta `requests`,
  `request_provider_access`, `quotes` ni `work_orders`; sin "Cerrar envío",
  "Contactar", observaciones ni "Crear orden". Los botones Aprobar/Rechazar
  dependen de `can_approve` del servidor.
- `quote=` del hash abre el diálogo solo con `quotes.view`.
- El flujo directo no cambia (mismas consultas, botones y RPCs).

## 8. Diferencias con el flujo directo del cliente

| Aspecto | Cliente directo | FM delegado |
|---|---|---|
| Lectura | RLS sobre `quotes` | RPC minimizada |
| Importes antes de `min_quotes` | Ocultos solo en la UI; la RLS ya los entrega | Ocultos **en el servidor** |
| Aprobar/rechazar con importes ocultos | Permitido | `55000` |
| Aprobar | owner/admin/manager/requester | owner/admin/manager |
| Rechazar con razón | La UI envía `NULL` | Admite razón opcional |
| Cerrar envío, observaciones, chat, Crear OT | Sí / disabled | No |
| Auditoría | Solo el trigger de notificación | + `audit_logs` |

## 9. Verificación

- pgTAP dedicado: **162/162**. Regresión completa local: **2169/2169**
  (2007 previas + 162), 19 archivos.
- Controles negativos (mutación temporal en la base local, restaurada):
  importes siempre visibles (12 fallos), payload que siempre incluye `amount` (4),
  rol technician en lectura (2), aprobar sin comprobar ocultación (4),
  `quotes.approve` sin `quotes.view` (3), payload con `provider_organization_id`
  (4), auditoría con importe (1), requester con aprobación (5).
- Smoke visual local (navegador integrado, Supabase local, fixtures
  temporales eliminados): FM manager ve 2/2 y 2/3 en la columna, importes en
  la solicitud completa y ninguno en la oculta (sin rastro en el DOM), aprueba
  y la otra queda "Not selected"; FM requester ve importes pero sin botones;
  el cliente directo conserva Cerrar envío, Contactar, Aprobar/Rechazar y
  observaciones.
- No se ejecutó nada contra Supabase Cloud.

## 10. Pendiente / fuera de alcance

- `quotes.manage` sin operación (§6). Decidir su alcance antes de implementarlo.
- Órdenes de trabajo (9C.6, incluida "Crear OT" desde una cotización aprobada)
  y reportes (9C.7).
- Chat de cotizaciones (hoy deshabilitado también para el cliente).
- Corrección del comportamiento directo con importes ocultos (aprobar a ciegas):
  decisión de producto, no se tocó.

## 11. Verificaciones adicionales (revisión de 9C.5)

### 11.1 ACL estricta
Las variantes se ejecutan dentro de una transacción descartable (prefijo
`BEGIN; REVOKE …` + el archivo de prueba, cuyo `ROLLBACK` final también deshace
el `REVOKE`), así que no queda ningún cambio en la base.

| Variante (para `authenticated` y `anon`) | Suite 9C.5 (162) |
|---|---|
| ACL actual | 162 ok |
| Sin `INSERT/UPDATE/DELETE/TRUNCATE` en **todas** las tablas públicas | 162 ok |
| Sin DML en `quotes, requests, request_details, request_provider_access, audit_logs, organization_notifications, work_orders` | 162 ok |
| Sin DML en `assets, client_branches, asset_criticality_assessments, maintenance_notices` (variante de 9C.4) | 162 ok |
| **Sin ningún privilegio de tabla** (ni `SELECT`) | 156 ok, 0 fallos; se omiten las 6 aserciones que leen tablas crudas a propósito |

Conclusión: las cinco RPCs no necesitan acceso directo a tablas; todo lo hacen
como `SECURITY DEFINER`. Las aserciones omitidas solo comprueban que el FM
**no** puede leer ni escribir `quotes`, `work_orders` ni notificaciones por la
vía cruda (con el `SELECT` revocado esa garantía la da el propio privilegio).

Suites heredadas bajo esas variantes: fallan algunas que usan DML directo como
`authenticated` o que aseveran los grants (`asset_default_responsible`,
`automatic_alerts`, `facility_manager_assets_criticality_access`,
`facility_manager_requests_access`, `organization_access_hardening`,
`public_table_meta_privilege_hardening`). **Los resultados son idénticos con y
sin la migración 9C.5** (se compararon quitando sus 10 funciones dentro de la
misma transacción): no son regresiones, es la dependencia histórica de esas
suites. Con la ACL real todas pasan: **2169/2169** (2007 + 162).

### 11.2 Concurrencia real
Dos sesiones `psql` simultáneas contra la base local, como el mismo FM
manager, aprobando cotizaciones distintas de una misma solicitud (se retiene la
transacción 0,3 s para forzar el solape).

- Función real: 12 corridas escalonadas (aprobar/aprobar y aprobar/rechazar) y
  15 simultáneas: **0 inconsistencias**. Siempre una sola cotización aprobada,
  las demás `rejected`, la sesión perdedora recibe `55000`, y la auditoría tiene
  exactamente una fila `quote_approved` (sin `quote_rejected` extra).
- **Control negativo:** quitando los dos `FOR UPDATE` (solicitud y cotización)
  la misma prueba produce **9 de 15 corridas con dos cotizaciones aprobadas y
  dos auditorías**. Se restauró la función y se repitió: 10/10 consistentes.

El bloqueo de la fila de `requests` es, por tanto, necesario y suficiente.

### 11.3 Deep link `quote=` (navegador, Supabase local)
`#requests?managedClient=…&request=…&quote=…`:

| Caso | Resultado |
|---|---|
| FM manager asignado | Abre el diálogo y resalta la cotización |
| Cotización/solicitud de **otro cliente** | No abre diálogo; aviso genérico "No se pudo abrir la solicitud"; ningún dato en el DOM |
| Relación **suspendida** | "Cliente no disponible: no tienes acceso delegado…" |
| FM manager **no asignado** | El mismo mensaje; ningún dato en el DOM |

### 11.4 Mínimo de cotizaciones y cierre anticipado
**Comportamiento actual (sin cambios):**

- Los importes se muestran si `recibidas >= min_quotes`
  (`QuoteListDialog.loadQuotes`; el comentario del código dice "regardless of
  quotes_closed"). El servidor delegado aplica la misma regla.
- El botón **"Cerrar envío de cotizaciones y ver precios"** hace
  `UPDATE requests SET quotes_closed = true` y fuerza `setShowPrices(true)` solo
  en el estado local. Al **reabrir** el diálogo se recalcula con
  `recibidas >= min_quotes`: si no se alcanzó, los importes vuelven a ocultarse.
  El mensaje del botón promete algo que no persiste.
- Cerrar impide nuevas cotizaciones (`can_provider_quote_request` exige
  `quotes_closed` falso), así que el recuento ya no puede crecer.

**¿Puede una solicitud quedar bloqueada?** Sí, para el FM: solicitud cerrada con
`recibidas < min_quotes` (por ejemplo, `min_quotes = 3` y solo respondieron 2).
- Delegado: importes ocultos, `can_approve = false`, aprobar/rechazar `55000`.
- Cliente directo: puede decidir a ciegas (el flujo directo no exige importes
  visibles).
- **Salida existente, sin cambiar reglas:** bajar `min_quotes` editando la
  solicitud (cliente directo, o FM con `requests.manage`; el formulario admite
  1-20 y `save_facility_management_request` valida `>= 1`). Cubierto por prueba.

**Solución mínima propuesta (no aplicada, requiere decisión comercial):** que
`facility_management_quote_prices_visible` devuelva `true` también cuando
`requests.quotes_closed` sea verdadero, y que `QuoteListDialog.loadQuotes`
(`setShowPrices(count >= min || quotesClosed)`) haga lo mismo en el flujo directo.
Es seguro para 9C.5: solo el cliente (o quien edite la solicitud) cierra el
envío, el FM delegado no puede cerrarlo (`quotes_closed` no está en la lista
blanca de `save_facility_management_request`) y, una vez cerrado, ningún
proveedor puede añadir cotizaciones, así que el recuento queda fijo.

**Conteos tras aprobar/rechazar:** `get_facility_management_quote_counts` cuenta
solo `submitted`, así que baja al decidir; `quotes_received` y `prices_visible`
**no** cambian (cuentan `submitted + approved + rejected`). Cubierto por pgTAP
(5.1, 5.3 y 6b), incluida la paridad entre aprobación directa y delegada.

## 12. Revisión de seguridad de las cinco RPCs

| Control | Resultado |
|---|---|
| Identidad | `auth.uid()` nulo ⇒ `42501`; ninguna RPC recibe `user_id`, FM ni membresía |
| Relación, asignación, rol y permisos | Un único helper (`has_facility_management_operational_access_all`) en las cinco; pruebas por rol, persona no asignada, membresía inactiva, relación suspendida y cada combinación de permisos |
| Otros clientes | Toda consulta filtra por `organization_id = _client_organization_id`; id de otro cliente, inexistente o de borrador ⇒ `NULL` (lecturas) o `42501` (decisiones), con el mismo mensaje |
| Importes ocultos | `amount` es `null` en listado, detalle y respuestas de decisión; sin rastro en el resto del JSON (prueba por texto) |
| Datos sensibles | Lista blanca exacta de claves verificada por prueba; sin proveedor, usuarios, desglose económico, observaciones ni OT |
| FM como proveedor | `INSERT/UPDATE/DELETE` crudos rechazados o a 0 filas; `can_provider_quote_request` y `is_provider_facing_organization` ⇒ `false`; no puede usar `approve_quote`/`reject_quote` |
| `SECURITY DEFINER` / `search_path` / grants | Las 5 RPCs: definer, `search_path=""`, `EXECUTE` solo `authenticated`; los 5 helpers sin `EXECUTE` para clientes. Verificado en `pg_proc` |
| Mensajes de error | 16 mensajes estáticos; ninguno interpola ids, importes ni nombres |

Hallazgos (no corregidos, fuera de 9C.5):
1. `approve_quote` / `reject_quote` (flujo directo) **no bloquean** la solicitud
   ni la cotización; dos aprobaciones directas concurrentes podrían dejar dos
   cotizaciones aprobadas, y una directa concurrente con una delegada también.
   Se deduce de la lectura del código; no se probó experimentalmente.
   Corrección mínima: añadir los mismos `FOR UPDATE`.
2. `notify_quote_status_change` guarda como `actor_user_id` al usuario del FM en
   la notificación del proveedor (solo el uuid, igual que con un usuario del
   cliente). No se revisó la UI del proveedor.
