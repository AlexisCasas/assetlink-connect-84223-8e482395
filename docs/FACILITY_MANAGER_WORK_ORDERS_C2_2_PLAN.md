# One Facility — 9C.6-C2.2: creación delegada desde Solicitudes / Cotizaciones

**Estado:** frontend en rama PR C2.2, QA automatizado y visual pendientes. No se ha habilitado la ejecución en Supabase Cloud ni cambiado Vercel Production.

## Base y límites

- Base GitHub: `productization/mvp`, commit `417b611b`, tras merge PR #84.
- Backend B2.2-D: migración `20261110142255_fm_delegated_work_order_creation_staged` aplicada a Cloud.
- Las RPC `create_facility_management_internal_work_order` y `create_facility_management_work_order_from_quote` existen pero NO tienen `EXECUTE` para `authenticated/anon/service_role`.
- `work_orders.manage` no está concedido en ninguna relación al inicio de C2.2. **Ningún clic debe crear una OT hasta una autorización separada de activación y QA.**
- No modificar las RPC del cliente ni la RLS/ACL, no consultar directamente tablas `work_orders`/`quotes` en modo FM, no asignar técnico/planificador ni cambiar estado.
- El mecanismo de respaldo del plan Supabase Free no debe presentarse como un backup verificado: consultar `docs/FACILITY_MANAGER_WORK_ORDERS_B2_2_CLOUD_DEPLOYMENT.md`.

## Flujo UI

| Origen | Condición UI | Acción |
|---|---|---|
| Solicitud interna enviada/elegible | FM asignado owner/admin/manager; `requests.view + work_orders.view + work_orders.manage` | `Generar o abrir OT`; confirmar; RPC `create_facility_management_internal_work_order`; guardar ID en UI y abrir detalle seguro |
| Cotización externa aprobada | FM asignado owner/admin/manager; `requests.view + work_orders.view + work_orders.manage + quotes.view` | `Crear o abrir OT`; confirmar; RPC `create_facility_management_work_order_from_quote`; navegar al detalle seguro |
| Solicitud interna borrador/anulada | Nunca | Botón no disponible |
| Cotización no aprobada | Nunca | Botón no disponible |
| Roles requester o no asignados / falta grant | Nunca | Sin acciones delegadas de creación |
| Flujo de cliente directo | Permisos cliente existentes | Conserva funciones legacy; ningún cambio semántico |

### UX y concurrencia

- El botón es una pista UX, **no autorización**: cada RPC revalida identidad, asignación, rol, grants, origen y estado tras bloquear el registro.
- Confirmación expresa antes de cada escritura. `generatingRequestId`/`creatingWorkOrderId` deshabilitan nuevos clics durante la operación.
- Si la OT existe, la RPC devuelve la existente (idempotencia); interfaz nunca usa `INSERT` directo.
- `42501` / permiso revocado / endpoint no disponible se muestra como error de autorización sin revelar si un UUID ajeno existe.
- La lectura de detalle sigue usando `get_facility_management_work_order` tras navegar a `#managed-work-orders?...&workOrder=...`.
- El listado FM de cotizaciones nunca solicita proveedores, montos ni descripciones fuera del payload minimizado 9C.5.

## Puertas de entrega

1. TypeScript: solo los 3 diagnósticos heredados de `Index.tsx` permitidos por SHA de archivo; ningún diagnóstico nuevo.
2. ESLint focalizado, test estático de transporte/ACL/confirmación y `npm run build`: PASS.
3. Vercel Preview exacta del PR (no Production) READY y sin errores recientes.
4. QA manual con FM asignado: comprobar botones ocultos con grants revocados, confirmar modales, navegación y la ausencia de edición operativa.
5. **Antes de probar creación REAL:** autorización independiente para conceder `EXECUTE` exclusivamente a `authenticated`, otorgar temporalmente `work_orders.manage` a relación de QA, elegir fixtures aislados y autorizar OT de prueba o idempotencia; luego limpieza y revocación.
6. Cerrar C2.2 únicamente tras QA manual PASS, revisión de seguridad y merge autorizado. No efectuar deploy productivo por inercia.

**NO-GO actual:** no merge; no deploy a Vercel Production; no `GRANT EXECUTE` en Cloud; no `work_orders.manage` temporal ni creación de OT Cloud sin un nuevo control de autorización.
