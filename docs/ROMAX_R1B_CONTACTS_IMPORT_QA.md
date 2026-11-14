# ROMAX R1-B L3 — Informe de importación y QA de contactos

**Fecha:** 14-nov-2026 · **Entorno:** Supabase Cloud OneFacility (organización ROMAX tipo proveedor) · **Fase:** R1-B contacto multisitio. **Resultado:** CARGA PRINCIPAL PASS, 19 fichas retenidas para calidad.

## Evidencia técnica y versionado

- PR de desarrollo: #103 (fusionado a productization/mvp).
- Migración aplicada en Cloud: supabase/migrations/20261114165704_commercial_client_contact_sites.sql.
- Test: supabase/tests/romax_r1b_contact_multisite.test.sql — 19 aserciones en una base desechable.
- CI: One Facility 9C.6-B1 isolated database QA y 9C.8-B1 integral multi-tenant QA: ambos PASS.
- Tabla nueva: public.commercial_client_contact_sites, con tres políticas RLS, FK compuestas de contacto y sede, y PK que impide repetir un mismo vínculo.
- Procedencia del lote: source_system = romax_contactos_20261114, en 170 contactos y 284 vínculos. Claves deterministas por identidad dentro del cliente; verificada su unicidad.
- Los archivos y la matriz de excepciones que contienen datos personales permanecen privados y fuera de GitHub público.

## Conciliación de fuente

| Etapa | Registros |
| --- | ---: |
| Filas únicas en hojas individuales de clientes | 289 |
| Excepciones retenidas | 19 |
| Filas utilizadas | 270 |
| Identidades provisionales antes del control de variantes | 171 |
| Dos variantes de la misma persona (misma sede, teléfono y correo) unificadas | -1 |
| **Contactos distintos importados** | **170** |
| **Vínculos distintos contacto-sede** | **284** |
| Contactos que cubren varias sedes | 20 |

| Cliente | Contactos insertados | Vínculos |
| --- | ---: | ---: |
| Cassinelli | 10 | 0 |
| Makro | 59 | 59 |
| National | 14 | 26 |
| Oechsle | 21 | 23 |
| Sodimac / Maestro | 57 | 107 |
| Tgestiona | 9 | 69 |
| **Total** | **170** | **284** |

Los contactos sin sede siguen asociados únicamente a su cliente, sin crear local ficticio. Un mismo contacto relacionado con varias sedes se almacena solo una vez. No se crean usuarios ni organizaciones clientes externos. Se mantienen las siglas de Tgestiona sin expandir.

## QA de Cloud posterior a la carga

| Control | Resultado |
| --- | --- |
| Clientes/sedes ROMAX | 6 / 145 |
| Contactos y vínculos ROMAX | 170 / 284 |
| Claves de importación únicas | 170 |
| Vínculos de otro cliente u organización | 0 |
| Asignación arbitraria del campo legado de sede | 0 |
| Lectura del owner ROMAX en rol autenticado | 170 contactos / 284 vínculos |
| Lectura de un miembro de otra organización en rol autenticado | 0 / 0 |
| Reintento de insertar contacto existente sin duplicar | 0 nuevos |
| Reintento de insertar vínculo existente sin duplicar | 0 nuevos |
| Supabase Security Advisors para tabla nueva | Sin hallazgos de seguridad asociados |
| Línea de base One Facility | 10 organizaciones / 33 solicitudes / 22 cotizaciones, sin variación |

## Excepciones para validación humana (sin datos personales)

Archivo: Base_Consolidada_Contactos_Clientes.xlsx, hojas individuales.

- **National (5):** celdas C6:C8 y C22:C23. Rótulos de cargo sin nombre verificado.
- **Oechsle (8):** C24 y C26:C32. Falta nombre de persona; no inventar identidades.
- **Tgestiona (6):** C22, C26, C30, C34, C38 y C42. Dos nombres por celda; confirmar destinatarios de teléfono y correo.
- **Makro (dos coincidencias de teléfono, no bloqueantes):** pares C15/C45 y C16/C46. Mantener personas separadas hasta confirmación, no deduplicar solo por teléfono.
- **H16:** significado de PVS/PVH/PVE/VIV y titular de facturación pendiente; no interpretar las siglas.

La hoja privada de revisión dispone de datos de origen y referencias exactas para resolver estos casos.

## Siguiente paso

1. ROMAX confirma las 19 excepciones y coincidencias de teléfono; los 170 contactos seguros permanecen disponibles.
2. Los casos confirmados se agregan como lote incremental idempotente sin reescribir identidades ya cargadas.
3. Continuar R1-D con un lote piloto de unas 25 cotizaciones 2026, manteniendo fechas, referencias, moneda y condición histórica; sin solicitudes cliente ficticias.
4. Mantener actualizado el plan maestro ROMAX tras cada PR, migración o lote de datos.

**Confidencialidad:** este reporte público contiene solo totales y coordenadas de celdas; no contiene nombres personales, teléfonos, correos, direcciones ni enlaces privados a Drive.
