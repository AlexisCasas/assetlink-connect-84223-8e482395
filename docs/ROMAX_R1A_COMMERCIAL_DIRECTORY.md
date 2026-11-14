# ROMAX R1-A — Directorio comercial híbrido

**Objetivo:** permitir que ROMAX cotice a clientes que no usan One Facility, sin crear organizaciones ficticias ni afectar las solicitudes, cotizaciones y órdenes de trabajo ya existentes.

## Entidades

- \`commercial_clients\`: clientes comerciales privados por organización proveedora; razón social, nombre, RUC, notas, procedencia y código opcional.
- \`commercial_client_sites\`: sedes con dirección, región, distrito, ciudad, código de sede y procedencia, ligadas al mismo proveedor y cliente mediante clave foránea compuesta.
- \`commercial_client_contacts\`: múltiples contactos por cliente y opcionalmente por sede, con la misma validación de integridad.
- \`linked_client_organization_id\`: enlace opcional y administrativo a una organización \`client_company\` real, únicamente cuando el cliente se incorpore explícitamente a One Facility. No concede accesos ni crea la organización.
- \`source_system\` y \`source_key\`: claves de trazabilidad para la importación idempotente R1-B; nombres parecidos no se fusionan automáticamente.

## Seguridad

RLS en las tres tablas. Solo miembros activos de la organización pueden leer; escritura de registros de la organización reservada a \`owner/admin/manager\` activos. Sin acceso \`anon\` ni borrado físico vía \`authenticated\`. Las columnas \`organization_id\`, \`commercial_client_id\` y el enlace futuro no pueden cambiarse desde la interfaz de usuario. El servicio privilegiado debe validar permisos de forma explícita antes de cualquier carga.

La tabla antigua \`provider_commercial_clients\` no se usa en R1 porque conserva el modelo \`provider_profiles\` y permisos de lectura demasiado amplios para información comercial.

## Gates para despliegue

1. Revisar la migración SQL y el test pgTAP en el PR.
2. Ejecutar el test \`supabase/tests/romax_r1a_commercial_directory.test.sql\` **solo en base de QA desechable**, nunca en Supabase Cloud, dado que crea identidades sintéticas bajo \`BEGIN/ROLLBACK\`.
3. Validar ACL, RLS, integridad de FK, protección entre proveedores y cero regresiones de \`requests\`/\`quotes\`.
4. Aplicar la migración una sola vez en una ventana controlada, con verificación y revisión de Supabase Security Advisors.
5. R1-B: preparar lotes de clientes, sedes y contactos desde el Drive privado de ROMAX; no publicar información personal ni comercial en el repositorio público.

**Fuera de R1-A:** importar clientes, interfaz administrativa, historial de cotizaciones, cambios de \`requests\` y \`quotes\`, Vercel deploy.
