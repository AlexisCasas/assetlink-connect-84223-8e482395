# ROMAX R2C — Seed controlado de recursos desde piloto R1D

**Fecha:** 18-nov-2026  
**Fuente:** lote histórico `romax_r1d_2026_pdf_pilot_20261114`.

## Resultado

Se cargaron **35 recursos normalizados** en `provider_cost_items` para ROMAX.

- 34 materiales.
- 1 equipo.
- 0 tarifas nuevas.
- 0 proveedores nuevos.
- 0 modificaciones al histórico comercial.

El catálogo pasó de 1 registro previo de prueba a **36 registros totales** en la organización. en la organización.

## Criterio de selección

Se incluyeron únicamente recursos del piloto que:
- tenían una descripción suficientemente identificable;
- podían mapearse a una unidad canónica ya existente;
- podían clasificarse sin inventar un proveedor o un costo;
- no dependían de una cantidad específica de una cotización.

Se excluyeron:
- encabezados de sección;
- “consumibles” genéricos;
- partidas compuestas o alcances completos;
- descripciones sin unidad normalizable;
- presentaciones cuya unidad aún no existe en R2;
- precios unitarios históricos.

## Normalizaciones aplicadas

- Variantes de escritura de **Thinner/Thiner acrílico** se consolidaron en un recurso.
- **Fragua** y **Fragua para Porcelanato** se consolidaron en un recurso.
- Las dos variantes históricas de **Porcelanato 0.38 x 0.38 m cortado** se consolidaron en un recurso.
- Las unidades históricas compatibles se mapearon a las unidades canónicas R2 (por ejemplo UNIDAD → UND, ML → M, KILO → KG, GALON → GAL).
- No se creó ninguna nueva unidad para resolver una ambigüedad.

## Importante: tarifas

Los precios de las 25 cotizaciones **no se copiaron** a `provider_cost_rates`.

QA posterior:
- cotizaciones históricas: **25**;
- partidas históricas: **186**;
- recursos ROMAX: **36**;
- recursos seed ROMAX con tarifas: **0**.

El histórico comercial permanece separado del catálogo de costos.

## Próximo paso

1. Revisar visualmente los 35 recursos cargados.
2. Completar una segunda tanda con servicios claramente normalizables.
3. Resolver las unidades históricas que todavía no tienen equivalente canónico, solo si existe una decisión funcional.
4. Crear tarifas únicamente desde fuentes de costo reales.
5. Continuar con R2D para revisión/aprobación.
