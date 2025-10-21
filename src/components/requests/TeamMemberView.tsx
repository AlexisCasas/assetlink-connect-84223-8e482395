import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Request, MOCK_PROVIDERS } from '@/types/request';
import { QuoteForm } from './QuoteForm';
import { FileText, Calendar, MapPin, Building2, Clock } from 'lucide-react';

export const TeamMemberView = () => {
  const { user } = useAuth();
  const [assignedRequests, setAssignedRequests] = useState<Request[]>([]);
  const [showQuoteForm, setShowQuoteForm] = useState(false);
  const [selectedRequest, setSelectedRequest] = useState<Request | null>(null);

  useEffect(() => {
    const stored = localStorage.getItem('requests');
    if (stored) {
      const allRequests = JSON.parse(stored);
      
      // Filtrar solicitudes asignadas a este miembro del equipo
      const filtered = allRequests.filter((r: Request) => {
        if (r.status !== 'sent' || !r.assignments) return false;
        
        // Buscar si esta solicitud está asignada a este usuario
        const provider = MOCK_PROVIDERS.find(p => 
          p.team?.some(tm => tm.email === user?.email)
        );
        
        if (!provider) return false;
        
        const assignment = r.assignments[provider.id];
        return assignment && assignment.teamMemberId === user?.id;
      });
      
      setAssignedRequests(filtered);
    }
  }, [user]);

  const handleSaveQuote = (quote: any) => {
    // Guardar la cotización
    const stored = localStorage.getItem('requests');
    if (stored && selectedRequest) {
      const allRequests = JSON.parse(stored);
      const requestIndex = allRequests.findIndex((r: Request) => r.id === selectedRequest.id);
      
      if (requestIndex >= 0) {
        if (!allRequests[requestIndex].quotes) {
          allRequests[requestIndex].quotes = [];
        }
        allRequests[requestIndex].quotes.push(quote);
        localStorage.setItem('requests', JSON.stringify(allRequests));
        
        setAssignedRequests(assignedRequests.map(r => 
          r.id === selectedRequest.id 
            ? { ...r, quotes: [...(r.quotes || []), quote] }
            : r
        ));
      }
    }
    
    setShowQuoteForm(false);
    setSelectedRequest(null);
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

  const getAssignmentInfo = (request: Request) => {
    if (!request.assignments) return null;
    
    const provider = MOCK_PROVIDERS.find(p => 
      p.team?.some(tm => tm.email === user?.email)
    );
    
    return provider ? request.assignments[provider.id] : null;
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h2 className="text-2xl font-bold">Mis Asignaciones</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Solicitudes asignadas para cotizar
          </p>
        </div>
        <Badge variant="outline" className="text-lg px-4 py-2">
          {assignedRequests.length} asignación(es)
        </Badge>
      </div>

      {assignedRequests.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <FileText className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <p className="text-muted-foreground">No tienes solicitudes asignadas</p>
            <p className="text-sm text-muted-foreground mt-2">
              Las solicitudes asignadas por tu supervisor aparecerán aquí
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {assignedRequests.map((request) => {
            const assignment = getAssignmentInfo(request);
            const hasQuote = request.quotes?.some(q => q.teamMemberId === user?.id);
            
            return (
              <Card key={request.id} className="hover:shadow-lg transition-shadow">
                <CardHeader>
                  <div className="flex justify-between items-start">
                    <div className="flex-1">
                      <CardTitle className="text-lg">{request.requestNumber}</CardTitle>
                      <p className="text-sm text-muted-foreground mt-1">
                        Cliente: {request.createdBy}
                      </p>
                    </div>
                    <Badge className={getServiceTypeColor(request.serviceType)}>
                      {getServiceTypeText(request.serviceType)}
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent className="space-y-4">
                  {assignment && (
                    <div className="p-3 bg-primary/5 border border-primary/20 rounded-lg">
                      <div className="flex items-center gap-2 text-sm">
                        <Clock className="w-4 h-4" />
                        <span className="text-muted-foreground">Fecha límite:</span>
                        <span className="font-medium text-primary">
                          {new Date(assignment.maxDeadline).toLocaleDateString('es-ES', {
                            day: '2-digit',
                            month: 'long',
                            year: 'numeric',
                            hour: '2-digit',
                            minute: '2-digit'
                          })}
                        </span>
                      </div>
                      {assignment.reason && (
                        <p className="text-xs text-muted-foreground mt-2">
                          Motivo de asignación: {assignment.reason}
                        </p>
                      )}
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
                  </div>

                  {request.observations && (
                    <div className="pt-3 border-t">
                      <p className="text-sm font-medium mb-1">Observaciones:</p>
                      <p className="text-sm text-muted-foreground">{request.observations}</p>
                    </div>
                  )}

                  <div className="pt-3 border-t flex justify-end">
                    {hasQuote ? (
                      <Badge variant="outline" className="text-green-600 border-green-600">
                        Cotización enviada
                      </Badge>
                    ) : (
                      <Button 
                        onClick={() => {
                          setSelectedRequest(request);
                          setShowQuoteForm(true);
                        }}
                      >
                        Crear cotización
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {showQuoteForm && selectedRequest && (
        <QuoteForm
          request={selectedRequest}
          onClose={() => {
            setShowQuoteForm(false);
            setSelectedRequest(null);
          }}
          onSave={handleSaveQuote}
        />
      )}
    </div>
  );
};
