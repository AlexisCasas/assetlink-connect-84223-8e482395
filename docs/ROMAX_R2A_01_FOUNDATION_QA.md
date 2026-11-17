# ROMAX R2A-01 — Fundación aplicada y QA Cloud

**Fecha:** 17-nov-2026  
**Proyecto:** Supabase Cloud OneFacility `hplchnsseylngjopgbtl`  
**Organización:** ROMAX  
**Estado:** R2A-01 PASS; continuar con R2A-02 solo como siguiente gate independiente.

## 1. Cambios aplicados

Migraciones registradas en Supabase:
- `20261117185721_romax_cost_catalog_foundation`
- `20261117185936_romax_cost_catalog_foundation_hardening`

La primera crea:
- `provider_cost_categories`: 8 categorías activas (mano de obra, materiales, equipos, subcontratación, movilización, desmovilización, otros costos directos y gastos generales).
- `provider_cost_units`: 13 unidades activas normalizadas.
- `provider_cost_settings`: configuración por organización, PEN base y FX USD/PEN opcional.

La segunda aplica hardening:
- Índice para FK `provider_cost_settings.updated_by`.
- Políticas RLS de INSERT/UPDATE usan `(select auth.uid())` para evitar evaluación repetida.
- `updated_by` se asigna por defecto al actor autenticado y se valida en políticas.

## 2. Preflight

- Organización ROMAX encontrada, activa y de tipo `provider_company`.
- Dependencias verificadas: `touch_updated_at()`, `is_organization_member(uuid)`, `has_organization_role(uuid, organization_member_role[])`.
- Roles existentes: owner, admin, manager, requester, quote_manager, technician, operator, viewer.
- Las tres tablas no existían antes de la aplicación.
- No se configuró un tipo de cambio ficticio.
- No se insertó ninguna fila de configuración para ROMAX; el valor USD/PEN permanece pendiente de definición.

## 3. Pruebas ejecutadas en Cloud

Prueba transaccional bajo rol `authenticated`, con rollback al final:
1. Owner ROMAX puede insertar configuración PEN por defecto.
2. La configuración inicial no trae FX inventado; `updated_by` corresponde al actor.
3. Owner puede actualizar FX con fuente, fecha y referencia.
4. Usuario externo no puede consultar la configuración ROMAX.
5. ROLLBACK comprobado: cero filas persistentes de configuración para ROMAX.

Verificaciones estructurales:
- Categorías: 8/8 activas.
- Unidades: 13/13 activas.
- Settings ROMAX persistidos: 0 (intencional).
- RLS habilitado en las tres tablas.
- Políticas: lectura global autenticada para catálogos estáticos; acceso a settings por membresía y rol.
- `anon` no tiene SELECT en ninguna de las tres tablas.
- Migration history confirma ambas versiones.

pgTAP no está instalado en el proyecto Cloud; por eso se ejecutaron pruebas transaccionales SQL directas con rollback. No se instaló extensión de pruebas en producción.

## 4. Supabase Advisors

- Security: ninguna observación nueva para `provider_cost_*`. Permanecen alertas previas globales del proyecto (144 funciones SECURITY DEFINER accesibles a authenticated, 4 tablas RLS sin políticas y 1 alerta de protección de contraseñas); no son introducidas por R2A-01.
- Performance: se corrigieron los dos hallazgos de `auth_rls_initplan` y la FK sin índice de `updated_by`. El único hallazgo residual de esta fase es `unused_index` sobre `provider_cost_settings_updated_by_idx`, esperado en una tabla recién creada sin filas; se conserva porque cubre la FK.
- Health: sin hallazgos.

## 5. Alcance no modificado

- No se insertaron proveedores ni recursos.
- No se modificó inventario, clientes, sedes, contactos, histórico, solicitudes ni cotizaciones operativas.
- No se desplegó Vercel.
- R2A-02 y R2A-03 no se aplicaron.
- No se configuró tipo de cambio.

## 6. Siguiente gate

R2A-01 se considera cerrado. El siguiente paso será revisar/aplicar únicamente R2A-02 (proveedores y recursos), ejecutar sus pruebas, y detenerse antes de R2A-03.
