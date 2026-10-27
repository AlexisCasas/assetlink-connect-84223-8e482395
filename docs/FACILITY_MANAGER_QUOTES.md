# Facility Manager · Cotizaciones delegadas (Fase 1 · Punto 9C.5)

- Migraciones: `supabase/migrations/20260930120000_facility_manager_quotes_access.sql` y
  `supabase/migrations/20260930180000_serialize_quote_decisions.sql` (§11.2).
- Pruebas: `supabase/tests/facility_manager_quotes_access.test.sql` (177 aserciones).
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
`requests.min_quotes` **o el cliente cerró el envío de cotizaciones**
(`requests.quotes_closed`). Es la misma regla que aplica ahora la UI directa
(`QuoteListDialog.loadQuotes`), aplicada **en el backend** a listados, detalle,
aprobación y rechazo. Mientras estén ocultos:

- `amount` es `null` y no aparece en ninguna otra parte de la respuesta;
- `can_approve` es `false` y `approve`/`reject` responden `55000`
  ("decidir a ciegas" anularía el propósito de la regla).

La respuesta sí informa `min_quotes`, `quotes_received`, `quotes_closed` y
`prices_visible`. Cerrar el envío revela los importes aunque no se haya llegado
al mínimo (es lo que promete el botón "Cerrar envío de cotizaciones y ver
precios"). Es seguro: cerrado, ningún proveedor puede cotizar (el recuento queda
fijo) y el FM no puede cerrar el envío (`quotes_closed` no está en la lista
blanca de `save_facility_management_request` ni en ninguna RPC delegada).

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
| Importes antes de `min_quotes` y sin cerrar el envío | Ocultos solo en la UI; la RLS ya los entrega | Ocultos **en el servidor** |
| Aprobar/rechazar con importes ocultos | Permitido | `55000` |
| Aprobar | owner/admin/manager/requester | owner/admin/manager |
| Rechazar con razón | La UI envía `NULL` | Admite razón opcional |
| Cerrar envío, observaciones, chat, Crear OT | Sí / disabled | No |
| Auditoría | Solo el trigger de notificación | + `audit_logs` |

## 9. Verificación

- pgTAP dedicado: **177/177**. Regresión completa local: **2184/2184**
  (2007 previas + 177), 19 archivos.
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

| Variante (para `authenticated` y `anon`) | Suite 9C.5 (177) |
|---|---|
| ACL actual | 177 ok |
| Sin `INSERT/UPDATE/DELETE/TRUNCATE` en **todas** las tablas públicas | 177 ok |
| Sin DML en `quotes, requests, request_details, request_provider_access, audit_logs, organization_notifications, work_orders` | 177 ok |
| Sin DML en `assets, client_branches, asset_criticality_assessments, maintenance_notices` (variante de 9C.4) | 177 ok |
| **Sin ningún privilegio de tabla** (ni `SELECT`) | 168 ok, 0 fallos; se omiten las 9 aserciones que leen tablas crudas a propósito |

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
suites. Con la ACL real todas pasan: **2184/2184** (2007 + 177).

### 11.2 Concurrencia real y corrección en el flujo directo

**Diagnóstico** (Supabase local, dos sesiones `psql` simultáneas, cada una
retiene su transacción 0,3 s para forzar el solape). `approve_quote` y
`reject_quote` no bloqueaban ninguna fila: ambas leían la cotización como
`submitted` antes de que la otra confirmara y el `UPDATE` final
(`WHERE id = ...`) no vuelve a comprobar el estado. Matriz **antes** de la
corrección (12 corridas por caso):

| Caso | Inconsistentes |
|---|---|
| Directo A vs directo B, aprobar/aprobar (cotizaciones distintas) | 7/12: **dos cotizaciones aprobadas** |
| Directo vs FM, aprobar/aprobar | 0/12 (el directo corría primero y el FM esperaba la fila) |
| FM vs directo, aprobar/aprobar | 8/12: **dos aprobadas** |
| FM vs FM, aprobar/aprobar | 0/12 (ya bloqueaba la solicitud) |
| Directo vs directo, misma cotización | 12/12: **aprobada por dos usuarios** |
| Directo aprobar vs directo rechazar (misma) | 11/12: aprobación "exitosa" y cotización rechazada |
| FM aprobar vs directo rechazar (misma) | 6/12: aprobación "exitosa" + **auditoría `quote_approved` de una cotización rechazada** |
| Aprobar vs rechazar de otra cotización (directo/FM, ambos sentidos), FM vs FM misma cotización, directo aprobar vs FM rechazar misma | 0/12 |

**Corrección** (`20260930180000_serialize_quote_decisions.sql`, migración nueva;
las históricas no se tocan): `approve_quote` y `reject_quote` toman
`FOR UPDATE OF request` en su primera lectura, el mismo bloqueo que ya usan
`approve_facility_management_quote` y `reject_facility_management_quote`. Todas
las decisiones sobre una solicitud (directas, delegadas o de `platform_admin`)
se ejecutan una detrás de otra y las comprobaciones de estado posteriores ven lo
confirmado por la anterior; la perdedora recibe el error de estado de siempre.
Cuerpo idéntico salvo esa cláusula; mismos roles, estados, mensajes,
`SECURITY DEFINER`, `search_path` y grants (reafirmados y verificados por pgTAP).
El orden de bloqueo es siempre solicitud -> cotización: sin interbloqueos.

