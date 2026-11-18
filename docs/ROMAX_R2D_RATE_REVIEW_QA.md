# ROMAX R2D — Revisión y activación controlada de tarifas

**Fecha:** 18-nov-2026  
**Estado:** interfaz implementada en rama; QA visual pendiente.

## Objetivo

Permitir que las tarifas registradas como `pending_review` pasen a `approved` o `rejected` con una intervención humana explícita.

La aprobación no cambia el histórico comercial ni el precio de venta.

## Flujo

1. Usuario autorizado registra una tarifa.
2. La tarifa queda `pending_review`.
3. R2D muestra las pendientes en una bandeja visible.
4. El revisor comprueba:
   - recurso;
   - proveedor/costo interno;
   - unidad;
   - costo original;
   - equivalente PEN;
   - moneda y FX;
   - fuente;
   - IGV;
   - vigencia.
5. **Aprobar** cambia el estado a `approved`.
6. **Rechazar** exige una nota de revisión.
7. La base registra quién y cuándo realizó la revisión mediante el trigger existente.
8. Una tarifa aprobada permanece inmutable salvo cierre de vigencia o archivado conforme a las reglas R2A.

## Reglas

- Solo owner/admin/manager/quote_manager de ROMAX pueden revisar.
- La aprobación está protegida también por RLS y trigger; la UI no es la barrera de seguridad.
- No se permite aprobar dos versiones con vigencias solapadas dentro de la misma serie recurso/proveedor.
- Una tarifa rechazada no se convierte en costo vigente.
- Una corrección de una tarifa aprobada se realiza mediante una nueva versión, no editando el precio aprobado.

## QA pendiente

### Navegador / sesión ROMAX

- [ ] Ver una tarifa pendiente.
- [ ] Aprobar una tarifa.
- [ ] Confirmar estado `approved`, revisor y fecha.
- [ ] Rechazar otra tarifa con nota.
- [ ] Confirmar estado `rejected` y nota.
- [ ] Intentar aprobar una vigencia solapada y comprobar rechazo del backend.
- [ ] Confirmar que una tarifa aprobada no permite modificar el costo.
- [ ] Confirmar que la comparación sigue mostrando proveedor, versión, fuente, vigencia y FX.

### Seguridad

- [ ] Rol autorizado puede revisar.
- [ ] Rol sin permiso no puede revisar.
- [ ] Otro tenant no ve tarifas ROMAX.
- [ ] La aprobación no requiere ni expone service_role.

## Estado de datos de prueba

Actualmente ROMAX tiene 2 tarifas de prueba, ambas `pending_review`, asociadas a `Material Test 001`. No se modificaron durante esta implementación para conservar un estado útil para el QA visual.

## Próximo gate

Cuando Vercel vuelva a aceptar builds, obtener preview del commit de R2D y ejecutar el QA visual real con esas dos tarifas de prueba. No aprobarlas automáticamente desde SQL.
