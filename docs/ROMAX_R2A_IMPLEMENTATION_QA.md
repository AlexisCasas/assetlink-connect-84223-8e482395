# ROMAX R2A — Implementación de tres migraciones controladas

**Rama:** `feature/romax-r2-cost-catalog-20261117`  
**Base:** `productization/mvp` en `3f724c84f656c599be88585dd5b92c948844ca0f`  
**Proyecto Supabase Cloud identificado por MCP:** `hplchnsseylngjopgbtl` (OneFacility, PostgreSQL 17.6.1).  
**Estado:** archivos SQL y prueba pgTAP preparados; CI aislado pendiente. Sin escrituras en Cloud.

## Decisiones implementadas

- Seis tablas iniciales; clientes/sedes/contactos existentes se reutilizan.
- Categorías y unidades son catálogos globales de solo lectura; unidades tienen alias canónicos, sin conversiones implícitas.
- Proveedores y recursos pertenecen a ROMAX y se crean bajo demanda.
- Proveedor opcional en tarifa para costos internos; un recurso admite varios proveedores.
- Tarifas conservan moneda original y FX snapshot. El costo PEN es generado.
- Configuración default USD/PEN permanece sin valor hasta que ROMAX registre tasa, fuente, fecha y referencia.
- Tarifas tienen versiones por organización + recurso + proveedor (NULL = costo interno).
- Una tarifa se registra como draft, pasa a pending_review y se aprueba/rechaza con identidad y fecha. El mismo usuario autorizado puede aprobar.
- Una nueva versión aprobada cierra la vigencia de la versión anterior que se solape; la versión anterior y su costo permanecen.
- Las tarifas aprobadas no permiten modificar valores económicos; la vigencia solo puede acortarse con razón de auditoría.
- RLS y permisos limitados a owner/admin/manager/quote_manager. Sin acceso anon, sin DELETE autenticado.

## Migraciones

| Archivo | Contenido |
|---|---|
| `20261117163000_provider_cost_reference_data.sql` | Categorías, unidades y configuración económica |
| `20261117163100_provider_cost_suppliers_and_items.sql` | Proveedores, recursos y restricciones tenant |
| `20261117163200_provider_cost_rates_versioning.sql` | Tarifas, FX snapshot, versiones y revisión |

## QA preparado

Prueba: `supabase/tests/provider_cost_catalog.test.sql` (38 aserciones pgTAP).

Cubre:
- Catálogos de referencia y acceso anon.
- Configuración de moneda y tipo de cambio.
- Dos proveedores para el mismo recurso.
- Costos internos sin proveedor.
- Unidad no coincidente y fuente que requiere proveedor.
- FK compuesta que impide proveedor de otro tenant.
- Versionado por proveedor y auto-cierre de vigencia.
- Aprobación por el mismo usuario y rechazo con motivo.
- Inmutabilidad de tarifas aprobadas.
- Snapshot FX estable ante cambios de configuración.
- Lectura aislada entre dos organizaciones y denegación al rol viewer.
- Denegación de hard delete para authenticated.
- Bloqueo de USD cuando no existe tipo de cambio predeterminado.

El workflow existente `.github/workflows/9c6-b1-isolated-db-qa.yml` se activa con cambios en `supabase/**` y ejecuta `supabase start` + `supabase test db` en stack local desechable. Está fijado a Supabase CLI **2.79.0**. Se conserva esa versión; el changelog de Supabase registra un breaking change de CLI v3 el 4-nov-2026 (local por defecto y confirmación para cambios hosted).

## Límites y gates

1. No ejecutar migraciones en Supabase Cloud desde esta rama.
2. No insertar proveedores, recursos, costos ni tipos de cambio reales.
3. No modificar clientes, histórico ROMAX, inventario, solicitudes o cotizaciones operativas.
4. No conectar el catálogo al cotizador hasta una fase posterior.
5. Abrir PR draft y esperar CI aislado. No mergear sin revisión del usuario.
6. Antes de una aplicación remota, verificar explícitamente el vínculo de proyecto. MCP identifica OneFacility como `hplchnsseylngjopgbtl`; `supabase/config.toml` contiene un `project_id` local diferente, por lo que el target remoto debe confirmarse con el estado de link de CLI y el proyecto MCP antes de cualquier push.

## Limitación de ejecución actual

El entorno de esta sesión no dispone de Supabase CLI ni acceso de red para instalarlo/ejecutarlo localmente. Por ello no se declara `supabase test db` como ejecutado ni PASS. La validación está preparada para el workflow aislado de GitHub Actions; el estado de CI debe consultarse después de abrir el PR.

**Producción permanece intacta.**
