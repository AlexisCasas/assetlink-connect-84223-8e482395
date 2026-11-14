# ROMAX R1-D2E2 — Subtotales por sección y aclaración de partida

**Fecha:** 14 de noviembre de 2026  
**Alcance:** ajuste de la visualización del lote clásico RMX-2026-2215, 2217 y 2218; preservar RMX-2026-2219 y sus datos.  
**Naturaleza:** mejora de frontend, una corrección puntual de la partida de servicio en Supabase Cloud, sin DDL ni cambios de RLS.

## Decisión funcional

1. Cada **Listado de servicios** debe mostrar en su fila gris el **subtotal de mano de obra/servicios declarado en el PDF**, aunque sus subactividades carezcan de precios individuales.
2. La **Descripción de materiales y consumibles** también debe mostrar el subtotal de materiales declarado en el PDF, sin exigir que todas sus partidas tengan tarifa.
3. El encabezado gris de los formatos clásicos debe decir **Listado de servicios** y no reutilizar la primera descripción como título de grupo. Las descripciones completas se conservan en filas subordinadas.
4. Si el importe de una sección difiere de la suma de partidas con parciales disponibles, mostrar ambos importes y **la diferencia pendiente**, sin crear una línea artificial ni reemplazar la tarifa fuente.
5. Las cotizaciones con formato de grupo real, como el piloto detallado RMX-2026-4087, mantienen su **título de grupo original** y subtotal. El documento 2219 no recibe cambios de datos.
6. Todos los precios siguen siendo históricos y con revisión comercial pendiente; un importe matemáticamente conciliado no es automáticamente un precio vigente o aprobado.

## Excepciones y control del caso 2217

- La única descripción de servicio del PDF corresponde a un **subtotal de servicios**, respaldado por el PDF y confirmado por el usuario. Se registró como **parcial de la línea**, pero no se inventaron cantidad, unidad ni precio unitario.
- El detalle del suministro de agua contiene una cantidad y un precio unitario explícitos en el PDF. Su parcial **no coincide** con el subtotal documental de materiales.
- La vista indica la diferencia pendiente de explicación. También calcula el **equivalente por unidad de dividir el subtotal total de materiales entre la cantidad**, dejando explícito que es un valor calculado y **NO** el precio unitario del PDF.
- No se calcula IGV ni se incorporan impuestos a ese diferencial: los cuatro documentos del lote declaran que sus precios no incluyen IGV.

## Matriz QA

| Control | Esperado |
| --- | --- |
| 2215 listado de servicios | Fila gris genérica de sección con subtotal de servicios; seis actividades debajo con precios individuales ausentes preservados |
| 2215 materiales | Fila gris con subtotal documental y su partida de consumibles |
| 2217 asistencia de llenado | Subtotal de servicio y parcial de única partida coinciden, sin cantidad ni unitario inventados |
| 2217 cisterna | Cantidad, unidad, precio unitario y parcial originales conservados; subtotal de sección, diferencia y equivalente calculado visibles por separado |
| 2218 listado de servicios | Fila gris genérica y tres trabajos debajo, sin asignarles precios individuales |
| 2218 materiales | Subtotal de sección y cuatro materiales sin tarifas individuales asignadas automáticamente |
| 2219 | Sin cambio de datos y sin regresiones del histórico |
| 4087 / 6200 | Compatibilidad con los casos estructurados anteriores |
| Autorización | Las consultas permanecen bajo RLS del proveedor |
| Operaciones | No crear ni alterar solicitudes o cotizaciones operativas; no cambia esquema ni inventarios |
| Continuidad | PR, QA, despliegue y decisiones registrados en el plan maestro |

**Observación:** el encabezado de sección no constituye una segunda partida económica ni debe contarse dos veces en una suma. Las diferencias entre subtotales y partidas siguen pendientes de homologación documental para la futura IA.
