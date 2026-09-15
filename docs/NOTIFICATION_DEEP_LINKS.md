# Deep Links de Notificaciones y Navegación Contextual

Rama `feature/notification-deep-links`. Sin migración SQL — `organization_notifications`
ya traía todo lo necesario (`entity_type`, `entity_id`, `related_request_id`,
`related_quote_id`, `metadata`). Sin tabla nueva, sin React Router (el hash
router liviano que ya tenía `Dashboard.tsx` fue suficiente una vez corregido).

## Por qué fallaba `#work-orders?workOrder=<uuid>` antes

`Dashboard.tsx` hacía `window.location.hash.replace('#', '')` y comparaba el
string **completo** contra la lista de vistas válidas
(`ALL_VIEWS.includes(hash)`). Con query string, `"work-orders?workOrder=..."`
nunca hace match exacto contra `"work-orders"` → se interpretaba como vista
desconocida y se ignoraba. Además el único `useEffect` que leía el hash
corría una sola vez al montar (dependencia `[isPlatformAdminOrg]`), sin
listener de `hashchange` — Back/Forward tampoco funcionaban.

## Formato canónico del hash

`src/lib/entityNavigation.ts` es la única fuente de verdad.

```
#requests?request=<uuid>
#requests?request=<uuid>&quote=<uuid>
#work-orders?workOrder=<uuid>
#work-orders?workOrder=<uuid>&activity=<uuid>
#inspections?plan=<uuid>
#inspections?run=<uuid>
```

Todo id es un UUID real — nunca nombre, correlativo (`SOL-xxxxxx`,
`OT-2026-xxxx`) ni título. `?org=<organization_uuid>` es soportado como
parámetro adicional en cualquier hash (ver más abajo).

- `buildEntityHash(target: EntityNavigationTarget): string` — arma el hash.
- `parseEntityHash(hash: string): ParsedEntityHash` — separa la vista lógica
  (`pathname`, antes del `?`) de los query params, en vez de comparar el
  string completo. Esto es la corrección de la Fase 0.
- `navigateToEntity(target)` — hace `window.location.hash = buildEntityHash(target)`,
  disparando el mismo `hashchange` que Back/Forward/pegar URL/F5 ya generan.
- `resolveNotificationTarget(notification)` — la matriz completa (ver abajo).
- `handleNotificationNavigation(notification, markAsRead?)` — handler
  compartido: intenta `markAsRead` (best-effort, nunca bloquea), resuelve el
  target, navega. Es la única función que `NotificationBell.tsx` y
  `NotificationList.tsx` llaman — ninguno de los dos tiene su propio
  `if (notification.type === ...)`.

## Matriz `entity_type` → destino

`resolveNotificationTarget` se ramifica por `entity_type`, no por
`notification.type` — la mayoría de los tipos operativos
(`work_order_created`, `technician_assigned`, `work_order_due_soon`,
`work_order_overdue`, `work_completed`, `internal_request_created`,
`request_private_invitation`) ya traen un `entity_id` directamente navegable
y no necesitan ninguna rama propia.

| `entity_type` | Resolución | Notas |
| --- | --- | --- |
| `request` | `#requests?request=<entity_id>` | Cubre `request_private_invitation` e `internal_request_created` sin código especial — el proveedor invitado y el cliente usan el mismo hash; `Dashboard`/`requests` view decide el componente (`RequestList` vs `ProviderRequestList`) según `user.role`. |
| `quote` | `#requests?request=<related_request_id>&quote=<related_quote_id ?? entity_id>` | `quote_submitted`/`quote_approved`/`quote_rejected` (y cualquier otro `quote_*`) se emiten vía la ruta antigua `create_organization_notification`, que sí llena `related_request_id`/`related_quote_id` — se usan esas columnas directamente, `metadata.request_id`/`metadata.quote_id` son solo fallback, nunca inventados. |
| `work_order` | `#work-orders?workOrder=<entity_id>` | Directo. |
| `activity` | `#work-orders?workOrder=<work_order_id>&activity=<entity_id>` | `entity_id` es el id de la actividad, **no** el de la OT. Se resuelve con `select work_order_id from work_order_activities where id = entity_id` — una consulta normal sujeta a RLS (solo la organización operadora o `platform_admin` la leen); si RLS deniega o la actividad ya no existe, `resolveNotificationTarget` devuelve `null` (degrade controlado, nunca bypass). |
| `inspection_plan` | `#inspections?plan=<metadata.plan_id>` | **Nunca `entity_id`**. `entity_id` en estas notificaciones es una clave sintética de deduplicación (`md5(plan_id\|rule_id\|next_due_at)`, ver `generate_inspection_due_notifications()` en `20260830100000_inspection_scheduling_alerts.sql`) — el plan real solo vive en `metadata.plan_id`. |
| `inspection_run` | `#inspections?run=<entity_id>` | Preparado para una futura notificación real de ejecución; ningún trigger actual emite este `entity_type` todavía. |
| otro / `null` | `null` (no navega) | `handleNotificationNavigation` retorna `false`; el caller muestra su propio "no se pudo abrir". |

## Persistencia F5 / Back / Forward

`Dashboard.tsx` ya no lee el hash una sola vez al montar: `syncFromHash()` se
llama en el montaje **y** en cada evento `hashchange` (`window.addEventListener`).
Como el estado real vive en `window.location.hash` (no en un `useState`
inicializado una sola vez), F5 y pegar la URL en otra pestaña vuelven a
correr exactamente el mismo parseo después de que `AuthContext` hidrata la
sesión — no hace falta ningún estado adicional de "hidratación pendiente".
Back/Forward del navegador disparan `hashchange` de forma nativa.

