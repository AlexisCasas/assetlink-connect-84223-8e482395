# ROMAX R2-E2.1 — Seguridad y permisos comerciales

## Estado
Implementación publicada en la rama `feature/romax-r2e2-1-pricing-access-security`, PR #128. CI integral y pgTAP PASS; revisión final pendiente. No aplicar a Supabase Cloud hasta autorización separada.

## Capacidades
- `market_cost.read`: consulta de costos de adquisición y proveedores.
- `market_cost.manage`: registrar/editar proveedores y costos en borrador/pendientes.
- `market_cost.validate`: aprobar/rechazar costos presentados por otra persona; no crear ni editar valores.
- `pricing_rules.manage`: administrar configuración FX existente.
- `commercial_price.read/propose/approve`: reservadas para R2-E2.5; todavía no dan acceso a precio de venta.

Owner/admin conceden y revocan capacidades a miembros activos. No se modifica el enum global de roles. Las concesiones son auditables y no se eliminan; la revocación es irreversible.

## RLS y triggers
- `provider_cost_rates` SELECT exige read/manage/validate; INSERT exige manage; UPDATE exige manage o validate, con guard trigger que separa cambios de borrador de la revisión.
- `provider_cost_suppliers` SELECT exige read/manage/validate; INSERT/UPDATE exige manage.
- `provider_cost_settings` INSERT/UPDATE exige pricing_rules.manage. SELECT de configuración sigue disponible para miembros de la organización para que el trigger de snapshot FX pueda leerla.
- El creador de una tarifa de costo no puede aprobar/rechazar su propio registro. Una tarifa aprobada conserva inmutabilidad; solo se puede cerrar vigencia/archivar con validate.
- Tabla de concesiones: RLS tenant-scoped, sin hard delete, revocación one-way, sin cambios a identidad/procedencia.
- No se agrega SECURITY DEFINER. Las políticas consultan la concesión propia bajo RLS y usan las funciones de rol existentes solo para administración owner/admin.

## Interfaz
- Sidebar y hash directo permiten abrir el shell del catálogo a cualquier miembro activo de proveedor.
- Catálogo técnico sigue siendo consultable.
- Recursos continúan bajo el gate de rol existente.
- Proveedores y Tarifas solo aparecen con capacidades de lectura.
- Owner/admin ven Permisos; el usuario se identifica por UUID porque perfiles ajenos no exponen correo.
- Usuarios con pricing_rules.manage ven Reglas para la configuración FX actual.
- Los controles de escritura se ocultan sin capacidad, pero RLS es el control efectivo.
- Las capacidades de precio de venta permanecen reservadas.

## Pruebas
- `supabase/tests/romax_r2e2_1_pricing_access.test.sql`: grants, RLS, aislamiento tenant, manage vs validate, revocación, settings y no auto-validación.
- `supabase/tests/romax_r2a_cost_catalog.test.sql`: actualizado para usar un validador distinto del creador.
- Workflow `.github/workflows/romax-r2e2-1-access-qa.yml`: cadena completa de migraciones/pgTAP en Supabase desechable, TypeScript, ESLint, contrato estático y Vite build.


## CI integral — PASS (27-nov-2026)

Ejecución verificada en el PR #128 y en el push de la rama, ambos sobre el commit `81e290251e32a9b8bdcadf5c7867fbaa40c991d0`.

- GitHub Actions PR run: https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/46022798672
- GitHub Actions push run: https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/46022789784
- Supabase aislado/no vinculado a Cloud: cadena completa de migraciones y 37 archivos pgTAP, 2,874 aserciones; `Result: PASS`.
- Regresión R2A: 22/22 aserciones.
- R2-E2.1 multiempresa: 38/38 aserciones.
- Frontend: TypeScript sin diagnósticos nuevos (se mantiene la línea base heredada de Index.tsx), ESLint, contrato estático de seguridad y Vite build: PASS.
- El stack local desechable se detuvo con `supabase stop --no-backup`: PASS.

Correcciones que quedaron cubiertas por el CI:
1. Sintaxis de dollar-quoting en pruebas pgTAP.
2. Identidad del usuario creador del costo en el fixture multiempresa.
3. Prueba de denegación de concesiones por un usuario no admin, diferenciando el guard de procedencia de la política RLS.
4. Preflight con planes explícitos de 22 y 38 pruebas y control estático para evitar dollar-quoting mal formado.

**Alcance no ejecutado:** no se aplicó la migración en Supabase Cloud, no se cambiaron concesiones reales, no se importaron precios ni históricos, no se hizo merge y no se desplegó a producción. El PR #128 permanece abierto y en Draft para revisión.

## No incluido
No aplicar migración en Cloud, no cambiar concesiones reales, no importar precios/históricos, no merge y no Vercel producción.
