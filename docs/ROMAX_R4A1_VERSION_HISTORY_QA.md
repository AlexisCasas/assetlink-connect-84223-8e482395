# ROMAX R4-A.1 — Historial y guardado idempotente

## Defecto reproducido
- One Facility Preview / ROMAX, 18-nov-2026: el usuario guardó sin cambios y recibió **"Versión 3 creada como borrador"**.
- Cloud conservaba V1 superseded, V2 superseded y V3 draft para la oportunidad QA de ventiladores. La oportunidad permanecía `new` pese a contener análisis.
- **No eliminar V3 ni reescribir V1/V2:** son evidencia histórica y se preservan.

## Objetivo del incremento
1. No crear una nueva versión si el contenido normalizado coincide con la última, incluso en doble envío/concurrencia.
2. Primer guardado de un análisis: avanzar la oportunidad desde `new`, `reviewing` o `ready_for_analysis` a `in_analysis`, sin regresar `quoted` ni `discarded`.
3. Mostrar `Versión N · Borrador vigente` y consultar/comparar versiones anteriores, sin poder editarlas.

## Implementación
- Nueva migración aditiva `20261118181500_romax_r4a1_idempotent_analysis_save.sql` define `romax_save_opportunity_analysis_v2`. No reemplaza ni elimina `v1`.
- RPC `SECURITY INVOKER`: verifica `auth.uid()`, rol comercial del tenant, RLS y consistencia de las partidas. Serializa por oportunidad usando advisory transaction lock.
- Compara servicio, alcance, tres listas y conjunto normalizado de partidas (orden indiferente). Una solicitud idéntica devuelve la versión vigente con `created_new=false`.
- Si hay cambio real, persiste análisis y partidas juntos, supersede versión anterior y actualiza etapa comercial en la misma transacción.
- La UI consulta `v2` y distingue `Análisis guardado` de `Sin cambios`; el historial separado permite comparar una versión anterior con la vigente.
- El historial muestra fecha, responsable como ID abreviado, tipo de origen, estado, partidas y notas. No introduce permisos nuevos sobre los datos.

## QA aislado requerido
- `supabase test db` aplica todas las migraciones a una base **descartable**, incluyendo las 30 aserciones de `romax_r4a1_idempotency.test.sql` con ROLLBACK.
- Verificar: 1) primer guardado => V1 e `in_analysis`; 2) no-op y reordenación => V1; 3) cambio real => V2 y V1 sin alteraciones; 4) rollback atómico de partida inválida; 5) tenant no autorizado y viewer denegados; 6) no regresar `quoted`.
- Frontend: TypeScript, ESLint y Vite en GitHub Actions.
- Preview: seleccionar V1/V2/V3, verificar comparación de partidas y notas, y guardar sin cambios para confirmar que no se genera V4. Comprobar que la oportunidad se muestra `En análisis` tras la primera llamada a `v2`.

## Gating y despliegue
1. Aprobar CI de PR en GitHub.
2. **Autorizar y aplicar por separado** la migración aditiva en Supabase Cloud; verificar permisos, RPC y conteos iniciales. No modificar historiales existentes.
3. QA visual en Vercel Preview con usuario ROMAX. La vista nueva requiere que Cloud tenga `v2`; antes de ello la llamada a Guardar fallará controladamente.
4. Merge y despliegue a producción solamente con autorización explícita.

Este PR **no aplica SQL en Cloud**, no modifica Drive ni promueve ningún deployment Vercel.
