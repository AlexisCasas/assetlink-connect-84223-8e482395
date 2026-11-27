# R2-E0 / R2-E1.1 progress and QA gates

- D01–D10 approved; Cloud structural migration and preliminary real-material import authorized, gated on regression and dry run.
- R2-E0 audit: 779 source codes in master and intake; 273 history references, 245 distinct materials; no orphan history. 36 legacy resources inventoried. 11 families / 149 subfamilies, 17 units. Exact material matching, semantic classifications and two ambiguous unit labels remain pending. No approved new commercial prices identified.
- Historical and current cost records must remain private; FII is markup, not sale margin; preserve source validity, tax treatment and commercial approval. No real prices in R2-E1.
- Foundation test file: supabase/tests/romax_r2e1_material_catalog.test.sql. Run via existing isolated database QA on PR; do not execute fixtures on Cloud.
- CI status: pending actual result. Cloud application: pending CI, preflight and post-check. Import: pending R2-E1.2/3. No merge or production deployment.
- Canonical updated route for this increment: ROMAX_R2E1_MATERIAL_CATALOG_DESIGN.md. Earlier planning docs may be historical.

## PR #122 CI correction
Initial commit 6a9b179: both isolated SQL workflows ran 35 test files, 2,791 assertions, with 4 failures (R2-E1.1 tests 1, 5, 9, 13); 35 of 39 foundation assertions passed. The two-argument has_table calls resolved to table-name/description rather than schema/table; all four corrected to explicit three-argument schema/name/description and a fixed plan(39). No assertions removed; no migration, RLS, application code or workflow changes. The new commit must pass both SQL workflows and remaining regressions before Cloud migration. No Cloud changes, import, merge or production deployment.
