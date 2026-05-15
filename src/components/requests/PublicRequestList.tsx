import { useState, useEffect } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { QuoteForm } from './QuoteForm';
import { Building2, MapPin, Calendar, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { seedDatabase } from '@/lib/seedData';

interface Request {
  id: string;
  request_number: string;
  description: string;
  asset: string;
  location: string;
  service_type: 'emergencia' | 'correctivo' | 'preventivo' | 'proyecto';
  observations?: string;
  deadline: string;
  start_time?: string;
  status: 'draft' | 'sent' | 'quoted' | 'completed' | 'anulado';
  created_at: string;
  created_by: string;
  priority: number;
  client_name?: string;
  client_branch?: string;
  is_public?: boolean;
  notified_at?: string;
}

export const PublicRequestList = () => {
  const [publicRequests, setPublicRequests] = useState<Request[]>([]);
  const [selectedRequest, setSelectedRequest] = useState<Request | null>(null);
  const [showQuoteForm, setShowQuoteForm] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    initializeAndLoadRequests();
  }, []);

  const initializeAndLoadRequests = async () => {
    await seedDatabase();
    loadPublicRequests();
  };

  const loadPublicRequests = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('requests')
        .select('*')
        .eq('status', 'sent')
        .eq('is_public', true)
        .order('priority', { ascending: true });

      if (error) {
        console.error('Error loading requests:', error);
        return;
      }

      setPublicRequests(data || []);
    } catch (error) {
      console.error('Error:', error);
    } finally {
      setLoading(false);
    }
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

  const handleSaveQuote = async (quote: any) => {
    // QuoteForm now persists the quote internally with all new fields.
    setShowQuoteForm(false);
    setSelectedRequest(null);
    loadPublicRequests();
  };

  // Convert database request to the format QuoteForm expects
  const convertToLegacyRequest = (dbRequest: Request) => ({
    ...dbRequest,
    requestNumber: dbRequest.request_number,
    serviceType: dbRequest.service_type,
    selectedProviders: [],
    createdAt: dbRequest.created_at,
    createdBy: dbRequest.created_by,
    clientName: dbRequest.client_name,
    clientBranch: dbRequest.client_branch,
    isPublic: dbRequest.is_public,
    notifiedAt: dbRequest.notified_at,
    startTime: dbRequest.start_time
  });

  if (loading) {
    return (
      <div className="p-6 space-y-6">
        <div>
          <h1 className="text-3xl font-bold">Solicitudes Públicas</h1>
          <p className="text-muted-foreground">
            Solicitudes abiertas para recibir cotizaciones de cualquier proveedor
          </p>
        </div>
        <Card className="p-8 text-center">
          <p className="text-muted-foreground">Cargando solicitudes...</p>
        </Card>
      </div>
    );
  }

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
                    <h3 className="text-lg font-semibold">{request.request_number}</h3>
                    {request.priority === 1 && (
                      <Badge variant="destructive" className="flex items-center gap-1">
                        <AlertCircle className="h-3 w-3" />
                        URGENTE
                      </Badge>
                    )}
                    <Badge variant={getServiceTypeColor(request.service_type)}>
                      {getServiceTypeText(request.service_type)}
                    </Badge>
                    <Badge variant="outline" className="bg-blue-50">
                      Solicitud Pública
                    </Badge>
                  </div>
                  <p className="text-muted-foreground mb-4">{request.description}</p>
                  
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    {request.client_name && (
                      <div className="flex items-center gap-2">
                        <Building2 className="h-4 w-4 text-muted-foreground" />
                        <span><strong>Cliente:</strong> {request.client_name}</span>
                      </div>
                    )}
                    {request.client_branch && (
                      <div className="flex items-center gap-2">
                        <MapPin className="h-4 w-4 text-muted-foreground" />
                        <span><strong>Sede:</strong> {request.client_branch}</span>
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
                    {request.start_time && (
                      <div>
                        <strong>Inicio requerido:</strong> {new Date(request.start_time).toLocaleDateString()}
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
          request={convertToLegacyRequest(selectedRequest) as any}
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
