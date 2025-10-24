import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Checkbox } from '@/components/ui/checkbox';
import { useToast } from '@/hooks/use-toast';
import { Request, MOCK_PROVIDERS, ServiceType } from '@/types/request';
import { Badge } from '@/components/ui/badge';
import { X, Upload } from 'lucide-react';

interface RequestFormProps {
  onClose: () => void;
  onSave: (request: Request, isDraft: boolean) => void;
  editingRequest?: Request;
}

export const RequestForm = ({ onClose, onSave, editingRequest }: RequestFormProps) => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [description, setDescription] = useState(editingRequest?.description || '');
  const [asset, setAsset] = useState(editingRequest?.asset || '');
  const [location, setLocation] = useState(editingRequest?.location || '');
  const [serviceType, setServiceType] = useState<ServiceType>(editingRequest?.serviceType || 'correctivo');
  const [observations, setObservations] = useState(editingRequest?.observations || '');
  const [deadline, setDeadline] = useState(editingRequest?.deadline || '');
  const [startTime, setStartTime] = useState(editingRequest?.startTime || '');
  const [selectedProviders, setSelectedProviders] = useState<string[]>(editingRequest?.selectedProviders || []);
  const [clientName, setClientName] = useState(editingRequest?.clientName || '');
  const [clientBranch, setClientBranch] = useState(editingRequest?.clientBranch || '');

  const handleProviderToggle = (providerId: string) => {
    if (selectedProviders.includes(providerId)) {
      setSelectedProviders(selectedProviders.filter(id => id !== providerId));
    } else {
      if (selectedProviders.length >= 5) {
        toast({
          title: "Límite alcanzado",
          description: "Solo puedes seleccionar hasta 5 proveedores",
          variant: "destructive",
        });
        return;
      }
      setSelectedProviders([...selectedProviders, providerId]);
    }
  };

  const handleSubmit = (isDraft: boolean) => {
    if (!description || !asset || !location || !deadline || !clientName || !clientBranch) {
      toast({
        title: "Error",
        description: "Por favor completa los campos obligatorios",
        variant: "destructive",
      });
      return;
    }

    // Advertir si no se seleccionan proveedores (solicitud pública)
    if (!isDraft && selectedProviders.length === 0) {
      const confirmed = window.confirm(
        "No has seleccionado ningún proveedor. Tu solicitud será publicada como solicitud pública para que cualquier proveedor pueda enviar una cotización. ¿Deseas continuar?"
      );
      if (!confirmed) return;
    }

    // Validar tiempo de inicio para correctivo/preventivo (mínimo 48 horas)
    if (!isDraft && (serviceType === 'correctivo' || serviceType === 'preventivo')) {
      if (!startTime) {
        toast({
          title: "Error",
          description: "Debes indicar el tiempo de inicio para este tipo de servicio",
          variant: "destructive",
        });
        return;
      }
      
      const startDate = new Date(startTime);
      const minDate = new Date();
      minDate.setHours(minDate.getHours() + 48);
      
      if (startDate < minDate) {
        toast({
          title: "Error",
          description: "El tiempo de inicio debe ser al menos 48 horas desde ahora",
          variant: "destructive",
        });
        return;
      }
    }

    // Validar tiempo de inicio para proyecto
    if (!isDraft && serviceType === 'proyecto' && !startTime) {
      toast({
        title: "Error",
        description: "Debes indicar cuándo deseas iniciar el proyecto",
        variant: "destructive",
      });
      return;
    }

    const requestNumber = editingRequest?.requestNumber || `SOL-${Date.now().toString().slice(-6)}`;
    
    // Determinar prioridad: 1=emergencia, 2=correctivo, 3=preventivo, 4=proyecto
    const priorityMap: { [key in ServiceType]: number } = {
      emergencia: 1,
      correctivo: 2,
      preventivo: 3,
      proyecto: 4,
    };
    
    const request: Request = {
      id: editingRequest?.id || crypto.randomUUID(),
      requestNumber,
      description,
      asset,
      location,
      serviceType,
      observations,
      deadline,
      startTime: serviceType !== 'emergencia' ? startTime : undefined,
      selectedProviders,
      status: isDraft ? 'draft' : 'sent',
      createdAt: editingRequest?.createdAt || new Date().toISOString(),
      createdBy: user?.email || '',
      priority: priorityMap[serviceType],
      assignments: editingRequest?.assignments || {},
      technicalVisitRequested: editingRequest?.technicalVisitRequested || {},
      quotes: editingRequest?.quotes || [],
      clientName,
      clientBranch,
      isPublic: selectedProviders.length === 0,
    };

    onSave(request, isDraft);
    
    toast({
      title: isDraft ? "Borrador guardado" : "Solicitud enviada",
      description: isDraft 
        ? "Tu solicitud ha sido guardada como borrador" 
        : `Solicitud enviada a ${selectedProviders.length} proveedor(es)`,
    });
    
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-4xl max-h-[90vh] overflow-y-auto">
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Nueva Solicitud</CardTitle>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Nro de solicitud</Label>
              <Input 
                value={editingRequest?.requestNumber || `SOL-${Date.now().toString().slice(-6)}`} 
                disabled 
                className="bg-muted"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="clientName">Nombre del Cliente *</Label>
              <Input
                id="clientName"
                value={clientName}
                onChange={(e) => setClientName(e.target.value)}
                placeholder="Ej: Transportes Unidos S.A."
                required
              />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="clientBranch">Sede o Sucursal *</Label>
              <Input
                id="clientBranch"
                value={clientBranch}
                onChange={(e) => setClientBranch(e.target.value)}
                placeholder="Ej: Lima Centro, Miraflores"
                required
              />
            </div>
            
            <div className="space-y-2">
              <Label htmlFor="deadline">Fecha límite de envío de cotizaciones *</Label>
              <Input
                id="deadline"
                type="date"
                value={deadline}
                onChange={(e) => setDeadline(e.target.value)}
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="description">Descripción *</Label>
            <Textarea
              id="description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describe el servicio requerido"
              rows={3}
              required
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="asset">Activo *</Label>
              <Input
                id="asset"
                value={asset}
                onChange={(e) => setAsset(e.target.value)}
                placeholder="Ej: Bus Mercedes Benz O500"
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="location">Ubicación *</Label>
              <Input
                id="location"
                value={location}
                onChange={(e) => setLocation(e.target.value)}
                placeholder="Ej: Terminal Central"
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="serviceType">Tipo de servicio *</Label>
            <Select value={serviceType} onValueChange={(value) => setServiceType(value as ServiceType)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="emergencia">Emergencia</SelectItem>
                <SelectItem value="correctivo">Correctivo</SelectItem>
                <SelectItem value="preventivo">Preventivo</SelectItem>
                <SelectItem value="proyecto">Proyecto</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="observations">Observaciones (opcional)</Label>
            <Textarea
              id="observations"
              value={observations}
              onChange={(e) => setObservations(e.target.value)}
              placeholder="Información adicional relevante"
              rows={2}
            />
          </div>

          {serviceType !== 'emergencia' && (
            <div className="space-y-2">
              <Label htmlFor="startTime">
                {serviceType === 'proyecto' 
                  ? 'Fecha deseada de inicio del proyecto *' 
                  : 'Fecha de inicio del servicio * (mínimo 48 horas)'}
              </Label>
              <Input
                id="startTime"
                type="datetime-local"
                value={startTime}
                onChange={(e) => setStartTime(e.target.value)}
                required
              />
              {(serviceType === 'correctivo' || serviceType === 'preventivo') && (
                <p className="text-xs text-muted-foreground">
                  El plazo mínimo es de 48 horas desde ahora
                </p>
              )}
            </div>
          )}

          {serviceType === 'emergencia' && (
            <div className="p-4 border border-red-500/20 bg-red-500/10 rounded-lg">
              <p className="text-sm text-red-600 dark:text-red-400 font-medium">
                ⚠️ Esta es una solicitud de emergencia. Los proveedores serán notificados inmediatamente.
              </p>
            </div>
          )}

          <div className="space-y-4">
            <Label>Seleccionar proveedores (máximo 5, opcional)</Label>
            <p className="text-xs text-muted-foreground">
              Si no seleccionas proveedores, tu solicitud será pública y cualquier proveedor podrá cotizar
            </p>
            <div className="border rounded-lg p-4 space-y-3 max-h-64 overflow-y-auto">
              {MOCK_PROVIDERS.map((provider) => {
                const providers = JSON.parse(localStorage.getItem('providers') || JSON.stringify(MOCK_PROVIDERS));
                const providerData = providers.find((p: any) => p.id === provider.id);
                const isCertified = providerData?.certified || false;
                
                return (
                  <div
                    key={provider.id}
                    className="flex items-start space-x-3 p-3 rounded-lg border hover:bg-accent/50 transition-colors"
                  >
                    <Checkbox
                      id={provider.id}
                      checked={selectedProviders.includes(provider.id)}
                      onCheckedChange={() => handleProviderToggle(provider.id)}
                    />
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <label htmlFor={provider.id} className="font-medium cursor-pointer">
                          {provider.name}
                        </label>
                        {isCertified && (
                          <Badge variant="default" className="text-xs">
                            Certificado
                          </Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground">{provider.email}</p>
                      <p className="text-xs text-muted-foreground mt-1">
                        {provider.specialties.join(', ')} • ⭐ {provider.rating}
                      </p>
                    </div>
                  </div>
                );
              })}
            </div>
            <p className="text-sm text-muted-foreground">
              Proveedores seleccionados: {selectedProviders.length}/5
            </p>
          </div>

          <div className="flex gap-3 justify-end pt-4 border-t">
            <Button variant="outline" onClick={onClose}>
              Cancelar
            </Button>
            <Button variant="outline" onClick={() => handleSubmit(true)}>
              Guardar como borrador
            </Button>
            <Button onClick={() => handleSubmit(false)}>
              Enviar a proveedores
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
