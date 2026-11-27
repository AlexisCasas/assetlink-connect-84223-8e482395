# ROMAX R2-E1.5 — Technical material catalog UI

## Scope
Read-only technical catalog interface integrated into the existing provider cost catalog. The existing Recursos, Proveedores and Tarifas tabs remain unchanged; a separate Catálogo técnico tab is added.

## Data sources
- `provider_cost_items`: 772 ROMAX resources, technical status and canonical unit.
- `provider_material_families`: 11 technical families.
- `provider_material_subfamilies`: 149 technical subfamilies.
- `provider_cost_item_sources`: 779 source identities, including 43 pending review.

All queries are scoped by the active organization ID and rely on existing Supabase RLS. The UI does not query `provider_cost_rates`, supplier cost details, FII or commercial history.

## User experience
- Search by source/internal code, name, description and technical specification.
- Filters for family, subfamily, unit, technical validation state and active/inactive resources.
- 25-row pagination.
- Read-only detail drawer/card shows original source identity and source classification.
- Pending view lists 43 unresolved source identities; GL and ZZ are explicitly labelled as units to confirm. Other rows are described generically as pending manual review because the current source schema does not store a granular review reason.
- Status labels distinguish preliminary technical state from legacy rows not yet assessed.
- Explicit notice: technical status is not commercial approval and does not enable quoting.

## Security and compatibility
- The existing dashboard route and provider manager role gate are reused.
- No write action, mapping confirmation, price, rate, supplier or history field is exposed.
- No migration or Supabase Cloud write is included.
- The existing Recursos, Proveedores and Tarifas views are retained.

## QA
A dedicated workflow `.github/workflows/romax-r2e1-5-ui-qa.yml` runs TypeScript no-new-diagnostics, ESLint on the two affected components, and Vite production build. The TypeScript check tolerates only the three pre-existing unchanged diagnostics in `src/pages/Index.tsx`.


## QA-01 / correctivo T06 — 27-nov-2026

Usuario reportó T01–T05/T07–T08 PASS, T06 FAIL. PR #129 movió detalle inmediatamente debajo de la fila, toggle único, campos originales Excel y diseño adaptable. CI 5/5 PASS: run 46061062570 específico y regresiones 46061062229/46061062268/46061062266/46061062278. Usuario confirmó que ya se muestra; QA-01 cerrado según reporte, validación móvil no detallada. Merge a5483db; Vercel production READY dpl_8B7CxzubNgfdijrurUrEDksVErVs. Sin cambios SQL ni datos comerciales. Ver [PR #129](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/pull/129) y [plan maestro actualizado](ROMAX_PILOT_MASTER_PLAN.md).
