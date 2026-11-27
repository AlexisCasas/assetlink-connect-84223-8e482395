# ROMAX R2-E2 — Gestión comercial de precios

**Estado:** D01-D12 aprobadas; R2-E2.1 implementado en PR #128, pendiente de CI y revisión.  
**Fecha:** 27-nov-2026.  
**Privacidad:** no se publican importes, proveedores, RUC, referencias documentales ni filas privadas del Excel.

## Objetivo y límites
Separar costos de adquisición de precios de venta ROMAX, preservar historial y procedencia, calcular FII/IGV determinísticamente y exigir validación humana. La IA propone; no calcula ni aprueba. R2-E2 no modifica inventario, órdenes de trabajo, clientes ni cotizaciones operativas.

## Fuente ROMAX
- 779 materiales; 245 con costo de mercado y 534 sin costo.
- 273 antecedentes históricos sobre 245 códigos.
- Tres excepciones FII sin aprobador/motivo documentado.
- Los 779 campos de decisión comercial permanecen pendientes; un estado “Activo” no equivale a aprobación.
- Los históricos conservan 120 días de vigencia; 180 días es el valor predeterminado para nuevas entradas.
- El Excel no contiene columna explícita de moneda en la matriz. El margen se expresa en S/; confirmar PEN antes de importar importes.
- Los 273 históricos tienen evidencia y proveedor/tienda, pero no disponibilidad, registrador ni validador. No inventar esos campos.

## Fórmula aprobada
FII estándar: [0,100) 30%; [100,500) 30%; [500,1000) 20%; [1000,+∞) 15%. Se interpreta con búsqueda aproximada por límite inferior. Un FII excepcional aprobado sustituye al estándar; no se suma.
- Precio ROMAX con IGV = ROUND(costo mercado con IGV × (1 + FII), 2).
- Precio ROMAX sin IGV = ROUND(precio con IGV / 1.18, 2).
- Margen = precio con IGV - costo mercado con IGV.
- Margen sobre venta = margen / precio con IGV.
FII no es margen porcentual. IGV inicial 18%; vigencia predeterminada 180 días; alerta previa 30 días; variación 10% pendiente de definir base comparativa.

## Modelo propuesto
- \`provider_cost_rates\`: costos de adquisición actuales versionados.
- \`provider_cost_market_history\`: histórico append-only.
- \`provider_commercial_pricing_settings\` y \`provider_fii_bands\`: reglas versionadas.
- \`provider_item_fii_overrides\`: excepciones justificadas y aprobadas.
- \`provider_commercial_price_versions\`: precio ROMAX separado, versionado e inmutable.
- \`provider_pricing_access_grants\`: permisos por usuario y organización.

## R2-E2.1 — Seguridad y permisos (PR #128)
- Capacidades: \`market_cost.read\`, \`market_cost.manage\`, \`market_cost.validate\`, \`pricing_rules.manage\`; las capacidades \`commercial_price.read/propose/approve\` están reservadas hasta R2-E2.5.
- Owner/admin conceden/revocan a miembros activos. Concesiones históricas no se eliminan; la revocación es irreversible.
- Lectura de \`provider_cost_rates\` y \`provider_cost_suppliers\` requiere \`market_cost.read\`, \`market_cost.manage\` o \`market_cost.validate\`.
- Registrar costos requiere \`market_cost.manage\`; validar requiere \`market_cost.validate\`; el creador no puede aprobar/rechazar su propio costo.
- FX settings requiere \`pricing_rules.manage\`.
- La interfaz del catálogo y el panel de permisos respetan las mismas capacidades; RLS es el control efectivo.
- pgTAP multiempresa, regresión R2A adaptada y workflow CI completo. Estado CI pendiente de evidencia.
- No se aplicó migración Cloud ni se modificaron los dos rates existentes.

## Próximos incrementos
1. R2-E2.1: permisos y RLS (PR #128).
2. R2-E2.2: parámetros versionados IGV/FII, excepciones y fórmula determinista.
3. R2-E2.3: conciliar proveedores e importar 273 históricos append-only.
4. R2-E2.4: registrar 245 costos de mercado como pendientes de validación; 534 sin costo quedan sin tarifa.
5. R2-E2.5: propuestas de precio ROMAX y aprobación comercial por persona distinta del proponente.
6. R2-E2.6: UI comercial, alertas y trazabilidad.
7. R2-E2.7: elegibilidad para cotizar.

## Gates
- Moneda de la matriz confirmada como PEN antes de importar.
- Base de comparación del 10% definida antes de activar alertas.
- Usuarios reales de logística y líder comercial incorporados antes de conceder capacidades.
- CI/pgTAP, advisors, RLS cross-tenant y QA Cloud controlado antes de aplicar.
- Sin carga de precios/históricos, merge o despliegue productivo sin autorizaciones separadas.
