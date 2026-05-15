## Objetivo

Reemplazar la pantalla "Mi Perfil" del proveedor (`ProviderProfile.tsx`) por una experiencia completa con 3 secciones (Mi información, Empresa, Información Comercial), persistiendo los datos en Supabase. Solo afecta al rol `proveedor`.

## 1. Base de datos (migración nueva)

**Tabla `provider_profiles`** (1:1 con `providers`, dueño = `auth.uid()` del proveedor):
- `provider_id uuid PK` (= profiles.provider_id del usuario)
- `owner_user_id uuid` (auth.uid del proveedor dueño, para RLS)
- Mi info: `contact_name`, `contact_email`, `phone`, `whatsapp_phone`, `position`
- Empresa: `business_name`, `commercial_name`, `tax_id`, `country`, `currency`, `timezone`, `fiscal_address`, `city`, `region`, `website`, `industry`, `logo_url`
- Comercial: `company_description`, `foundation_year`, `employee_range`, `coverage_area`, `presentation_letter_url`, `presentation_letter_name`, `receive_all_invitations boolean default false`
- `certification_status` enum (`not_started`,`in_review`,`certified`,`rejected`) default `not_started`
- `created_at`, `updated_at` + trigger `touch_updated_at`
- RLS: dueño (`owner_user_id = auth.uid()`) puede CRUD; otros autenticados solo SELECT (clientes pueden ver perfil público).

**Tabla `provider_commercial_clients`**:
- `id`, `provider_id`, `business_name`, `contact_person`, `email`, `phone`, `extension`, timestamps
- RLS: dueño del provider puede CRUD (vía join a `provider_profiles.owner_user_id`); SELECT abierto a authenticated.

**Tabla `provider_documents`**:
- `id`, `provider_id`, `document_type` text (`logo|presentation_letter|certification_document`), `file_name`, `file_url`, `status`, timestamps
- RLS: igual que clientes comerciales.

**Storage buckets** (privados, con policies dueño = carpeta `{provider_id}/...`):
- `provider-logos`
- `provider-documents`

**Seed**: insertar `provider_profiles` demo para `provider-1` (proveedor@test.com) con datos ROMAX y 3 clientes comerciales — vía tool `supabase--insert` después de la migración.

## 2. Tipos

`src/types/provider.ts` (nuevo):
- `ProviderProfile`, `ProviderCommercialClient`, `CertificationStatus`, `EmployeeRange`.

## 3. Componente principal

Reemplazar `src/components/requests/ProviderProfile.tsx` con un wrapper que:
- Si `user.role !== 'proveedor'` → muestra "Acceso no permitido" + botón a Dashboard.
- Carga `provider_profiles` por `owner_user_id = user.id` (crea fila vacía si no existe).
- Renderiza header "Mi Perfil / Gestiona tu información como proveedor".
- 3 cards en columna (sin tabs para mantenerlo simple; cada card maneja su propio modo lectura/edición).

## 4. Sub-componentes nuevos en `src/components/provider/`

- `MyInfoCard.tsx` — campos mi info, modo lectura/edición, diálogos `ChangeEmailDialog` y `ChangePasswordDialog` (mockup, solo toast).
- `CompanyCard.tsx` — datos empresa + upload logo (a `provider-logos` bucket), preview, validaciones requeridas.
- `CommercialInfoCard.tsx` — datos comerciales + sub-bloques:
  - `CommercialClientsTable.tsx` — CRUD inline contra `provider_commercial_clients`.
  - `PresentationLetterUpload.tsx` — un solo archivo activo en `provider-documents`.
  - Switch `receive_all_invitations`.
  - `CertificationBlock.tsx` — refactor del actual: 0/5 docs, badge (No certificado / En revisión / Certificado), enviar → `certification_status='in_review'`.

## 5. Visibilidad por rol

- `Dashboard.tsx` case `'profile'`: si `user.role !== 'proveedor'` redirigir a `dashboard`.
- Sidebar ya muestra "Mi Perfil" solo a proveedor — no se toca.

## 6. Compatibilidad

- No tocar `MOCK_PROVIDERS`, `Provider` interface, ni flujos de cliente/equipo.
- `providers.certified` se mantiene; espejamos vía `certification_status='certified'` cuando aplique para no romper consultas existentes.

## Archivos

```
supabase/migrations/<new>.sql       (tablas, enum, RLS, buckets+policies, trigger)
src/types/provider.ts               (nuevo)
src/components/requests/ProviderProfile.tsx   (reescrito como wrapper)
src/components/provider/MyInfoCard.tsx
src/components/provider/CompanyCard.tsx
src/components/provider/CommercialInfoCard.tsx
src/components/provider/CommercialClientsTable.tsx
src/components/provider/PresentationLetterUpload.tsx
src/components/provider/CertificationBlock.tsx
src/components/provider/ChangePasswordDialog.tsx
src/pages/Dashboard.tsx             (guard de rol en case 'profile')
```

## Criterios de aceptación

Los 9 puntos: 3 secciones, edición/guardado por card, upload de logo, CRUD de clientes comerciales, carta de presentación reemplazable, switch de invitaciones, certificación con estado "En revisión", solo afecta a proveedor, login demo y demás flujos intactos, responsive shadcn/Tailwind.
