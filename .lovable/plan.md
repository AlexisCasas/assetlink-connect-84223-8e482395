## Objetivo

Rehacer el formulario de Nueva Solicitud del módulo Cliente para soportar título de la solicitud, metadata real del creador, y reemplazar "Tienda" por "Sucursal" con autocompletado de Ciudad y Sede a partir de una tabla administrable de sucursales.

## 1. Base de datos

**Nueva tabla `client_branches`** (sucursales administrables):
- `id`, `client_email` (dueña), `name`, `city`, `site` (sede), `address`, `is_active`, `created_at`, `updated_at`
- RLS: el cliente dueño (por `client_email = auth.email()`) puede CRUD; otros autenticados solo SELECT (para que un cliente que ve una solicitud pueda ver el nombre de la sucursal aunque no sea suya — opcional). De momento aplicamos solo dueño con SELECT abierto a `authenticated` para mockup.

**Tabla `requests`** — agregar columnas (no destructivo):
- `title text` (nullable por compatibilidad; el form lo exigirá)
- `branch_id uuid` (referencia lógica a `client_branches.id`, nullable)
- `created_by_user_id uuid` (auth.uid del creador)
- `created_by_name text`
- `created_by_email text` (espejo de `created_by` por claridad; mantener `created_by` existente)

Mantenemos `city`, `store`, `branch` actuales como snapshot histórico. `store` queda en BD por compatibilidad pero ya no se llena desde la UI (se mantiene igual a `site` para compatibilidad con vistas viejas), o se deja vacío.

**Seed**: insertar 4 sucursales demo para el cliente `cliente@demo.com` (Plaza Vea Marina/Tacna/Marina, Plaza Vea Centro/Lima/Centro, Plaza Vea Norte/Lima/Norte, Tienda Arequipa Principal/Arequipa/Principal).

## 2. Tipos

`src/types/request.ts`:
- Añadir a `Request`: `title?`, `branchId?`, `createdByUserId?`, `createdByName?`, `createdByEmail?`
- Nuevo tipo `ClientBranch { id, name, city, site, address?, isActive }`

## 3. Formulario `RequestForm.tsx`

- Reemplazar arrays hardcoded `CITIES/STORES/BRANCHES` por carga desde `client_branches` (filtradas por `client_email = user.email` y `is_active = true`).
- Estado: `title`, `branchId`. Eliminar selectores manuales de Ciudad y Sede; pasarlos a inputs `readOnly bg-muted` autocompletados por `branchId`.
- Reordenar grid de Cabecera según UX especificado (3 filas).
- Validaciones: `title`, `branchId`, `description`, `deadline` obligatorios. Si la sucursal seleccionada no tiene `city`/`site`, mostrar warning toast.
- En submit, mapear: `city = branch.city`, `branch (sede) = branch.site`, `store = branch.site` (compatibilidad), guardar `title`, `branchId`, `createdByUserId = user.id`, `createdByName = user.name`, `createdByEmail = user.email`.
- Quitar el campo "Tienda".

## 4. Listado `RequestList.tsx`

- Mostrar columna "Título" justo después de "Nro. Solicitud" (visible por defecto).
- Etiqueta de columna "Tienda" → "Sucursal" (mantener key interna para compatibilidad de localStorage de columnas, solo cambiar label).
- En filtros: renombrar "Tienda" a "Sucursal" en UI.
- Preview inline / título destacado.

## 5. Detalle `RequestDetailDialog.tsx`

- Encabezado principal: `request.title` grande; `request.requestNumber` como subtítulo.
- Bloque metadata: Creado por (`created_by_name` / `created_by_email`), Fecha de creación, Sucursal, Ciudad, Sede.

## 6. Nueva pantalla "Sucursales"

- `src/components/branches/BranchesList.tsx`: tabla con CRUD (crear/editar/desactivar) sobre `client_branches` del usuario actual.
- Agregar entrada en `Sidebar` (solo cliente).
- Agregar ruta/sección en `Index.tsx` o `Dashboard.tsx` (donde estén las secciones del cliente).

## 7. Compatibilidad

- Solicitudes existentes sin `title` → mostrar `requestNumber` como fallback en listado/detalle.
- Sin `branchId` → mostrar los valores existentes de `city`/`store`/`branch` tal cual.
- No borrar columnas existentes en BD.

## Archivos a tocar

```
supabase/migrations/<new>.sql        (nueva tabla, columnas, RLS, seed)
src/types/request.ts                  (campos nuevos + ClientBranch)
src/components/requests/RequestForm.tsx
src/components/requests/RequestList.tsx
src/components/requests/RequestDetailDialog.tsx
src/components/branches/BranchesList.tsx  (nuevo)
src/components/layout/Sidebar.tsx
src/pages/Index.tsx (o donde se ruteen las secciones cliente)
```

## Criterios de aceptación

Los 11 puntos de la especificación: crear con título, mostrarlo en listado/detalle, creador automático, sin "Tienda", autocompletar Ciudad/Sede desde Sucursal, pantalla de admin de sucursales, sin perder detalles ni romper el flujo existente.
