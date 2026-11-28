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
