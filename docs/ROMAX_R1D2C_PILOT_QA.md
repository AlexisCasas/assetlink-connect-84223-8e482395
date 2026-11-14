# ROMAX R1-D2C - Cierre de primer piloto de homologacion

**Fecha:** 14-nov-2026
**Entorno:** Supabase Cloud / One Facility
**Organizacion:** ROMAX, provider_company
**Resultado:** PASS para estructura flexible y primer piloto documentado; precios unitarios por partida siguen pendientes de vinculacion visual.

## Desarrollo e integridad

- PR #111 integrado, merge SHA b87bc2c934e89de85e40a9bb64a587646fd4eb6c.
- Cinco suites de QA en GitHub Actions: todas PASS, incluyendo migraciones pgTAP y validaciones de aislamiento por organizacion.
- Supabase Cloud: migracion 20261114213637_romax_quote_sections. La version de archivo se alinea en este PR documental sin alterar su SQL.
- Tabla comercial privada commercial_quote_history_sections: FK compuesta con la cotizacion, secciones ordenadas y encabezados originales, pagina opcional, procedencia y review_status, RLS activa con lectura solo del tenant.
- Cost components: source_page acepta NULL para PDF aplanados que no permitan confirmar la pagina sin inventarla.
- Frontend: consulta tabular de secciones tecnicas/contractuales y otros apartados; el texto original sigue disponible bajo demanda.

## Fuente auditada

25 documentos PDF de 2026 y plantilla Excel oficial ROMAX.

| Familia | Documentos |
| --- | ---: |
| Cotizacion clasica | 15 |
| Propuesta economica detallada | 7 |
| Cotizacion por metrajes | 2 |
| Mixta | 1 |
| Total | 25 |

La plantilla Excel incluye datos de propuesta comercial, recursos tecnicos y estructura interna de costo: deben permanecer diferenciados. Se conserva el numero de PDF y archivo, pero el correlativo nunca es clave unica.

## Piloto real

Documento RMX-2026-4087, Cassinelli / HMC Iquitos (formato detallado), comparado con el formato clasico RMX-2026-6200 que ya tenia partidas estructuradas.

Se registraron:
- Seis secciones con titulo original y texto fuente: propuesta/alcance, aclaraciones tecnicas, seguridad, gestion y entrega, resumen economico y condiciones comerciales.
- Tres componentes de resumen economico: subtotal neto, IGV, total; cada uno conservado en Supabase como extracted_unverified y source_page=NULL.
- Cero partidas economicas nuevas con descripcion y precio unitario inventado: el extractor PDF habia separado las tres filas numericas y sus descripciones.
- Se verifico que el subtotal de los tres registros numericos coincide con el subtotal impreso, que el IGV coincide con el 18% y que subtotal mas impuesto equivale al total.
- Se preservaron price_review=pending y commercial_status=unverified en cabecera; la conciliacion aritmetica NO equivale a aprobacion de precios o adjudicacion.

## QA de Supabase Cloud

| Verificacion | Resultado |
| --- | --- |
| Secciones nuevas de 4087 | 6 |
| Componentes financieros nuevos de 4087 | 3 |
| Partidas precio/descripcion nuevas de 4087 | 0 (pendientes de cotejo) |
| Paginas adivinadas | 0 |
| Secciones o importes marcados erroneamente como verificados | 0 |
| Acceso ROMAX owner (secciones / componentes piloto) | 6 / 3 |
| Acceso de otra organizacion | 0 / 0 |
| Prueba de reimportacion idempotente (secciones / resumen) | 0 / 0 |
| Seguridad RLS | PASS |
| Permisos anon | SELECT denegado |
| Escritura desde navegador | Denegada |
| Supabase Advisors, tabla nueva | Sin alertas |
| Historicos originales / documentos / textos | 25 / 25 / 25 |
| Partidas 6200 existentes | 5 |
| Solicitudes / cotizaciones operativas | 33 / 22 |
| Organizaciones | 10 |

## Proximos lotes

1. Validar visualmente con ROMAX el nuevo detalle de 4087 y comparar con 6200.
2. Encontrar el Excel especifico de 4087 o cotejar su PDF visual para unir descripcion de partida, cantidad, unidad, precio y parcial. No forzar las tres asociaciones por orden de texto plano.
3. Estandarizar en lotes de 3 a 5 documentos por familia, dejando registros ambiguos en cuarentena de homologacion.
4. Para IA, consultar secciones historicas y partidas con citas al documento, pero para recomendar precios nuevos exigir review_status=verified, comparacion con catalogos y control de antiguedad.

**Alcance:** R1-D2C valida la estructura y un nuevo piloto de secciones/economia; NO completa homologacion de las 24 cotizaciones restantes. Los precios comerciales quedan exclusivamente en Supabase, nunca en el repositorio publico.

Referencia: docs/ROMAX_R1D2C_HOMOLOGATION_AUDIT_PILOT.md.
