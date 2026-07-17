# AI_CONTEXT.md

## Proyecto
One Facility / Assetlink Connect.

## Objetivo del producto
SaaS multi-tenant para gestión de mantenimiento, solicitudes, cotizaciones, proveedores, facility managers, subcontratistas, órdenes de trabajo, evidencias y cierre de servicios.

## Estado actual
La rama `onefacility-design` contiene el mockup visual generado con Lovable.

La rama `productization/mvp` será la base de desarrollo productivo.

Desde este punto, Lovable se usará como diseñador visual y fuente de componentes UI, pero no como rama productiva directa.

## Ramas principales
- `onefacility-design`: rama de diseño / mockup / Lovable.
- `productization/mvp`: rama base productiva.
- `feature/*`: ramas por módulo o tarea.
- `fix/*`: correcciones puntuales.

## Stack tecnológico
Frontend:
- React
- Vite
- TypeScript strict
- Tailwind CSS
- shadcn/ui

Backend:
- Supabase
- PostgreSQL
- Supabase Auth
- Row Level Security activo por defecto

Archivos:
- Cloudflare R2 compatible con S3
- Supabase solo guardará metadatos, referencias y enlaces firmados

Deploy:
- Local con Supabase CLI
- Staging en Vercel
- Producción en Vercel

## Modelo multi-tenant
La entidad central es `organizations`, no el usuario.

Relación base:

auth.users
→ profiles
→ organization_members
→ organizations

Tipos de organización esperados:
- client_company
- provider_company
- facility_manager
- subcontractor_company
- platform_admin

Roles internos esperados:
- owner
- admin
- manager
- requester
- quote_manager
- technician
- operator
- viewer

## Reglas críticas
- No usar `localStorage` como fuente de verdad para permisos, usuarios, tenants o datos productivos.
- No hardcodear IDs como `client-1`, `provider-1`, `user-1` en lógica productiva.
- No crear tablas sin migración.
- No dejar policies abiertas tipo “Anyone can view”.
- No mezclar lógica mock con lógica productiva.
- Todo acceso a datos debe respetar tenant y RLS.
- Todo módulo productivo debe incluir UI, DB, RLS, validaciones, manejo de errores y logs mínimos.

## Flujo Lovable → Producción
1. Lovable trabaja sobre `onefacility-design`.
2. Los componentes visuales útiles se migran manualmente a ramas `feature/*`.
3. Codex o Claude Code refactorizan esos componentes.
4. Se eliminan mocks.
5. Se conectan hooks reales de Supabase.
6. Se actualizan tipos.
7. Se agregan migraciones y RLS.
8. Se prueba en local/staging.
9. Se hace PR hacia `productization/mvp`.

## Próximo objetivo técnico
Implementar la base multi-tenant productiva:

- organizations
- profiles
- organization_members
- roles/enums
- activity_logs
- audit_logs
- hooks base
- RLS inicial
- separación entre demo/mock y productivo

## Última actualización
Inicio de la rama `productization/mvp`.