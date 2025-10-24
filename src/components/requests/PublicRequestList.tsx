import { useState, useEffect } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Request } from '@/types/request';
import { QuoteForm } from './QuoteForm';
import { Building2, MapPin, Calendar, AlertCircle } from 'lucide-react';

export const PublicRequestList = () => {
  const [publicRequests, setPublicRequests] = useState<Request[]>([]);
  const [selectedRequest, setSelectedRequest] = useState<Request | null>(null);
  const [showQuoteForm, setShowQuoteForm] = useState(false);

  useEffect(() => {
    loadPublicRequests();
  }, []);

  const loadPublicRequests = () => {
    const requests = JSON.parse(localStorage.getItem('requests') || '[]');
    const publics = requests.filter((r: Request) => 
      r.status === 'sent' && (r.isPublic || r.selectedProviders.length === 0)
    ).sort((a: Request, b: Request) => a.priority - b.priority);
    setPublicRequests(publics);
  };

  const getServiceTypeColor = (type: string) => {
    switch (type) {
      case 'emergencia': return 'destructive';
      case 'correctivo': return 'default';
      case 'preventivo': return 'secondary';
      case 'proyecto': return 'outline';
      default: return 'default';
    }
  };

  const getServiceTypeText = (type: string) => {
    switch (type) {
      case 'emergencia': return 'Emergencia';
      case 'correctivo': return 'Correctivo';
      case 'preventivo': return 'Preventivo';
      case 'proyecto': return 'Proyecto';
      default: return type;
    }
  };

  const handleQuote = (request: Request) => {
    setSelectedRequest(request);
    setShowQuoteForm(true);
  };

  const handleSaveQuote = () => {
    setShowQuoteForm(false);
    setSelectedRequest(null);
    loadPublicRequests();
  };

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Solicitudes Públicas</h1>
        <p className="text-muted-foreground">
          Solicitudes abiertas para recibir cotizaciones de cualquier proveedor
        </p>
      </div>

      {publicRequests.length === 0 ? (
        <Card className="p-8 text-center">
          <p className="text-muted-foreground">No hay solicitudes públicas disponibles</p>
        </Card>
      ) : (
        <div className="grid gap-4">
          {publicRequests.map((request) => (
            <Card key={request.id} className="p-6">
              <div className="flex items-start justify-between mb-4">
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-2">
                    <h3 className="text-lg font-semibold">{request.requestNumber}</h3>
                    {request.priority === 1 && (
                      <Badge variant="destructive" className="flex items-center gap-1">
                        <AlertCircle className="h-3 w-3" />
                        URGENTE
                      </Badge>
                    )}
                    <Badge variant={getServiceTypeColor(request.serviceType)}>
                      {getServiceTypeText(request.serviceType)}
                    </Badge>
                    <Badge variant="outline" className="bg-blue-50">
                      Solicitud Pública
                    </Badge>
                  </div>
                  <p className="text-muted-foreground mb-4">{request.description}</p>
                  
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    {request.clientName && (
                      <div className="flex items-center gap-2">
                        <Building2 className="h-4 w-4 text-muted-foreground" />
                        <span><strong>Cliente:</strong> {request.clientName}</span>
                      </div>
                    )}
                    {request.clientBranch && (
                      <div className="flex items-center gap-2">
                        <MapPin className="h-4 w-4 text-muted-foreground" />
                        <span><strong>Sede:</strong> {request.clientBranch}</span>
                      </div>
                    )}
                    <div>
                      <strong>Activo:</strong> {request.asset}
                    </div>
                    <div>
                      <strong>Ubicación:</strong> {request.location}
                    </div>
                    <div className="flex items-center gap-2">
                      <Calendar className="h-4 w-4 text-muted-foreground" />
                      <span><strong>Fecha límite:</strong> {new Date(request.deadline).toLocaleDateString()}</span>
                    </div>
                    {request.startTime && (
                      <div>
                        <strong>Inicio requerido:</strong> {new Date(request.startTime).toLocaleDateString()}
                      </div>
                    )}
                  </div>
                  {request.observations && (
                    <div className="mt-4">
                      <strong>Observaciones:</strong>
                      <p className="text-muted-foreground">{request.observations}</p>
                    </div>
                  )}
                </div>
              </div>

              <div className="flex gap-2">
                <Button onClick={() => handleQuote(request)}>
                  Enviar Cotización
                </Button>
              </div>
            </Card>
          ))}
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
