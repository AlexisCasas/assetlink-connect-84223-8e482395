# ROMAX R2-E1.4 — Controlled import runbook

## Scope
Controlled ROMAX material catalog import after R2-E1.1 and R2-E1.2 Cloud migrations. Workbook source SHA-256: `abc09b6b9ce97292a3ba6863ff4b1a3ba42d2f4b1a664c4a874202035816b910`. The source workbook and generated import SQL are private artifacts and are deliberately not committed here.

## Cloud preflight (2026-11-27)
- Project: OneFacility `hplchnsseylngjopgbtl`, ACTIVE_HEALTHY.
- ROMAX organization: `a76fb740-78cf-4ed5-97dd-1e1e24fcab68`.
- Baseline: 36 resources, 2 rates, 13 original units.
- R2-E1.1 migration `20261127063621_romax_r2e1_material_catalog_foundation`: applied through Supabase MCP.
- R2-E1.2 migration `20261127063641_romax_r2e1_2_unit_normalization`: applied through Supabase MCP.
- Units after migration: 19 (13 original + 6 presentation units).
- New taxonomy/source/batch tables exist and are empty. No materials, rates or source identities imported yet.
- GitHub PRs #122 and #123 remain open/draft and unmerged. Their source commits have CI PASS. The Cloud migrations were applied directly from those PR files under the user's authorization; reconcile migration history with repository before any merge.

## Import partition
- 779 source identities, no source-code loss.
- 736 new canonical resource candidates; all start with `technical_validation_status='preliminary'`.
- 26 existing-resource candidates held for manual mapping.
- 10 same-name/same-unit duplicate rows held for review.
- 7 unresolved units (GL: 5, ZZ: 2) held without canonical item.
- 11 families and 149 subfamilies.
- All 779 source identities are staged in `provider_cost_item_sources`; the 43 unresolved rows have `mapping_status='needs_review'`. The 736 created item identities are mapped to their own canonical item, but technical validation remains preliminary.
- No cost, sale price, FII, supplier, evidence URL or 273 historical price rows are imported.

## Private execution artifact
Use the private `ROMAX_R2E1_4_import_controlled.sql` bundle generated from the source workbook. Verify the SQL's workbook SHA and target project before running. Execute from a trusted local terminal using the project's direct database connection string stored only in the local environment:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f ROMAX_R2E1_4_import_controlled.sql
```

The SQL runs as one transaction and asserts the baseline of 36 resources and 2 rates before writing. It is idempotent by workbook digest and source identity. It verifies the expected final counts (772 resources, 779 source identities, 11 families, 149 subfamilies, 2 rates) before commit. Stop on any error; do not manually rerun partial inserts.

## Post-import verification
1. Confirm 11 families and 149 subfamilies for ROMAX.
2. Confirm exactly 779 source identities for the import batch.
3. Confirm 736 new resources have technical status preliminary.
4. Confirm 43 source rows remain needs_review and have no canonical resource mapping.
5. Confirm total ROMAX resources 772 and original 36 IDs unchanged.
6. Confirm rate count remains 2 and rate fingerprint unchanged.
7. Repeat the same SQL only if the first run completed; verify counts do not increase.
8. Do not load price history until R2-E2's commercial permissions and history model are ready.

## Release boundaries
No merge, Vercel production deployment, pricing import or historical-price import is included in R2-E1.4.
