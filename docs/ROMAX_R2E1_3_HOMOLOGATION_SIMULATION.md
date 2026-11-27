# ROMAX R2-E1.3 — Homologation and import simulation

## Scope and safety
Read-only simulation against the supplied ROMAX workbook and a read-only snapshot of the current ROMAX cost catalog. The source workbook, supplier details, evidence URLs and price values are private inputs and are not committed to this public repository. The generated reconciliation workbook remains private.

This increment does not call Supabase, create resources, write rates, change inventory, approve prices, or import history. It produces a row-level plan for R2-E1.4.

## Source structure and integrity
- 779 unique material source codes; code sets in Matriz materiales and Dados de Alta agree exactly. Names and raw units agree between those two sheets.
- Taxonomy master: 11 families and 149 unique subfamilies. Ten families are used in Dados de Alta; Otros is unused.
- Dados de Alta assigns a family to all 779 rows but assigns no subfamily. Forty keyword-based family suggestions differ from the supplied family; they are review flags only and do not overwrite the source.
- Matriz materiales has 775 blank family cells and four populated family values that conflict with Dados de Alta. The import simulation retains the intake family as preliminary source metadata; it does not silently reconcile these conflicts.
- 273 historical records reference 245 distinct material codes; there are no orphan codes or duplicate history IDs. All have 120-day validity, evidence metadata, and no recorded registrar or validator.

## Unit normalization and source collisions
- 17 raw unit labels observed; 772 rows resolve using the R2-E1.2 mapping; seven remain unresolved (GL: five, ZZ: two).
- The resolver performs label normalization only. It never converts quantities, package contents, or prices. ML maps to M, GALÓN to GAL, and RLL to ROLLO. GL and ZZ remain pending.
- 24 repeated normalized-name groups were detected: five groups (10 rows) have the same normalized unit and are held for duplicate review; 19 groups (40 rows) use different units and are retained as distinct source identities pending review.

## Existing resource reconciliation
Current ROMAX catalog snapshot: 36 resources (34 ROMAX material resources, one equipment resource and one synthetic test resource). Two existing rates belong to the synthetic test resource and are excluded from the material matching process.
- Eight exact normalized name + normalized unit candidates.
- Three exact-name candidates with unit conflicts.
- Sixteen fuzzy candidates (advisory only; no automatic link).
- All candidates remain unlinked pending human confirmation. Similarity is not proof of material identity.

## Dry-run partition
| Outcome | Rows | Behavior in R2-E1.4 |
|---|---:|---|
| New preliminary resource candidates | 736 | Candidate for new resource, with no price and technical status preliminary |
| Existing-resource mapping review | 26 | Do not merge until a reviewer confirms identity, specification and unit |
| Duplicate source identity review | 10 | Preserve every source code; do not collapse groups automatically |
| Unit review staging | 7 | Preserve source row with no canonical unit; do not create a cost item yet |
| **Total** | **779** | Exact reconciliation; no row discarded |

One of the 27 total matching suggestions overlaps the seven unresolved-unit rows, so the mutually exclusive partition above remains 779.

## Commercial safeguards
- 245 rows have a market-cost value and 534 do not. No numeric cost, suggested sale price, FII, supplier name or evidence URL is included in the simulation report.
- Among the 245 rows with market cost, validity labels are 162 Actualizar, 58 Vigente, and 25 Próximo a vencer.
- No material has Aprobado por; all 779 leader-commercial decisions remain Pendiente. Logistics has validated one row and 778 remain pending.
- Market costs and historical prices are not ROMAX-approved sale prices. R2-E1.4 imports materials as preliminary only. R2-E2 must implement role separation, historical rate versioning, FII, tax, validity and commercial approval before prices can be used for quotations.

## Reproducible utility and QA
Run locally with a private workbook and private JSON catalog snapshot:

    python scripts/romax_r2e1_3_simulation.py --input /secure/path/romax-materials.xlsx --catalog /secure/path/romax-catalog-snapshot.json --output /secure/path/romax-reconciliation.json

The script is read-only and deliberately excludes price values and source evidence details from its output. Synthetic tests validate source-code integrity, unit ambiguity, duplicate handling, historical references and taxonomy conflicts. CI does not contain or access ROMAX source data.

## Release gates
1. Keep PRs #122 and #123 unmerged until their independent review is complete; their GitHub Actions were verified PASS on 2026-11-27.
2. Apply the approved additive foundation and unit migrations in Cloud only after the separate Cloud preflight and backup/restore readiness checks.
3. Reconcile the 26 existing-resource candidates and ten duplicate rows with ROMAX; confirm the seven unresolved unit labels.
4. R2-E1.4 may stage all 779 source identities, but only create canonical preliminary items for rows with resolved units and no unresolved duplicate/mapping conflict. Do not import any prices or history in R2-E1.4.
5. Run the same file twice in dry-run/import rehearsal and prove idempotency; preserve all 36 existing resources and both existing rates.
6. No merge or Vercel production deployment is included in this increment.
