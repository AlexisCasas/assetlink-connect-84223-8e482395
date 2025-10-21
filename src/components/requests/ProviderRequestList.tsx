import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Request, MOCK_PROVIDERS } from '@/types/request';
import { AssignmentDialog } from './AssignmentDialog';
import { FileText, Calendar, MapPin, Building2, Users, AlertTriangle } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

export const ProviderRequestList = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [receivedRequests, setReceivedRequests] = useState<Request[]>([]);
  const [showAssignmentDialog, setShowAssignmentDialog] = useState(false);
  const [selectedRequest, setSelectedRequest] = useState<Request | null>(null);

  useEffect(() => {
    const stored = localStorage.getItem('requests');
    if (stored) {
      const allRequests = JSON.parse(stored);
      
      // Encontrar el proveedor actual basado en el email del usuario
      const currentProvider = MOCK_PROVIDERS.find(p => p.email === user?.email);
      
      if (currentProvider) {
        // Filtrar solicitudes enviadas que incluyan a este proveedor
        const filtered = allRequests.filter((r: Request) => 
          r.status === 'sent' && r.selectedProviders.includes(currentProvider.id)
        );
        // Ordenar por prioridad (emergencia primero)
        filtered.sort((a, b) => a.priority - b.priority);
        setReceivedRequests(filtered);
      }
    }
  }, [user]);

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

  const handleRequestTechnicalVisit = (request: Request) => {
    const currentProvider = MOCK_PROVIDERS.find(p => p.email === user?.email);
    if (!currentProvider) return;

    const stored = localStorage.getItem('requests');
    if (stored) {
      const allRequests = JSON.parse(stored);
      const requestIndex = allRequests.findIndex((r: Request) => r.id === request.id);
      
      if (requestIndex >= 0) {
        if (!allRequests[requestIndex].technicalVisitRequested) {
          allRequests[requestIndex].technicalVisitRequested = {};
        }
        allRequests[requestIndex].technicalVisitRequested[currentProvider.id] = true;
        localStorage.setItem('requests', JSON.stringify(allRequests));
        
        setReceivedRequests(receivedRequests.map(r => 
          r.id === request.id 
            ? { ...r, technicalVisitRequested: { ...r.technicalVisitRequested, [currentProvider.id]: true } }
            : r
        ));
        
        toast({
          title: "Visita técnica solicitada",
          description: "Se ha enviado la solicitud de visita técnica al cliente",
        });
      }
    }
  };

  const handleAssignment = (assignment: any) => {
    if (!selectedRequest) return;
    
    const currentProvider = MOCK_PROVIDERS.find(p => p.email === user?.email);
    if (!currentProvider) return;

    const stored = localStorage.getItem('requests');
    if (stored) {
      const allRequests = JSON.parse(stored);
      const requestIndex = allRequests.findIndex((r: Request) => r.id === selectedRequest.id);
      
      if (requestIndex >= 0) {
        if (!allRequests[requestIndex].assignments) {
          allRequests[requestIndex].assignments = {};
        }
        allRequests[requestIndex].assignments[currentProvider.id] = assignment;
        localStorage.setItem('requests', JSON.stringify(allRequests));
        
        setReceivedRequests(receivedRequests.map(r => 
          r.id === selectedRequest.id 
            ? { ...r, assignments: { ...r.assignments, [currentProvider.id]: assignment } }
            : r
        ));
      }
    }
  };

  const getCurrentProviderAssignment = (request: Request) => {
    const currentProvider = MOCK_PROVIDERS.find(p => p.email === user?.email);
    if (!currentProvider || !request.assignments) return null;
    return request.assignments[currentProvider.id];
  };

  const hasTechnicalVisitRequested = (request: Request) => {
    const currentProvider = MOCK_PROVIDERS.find(p => p.email === user?.email);
    if (!currentProvider || !request.technicalVisitRequested) return false;
    return request.technicalVisitRequested[currentProvider.id];
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold">Nuevas Solicitudes</h2>
        <Badge variant="outline" className="text-lg px-4 py-2">
          {receivedRequests.length} solicitud(es)
        </Badge>
      </div>

      {receivedRequests.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <FileText className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <p className="text-muted-foreground">No tienes nuevas solicitudes</p>
            <p className="text-sm text-muted-foreground mt-2">
              Las solicitudes de clientes aparecerán aquí
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {receivedRequests.map((request) => {
            const assignment = getCurrentProviderAssignment(request);
            const visitRequested = hasTechnicalVisitRequested(request);
            
            return (
              <Card key={request.id} className="hover:shadow-lg transition-shadow">
                <CardHeader>
                  <div className="flex justify-between items-start">
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <CardTitle className="text-lg">{request.requestNumber}</CardTitle>
                        {request.serviceType === 'emergencia' && (
                          <Badge variant="destructive" className="animate-pulse">
                            <AlertTriangle className="w-3 h-3 mr-1" />
                            URGENTE
                          </Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground mt-1">
                        De: {request.createdBy}
                      </p>
                    </div>
                    <Badge className={getServiceTypeColor(request.serviceType)}>
                      {getServiceTypeText(request.serviceType)}
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent className="space-y-4">
                  {assignment && (
                    <div className="p-3 bg-green-500/10 border border-green-500/20 rounded-lg">
                      <div className="flex items-center gap-2 text-sm">
                        <Users className="w-4 h-4 text-green-600" />
                        <span className="font-medium text-green-600">
                          Asignado a: {assignment.teamMemberName}
                        </span>
                      </div>
                      <p className="text-xs text-muted-foreground mt-1">
                        Fecha límite: {new Date(assignment.maxDeadline).toLocaleDateString('es-ES')}
                      </p>
                    </div>
                  )}

                  <div>
                    <p className="text-sm font-medium mb-1">Descripción:</p>
                    <p className="text-sm text-muted-foreground">{request.description}</p>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                    <div className="flex items-center gap-2">
                      <Building2 className="w-4 h-4 text-muted-foreground" />
                      <span className="text-muted-foreground">Activo:</span>
                      <span className="font-medium">{request.asset}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <MapPin className="w-4 h-4 text-muted-foreground" />
                      <span className="text-muted-foreground">Ubicación:</span>
                      <span className="font-medium">{request.location}</span>
                    </div>
                    <div className="flex items-center gap-2 md:col-span-2">
                      <Calendar className="w-4 h-4 text-muted-foreground" />
                      <span className="text-muted-foreground">Fecha límite para cotizar:</span>
                      <span className="font-medium text-primary">
                        {new Date(request.deadline).toLocaleDateString('es-ES', {
                          day: '2-digit',
                          month: 'long',
                          year: 'numeric'
                        })}
                      </span>
                    </div>
                  </div>

                  {request.startTime && (
                    <div className="p-2 bg-muted rounded">
                      <p className="text-sm">
                        <span className="text-muted-foreground">Inicio solicitado:</span>
                        <span className="ml-2 font-medium">
                          {new Date(request.startTime).toLocaleDateString('es-ES', {
                            day: '2-digit',
                            month: 'long',
                            year: 'numeric',
                            hour: '2-digit',
                            minute: '2-digit'
                          })}
                        </span>
                      </p>
                    </div>
                  )}

                  {request.observations && (
                    <div className="pt-3 border-t">
                      <p className="text-sm font-medium mb-1">Observaciones:</p>
                      <p className="text-sm text-muted-foreground">{request.observations}</p>
                    </div>
                  )}

                  <div className="pt-3 border-t flex flex-wrap gap-2">
                    <Button 
                      size="sm"
                      onClick={() => {
                        setSelectedRequest(request);
                        setShowAssignmentDialog(true);
                      }}
                    >
                      <Users className="w-4 h-4 mr-2" />
                      {assignment ? 'Reasignar' : 'Asignar a equipo'}
                    </Button>
                    
                    <Button 
                      size="sm"
                      variant="outline"
                      onClick={() => handleRequestTechnicalVisit(request)}
                      disabled={visitRequested}
                    >
                      {visitRequested ? 'Visita solicitada' : 'Solicitar visita técnica'}
                    </Button>
                  </div>

                  <div className="pt-2 border-t">
                    <p className="text-xs text-muted-foreground">
                      Recibido: {new Date(request.createdAt).toLocaleDateString('es-ES', {
                        day: '2-digit',
                        month: 'long',
                        year: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit'
                      })}
                    </p>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {showAssignmentDialog && selectedRequest && (
        <AssignmentDialog
          request={selectedRequest}
          providerId={MOCK_PROVIDERS.find(p => p.email === user?.email)?.id || ''}
          onClose={() => {
            setShowAssignmentDialog(false);
            setSelectedRequest(null);
          }}
          onAssign={handleAssignment}
        />
      )}
    </div>
  );
};
