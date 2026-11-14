# ROMAX R1-B — Control de homologación pendiente

**Estado al 14-nov-2026:** levantamiento de sedes terminado, revisión del responsable ROMAX pendiente. Las sedes y contactos NO se han insertado en Supabase. Se mantiene una hoja de revisión privada fuera de GitHub, con todas las filas de origen exactas, 160 etiquetas y 17 preguntas.

## Contexto de datos y reconciliación

Fuente principal: el Excel consolidado privado de ROMAX, con ocho hojas: BASE GENERAL, seis hojas de clientes y RESUMEN. Existe otro Excel histórico para apoyo de nomenclatura Makro. Se preserva la fuente de 2026 como referencia preferente cuando los documentos difieren.

- 289 fichas únicas = 289 filas en las hojas de cliente y 289 representaciones iguales en BASE GENERAL; no son 289 duplicados accidentales.
- 160 etiquetas de sede diferentes en origen, no 160 sitios físicos certificados.
- Makro: 54 etiquetas agrupables de forma tentativa en 27 sedes; dos casos sensibles por oficina central y REX.
- National: 9 etiquetas, una es la palabra genérica TIENDA y no debe producir un local ficticio.
- Oechsle: 31 etiquetas no vacías y dos contactos sin sede; tiendas especializadas o sub-marcas deben mantenerse diferenciadas.
- Sodimac / Maestro: 54 etiquetas, conservando prefijos de tienda/almacén/oficina, y agrupación comercial provisional.
- Tgestiona: 12 expresiones, algunas con varias ubicaciones físicas y algunas con cobertura transversal; el mismo contacto puede cubrir más de un lugar.
- Cassinelli: 10 fichas sin sede.

## Decisiones requeridas del responsable

| ID | Prioridad | Cuestión | Acción antes de respuesta |
| --- | --- | --- | --- |
| H01 | Alta | Relación entre tienda Surco y oficina central Makro | No fusionar |
| H02 | Alta | Identidad SMP/REX y discrepancia de dirección | No fusionar |
| H03 | Media | Números implícitos de las tiendas 1 de Makro | Propuesta sin ejecutar |
| H04 | Alta | Sede genérica en National | No crear tienda genérica |
| H05 | Alta | Cliente final/facturación National frente a SPSA | Mantener cliente existente |
| H06 | Media | Identidad de los locales especializados SFERA | Mantener separados |
| H07 | Media | Identidad de los locales especializados MAC | Mantener separados |
| H08 | Media | Contactos Oechsle sin sede | No inventar local |
| H09 | Alta | Agrupación comercial Sodimac / Maestro | No dividir cliente |
| H10 | Alta | Grupo Tgestiona de 3 sedes A | Sin asignar contactos a un local único |
| H11 | Alta | Grupo Tgestiona de 3 sedes B | Sin asignar contactos a un local único |
| H12 | Alta | Ubicación Tgestiona con dos nombres separados por barra | Sin desdoblar |
| H13 | Alta | Grupo Tgestiona de 3 sedes C | Sin asignar contactos a un local único |
| H14 | Alta | Grupo Tgestiona de 2 sedes | Sin asignar contactos a un local único |
| H15 | Alta | Cobertura Tgestiona varias tiendas / ITSE | No crear sede virtual |
| H16 | Alta | Significado de abreviaturas y titular de cotización Tgestiona | No deducir |
| H17 | Baja | Diez contactos Cassinelli sin sede | Conservar contacto a nivel cliente |

**Nota:** por privacidad, las etiquetas y ubicaciones específicas, los datos de contacto y la matriz de revisión con referencias de fila están en un archivo Excel privado entregado al responsable de ROMAX y no en este repositorio público.

## Gate siguiente

1. Recibir respuesta de ROMAX por ID H01–H17 (preferible H01/H02/H04/H05/H09/H10–H16 primero).
2. Convertir respuestas en tabla de aliases confirmados; no unificar solo por similitud textual.
3. Preparar un dry-run privado de inserts en commercial_client_sites y commercial_client_contacts con conteos por cliente y source_key estable.
4. Importar solo los registros aprobados por lote transaccional y verificar idempotencia, FKs y RLS tenant.
5. Registrar en GitHub exclusivamente conteos, versión del lote, decisión técnica y QA; no PII ni URLs del Drive.
6. Continuar R1-C con sedes ya homologadas, sin crear organizaciones ficticias de los clientes externos.

## Estado productivo de referencia

- Organización ROMAX: provider_company; tiene 6 clientes comerciales.
- Tablas de ROMAX: 0 sedes, 0 contactos hasta la última verificación anterior a la homologación.
- Solicitudes y cotizaciones previas no se tocan durante R1-B.
- Verificación obligatoria antes de escribir en Supabase: consultar conteos y permisos reales; evitar confiar en este snapshot si cambió desde el 14-nov.

## Documentos de continuidad

- docs/ROMAX_PILOT_MASTER_PLAN.md — plan maestro R0–R6, decisiones, situación, próximo paso.
- docs/ROMAX_R1B_SOURCE_AUDIT.md — recuento de filas y estrategia de carga.
- docs/ROMAX_R1A_COMMERCIAL_DIRECTORY.md — esquema híbrido y seguridad R1-A.
