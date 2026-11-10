import { useState, useEffect, useMemo, useRef } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { OrderForm } from './OrderForm';
import { QuoteListDialog } from './QuoteListDialog';
import { Request } from '@/types/request';
import { Plus, FileText } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { seedDatabase } from '@/lib/seedData';
import { supabase } from '@/integrations/supabase/client';
import { persistRequest } from '@/lib/requestPersistence';
import {
  annulDelegatedRequest,
  fetchDelegatedRequest,
  fetchDelegatedRequests,
  loadDelegatedRequestForEdit,
  loadDirectRequestForEdit,
  mapRequestRow,
} from '@/lib/requestData';
import { fetchDelegatedQuoteCounts } from '@/lib/quoteData';
import { createDelegatedInternalWorkOrder } from '@/lib/delegatedWorkOrders';
import { navigateToEntity } from '@/lib/entityNavigation';
import { useAssets } from '@/hooks/useAssets';
import { NO_ASSET_ACCESS_SCOPE } from '@/hooks/useAssetScope';
import { useDirectRequestScope, type RequestScope } from '@/hooks/useRequestScope';
import { buildAssetPathMap } from '@/lib/assetTree';
import { RequestAssetSummary, StaticRequestAssetSummary } from './RequestAssetSummary';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { format } from 'date-fns';
import { es } from 'date-fns/locale';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Separator } from '@/components/ui/separator';
import { OrderFilters } from './OrderFilters';
import {
  OrderTable,
  ColumnKey,
  SortKey,
  COLUMN_LABELS,
  DEFAULT_COLUMN_ORDER,
} from './OrderTable';
import {
  ServiceTypeBadge,
  RequestTypeBadge,
  getServiceTypeText,
  getStatusText,
  getServiceTypeColor,
} from './StatusBadge';

interface RequestListProps {
  /** Deep-link target from a notification (#requests?request=...&quote=...)
   * — Dashboard parses the hash and passes these down; this component never
   * reads window.location.hash itself. Sent, quoted and completed requests
   * are available; drafts and cancelled requests remain outside this list. */
  focusRequestId?: string;
  focusQuoteId?: string;
  /** Direct (default, historic) or delegated (Facility Manager, 9C.4). In
   * delegated mode work orders and the forum are never queried; quotes go
   * through the minimized delegated RPCs (9C.5) and `focusQuoteId` only
   * applies with quotes.view. */
  scope?: RequestScope;
}

