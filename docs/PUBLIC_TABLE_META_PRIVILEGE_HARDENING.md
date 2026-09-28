# Public table meta-privilege hardening (Fase 1 · Punto 9C.1H)

Migración: `supabase/migrations/20260928062721_public_table_meta_privilege_hardening.sql`
Pruebas: `supabase/tests/public_table_meta_privilege_hardening.test.sql` (33 aserciones)

## Problema detectado

La auditoría de producción encontró 55 de las 72 tablas de `public` que
conceden a `anon` y a `authenticated` cuatro privilegios de objeto que
ninguna superficie de la aplicación usa. Esto se suma a `SELECT`/`INSERT`/
`UPDATE`/`DELETE`, que sí forman parte del modelo PostgREST + RLS:

- **`TRUNCATE`**: vacía la tabla completa.
- **`REFERENCES`**: permite crear una `FOREIGN KEY` que apunte a la tabla.
- **`TRIGGER`**: permite crear triggers sobre la tabla.
- **`MAINTAIN`** (PostgreSQL 17+): permite `VACUUM`, `ANALYZE`, `CLUSTER`,
  `REINDEX` y `REFRESH MATERIALIZED VIEW`.

Las otras 17 tablas ya se habían endurecido en migraciones anteriores:
`organizations`, `organization_members`, `organization_invitations`,
`activity_logs`, `audit_logs`, `organization_relationships`,
`facility_management_*`, `preventive_maintenance_*`, `maintenance_card*`,
`criticality_thresholds`, `asset_meter*` y `automatic_alert_runs`.

Los default privileges de tablas en `public` también conceden esos cuatro
privilegios. Una tabla nueva nacía igual de expuesta.

## Privilegios SQL y RLS

RLS decide **qué filas** ve o escribe un rol en `SELECT`/`INSERT`/
`UPDATE`/`DELETE`. `TRUNCATE`, `REFERENCES`, `TRIGGER` y `MAINTAIN` se
autorizan solo por `GRANT` (`pg_class.relacl`), y ninguna policy interviene:

- `TRUNCATE` vacía la tabla sin evaluar policies de fila. Con ese privilegio,
  `anon` o `authenticated` la vacían como si no existiera RLS.
- `TRIGGER` permite instalar lógica que corre en cada operación sobre la
  tabla.
- `REFERENCES` permite anclar una FK propia a la tabla.
- `MAINTAIN` abre una superficie de mantenimiento (`REINDEX`, `CLUSTER`,
  etc.) ajena al modelo de autorización.

Por eso la corrección es revocarlos con `REVOKE`; RLS no puede sustituirlo.

## Qué hace la migración

Solo retira `TRUNCATE`, `REFERENCES`, `TRIGGER` y `MAINTAIN` de `PUBLIC`,
`anon` y `authenticated`. No usa `REVOKE ALL` y nunca revoca `SELECT`,
`INSERT`, `UPDATE` ni `DELETE`.

1. **Tablas existentes**: `REVOKE ... ON ALL TABLES IN SCHEMA public`. Cubre
   las 72 tablas actuales. En `public` no hay vistas, vistas materializadas
   ni foreign tables. En las tablas donde el privilegio no existía, no hace
   nada.
2. **Default privileges de `postgres`**: `ALTER DEFAULT PRIVILEGES FOR ROLE
   postgres IN SCHEMA public REVOKE ... ON TABLES`. Todas las migraciones del
   repo corren como `postgres`. El CRUD que el default ACL ya concedía se
   conserva:
   - en producción, `anon` y `authenticated` siguen con CRUD;
   - en local, donde no había CRUD, no se inventa ni se concede.
3. **Default privileges de `supabase_admin`**: antes de actuar, la
   migración comprueba `pg_has_role(current_user, 'supabase_admin', 'SET')`.
   No provoca ni captura una excepción esperada.
   - Si el rol actual puede asumir `supabase_admin`, ejecuta el mismo
     `REVOKE` acotado.
   - Si no puede, emite un `NOTICE` explícito, continúa y **no** da el
     default ACL por corregido.

## Baseline de default ACL (tablas de `public`)

### Local observado (Supabase CLI, PostgreSQL 17.6)

| Owner | Grantee | Antes | Después |
|---|---|---|---|
| `postgres` | `anon`, `authenticated` | `TRUNCATE`, `REFERENCES`, `TRIGGER`, `MAINTAIN` (sin CRUD) | sin entradas |
| `postgres` | `service_role` | `TRUNCATE`, `REFERENCES`, `TRIGGER`, `MAINTAIN` | sin cambio |
| `postgres` | `postgres` | los 8 | sin cambio |
| `supabase_admin` | `anon`, `authenticated` | CRUD + los 4 | sin cambio (no modificable) |
| cualquiera | `PUBLIC` | sin entrada | sin entrada |

