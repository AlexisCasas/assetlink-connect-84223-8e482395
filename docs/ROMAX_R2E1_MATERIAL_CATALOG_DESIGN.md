# ROMAX R2-E1 — Material catalog foundation (D01–D10 approved)

## Status
R2-E0 structural audit: 779 source identities, 36 legacy resources, 11 families / 149 subfamilies, 17 raw units, 273 historical records. Aggregate reconciliation only; item-level matches, taxonomy conflicts and ambiguous units still require review. No real workbook, supplier, pricing or contact data in this public repository.
R4-A.1 #121 merged; base e8f8486. R2-E1.1 implementation proposed in this PR; CI and Cloud application not yet verified.

## Approved contract
D01 reuse provider_cost_items; D02 retain economic categories; D03 organization taxonomy; D04 source identity; D05 separate technical from commercial validation; D06 unit extension later; D07 idempotent imports; D08 tenant isolation; D09 preserve existing identifiers/rates; D10 separate acquisition and sale prices.
Four additive tables: provider_material_families, provider_material_subfamilies, provider_cost_item_sources, provider_catalog_import_batches. Composite foreign keys enforce tenant and family relationships. Existing rows remain unassessed (NULL), new resources preliminary. No update of existing records or commercial rates. Authenticated users can read own tenant; existing catalog managers may create taxonomy and edit labels/active state; import identity, classification and validation require controlled server-side writes. No client delete. No new definer function.
A digest uniquely identifies a batch per tenant/source; a case-insensitive source code uniquely identifies a material per tenant/source. Duplicate insert rejects; retry importer must compare existing payload and report conflicts, never overwrite confirmed mappings or approved rates. A pending source may lack an item when unit or identity is ambiguous. Actual importer and immutable revision evidence are later work; this migration is not an importer. No price eligibility endpoint yet. No real prices may be loaded until acquisition-cost access is separated at the database/API layer.

## Increment plan
- R2-E1.1 foundation, pgTAP and isolated CI; then authorized Cloud migration after PASS and preflight fingerprints.
- R2-E1.2 units: aliases and package units; GL/ZZ unresolved; no invented conversion.
- R2-E1.3 row-level reconciliation, taxonomy checks and dry run; preserve all existing 36 and 779 source identities.
- R2-E1.4 authorized preliminary import, repeat exact file to verify no duplicates. Ambiguous unit may remain staged pending confirmation; no commercial activation.
- R2-E1.5 catalog UI and visual QA.
- R2-E2 history (273), FII, tax, validity, commercial approval and permissions; no automatic approval.
- R4-B historical comparison; R4-C deterministic economics; R4-D quotation builder; R4-E AI assistant; R6 approval/PDF. Gmail and visits separately scoped.
No merge or production deployment authorized.

## Gates
Existing isolated Supabase workflow runs full pgTAP and FM regressions on PR. New synthetic tests verify RLS, tenant isolation, valid/invalid classification, source identity uniqueness, legacy compatibility and no auto-rate. No actual test result claimed until check runs complete. Before Cloud apply: verify target, backup/restore readiness, migrations alignment, counts and fingerprints of existing item/rate/operational records; after apply compare, inspect policies/grants and advisors. Stop on any failed or missing check. No destructive rollback; if a defect occurs stop import and use reviewed forward fix. Public repository contains no commercial source data.
