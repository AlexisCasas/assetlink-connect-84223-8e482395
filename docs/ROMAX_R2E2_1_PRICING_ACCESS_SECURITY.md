# ROMAX R2-E2.1 — Seguridad y permisos comerciales

## Estado
Implementación revisada en PR #128. Las dos migraciones se aplicaron a Supabase Cloud OneFacility el 27-nov-2026. El PR continúa abierto y en Draft; no se hizo merge ni despliegue Vercel de producción.

## Capacidades
- `market_cost.read`: consulta de costos de adquisición y proveedores.
- `market_cost.manage`: registrar/editar proveedores y costos en borrador/pendientes.
- `market_cost.validate`: aprobar/rechazar costos presentados por otra persona; no crear ni editar valores.
- `pricing_rules.manage`: administrar configuración FX existente.
- `commercial_price.read/propose/approve`: reservadas para R2-E2.5; todavía no dan acceso a precio de venta.

Owner/admin conceden y revocan capacidades a miembros activos. No se modifica el enum global de roles. Las concesiones son auditables y no se eliminan; la revocación es irreversible.

## RLS, triggers y defensa en profundidad
- `provider_cost_rates` SELECT exige read/manage/validate; INSERT exige manage y membresía activa; UPDATE exige manage o validate, con guard trigger que separa cambios de borrador de la revisión.
- `provider_cost_suppliers` SELECT exige read/manage/validate; INSERT/UPDATE exige manage y membresía activa.
- `provider_cost_settings` INSERT/UPDATE exige `pricing_rules.manage` y membresía activa. SELECT de configuración sigue disponible para miembros de la organización para que el trigger de snapshot FX pueda leerla.
- El creador de una tarifa de costo no puede aprobar/rechazar su propio registro. Una tarifa aprobada conserva inmutabilidad; solo se puede cerrar vigencia/archivar con validate.
- Tabla `provider_pricing_access_grants`: RLS tenant-scoped, sin DELETE ni TRUNCATE para service_role, revocación one-way, sin cambios a identidad/procedencia.
- Los INSERT comprueban explícitamente membresía activa. La RLS de la tabla de concesiones también impide que miembros inactivos consulten sus permisos.
- No se agrega SECURITY DEFINER. Las políticas consultan la concesión propia bajo RLS y usan las funciones de rol existentes solo para administración owner/admin.
- Índices de soporte para las FK `user_id`, `granted_by` y `revoked_by`.

## Interfaz
- Sidebar y hash directo permiten abrir el shell del catálogo a cualquier miembro activo de proveedor.
- Catálogo técnico sigue siendo consultable.
- Recursos continúan bajo el gate de rol existente.
- Proveedores y Tarifas solo aparecen con capacidades de lectura.
- Owner/admin ven Permisos; el usuario se identifica por UUID porque perfiles ajenos no exponen correo.
- Usuarios con `pricing_rules.manage` ven Reglas para la configuración FX actual.
- Los controles de escritura se ocultan sin capacidad, pero RLS es el control efectivo.
- Las capacidades de precio de venta permanecen reservadas.

## Migraciones aplicadas en Supabase Cloud
- `20261127154749_romax_r2e2_1_pricing_access_security`: concesiones por usuario/organización, RLS, triggers y separación manage/validate.
- `20261127155628_romax_r2e2_1_service_role_privilege_hardening`: revoca privilegios amplios de service_role sobre la auditoría y conserva SELECT/INSERT/UPDATE; agrega índices para FK.
- Proyecto: `hplchnsseylngjopgbtl`; estado `ACTIVE_HEALTHY`; PostgreSQL 17.6.1.147.
- `provider_pricing_access_grants`: 0 concesiones iniciales. No se otorgaron permisos reales automáticamente.
- Datos preservados: 2 tarifas, 1 proveedor y 1 configuración FX; ninguna tarifa/proveedor/configuración fue modificada.
- `service_role`: SELECT/INSERT/UPDATE permitidos; DELETE y TRUNCATE denegados.
- Security Advisor: 149 hallazgos, igual que la línea base previa; no aparecieron nuevos hallazgos de seguridad por estas migraciones.
- Performance Advisor: 74 FK sin índice, 24 auth_rls_initplan, 7 multiple_permissive_policies y 93 índices sin uso. Los tres índices de FK nuevos aparecen sin uso inmediato, pero se conservan para acelerar comprobaciones de integridad referencial.

## Observaciones operativas de ROMAX
- ROMAX tiene actualmente un único miembro activo: el owner. Puede administrar Permisos, pero no existe todavía un segundo usuario activo que pueda recibir `market_cost.validate`.
- Las dos tarifas preexistentes (una `approved` y una `rejected`) fueron revisadas por su mismo creador antes de R2-E2.1. Se preservaron sin alterarlas; la nueva regla de no auto-validación se aplica a nuevas decisiones/cambios, no reescribe el historial.
- Tras la migración, los costos/proveedores permanecen ocultos hasta que owner/admin asigne capacidades. No se crearon concesiones automáticas.
- Para validar futuras tarifas, agregar un segundo miembro activo a ROMAX y asignarle `market_cost.validate`.

## CI integral — PASS (27-nov-2026)
- [PR run #46029672570](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/46029672570) y [push run #46029661761](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/46029661761).
- Supabase local no vinculado a Cloud: 37 archivos pgTAP, 2,882 aserciones; `Result: PASS`.
- Regresión R2A: 22/22; R2-E2.1: 46/46.
- Frontend: TypeScript sin diagnósticos nuevos (baseline heredado de Index.tsx), ESLint, contrato estático y Vite build: PASS.
- Stack desechable detenido con `supabase stop --no-backup`: PASS.
- Las pruebas incluyen membresía desactivada con concesión retenida, denegación de lectura/escritura, no auto-validación y denegación de TRUNCATE para service_role.

## Integración pendiente
- PR #128 permanece Draft y no está mergeado. La cadena #122 → #123 → #126 → #127 → #128 sigue abierta en Draft.
- El head de PR #128 alinea los nombres de migración R2-E1.1/R2-E1.2 con las versiones ya aplicadas en Cloud (`20261127063621` y `20261127063641`). Los heads independientes de PR #122/#123 aún contienen los nombres anteriores; actualizar/rebasar esa cadena antes de merge y no ejecutar `supabase db push` desde esas ramas intermedias.
- No se importaron precios ni históricos, no se cambiaron concesiones reales, no se hizo merge y no se desplegó Vercel producción.

## Próximo paso
Completar la asignación explícita de capacidades (owner/admin) y habilitar un segundo miembro validador en ROMAX antes de continuar con R2-E2.2. La importación de precios/históricos y la activación comercial siguen siendo fases separadas.

## Actualización vigente — 27-nov-2026

Cadena #122/#123/#126/#127/#128 homologada, mergeada y desplegada; migraciones canónicas en Cloud, CI integral y complementaria PASS. #129 desplegado en a5483db. Usuario decide mantener solo propietario actual, sin segundo usuario ni perfiles nuevos. El trigger sigue bloqueando la auto-validación; pendiente diseño R2-E2.1B para compatibilizar operación de owner único con auditoría, RLS y permisos explícitos. No se ha aplicado excepción ni concedido capacidades en este cierre. QA comercial real pendiente. Ver [plan maestro actualizado](ROMAX_PILOT_MASTER_PLAN.md). Las observaciones anteriores son históricas, no gates actuales de merge.
