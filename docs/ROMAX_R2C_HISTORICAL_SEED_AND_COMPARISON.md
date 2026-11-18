# ROMAX R2C — Reutilización controlada del piloto de 25 cotizaciones

**Fecha:** 18-nov-2026  
**Estado:** análisis completado; sin escrituras de datos históricos en el catálogo.

## 1. Base disponible

En Supabase Cloud existen **25** registros en `commercial_quote_history`, todos del lote `romax_r1d_2026_pdf_pilot_20261114`.

La estructura contiene:
- 186 partidas históricas.
- 93 secciones.
- componentes económicos históricos separados.
- documentos y trazabilidad de origen.

La distribución actual de partidas es:
- 67 materiales.
- 115 servicios.
- 4 otros.

Hay 179 descripciones distintas.

## 2. Qué sí reutilizamos para R2

El histórico puede alimentar el catálogo como **referencia para normalización**, no como tarifario vigente.

### Candidatos de recursos
Podemos reutilizar, previa normalización:
- descripciones de materiales y consumibles;
- descripciones de servicios recurrentes;
- unidades documentadas;
- especificaciones técnicas que estén expresamente en el PDF;
- relación con cliente/sede cuando sirva como contexto comercial.

### Unidades
El piloto presenta varias formas equivalentes (por ejemplo UND/Und/und./UND. y GLB/GBL/Glb/glb). R2 ya tiene unidades canónicas. La normalización debe mapear alias sin alterar el documento histórico.

### Proveedores
Los clientes históricos **no se convierten en proveedores**. El piloto no constituye por sí solo evidencia suficiente para crear proveedores de costos.

### Tarifas
Los precios unitarios de las cotizaciones históricas **no se copian automáticamente a `provider_cost_rates`**. Son precios de propuestas comerciales y pueden incluir mano de obra, materiales, gastos, utilidad u otros componentes. Una tarifa R2 requiere una fuente de costo identificable (cotización de proveedor, compra, planilla, hoja interna, etc.), vigencia y revisión.

## 3. Regla para la carga inicial

La carga se hará en dos niveles:

1. **Catálogo base:** crear solo recursos que puedan normalizarse con suficiente claridad a una categoría y unidad canónica.
2. **Tarifa:** crearla únicamente cuando exista evidencia de costo independiente y verificable.

No se importarán masivamente las 186 partidas como tarifas.

## 4. Comparación de alternativas

R2C incorpora comparación de hasta 4 tarifas del **mismo recurso**.

La comparación muestra:
- proveedor o costo interno;
- versión;
- costo original;
- equivalente PEN;
- unidad;
- vigencia;
- fuente;
- estado de revisión;
- tipo de cambio cuando aplica.

El menor equivalente PEN se marca solo como referencia. No se genera una recomendación automática porque precio, proveedor, vigencia, impuestos y calidad de la fuente pueden cambiar la decisión.

## 5. Siguiente carga controlada

Antes de escribir registros derivados del histórico:
- generar una propuesta de candidatos normalizados;
- revisar duplicados y alias de unidades;
- separar materiales de servicios compuestos;
- confirmar qué candidatos realmente deben existir como recursos del catálogo;
- después insertar los recursos aprobados;
- las tarifas se cargarán aparte con fuentes de costo reales.

Esto mantiene separado el **histórico comercial** del **costo vigente**, que es la condición fundamental de R2.
