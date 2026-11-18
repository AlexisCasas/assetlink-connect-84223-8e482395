# ROMAX R3 — Oportunidades y adjuntos · QA controlado

**Fecha:** 18-nov-2026  
**Estado:** backend migrado y UI implementada en rama; sin despliegue Vercel.

## Alcance ejecutado

### Supabase Cloud — OneFacility

- Proyecto: `hplchnsseylngjopgbtl`.
- Organización ROMAX: `a76fb740-78cf-4ed5-97dd-1e1e24fcab68`.
- Migración: `romax_r3_opportunities`.
- Hardening: `romax_r3_function_search_path`.

### Modelo

- `romax_opportunities`
- `romax_opportunity_attachments`

### Controles verificados

- RLS habilitado en ambas tablas.
- Políticas SELECT para miembros activos del tenant.
- INSERT/UPDATE/DELETE limitados a owner/admin/manager/quote_manager.
- Deduplicación futura de Gmail por `organization_id + source_message_id`.
- Deduplicación futura de threads por `organization_id + source_thread_id`.
- Deduplicación futura de adjuntos por `organization_id + source_attachment_id`.
- Trigger de integridad impide vincular cliente/sede/contacto de otra organización.
- Trigger de integridad impide adjuntar un archivo a una oportunidad de otro tenant.
- Funciones R3 tienen `search_path=public`.
- Conteo actual de oportunidades: **0**.
- Conteo actual de adjuntos: **0**.

No se crearon registros temporales en Cloud para QA. Se verificó estructura, RLS, índices y funciones sin alterar datos.

## Frontend

Implementado en GitHub:

- `src/components/provider/OpportunitiesView.tsx`
- ruta `#opportunities`
- acceso desde Sidebar para usuarios autorizados.
- bandeja con búsqueda y filtro de estado.
- alta manual temporal para probar R3 mientras no exista el buzón Gmail.
- selección de cliente, sede y contacto existentes.
- clasificación inicial.
- estado y origen visibles.
- indicador de adjuntos preparado para la futura sincronización.

## QA pendiente con navegador

1. Abrir `#opportunities` como usuario ROMAX autorizado.
2. Registrar una oportunidad manual real de prueba.
3. Confirmar que cliente → sede → contacto solo muestran datos de ROMAX.
4. Confirmar lectura de la oportunidad después de recargar.
5. Confirmar que un usuario sin rol permitido no puede crear/editar.
6. Confirmar que la ruta directa `#opportunities` no bypassa el gate.
7. Conectar Gmail cuando el cliente entregue el buzón y ejecutar:
   - message ID único;
   - thread ID único;
   - adjunto único;
   - segunda lectura del mismo thread sin duplicar oportunidad.

## No ejecutado

- No se conectó Gmail.
- No se solicitaron credenciales del cliente.
- No se desplegó Vercel.
- No se modificó Drive.
