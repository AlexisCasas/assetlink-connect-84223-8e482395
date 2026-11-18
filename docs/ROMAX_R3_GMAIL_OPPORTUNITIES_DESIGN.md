# ROMAX R3 — Bandeja de oportunidades y entrada Gmail

**Fecha:** 18-nov-2026  
**Estado:** diseño preparado; sin conexión Gmail ni migración Cloud.

## Objetivo

Convertir una solicitud que llega por correo en una **oportunidad ROMAX**, sin crear falsamente una solicitud de cliente ni enviar respuestas automáticas.

## Flujo

Correo → detección → oportunidad → clasificación → vinculación comercial → adjuntos → análisis R4.

## Modelo funcional mínimo

### Oportunidad

- organización ROMAX;
- estado;
- cliente comercial opcional;
- sede opcional;
- contacto opcional;
- asunto;
- remitente;
- fecha de recepción;
- Gmail thread ID;
- Gmail message ID de origen;
- resumen/snippet;
- clasificación;
- confianza de clasificación;
- motivo de clasificación;
- notas internas;
- timestamps.

### Estados

- `new`: detectada.
- `reviewing`: en revisión.
- `ready_for_analysis`: datos mínimos confirmados.
- `in_analysis`: R4 procesándola.
- `quoted`: existe borrador de cotización.
- `discarded`: descartada por no ser una oportunidad válida.

### Clasificación

- `quote_request`
- `follow_up`
- `information_only`
- `other`
- `unknown`

La clasificación automática nunca crea una oportunidad de cliente en One por sí sola.

## Deduplicación

La primera barrera será técnica y determinista:

1. `gmail_message_id` único por organización.
2. `gmail_thread_id` para agrupar mensajes de la misma conversación.
3. Los mensajes posteriores del mismo thread se agregan como actividad/mensaje, no como nuevas oportunidades.
4. No se deduplica únicamente por asunto, remitente o fecha.

Esto aprovecha los identificadores inmutables de mensaje y thread de Gmail.

## Cliente / sede / contacto

Se reutilizan los maestros existentes:

- `commercial_clients`
- `commercial_client_sites`
- `commercial_client_contacts`

La IA puede proponer coincidencias, pero la asociación definitiva queda bajo control de ROMAX cuando exista ambigüedad.

## Adjuntos

Se registra primero metadata:

- message ID;
- attachment ID;
- nombre;
- MIME;
- tamaño;
- estado de procesamiento.

Estados:

- `detected`
- `queued`
- `downloaded`
- `processed`
- `unsupported`
- `failed`

Los PDF/XLSX/DOCX/imágenes serán insumos para R4. No se convierten automáticamente en partidas económicas.

## Gmail

Para el primer alcance se usará **solo lectura**. El alcance funcional requerido es lectura de mensajes, threads y adjuntos; no se necesita enviar, modificar, archivar ni etiquetar correos.

La integración debe pedir el mínimo permiso posible: `gmail.readonly`.

No se almacenarán tokens de Gmail en GitHub ni en tablas públicas.

## Reglas de seguridad

- Solo miembros autorizados de ROMAX pueden consultar oportunidades ROMAX.
- RLS por `organization_id`.
- No se crean organizaciones cliente automáticamente.
- No se escriben solicitudes operativas existentes.
- No se envían correos automáticamente.
- No se modifica el buzón durante la primera versión.
- Los datos recibidos de Gmail permanecen separados del histórico comercial.

## Primer vertical slice

R3 no debe intentar resolver todavía toda la IA.

La primera entrega útil será:

**correo → oportunidad → cliente/sede sugeridos → adjuntos visibles → estado**

Después:

**oportunidad → análisis R4 → histórico → costos → borrador.**

## Gate antes de conexión real

1. Confirmar el buzón ROMAX que será fuente.
2. Configurar OAuth con alcance mínimo.
3. Crear tabla de oportunidades y adjuntos.
4. QA RLS/tenant.
5. Probar deduplicación por message/thread.
6. Probar lectura de PDF/XLSX/DOCX/imágenes.
7. Recién después habilitar sincronización automática.
