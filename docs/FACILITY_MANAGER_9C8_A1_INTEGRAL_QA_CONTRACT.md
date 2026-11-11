# One Facility — 9C.8-A1 · Auditoría y contrato propuesto de QA integral multi-tenant

**Fecha:** 2026-11-11.  
**Estado:** A1 INVENTARIO + PREFLIGHT CLOUD READ-ONLY COMPLETADOS. **D1–D8 PROPUESTAS, NO APROBADAS AÚN.**  
**Base:** `productization/mvp`, SHA `534ff223b4810c8cc49d8ef435497a856fdd914f`; PR #95 merged y QA visual PASS informado por el responsable.  
**No autorizados por este documento:** escrituras Supabase Cloud, concesiones/revocaciones de permisos, usuarios sintéticos persistidos, nuevas OT, merge o nuevo despliegue Production.

## 1. Secuencia y objetivo

La hoja de ruta 9C comprende: 9C.1 activos/criticidad; 9C.2 inspecciones/preventivo; 9C.3 avisos/backlog; 9C.4 solicitudes; 9C.5 cotizaciones; 9C.6 OT; 9C.7 indicadores actuales e históricos. **9C.8 es regresión integral y aislamiento cross-tenant, no un módulo nuevo**.

Objetivo: confirmar que autorizaciones, datos, navegación, cache, clientes directos/proveedores y delegación FM funcionan juntos, sin fuga entre cliente A/cliente B ni FM A/FM B, ni reaparición de funcionalidades ocultas por cambios de permisos. No declarar PASS integral solo porque cada PR anterior aprobó su propia suite.

## 2. Baseline técnica verificada

- GitHub: `productization/mvp` = `534ff223...`; PR #95 fusionado, responsable confirma QA visual PASS. Vercel Production asociado a ese SHA según despliegue previo.
- Repositorio: **13** suites SQL `facility_manager_*.test.sql` presentes; **5** workflows de CI frontend/backend relevantes; scripts aislados de concurrencia OT, notas y recorrido 9C.6-D.
- Los pipelines frontend 9C.6, 9C.7-C1, 9C.7-C2 y correctivo #95 aprobaron el commit anterior del PR #95 `b2315c...`. **Aún NO consta un run 9C.8 único sobre el merge actual** que ejecute `supabase test db` y los recorridos de concurrencia completos.
- Cloud One Facility (SELECT 2026-11-11): **1** relación FM activa, **2** asignaciones, **14** permisos delegados, **1** `reports.view`, **0** `work_orders.manage`, **0** crons antiguos de QA 9C.7. RPCs de indicadores y tendencias presentes.
- Seguridad selectiva confirmada: RPCs de lectura OT, seguimiento, KPI y tendencias no son ejecutables por `anon`, sí por `authenticated` con controles internos. RPCs de **creación** de OT y de **escritura de notas externas** no son ejecutables por `authenticated` en Cloud. La RPC de planificación OT interna aún admite rol `authenticated`, pero depende de autorización interna; se debe probar su denegación efectiva sin `work_orders.manage`.
- **Límite de Cloud:** hay solamente una relación FM activa. Por tanto **no se puede certificar aislamiento multi-FM / multi-cliente solo con datos reales**; la matriz de identidades cruzadas requiere fixtures sintéticas y PostgreSQL local descartable.
- **Deriva de migraciones pendiente:** SQL de `supabase/migrations/20261110235345_fm_delegated_daily_trends.sql` es idéntico al registrado por Cloud, pero Cloud lo registra como versión `20261111004204`. No ejecutar `supabase db push` hasta reconciliar el historial mediante procedimiento revisado y aprobado; no editar o borrar migraciones históricas a ciegas.

## 3. Matriz de regresión propuesta (códigos 9C8-01–9C8-24)

