# ROMAX R1-B — Contactos compartidos entre varias sedes

**Estado inicial (14-nov-2026):** R1-A terminado. Seis clientes comerciales y 145 sedes homologadas en Supabase Cloud. Contactos todavía sin importar al comenzar esta fase.

## Decisión técnica

Se incorpora \`commercial_client_contact_sites\`, una relación **muchos a muchos** entre \`commercial_client_contacts\` y \`commercial_client_sites\`.

- Un contacto existe **una sola vez por identidad comercial** y puede estar relacionado a cero, una o múltiples sedes.
- Contactos sin sede identificable permanecen vinculados a su \`commercial_client_id\`, sin enlaces de sede.
- Las FK compuestas (organización, cliente, contacto/sede) impiden asociar sedes de otro proveedor o de otro cliente del mismo proveedor.
- La clave primaria \`(organization_id, commercial_contact_id, commercial_site_id)\` impide enlaces repetidos.
- RLS: miembro activo puede leer; owner/admin/manager puede añadir o retirar vínculos; \`anon\` no puede leer, y el navegador no puede actualizar claves estructurales.
- \`commercial_client_contacts.commercial_site_id\` legado sigue intacto y opcional; las nuevas importaciones usan \`NULL\` y la relación muchos-a-muchos, no duplican personas.
- **No** se crean usuarios ni organizaciones para clientes externos. Sin cambios en \`requests\`, \`quotes\` u órdenes.

## Contrato de depuración e importación del libro privado

**Fuente única para filas y coordenadas:** hojas individuales del archivo Excel consolidado de ROMAX; \`BASE GENERAL\` se usa para conciliar, no para duplicar registros.

Auditoría previa en origen:

| Cliente | Filas fuente | Candidatos tras exclusiones | Contactos distintos propuestos |
| --- | ---: | ---: | ---: |
| Cassinelli | 10 | 10 | 10 |
| Makro | 59 | 59 | 59 |
| National | 31 | 26 | 14 |
| Oechsle | 33 | 25 | 21 |
| Sodimac / Maestro | 108 | 108 | 58 |
| Tgestiona | 48 | 42 | 9 |
| **Total** | **289** | **270** | **171** |

Las 19 filas en revisión: 5 rótulos genéricos de nivel de contacto (National), 8 fichas sin nombre de persona (Oechsle) y 6 celdas con dos nombres (Tgestiona). No convertir etiquetas en personas ni asignar a una identidad suplantada; los detalles privados y referencias de celda se entregan fuera de GitHub.

### Identidad y vínculos

- Las personas candidatas se agrupan **dentro del mismo cliente** por nombre normalizado y correo; si falta correo, por nombre y teléfono, sin fusionar personas de distintos clientes.
- Identidades con correos compartidos pero nombres distintos **no** se fusionan automáticamente; estos casos quedan señalados para calidad.
- Cada fila confirma uno o varios locales de cobertura si la etiqueta de origen fue homologada. La asociación se hace contra las **145 sedes existentes**, no se inventan nuevas.
- Los grupos de Tgestiona homologados como 2/3 sedes se vinculan a todas las sedes que indica el grupo, sin seleccionar una arbitrariamente.
- Si el origen está vacío, es un marcador genérico o solo describe cobertura ITSE, el contacto permanece asociado al cliente y sin sede artificial.
- \`source_system\` y \`source_key\` de cada contacto son estables por identidad; el vínculo contacto-sede se deduplica por PK. Nunca incluir correos o teléfonos en el repo público.

## QA y despliegue

1. Ejecutar migración y \`supabase/tests/romax_r1b_contact_multisite.test.sql\` en base Supabase local desechable.
2. Confirmar RLS, grants, FKs cruzadas, acceso owner/viewer/outsider y compatibilidad con todas las pruebas anteriores.
3. Merge del PR, aplicar migración en Supabase Cloud con versión sincronizada con \`supabase_migrations.schema_migrations\`.
4. Verificar tabla vacía y seguridad con consultas de solo lectura.
5. Importar solamente 171 contactos candidatos en lotes transaccionales, con cláusula de no duplicación y registro de claves de origen; crear vínculos exclusivamente contra sedes homologadas existentes.
6. Verificar conciliación real: 6 clientes, 145 sedes, contactos únicos, vínculos únicos, 19 filas excluidas, sin cambios en 10 organizaciones, 33 solicitudes ni 22 cotizaciones preexistentes (revisar línea de base).
7. Registrar informe agregado de importación y excepciones/hoja-fila en archivo **privado**, no publicarlas en repositorio abierto.

**Pendiente de ROMAX:** H16 significado de siglas PVS/PVH/PVE/VIV; este modelo no expande esas siglas ni adjudica un titular jurídico de facturación.

## Resguardo

Se mantiene \`is_active\` de contactos y sedes para bajas lógicas; la eliminación de un vínculo no borra personas, sitios ni históricos. Las credenciales privadas y los archivos con PII jamás van a GitHub.
