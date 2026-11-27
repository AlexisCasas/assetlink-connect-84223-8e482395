# R2-E0 / R2-E1.1 progress and QA gates

- D01–D10 approved; Cloud structural migration and preliminary real-material import authorized, gated on regression and dry run.
- R2-E0 audit: 779 source codes in master and intake; 273 history references, 245 distinct materials; no orphan history. 36 legacy resources inventoried. 11 families / 149 subfamilies, 17 units. Exact material matching, semantic classifications and two ambiguous unit labels remain pending. No approved new commercial prices identified.
- Historical and current cost records must remain private; FII is markup, not sale margin; preserve source validity, tax treatment and commercial approval. No real prices in R2-E1.
- Foundation test file: supabase/tests/romax_r2e1_material_catalog.test.sql. Run via existing isolated database QA on PR; do not execute fixtures on Cloud.
- CI status: pending actual result. Cloud application: pending CI, preflight and post-check. Import: pending R2-E1.2/3. No merge or production deployment.
- Canonical updated route for this increment: ROMAX_R2E1_MATERIAL_CATALOG_DESIGN.md. Earlier planning docs may be historical.
