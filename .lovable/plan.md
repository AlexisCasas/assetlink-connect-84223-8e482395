## Objetivo

Mejorar el flujo de cotización del proveedor en One Facility manteniendo la base actual (`QuoteForm`, `QuoteSummary`, `QuoteDetailDialog`, `ProviderRequestList`, tabla `quotes`), evolucionándola hacia secciones estandar, cálculo en cascada (Gastos Generales → Utilidades → IGV), condiciones de venta y modos resumen/detalle.

## 1. Migración de base de datos

Ampliar la tabla `quotes` (ALTER TABLE / ADD COLUMN IF NOT EXISTS) sin romper datos existentes:

- `quote_sections jsonb default '[]'`
- `base_subtotal numeric default 0`
- `general_expenses_percentage numeric default 0`
- `general_expenses_amount numeric default 0`
- `utilities_percentage numeric default 0`
- `utilities_amount numeric default 0`
- `subtotal numeric default 0`
- `igv_amount numeric default 0`
- `total_amount numeric default 0`
- `sales_conditions jsonb default '{}'`
- `sent_at timestamptz null`
- `emailed_at timestamptz null`
- `updated_at timestamptz default now()`

Trigger `touch_updated_at` reusado para mantener `updated_at`.

`amount` y `description` permanecen como legacy. `amount = total_amount` siempre.

## 2. Tipos TypeScript

Nuevo bloque en `src/types/request.ts` (sin romper lo anterior):

```ts
export type QuoteSectionType = 'line_items' | 'percentage';

export interface QuoteSectionItem {
  id: string;
  description: string;
  quantity: number;
  unitMeasure: string;
  totalPrice: number;
}

export interface QuoteSection {
  id: string;
  name: string;
  type: 'line_items';
  order: number;
  enabled: boolean;
  items: QuoteSectionItem[];
  subtotal: number;
}

export interface QuoteSalesConditions {
  validityDays: number;
  warrantyMonths: number;
  deliveryDays: number;
  paymentTerms: string;
  additionalNotes?: string;
}

export interface QuoteCalculationSummary {
  baseSubtotal: number;
  generalExpensesPercentage: number;
  generalExpensesAmount: number;
  utilitiesPercentage: number;
  utilitiesAmount: number;
  subtotal: number;
  igvAmount: number;
  totalAmount: number;
}
```

Se extiende `Quote` con `sections?`, `salesConditions?`, `calculation?`, `emailedAt?`, `sentAt?`.

## 3. Helpers nuevos

`src/lib/quoteCalculations.ts`:

- `DEFAULT_SECTIONS` (Actividades, Materiales, Equipos, Movilización).
- `GENERAL_SECTION` factory.
- `calculateSectionSubtotal`, `calculateQuote(sections, gPct, uPct)`.
- `formatSoles(value)` → `S/ 0.00`, robusto a `NaN`.

## 4. QuoteForm.tsx (rewrite del cuerpo)

- Botón principal: **"Agregar sección"** (no "Agregar campo").
- Botón **"Usar sección general"** → reemplaza secciones por una sola sección `General`.
- Botón **"Restaurar secciones por defecto"**.
- Cada sección de líneas con:
  - Nombre editable
  - Filas: Descripción · Cantidad · Unidad · **Precio total** (sin precio unitario)
  - Agregar / eliminar fila, eliminar sección
- Toggles independientes para **Gastos Generales** y **Utilidades** con input de % (no tabla).
- Al guardar/enviar usa `upsert` en `quotes` por `(request_id, provider_id)` para no duplicar borradores. Si ya existía borrador, actualiza.
- Validaciones:
  - Enviar requiere ≥1 línea con descripción y `totalPrice > 0`.
  - No permitir negativos.
  - Borrador permitido con datos parciales.
- Carga inicial: si llega `existingQuote` (prop opcional) hidrata todo; si no, usa secciones default.

Acepta nueva prop opcional `existingQuote?: any` para edición de borrador.

## 5. QuoteSummary.tsx

Reescribir para mostrar:

- Lista de secciones con subtotal por sección (solo `enabled` y `line_items`).
- Subtotal base.
- Gastos Generales % y monto.
- Utilidades % y monto.
- Subtotal.
- IGV 18%.
- **Total** en `S/`.
- Mantiene props compatibles: nueva forma `QuoteSummary({ sections, generalExpensesPercentage, utilitiesPercentage, salesConditions })`. Las llamadas existentes con `data` se siguen soportando con guard.

## 6. Botones de acción

En el footer del `QuoteForm`:

- **Guardar borrador** → `status='draft'`, sin notificación.
- **Enviar cotización** → `status='submitted'`, `sent_at=now()`, notificación `quote_received`.
- **Enviar por correo** (mock) → `status='submitted'`, `emailed_at=now()`, notificación + toast `"Cotización enviada por correo"`.
- **Cancelar** → cierra.

Actualiza `requests.status` a `'quoted'` solo si aún está en `'sent'` (no cierra para otros).

## 7. ProviderRequestList.tsx

- Carga `quotes` del proveedor para todas las solicitudes visibles.
- Nueva columna **Estado cotización** con badge:
  - Sin cotizar / Borrador / Enviada / Enviada por correo / Aprobada / Rechazada.
- Acciones por fila:
  - Sin cotizar → **Cotizar**
  - Borrador → **Editar borrador** (abre `QuoteForm` con `existingQuote`)
  - Enviada / por correo → **Ver cotización** (abre `QuoteDetailDialog` en modo proveedor)

## 8. QuoteDetailDialog.tsx

Reescribir con tabs **Resumen / Detalle**:

- **Resumen**: nombre proveedor, descripción, elaborado por, lista secciones con subtotal, GG, Utilidades, Subtotal, IGV, Total.
- **Detalle**: cada sección con tabla de líneas, subtotal de sección, luego GG/Utilidades/Subtotal/IGV/Total y bloque de Condiciones de Venta + notas.
- Mantiene compatibilidad: si la cotización legacy no tiene `quote_sections`, cae al render anterior (mostrando `description` y `amount`).

## 9. Notificaciones

Helper `createQuoteReceivedNotification(request, quote, providerName, viaEmail)` insertando en `notifications` con `type='quote_received'`, asociando `request_id` + `quote_id`.

## 10. Datos demo

Insertar (mediante insert tool, post-migración) una cotización demo para ROMAX en una solicitud existente del seed (si existe) con la estructura del enunciado. Si no hay solicitud apta, omitir sin romper.

## 11. Impacto en otros archivos

- `PublicRequestList.tsx` y `TeamMemberView.tsx`: solo se ajusta el **payload** al guardar (incluir nuevos campos = 0/[] cuando aplique). No se modifica su UI.
- `QuoteListDialog.tsx` y `RequestList.tsx`: sin cambios estructurales; siguen leyendo `amount` (= `total_amount`).

## Archivos a crear

- `src/lib/quoteCalculations.ts`
- `supabase/migrations/<timestamp>_quote_sections.sql`

## Archivos a editar

- `src/types/request.ts`
- `src/components/requests/QuoteForm.tsx`
- `src/components/requests/QuoteSummary.tsx`
- `src/components/requests/QuoteDetailDialog.tsx`
- `src/components/requests/ProviderRequestList.tsx`
- `src/components/requests/PublicRequestList.tsx` (solo payload)
- `src/components/requests/TeamMemberView.tsx` (solo payload)

## Criterios de aceptación

Cubre todos los puntos de la sección 15 del enunciado, sin romper los flujos de cliente y equipo.
