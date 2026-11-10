# One Facility — 9C.6-D · Cierre integral de QA
**Estado: en evaluación.** Este archivo es una matriz de evidencias y criterios de cierre, NO un certificado de PASS hasta observar los workflows del commit exacto.

## Línea base Cloud y restricciones (2026-11-10)

- GitHub base: `productization/mvp`, merge D4 `56faaab3e834a2f30f268c75e8a3a520cbc883a8`.
- Vercel Production: `one-facility.vercel.app`, deployment `dpl_BDZrz5B8XuN64XEvM91Z4zkk9drX` del merge D4, READY.
- Supabase One Facility: 29 OT, hash `64a83b25e58142ca0ba9979ebbb8d8c7`; 14 auditorías y 1 nota D4 de QA. Sin grants `work_orders.manage`, sin tareas de QA pg_cron.
- B2.2 D3: `create_facility_management_internal_work_order`, `create_facility_management_work_order_from_quote`: `EXECUTE` revocado para authenticated.
- D4: lectura de seguimiento habilitada para autenticados y autorizados; escritura `EXECUTE` revocada. No conceder escrituras solo por aprobar la matriz.
- **No existe cotización Makro Test aprobada sin OT**. Existe **una solicitud interna elegible sin OT**. Crear OT nueva en Cloud requiere autorización **separada**, identificador de solicitud confirmado, y tratamiento explícito de los efectos reales. El plan Supabase Free no aporta backup completo verificado.

## Matriz de aceptación (contrato D1–D7, códigos OT-01–OT-21)

| Caso | Comportamiento esperado | Prueba/evidencia exigida | Estado de cierre |
|---|---|---|---|
| OT-01 | FM asignado y permisos completos ve lista/detalle sanitizados | `facility_manager_work_orders_read_access.test.sql`; integral D | Por verificar CI D |
| OT-02 | Sin `work_orders.view` no accede | Suite de lectura + permisos | Por verificar CI D |
| OT-03 | `work_orders.view` sin `requests.view` no accede | Suite de lectura | Por verificar CI D |
| OT-04 | Owner FM no asignado queda fuera | Suite de lectura/gestión | Por verificar CI D |
| OT-05 | Relación suspendida/inactiva bloquea | Suite de lectura + gestión | Por verificar CI D |
| OT-06 | OT ajena y otro FM se deniegan | Suite de lectura + integral D | Por verificar CI D |
| OT-07 | FM sin membresía cliente usa acceso delegado; no SELECT crudo | Integral D + RLS/ACL | Por verificar CI D |
| OT-08 | Usuario con doble membresía respeta contexto/tenant | Suite `facility_manager_ui_integration.test.sql` + QA manual | Mixto; confirmar manual |
| OT-09 | Estados de OT externa visibles sin operaciones del proveedor | Suite B1 + inspección visual | Mixto; confirmar manual |
| OT-10 | Estados de OT interna visibles con alcance correcto | Suite B1 + inspección visual | Mixto; confirmar manual |
| OT-11 | Precio y textos ocultos bajo mínimo de cotizaciones | Suite B1/B2.2 + UI | Por verificar CI D |
| OT-12 | Precio visible solo con condiciones de cotización | Suite B1/B2.2 + QA previo de Makro | Por verificar CI D |
| OT-13 | No acceso FM a partes, evidencias ni materiales | Suite B1 + comprobación UI | Mixto; confirmar manual |
| OT-14 | Revocación corta accesos/caché | Suite B1 + D4 + cambio de sesión/refresh | Mixto; confirmar manual |
| OT-15 | `work_orders.manage` sin view no autoriza gestión | Suite B2.1/B2.2 | Por verificar CI D |
| OT-16 | FM no asigna técnico ni cambia estados externos | Suite B1/B2.2 + QA de UI | Por verificar CI D |
| OT-17 | OT interna terminal no admite planificación | Suite B2.1 | Por verificar CI D |
| OT-18 | Crear OT concurrentemente es idempotente | `run_fm_work_order_creation_concurrency.sh` | Por verificar CI D |
| OT-19 | Deep link permitido solo si cliente y asignación coinciden | Suite B1 + QA manual de deep link | Mixto; confirmar manual |
| OT-20 | Cliente directo/proveedor continúa operativo | Pruebas SQL heredadas + navegación cliente/proveedor | Mixto; confirmar manual |
| OT-21 | SQL integral + concurrency + seguridad frontend + build + Preview | 2 pipelines HEAD, Preview READY | Por verificar CI D |

