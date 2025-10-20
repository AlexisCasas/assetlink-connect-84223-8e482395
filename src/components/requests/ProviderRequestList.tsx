import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Request, MOCK_PROVIDERS } from '@/types/request';
import { FileText, Calendar, MapPin, Building2 } from 'lucide-react';

export const ProviderRequestList = () => {
  const { user } = useAuth();
  const [receivedRequests, setReceivedRequests] = useState<Request[]>([]);

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
          {receivedRequests.map((request) => (
            <Card key={request.id} className="hover:shadow-lg transition-shadow">
              <CardHeader>
                <div className="flex justify-between items-start">
                  <div className="flex-1">
                    <CardTitle className="text-lg">{request.requestNumber}</CardTitle>
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

                {request.observations && (
                  <div className="pt-3 border-t">
                    <p className="text-sm font-medium mb-1">Observaciones:</p>
                    <p className="text-sm text-muted-foreground">{request.observations}</p>
                  </div>
                )}

                <div className="pt-3 border-t">
                  <p className="text-sm text-muted-foreground">
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
          ))}
        </div>
      )}
    </div>
  );
};