| ID | Área | Condición exigida | Evidencia requerida |
|---|---|---|---|
| 01 | 9A/9B | Relación activa + FM activo + usuario asignado + grant correcto habilitan acceso | SQL aislado + UI |
| 02 | 9A/9B | Owner/admin no asignado y membresía inactiva no reciben acceso operativo | SQL y gate UI |
| 03 | Cross-tenant | FM A nunca lee cliente B por cambiar UUID, relación o deep link | SQL multi-FM |
| 04 | Cross-tenant | Un cliente con dos FM no transfiere datos/roles de una relación a otra | SQL multi-FM |
| 05 | Caché | Cambio de usuario, organización, cliente o relación no deja datos antiguos visibles | UI + pruebas |
| 06 | Seguridad | SELECT/RPC crudo ajeno y `anon` no filtran datos | ACL/RLS SQL |
| 07 | 9C.1 | Activos: lectura/gestión separadas, vínculo correcto cliente/relación | SQL + UI |
| 08 | 9C.1 | Criticidad: vista, gestión y edición manual sin bypass de `assets.manage` | SQL + UI |
| 09 | Punto 10 R2 | Fotos y documentos de activos solo con permiso y dueño adecuados | SQL + prueba UI |
| 10 | 9C.2 | Inspecciones y preventivo: ver vs planificar/ejecutar, técnico según matriz | SQL + UI |
| 11 | 9C.3 | Avisos/backlog: reportar, clasificar y permisos por rol separados | SQL + UI |
| 12 | 9C.4 | Solicitudes delegadas, borradores, conversión desde aviso/plan | SQL + UI |
| 13 | 9C.5 | Cotizaciones: `quotes.view` vs `quotes.approve` y visibilidad económica condicionada | SQL + UI |
| 14 | 9C.6-B1 | Lista/detalle OT cliente correctas; sin datos crudos del proveedor | SQL + UI |
| 15 | 9C.6-B2 | Planificación OT internas: CAS/idempotencia, escrituras sin `manage` denegadas | SQL/concurrencia descartable |
| 16 | 9C.6-D3 | Creación interna/externa idempotente y sin duplicados; no crear OT real para QA | SQL/concurrencia descartable |
| 17 | 9C.6-D4 | Notas externas por relación, autor, duplicados, revocación inmediata | SQL/concurrencia descartable |
| 18 | 9C.7-V1 | KPI actuales correctos y separados por OT/solicitud/activos; `reports.view` requerido | SQL + UI |
| 19 | 9C.7-B2 | Histórico 30/90/180, personalizado 1–366 días, inclusividad/zona Perú, ceros veraces | SQL + QA visual |
| 20 | 9C.7 ACL | `null/unavailable` sin permiso de dominio vs `0` con acceso y sin eventos | SQL + UI |
| 21 | PR #95 | `Ver indicadores` presente pero bloqueado y explicado sin permiso; abierto con permiso | UI/contrato |
| 22 | Clientes/proveedores | Operación propia del cliente y proveedor permanece intacta (sin secuestro de contexto FM) | QA de regresión UI |
| 23 | Integridad/infra | ACL de RPCs, Cloud sin grants temporales ni job de prueba, sanidad datos | SQL read-only |
| 24 | Historial | Reconciliar discrepancia de versiones GitHub/Cloud antes de cualquier migración posterior | Plan + evidencia, sin `db push` |

**Estado actual:** los casos tienen cobertura **parcial** en suites anteriores; **ninguno se marca QA integral PASS todavía** sin ejecución consolidada de las evidencias exigidas.

## 4. Decisiones D1–D8 propuestas para aprobación

| Código | Decisión | Límite |
|---|---|---|
| **D1** | Iniciar con QA reproducible en Supabase local/Docker descartable y `supabase test db` completo | No ejecutar runners mutadores contra Cloud |
| **D2** | Usar fixtures de **dos clientes y dos FM**, usuarios con doble membresía, no asignados, roles distintos y relaciones activas/inactivas | No insertar identidades de QA en producción |
| **D3** | Exigir matriz de `view/manage/create/approve` por módulo; el permiso de módulo nunca sustituye rol ni asignación | Sin permisos por defecto |
| **D4** | Exigir denegación cross-tenant incluso en deep links y caché de React Query; no conservar datos tras revocación | UX fail-closed y servidor como autoridad |
| **D5** | Ejecutar regresión de módulos 9C.1–9C.7 y punto R2, protegiendo flujos de cliente directo/proveedor | No habilitar escritura OT Cloud para probar |
| **D6** | Crear CI específico 9C.8 que agrupe pgTAP + concurrencia + contrato UI/TypeScript/lint/build; revisar logs y SHA exacto | QA aislado antes de merge |
| **D7** | Cloud solo para preflight/QA read-only y smoke visual con usuario real; formalizar riesgo de deriva de migración antes de futuras DDL | Ningún `db push` ni `migration repair` sin autorización |
| **D8** | Cierre requiere evidencia automática PASS + checklist funcional manual + hallazgos/riesgos clasificados y plan de rollback | Merge y Production se autorizan por separado si hubiera código correctivo |

## 5. Etapas operativas propuestas

1. **9C.8-A1** (este PR): inventario + matriz D1–D8 + identificación de brechas. Sin cambios funcionales.
2. **9C.8-B1**: fixtures cross-tenant, pruebas específicas de revocación/aislamiento y runner CI integral, todas locales y sin credenciales Cloud.
3. **9C.8-B2**: consolidación y evidencia frontend (caché por usuario/relación, botón PR #95, rutas, filtros 30/180).
4. **9C.8-C1**: QA manual en Production **solo lectura**, sesiones reales por rol y checklist firmado; no generar órdenes ni revocar permisos de clientes durante la prueba.
5. **9C.8-D**: informe de hallazgos y cierre integral. Correcciones bajo PRs y autorizaciones separadas; plan específico de reconciliación de migración si se requieren posteriores cambios de BD.

## 6. Criterios de salida de A1

- [x] Confirmación de continuidad 9C.7 → 9C.8.
- [x] Inventario de suites SQL/workflows y preflight Cloud solo lectura.
- [x] Matriz de regresión inicial, riesgos y exclusiones.
- [ ] Aprobación explícita de D1–D8.
- [ ] Ejecución consolidada 9C.8 y QA manual: **aún NO realizados**.
