# ROMAX — Replanning funcional 28/11/2026

Estado: REPLANNING APROBADO (P01–P12, 28/11/2026). Documento de arquitectura funcional sin implementación. Fuentes: reunión del 27/11 y matriz de 27 requisitos del 19/11, conservadas fuera de este repositorio público. El estado del prototipo del cliente no certifica el estado de One Facility. La maqueta no fue inspeccionada directamente; no se adjuntan correos, archivos, precios o datos comerciales privados.

## Línea base
PR #132 QA Q01–Q08 PASS. PR #133 CI final 40c8d08 PASS (36 Deno; 2919 pgTAP; concurrencia); QA visual 8/8. Migración Cloud canónica 20261128145232 homologada, primera oportunidad Gmail y auditoría confirmadas por propietario. Resincronización real como existente pendiente. Ambos PR sin merge; producción sin nuevo despliegue. Mantener confirmación individual, deduplicación, RLS y auditoría. R1 directorio/histórico y R2 catálogo reutilizables; R4-A análisis versionado sin precios ya disponible. R2-E2 elegibilidad comercial pendiente.

## Contrato propuesto de solicitud
No duplicar la entidad oportunidad ni crear una solicitud operativa de Facility. Bandeja persistente separada de preview Gmail, tabla con ingreso, referencia de solicitud (no correlativo de cotización), cliente, sede/ciudad, servicio resumido, especialidad, plazo, adjuntos, responsable, estado y alerta. Detalle con resumen/alcance, datos comerciales revisables, referencias y plazos con evidencia, documentos, asignación e historial, acceso al análisis técnico. Datos faltantes explícitos, sin inferir fechas ni cliente/sede; origen inmutable. Mantener estados existentes; asignación y alertas como dimensiones distintas. Filtros estado, especialidad, responsable, cliente, fecha; detalle responsive. Sin campos redundantes.

## Matriz trazable (IDs de requisitos; estado fuente no es estado del producto)
| ID | Área | Incremento |
|---|---|---|
| 01–03 | Hospedaje, viáticos, pasajes por grupo y tramo | R4-C2 |
| 04–06 | Unidad/material, fuentes mercado, costo y venta separados | R2-E2 / R4-C1 |
| 07–09 | Cabecera, contactos múltiples, avisos sin montos | R4-D / R6 |
| 10–15 | Partidas/subpartidas, nivel valorizado, unidad/metrado, tarifa/jornadas, servicios | R4-C1/C2 |
| 16–17 | PDR/supervisión general y movilización local | R4-C2 |
| 18–20 | Cláusulas versionadas, PDF/Excel, anexos y documento final | R4-D / R6.2 |
| 21–22 | Correlativo atómico y aprobación por versión | R6.1 |
| 23–24 | Dashboard comercial, metas, KPI | R7 propuesto |
| 25–26 | Toma exclusiva, permisos y acceso directo privado | R3-SOL.3 |
| 27 | Subcontratos, fuente original, margen sobre venta | R4-C3 / R4-E |

## Ruta crítica propuesta
0. Cerrar R3-GMAIL.3 con resincronización real; integrar PRs solo cuando autorizado.
1. R3-SOL.1: contrato UI tabla/ficha de solo lectura, casos Gmail/manual, filtros, estados, responsive; no inventar campos persistidos.
2. R3-SOL.2: persistir datos estructurados revisables y su procedencia (referencia, plazo, ampliaciones, cliente/sede, especialidad, contactos), RLS y auditoría.
3. R3-GMAIL.4 / R3-SOL.4: adjuntos bajo demanda; metadatos, límites, allowlist, storage privado, idempotencia y revisión; no ejecutar contenido activo.
4. R3-SOL.3: toma exclusiva y reasignación atómica, servidor y audit trail; pruebas de concurrencia con usuarios sintéticos, no crear cuentas reales.
5. R4-A/R4-B: integrar análisis existente y antecedentes de histórico, sin convertirlos en tarifas vigentes.
En paralelo R2-E2.1B–7: resolver owner único, costo validado vigente, precio/reglas aprobados y subconjunto elegible; costo faltante no es cero.
6. R4-C1: cálculo determinista partida/subpartida, unidad, metrado, tarifa y snapshot; no sumar ambos niveles.
7. R4-C2: recursos/jornadas/rendimiento y logística por grupo, generales una sola vez.
8. R4-C3/R4-D: rentabilidad por origen de trabajo, subcontrato, borrador editable y cláusulas.
9. R4-E: IA asistida, evidencias y revisión humana; números por motor.
10. R6.1–2: correlativo único, aprobación por versión, exportación reproducible PDF/Excel y anexos.
11. R6.3: emisión y avisos manuales primero, seguimiento por destinatario/hilo/estado. Gmail readonly no permite envío; nueva autorización OAuth separada.
12. R7: indicadores, metas y tablero por emisión/cotizador, sin duplicar códigos.
R5 visitas queda como complemento cuando el alcance lo exija.

## Decisiones de aprobación
P01 reutilizar oportunidad; P02 tabla/ficha inicialmente read-only; P03 procedencia y estados separados de asignación; P04 adjuntos privados bajo demanda; P05 confirmar especialidades y responsables; P06 asignación atómica y reasignación por permiso; P07 margen sobre venta vs incremento sobre costo, política mixtos y excepciones; P08 PDR/supervisor general por defecto, resolver discrepancia fuente sobre mano de obra y evitar doble cómputo; P09 owner único y aprobación explícita sin crear usuarios reales; P10 avisos sin montos y envío manual inicial; P11 plantilla y alcance de documentos cliente/interno; P12 IA propone, revisión humana y confirmación Gmail conservadas.

## Gates
No implementar código, migraciones, usuarios, costos, imports, merges o despliegues en este replanning. Cada incremento requiere contrato, PR, CI/regresión, QA y autorización Cloud/producción cuando corresponda. Próximo entregable: aprobar diseño funcional R3-SOL.1, y comprobar resincronización real de la primera oportunidad. La matriz privada completa incluye referencias a filas y minutos, criterios y fórmulas del cliente; no publicarla en GitHub.

## Aprobación y siguiente diseño

P01–P12 aprobadas sin pendientes de revisión de la decisión marco. El contrato detallado SOL1-D01–D12 se propone en [R3-SOL.1](ROMAX_R3_SOL_1_FUNCTIONAL_DESIGN.md), pendiente autorización de implementación. Los parámetros específicos de fases posteriores aún deberán definirse en sus contratos. No código.
