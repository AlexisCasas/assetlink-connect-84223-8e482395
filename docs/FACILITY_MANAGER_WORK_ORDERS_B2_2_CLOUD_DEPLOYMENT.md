# One Facility | B2.2-D — informe de despliegue Cloud (2026-11-10)

## Resultado
Migración **PASS**; dos RPC de creación delegada instaladas pero **inactivas por ACL**. No hay merge, UI C2.2 ni permisos de creación activados.

| Campo | Valor |
|---|---|
| Supabase project | `hplchnsseylngjopgbtl` |
| Migration version | `20261110142255` |
| Migration name | `fm_delegated_work_order_creation_staged` |
| Repo PR | #84 — Draft |
| SQL source | `supabase/migrations/20261110142255_fm_delegated_work_order_creation_staged.sql` |
| CI verificado | [GitHub Actions #42832815476](https://github.com/AlexisCasas/assetlink-connect-84223-8e482395/actions/runs/42832815476) |
| QA SQL | 22 suites / 2,361 aserciones PASS |
| QA concurrencia | Dos sesiones por solicitud interna y cotización externa: PASS; una sola OT y auditoría |
| Reversión | `docs/rollbacks/9c6-b2-2-remove-inert-rpcs.sql` |

## Preflight / postcheck (solo conteos y huellas, sin PII)

| Recurso | Antes | Después |
|---|---|---|
| `work_orders` | 29 | 29 |
| OT MD5 fingerprint | `64a83b25e58142ca0ba9979ebbb8d8c7` | Igual |
| `audit_logs` | 13 | 13 |
| Audit MD5 fingerprint | `f237594c934b60cb7ea2bc45bcecd0c7` | Igual |
| Permisos FM totales | 13 | 13 |
| Grants MD5 fingerprint | `b07f18b4bd9af55f6ec01511f7849e98` | Igual |
| `work_orders.manage` | 0 | 0 |
| RLS `work_orders`/`audit_logs` | Activa/activa | Activa/activa |
| Políticas RLS | 1 / 1 | 1 / 1 |
| Migraciones | 86 | 87 |

Las RPC `create_facility_management_internal_work_order(uuid,uuid)` y `create_facility_management_work_order_from_quote(uuid,uuid)` tienen `RETURNS jsonb`, `SECURITY DEFINER`, `search_path=''`, `lock_timeout=3s`. `has_function_privilege(...,'EXECUTE') = false` para `anon`, `authenticated`, `service_role` en ambas.

## Limitaciones y seguridad

El proyecto Supabase está en el plan **Free**. No cuenta con backup diario automático confirmado. No se creó un `pg_dump` ni se verificó backup físico. Las huellas se usan solo como detector de cambios, **no como mecanismo de recuperación**. Dado que la migración es exclusivamente aditiva (dos funciones) y sin modificaciones de datos, el rollback focalizado elimina ambas RPC únicamente tras revisar que no existan OT creadas por ellas. El historial de migraciones deberá conciliarse en caso de rollback.

**Gate siguiente:** mantener PR Draft y no habilitar `EXECUTE` ni `work_orders.manage` hasta que C2.2 esté diseñada, validada y autorizada.