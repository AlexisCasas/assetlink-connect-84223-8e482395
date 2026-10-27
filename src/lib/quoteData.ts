import { supabase } from '@/integrations/supabase/client';

/**
 * Cotizaciones delegadas al Facility Manager (9C.5). El FM decide en nombre
 * del cliente; nunca cotiza como proveedor. Todo pasa por RPCs minimizadas:
 * la RLS de quotes no se abre. El importe llega `null` hasta que las
 * cotizaciones recibidas alcancen el mínimo de la solicitud (la regla la
 * aplica el servidor, no esta capa).
 */

export interface DelegatedQuote {
  id: string;
  requestId: string;
  status: string;
  description: string;
  createdAt: string;
  /** null mientras los importes no sean visibles. */
  amount: number | null;
  approvedAt: string | null;
  approvalReason: string | null;
  rejectedAt: string | null;
  rejectionReason: string | null;
  /** Calculado por el servidor: capacidad + solicitud abierta + importes visibles. */
  canApprove: boolean;
}

export interface DelegatedRequestQuotes {
  requestId: string;
  minQuotes: number;
  quotesReceived: number;
  quotesClosed: boolean;
  pricesVisible: boolean;
  canApprove: boolean;
  quotes: DelegatedQuote[];
}

interface DelegatedQuotePayload {
  id: string;
  request_id: string;
  status: string;
  description: string;
  created_at: string;
  amount: number | null;
  approved_at: string | null;
  approval_reason: string | null;
  rejected_at: string | null;
  rejection_reason: string | null;
  can_approve: boolean;
}

interface DelegatedRequestQuotesPayload {
  request_id: string;
  min_quotes: number;
  quotes_received: number;
  quotes_closed: boolean;
  prices_visible: boolean;
  can_approve: boolean;
  quotes: DelegatedQuotePayload[];
}

const mapDelegatedQuote = (payload: DelegatedQuotePayload): DelegatedQuote => ({
  id: payload.id,
  requestId: payload.request_id,
  status: payload.status,
  description: payload.description,
  createdAt: payload.created_at,
  amount: payload.amount === null || payload.amount === undefined ? null : Number(payload.amount),
  approvedAt: payload.approved_at,
  approvalReason: payload.approval_reason,
  rejectedAt: payload.rejected_at,
  rejectionReason: payload.rejection_reason,
  canApprove: payload.can_approve,
});

/** null = la solicitud no existe, es interna, es un borrador o no es del
 * cliente (el servidor no distingue entre esos casos). */
export async function fetchDelegatedRequestQuotes(
  clientOrganizationId: string,
  requestId: string,
): Promise<DelegatedRequestQuotes | null> {
  const { data, error } = await supabase.rpc('get_facility_management_request_quotes', {
    _client_organization_id: clientOrganizationId,
    _request_id: requestId,
  });
  if (error) throw error;
  if (!data) return null;
  const payload = data as unknown as DelegatedRequestQuotesPayload;
  return {
    requestId: payload.request_id,
    minQuotes: payload.min_quotes,
    quotesReceived: payload.quotes_received,
    quotesClosed: payload.quotes_closed,
    pricesVisible: payload.prices_visible,
    canApprove: payload.can_approve,
    quotes: (payload.quotes ?? []).map(mapDelegatedQuote),
  };
}

/** Cotizaciones en revisión por solicitud (columna de la lista). */
export async function fetchDelegatedQuoteCounts(clientOrganizationId: string): Promise<Record<string, number>> {
  const { data, error } = await supabase.rpc('get_facility_management_quote_counts', {
    _client_organization_id: clientOrganizationId,
  });
  if (error) throw error;
  const counts: Record<string, number> = {};
  for (const row of (data ?? []) as unknown as { request_id: string; submitted_quotes: number }[]) {
    counts[row.request_id] = Number(row.submitted_quotes);
  }
  return counts;
}

export async function approveDelegatedQuote(clientOrganizationId: string, quoteId: string): Promise<void> {
  const { error } = await supabase.rpc('approve_facility_management_quote', {
    _client_organization_id: clientOrganizationId,
    _quote_id: quoteId,
  });
  if (error) throw error;
}

export async function rejectDelegatedQuote(clientOrganizationId: string, quoteId: string, reason: string | null): Promise<void> {
  const { error } = await supabase.rpc('reject_facility_management_quote', {
    _client_organization_id: clientOrganizationId,
    _quote_id: quoteId,
    _reason: reason ?? undefined,
  });
  if (error) throw error;
}
