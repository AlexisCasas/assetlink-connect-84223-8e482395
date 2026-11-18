# ROMAX R4-A — Análisis técnico de oportunidad · QA

**Fecha:** 18-nov-2026  
**Estado:** backend y editor manual implementados en rama; sin despliegue Vercel.

## Contrato

R4-A transforma una oportunidad en una descripción técnica estructurada:

1. Servicio solicitado.
2. Alcance / trabajos incluidos.
3. Partidas identificadas:
   - servicio;
   - material;
   - equipo;
   - mano de obra;
   - movilización;
   - otro.
4. Cantidades y unidades cuando estén disponibles.
5. Especificaciones técnicas.
6. Información faltante.
7. Consideraciones técnicas.
8. Riesgos.

### Regla económica

R4-A **no guarda precios, costos ni márgenes**.

La IA podrá proponer recursos/cantidades posteriormente, pero los importes seguirán en R2/R4-C y los cálculos serán determinísticos.

## Implementación

### Supabase

- `romax_opportunity_analyses`: versiones del análisis.
- `romax_opportunity_analysis_items`: partidas estructuradas.
- RLS por organización.
- escritura limitada a owner/admin/manager/quote_manager.
- vínculo obligatorio entre oportunidad y análisis dentro del mismo tenant.
- vínculo opcional a `provider_cost_items`, también aislado por organización.
- versionado `opportunity_id + version_number`.

### Frontend

- `#opportunity-analysis?opportunity=<uuid>`.
- botón **Analizar** desde la bandeja de oportunidades.
- editor manual de R4-A.
- selección opcional de recursos del catálogo.
- guardado como nueva versión.
- versión anterior pasa a `superseded`.

## QA Cloud

- RLS de ambas tablas: PASS.
- 8 políticas esperadas: PASS.
- índices de oportunidad/versionado: PASS.
- oportunidades persistentes: 0.
- análisis persistentes: 0.
- partidas de análisis persistentes: 0.
- no se crearon registros temporales.

## QA navegador pendiente

Con una oportunidad manual real:

- [ ] abrir Analizar;
- [ ] completar servicio y alcance;
- [ ] agregar material/equipo/mano de obra;
- [ ] asociar opcionalmente recursos R2;
- [ ] guardar versión 1;
- [ ] editar y guardar versión 2;
- [ ] confirmar que versión 1 queda `superseded`;
- [ ] comprobar que no aparecen precios en R4-A;
- [ ] comprobar acceso directo sin autorización.

## Siguiente

Después del QA manual, R4-B puede usar el histórico de 25 cotizaciones para recuperar antecedentes comparables y R4-C conectar las partidas aprobadas con el catálogo de costos.