**Matriz después** (15 corridas por caso, 165 en total): **0 inconsistencias** en
los 11 casos. En cada corrida: nunca dos cotizaciones aprobadas, una aprobación
exitosa deja la cotización aprobada y ninguna en `submitted`, la sesión perdedora
recibe el error de estado, y `audit_logs` solo contiene filas coherentes con el
estado final (una `quote_approved` por aprobación delegada exitosa, ninguna
sobre una cotización que terminó rechazada).

Casos probados: directo A vs directo B; directo vs FM; FM vs directo; FM vs FM
(manager y admin); aprobación simultánea de dos cotizaciones; aprobar vs
rechazar la misma y otra cotización, en todas las combinaciones directo/FM.

**Control negativo previo (9C.5):** quitando los `FOR UPDATE` de las RPCs
delegadas, 9 de 15 corridas dejaban dos aprobadas y dos auditorías.

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

- **Antes de este cambio** los importes se mostraban solo si
  `recibidas >= min_quotes` (`QuoteListDialog.loadQuotes`, "regardless of
  quotes_closed"), y el servidor delegado aplicaba la misma regla.
- El botón **"Cerrar envío de cotizaciones y ver precios"** hace
  `UPDATE requests SET quotes_closed = true` y fuerza `setShowPrices(true)` solo
  en el estado local. Al **reabrir** el diálogo se recalcula con
  `recibidas >= min_quotes`: si no se alcanzó, los importes vuelven a ocultarse.
  El mensaje del botón promete algo que no persiste.
- Cerrar impide nuevas cotizaciones (`can_provider_quote_request` exige
  `quotes_closed` falso), así que el recuento ya no puede crecer.

**¿Podía una solicitud quedar bloqueada?** Sí, para el FM: solicitud cerrada con
`recibidas < min_quotes` (por ejemplo, `min_quotes = 3` y solo respondieron 2).
- Delegado: importes ocultos, `can_approve = false`, aprobar/rechazar `55000`.
- Cliente directo: podía decidir a ciegas (el flujo directo no exige importes
  visibles).
- **Salida existente, sin cambiar reglas:** bajar `min_quotes` editando la
  solicitud (cliente directo, o FM con `requests.manage`; el formulario admite
  1-20 y `save_facility_management_request` valida `>= 1`). Cubierto por prueba.

**Solución aplicada (mínima):**
- `facility_management_quote_prices_visible` devuelve `true` si
  `requests.quotes_closed` es verdadero **o** `recibidas >= min_quotes`.
- `QuoteListDialog.loadQuotes` (flujo directo) aplica la misma condición
  (`recibidas >= min_quotes || quotes_closed`). Es el único cambio en el flujo
  directo: ahora el botón cumple lo que dice y los importes no vuelven a
  ocultarse al reabrir el diálogo. No cambia permisos, RLS ni RPCs directas.
- Una solicitud cerrada antes del mínimo ya no queda bloqueada para el FM.
- Sin cerrar el envío, `min_quotes` sigue protegiendo los importes: ocultos en
  servidor y en UI.
- Pruebas (6b): abierta y bajo el mínimo => ocultos y `55000`; tras cerrar =>
  visibles (listado y detalle), `can_approve` según rol, requester y otro FM
  siguen sin acceso, el delegado aprueba y el resto queda rechazado; el FM no
  puede escribir `quotes_closed`. Controles negativos: con la regla anterior
  fallan 8 aserciones; con importes siempre visibles fallan 12 o más.
- Smoke en navegador (local): cliente directo y FM manager ven los importes de
  una solicitud cerrada con 2 de 3 recibidas, al reabrir el diálogo.

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

### 12.1 Concurrencia directo/FM
Resuelta en §11.2 con una migración nueva. Cubierta por pgTAP (el cuerpo de las
cuatro funciones bloquea la fila de la solicitud) y por la matriz de §11.2.

### 12.2 Notificación al proveedor (`notify_quote_status_change`)
Revisado el disparador, `create_organization_notification` y la interfaz
(`useOrganizationNotifications`, `NotificationList`, `NotificationBell`):

- El texto es estático ("Tu cotizacion fue aprobada por el cliente."); no
  incluye nombre ni organización del actor.
- La fila guarda `actor_user_id = approved_by_user_id` (el uuid del usuario del
  FM) y el proveedor la lee completa por RLS (`select *`). Es el comportamiento
  histórico: con una aprobación directa se guardaba el uuid del usuario del
  cliente.
- La interfaz **no muestra ni usa** `actor_user_id`.
- Un proveedor autenticado **no puede resolver ese uuid**: `profiles` y
  `auth.users` le deniegan el acceso, y no ve `organization_members`,
  `organizations` ni `organization_relationships` del FM, ni `audit_logs`
  (comprobado con la sesión del proveedor y cubierto por pgTAP).
- Conclusión: sin fuga ni error demostrado. No se cambió la identidad auditada
  del actor ni el sistema de notificaciones. Observación residual: el uuid sí es
  legible mediante la API; si se quisiera ocultarlo, bastaría una vista o RPC
  de lectura sin esa columna (decisión de producto, no incluida).
