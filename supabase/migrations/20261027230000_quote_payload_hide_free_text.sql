-- =========================================================================
-- 9C.5-HF01 — proteger los textos libres de una cotización mientras los
-- importes están ocultos (respuesta DELEGADA del Facility Manager).
--
-- Origen del fallo: facility_management_quote_payload (20260930120000) anulaba
-- solo `amount` cuando prices_visible = false y devolvía tal cual `description`,
-- `approval_reason` y `rejection_reason`. Esos textos los escribe el proveedor
-- o el cliente en texto libre y pueden contener importes ("S/ 1800.00",
-- "mil ochocientos soles"), así que un FM con quotes.view podía leer la cifra
-- aunque amount fuera null. No hay forma fiable de detectar "texto monetario"
-- (formatos, monedas, palabras, idiomas), por lo que NO se filtra por patrón:
-- mientras los importes estén ocultos, los tres campos se devuelven null.
--
-- Cambio: solo este helper interno. Las claves de la respuesta son las mismas
-- (el contrato JSON no cambia: description/approval_reason/rejection_reason
-- pasan a ser null mientras prices_visible = false). Con prices_visible = true
-- el resultado es idéntico al de 9C.5.
--
-- Sin cambios: las cinco RPCs (firmas, ACL, comprobaciones de autorización),
-- la regla de visibilidad (recibidas >= min_quotes o envío cerrado), la RLS de
-- quotes, las policies de proveedor, approve_quote/reject_quote y el flujo
-- directo del cliente, que sigue leyendo las filas por RLS.
-- =========================================================================

CREATE OR REPLACE FUNCTION public.facility_management_quote_payload(_quote public.quotes, _prices_visible boolean, _can_decide boolean)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'id', _quote.id,
    'request_id', _quote.request_id,
    'status', _quote.status,
    'description', CASE WHEN COALESCE(_prices_visible, false) THEN _quote.description END,
    'created_at', _quote.created_at,
    'amount', CASE WHEN COALESCE(_prices_visible, false) THEN _quote.amount END,
    'approved_at', _quote.approved_at,
    'approval_reason', CASE WHEN COALESCE(_prices_visible, false) AND _quote.status = 'approved' THEN _quote.approval_reason END,
    'rejected_at', _quote.rejected_at,
    'rejection_reason', CASE WHEN COALESCE(_prices_visible, false) THEN _quote.rejection_reason END,
    'can_approve', COALESCE(_can_decide, false) AND COALESCE(_prices_visible, false) AND _quote.status = 'submitted'
  );
$$;

-- CREATE OR REPLACE conserva owner y ACL; se reafirma que sigue siendo interna.
REVOKE ALL ON FUNCTION public.facility_management_quote_payload(public.quotes, boolean, boolean) FROM PUBLIC, anon, authenticated;
