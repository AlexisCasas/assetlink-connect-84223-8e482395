import { useEffect, useMemo, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { AlertCircle, ExternalLink, FileSearch, FileText, Loader2, Search, X } from 'lucide-react';
import {
  EMPTY_QUOTE_HISTORY_FILTERS, QUOTE_HISTORY_PAGE_SIZE,
  getCommercialQuoteDirectory, getCommercialQuoteDocuments, getCommercialQuoteHistory,
  getAuthorizedDriveDocumentUrl,
  type CommercialClientOption, type CommercialSiteOption,
  type CommercialQuoteHistory, type CommercialQuoteDocument, type QuoteHistoryFilters,
} from '@/lib/commercialQuoteHistory';

const formatDate = (date: string | null): string => {
  if (!date) return 'Fecha por confirmar';
  // Use local noon: YYYY-MM-DD is a calendar date, not a UTC midnight timestamp.
  const parsed = new Date(date + 'T12:00:00');
  if (Number.isNaN(parsed.getTime())) return date;
  return new Intl.DateTimeFormat('es-PE', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(parsed);
};

const formatVerifiedAmount = (row: CommercialQuoteHistory): string => {
  if (row.price_review !== 'verified') return 'Sin validar';
  const amount = row.amount_gross ?? row.amount_net;
  if (amount === null) return 'Sin validar';
  return new Intl.NumberFormat('es-PE', { style: 'currency', currency: row.currency_code || 'PEN' }).format(amount);
};

const getCommercialStatusLabel = (status: string): string => {
  switch (status) {
    case 'sent_verified': return 'Envío verificado';
    case 'accepted_verified': return 'Aceptada';
    case 'rejected_verified': return 'Rechazada';
    case 'cancelled_verified': return 'Anulada';
    default: return 'Sin confirmar';
  }
};

export function CommercialQuoteHistoryView() {
  const { currentOrganization, currentMembership } = useAuth();
  // This is a provider-owned commercial archive, not a delegated FM view
  // and never an organization selector supplied by a user/query string.
  const organizationId = currentOrganization?.organizationType === 'provider_company'
    && currentMembership?.isActive
    && currentMembership.organizationId === currentOrganization.id
    ? currentOrganization.id : null;

  const [clients, setClients] = useState<CommercialClientOption[]>([]);
  const [sites, setSites] = useState<CommercialSiteOption[]>([]);
  const [directoryError, setDirectoryError] = useState<string | null>(null);
  const [draft, setDraft] = useState<QuoteHistoryFilters>({ ...EMPTY_QUOTE_HISTORY_FILTERS });
  const [filters, setFilters] = useState<QuoteHistoryFilters>({ ...EMPTY_QUOTE_HISTORY_FILTERS });
  const [page, setPage] = useState(0);
  const [reloadCounter, setReloadCounter] = useState(0);
  const [rows, setRows] = useState<CommercialQuoteHistory[]>([]);
  const [total, setTotal] = useState(0);
  const [loadedOrganizationId, setLoadedOrganizationId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<CommercialQuoteHistory | null>(null);
  const [documents, setDocuments] = useState<CommercialQuoteDocument[]>([]);
  const [documentsLoading, setDocumentsLoading] = useState(false);
  const [documentsError, setDocumentsError] = useState<string | null>(null);

  const filteredSites = useMemo(() => (
    draft.clientId !== 'all' && draft.clientId !== 'pending'
      ? sites.filter((site) => site.commercial_client_id === draft.clientId)
      : sites
  ), [sites, draft.clientId]);

  const clientNames = useMemo(
    () => new Map(clients.map((client) => [client.id, client.business_name])),
    [clients],
  );
  const siteNames = useMemo(
    () => new Map(sites.map((site) => [site.id, site.site_name])),
    [sites],
  );

  useEffect(() => {
    let active = true;
    setClients([]);
    setSites([]);
    setDirectoryError(null);
    setDraft({ ...EMPTY_QUOTE_HISTORY_FILTERS });
    setFilters({ ...EMPTY_QUOTE_HISTORY_FILTERS });
    setSelected(null);
    setPage(0);
    if (!organizationId) return () => { active = false; };
    void getCommercialQuoteDirectory(organizationId)
      .then((directory) => {
        if (!active) return;
        setClients(directory.clients);
        setSites(directory.sites);
      })
      .catch(() => {
        if (active) setDirectoryError('No se pudo cargar el catálogo de clientes y sedes.');
      });
    return () => { active = false; };
  }, [organizationId]);

  useEffect(() => {
    let active = true;
    setRows([]);
    setLoadedOrganizationId(null);
    setLoading(true);
    setError(null);
    if (!organizationId) {
      setLoading(false);
      return () => { active = false; };
    }
    void getCommercialQuoteHistory(organizationId, filters, page)
      .then((result) => {
        if (!active) return;
        setRows(result.rows);
        setTotal(result.count);
        setLoadedOrganizationId(organizationId);
      })
      .catch(() => {
        if (!active) return;
        setError('No se pudo consultar el histórico. Revisa tu sesión o permisos e inténtalo nuevamente.');
        setTotal(0);
      })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [organizationId, filters, page, reloadCounter]);

  const visibleSelected = selected?.organization_id === organizationId ? selected : null;
  const selectedQuoteId = visibleSelected?.id ?? null;
  useEffect(() => {
    let active = true;
    setDocuments([]);
    setDocumentsError(null);
    setDocumentsLoading(false);
    if (!organizationId || !selectedQuoteId) return () => { active = false; };
    setDocumentsLoading(true);
    void getCommercialQuoteDocuments(organizationId, selectedQuoteId)
      .then((data) => { if (active) setDocuments(data); })
      .catch(() => {
        if (active) setDocumentsError('No se pudo consultar el documento de origen.');
      })
      .finally(() => { if (active) setDocumentsLoading(false); });
    return () => { active = false; };
  }, [organizationId, selectedQuoteId]);

  if (!organizationId) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center p-6">
        <p className="text-sm text-muted-foreground">
          El histórico comercial está disponible únicamente para miembros activos de una organización proveedora.
        </p>
      </div>
    );
  }

  const applyFilters = () => {
    if (draft.fromDate && draft.toDate && draft.fromDate > draft.toDate) {
      setError('La fecha de inicio debe ser anterior o igual a la fecha final.');
      return;
    }
    setError(null);
    setFilters({ ...draft });
    setPage(0);
    setSelected(null);
    setReloadCounter((value) => value + 1);
  };

  const clearFilters = () => {
    setDraft({ ...EMPTY_QUOTE_HISTORY_FILTERS });
    setFilters({ ...EMPTY_QUOTE_HISTORY_FILTERS });
    setPage(0);
    setSelected(null);
    setReloadCounter((value) => value + 1);
  };

  const pageCount = Math.max(1, Math.ceil(total / QUOTE_HISTORY_PAGE_SIZE));
  const visibleRows = loadedOrganizationId === organizationId ? rows : [];
  const start = total === 0 ? 0 : page * QUOTE_HISTORY_PAGE_SIZE + 1;
  const end = Math.min((page + 1) * QUOTE_HISTORY_PAGE_SIZE, total);

  return (
    <div className="space-y-6 p-4 md:p-6">
      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="text-2xl font-semibold tracking-tight">Histórico de cotizaciones</h1>
          <Badge variant="outline">Solo lectura</Badge>
        </div>
        <p className="text-sm text-muted-foreground">
          Consulta propuestas anteriores de {currentOrganization?.name}. Este archivo es independiente de las cotizaciones y solicitudes operativas.
        </p>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base">
            <Search className="h-4 w-4" />
            Buscar cotizaciones
          </CardTitle>
        </CardHeader>
        <CardContent>
          <form
            className="space-y-4"
            onSubmit={(event) => { event.preventDefault(); applyFilters(); }}
          >
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
              <div className="space-y-2">
                <Label htmlFor="history-client">Cliente comercial</Label>
                <Select
                  value={draft.clientId}
                  onValueChange={(value) => setDraft((current) => ({ ...current, clientId: value, siteId: 'all' }))}
                >
                  <SelectTrigger id="history-client"><SelectValue placeholder="Todos los clientes" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Todos los clientes</SelectItem>
                    <SelectItem value="pending">Cliente por confirmar</SelectItem>
                    {clients.map((client) => <SelectItem key={client.id} value={client.id}>{client.business_name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="history-site">Sede homologada</Label>
                <Select
                  value={draft.siteId}
                  onValueChange={(value) => setDraft((current) => ({ ...current, siteId: value }))}
                  disabled={draft.clientId === 'pending'}
                >
                  <SelectTrigger id="history-site"><SelectValue placeholder="Todas las sedes" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Todas las sedes</SelectItem>
                    {filteredSites.map((site) => (
                      <SelectItem key={site.id} value={site.id}>{site.site_name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="history-service">Servicio o trabajo</Label>
                <Input
                  id="history-service" value={draft.service} maxLength={120}
                  onChange={(event) => setDraft((current) => ({ ...current, service: event.target.value }))}
                  placeholder="Ej. pintura, racks, filtración"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="history-reference">Correlativo</Label>
                <Input
                  id="history-reference" value={draft.reference} maxLength={80}
                  onChange={(event) => setDraft((current) => ({ ...current, reference: event.target.value }))}
                  placeholder="Ej. RMX-2026-0212"
                />
                <Select
                  value={draft.referenceField}
                  onValueChange={(value: 'document' | 'filename') => setDraft((current) => ({ ...current, referenceField: value }))}
                >
                  <SelectTrigger aria-label="Tipo de correlativo"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="document">Número impreso en PDF</SelectItem>
                    <SelectItem value="filename">Número del nombre de archivo</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="history-from">Desde</Label>
                <Input
                  id="history-from" type="date" value={draft.fromDate}
                  onChange={(event) => setDraft((current) => ({ ...current, fromDate: event.target.value }))}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="history-to">Hasta</Label>
                <Input
                  id="history-to" type="date" value={draft.toDate}
                  onChange={(event) => setDraft((current) => ({ ...current, toDate: event.target.value }))}
                />
              </div>
            </div>
            {directoryError && <p className="text-sm text-destructive" role="alert">{directoryError}</p>}
            <div className="flex flex-wrap gap-2">
              <Button type="submit" disabled={loading}><Search className="mr-2 h-4 w-4" />Buscar</Button>
              <Button type="button" variant="outline" onClick={clearFilters} disabled={loading}>
                <X className="mr-2 h-4 w-4" />Limpiar filtros
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <CardTitle className="flex items-center gap-2 text-base">
              <FileText className="h-4 w-4" />
              Cotizaciones encontradas
            </CardTitle>
            <span className="text-sm text-muted-foreground">
              {loading ? 'Consultando…' : total + ' resultado(s)'}
            </span>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {error && (
            <div role="alert" className="flex items-start gap-2 rounded-md border border-destructive/30 p-3 text-sm text-destructive">
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />{error}
            </div>
          )}
          {loading ? (
            <div className="flex items-center justify-center gap-2 py-12 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />Cargando histórico…
            </div>
          ) : visibleRows.length === 0 && !error ? (
            <div className="space-y-2 py-12 text-center">
              <FileSearch className="mx-auto h-8 w-8 text-muted-foreground" />
              <p className="font-medium">No hay cotizaciones para los filtros seleccionados.</p>
              <p className="text-sm text-muted-foreground">Prueba con otra fecha, cliente, servicio o referencia.</p>
            </div>
          ) : visibleRows.length > 0 ? (
            <div className="overflow-x-auto rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Fecha</TableHead>
                    <TableHead>Correlativo</TableHead>
                    <TableHead>Cliente</TableHead>
                    <TableHead>Sede</TableHead>
                    <TableHead>Servicio</TableHead>
                    <TableHead>Importe</TableHead>
                    <TableHead>Estado</TableHead>
                    <TableHead className="text-right">Acción</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleRows.map((quote) => (
                    <TableRow key={quote.id}>
                      <TableCell className="whitespace-nowrap text-sm">{formatDate(quote.proposal_date)}</TableCell>
                      <TableCell className="min-w-[140px]">
                        <div className="font-medium">{quote.reference_document || quote.reference_filename || 'Sin referencia'}</div>
                        {quote.reference_review === 'mismatch' && (
                          <Badge variant="destructive" className="mt-1">Referencia distinta</Badge>
                        )}
                      </TableCell>
                      <TableCell className="min-w-[140px]">
                        <div>{quote.commercial_client_id
                          ? (clientNames.get(quote.commercial_client_id) || quote.source_client_name || 'Cliente')
                          : (quote.source_client_name || 'Por confirmar')}</div>
                        {quote.client_match_status !== 'matched' && (
                          <Badge variant="outline" className="mt-1">Sin homologar</Badge>
                        )}
                      </TableCell>
                      <TableCell className="min-w-[140px]">
                        {quote.commercial_site_id
                          ? (siteNames.get(quote.commercial_site_id) || quote.source_site_name || '—')
                          : (quote.source_site_name || '—')}
                      </TableCell>
                      <TableCell className="min-w-[220px] max-w-[380px]">
                        <p className="line-clamp-2 text-sm" title={quote.service_title}>{quote.service_title}</p>
                      </TableCell>
                      <TableCell className="whitespace-nowrap text-sm">
                        {formatVerifiedAmount(quote)}
                      </TableCell>
                      <TableCell>
                        <Badge variant="secondary" className="whitespace-nowrap">
                          {getCommercialStatusLabel(quote.commercial_status)}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <Button variant="outline" size="sm" onClick={() => setSelected(quote)}>
                          Ver detalle
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          ) : null}
          {!loading && !error && total > 0 && (
            <div className="flex flex-wrap items-center justify-between gap-2 text-sm text-muted-foreground">
              <span>Mostrando {start}–{end} de {total}</span>
              <div className="flex items-center gap-2">
                <Button size="sm" variant="outline" disabled={page === 0}
                  onClick={() => setPage((value) => Math.max(0, value - 1))}>Anterior</Button>
                <span>Página {page + 1} de {pageCount}</span>
                <Button size="sm" variant="outline" disabled={page + 1 >= pageCount}
                  onClick={() => setPage((value) => value + 1)}>Siguiente</Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={!!visibleSelected} onOpenChange={(open) => { if (!open) setSelected(null); }}>
        <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Detalle de cotización histórica</DialogTitle>
            <DialogDescription>
              Archivo de referencia de ROMAX. No acredita adjudicación ni constituye un precio actualizado.
            </DialogDescription>
          </DialogHeader>
          {visibleSelected && (
            <div className="space-y-5 text-sm">
              <dl className="grid gap-3 sm:grid-cols-2">
                <div><dt className="text-muted-foreground">Correlativo del PDF</dt><dd className="font-medium">{visibleSelected.reference_document || 'Sin referencia'}</dd></div>
                <div><dt className="text-muted-foreground">Correlativo del archivo</dt><dd>{visibleSelected.reference_filename || 'Sin referencia'}</dd></div>
                <div><dt className="text-muted-foreground">Fecha documental</dt><dd>{formatDate(visibleSelected.proposal_date)}</dd></div>
                <div><dt className="text-muted-foreground">Cliente</dt><dd>{visibleSelected.commercial_client_id
                  ? (clientNames.get(visibleSelected.commercial_client_id) || visibleSelected.source_client_name || '—')
                  : (visibleSelected.source_client_name || 'Por confirmar')}</dd></div>
                <div><dt className="text-muted-foreground">Sede</dt><dd>{visibleSelected.commercial_site_id
                  ? (siteNames.get(visibleSelected.commercial_site_id) || visibleSelected.source_site_name || '—')
                  : (visibleSelected.source_site_name || 'No especificada')}</dd></div>
                <div><dt className="text-muted-foreground">Estado</dt><dd>{getCommercialStatusLabel(visibleSelected.commercial_status)}</dd></div>
              </dl>
              <div>
                <p className="text-muted-foreground">Servicio propuesto</p>
                <p className="mt-1 font-medium">{visibleSelected.service_title}</p>
              </div>
              {visibleSelected.reference_review === 'mismatch' && (
                <div role="note" className="rounded-md border border-destructive/30 p-3 text-sm">
                  El correlativo del PDF no coincide con el nombre del archivo. Se conservaron ambos; no fueron unificados.
                </div>
              )}
              <div className="rounded-md border p-3">
                <p className="font-medium">Importe: {formatVerifiedAmount(visibleSelected)}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Los valores de 2026 se muestran solamente después de verificar neto, impuestos y total contra el documento original.
                </p>
              </div>
              <div className="space-y-2">
                <h3 className="font-medium">Documentos de origen</h3>
                {documentsLoading && <p className="text-muted-foreground">Cargando documentos…</p>}
                {documentsError && <p className="text-destructive" role="alert">{documentsError}</p>}
                {!documentsLoading && !documentsError && documents.length === 0 && (
                  <p className="text-muted-foreground">No hay documentos vinculados.</p>
                )}
                {!documentsLoading && documents.map((document) => {
                  const url = getAuthorizedDriveDocumentUrl(document);
                  return (
                    <div key={document.id} className="flex flex-wrap items-center justify-between gap-2 rounded-md border px-3 py-2">
                      <span className="min-w-0 flex-1 break-words">{document.source_filename}</span>
                      {url && (
                        <a href={url} target="_blank" rel="noopener noreferrer"
                          className="inline-flex items-center gap-1 text-primary underline-offset-4 hover:underline">
                          Abrir en Drive <ExternalLink className="h-3.5 w-3.5" />
                        </a>
                      )}
                    </div>
                  );
                })}
                <p className="text-xs text-muted-foreground">
                  Abrir un PDF requiere permiso independiente sobre el archivo en Google Drive.
                </p>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
