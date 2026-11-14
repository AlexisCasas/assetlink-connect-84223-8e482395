# ROMAX R1-B — Auditoría de origen y reglas de depuración

**Fecha de inspección:** 14-nov-2026 · **Fuente:** Base_Consolidada_Contactos_Clientes.xlsx (Drive ROMAX, solo lectura; modificado 09-nov-2026).
**Privacidad:** informe agregado; no copiar correos, nombres, teléfonos, direcciones ni URL/ID del documento al repositorio público.

## Reconstrucción del total de filas

| Categoría | Filas |
| --- | ---: |
| Filas devueltas como datos en la extracción (sin encabezado CSV inicial) | 592 |
| Encabezados intercalados y filas de resumen general | 8 |
| Subtotales por cada uno de los seis clientes | 6 |
| Filas comerciales restantes | 578 |
| Repetición legítima entre BASE GENERAL y hoja individual (cada ficha aparece en ambas) | 289 pares |
| **Registros comerciales únicos para evaluar** | **289** |

El total de 289 coincide con el pie del documento original; no corresponde cargar 592, 584 ni 578 como registros finales. **Interpretación precisa:** cada ficha aparece en BASE GENERAL y una hoja específica del cliente. Esta duplicación entre pestañas es intencional y sirve para conciliar; no debe considerarse un error de contenido.

## Distribución de registros comerciales únicos

| Etiqueta del cliente en origen | Registros únicos | Etiquetas de sede en bruto |
| --- | ---: | ---: |
| Sodimac / Maestro | 108 | 54 |
| Makro | 59 | 54 |
| Tgestiona | 48 | 12 |
| Oechsle | 33 | 31 |
| National | 31 | 9 |
| Cassinelli | 10 | 0 |
| **Total** | **289** | **160** |

**Advertencia:** 160 significa etiquetas distintas de sede en la fuente, NO 160 locales físicos confirmados. Makro tiene alias entre registros MK / MKR; Tgestiona agrupa varias tiendas en una celda; Sodimac / Maestro mezcla marcas y tipos de instalaciones. La tabla comercial debe diferenciar etiquetas originales de sedes homologadas.

## Riesgos de calidad

1. Muchos contactos aparecen en varias sedes; repetir persona/correo no implica duplicado incorrecto.
2. Algunas filas carecen de nombre de persona, pero contienen otros atributos operativos. Se revisarán antes de descartarlas.
3. No hay RUC o razón social jurídica confiable en este archivo: no inventarlos.
4. Regiones numéricas de algunos directorios no son geografía confirmada: evitar convertirlas automáticamente a ciudad/región.
5. El origen está compartido fuera del repositorio; validar los permisos antes de automatizar importaciones recurrentes.
6. No convertir el resumen de seis clientes en seis organizaciones One Facility; todos permanecen bajo proveedor ROMAX.

## Estrategia

- Primera carga: seis etiquetas cliente, con source_key/registro idempotente, sin forzar sedes, facturación ni invitaciones externas.
- Segunda carga: homologación de sedes, con tabla de equivalencias aprobadas y sedes dudosas sin asociar.
- Tercera carga: 289 registros únicos de contactos, preservando procedencia e identidad de fila; contacto con sede provisional NULL cuando no hay asociación inequívoca.
- QA: comparación de COUNT, claves únicas, reejecución sin registros adicionales y SELECT simulado por otro tenant.
- Mantener el original de Drive intacto y cambios de producción trazados en Supabase.

## Evidencia técnica relacionada

- Migración productiva R1-A: supabase/migrations/20261114161357_provider_commercial_directory.sql
- Pruebas SQL de aislamiento: supabase/tests/romax_r1a_commercial_directory.test.sql
- Plan maestro: docs/ROMAX_PILOT_MASTER_PLAN.md

## Estado

**Carga L1 verificada (14-nov-2026):** 6 de 6 clientes comerciales insertados en Supabase OneFacility, organización ROMAX, con source_system = romax_contactos_consolidados_20261109 y 6 source_key distintas. Registros destino: Cassinelli, Makro, National, Oechsle, Sodimac / Maestro (agrupación provisional) y Tgestiona. Conteo post-write: clientes=6, sedes=0, contactos=0. No se crearon organizaciones cliente, vínculos externos, razones sociales/RUC inventados ni cambios en requests/quotes (33/22); total de organizaciones=10. Las 289 fichas únicas de contacto y 160 etiquetas brutas de sede siguen PENDIENTES de normalización y carga.

## Revisión de homologación (14-nov-2026)

Se reabrió el XLSX binario y se verificaron las 8 hojas originales. Conciliación exacta: 289 filas de hojas individuales y 289 coincidencias en BASE GENERAL. De 160 etiquetas no vacías de sedes, se propusieron 27 agrupaciones Makro a partir de 54 etiquetas, respaldadas parcialmente por un libro histórico 2025. Los identificadores H01–H17 de validación están descritos en docs/ROMAX_R1B_HOMOLOGATION_GATE.md. Las etiquetas multi-sede o genéricas permanecen en cuarentena; sin altas de sedes/contactos en Supabase durante este gate.

La matriz detallada entregada al responsable incluye nombre original y archivo/hoja/celda para cada caso, **no se versiona en GitHub público**.
