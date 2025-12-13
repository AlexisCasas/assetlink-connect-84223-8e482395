import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { RequestForm } from './RequestForm';
import { QuoteListDialog } from './QuoteListDialog';
import { RequestChatDialog } from './RequestChatDialog';
import { Request, MOCK_PROVIDERS } from '@/types/request';
import { Plus, FileText, DollarSign, MessageSquare, Eye } from 'lucide-react';
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

export const RequestList = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [showForm, setShowForm] = useState(false);
  const [requests, setRequests] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [showQuotesDialog, setShowQuotesDialog] = useState(false);
  const [showChatDialog, setShowChatDialog] = useState(false);
  const [selectedRequest, setSelectedRequest] = useState<Request | null>(null);

  useEffect(() => {
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
        }));
        
        setRequests(transformedRequests);
      } catch (error) {
        console.error('Error loading requests:', error);
        setRequests([]);
      } finally {
        setLoading(false);
      }
    };
    loadRequests();
  }, [user]);

  const handleSaveRequest = (request: Request, isDraft: boolean) => {
    const stored = localStorage.getItem('requests');
    const allRequests = stored ? JSON.parse(stored) : [];
    
    const existingIndex = allRequests.findIndex((r: Request) => r.id === request.id);
    if (existingIndex >= 0) {
      allRequests[existingIndex] = request;
    } else {
      allRequests.push(request);
    }
    
    localStorage.setItem('requests', JSON.stringify(allRequests));
    
    if (!isDraft) {
      setRequests(allRequests.filter((r: Request) => r.createdBy === user?.email && r.status === 'sent'));
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
        <Button onClick={() => setShowForm(true)}>
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
            <Button onClick={() => setShowForm(true)} className="mt-4">
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
          onClose={() => setShowForm(false)}
          onSave={handleSaveRequest}
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
    </div>
  );
};