# R3-GMAIL.2.1 — Correctivos de clasificación
27-nov-2026. PR correctivo sobre R3-GMAIL.2. No desplegar ni importar oportunidades.
## Cambios
- Identidad interna ROMAX se determina por dominio @romaxfm.com, no solo por Gmail SENT; cubre ventas, ventas2, ventas3, operaciones y alias futuros del mismo dominio.
- Reenvíos: si el hilo contiene el mensaje externo original, se usa ese mensaje como fuente y se agrega una sola conversación. Si solo llega el reenvío interno, se extrae el remitente externo de la cabecera forwarded del snippet.
- Cotizaciones de alias internos con evidencia de envío y PDF se reconocen como quoted, no como solicitudes nuevas.
- Ampliaciones de plazo: patrones “se extiende plazo”, “se amplía”, “prórroga” y equivalentes.
- Historial de plazos conserva fecha original y extensión; parser explícito dd/mm, dd.mm, dd/mm/yyyy, weekday y hora AM/PM; salida en America/Lima (-05:00). Día de semana contradictorio → ambiguous, sin fecha normalizada.
- UI muestra el historial de fechas y señala los casos ambiguos.
## Casos de regresión
Cassinelli Piura (original + forward), Makro (ventas3 alias), UTP Lima Sur (28/11 12:00 extension from 10/11 12:00), UTP Chiclayo (27/11 -> 30/11), UTP Piura (viernes 26/11 conflict), quoted/internal mail.
## Límites
No leer body.data ni descargar adjuntos. No escribir Gmail, oportunidades, labels ni tablas. Sin migración ni secretos. No merge ni deploy hasta CI y QA.


Ajustes QA adicionales: excluir el hilo de soporte/notificaciones Suplayer como no comercial; reconocer solicitudes que dicen propuesta sin exigir “propuesta económica”; tratar solicitudes de documentos SST/ingreso como coordinación operativa cuando no contienen una petición de cotización. El parser reconoce días con acento (sábado/miércoles) y horas precedidas por guion.


Fechas soportadas: dd/mm, dd.mm, dd/mm/yyyy y yyyy-mm-dd. La fecha se normaliza solo si es válida y el día de semana coincide cuando el correo lo indica. Las horas AM/PM se normalizan a America/Lima (UTC-05:00). Los mensajes de soporte Suplayer se excluyen y las solicitudes con “propuesta” se reconocen aunque no repitan la palabra “cotización”.

El plazo indicado en una solicitud inicial no se clasifica como seguimiento: solo se marca seguimiento cuando hay lenguaje de ampliación, prórroga, recordatorio, nueva fecha o reprogramación.