**Extensión D4:** nota externa isolada por relación FM, autor real, auditoría sin texto, una nota por clave de idempotencia, lectura posible tras revocar manage. Prueba `facility_manager_work_order_followups_access.test.sql` (44 casos) + `run_fm_work_order_followups_concurrency.sh` y `run_fm_9c6_d_integral_regression.sh`.

## Secuencia de ejecución automatizada

- PostgreSQL aislado: `supabase start`, `supabase test db` (regresión de **todas** las migraciones y suites existentes).
- Sesiones concurrentes B2.2: creación OT interna desde solicitud sintética y OT externa desde cotización aprobada sintética, exactamente una OT y una auditoría por origen.
- Sesiones concurrentes D4: una nota del cliente por misma clave, exactamente una auditoría, sin texto en audit log.
- **Nuevo recorrido D** (siempre tras B2.2 y D4): FM sin membresía directa del cliente abre lista+detalle B1, reintenta ambas creaciones D3, planifica OT interna B2.1 y rechaza CAS obsoleto, lee y reintenta nota D4, niega lectura a usuario ajeno, revoca `manage` y comprueba denegación inmediata de escrituras. El recorrido abre una transacción con **ROLLBACK** y no persiste modificaciones.
- CI frontend C1/C2: TypeScript (sin regresiones nuevas respecto a los 3 diagnósticos heredados de Index.tsx), ESLint focalizado, comprobación de privilegios de RPC, build Vite.
- Vercel Preview por PR: verificar commit exacto, sin errores de build.

## QA manual protegido en producción

Usar usuarios y relaciones **ya autorizados**, sin crear roles nuevos:
1. FM QA Test → Makro Test: lista, filtros, refresh, OT interna y externa, deep link de OT autorizada.
2. OT-MAKRO-011: nota D4 visible con nombre/fecha correctos, **formulario de escritura ausente**; datos operativos del proveedor no editables.
3. Otras OT: comprobar importes solo si `prices_visible` verdadero; sin paneles operativos del proveedor.
4. Cambiar de usuario/organización: el contexto y caché no mezclan OT de clientes distintos.
5. Cliente directo y proveedor: los módulos habituales siguen accesibles conforme a permisos previos.
6. No probar `Generar OT` real si sigue oculto: eso es **esperado** porque `work_orders.manage=0` y D3 `EXECUTE` revocado.

## Gate explícito pendiente de Cloud para creación NUEVA

- Cobertura **automática aislada** demuestra creación real de OT interna y externa bajo privilegios sintéticos y concurrencia.
- **Cobertura navegador en Cloud de creación nueva** sigue **PENDIENTE**. Solo existe solicitud interna elegible `SOL-468525` en Makro Test; está prohibido consumirla como QA real sin autorización explícita que acepte la creación persistente de una OT nueva y detalle de limpieza/archivado. No existe cotización externa aprobada pendiente de OT para prueba sin agregar datos.
- Antes de cualquier ventana: preflight de OT/auditorías/permisos; GRANT por relación específica con cron de revocación comprobado; ACL para `authenticated` únicamente de la RPC elegida; creación controlada; postcheck de idempotencia, autoría y ausencia de efecto lateral; revocar y comparar hash.
- Evitar ejecutar pruebas SQL del runner contra Supabase Cloud: los scripts dependen de Docker descartable y usan identidades sintéticas.

## Cierre de 9C.6-D

**GO del QA automatizado:** CI SQL y frontend verdes sobre el mismo HEAD + Vercel Preview READY; scripts local-only y ROLLBACK. **GO parcial de producción:** lectura y notas D4 ya verificadas, OT nuevas sin autorización. **Cierre integral total:** QA manual regresivo OT-08/09/10/13/14/19/20 y decisión explícita sobre aceptación de la brecha del QA en Cloud de creación nueva. Solo fusionar PR de pruebas y cambiar estado de fase tras autorización específica. No hacer migraciones ni nuevas escrituras en Cloud durante esta etapa sin permiso.
