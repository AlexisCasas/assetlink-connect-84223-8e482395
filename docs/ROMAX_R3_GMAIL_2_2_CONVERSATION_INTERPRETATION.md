# R3-GMAIL.2.2 — Interpretación de conversaciones

Fecha: 27/11/2026. Incremento dentro del PR #132, sin merge.

## Alcance
- Listado y metadata de hilos; GET de texto MIME únicamente para mensajes dentro de los últimos siete días. Preferencia text/plain, alternativa HTML convertido a texto; no se renderiza HTML, no se ejecutan enlaces ni se consulta el endpoint de adjuntos. Se omiten partes con nombre de archivo, disposición attachment o MIME no textual. Gmail puede incluir datos inline en la respuesta FULL: se descartan sin decodificar las partes de adjuntos. Sin persistir ni registrar cuerpos; respuesta limitada a extracto y evidencia breve de plazo.
- Límites: 12 mensajes por hilo, 48.000 caracteres por cuerpo, JSON máximo 2 MiB, tres hilos concurrentes, presupuesto 25 segundos por página. Lectura limitada se señala y requiere revisión; fallos de API no devuelven una página silenciosamente incompleta.
- Compara plazos confirmados de mensajes sucesivos; conserva original y fecha actualizada incluso sin frase de ampliación. Las fechas citadas se usan como evidencia histórica, no como nuevo mensaje. No convierte fechas contradictorias en confirmadas; no convierte visitas en plazos de oferta.
- Reconoce invitación a participar y solicitudes de propuestas; excluye CATEGORY_PROMOTIONS. Mantiene controles de remitentes ROMAX, soporte y coordinación operativa.
- Política de previsualización: new_candidate, link_existing, review_required, not_importable. Seguimiento sin oportunidad vinculada queda review_required. No existe endpoint de importación; R3-GMAIL.3 deberá revalidar esta política en servidor antes de cualquier escritura, con confirmación del propietario.

## Regresiones basadas en auditoría (fixtures sintéticos, sin cuerpos reales ni IDs de Gmail)
Cassinelli Piura original/reenvío, Makro alias, UTP Lima Sur (10/11 y 28/11 a 12:00), UTP Chiclayo (27/11 y 30/11 sin frase de ampliación), Trujillo (01/12), UTP Piura fecha contradictoria, FEN (27/11 a 12:00), promociones y recordatorio huérfano. Cobertura adicional: MIME, datos adjuntos ignorados, lectura temporal, no consultar cuerpos antiguos, no devolver cuerpo completo, política de vinculación.

## Gates
CI en GitHub Actions, revisión de resultados y QA real posterior en la función QA. Sin migraciones, secretos nuevos, modificación de Gmail, importación, merge ni actualización de Supabase Cloud (incluida QA) o Vercel producción en este incremento. Preview automático de la rama puede actualizarse por GitHub; la función QA sigue en v1 hasta autorización y despliegue posterior.


## R3-GMAIL.2.2.1 — correcciones derivadas del QA real
- Makro: conservar en memoria el payload MIME completo devuelto por `messages.get` para reconocer adjuntos anidados de cotizaciones enviadas por alias ROMAX aunque Gmail no marque SENT; usar cuerpo + referencia RMX + adjunto para la categoría `quoted`.
- Cassinelli Outlook: convertir cierres de celdas/filas/tablas HTML en separadores de texto para no perder plazos ISO ubicados en tablas; mantener adjuntos XLSX/PDF como metadatos, sin descargarlos.
- Samsung/marketing: excluir `CATEGORY_PROMOTIONS` y reforzar con `List-Unsubscribe`/`List-Id`/`Precedence` combinado con señales promocionales. La consulta Gmail también excluye `-category:promotions`; no se ocultan mensajes solo por tener List-Unsubscribe.
- Añadidas pruebas de integración con respuestas Gmail API sintéticas que reproducen las estructuras MIME auditadas. Sin cuerpos reales, IDs reales, persistencia, importación ni modificaciones de Gmail.

## R3-GMAIL.2.2.1 — aceptación manual real y cierre (28/11/2026)

**QA manual confirmado por el propietario: PASS en Vercel Preview v3.** Se repitió la sincronización real y quedaron aprobados los ocho casos Q01–Q08:

| Caso | Resultado final | Observación |
| --- | --- | --- |
| Q01 Cassinelli Piura | PASS | Clasificación validada |
| Q02 Makro Motobombas | PASS | Reconocimiento de alias ROMAX y adjunto MIME; referencia RMX-2026-7269 |
| Q03 UTP Lima Sur | PASS | Clasificación y seguimiento validados |
| Q04 UTP Chiclayo | PASS | Clasificación y actualización de plazo validadas |
| Q05 Cassinelli Trujillo | PASS | HTML multipart de Outlook y plazo 01/12 reconocidos |
| Q06 FEN | PASS | Clasificación validada |
| Q07 HMC Chiclayo | PASS | Clasificación validada |
| Q08 Samsung Black Friday | PASS | Excluido como promoción |

Preview utilizado: https://one-facility-git-feature-romax-r3-29c35c-alexiscasasrs-projects.vercel.app

**Corroboración técnica:** los registros de Supabase muestran invocaciones de la función QA v3 con respuestas HTTP 200 y preflight CORS 204 durante la sesión. No se registran cuerpos de correo ni datos de los casos en logs; por ello, el detalle Q01–Q08 se conserva como aceptación manual expresa del propietario, no como inferencia desde logs.

**Línea base al cierre:** Edge QA v3 ACTIVE con JWT obligatorio; Edge productiva v2 ACTIVE. La tabla de oportunidades conserva una oportunidad manual preexistente y **0 oportunidades con source_system=gmail**; no se importaron correos ni adjuntos. No se ejecutó migración, merge ni despliegue productivo.

**Estado:** R3-GMAIL.2.2.1 cerrado. PR #132 permanece Draft y abierto, pendiente de su revisión/merge autorizados. Siguiente incremento: R3-GMAIL.3, con importación exclusivamente tras confirmación expresa del propietario.