`focus` (los ids parseados) es estado de React separado de `currentView`;
`handleViewChange` (clicks del Sidebar) lo limpia explícitamente para que
navegar a otra vista por el menú nunca arrastre un id de foco obsoleto.

## `?org=<organization_uuid>`

Implementado, no diferido. Cuando el hash trae `org` distinto de
`currentOrganization.id`, `Dashboard` busca ese id en `organizations` (ya
cargadas por `AuthContext` desde las membresías reales del usuario — misma
fuente que usa `OrganizationSwitcher`):

- Si pertenece: `setCurrentOrganization(target.id)` (método ya existente de
  `AuthContext`, sin necesidad de esperar ninguna carga adicional — las
  organizaciones del usuario ya están todas en memoria). El efecto se
  re-ejecuta solo (`currentOrganization?.id` es dependencia) y en la segunda
  pasada abre la entidad con la organización ya activa.
- Si no pertenece: toast *"No tienes acceso a la organización relacionada
  con este enlace."*, la vista solicitada se muestra igual pero sin abrir
  ningún foco — nunca un bypass, nunca cambia a una organización que el
  usuario no integra.

## Seguridad

Ningún paso de este trabajo relaja RLS ni agrega policies nuevas. El flujo es
siempre: URL → componente intenta cargar la entidad (`.find()` sobre datos ya
cargados con RLS, o una consulta puntual como la de `activity` arriba) →
Supabase/RLS decide → si no autorizado, el componente muestra un mensaje
controlado y permanece en el módulo correcto. Sin `service_role`, sin cliente
admin, sin policy abierta. `git grep -n "service_role" src` sigue sin
resultados.

## Componentes actualizados

- `NotificationBell.tsx` / `NotificationList.tsx`: ambos llaman únicamente
  `handleNotificationNavigation`. `NotificationList` además hace la tarjeta
  completa clickeable (`role="button"`, `cursor-pointer`) y agrega un botón
  "Ver detalle" explícito; "Marcar como leída" sigue siendo una acción
  separada con `stopPropagation`.
- `WorkOrdersList.tsx` / `TechnicianWorkView.tsx`: aceptan
  `focusWorkOrderId?`/`focusActivityId?`. Un `useRef` evita reabrir el
  diálogo en cada render — solo actúa cuando el id de foco realmente cambia.
  UUID inexistente o sin acceso → toast *"No se pudo abrir la orden de
  trabajo. Puede haber sido eliminada o ya no tienes acceso."* (técnico:
  variante que menciona reasignación), la vista de lista se mantiene.
- `WorkOrderDetailDialog.tsx` / `TechnicianWorkOrderDetailDialog.tsx`:
  aceptan `focusActivityId?`, lo pasan a la sección/lista de actividades
  correspondiente para resaltar (`ring-2 ring-primary`) y hacer
  `scrollIntoView`. MVP: solo resalta/ubica, no abre el formulario de
  reporte automáticamente.
- `RequestList.tsx` (cliente): acepta `focusRequestId?`/`focusQuoteId?`.
  Sin `focusQuoteId` abre el diálogo de detalle (`handleViewRequest`); con
  `focusQuoteId` abre `QuoteListDialog` (que además resalta la cotización
  concreta). Nota: esta lista solo carga solicitudes `status='sent'` (query
  preexistente, sin cambios) — una solicitud que ya pasó a
  `quoted`/`completed`/`anulado` degrada al mismo mensaje de "no se pudo
  abrir" que una inexistente; no es un hueco de seguridad, es la misma
  visibilidad que ya tenía esta lista antes de esta fase.
- `ProviderRequestList.tsx`: acepta `focusRequestId?`/`focusQuoteId?`.
  Busca sobre `requests` (ya filtrado por `is_public`/invitación privada vía
  RLS en `initializeAndLoadRequests`), nunca sobre `filteredRequests` — así
  un filtro de búsqueda/estado activo nunca oculta la solicitud enlazada.
  Sin acceso → *"La solicitud no existe o ya no tienes acceso."*, sin
  service role ni consulta administrativa.
- `InspectionsView.tsx`: acepta `focusPlanId?`/`focusRunId?`. Los `Tabs` de
  shadcn pasan de no controlados (`defaultValue`) a controlados
  (`value`/`onValueChange`) para poder cambiar de pestaña programáticamente.
  `focusRunId` abre `InspectionRunDialog` de inmediato (esa pieza ya carga
  el detalle vía su propia RPC con RLS y ya mostraba su propio error
  controlado); `focusPlanId` espera a que carguen los planes y abre
  `InspectionPlanDialog` en modo edición, o muestra el mensaje controlado si
  no se encuentra.
- `notificationLabels.ts`: se agregó la etiqueta faltante para
  `request_private_invitation` (tipo ya emitido en producción desde la fase
  anterior, sin entrada en el mapa de labels).

## Pendiente / limitaciones conocidas

- Sin pruebas de navegador automatizadas en este entorno (no hay Playwright
  ni herramienta equivalente configurada) — la verificación de esta fase fue
  estática (lectura de código, build, `tsc`) más el arranque del servidor de
  desarrollo (`npm run dev`, responde `HTTP 200`, sin errores de compilación
  de módulos). **Los 10 casos manuales del enunciado (click real, F5, Back/
  Forward con sesión autenticada) quedan pendientes de verificación manual
  por el equipo** antes de mergear — ver la lista exacta en la entrega de
  esta tarea.
- `#inspections?run=<uuid>` no tiene todavía ninguna notificación real que lo
  dispare (preparado para cuando exista).
- Deep link a una solicitud del cliente que ya no está en `status='sent'`
  (limitación heredada de `RequestList.tsx`, no de esta fase) muestra el
  mismo mensaje que una sin acceso.
