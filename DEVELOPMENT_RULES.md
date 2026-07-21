# DEVELOPMENT_RULES.md

> Las altas de organizaciones, invitaciones y membresías privilegiadas deben
> pasar por Edge Functions o backend administrativo. `SUPABASE_SERVICE_ROLE_KEY`
> está prohibida en frontend y sólo se permite en secretos de funciones/backend.

## Principios de desarrollo

1. Multi-tenant primero.
2. Seguridad desde base de datos con RLS.
3. TypeScript strict obligatorio.
4. Migraciones controladas.
5. Separación clara entre mock y producción.
6. No secrets en Git.
7. Cada módulo debe poder probarse con más de un tenant.
8. Cada feature debe ser pequeña, revisable y desplegable.
9. No romper la rama de diseño.
10. No hacer merges directos desde Lovable a producción.

## Branching

### Ramas principales
- `onefacility-design`: diseño, Lovable, mockup visual.
- `productization/mvp`: base productiva.
- `feature/*`: nuevas funcionalidades.
- `fix/*`: correcciones puntuales.
- `docs/*`: documentación.

### Flujo correcto
```bash
git checkout productization/mvp
git pull origin productization/mvp
git checkout -b feature/nombre-de-la-tarea
