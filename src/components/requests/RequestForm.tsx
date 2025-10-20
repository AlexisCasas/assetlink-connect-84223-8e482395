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
  const [selectedProviders, setSelectedProviders] = useState<string[]>(editingRequest?.selectedProviders || []);

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
    if (!description || !asset || !location || !deadline || (!isDraft && selectedProviders.length === 0)) {
      toast({
        title: "Error",
        description: isDraft 
          ? "Por favor completa los campos obligatorios" 
          : "Por favor completa todos los campos y selecciona al menos un proveedor",
        variant: "destructive",
      });
      return;
    }

    const requestNumber = editingRequest?.requestNumber || `SOL-${Date.now().toString().slice(-6)}`;
    
    const request: Request = {
      id: editingRequest?.id || crypto.randomUUID(),
      requestNumber,
      description,
      asset,
      location,
      serviceType,
      observations,
      deadline,
      selectedProviders,
      status: isDraft ? 'draft' : 'sent',
      createdAt: editingRequest?.createdAt || new Date().toISOString(),
      createdBy: user?.email || '',
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

          <div className="space-y-4">
            <Label>Seleccionar proveedores (máximo 5) *</Label>
            <div className="border rounded-lg p-4 space-y-3 max-h-64 overflow-y-auto">
              {MOCK_PROVIDERS.map((provider) => (
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
                    <label htmlFor={provider.id} className="font-medium cursor-pointer">
                      {provider.name}
                    </label>
                    <p className="text-sm text-muted-foreground">{provider.email}</p>
                    <p className="text-xs text-muted-foreground mt-1">
                      {provider.specialties.join(', ')} • ⭐ {provider.rating}
                    </p>
                  </div>
                </div>
              ))}
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
