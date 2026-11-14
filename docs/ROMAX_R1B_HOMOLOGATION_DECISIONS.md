# ROMAX R1-B — Decisiones de homologación aprobadas

**Fecha:** 14-nov-2026. **Fuente:** validación expresa del responsable del piloto y contrastación con las hojas individuales de la base comercial ROMAX.
**Privacidad:** el archivo de revisión con hoja/fila/alias completo permanece fuera del repositorio público; este documento contiene decisiones de modelo y resultados agregados.

## Decisiones aprobadas

| ID | Resultado y tratamiento | Estado |
| --- | --- | --- |
| H01 | Makro tienda Surco y Oficina Central son dos sedes independientes. | Confirmado |
| H02 | Makro SMP (REX) y SMP - MK se mantienen separados por direcciones/referencias distintas. | Confirmado |
| H03 | No fusionar sede sin número con sede 1 en Arequipa, Piura, Trujillo y Zárate. | Confirmado |
| H04 | Etiqueta National TIENDA es genérica: no crear sede. | Confirmado |
| H05 | National es intermediario Facility Manager que deriva servicios a ROMAX; comercialmente se registra como cliente de ROMAX, sin organización FM adicional. | Confirmado |
| H06 | SFERA se conserva como establecimiento separado de otros locales Oechsle. | Confirmado |
| H07 | MAC se conserva como establecimiento separado de otros locales Oechsle. | Confirmado |
| H08 | Contactos de Oechsle sin sede permanecen asociados al cliente. | Confirmado |
| H09 | Mantener agrupación Sodimac / Maestro hasta validar razón social de facturación en las cotizaciones. | Confirmado |
| H10 | Próceres/Puruchuco/Santa Clara: tres sedes individuales; contactos de cobertura compartida. | Confirmado |
| H11 | Benavides/Libertadores/Santa Cruz: tres sedes individuales; contactos de cobertura compartida. | Confirmado |
| H12 | Bolognesi y Salaverry: dos sedes. El sufijo PVH de la etiqueta compuesta no se atribuye arbitrariamente a una sola. | Confirmado |
| H13 | Caminos del Inca/La Paz/Dasso: tres sedes individuales; contactos compartidos. | Confirmado |
| H14 | Trujillo/Trujillo Mansiche: dos sedes individuales; contactos compartidos. | Confirmado |
| H15 | TIENDAS VARIAS (ITSE) es categoría/cobertura de proyectos pequeños, NO cliente ni sede. | Confirmado |
| H16 | Significado de PVS/PVH/PVE/VIV y destinatario de cotizaciones pendientes: preservar los códigos en los nombres fuente sin expandir. | **Pendiente** |
| H17 | Contactos Cassinelli sin tienda identificada: vincular al cliente, sin inventar sede. | Confirmado |

**Recordatorio:** las expresiones `cliente comercial` y `Facility Manager intermediario` representan una relación comercial desde la perspectiva de ROMAX. No crean una organización cliente o FM de One Facility ni conceden acceso externo a datos.

## Importación de sedes aplicada (lote L2)

- Tablas productivas: `public.commercial_client_sites`, bajo el `organization_id` real de ROMAX.
- `source_system`: `romax_r1b_homologation_20261114`.
- Insertadas: **145**; verificadas: **145** con **145 source_key** distintas.
- Distribución: Makro 33; National 8; Oechsle 31; Sodimac/Maestro 54; Tgestiona 19; Cassinelli 0.
- Tres tipos excluidos de creación ficticia: National/TIENDA y Tgestiona/TIENDAS VARIAS (ITSE) (dos etiquetas), contactos sin sede física concreta.
- No se importaron contactos en L2. Ningún contacto quedó asignado arbitrariamente a una ubicación.
- Conteos de control: 6 clientes ROMAX, 0 contactos ROMAX, 10 organizaciones, 33 solicitudes y 22 cotizaciones sin cambios.

## Información que aún debe resolverse

1. **H16:** ROMAX no ha definido el significado exacto de PVS, PVH, PVE y VIV. No expandir siglas ni inferir titulares de facturación.
2. **Relación muchos-a-muchos de contactos:** `commercial_client_contacts.commercial_site_id` es opcional, pero permite una sola sede por persona. Para reflejar cobertura de varias sedes, crear una tabla de relación `commercial_contact_sites` con FKs compuestas que comprueben mismo proveedor, mismo cliente y sede. Evitar duplicar personas por cada establecimiento.
3. **Datos personales ambiguos:** cinco filas National con nombres tipo nivel de contacto, seis celdas Tgestiona que contienen dos nombres. Revisar en el archivo privado sin publicar PII; no convertir estas cadenas en un usuario real ni en dos personas hasta conciliar datos.
4. **Facturación Sodimac/Maestro:** pendiente de contrastar razón social de cotizaciones históricas, sin separar por intuición.
5. **Tgestiona ITSE:** los trabajos se registrarán en objetos de oportunidad/servicio o cotización, nunca como sitio virtual TIENDAS VARIAS.

## Próximo gate R1-B (contactos)

- Conservar las 289 fichas originales y su trazabilidad; identificar filas aptas/ambiguas.
- Diseñar y probar el enlace de múltiples sedes por contacto en una base aislada; proponer PR/migración, no DDL directo en Cloud sin QA.
- Dry-run de contactos con source_key estable, comprobación de roles RLS y conciliación antes de escribir.
- Actualizar plan maestro y auditoría pública con los totales y estado real, sin datos personales ni URLs privadas.

**Documentos hermanos:** `docs/ROMAX_PILOT_MASTER_PLAN.md`, `docs/ROMAX_R1B_HOMOLOGATION_GATE.md`, `docs/ROMAX_R1B_SOURCE_AUDIT.md`.
