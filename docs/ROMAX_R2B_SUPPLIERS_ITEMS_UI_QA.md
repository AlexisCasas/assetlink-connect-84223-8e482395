# ROMAX R2B — Interfaz inicial de proveedores y recursos

**Estado:** primera entrega funcional preparada en preview; sin merge ni producción.  
**Rama:** `feature/romax-r2a-cost-catalog`.

## Alcance implementado
- Nueva vista `CostCatalogView` dentro de la navegación del proveedor.
- Pestaña **Recursos**: listar, buscar, crear, editar, activar y desactivar conceptos reutilizables.
- Pestaña **Proveedores**: listar, buscar, crear, editar, activar y desactivar proveedores.
- Categorías y unidades se consultan de los catálogos predefinidos `provider_cost_categories` y `provider_cost_units`; no se permiten unidades o categorías libres.
- El proveedor es opcional en el modelo de tarifas y no se exige para registrar conceptos internos.
- No hay eliminación física desde la interfaz.
- No se crean clientes, sedes ni contactos; se reutilizarán los maestros comerciales existentes en las fases de oportunidades/cotizador.
- No se cargan tarifas, fuentes económicas ni tipo de cambio en esta entrega.

## Autorización de interfaz
- Solo organizaciones `provider_company`.
- Roles: owner, admin, manager y quote_manager.
- El gate se valida tanto en el menú lateral como en Dashboard para navegación directa por hash.
- Las tablas siguen protegidas por RLS en Supabase; el gate visual no sustituye las políticas de base de datos.
- Los inserts omiten `created_by` y dependen de su default `auth.uid()`; los updates no modifican `organization_id` ni `created_by`.

## QA y despliegue
- Vercel preview para commit `b276b0adb56b19b92a330671e04c896fe18c9b08`: **READY**.
- Check de estado Vercel en GitHub: **success**.
- No se desplegó a Production ni se fusionó el PR.
- No se ejecutó prueba CRUD desde una sesión autenticada real de navegador; queda pendiente validar carga, alta, edición, desactivación y errores de RLS en la preview.
- No se insertaron proveedores ni recursos reales. Los contadores permanecen en cero.

## Fuera de alcance
- Tarifas, versiones, aprobación y tipo de cambio (R2C/R2D).
- Integración con cotizador actual.
- Importación de proveedores desde archivos o Gmail.
- Proyecciones por oportunidad.

## Próximo gate
1. QA visual y CRUD en preview con usuario ROMAX autorizado.
2. Comprobar que un usuario de rol no autorizado no ve el menú y recibe acceso restringido por hash.
3. Confirmar que otra organización no puede consultar datos ROMAX.
4. Tras PASS, preparar R2C: registro de tarifas y vinculación opcional con proveedor.


## Confirmación funcional del usuario — 17-nov-2026

El usuario confirmó visualmente la vista previa y realizó registros de prueba desde la interfaz. Se verificó directamente en Supabase Cloud:
- Proveedores ROMAX: 1 registro activo, **Proveedor Test** (razón social Test Comercial SAC).
- Recursos ROMAX: 1 registro activo, **Material Test 001**, código `PR001`, categoría `MATERIAL`, unidad `UND`.
- Ambos registros tienen `created_by` asociado a una membresía activa con rol autorizado en ROMAX.
- Tarifas ROMAX: 0; no se crearon tarifas durante esta prueba.

**Resultado:** R2B PASS para navegación, carga de datos y altas de proveedor/recurso desde la vista previa. Las pruebas específicas de edición y desactivación no se declaran ejecutadas en esta confirmación.
