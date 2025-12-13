import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { RequestForm } from './RequestForm';
import { QuoteListDialog } from './QuoteListDialog';
import { RequestChatDialog } from './RequestChatDialog';
import { Request, MOCK_PROVIDERS } from '@/types/request';
import { Plus, FileText, DollarSign, MessageSquare, Eye, Pencil } from 'lucide-react';
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
import { Separator } from '@/components/ui/separator';

export const RequestList = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [showForm, setShowForm] = useState(false);
  const [requests, setRequests] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [showQuotesDialog, setShowQuotesDialog] = useState(false);
  const [showChatDialog, setShowChatDialog] = useState(false);
  const [showViewDialog, setShowViewDialog] = useState(false);
  const [selectedRequest, setSelectedRequest] = useState<Request | null>(null);
  const [editingRequest, setEditingRequest] = useState<Request | null>(null);
  const [requestDetails, setRequestDetails] = useState<any[]>([]);

  const loadRequests = async () => {
    try {
      setLoading(true);
      await seedDatabase();
      
      const { data: requestsData, error: requestsError } = await supabase
        .from('requests')
        .select('*')
        .eq('status', 'sent')
        .order('created_at', { ascending: false });
      
      if (requestsError) throw requestsError;
      
      const transformedRequests: Request[] = (requestsData || []).map((req: any) => ({
        id: req.id,
        requestNumber: req.request_number,
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
        priority: req.priority,
        clientName: req.client_name,
        clientBranch: req.client_branch,
        isPublic: req.is_public,
        notifiedAt: req.notified_at,
        city: req.city,
        store: req.store,
        branch: req.branch,
        requiresVisit: req.requires_visit,
        visitDate: req.visit_date,
      }));
      
      setRequests(transformedRequests);
    } catch (error) {
      console.error('Error loading requests:', error);
      setRequests([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadRequests();
  }, [user]);

  const loadRequestDetails = async (requestId: string) => {
    const { data } = await supabase
      .from('request_details')
      .select('*')
      .eq('request_id', requestId);
    setRequestDetails(data || []);
  };

  const handleViewRequest = async (request: Request) => {
    setSelectedRequest(request);
    await loadRequestDetails(request.id);
    setShowViewDialog(true);
  };

  const handleEditRequest = async (request: Request) => {
    // Cargar detalles primero y esperar resultado
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

    setEditingRequest({
      ...request,
      details,
    });
    setShowForm(true);
  };

  const handleSaveRequest = async (request: Request, isDraft: boolean) => {
    try {
      // Actualizar cabecera en requests
      const { error: requestError } = await supabase
        .from('requests')
        .update({
          description: request.description,
          service_type: request.serviceType,
          deadline: request.deadline,
          city: request.city,
          store: request.store,
          branch: request.branch,
          location: request.location,
          requires_visit: request.requiresVisit,
          visit_date: request.visitDate || null,
          asset: request.asset,
          status: isDraft ? 'draft' : 'sent',
        })
        .eq('id', request.id);

      if (requestError) throw requestError;

      // Eliminar detalles antiguos y crear nuevos
      await supabase
        .from('request_details')
        .delete()
        .eq('request_id', request.id);

      if (request.details && request.details.length > 0) {
        const detailsToInsert = request.details.map(d => ({
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

        const { error: detailsError } = await supabase
          .from('request_details')
          .insert(detailsToInsert);

        if (detailsError) throw detailsError;
      }

      toast({
        title: isDraft ? "Borrador guardado" : "Solicitud actualizada",
        description: isDraft 
          ? "Tu solicitud ha sido guardada como borrador" 
          : "Los cambios han sido guardados correctamente",
      });
      
      setShowForm(false);
      setEditingRequest(null);
      loadRequests();
    } catch (error) {
      console.error('Error saving request:', error);
      toast({
        title: "Error",
        description: "No se pudo guardar la solicitud",
        variant: "destructive",
      });
    }
  };

  const getServiceTypeColor = (type: string) => {
    const colors = {
      emergencia: 'bg-red-500/10 text-red-500 border-red-500/20',
      correctivo: 'bg-orange-500/10 text-orange-500 border-orange-500/20',
      preventivo: 'bg-blue-500/10 text-blue-500 border-blue-500/20',
      proyecto: 'bg-purple-500/10 text-purple-500 border-purple-500/20',
    };
    return colors[type as keyof typeof colors] || '';
  };

  const getServiceTypeText = (type: string) => {
    const texts = {
      emergencia: 'Emergencia',
      correctivo: 'Correctivo',
      preventivo: 'Preventivo',
      proyecto: 'Proyecto',
    };
    return texts[type as keyof typeof texts] || type;
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold">Mis Solicitudes</h2>
        <Button onClick={() => { setEditingRequest(null); setShowForm(true); }}>
          <Plus className="w-4 h-4 mr-2" />
          Nueva solicitud
        </Button>
      </div>

      {loading ? (
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">Cargando solicitudes...</p>
          </CardContent>
        </Card>
      ) : requests.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <FileText className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <p className="text-muted-foreground">No tienes solicitudes enviadas</p>
            <Button onClick={() => { setEditingRequest(null); setShowForm(true); }} className="mt-4">
              Crear primera solicitud
            </Button>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nro. Solicitud</TableHead>
                  <TableHead>Tipo de Servicio</TableHead>
                  <TableHead>Sede</TableHead>
                  <TableHead>Fecha de Registro</TableHead>
                  <TableHead>Tienda</TableHead>
                  <TableHead>Usuario</TableHead>
                  <TableHead>Fecha Entrega Cotizaciones</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {requests.map((request) => (
                  <TableRow key={request.id}>
                    <TableCell className="font-medium">
                      {request.requestNumber}
                    </TableCell>
                    <TableCell>
                      <Badge className={getServiceTypeColor(request.serviceType)}>
                        {getServiceTypeText(request.serviceType)}
                      </Badge>
                    </TableCell>
                    <TableCell>{request.branch || request.clientBranch || '-'}</TableCell>
                    <TableCell>
                      {request.createdAt 
                        ? format(new Date(request.createdAt), 'dd/MM/yyyy', { locale: es })
                        : '-'}
                    </TableCell>
                    <TableCell>{request.store || '-'}</TableCell>
                    <TableCell>{request.createdBy}</TableCell>
                    <TableCell>
                      {request.deadline 
                        ? format(new Date(request.deadline), 'dd/MM/yyyy', { locale: es })
                        : '-'}
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => handleViewRequest(request)}
                          title="Ver solicitud"
                        >
                          <Eye className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => handleEditRequest(request)}
                          title="Editar solicitud"
                        >
                          <Pencil className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => {
                            setSelectedRequest(request);
                            setShowChatDialog(true);
                          }}
                          title="Chat"
                        >
                          <MessageSquare className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => {
                            setSelectedRequest(request);
                            setShowQuotesDialog(true);
                          }}
                          title="Ver cotizaciones"
                        >
                          <DollarSign className="h-4 w-4" />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {showForm && (
        <RequestForm
          onClose={() => { setShowForm(false); setEditingRequest(null); }}
          onSave={handleSaveRequest}
          editingRequest={editingRequest || undefined}
        />
      )}

      {showQuotesDialog && selectedRequest && (
        <QuoteListDialog
          open={showQuotesDialog}
          onClose={() => {
            setShowQuotesDialog(false);
            setSelectedRequest(null);
          }}
          request={selectedRequest}
        />
      )}

      {showChatDialog && selectedRequest && (
        <RequestChatDialog
          open={showChatDialog}
          onClose={() => {
            setShowChatDialog(false);
            setSelectedRequest(null);
          }}
          requestId={selectedRequest.id}
          requestNumber={selectedRequest.requestNumber}
        />
      )}

      {/* Diálogo para ver detalle de solicitud */}
      <Dialog open={showViewDialog} onOpenChange={setShowViewDialog}>
        <DialogContent className="max-w-3xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Detalle de Solicitud {selectedRequest?.requestNumber}</DialogTitle>
          </DialogHeader>
          
          {selectedRequest && (
            <div className="space-y-6">
              {/* Cabecera */}
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-primary">Datos de Cabecera</h3>
                <div className="grid grid-cols-2 md:grid-cols-3 gap-4 text-sm">
                  <div>
                    <span className="text-muted-foreground">Nro. Solicitud:</span>
                    <p className="font-medium">{selectedRequest.requestNumber}</p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Tipo de Servicio:</span>
                    <p>
                      <Badge className={getServiceTypeColor(selectedRequest.serviceType)}>
                        {getServiceTypeText(selectedRequest.serviceType)}
                      </Badge>
                    </p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Creador:</span>
                    <p className="font-medium">{selectedRequest.createdBy}</p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Ciudad:</span>
                    <p className="font-medium">{selectedRequest.city || '-'}</p>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Tienda:</span>
                    <p className="font-medium">{selectedRequest.store || '-'}</p>
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

              {/* Detalles */}
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-primary">Detalle de la Solicitud</h3>
                {requestDetails.length === 0 ? (
                  <p className="text-muted-foreground text-sm">No hay detalles registrados</p>
                ) : (
                  requestDetails.map((detail: any, index: number) => (
                    <Card key={detail.id} className="p-4 bg-muted/30">
                      <h4 className="font-medium mb-3">Detalle #{index + 1}</h4>
                      <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
                        <div>
                          <span className="text-muted-foreground">Equipo:</span>
                          <p className="font-medium">{detail.equipment || '-'}</p>
                        </div>
                        <div>
                          <span className="text-muted-foreground">Subequipo:</span>
                          <p className="font-medium">{detail.sub_equipment || '-'}</p>
                        </div>
                        <div>
                          <span className="text-muted-foreground">Área:</span>
                          <p className="font-medium">{detail.area || '-'}</p>
                        </div>
                        <div>
                          <span className="text-muted-foreground">Subárea:</span>
                          <p className="font-medium">{detail.sub_area || '-'}</p>
                        </div>
                        <div>
                          <span className="text-muted-foreground">Cantidad:</span>
                          <p className="font-medium">{detail.quantity || '-'}</p>
                        </div>
                        <div>
                          <span className="text-muted-foreground">U.M.:</span>
                          <p className="font-medium">{detail.unit_measure || '-'}</p>
                        </div>
                        <div>
                          <span className="text-muted-foreground">Encargado:</span>
                          <p className="font-medium">{detail.responsible_user || '-'}</p>
                        </div>
                        <div>
                          <span className="text-muted-foreground">Delegado:</span>
                          <p className="font-medium">{detail.delegate_type || '-'}</p>
                        </div>
                        {detail.activities && (
                          <div className="col-span-full">
                            <span className="text-muted-foreground">Actividades:</span>
                            <p className="font-medium">{detail.activities}</p>
                          </div>
                        )}
                        {detail.relevant_materials && (
                          <div className="col-span-full">
                            <span className="text-muted-foreground">Materiales Relevantes:</span>
                            <p className="font-medium">{detail.relevant_materials}</p>
                          </div>
                        )}
                        {detail.observation && (
                          <div className="col-span-full">
                            <span className="text-muted-foreground">Observación:</span>
                            <p className="font-medium">{detail.observation}</p>
                          </div>
                        )}
                      </div>
                    </Card>
                  ))
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
};