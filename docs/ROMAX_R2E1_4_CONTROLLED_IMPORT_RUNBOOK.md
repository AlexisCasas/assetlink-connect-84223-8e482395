# ROMAX R2-E1.4 — Controlled import runbook

## Scope
Controlled ROMAX material catalog import after R2-E1.1 and R2-E1.2 Cloud migrations. Workbook source SHA-256: `abc09b6b9ce97292a3ba6863ff4b1a3ba42d2f4b1a664c4a874202035816b910`. The source workbook and generated import SQL are private artifacts and are deliberately not committed here.

## Cloud preflight (2026-11-27)
- OneFacility project was ACTIVE_HEALTHY.
- Baseline: 36 resources, 2 rates, 13 original units.
- R2-E1.1 migration `romax_r2e1_material_catalog_foundation`: applied through Supabase MCP.
- R2-E1.2 migration `romax_r2e1_2_unit_normalization`: applied through Supabase MCP.
- Units after migration: 19 (13 original + 6 presentation units).
- The four new taxonomy/source/batch tables were empty before import.
- GitHub PRs #122 and #123 remain open/draft and unmerged. Their source commits have CI PASS. Cloud migrations were applied directly from those PR files under the user's authorization; reconcile migration history with repository before any merge.

## Import partition
- 779 unique source identities, no source-code loss.
- 736 new canonical resource candidates; all start with `technical_validation_status='preliminary'`.
- 43 source identities remain staged for review without canonical item mapping. Seven have unresolved units (GL: 5, ZZ: 2); the other review cases include possible existing-resource matches and duplicate candidates.
- 11 families and 149 subfamilies imported. The source workbook has no assigned subfamily for the 779 materials, so no item was assigned a subfamily.
- No cost, sale price, FII, supplier, evidence URL or 273 historical price rows were imported.

## Import execution — PASS (2026-11-27)
The private SQL bundle was executed against the intended OneFacility Cloud project as one transaction. A first-run baseline gate checked the 36 original resources, 2 original rates, 13 legacy unit definitions and their fingerprints. Final verification passed:
- 772 total ROMAX resources = 36 original + 736 new.
- 736 new resources have technical status preliminary and a family assignment.
- 779 distinct source identities in one import batch; 736 confirmed source-to-new-item links and 43 `needs_review` unlinked identities.
- 11 families and 149 subfamilies.
- 19 units (13 original + 6 presentation units).
- The original 36-resource fingerprint is unchanged.
- The original two-rate count and rate fingerprint are unchanged.
- Batch status: `imported`.

The exact same private SQL was executed a second time. The matching completed digest was recognized; the run was a no-op and all counts remained unchanged. This verifies idempotency.

## Private execution artifact
The private `ROMAX_R2E1_4_import_controlled.sql` and ZIP bundle are not committed to the public repository because they contain ROMAX's source material identities. Workbook SHA and SQL SHA are checked before execution. The SQL uses one transaction, verifies the baseline and final state, and aborts on any mismatch.

## Post-import verification
1. 11 families and 149 subfamilies: PASS.
2. 779 unique source identities: PASS.
3. 736 new resources in preliminary state: PASS.
4. 43 source rows remain `needs_review` and unlinked: PASS.
5. 772 total resources; original 36 preserved by fingerprint: PASS.
6. Two original rates and rate fingerprint unchanged: PASS.
7. Exact repeat execution produced no duplicates: PASS.
8. No price history was loaded; R2-E2 remains responsible for history, FII, tax, validity and commercial permissions.

## Release boundaries
No merge or Vercel production deployment was performed. Pricing and historical-price imports remain out of scope. Next: R2-E1.5 catalog UI/visual QA, then R2-E2 commercial price governance.