export const RequestList = ({ focusRequestId, focusQuoteId, scope }: RequestListProps = {}) => {
  const { user, currentOrganization } = useAuth();
  const { toast } = useToast();
  const directScope = useDirectRequestScope();
  const requestScope = scope ?? directScope;
  const isDelegated = requestScope.mode === 'facility_manager';
  // Target organization: the active one (direct) or the operated client.
  const organizationId = requestScope.organizationId;
  // requests.* does not imply assets.view: in delegated mode useAssets()
  // queries nothing and the table falls back to the request's asset text.
  const { assets: linkedAssets, assetTree } = useAssets(isDelegated ? NO_ASSET_ACCESS_SCOPE : undefined);
  const assetsById = useMemo(() => new Map(linkedAssets.map((asset) => [asset.id, asset])), [linkedAssets]);
  const assetPaths = useMemo(() => buildAssetPathMap(assetTree), [assetTree]);
  const [showForm, setShowForm] = useState(false);
  const [requests, setRequests] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [showQuotesDialog, setShowQuotesDialog] = useState(false);
  const [showViewDialog, setShowViewDialog] = useState(false);
  const [selectedRequest, setSelectedRequest] = useState<Request | null>(null);
  const [editingRequest, setEditingRequest] = useState<Request | null>(null);
  const [requestDetails, setRequestDetails] = useState<any[]>([]);
  const [editingKnownProviders, setEditingKnownProviders] = useState<{ organizationId: string; organizationName: string }[]>([]);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [requestToDelete, setRequestToDelete] = useState<string | null>(null);

  // Preview inline
  const [expandedRequestId, setExpandedRequestId] = useState<string | null>(null);
  const [expandedDetails, setExpandedDetails] = useState<any[]>([]);

  // Conteo de cotizaciones por solicitud
  const [quoteCounts, setQuoteCounts] = useState<Record<string, number>>({});

  // OTs internas ya generadas, por request_id (solicitudes internas no usan cotizaciones)
  const [internalWorkOrders, setInternalWorkOrders] = useState<Record<string, { id: string }>>({});
  const [generatingRequestId, setGeneratingRequestId] = useState<string | null>(null);
  const [pendingDelegatedRequest, setPendingDelegatedRequest] = useState<Request | null>(null);

  // Filtros
  const [filterStore, setFilterStore] = useState<string>('all');
  const [filterBranch, setFilterBranch] = useState<string>('all');
  const [filterDate, setFilterDate] = useState<string>('');
  const [filterServiceType, setFilterServiceType] = useState<string>('all');
  const [filterStatus, setFilterStatus] = useState<string>('all');

  // Ordenamiento
  const [sortKey, setSortKey] = useState<SortKey | null>(null);
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');

  // Columnas
  const [visibleColumns, setVisibleColumns] = useState<Record<ColumnKey, boolean>>(() => {
    const defaults: Record<ColumnKey, boolean> = {
      requestNumber: true, title: true, serviceType: true, status: true, type: true, branch: true, asset: true,
      createdAt: true, store: true, createdBy: true, deadline: true, quotesProgress: true, actions: true,
    };
    const saved = localStorage.getItem('requestListVisibleColumns');
    if (saved) {
      try { return { ...defaults, ...JSON.parse(saved) }; } catch { /* noop */ }
    }
    return defaults;
  });

  const [columnOrder, setColumnOrder] = useState<ColumnKey[]>(() => {
    const saved = localStorage.getItem('requestListColumnOrder');
    if (saved) {
      try {
        const parsed = JSON.parse(saved) as ColumnKey[];
        const missing = DEFAULT_COLUMN_ORDER.filter((k) => !parsed.includes(k));
        return [...parsed, ...missing];
      } catch { /* noop */ }
    }
    return DEFAULT_COLUMN_ORDER;
  });

  const [draggedColumn, setDraggedColumn] = useState<ColumnKey | null>(null);
  const [dragOverColumn, setDragOverColumn] = useState<ColumnKey | null>(null);

  useEffect(() => {
    localStorage.setItem('requestListVisibleColumns', JSON.stringify(visibleColumns));
  }, [visibleColumns]);

  useEffect(() => {
    localStorage.setItem('requestListColumnOrder', JSON.stringify(columnOrder));
  }, [columnOrder]);

  const toggleColumn = (column: ColumnKey) => {
    setVisibleColumns((prev) => ({ ...prev, [column]: !prev[column] }));
  };

  const resetColumns = () => {
    setVisibleColumns({
      requestNumber: true, title: true, serviceType: true, status: true, type: true, branch: true, asset: true,
      createdAt: true, store: true, createdBy: true, deadline: true, quotesProgress: true, actions: true,
    });
    setColumnOrder(DEFAULT_COLUMN_ORDER);
  };

  const handleDragStart = (column: ColumnKey) => setDraggedColumn(column);
  const handleDragOver = (e: React.DragEvent, column: ColumnKey) => {
    e.preventDefault();
    if (draggedColumn && draggedColumn !== column) setDragOverColumn(column);
  };
  const handleDrop = (targetColumn: ColumnKey) => {
    if (!draggedColumn || draggedColumn === targetColumn) {
      setDraggedColumn(null);
      setDragOverColumn(null);
      return;
    }
    const newOrder = [...columnOrder];
    const draggedIndex = newOrder.indexOf(draggedColumn);
    const targetIndex = newOrder.indexOf(targetColumn);
    newOrder.splice(draggedIndex, 1);
    newOrder.splice(targetIndex, 0, draggedColumn);
    setColumnOrder(newOrder);
    setDraggedColumn(null);
    setDragOverColumn(null);
  };
  const handleDragEnd = () => {
    setDraggedColumn(null);
    setDragOverColumn(null);
  };

  const loadRequests = async () => {
    if (!organizationId) {
      setRequests([]);
      setQuoteCounts({});
      setInternalWorkOrders({});
      setLoading(false);
      return;
    }

    if (isDelegated) {
      // Minimized payload from the delegated RPC. No raw quotes, no work
      // orders, no seed.
      try {
        setLoading(true);
        setInternalWorkOrders({});
        setRequests(await fetchDelegatedRequests(organizationId, 'history'));
        // Quotes are delegated since 9C.5 (quotes.view): only the number of
        // received quotes per request, never an amount. Work orders and
        // the forum are still never queried.
        if (requestScope.canViewQuotes) {
          try {
            setQuoteCounts(await fetchDelegatedQuoteCounts(organizationId));
          } catch (quoteError) {
            console.error('Error loading delegated quote counts:', quoteError);
            setQuoteCounts({});
          }
        } else {
          setQuoteCounts({});
        }
      } catch (error) {
        console.error('Error loading delegated requests:', error);
        setRequests([]);
      } finally {
        setLoading(false);
      }
      return;
    }

    try {
      setLoading(true);
      await seedDatabase();
      const { data: requestsData, error: requestsError } = await supabase
        .from('requests')
        .select('*')
        .eq('organization_id', organizationId)
        .in('status', ['sent', 'quoted', 'completed'])
        .order('created_at', { ascending: false });
      if (requestsError) throw requestsError;

      const transformedRequests: Request[] = (requestsData || []).map(mapRequestRow);

      setRequests(transformedRequests);

      const externalRequestIds = transformedRequests.filter((r) => r.requestType !== 'internal').map((r) => r.id);
      if (externalRequestIds.length > 0) {
        const { data: quotesData } = await supabase
          .from('quotes')
          .select('request_id')
          .in('request_id', externalRequestIds)
          .in('status', ['submitted', 'approved', 'rejected']);

        const counts: Record<string, number> = {};
        (quotesData || []).forEach((q: any) => {
          counts[q.request_id] = (counts[q.request_id] || 0) + 1;
        });
        setQuoteCounts(counts);
      } else {
        setQuoteCounts({});
      }

      const internalRequestIds = transformedRequests.filter((r) => r.requestType === 'internal').map((r) => r.id);
      if (internalRequestIds.length > 0) {
        // Internal work orders only (quote_id is null) — external work orders
        // for the same organization are irrelevant to this "Generar OT" flag.
        const { data: workOrdersData } = await supabase
          .from('work_orders')
          .select('id, request_id')
          .in('request_id', internalRequestIds)
          .is('quote_id', null);

        const workOrderByRequest: Record<string, { id: string }> = {};
        (workOrdersData || []).forEach((wo: any) => { workOrderByRequest[wo.request_id] = { id: wo.id }; });
        setInternalWorkOrders(workOrderByRequest);
      } else {
        setInternalWorkOrders({});
      }
    } catch (error) {
      console.error('Error loading requests:', error);
      setRequests([]);
    } finally {
      setLoading(false);
    }
  };

  const handleGenerateWorkOrder = async (request: Request) => {
    setGeneratingRequestId(request.id);
    try {
      if (isDelegated) {
        if (!organizationId || !requestScope.canCreateDelegatedInternalWorkOrder || request.requestType !== 'internal'
          || !['sent', 'quoted', 'completed'].includes(request.status)) {
          throw new Error('Esta solicitud no permite crear una orden delegada.');
        }
        // The D3 RPC rechecks FM assignment, grants and origin; it also
        // returns the existing OT on repeated/concurrent calls.
        const order = await createDelegatedInternalWorkOrder(organizationId, request.id);
        setInternalWorkOrders((current) => ({ ...current, [request.id]: { id: order.id } }));
        toast({ title: 'Orden disponible', description: `OT ${order.workOrderNumber}. Puedes abrirla desde la solicitud.` });
      } else {
        const { data, error } = await supabase.rpc('create_internal_work_order_from_request', {
          target_request_id: request.id,
          target_assigned_member_id: request.internalResponsibleMemberId || null,
        });
        if (error) throw error;
        if (data) setInternalWorkOrders((current) => ({ ...current, [request.id]: { id: data.id } }));
        toast({ title: 'Orden de trabajo generada', description: `Se generó la OT para "${request.title || request.requestNumber}".` });
      }
    } catch (error) {
      console.error('Error generating internal work order:', error);
      toast({
        title: 'No se pudo generar la orden de trabajo',
        description: error instanceof Error ? error.message : 'Intenta nuevamente.',
        variant: 'destructive',
      });
    } finally {
      setGeneratingRequestId(null);
    }
  };

  useEffect(() => { loadRequests(); }, [user, organizationId, isDelegated]);

  // Detail rows (without attachments in delegated mode).
  const fetchDetailRows = async (requestId: string) => {
    if (isDelegated) {
      if (!organizationId) return [];
      return (await fetchDelegatedRequest(organizationId, requestId))?.detailRows ?? [];
    }
    const { data } = await supabase
      .from('request_details')
      .select('*')
      .eq('request_id', requestId);
    return data || [];
  };

  const loadRequestDetails = async (requestId: string) => {
    setRequestDetails(await fetchDetailRows(requestId));
  };

  const togglePreview = async (requestId: string) => {
    if (expandedRequestId === requestId) {
      setExpandedRequestId(null);
      setExpandedDetails([]);
    } else {
      setExpandedDetails(await fetchDetailRows(requestId));
      setExpandedRequestId(requestId);
    }
  };

  const handleViewRequest = async (request: Request) => {
    setSelectedRequest(request);
    await loadRequestDetails(request.id);
    setShowViewDialog(true);
  };

  // Guards against reprocessing the same focusRequestId on every render —
  // only acts again if the deep link target itself changes.
  const processedFocusIdRef = useRef<string | null>(null);
  useEffect(() => {
    if (!focusRequestId || loading) return;
    if (processedFocusIdRef.current === focusRequestId) return;
    processedFocusIdRef.current = focusRequestId;

    const found = requests.find((request) => request.id === focusRequestId);
    if (!found) {
      toast({
        title: 'No se pudo abrir la solicitud',
        description: 'Puede haber sido eliminada o ya no tienes acceso.',
        variant: 'destructive',
      });
      return;
    }

    // Delegated mode opens quotes only with quotes.view (canViewQuotes).
    if (focusQuoteId && requestScope.canViewQuotes) {
      setSelectedRequest(found);
      setShowQuotesDialog(true);
    } else {
      void handleViewRequest(found);
    }
  }, [focusRequestId, focusQuoteId, loading, requests]);

  const handleEditRequest = async (request: Request) => {
    if (isDelegated) {
      if (!organizationId) return;
      try {
        const { request: editable, knownProviders } = await loadDelegatedRequestForEdit(organizationId, request.id);
        setEditingKnownProviders(knownProviders);
        setEditingRequest(editable);
        setShowForm(true);
      } catch (error) {
        toast({ title: 'No se pudo abrir la solicitud', description: error instanceof Error ? error.message : undefined, variant: 'destructive' });
      }
      return;
    }
    setEditingRequest(await loadDirectRequestForEdit(request));
    setShowForm(true);
  };

  const handleSaveRequest = async (request: Request, isDraft: boolean) => {
    if (!organizationId) {
      toast({ title: 'Organización requerida', description: 'Selecciona una organización activa antes de guardar.', variant: 'destructive' });
      return;
    }

    try {
      // Toda la persistencia (incluida la garantía de atomicidad
      // draft -> audiencia -> 'sent') vive en src/lib/requestPersistence.ts,
      // compartida con la conversión de avisos del backlog para que exista
      // una sola implementación de este flujo.
      await persistRequest({
        request,
        isDraft,
        organizationId,
        actor: { id: user?.id, email: user?.email, name: user?.name },
        mode: isDelegated ? 'delegated' : 'direct',
      });

      toast({
        title: isDraft ? 'Borrador guardado' : 'Solicitud actualizada',
        description: isDraft
          ? 'Tu solicitud ha sido guardada como borrador'
          : 'Los cambios han sido guardados correctamente',
      });

      setShowForm(false);
      setEditingRequest(null);
      loadRequests();
    } catch (error) {
      console.error('Error saving request:', error);
      toast({
        title: 'Error',
        description: error instanceof Error && error.message ? error.message : 'No se pudo guardar la solicitud',
        variant: 'destructive',
      });
    }
  };

  const confirmDeleteRequest = (id: string) => {
    setRequestToDelete(id);
    setDeleteDialogOpen(true);
  };

  const handleDeleteRequest = async () => {
    if (!requestToDelete) return;
    try {
      if (isDelegated) {
        await annulDelegatedRequest(organizationId!, requestToDelete);
      } else {
        const { error } = await supabase
          .from('requests')
          .update({ status: 'anulado' })
          .eq('id', requestToDelete)
          .eq('organization_id', organizationId!);
        if (error) throw error;
      }
      toast({ title: 'Solicitud anulada', description: 'La solicitud ha sido anulada correctamente' });
      loadRequests();
    } catch (error) {
      console.error('Error anulando solicitud:', error);
      toast({ title: 'Error', description: 'No se pudo anular la solicitud', variant: 'destructive' });
    } finally {
      setDeleteDialogOpen(false);
      setRequestToDelete(null);
    }
  };

  const uniqueStores = useMemo(() => {
    const stores = requests.map((r) => r.store).filter(Boolean) as string[];
    return [...new Set(stores)];
  }, [requests]);

  const uniqueBranches = useMemo(() => {
    const branches = requests.map((r) => r.branch || r.clientBranch).filter(Boolean) as string[];
    return [...new Set(branches)];
  }, [requests]);

  const handleSort = (key: SortKey) => {
    if (sortKey === key) setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    else {
      setSortKey(key);
      setSortOrder('asc');
    }
  };

  const filteredRequests = useMemo(() => {
    let result = requests.filter((request) => {
      if (filterStore !== 'all' && request.store !== filterStore) return false;
      const requestBranch = request.branch || request.clientBranch;
      if (filterBranch !== 'all' && requestBranch !== filterBranch) return false;
      if (filterDate) {
        const requestDate = request.createdAt
          ? format(new Date(request.createdAt), 'yyyy-MM-dd')
          : '';
        if (requestDate !== filterDate) return false;
      }
      if (filterServiceType !== 'all' && request.serviceType !== filterServiceType) return false;
      if (filterStatus !== 'all' && request.status !== filterStatus) return false;
      return true;
    });

    if (sortKey) {
      result = [...result].sort((a, b) => {
        let aVal: string | number = '';
        let bVal: string | number = '';
        switch (sortKey) {
          case 'requestNumber': aVal = a.requestNumber || ''; bVal = b.requestNumber || ''; break;
          case 'serviceType': aVal = getServiceTypeText(a.serviceType); bVal = getServiceTypeText(b.serviceType); break;
          case 'status': aVal = getStatusText(a.status); bVal = getStatusText(b.status); break;
          case 'branch': aVal = a.branch || a.clientBranch || ''; bVal = b.branch || b.clientBranch || ''; break;
          case 'createdAt': aVal = a.createdAt || ''; bVal = b.createdAt || ''; break;
          case 'store': aVal = a.store || ''; bVal = b.store || ''; break;
          case 'createdBy': aVal = a.createdBy || ''; bVal = b.createdBy || ''; break;
          case 'deadline': aVal = a.deadline || ''; bVal = b.deadline || ''; break;
          case 'quotesProgress': aVal = quoteCounts[a.id] || 0; bVal = quoteCounts[b.id] || 0; break;
        }
        if (aVal < bVal) return sortOrder === 'asc' ? -1 : 1;
        if (aVal > bVal) return sortOrder === 'asc' ? 1 : -1;
        return 0;
      });
    }
    return result;
  }, [requests, filterStore, filterBranch, filterDate, filterServiceType, filterStatus, sortKey, sortOrder, quoteCounts]);

  const clearFilters = () => {
    setFilterStore('all');
    setFilterBranch('all');
    setFilterDate('');
    setFilterServiceType('all');
    setFilterStatus('all');
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold">{isDelegated ? `Solicitudes de ${requestScope.organizationName ?? 'cliente'}` : 'Mis Solicitudes'}</h2>
        {requestScope.canCreate && (
          <Button disabled={!organizationId} onClick={() => { setEditingRequest(null); setEditingKnownProviders([]); setShowForm(true); }}>
            <Plus className="w-4 h-4 mr-2" />
            Nueva solicitud
          </Button>
        )}
      </div>

      <OrderFilters
        filterStore={filterStore}
        filterBranch={filterBranch}
        filterDate={filterDate}
        filterServiceType={filterServiceType}
        filterStatus={filterStatus}
        uniqueStores={uniqueStores}
        uniqueBranches={uniqueBranches}
        onFilterStoreChange={setFilterStore}
        onFilterBranchChange={setFilterBranch}
        onFilterDateChange={setFilterDate}
        onFilterServiceTypeChange={setFilterServiceType}
        onFilterStatusChange={setFilterStatus}
        onClearFilters={clearFilters}
        columnLabels={COLUMN_LABELS}
        visibleColumns={visibleColumns}
        onToggleColumn={toggleColumn}
        onResetColumns={resetColumns}
      />

      {loading ? (
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">Cargando solicitudes...</p>
          </CardContent>
        </Card>
      ) : filteredRequests.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <FileText className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <p className="text-muted-foreground">
              {!organizationId
                ? 'Selecciona una organización activa para ver y crear solicitudes'
                : requests.length === 0
                ? (isDelegated ? 'El cliente no tiene solicitudes disponibles' : 'No tienes solicitudes disponibles')
                : 'No hay solicitudes que coincidan con los filtros'}
            </p>
            {organizationId && requests.length === 0 && requestScope.canCreate && (
              <Button onClick={() => { setEditingRequest(null); setShowForm(true); }} className="mt-4">
                Crear primera solicitud
              </Button>
            )}
          </CardContent>
        </Card>
      ) : (
        <OrderTable
          requests={filteredRequests}
          quoteCounts={quoteCounts}
          assetsById={assetsById}
          assetPaths={assetPaths}
          internalWorkOrders={internalWorkOrders}
          generatingRequestId={generatingRequestId}
          onGenerateWorkOrder={requestScope.canGenerateWorkOrder ? (r) => {
            if (isDelegated) setPendingDelegatedRequest(r);
            else void handleGenerateWorkOrder(r);
          } : undefined}
          onOpenWorkOrder={isDelegated && organizationId ? (workOrderId) => {
            navigateToEntity({ view: 'managed-work-orders', managedClientId: organizationId, workOrderId });
          } : undefined}
          canEdit={isDelegated ? (r) => r.status === 'sent' && !!r.delegatedAccess?.canEdit : (r) => r.status === 'sent'}
          canDelete={isDelegated ? (r) => r.status === 'sent' && !!r.delegatedAccess?.canAnnul : (r) => r.status === 'sent'}
          expandedRequestId={expandedRequestId}
          expandedDetails={expandedDetails}
          columnOrder={columnOrder}
          visibleColumns={visibleColumns}
          sortKey={sortKey}
          sortOrder={sortOrder}
          draggedColumn={draggedColumn}
          dragOverColumn={dragOverColumn}
          onSort={handleSort}
          onTogglePreview={togglePreview}
          onView={handleViewRequest}
          onEdit={handleEditRequest}
          onOpenChat={isDelegated ? undefined : () => toast({
            title: 'Chat pendiente de migracion tenant-aware',
            description: 'El foro de mensajes no esta disponible todavia.',
          })}
          onOpenQuotes={requestScope.canViewQuotes ? (r) => { setSelectedRequest(r); setShowQuotesDialog(true); } : undefined}
          onDelete={confirmDeleteRequest}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDrop={handleDrop}
          onDragEnd={handleDragEnd}
        />
      )}

      {showForm && (
        <OrderForm
          onClose={() => { setShowForm(false); setEditingRequest(null); }}
          onSave={handleSaveRequest}
          editingRequest={editingRequest || undefined}
          scope={requestScope}
          knownProviders={editingKnownProviders}
        />
      )}

      {requestScope.canViewQuotes && showQuotesDialog && selectedRequest && (
        <QuoteListDialog
          open={showQuotesDialog}
          onClose={() => { setShowQuotesDialog(false); setSelectedRequest(null); }}
          request={selectedRequest}
          focusQuoteId={selectedRequest.id === focusRequestId ? focusQuoteId : undefined}
          delegated={isDelegated && organizationId ? {
            clientOrganizationId: organizationId,
            canCreateWorkOrder: requestScope.canCreateDelegatedExternalWorkOrder,
            onOpenWorkOrder: (workOrderId: string) => navigateToEntity({
              view: 'managed-work-orders', managedClientId: organizationId, workOrderId,
            }),
          } : undefined}
        />
      )}

      <Dialog open={showViewDialog} onOpenChange={setShowViewDialog}>
        <DialogContent className="max-w-3xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="text-2xl">
              {selectedRequest?.title || 'Solicitud sin título'}
            </DialogTitle>
            {selectedRequest && (
              <DialogDescription className="text-sm text-muted-foreground mt-1">
                {selectedRequest.requestNumber}
              </DialogDescription>
            )}
          </DialogHeader>

          {selectedRequest && (
            <div className="space-y-6">
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-primary">Datos de Cabecera</h3>
                <div className="grid grid-cols-2 md:grid-cols-3 gap-4 text-sm">
                  <div>
                    <span className="text-muted-foreground">Nro. Solicitud:</span>
                    <p className="font-medium">{selectedRequest.requestNumber}</p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Tipo de Servicio:</span>
                    <p><ServiceTypeBadge type={selectedRequest.serviceType} /></p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Tipo de Gestión:</span>
                    <p><RequestTypeBadge type={selectedRequest.requestType} /></p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Creador:</span>
                    <p className="font-medium">
                      {selectedRequest.createdByName || selectedRequest.createdBy}
                    </p>
                    {!isDelegated && selectedRequest.createdByEmail && selectedRequest.createdByName && (
                      <p className="text-xs text-muted-foreground">{selectedRequest.createdByEmail}</p>
                    )}
                  </div>
                  <div>
                    <span className="text-muted-foreground">Ciudad:</span>
                    <p className="font-medium">{selectedRequest.city || '-'}</p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Sucursal:</span>
                    <p className="font-medium">{selectedRequest.clientName || selectedRequest.store || '-'}</p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Sede:</span>
                    <p className="font-medium">{selectedRequest.branch || '-'}</p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Fecha de Registro:</span>
                    <p className="font-medium">
                      {selectedRequest.createdAt
                        ? format(new Date(selectedRequest.createdAt), 'dd/MM/yyyy HH:mm', { locale: es })
                        : '-'}
                    </p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Fecha Entrega Cotizaciones:</span>
                    <p className="font-medium">
                      {selectedRequest.deadline
                        ? format(new Date(selectedRequest.deadline), 'dd/MM/yyyy', { locale: es })
                        : '-'}
                    </p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Requiere Visita:</span>
                    <p className="font-medium">{selectedRequest.requiresVisit ? 'Sí' : 'No'}</p>
                  </div>
                  {selectedRequest.requiresVisit && selectedRequest.visitDate && (
                    <div>
                      <span className="text-muted-foreground">Fecha Visita Técnica:</span>
                      <p className="font-medium">
                        {format(new Date(selectedRequest.visitDate), 'dd/MM/yyyy', { locale: es })}
                      </p>
                    </div>
                  )}
                </div>
              </div>

              {isDelegated && selectedRequest.delegatedAccess?.hasClientAttachments && (
                <p className="rounded-md border border-dashed bg-muted/40 p-3 text-sm text-muted-foreground" data-testid="request-protected-attachments">
                  Esta solicitud contiene adjuntos protegidos y no puede editarse desde la gestión delegada todavía.
                </p>
              )}

              {isDelegated
                ? <StaticRequestAssetSummary assetId={selectedRequest.assetId} assetText={selectedRequest.asset} />
                : <RequestAssetSummary assetId={selectedRequest.assetId} assetText={selectedRequest.asset} />}

              <div className="space-y-4">
                <div>
                  <span className="text-muted-foreground text-sm">Descripción:</span>
                  <p className="font-medium">{selectedRequest.description}</p>
                </div>
              </div>

              <Separator />

              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-primary">
                  Detalle de la Solicitud ({requestDetails.length} {requestDetails.length === 1 ? 'fila' : 'filas'})
                </h3>
                {requestDetails.length === 0 ? (
                  <p className="text-muted-foreground text-sm">No hay detalles registrados</p>
                ) : (
                  <div className="border rounded-md overflow-hidden">
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead className="min-w-[50px]">#</TableHead>
                            <TableHead className="min-w-[220px]">Actividad / Partida</TableHead>
                            <TableHead className="min-w-[180px]">Materiales</TableHead>
                            <TableHead className="min-w-[80px]">Cantidad</TableHead>
                            <TableHead className="min-w-[80px]">U.M</TableHead>
                            <TableHead className="min-w-[150px]">Observación</TableHead>
                            <TableHead className="min-w-[130px]">Encargado</TableHead>
                            <TableHead className="min-w-[100px]">Delegado</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {requestDetails.map((detail: any, index: number) => (
                            <TableRow key={detail.id}>
                              <TableCell className="font-medium">{index + 1}</TableCell>
                              <TableCell>
                                {detail.activities || '-'}
                                {(detail.equipment || detail.area) && (
                                  <p className="mt-0.5 text-xs text-muted-foreground">
                                    {[detail.equipment, detail.area].filter(Boolean).join(' · ')}
                                  </p>
                                )}
                              </TableCell>
                              <TableCell>{detail.relevant_materials || '-'}</TableCell>
                              <TableCell>{detail.quantity || '-'}</TableCell>
                              <TableCell>{detail.unit_measure || '-'}</TableCell>
                              <TableCell>{detail.observation || '-'}</TableCell>
                              <TableCell>{detail.responsible_user || '-'}</TableCell>
                              <TableCell>{detail.delegate_type || '-'}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <AlertDialog open={!!pendingDelegatedRequest} onOpenChange={(open) => {
        if (!open) setPendingDelegatedRequest(null);
      }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>¿Generar orden de trabajo interna?</AlertDialogTitle>
            <AlertDialogDescription>
              Solicitud {pendingDelegatedRequest?.requestNumber ?? ''} de {requestScope.organizationName ?? 'este cliente'}.
              La orden quedará pendiente y sin técnico ni planificador asignado.
              Si ya existe una OT para esta solicitud, se recuperará sin crear otra.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction disabled={!!generatingRequestId} onClick={() => {
              if (pendingDelegatedRequest) void handleGenerateWorkOrder(pendingDelegatedRequest);
              setPendingDelegatedRequest(null);
            }}>
              Generar o abrir OT
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>¿Anular solicitud?</AlertDialogTitle>
            <AlertDialogDescription>
              La solicitud será marcada como anulada y ya no aparecerá en el listado activo.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteRequest} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
              Anular
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
};
