# ROMAX R2-E1.2 — Unit normalization

## Scope and status
R2-E1.1 PR #122 commit cd1087b: four GitHub checks confirmed successful on 2026-11-27. The Cloud preflight still showed no foundation tables, 36 existing resources, 2 rates and 13 original units. This PR is independent of #122, based on productization/mvp; no merge or Cloud change performed here. The structural migration must still pass its authorized Cloud preflight (including backup/restore readiness) before application. Import remains gated by R2-E1.3 reconciliation/dry run.

## Contract (agreed R2-E0 mapping)
| Raw label | Unit code | Action |
|---|---|---|
| UND | UND | Existing |
| M | M | Existing |
| ML | M | Explicit alias |
| GALÓN | GAL | Explicit alias |
| KG | KG | Existing |
| ROLLO | ROLLO | Existing |
| RLL | ROLLO | Explicit alias |
| M2 | M2 | Existing |
| M3 | M3 | Existing |
| CAJA | CAJA | New presentation |
| BOLSA | BOLSA | New presentation |
| BALDE | BALDE | New presentation |
| MILLAR | MILLAR | New presentation |
| PAR | PAR | New presentation |
| PQT | PQT | New presentation |
| GL | NULL | Manual review |
| ZZ | NULL | Manual review |
15 resolved label classes; two unresolved. Case and outer spaces normalized; accentless GALON additionally allowed. Unknown, empty, inactive, GL and ZZ return NULL; never infer GLB, GAL or UND. Retain original label in source staging. A missing unit blocks canonical item creation until resolved or mapped to an existing item with verified unit. Do not drop source identities.
Six globally available codes (existing system convention); dimension count is metadata only, not conversion permission. No new aliases in existing units. No factors, no automatic package-to-unit or gallon-to-liter conversion. MILLAR and PAR retained as distinct commercial units, not translated into prices per item. A collision aborts without overwriting metadata. Existing resource IDs, rates and operational inventory untouched.
Resolver public.resolve_romax_material_import_unit(text) is read-only, security invoker, empty search_path; explicit execute ACL to authenticated/service_role only; existing unit RLS retained. Scope is ROMAX matrix import profile, not a universal alias resolver.

## QA and release
44 isolated assertions: all 17 raw labels, normalization, unknowns, inactive unit, six new presentation codes, legacy codes and alias preservation, ACL and no client write. Full existing pgTAP and regression workflows via pull_request to productization/mvp. No live price/material fixtures. No CI result claimed before completion.
Cloud release requires PASS and migration alignment, backup/restore readiness, counts and hashes of existing units/items/rates, then 19 codes total if preflight is still 13, original 13 unchanged, resolver checks, no item/rate changes; no import yet. No merge or production deployment authorized. R2-E1.3 will verify every row and retain unresolved units. R2-E2 handles commercial security and prices.
