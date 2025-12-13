import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Checkbox } from '@/components/ui/checkbox';
import { useToast } from '@/hooks/use-toast';
import { Request, ServiceType } from '@/types/request';
import { Badge } from '@/components/ui/badge';
import { X, Upload, Search, CheckCircle2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

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
  const [images, setImages] = useState<File[]>([]);
  const [documents, setDocuments] = useState<File[]>([]);
  const [providers, setProviders] = useState<any[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterCertified, setFilterCertified] = useState<'all' | 'certified' | 'non-certified'>('all');
  const [filterSpecialty, setFilterSpecialty] = useState<string>('all');
  const [availableSpecialties, setAvailableSpecialties] = useState<string[]>([]);

  useEffect(() => {
    fetchProviders();
  }, []);

  const fetchProviders = async () => {
    const { data } = await supabase.from('providers').select('*').order('name');
    setProviders(data || []);
    
    // Extract unique specialties from all providers
    const specialties = new Set<string>();
    (data || []).forEach((provider: any) => {
      if (provider.specialties && Array.isArray(provider.specialties)) {
        provider.specialties.forEach((specialty: string) => specialties.add(specialty));
      }
    });
    setAvailableSpecialties(Array.from(specialties).sort());
  };

  const filteredProviders = providers.filter(provider => {
    const matchesSearch = provider.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         provider.email.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesCertified = filterCertified === 'all' ||
                            (filterCertified === 'certified' && provider.certified) ||
                            (filterCertified === 'non-certified' && !provider.certified);
    const matchesSpecialty = filterSpecialty === 'all' ||
                            (provider.specialties && provider.specialties.includes(filterSpecialty));
    return matchesSearch && matchesCertified && matchesSpecialty;
  });

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      const newFiles = Array.from(e.target.files);
      if (images.length + newFiles.length > 5) {
        toast({
          title: 'Límite excedido',
          description: 'Solo puedes subir un máximo de 5 imágenes',
          variant: 'destructive',
        });
        return;
      }
      setImages([...images, ...newFiles]);
    }
  };

  const handleDocumentChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      const newFiles = Array.from(e.target.files);
      if (documents.length + newFiles.length > 5) {
        toast({
          title: 'Límite excedido',
          description: 'Solo puedes subir un máximo de 5 documentos',
          variant: 'destructive',
        });
        return;
      }
      setDocuments([...documents, ...newFiles]);
    }
  };

  const removeImage = (index: number) => {
    setImages(images.filter((_, i) => i !== index));
  };

  const removeDocument = (index: number) => {
    setDocuments(documents.filter((_, i) => i !== index));
  };

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
            <div className="space-y-2">
              <Label htmlFor="images">Imágenes (opcional, máx. 5)</Label>
              <Input
                id="images"
                type="file"
                multiple
                accept="image/*"
                onChange={handleImageChange}
                disabled={images.length >= 5}
              />
              {images.length > 0 && (
                <div className="space-y-1 mt-2">
                  {images.map((file, index) => (
                    <div key={index} className="flex items-center justify-between p-2 bg-muted rounded text-sm">
                      <span className="truncate flex-1">{file.name}</span>
                      <Button variant="ghost" size="sm" onClick={() => removeImage(index)}>
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="space-y-2">
              <Label htmlFor="documents">Documentos (opcional, máx. 5)</Label>
              <Input
                id="documents"
                type="file"
                multiple
                accept=".pdf,.doc,.docx,.xls,.xlsx"
                onChange={handleDocumentChange}
                disabled={documents.length >= 5}
              />
              {documents.length > 0 && (
                <div className="space-y-1 mt-2">
                  {documents.map((file, index) => (
                    <div key={index} className="flex items-center justify-between p-2 bg-muted rounded text-sm">
                      <span className="truncate flex-1">{file.name}</span>
                      <Button variant="ghost" size="sm" onClick={() => removeDocument(index)}>
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>

          <div className="space-y-4">
            <Label>Seleccionar proveedores (máximo 5, opcional)</Label>
            <p className="text-xs text-muted-foreground">
              Si no seleccionas proveedores, tu solicitud será pública y cualquier proveedor podrá cotizar
            </p>
            
            <div className="flex flex-col md:flex-row gap-2">
              <div className="flex-1 relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Buscar por nombre o email..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-9"
                />
              </div>
              <Select value={filterSpecialty} onValueChange={setFilterSpecialty}>
                <SelectTrigger className="w-full md:w-[200px]">
                  <SelectValue placeholder="Especialidad" />
                </SelectTrigger>
                <SelectContent className="bg-popover">
                  <SelectItem value="all">Todas las especialidades</SelectItem>
                  {availableSpecialties.map((specialty) => (
                    <SelectItem key={specialty} value={specialty}>
                      {specialty}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select value={filterCertified} onValueChange={(value: any) => setFilterCertified(value)}>
                <SelectTrigger className="w-full md:w-[180px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent className="bg-popover">
                  <SelectItem value="all">Todos</SelectItem>
                  <SelectItem value="certified">Certificados</SelectItem>
                  <SelectItem value="non-certified">No certificados</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="border rounded-lg p-4 space-y-3 max-h-64 overflow-y-auto">
              {filteredProviders.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-4">
                  No se encontraron proveedores
                </p>
              ) : (
                filteredProviders.map((provider) => (
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
                        {provider.certified && (
                          <Badge variant="default" className="text-xs flex items-center gap-1">
                            <CheckCircle2 className="h-3 w-3" />
                            Certificado
                          </Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground">{provider.email}</p>
                      <p className="text-xs text-muted-foreground mt-1">
                        {provider.specialties?.join(', ') || 'Sin especialidades'} • ⭐ {provider.rating || 'N/A'}
                      </p>
                    </div>
                  </div>
                ))
              )}
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
