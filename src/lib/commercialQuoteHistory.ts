import { supabase } from '@/integrations/supabase/client';

/**
 * R1-E reads the provider-owned historical quotations schema, which was added
 * after the checked-in generated Supabase database types. This minimal, typed,
 * READ-ONLY adapter is deliberately scoped to SELECT (never to service_role).
 * Replace it with generated types when database type regeneration is done.
 */
interface ReadResult<T> {
  data: T[] | null;
  error: { message: string } | null;
  count: number | null;
}
interface ReadQuery<T> extends PromiseLike<ReadResult<T>> {
  eq(column: string, value: string): ReadQuery<T>;
  is(column: string, value: null): ReadQuery<T>;
  gte(column: string, value: string): ReadQuery<T>;
  lte(column: string, value: string): ReadQuery<T>;
  ilike(column: string, pattern: string): ReadQuery<T>;
  order(column: string, options?: { ascending?: boolean }): ReadQuery<T>;
  range(start: number, end: number): ReadQuery<T>;
}
interface ReadTable<T> {
  select(columns: string, options?: { count?: 'exact' }): ReadQuery<T>;
}
const historyReader = supabase as unknown as {
  from: <T>(table: string) => ReadTable<T>;
};

export interface CommercialClientOption {
  id: string;
  business_name: string;
}
export interface CommercialSiteOption {
  id: string;
  commercial_client_id: string;
  site_name: string;
}
export interface CommercialQuoteHistory {
  id: string;
  organization_id: string;
  commercial_client_id: string | null;
  commercial_site_id: string | null;
  source_client_name: string | null;
  source_site_name: string | null;
  reference_document: string | null;
  reference_filename: string | null;
  reference_review: 'match' | 'mismatch' | 'unverified';
  proposal_date: string | null;
  service_title: string;
  currency_code: string | null;
  amount_net: number | null;
  amount_gross: number | null;
  price_review: 'pending' | 'verified' | 'needs_review';
  commercial_status: string;
  client_match_status: 'matched' | 'unmatched' | 'needs_review';
}
export interface CommercialQuoteDocument {
  id: string;
  source_provider: string;
  source_file_id: string;
  source_filename: string;
  mime_type: string;
  document_role: string;
}
export interface QuoteHistoryFilters {
  clientId: string;
  siteId: string;
  service: string;
  reference: string;
  referenceField: 'document' | 'filename';
  fromDate: string;
  toDate: string;
}
export const EMPTY_QUOTE_HISTORY_FILTERS: QuoteHistoryFilters = {
  clientId: 'all',
  siteId: 'all',
  service: '',
  reference: '',
  referenceField: 'document',
  fromDate: '',
  toDate: '',
};
export const QUOTE_HISTORY_PAGE_SIZE = 15;

export async function getCommercialQuoteDirectory(organizationId: string): Promise<{
  clients: CommercialClientOption[];
  sites: CommercialSiteOption[];
}> {
  const [clients, sites] = await Promise.all([
    historyReader.from<CommercialClientOption>('commercial_clients')
      .select('id,business_name')
      .eq('organization_id', organizationId)
      .order('business_name', { ascending: true }),
    historyReader.from<CommercialSiteOption>('commercial_client_sites')
      .select('id,commercial_client_id,site_name')
      .eq('organization_id', organizationId)
      .order('site_name', { ascending: true }),
  ]);
  if (clients.error) throw new Error(clients.error.message);
  if (sites.error) throw new Error(sites.error.message);
  return { clients: clients.data ?? [], sites: sites.data ?? [] };
}

/** Never interpolate filter text into PostgREST .or() expressions. Every
 * filter is an individually bound Supabase filter with the tenant scoped
 * first, so the owner RLS is applied on top of the explicit organization id.
 */
export async function getCommercialQuoteHistory(
  organizationId: string,
  filters: QuoteHistoryFilters,
  page: number,
): Promise<{ rows: CommercialQuoteHistory[]; count: number }> {
  let query = historyReader.from<CommercialQuoteHistory>('commercial_quote_history')
    .select(
      'id,organization_id,commercial_client_id,commercial_site_id,source_client_name,source_site_name,reference_document,reference_filename,reference_review,proposal_date,service_title,currency_code,amount_net,amount_gross,price_review,commercial_status,client_match_status',
      { count: 'exact' },
    )
    .eq('organization_id', organizationId);

  if (filters.clientId === 'pending') query = query.is('commercial_client_id', null);
  else if (filters.clientId !== 'all') query = query.eq('commercial_client_id', filters.clientId);

  if (filters.siteId !== 'all') query = query.eq('commercial_site_id', filters.siteId);
  if (filters.service.trim()) query = query.ilike('service_title', '%' + filters.service.trim().slice(0, 120) + '%');
  if (filters.reference.trim()) {
    // The printed code and filename code can differ. Search the one the
    // user explicitly selected; do not conflate or silently fix them.
    query = query.ilike(filters.referenceField === 'filename' ? 'reference_filename' : 'reference_document',
      '%' + filters.reference.trim().slice(0, 80) + '%');
  }
  if (filters.fromDate) query = query.gte('proposal_date', filters.fromDate);
  if (filters.toDate) query = query.lte('proposal_date', filters.toDate);

  const start = Math.max(0, page) * QUOTE_HISTORY_PAGE_SIZE;
  const { data, error, count } = await query
    .order('proposal_date', { ascending: false })
    .order('id', { ascending: false })
    .range(start, start + QUOTE_HISTORY_PAGE_SIZE - 1);
  if (error) throw new Error(error.message);
  return { rows: data ?? [], count: count ?? 0 };
}

/** Details are fetched only on demand, after the user opens a quote already
 * visible through the history table's RLS policy. File IDs never occur in
 * the paginated listing payload.
 */
export async function getCommercialQuoteDocuments(
  organizationId: string,
  historyId: string,
): Promise<CommercialQuoteDocument[]> {
  const { data, error } = await historyReader.from<CommercialQuoteDocument>('commercial_quote_history_documents')
    .select('id,source_provider,source_file_id,source_filename,mime_type,document_role')
    .eq('organization_id', organizationId)
    .eq('history_id', historyId)
    .order('created_at', { ascending: true });
  if (error) throw new Error(error.message);
  return data ?? [];
}

/** Only construct the normal Drive document URL for a valid provider/id.
 * Google Drive independently checks the viewer's own Google permissions.
 * No API keys, download tokens, or public document links are generated.
 */
export function getAuthorizedDriveDocumentUrl(document: CommercialQuoteDocument): string | null {
  if (document.source_provider !== 'google_drive') return null;
  if (!/^[a-zA-Z0-9_-]{12,200}$/.test(document.source_file_id)) return null;
  return 'https://drive.google.com/file/d/' + encodeURIComponent(document.source_file_id) + '/view';
}
