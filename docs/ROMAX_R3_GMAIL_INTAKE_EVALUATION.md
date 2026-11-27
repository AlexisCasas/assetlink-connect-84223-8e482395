# R3-GMAIL — Evaluación de entrada de solicitudes y plan de integración

Fecha: 27-nov-2026. Estado: evaluación inicial read-only completada; integración de aplicación pendiente.

## Evidencia y alcance
- Acceso al buzón comercial confirmado por conector Gmail de ChatGPT. No equivale a OAuth propio de One Facility ni transfiere credenciales a la aplicación.
- Muestra de 60 mensajes recientes (consulta de 14 días, paginada; no censo completo). Se revisaron conversaciones seleccionadas y búsqueda de respuestas enviadas. Seis candidatos iniciales, no certificados como pendientes por otros canales.
- Se observaron solicitudes nuevas, recordatorios, prórrogas, solicitudes reenviadas, propuestas ya enviadas, reajustes, pedidos de compra, coordinación de visitas/ejecución y correos no comerciales.
- Un hilo contiene dos mensajes de la misma solicitud con diferente plazo: se debe actualizar el plazo con procedencia, no duplicar. También hay referencias comerciales repetidas y múltiples propuestas en un hilo: el índice único por hilo existente no cubre todos los casos; en el MVP separar casos ambiguos para revisión, evaluar relación mensaje-solicitud antes de automatizar.
- Adjuntos PDF, XLSX, DOCX, imágenes y video; planos y enlaces externos requieren tratamiento específico. No se descargaron adjuntos ni se siguieron enlaces externos.
- Supabase Cloud: una oportunidad manual en análisis, cero oportunidades Gmail y cero adjuntos. Tablas romax_opportunities y romax_opportunity_attachments existentes, índices únicos parciales por organización/message ID y thread ID, y por organización/message/attachment ID. No se identificaron tablas Gmail/mailbox/OAuth/sync en public/private por nombre; no se confirma que no existan credenciales por otras vías.
- Maestros de clientes existentes cubren parte de los candidatos; clientes/sedes no homologados deben quedar pendientes, nunca crear una organización cliente o inferir enlaces.
- No se escribieron datos Cloud, no se enviaron correos, no se modificaron etiquetas, no se publicaron asuntos, cuerpos, remitentes, IDs, adjuntos o enlaces privados.

## Incrementos propuestos
1. R3-GMAIL.1: diseño y autorización OAuth de aplicación, alcance Gmail de solo lectura, callback seguro, token refresh solo servidor, identidad del buzón y vínculo tenant ROMAX verificados, revocación, estado de conexión, sin tokens en frontend/repositorio/logs. Definir configuración Google Cloud y secretos por interfaz autorizada.
2. R3-GMAIL.2: sincronización manual de ventana acotada, previsualización de candidatos, paginación, límites, errores/reintentos y cursor. No marcar leído ni enviar. Clasificar mensaje y contexto del hilo, separar nueva solicitud, actualización, ya cotizada, operativa, ruido y caso ambiguo. Detectar código de solicitud, último plazo explícito con zona operativa y procedencia; no inventar fechas.
3. R3-GMAIL.3: confirmar candidatos desde UI, vínculo con maestros existentes o pendiente de homologación; persistir idempotentemente en tablas existentes. Conservar mensajes relacionados y fechas de cambios de forma trazable mediante diseño aditivo si procede. Probar concurrencia, reenvíos entre hilos y solicitudes distintas dentro de un hilo.
4. R3-GMAIL.4: guardar adjuntos admitidos en almacenamiento privado con ACL tenant, checksum, validación tamaño/tipo y estados; no ejecutar contenido ni abrir enlaces externos automáticamente; adjuntos no soportados conservan referencia y estado.
5. R3-GMAIL.5: automatizar lectura incremental solamente tras QA manual y autorización; reintentos, auditoría y desconexión. No automatizar envío ni aprobación.
6. R4-A/E: enlazar oportunidad y adjuntos con análisis técnico existente; extracción asistida de alcance y faltantes, sin calcular ni aprobar precios por IA. R2-E2 sigue en paralelo.

## Gates
- Caso solicitud nueva con TDR, recordatorio que cambia fecha, reenvío, respuesta ya cotizada, orden de compra y ruido; repetir sync sin duplicados.
- Confirmación manual antes de crear oportunidades reales durante piloto. No incorporar todos los correos históricos.
- RLS y autorización por tenant, pruebas aisladas, CI, aprobación de migración/despliegue separada. No transferir tokens del conector de ChatGPT; es una conexión independiente.
- Primera ventana propuesta: 7 días, sincronización manual y revisión antes de guardar. Estado actual: ninguna oportunidad creada en esta evaluación.
