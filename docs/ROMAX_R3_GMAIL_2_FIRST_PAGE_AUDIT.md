# R3-GMAIL.2 — auditoría de primera página (27-nov-2026)

## Alcance
Revisión de solo lectura de las 12 conversaciones de la primera página del preview (ventana 20-nov 16:49 a 27-nov 16:49, America/Lima) y contraste de los hilos completos disponibles en Gmail. El UI indicó 7 conversaciones con mensajes recibidos. No se descargaron adjuntos, no se siguieron enlaces, no se modificó Gmail y no se crearon oportunidades. Hay páginas posteriores pendientes de revisión.

## Resultado agregado
- 6 hilos comerciales para revisión: 5 solicitudes y 1 actualización de plazo.
- 4 hilos ya cotizados o de coordinación de ejecución; no deben entrar como nuevas oportunidades pendientes.
- 2 falsos positivos no comerciales (invitación/evento y soporte de plataforma).
- Supabase continúa con 0 oportunidades Gmail; existe una oportunidad manual de QA.
Los conteos se refieren exclusivamente a esta primera página y no al total de los siete días.

## Casos comerciales que deben conservarse
1. Nueva solicitud Cassinelli Piura: deadline 30/11; el correo original y su reenvío interno pertenecen al mismo hilo, crear como máximo una oportunidad; tres adjuntos únicos.
2. UTP Lima Sur: actualización de SC-0000153027-2026. Deadline original 10/11 12:00, ampliado a 28/11 12:00. Debe conservar ambos hitos y actualizar una sola oportunidad; el mensaje dentro de ventana incluye el contexto de la solicitud original.
3. UTP Chiclayo: SC-0000154401-2026. Deadline inicial 27/11, actualizado a 30/11. Una oportunidad y un historial de plazo, no dos.
4. Cassinelli Trujillo Larco: nueva solicitud; visita 27/11 10:00–16:00; entrega de propuesta 01/12.
5. UTP Piura: nueva solicitud, pero el mensaje indica literalmente “viernes 26/11”. El 26-nov-2026 fue jueves; no inferir si la fecha correcta es 26 o viernes 27. Requiere confirmación y queda en revisión.
6. Licitación nacional UTP/FEN de técnicos 24/7: nueva oportunidad compleja, con alcance en ocho ciudades y tres documentos (XLSX y DOCX). Deadline indicado: 27/11 a las 12:00; ya había vencido al momento del preview de las 16:49. Confirmar si aceptan propuesta tardía o hubo prórroga antes de marcarla activa.

## Cotizadas / operativas — no crear nuevas oportunidades pendientes
- Makro motobombas: mensaje contiene propuesta ROMAX RMX-2026-7269 y PDF, enviado por el alias ventas3@romaxfm.com. No aparece con etiqueta SENT en el buzón ventas@; el clasificador lo mostró como “Requiere revisión”. Debe reconocerse como cotización saliente por alias, no como nueva solicitud.
- HMC SJL Jardines: cotización RMX-2026-4091 enviada y actualizada; mensaje reciente solicita documentación SST para ingreso e inicio de trabajo 30/11. Es coordinación de ejecución.
- Real Plaza PV Chiclayo SIP: cotización RMX-2026-4102 enviada y actualizada; no es nueva solicitud.
- Real Plaza PV Callao/Claro: cotizaciones RMX-2026-4100 y RMX-2026-4101 enviadas; mensajes recientes de acceso/visita son operativos.

## Falsos positivos
- Invitación a cóctel/evento empresarial: no es solicitud de cotización.
- Hilo de soporte de notificaciones de Suplayer: incidencia de correo/plataforma, no oportunidad comercial.

## Fallos confirmados del clasificador
1. Cassinelli Piura se clasifica como “Otros” porque se toma el último mensaje reenviado por personal interno; el asunto/snippet de ese reenvío no contiene el texto comercial completo. El mensaje externo original del mismo hilo sí pide cotizar y tiene deadline 30/11.
2. UTP Lima Sur no se reconoce como actualización porque el patrón no contempla “se extiende plazo para entrega de propuesta”; se puede perder el deadline 28/11 12:00.
3. UTP Chiclayo requiere comparar mensajes de la misma conversación y conservar la transición 27/11 → 30/11.
4. Cotizaciones enviadas por alias internos (ventas3@romaxfm.com y otros remitentes @romaxfm.com) pueden no llevar la etiqueta Gmail SENT del buzón conectado; se clasifican erróneamente como candidatas.
5. El extracto/snippet no basta para distinguir todos los mensajes reenviados, respuestas y correos operativos. La clasificación debe considerar todos los mensajes de la conversación dentro de ventana, remitentes externos/internos y referencias RMX/SC.
6. Extraer plazo como texto libre no basta: guardar fecha/hora normalizada con zona America/Lima, plazo anterior, plazo actualizado, mensaje fuente y ambigüedad. Nunca inferir una fecha cuando el día de semana y la fecha numérica discrepan.

## Decisión de importación
NO AUTORIZAR IMPORTACIÓN todavía. Corregir primero el clasificador y las reglas de fecha en un PR independiente (R3-GMAIL.2.1), repetir CI y QA con estos casos. Después revisar las páginas siguientes con “Cargar más conversaciones”. Solo entonces el propietario confirma las oportunidades y se ejecuta R3-GMAIL.3 idempotente. Mantener cero escrituras en oportunidades hasta autorización expresa.
