import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { RequestForm } from './RequestForm';
import { Request, MOCK_PROVIDERS } from '@/types/request';
import { Plus, Calendar, MapPin, FileText, Bell, Building2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { seedDatabase } from '@/lib/seedData';
import { supabase } from '@/integrations/supabase/client';

export const RequestList = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [showForm, setShowForm] = useState(false);
  const [requests, setRequests] = useState<Request[]>([]);

  useEffect(() => {
    const loadRequests = async () => {
      // Always seed the database to ensure example data exists
      await seedDatabase();
      
      // Load all sent requests from Supabase (not filtered by user)
      const { data, error } = await supabase
        .from('requests')
        .select('*')
        .eq('status', 'sent')
        .order('created_at', { ascending: false });
      
      if (data && !error) {
        setRequests(data as any);
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

  const handleNotifyProviders = (request: Request) => {
    const stored = localStorage.getItem('requests');
    const allRequests = stored ? JSON.parse(stored) : [];
    const requestIndex = allRequests.findIndex((r: Request) => r.id === request.id);
    
    if (requestIndex !== -1) {
      allRequests[requestIndex].notifiedAt = new Date().toISOString();
      localStorage.setItem('requests', JSON.stringify(allRequests));
      
      toast({
        title: "Proveedores notificados",
        description: `Se ha notificado a ${request.isPublic ? 'todos los proveedores' : request.selectedProviders.length + ' proveedor(es)'} sobre tu solicitud urgente`,
      });
      
      setRequests(allRequests.filter((r: Request) => r.createdBy === user?.email && r.status === 'sent'));
    }
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

      {requests.length === 0 ? (
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
        <div className="grid gap-4">
          {requests.map((request) => (
            <Card key={request.id}>
              <CardHeader>
                <div className="flex justify-between items-start">
                  <div>
                    <CardTitle className="text-lg">{request.requestNumber}</CardTitle>
                    <p className="text-sm text-muted-foreground mt-1">{request.description}</p>
                  </div>
                  <Badge className={getServiceTypeColor(request.serviceType)}>
                    {getServiceTypeText(request.serviceType)}
                  </Badge>
                </div>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="grid grid-cols-2 gap-4 text-sm">
                  {request.clientName && (
                    <div className="flex items-center gap-2">
                      <Building2 className="w-4 h-4 text-muted-foreground" />
                      <span className="text-muted-foreground">Cliente:</span>
                      <span className="font-medium">{request.clientName}</span>
                    </div>
                  )}
                  {request.clientBranch && (
                    <div className="flex items-center gap-2">
                      <MapPin className="w-4 h-4 text-muted-foreground" />
                      <span className="text-muted-foreground">Sede:</span>
                      <span className="font-medium">{request.clientBranch}</span>
                    </div>
                  )}
                  <div className="flex items-center gap-2">
                    <FileText className="w-4 h-4 text-muted-foreground" />
                    <span className="text-muted-foreground">Activo:</span>
                    <span className="font-medium">{request.asset}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <MapPin className="w-4 h-4 text-muted-foreground" />
                    <span className="text-muted-foreground">Ubicación:</span>
                    <span className="font-medium">{request.location}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <Calendar className="w-4 h-4 text-muted-foreground" />
                    <span className="text-muted-foreground">Fecha límite:</span>
                    <span className="font-medium">
                      {new Date(request.deadline).toLocaleDateString()}
                    </span>
                  </div>
                </div>
                
                <div className="pt-3 border-t">
                  <p className="text-sm text-muted-foreground mb-2">
                    {request.isPublic ? 'Solicitud Pública - Visible para todos los proveedores' : `Enviado a ${request.selectedProviders.length} proveedor(es):`}
                  </p>
                  {!request.isPublic && (
                    <div className="flex flex-wrap gap-2 mb-3">
                      {request.selectedProviders.map((providerId) => {
                        const provider = MOCK_PROVIDERS.find(p => p.id === providerId);
                        return (
                          <Badge key={providerId} variant="outline">
                            {provider?.name}
                          </Badge>
                        );
                      })}
                    </div>
                  )}
                  
                  <div className="flex gap-2 items-center">
                    <Button 
                      variant="outline" 
                      size="sm"
                      onClick={() => handleNotifyProviders(request)}
                    >
                      <Bell className="h-4 w-4 mr-2" />
                      Notificar a Proveedores
                    </Button>
                    {request.notifiedAt && (
                      <Badge variant="secondary" className="text-xs">
                        Última notificación: {new Date(request.notifiedAt).toLocaleString()}
                      </Badge>
                    )}
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {showForm && (
        <RequestForm
          onClose={() => setShowForm(false)}
          onSave={handleSaveRequest}
        />
      )}
    </div>
  );
};
