import { useState, useEffect, useMemo } from 'react';
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
  getServiceTypeText,
  getStatusText,
  getServiceTypeColor,
} from './StatusBadge';

export const RequestList = () => {
  const { user, currentOrganization } = useAuth();
  const { toast } = useToast();
  const [showForm, setShowForm] = useState(false);
  const [requests, setRequests] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [showQuotesDialog, setShowQuotesDialog] = useState(false);
  const [showViewDialog, setShowViewDialog] = useState(false);
  const [selectedRequest, setSelectedRequest] = useState<Request | null>(null);
  const [editingRequest, setEditingRequest] = useState<Request | null>(null);
  const [requestDetails, setRequestDetails] = useState<any[]>([]);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [requestToDelete, setRequestToDelete] = useState<string | null>(null);

  // Preview inline
  const [expandedRequestId, setExpandedRequestId] = useState<string | null>(null);
  const [expandedDetails, setExpandedDetails] = useState<any[]>([]);

  // Conteo de cotizaciones por solicitud
  const [quoteCounts, setQuoteCounts] = useState<Record<string, number>>({});

  // Filtros
  const [filterStore, setFilterStore] = useState<string>('all');
  const [filterBranch, setFilterBranch] = useState<string>('all');
  const [filterDate, setFilterDate] = useState<string>('');
  const [filterServiceType, setFilterServiceType] = useState<string>('all');

  // Ordenamiento
  const [sortKey, setSortKey] = useState<SortKey | null>(null);
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');

  // Columnas
  const [visibleColumns, setVisibleColumns] = useState<Record<ColumnKey, boolean>>(() => {
    const defaults: Record<ColumnKey, boolean> = {
      requestNumber: true, title: true, serviceType: true, status: true, branch: true,
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
      requestNumber: true, title: true, serviceType: true, status: true, branch: true,
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
    if (!currentOrganization) {
      setRequests([]);
      setQuoteCounts({});
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      await seedDatabase();
      const { data: requestsData, error: requestsError } = await supabase
        .from('requests')
        .select('*')
        .eq('organization_id', currentOrganization.id)
        .eq('status', 'sent')
        .order('created_at', { ascending: false });
      if (requestsError) throw requestsError;

      const transformedRequests: Request[] = (requestsData || []).map((req: any) => ({
        id: req.id,
        organizationId: req.organization_id,
        requestNumber: req.request_number,
        title: req.title,
        description: req.description,
        asset: req.asset,
        location: req.location,
        serviceType: req.service_type,
        observations: req.observations,
        images: req.image_urls || [],
        documents: req.document_urls || [],
        deadline: req.deadline,
        startTime: req.start_time,
        selectedProviders: [],
        status: req.status,
        createdAt: req.created_at,
        createdBy: req.created_by,
        createdByUserId: req.created_by_user_id,
        createdByName: req.created_by_name,
        createdByEmail: req.created_by_email,
        priority: req.priority,
        clientName: req.client_name,
        clientBranch: req.client_branch,
        isPublic: req.is_public,
        notifiedAt: req.notified_at,
        city: req.city,
        store: req.store,
        branch: req.branch,
        branchId: req.branch_id,
        requiresVisit: req.requires_visit,
        visitDate: req.visit_date,
        minQuotes: req.min_quotes ?? 3,
      }));

      setRequests(transformedRequests);

      if (transformedRequests.length > 0) {
        const requestIds = transformedRequests.map((r) => r.id);
        const { data: quotesData } = await supabase
          .from('quotes')
          .select('request_id')
          .in('request_id', requestIds)
          .eq('status', 'submitted');

        const counts: Record<string, number> = {};
        (quotesData || []).forEach((q: any) => {
          counts[q.request_id] = (counts[q.request_id] || 0) + 1;
        });
        setQuoteCounts(counts);
      }
    } catch (error) {
      console.error('Error loading requests:', error);
      setRequests([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { loadRequests(); }, [user, currentOrganization?.id]);

  const loadRequestDetails = async (requestId: string) => {
    const { data } = await supabase
      .from('request_details')
      .select('*')
      .eq('request_id', requestId);
    setRequestDetails(data || []);
  };

  const togglePreview = async (requestId: string) => {
    if (expandedRequestId === requestId) {
      setExpandedRequestId(null);
      setExpandedDetails([]);
    } else {
      const { data } = await supabase
        .from('request_details')
        .select('*')
        .eq('request_id', requestId);
      setExpandedDetails(data || []);
      setExpandedRequestId(requestId);
    }
  };

  const handleViewRequest = async (request: Request) => {
    setSelectedRequest(request);
    await loadRequestDetails(request.id);
    setShowViewDialog(true);
  };

  const handleEditRequest = async (request: Request) => {
    const { data: detailsData } = await supabase
      .from('request_details')
      .select('*')
      .eq('request_id', request.id);

    const details = (detailsData || []).map((d: any) => ({
      equipment: d.equipment || '',
      subEquipment: d.sub_equipment || '',
      area: d.area || '',
      subArea: d.sub_area || '',
      activities: d.activities || '',
      relevantMaterials: d.relevant_materials || '',
      quantity: d.quantity,
      unitMeasure: d.unit_measure || '',
      observation: d.observation || '',
      responsibleUser: d.responsible_user || '',
      delegateType: d.delegate_type || '',
    }));

    setEditingRequest({ ...request, details });
    setShowForm(true);
  };

  const handleSaveRequest = async (request: Request, isDraft: boolean) => {
    if (!currentOrganization) {
      toast({ title: 'Organización requerida', description: 'Selecciona una organización activa antes de guardar.', variant: 'destructive' });
      return;
    }

    if (request.organizationId && request.organizationId !== currentOrganization.id) {
      throw new Error('La solicitud no pertenece a la organización activa.');
    }

    try {
      const { data: existing } = await supabase
        .from('requests')
        .select('id')
        .eq('id', request.id)
        .eq('organization_id', currentOrganization.id)
        .maybeSingle();

      if (existing) {
        const { error: requestError } = await supabase
          .from('requests')
          .update({
            title: request.title || null,
            description: request.description,
            service_type: request.serviceType,
            deadline: request.deadline,
            branch_id: request.branchId || null,
            city: request.city,
            store: request.store,
            branch: request.branch,
            location: request.location,
            requires_visit: request.requiresVisit,
            visit_date: request.visitDate || null,
            asset: request.asset,
            status: isDraft ? 'draft' : 'sent',
            is_public: request.isPublic,
            min_quotes: request.minQuotes ?? 3,
          })
          .eq('id', request.id)
          .eq('organization_id', currentOrganization.id);
        if (requestError) throw requestError;

        await supabase.from('request_details').delete().eq('request_id', request.id);
      } else {
        const { error: insertError } = await supabase.from('requests').insert({
          id: request.id,
          organization_id: currentOrganization.id,
          request_number: request.requestNumber,
          title: request.title || null,
          description: request.description,
          service_type: request.serviceType,
          deadline: request.deadline,
          branch_id: request.branchId || null,
          city: request.city,
          store: request.store,
          branch: request.branch,
          location: request.location,
          requires_visit: request.requiresVisit,
          visit_date: request.visitDate || null,
          asset: request.asset,
          status: isDraft ? 'draft' : 'sent',
          created_by: user?.email || '',
          created_by_user_id: user?.id || null,
          created_by_name: user?.name || null,
          created_by_email: user?.email || null,
          is_public: request.isPublic,
          client_name: request.clientName,
          client_branch: request.clientBranch,
          priority: request.priority,
          min_quotes: request.minQuotes ?? 3,
        });
        if (insertError) throw insertError;
      }

      if (request.details && request.details.length > 0) {
        const detailsToInsert = request.details.map((d) => ({
          request_id: request.id,
          equipment: d.equipment || null,
          sub_equipment: d.subEquipment || null,
          area: d.area || null,
          sub_area: d.subArea || null,
          activities: d.activities || null,
          relevant_materials: d.relevantMaterials || null,
          quantity: d.quantity || null,
          unit_measure: d.unitMeasure || null,
          observation: d.observation || null,
          responsible_user: d.responsibleUser || null,
          delegate_type: d.delegateType || null,
        }));
        const { error: detailsError } = await supabase.from('request_details').insert(detailsToInsert);
        if (detailsError) throw detailsError;
      }

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
        description: 'No se pudo guardar la solicitud',
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
      const { error } = await supabase
        .from('requests')
        .update({ status: 'anulado' })
        .eq('id', requestToDelete)
        .eq('organization_id', currentOrganization.id);
      if (error) throw error;
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
  }, [requests, filterStore, filterBranch, filterDate, filterServiceType, sortKey, sortOrder, quoteCounts]);

  const clearFilters = () => {
    setFilterStore('all');
    setFilterBranch('all');
    setFilterDate('');
    setFilterServiceType('all');
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold">Mis Solicitudes</h2>
        <Button disabled={!currentOrganization} onClick={() => { setEditingRequest(null); setShowForm(true); }}>
          <Plus className="w-4 h-4 mr-2" />
          Nueva solicitud
        </Button>
      </div>

      <OrderFilters
        filterStore={filterStore}
        filterBranch={filterBranch}
        filterDate={filterDate}
        filterServiceType={filterServiceType}
        uniqueStores={uniqueStores}
        uniqueBranches={uniqueBranches}
        onFilterStoreChange={setFilterStore}
        onFilterBranchChange={setFilterBranch}
        onFilterDateChange={setFilterDate}
        onFilterServiceTypeChange={setFilterServiceType}
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
              {!currentOrganization
                ? 'Selecciona una organización activa para ver y crear solicitudes'
                : requests.length === 0
                ? 'No tienes solicitudes enviadas'
                : 'No hay solicitudes que coincidan con los filtros'}
            </p>
            {currentOrganization && requests.length === 0 && (
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
          onOpenChat={() => toast({
            title: 'Chat pendiente de migracion tenant-aware',
            description: 'El foro de mensajes no esta disponible todavia.',
          })}
          onOpenQuotes={(r) => { setSelectedRequest(r); setShowQuotesDialog(true); }}
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
        />
      )}

      {showQuotesDialog && selectedRequest && (
        <QuoteListDialog
          open={showQuotesDialog}
          onClose={() => { setShowQuotesDialog(false); setSelectedRequest(null); }}
          request={selectedRequest}
        />
      )}

      <Dialog open={showViewDialog} onOpenChange={setShowViewDialog}>
        <DialogContent className="max-w-3xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="text-2xl">
              {selectedRequest?.title || 'Solicitud sin título'}
            </DialogTitle>
            {selectedRequest && (
              <p className="text-sm text-muted-foreground mt-1">
                {selectedRequest.requestNumber}
              </p>
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
                    <span className="text-muted-foreground">Creador:</span>
                    <p className="font-medium">
                      {selectedRequest.createdByName || selectedRequest.createdBy}
                    </p>
                    {selectedRequest.createdByEmail && selectedRequest.createdByName && (
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
                            <TableHead className="min-w-[200px]">Equipo</TableHead>
                            <TableHead className="min-w-[150px]">Subequipo</TableHead>
                            <TableHead className="min-w-[120px]">Área</TableHead>
                            <TableHead className="min-w-[120px]">Subárea</TableHead>
                            <TableHead className="min-w-[200px]">Actividades</TableHead>
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
                              <TableCell>{detail.equipment || '-'}</TableCell>
                              <TableCell>{detail.sub_equipment || '-'}</TableCell>
                              <TableCell>{detail.area || '-'}</TableCell>
                              <TableCell>{detail.sub_area || '-'}</TableCell>
                              <TableCell>{detail.activities || '-'}</TableCell>
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
