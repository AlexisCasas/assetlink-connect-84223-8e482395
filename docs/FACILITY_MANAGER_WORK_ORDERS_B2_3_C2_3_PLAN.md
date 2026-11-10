# One Facility — 9C.6-B2.3 / C2.3 (D4): seguimiento FM del lado del cliente

## Contrato de seguridad (primera implementación)
- Solo **OT externas** pertenecientes a solicitudes válidas del cliente administrado. Internas y ajenas: NO.
- Las notas de seguimiento son **coordinación del Facility Manager en nombre del cliente**, no comunicación con la operadora. La versión inicial **solo es visible a miembros FM asignados a la misma relación específica**, no a miembros del proveedor ni a miembros cliente sin relación FM. Ampliar visibilidad a clientes/proveedores requerirá una nueva decisión explícita.
- Lectura: relación activa, FM activo, miembro asignado y activo, rol owner/admin/manager/requester; permisos `requests.view + work_orders.view` concedidos en **esa misma relación**.
- Escritura: rol owner/admin/manager y permiso adicional `work_orders.manage` en **esa misma relación**. La autenticación nunca se sustituye por identidad del cliente.
- Tabla nueva `public.facility_management_work_order_followups`: `id`, `client_organization_id`, `relationship_id`, `work_order_id`, `author_user_id`, `idempotency_key`, `body` (1–2,000 caracteres), `created_at`. Campos solo de adición; sin interfaz ni grants de UPDATE/DELETE.
- Se aplica RLS y FORCE RLS sin políticas; tabla sin permisos para roles de API. Acceso exclusivamente por funciones de lectura y escritura, `SECURITY DEFINER` con `search_path=''`.
- Funciones: `get_facility_management_work_order_followups(client, relation, OT, limit, offset)` devuelve notas con `authored_by_me`, no el ID real del autor; `add_facility_management_work_order_followup(...,body,idempotency_key)` guarda la autoría real sin devolver IDs internos de otros miembros.
- Auditoría: una entrada por nueva nota, con actor real, cliente, OT y relación; **sin copiar el texto** al registro de auditoría.
- Operación idempotente bajo `(relationship_id,work_order_id,idempotency_key)`; un reintento idéntico no genera nueva nota ni auditoría.
- Sin cambio en `work_orders.status`, `observations`, técnicos, responsables, `work_order_work_logs`, materiales, cotizaciones, costes ni RLS existente.

## Secuencia por puertas
1. **B2.3-B:** migración y pruebas pgTAP en rama. No aplicar a Supabase Cloud todavía.
2. **C2.3-C:** componente de lectura y formulario de nota añadido exclusivamente al detalle FM de OT externa, con validación de 2000 caracteres y estados vacíos/error. `work_orders.manage` es solo hint de UI; la función comprueba de nuevo la autorización.
3. CI en GitHub: suite SQL completa + regresión frontend y build; ejecutar una prueba aislada de concurrencia de idempotency_key antes de recomendar publicación.
4. **B2.3-D:** con nueva autorización, aplicar migración a Supabase Cloud en modo fail-closed (READ habilitada, WRITE sin `EXECUTE`). Verificar ACL, RLS y ausencia de datos nuevos.
5. Preview → revisión visual; QA de escritura real solo con permisos temporales acotados, datos de QA autorizados y revocación verificada.
6. Merge y Production **solo tras aprobación explícita**.

## Riesgos/limitaciones
- El plan Supabase Free no ofrece copia automática garantizada; el despliegue futuro deberá preparar reversión focalizada y preflight de datos, sin llamarlos respaldo completo.
- La primera versión **no reemplaza** bitácoras del proveedor y no comparte notas entre distintas relaciones FM.
- La creación de OT nueva de C2.2 sigue siendo un QA independiente pendiente, no se considera cerrada por D4.
