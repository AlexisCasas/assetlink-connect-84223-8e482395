import { useState, useEffect } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Building2, MapPin, Calendar, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { isProviderFacingOrganizationType } from '@/types/providerRelationship';
import { QuoteForm } from './QuoteForm';

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
  const { currentOrganization } = useAuth();
  const [publicRequests, setPublicRequests] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedRequestForQuote, setSelectedRequestForQuote] = useState<Request | null>(null);

  const canViewMarketplace = isProviderFacingOrganizationType(currentOrganization?.organizationType);

  useEffect(() => {
    if (!canViewMarketplace) {
      setPublicRequests([]);
      setLoading(false);
      return;
    }

    loadPublicRequests();
  }, [currentOrganization?.id, canViewMarketplace]);

  const loadPublicRequests = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('requests')
        .select('*')
        .eq('status', 'sent')
        .eq('is_public', true)
        .eq('request_type', 'external')
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

      {!canViewMarketplace ? (
        <Card className="p-8 text-center">
          <p className="text-muted-foreground">Selecciona una organización proveedora para ver solicitudes disponibles</p>
        </Card>
      ) : publicRequests.length === 0 ? (
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
                <Button variant="outline" onClick={() => setSelectedRequestForQuote(request)}>
                  Enviar Cotización
                </Button>
              </div>
            </Card>
          ))}
        </div>
      )}

      {selectedRequestForQuote && (
        <QuoteForm
          request={selectedRequestForQuote as any}
          onClose={() => setSelectedRequestForQuote(null)}
          onSave={() => {
            setSelectedRequestForQuote(null);
            loadPublicRequests();
          }}
        />
      )}

    </div>
  );
};