### Producción auditada

| Owner | Grantee | Antes | Después esperado |
|---|---|---|---|
| `postgres` | `anon`, `authenticated` | CRUD + los 4 | **CRUD se conserva**; `TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN` retirados |
| `supabase_admin` | `anon`, `authenticated` | CRUD + los 4 | sin cambio: las migraciones actuales del repo no pueden modificarlo; queda **pendiente de plataforma/operación** |
| cualquiera | `PUBLIC` | sin entrada | sin entrada |

Además, las 72 tablas de `public` pertenecen a `postgres` y ninguna a
`supabase_admin`.

El default ACL de `postgres` es distinto en local y en producción; el resto
coincide. Por eso las pruebas exigen la **ausencia** de los cuatro
privilegios, sin fijar el CRUD que tenga cada entorno.

La forma productiva se simuló en local: se concedió CRUD + los 4 al default
ACL de `postgres` y se reaplicó la migración. Resultado: `anon` y
`authenticated` quedaron con `DELETE`, `INSERT`, `SELECT`, `UPDATE`, y la
suite pasó 33/33.

## Pendiente: default ACL de `supabase_admin` en hosted Supabase

`ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin` exige poder asumir ese
rol. En Supabase, `postgres` aplica las migraciones y no puede:

- no es superusuario;
- no es miembro de `supabase_admin`, así que
  `pg_has_role('postgres', 'supabase_admin', 'SET')` es `false`;
- Supabase no expone credenciales de `supabase_admin`.

Consecuencias:

- **Las 72 tablas actuales sí quedan endurecidas**, porque el paso 1 actúa
  sobre las tablas existentes con independencia de sus default privileges, y
  ninguna pertenece a `supabase_admin`.
- **Riesgo remanente**: si una tabla futura se crea realmente como
  `supabase_admin` en `public` (por ejemplo, desde la infraestructura de
  Supabase y no desde una migración de este repo), volvería a heredar
  `TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN` para `anon`/`authenticated`.
  Mitigarlo requiere control de plataforma/operación: pedirlo a Supabase o
  auditar periódicamente los owners y ACL de `public`.
- Si algún día la migración corre con un rol que puede asumir
  `supabase_admin`, el paso 3 lo corrige solo.

Esa ruta se verificó en local, aplicando la migración y la suite como
`supabase_admin`: quedaron solo los 4 retirados y el CRUD conservado.

## Fuera de alcance

- Default privileges de **sequences** y **functions**: no se tocan.
- **`service_role`**: no se modifica en ninguna dirección, ni por tabla ni
  en default ACL.
- Owners, RLS, policies, Edge Functions, RPCs y frontend: sin cambios.

## Verificación

pgTAP dedicado: 33/33. En el entorno normal, 32 pasan y 1 es `skip`: la
tabla futura de `supabase_admin`, que `postgres` no puede crear. Esa prueba
sí se ejecuta cuando la suite corre como `supabase_admin`.

Qué cubre:

- ninguna tabla de `public` concede los 4 a `PUBLIC`, `anon` o
  `authenticated`;
- CRUD mínimo conservado en `assets`, `quotes`, `requests` y `work_orders`;
- contrato exacto de las tablas endurecidas antes;
- las sentencias registradas de la migración solo revocan los 4 (ni
  `REVOKE ALL` ni CRUD);
- default ACL de `postgres` sin los 4;
- default ACL de `supabase_admin` según lo que permita el entorno;
- ninguna tabla es de `supabase_admin`;
- `service_role` intacto;
- una tabla futura nace sin los 4 y con exactamente el CRUD del default ACL
  de su entorno;
- `TRUNCATE` y `REINDEX` fallan con `42501` para `anon` y `authenticated`.

Controles negativos (descartables y restaurados):

| Control | Mutación | Fallos |
|---|---|---|
| A | Re-conceder los 4 en tablas existentes | 5 |
| B | Re-conceder los 4 en el default ACL de `postgres` | 6 |
| C | Omitir el paso de `supabase_admin` y correr la suite como `supabase_admin` | 2 |
| D | Re-conceder solo `TRUNCATE` a `authenticated` en `assets` | 2 |
| E | Re-conceder solo `MAINTAIN` a `anon` en `quotes` | 1 |
| F | Reemplazar el paso 1 por `REVOKE ALL` | 8 |

Regresión completa: 1329/1329 (1296 previos + 33).
