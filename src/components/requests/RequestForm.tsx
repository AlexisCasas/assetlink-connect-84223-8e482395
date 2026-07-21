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
import { Request, ServiceType, ClientBranch } from '@/types/request';
import { Badge } from '@/components/ui/badge';
import { X, Upload, Search, CheckCircle2, Plus, Trash2, Pencil, CheckCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Separator } from '@/components/ui/separator';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ScrollArea, ScrollBar } from '@/components/ui/scroll-area';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';

interface RequestFormProps {
  onClose: () => void;
  onSave: (request: Request, isDraft: boolean) => Promise<void>;
  editingRequest?: Request;
}

interface RequestDetail {
  id: string;
  equipment: string;
  subEquipment: string;
  area: string;
  subArea: string;
  activities: string;
  relevantMaterials: string;
  quantity: string;
  unitMeasure: string;
  observation: string;
  responsibleUser: string;
  delegateType: string;
  attachments: File[];
}

const EQUIPMENT_OPTIONS = ['CÁMARA CONGELADOS PESCADOS 01', 'ESCALERA DE AVIÓN 03', 'ESCALERA DE AVIÓN # 01'];
const SUB_EQUIPMENT_OPTIONS = ['EXTRACTOR 02', 'EXTRACTOR 03'];
const AREA_OPTIONS = ['Transtienda', 'Almacén', 'Sala de Ventas'];
const SUB_AREA_OPTIONS = ['Congelados', 'Abarrotes', 'Electro'];

const createEmptyDetail = (): RequestDetail => ({
  id: crypto.randomUUID(),
  equipment: '',
  subEquipment: '',
  area: '',
  subArea: '',
  activities: '',
  relevantMaterials: '',
  quantity: '',
  unitMeasure: '',
  observation: '',
  responsibleUser: '',
  delegateType: '',
  attachments: [],
});

export const RequestForm = ({ onClose, onSave, editingRequest }: RequestFormProps) => {
  const { user, currentOrganization } = useAuth();
  const { toast } = useToast();
  const currentOrganizationId = currentOrganization?.id;
  
  // Formatear fecha para input date
  const formatDateForInput = (dateString: string | undefined) => {
    if (!dateString) return '';
    try {
      const date = new Date(dateString);
      return date.toISOString().split('T')[0];
    } catch {
      return '';
    }
  };
  
  // Cabecera
  const [title, setTitle] = useState(editingRequest?.title || '');
  const [description, setDescription] = useState(editingRequest?.description || '');
  const [serviceType, setServiceType] = useState<ServiceType>(editingRequest?.serviceType || 'correctivo');
  const [deadline, setDeadline] = useState(formatDateForInput(editingRequest?.deadline));
  const [branchId, setBranchId] = useState<string>(editingRequest?.branchId || '');
  const [city, setCity] = useState(editingRequest?.city || '');
  const [site, setSite] = useState(editingRequest?.branch || '');
  const [branches, setBranches] = useState<ClientBranch[]>([]);
  const [requiresVisit, setRequiresVisit] = useState(editingRequest?.requiresVisit || false);
  const [visitDate, setVisitDate] = useState(formatDateForInput(editingRequest?.visitDate));
  const [minQuotes, setMinQuotes] = useState<number>(editingRequest?.minQuotes ?? 3);
  
  // Detalle (1 a muchos) - inicializar con datos existentes o vacío
  const initialDetails = editingRequest?.details?.length 
    ? editingRequest.details.map(d => ({
        id: crypto.randomUUID(),
        equipment: d.equipment || '',
        subEquipment: d.subEquipment || '',
        area: d.area || '',
        subArea: d.subArea || '',
        activities: d.activities || '',
        relevantMaterials: d.relevantMaterials || '',
        quantity: d.quantity?.toString() || '',
        unitMeasure: d.unitMeasure || '',
        observation: d.observation || '',
        responsibleUser: d.responsibleUser || '',
        delegateType: d.delegateType || '',
        attachments: [] as File[],
      }))
    : [];
  
  const [details, setDetails] = useState<RequestDetail[]>(initialDetails);
  const [editingDetailId, setEditingDetailId] = useState<string | null>(null);
  const [isDetailDialogOpen, setIsDetailDialogOpen] = useState(false);
  const [currentDetail, setCurrentDetail] = useState<RequestDetail | null>(null);
  
  // Proveedores
  const [selectedProviders, setSelectedProviders] = useState<string[]>(editingRequest?.selectedProviders || []);
  const [providers, setProviders] = useState<any[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterCertified, setFilterCertified] = useState<'all' | 'certified' | 'non-certified'>('all');
  const [filterSpecialty, setFilterSpecialty] = useState<string>('all');
  const [availableSpecialties, setAvailableSpecialties] = useState<string[]>([]);
  
  // Usuarios del cliente para encargado
  const [clientUsers, setClientUsers] = useState<string[]>([]);

  useEffect(() => {
    fetchProviders();
    if (currentOrganizationId) {
      fetchBranches(currentOrganizationId);
    } else {
      setBranches([]);
    }
    // Simular usuarios del cliente (en producción vendría de la base de datos)
    setClientUsers(['Juan Pérez', 'María García', 'Carlos López', 'Ana Rodríguez']);
  }, [currentOrganizationId]);

  const fetchBranches = async (organizationId: string) => {
    const { data } = await supabase
      .from('client_branches')
      .select('*')
      .eq('organization_id', organizationId)
      .eq('is_active', true)
      .order('name');
    const list: ClientBranch[] = (data || []).map((b: any) => ({
      id: b.id, name: b.name, city: b.city, site: b.site, address: b.address, isActive: b.is_active,
    }));
    setBranches(list);
  };

  const handleBranchChange = (id: string) => {
    setBranchId(id);
    const b = branches.find(x => x.id === id);
    if (b) {
      setCity(b.city || '');
      setSite(b.site || '');
      if (!b.city || !b.site) {
        toast({
          title: 'Sucursal incompleta',
          description: 'Esta sucursal no tiene Ciudad o Sede configurada. Edítala desde Sucursales.',
          variant: 'destructive',
        });
      }
    } else {
      setCity('');
      setSite('');
    }
  };

  const fetchProviders = async () => {
    const { data } = await supabase.from('providers').select('*').order('name');
    setProviders(data || []);
    
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

  const addDetail = () => {
    const newDetail = createEmptyDetail();
    setCurrentDetail(newDetail);
    setEditingDetailId(null);
    setIsDetailDialogOpen(true);
  };

  const editDetail = (detail: RequestDetail) => {
    setCurrentDetail({ ...detail });
    setEditingDetailId(detail.id);
    setIsDetailDialogOpen(true);
  };

  const removeDetail = (id: string) => {
    setDetails(details.filter(d => d.id !== id));
  };

  const updateDetail = (id: string, field: keyof RequestDetail, value: any) => {
    setDetails(details.map(d => d.id === id ? { ...d, [field]: value } : d));
  };

  const saveDetailFromDialog = () => {
    if (!currentDetail) return;
    
    if (editingDetailId) {
      setDetails(details.map(d => d.id === editingDetailId ? currentDetail : d));
    } else {
      setDetails([...details, currentDetail]);
    }
    setIsDetailDialogOpen(false);
    setCurrentDetail(null);
    setEditingDetailId(null);
  };

  const updateCurrentDetail = (field: keyof RequestDetail, value: any) => {
    if (currentDetail) {
      setCurrentDetail({ ...currentDetail, [field]: value });
    }
  };

  const handleDetailAttachmentChange = (detailId: string, e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      const newFiles = Array.from(e.target.files);
      const detail = details.find(d => d.id === detailId);
      if (detail && detail.attachments.length + newFiles.length > 5) {
        toast({
          title: 'Límite excedido',
          description: 'Solo puedes subir un máximo de 5 anexos por detalle',
          variant: 'destructive',
        });
        return;
      }
      updateDetail(detailId, 'attachments', [...(detail?.attachments || []), ...newFiles]);
    }
  };

  const removeDetailAttachment = (detailId: string, index: number) => {
    const detail = details.find(d => d.id === detailId);
    if (detail) {
      updateDetail(detailId, 'attachments', detail.attachments.filter((_, i) => i !== index));
    }
  };

  const handleSubmit = async (isDraft: boolean) => {
    if (!title.trim()) {
      toast({ title: 'Falta el título', description: 'Ingresa el título de la solicitud', variant: 'destructive' });
      return;
    }
    if (!branchId) {
      toast({ title: 'Falta la sucursal', description: 'Selecciona una sucursal', variant: 'destructive' });
      return;
    }
    if (!description || !deadline) {
      toast({
        title: "Error",
        description: "Completa la descripción y la fecha de entrega",
        variant: "destructive",
      });
      return;
    }

    if (requiresVisit && !visitDate) {
      toast({
        title: "Error",
        description: "Por favor indica la fecha de visita técnica",
        variant: "destructive",
      });
      return;
    }

    if (!isDraft && selectedProviders.length === 0) {
      const confirmed = window.confirm(
        "No has seleccionado ningún proveedor. Tu solicitud será publicada como solicitud pública para que cualquier proveedor pueda enviar una cotización. ¿Deseas continuar?"
      );
      if (!confirmed) return;
    }

    const requestNumber = editingRequest?.requestNumber || `SOL-${Date.now().toString().slice(-6)}`;
    
    const priorityMap: { [key in ServiceType]: number } = {
      emergencia: 1,
      correctivo: 2,
      preventivo: 3,
      proyecto: 4,
    };
    
    const request: Request = {
      id: editingRequest?.id || crypto.randomUUID(),
      requestNumber,
      title: title.trim(),
      description,
      asset: details[0]?.equipment || '',
      location: `${city} - ${site}`,
      serviceType,
      observations: '',
      deadline,
      startTime: undefined,
      selectedProviders,
      status: isDraft ? 'draft' : 'sent',
      createdAt: editingRequest?.createdAt || new Date().toISOString(),
      createdBy: user?.email || '',
      createdByUserId: editingRequest?.createdByUserId || user?.id,
      createdByName: editingRequest?.createdByName || user?.name,
      createdByEmail: editingRequest?.createdByEmail || user?.email,
      priority: priorityMap[serviceType],
      assignments: editingRequest?.assignments || {},
      technicalVisitRequested: editingRequest?.technicalVisitRequested || {},
      quotes: editingRequest?.quotes || [],
      clientName: branches.find(b => b.id === branchId)?.name || '',
      clientBranch: site,
      isPublic: selectedProviders.length === 0,
      // Nuevos campos
      city,
      store: site,
      branch: site,
      branchId,
      requiresVisit,
      visitDate: requiresVisit ? visitDate : undefined,
      minQuotes,
      details: details.map(d => ({
        equipment: d.equipment,
        subEquipment: d.subEquipment,
        area: d.area,
        subArea: d.subArea,
        activities: d.activities,
        relevantMaterials: d.relevantMaterials,
        quantity: d.quantity ? parseFloat(d.quantity) : undefined,
        unitMeasure: d.unitMeasure,
        observation: d.observation,
        responsibleUser: d.responsibleUser,
        delegateType: d.delegateType,
      })),
    };

    try {
      await onSave(request, isDraft);
    } catch (error) {
      console.error('Error saving request:', error);
      toast({
        title: "Error",
        description: "No se pudo guardar la solicitud",
        variant: "destructive",
      });
    }
  };

  return (
    <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-5xl max-h-[90vh] overflow-y-auto">
        <CardHeader className="flex flex-row items-center justify-between sticky top-0 bg-card z-10">
          <CardTitle>Nueva Solicitud</CardTitle>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* CABECERA */}
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-primary">Datos de Cabecera</h3>
            
            {/* Fila 1: Título / Nro / Tipo */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label htmlFor="title">Título de la solicitud *</Label>
                <Input
                  id="title"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Ej: Mantenimiento preventivo equipos tienda Marina"
                  maxLength={200}
                  required
                />
              </div>
              <div className="space-y-2">
                <Label>Nro de solicitud</Label>
                <Input
                  value={editingRequest?.requestNumber || `SOL-${Date.now().toString().slice(-6)}`}
                  disabled
                  className="bg-muted"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="serviceType">Tipo de servicio *</Label>
                <Select value={serviceType} onValueChange={(value) => setServiceType(value as ServiceType)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent className="bg-popover">
                    <SelectItem value="emergencia">Emergencia</SelectItem>
                    <SelectItem value="correctivo">Correctivo</SelectItem>
                    <SelectItem value="preventivo">Preventivo</SelectItem>
                    <SelectItem value="proyecto">Proyecto</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            {/* Fila 2: Fecha entrega / Sucursal / Ciudad */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label htmlFor="deadline">Fecha de Entrega de Cotizaciones *</Label>
                <Input
                  id="deadline"
                  type="date"
                  value={deadline}
                  onChange={(e) => setDeadline(e.target.value)}
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="branchId">Sucursal *</Label>
                <Select value={branchId} onValueChange={handleBranchChange}>
                  <SelectTrigger>
                    <SelectValue placeholder={branches.length === 0 ? 'No hay sucursales' : 'Selecciona sucursal'} />
                  </SelectTrigger>
                  <SelectContent className="bg-popover">
                    {branches.map((b) => (
                      <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="city">Ciudad</Label>
                <Input id="city" value={city} readOnly className="bg-muted" placeholder="Auto desde sucursal" />
              </div>
            </div>

            {/* Fila 3: Sede / Creador / Min cotizaciones */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label htmlFor="site">Sede</Label>
                <Input id="site" value={site} readOnly className="bg-muted" placeholder="Auto desde sucursal" />
              </div>
              <div className="space-y-2">
                <Label>Creador</Label>
                <Input
                  value={user?.name ? `${user.name} (${user.email})` : (user?.email || '')}
                  disabled
                  className="bg-muted"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="minQuotes">Cotizaciones mínimas requeridas *</Label>
                <Input
                  id="minQuotes"
                  type="number"
                  min={1}
                  max={20}
                  value={minQuotes}
                  onChange={(e) => setMinQuotes(Math.max(1, parseInt(e.target.value) || 3))}
                  required
                />
                <p className="text-xs text-muted-foreground">Los precios se mostrarán al alcanzar este número</p>
              </div>
            </div>

            {/* Descripción */}
            <div className="space-y-2">
              <Label htmlFor="description">Descripción *</Label>
              <Textarea
                id="description"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Describe el servicio requerido"
                rows={2}
                required
              />
            </div>

            {/* Visita técnica */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="requiresVisit"
                  checked={requiresVisit}
                  onCheckedChange={(checked) => setRequiresVisit(checked as boolean)}
                />
                <Label htmlFor="requiresVisit" className="cursor-pointer">¿Requiere visita técnica?</Label>
              </div>

              {requiresVisit && (
                <div className="space-y-2">
                  <Label htmlFor="visitDate">Fecha Visita Técnica *</Label>
                  <Input
                    id="visitDate"
                    type="date"
                    value={visitDate}
                    onChange={(e) => setVisitDate(e.target.value)}
                    required
                  />
                </div>
              )}
            </div>
          </div>

          <Separator />

          {/* DETALLE EN TABLA */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-semibold text-primary">Detalle de la Solicitud</h3>
              <Button type="button" variant="outline" size="sm" onClick={addDetail}>
                <Plus className="w-4 h-4 mr-2" />
                Agregar Fila
              </Button>
            </div>

            {details.length === 0 ? (
              <div className="text-center py-8 text-muted-foreground border rounded-lg">
                <p>No hay detalles agregados.</p>
                <Button type="button" variant="link" onClick={addDetail}>
                  Agregar el primer detalle
                </Button>
              </div>
            ) : (
              <ScrollArea className="w-full whitespace-nowrap border rounded-lg">
                <div className="min-w-max">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="min-w-[50px]">#</TableHead>
                        <TableHead className="min-w-[180px]">Equipo</TableHead>
                        <TableHead className="min-w-[130px]">Subequipo</TableHead>
                        <TableHead className="min-w-[100px]">Área</TableHead>
                        <TableHead className="min-w-[100px]">Subárea</TableHead>
                        <TableHead className="min-w-[150px]">Actividades</TableHead>
                        <TableHead className="min-w-[130px]">Materiales</TableHead>
                        <TableHead className="min-w-[80px]">Cantidad</TableHead>
                        <TableHead className="min-w-[70px]">U.M</TableHead>
                        <TableHead className="min-w-[120px]">Observación</TableHead>
                        <TableHead className="min-w-[110px]">Encargado</TableHead>
                        <TableHead className="min-w-[90px]">Delegado</TableHead>
                        <TableHead className="min-w-[100px] text-center">Acciones</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {details.map((detail, index) => (
                        <TableRow key={detail.id}>
                          <TableCell className="font-medium">{index + 1}</TableCell>
                          <TableCell className="max-w-[180px] truncate" title={detail.equipment}>{detail.equipment || '-'}</TableCell>
                          <TableCell className="max-w-[130px] truncate" title={detail.subEquipment}>{detail.subEquipment || '-'}</TableCell>
                          <TableCell>{detail.area || '-'}</TableCell>
                          <TableCell>{detail.subArea || '-'}</TableCell>
                          <TableCell className="max-w-[150px] truncate" title={detail.activities}>{detail.activities || '-'}</TableCell>
                          <TableCell className="max-w-[130px] truncate" title={detail.relevantMaterials}>{detail.relevantMaterials || '-'}</TableCell>
                          <TableCell>{detail.quantity || '-'}</TableCell>
                          <TableCell>{detail.unitMeasure || '-'}</TableCell>
                          <TableCell className="max-w-[120px] truncate" title={detail.observation}>{detail.observation || '-'}</TableCell>
                          <TableCell>{detail.responsibleUser || '-'}</TableCell>
                          <TableCell>{detail.delegateType || '-'}</TableCell>
                          <TableCell>
                            <div className="flex items-center justify-center gap-1">
                              <Button 
                                type="button" 
                                variant="ghost" 
                                size="sm"
                                onClick={() => editDetail(detail)}
                              >
                                <Pencil className="w-4 h-4" />
                              </Button>
                              <Button 
                                type="button" 
                                variant="ghost" 
                                size="sm"
                                onClick={() => removeDetail(detail.id)}
                                className="text-destructive hover:text-destructive"
                              >
                                <Trash2 className="w-4 h-4" />
                              </Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
                <ScrollBar orientation="horizontal" />
              </ScrollArea>
            )}
          </div>

          {/* Dialog para editar/agregar detalle */}
          <Dialog open={isDetailDialogOpen} onOpenChange={(open) => {
            setIsDetailDialogOpen(open);
            if (!open) {
              setCurrentDetail(null);
              setEditingDetailId(null);
            }
          }}>
            <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
              <DialogHeader>
                <DialogTitle>
                  {editingDetailId ? 'Editar Detalle' : 'Agregar Nuevo Detalle'}
                </DialogTitle>
              </DialogHeader>
              
              {currentDetail && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 py-4">
                  <div className="space-y-2">
                    <Label>Equipo</Label>
                    <Select 
                      value={currentDetail.equipment} 
                      onValueChange={(value) => updateCurrentDetail('equipment', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecciona equipo" />
                      </SelectTrigger>
                      <SelectContent className="bg-popover">
                        {EQUIPMENT_OPTIONS.map((eq) => (
                          <SelectItem key={eq} value={eq}>{eq}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label>Subequipo</Label>
                    <Select 
                      value={currentDetail.subEquipment} 
                      onValueChange={(value) => updateCurrentDetail('subEquipment', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecciona subequipo" />
                      </SelectTrigger>
                      <SelectContent className="bg-popover">
                        {SUB_EQUIPMENT_OPTIONS.map((seq) => (
                          <SelectItem key={seq} value={seq}>{seq}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label>Área</Label>
                    <Select 
                      value={currentDetail.area} 
                      onValueChange={(value) => updateCurrentDetail('area', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecciona área" />
                      </SelectTrigger>
                      <SelectContent className="bg-popover">
                        {AREA_OPTIONS.map((a) => (
                          <SelectItem key={a} value={a}>{a}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label>Subárea</Label>
                    <Select 
                      value={currentDetail.subArea} 
                      onValueChange={(value) => updateCurrentDetail('subArea', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecciona subárea" />
                      </SelectTrigger>
                      <SelectContent className="bg-popover">
                        {SUB_AREA_OPTIONS.map((sa) => (
                          <SelectItem key={sa} value={sa}>{sa}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label>Partidas o Actividades</Label>
                    <Input
                      value={currentDetail.activities}
                      onChange={(e) => updateCurrentDetail('activities', e.target.value)}
                      placeholder="Describe las actividades"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Materiales Relevantes</Label>
                    <Input
                      value={currentDetail.relevantMaterials}
                      onChange={(e) => updateCurrentDetail('relevantMaterials', e.target.value)}
                      placeholder="Materiales necesarios"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Cantidad</Label>
                    <Input
                      type="number"
                      step="0.01"
                      value={currentDetail.quantity}
                      onChange={(e) => updateCurrentDetail('quantity', e.target.value)}
                      placeholder="0.00"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>U.M (Unidad de Medida)</Label>
                    <Input
                      value={currentDetail.unitMeasure}
                      onChange={(e) => updateCurrentDetail('unitMeasure', e.target.value)}
                      placeholder="Ej: Unidad, Metro, Kg"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Observación</Label>
                    <Input
                      value={currentDetail.observation}
                      onChange={(e) => updateCurrentDetail('observation', e.target.value)}
                      placeholder="Observaciones adicionales"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Encargado</Label>
                    <Select 
                      value={currentDetail.responsibleUser} 
                      onValueChange={(value) => updateCurrentDetail('responsibleUser', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecciona encargado" />
                      </SelectTrigger>
                      <SelectContent className="bg-popover">
                        {clientUsers.map((u) => (
                          <SelectItem key={u} value={u}>{u}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label>Delegado</Label>
                    <Select 
                      value={currentDetail.delegateType} 
                      onValueChange={(value) => updateCurrentDetail('delegateType', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecciona tipo" />
                      </SelectTrigger>
                      <SelectContent className="bg-popover">
                        <SelectItem value="Tercero">Tercero</SelectItem>
                        <SelectItem value="Propio">Propio</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2 md:col-span-2">
                    <Label>Anexos (máx. 5)</Label>
                    <Input
                      type="file"
                      multiple
                      onChange={(e) => {
                        if (e.target.files && currentDetail) {
                          const newFiles = Array.from(e.target.files);
                          if (currentDetail.attachments.length + newFiles.length > 5) {
                            toast({
                              title: 'Límite excedido',
                              description: 'Solo puedes subir un máximo de 5 anexos por detalle',
                              variant: 'destructive',
                            });
                            return;
                          }
                          updateCurrentDetail('attachments', [...currentDetail.attachments, ...newFiles]);
                        }
                      }}
                      disabled={currentDetail.attachments.length >= 5}
                    />
                    {currentDetail.attachments.length > 0 && (
                      <div className="space-y-1 mt-2">
                        {currentDetail.attachments.map((file, i) => (
                          <div key={i} className="flex items-center justify-between p-2 bg-muted rounded text-sm">
                            <span className="truncate flex-1">{file.name}</span>
                            <Button 
                              type="button"
                              variant="ghost" 
                              size="sm" 
                              onClick={() => {
                                updateCurrentDetail('attachments', currentDetail.attachments.filter((_, idx) => idx !== i));
                              }}
                            >
                              <X className="h-4 w-4" />
                            </Button>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              )}

              <div className="flex justify-end gap-2 pt-4">
                <Button variant="outline" onClick={() => setIsDetailDialogOpen(false)}>
                  Cancelar
                </Button>
                <Button onClick={saveDetailFromDialog}>
                  {editingDetailId ? 'Guardar Cambios' : 'Agregar'}
                </Button>
              </div>
            </DialogContent>
          </Dialog>

          <Separator />

          {/* PROVEEDORES */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <Label>Seleccionar proveedores (máximo 5, opcional)</Label>
                <p className="text-xs text-muted-foreground">
                  Si no seleccionas proveedores, tu solicitud será pública y cualquier proveedor podrá cotizar
                </p>
              </div>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => {
                  const allProviderIds = filteredProviders.map(p => p.id);
                  setSelectedProviders(allProviderIds);
                  if (allProviderIds.length > 5) {
                    toast({
                      title: "Proveedores seleccionados",
                      description: `Se han seleccionado los ${allProviderIds.length} proveedores disponibles`,
                    });
                  }
                }}
                disabled={filteredProviders.length === 0}
              >
                <CheckCheck className="h-4 w-4 mr-2" />
                Seleccionar todos
              </Button>
            </div>
            
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
                  <SelectValue placeholder="Certificación" />
                </SelectTrigger>
                <SelectContent className="bg-popover">
                  <SelectItem value="all">Todos</SelectItem>
                  <SelectItem value="certified">Certificados</SelectItem>
                  <SelectItem value="non-certified">No certificados</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {selectedProviders.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {selectedProviders.map(providerId => {
                  const provider = providers.find(p => p.id === providerId);
                  return provider ? (
                    <Badge key={providerId} variant="secondary" className="pl-2 pr-1 py-1">
                      {provider.name}
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-4 w-4 ml-1 hover:bg-transparent"
                        onClick={() => handleProviderToggle(providerId)}
                      >
                        <X className="h-3 w-3" />
                      </Button>
                    </Badge>
                  ) : null;
                })}
              </div>
            )}

            <div className="border rounded-lg max-h-48 overflow-y-auto">
              {filteredProviders.length === 0 ? (
                <div className="p-4 text-center text-muted-foreground text-sm">
                  No se encontraron proveedores
                </div>
              ) : (
                filteredProviders.map(provider => (
                  <div
                    key={provider.id}
                    className={`flex items-center justify-between p-3 border-b last:border-b-0 cursor-pointer hover:bg-muted/50 transition-colors ${
                      selectedProviders.includes(provider.id) ? 'bg-primary/10' : ''
                    }`}
                    onClick={() => handleProviderToggle(provider.id)}
                  >
                    <div className="flex items-center gap-3">
                      <div className={`w-5 h-5 rounded border flex items-center justify-center ${
                        selectedProviders.includes(provider.id) 
                          ? 'bg-primary border-primary' 
                          : 'border-muted-foreground'
                      }`}>
                        {selectedProviders.includes(provider.id) && (
                          <CheckCircle2 className="w-4 h-4 text-primary-foreground" />
                        )}
                      </div>
                      <div>
                        <p className="font-medium text-sm">{provider.name}</p>
                        <p className="text-xs text-muted-foreground">{provider.email}</p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      {provider.certified && (
                        <Badge variant="outline" className="text-xs">Certificado</Badge>
                      )}
                      <Badge variant="secondary" className="text-xs">
                        ★ {provider.rating?.toFixed(1) || '0.0'}
                      </Badge>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>

          {/* BOTONES */}
          <div className="flex flex-col sm:flex-row gap-2 pt-4">
            <Button variant="outline" onClick={onClose} className="flex-1 sm:flex-none">
              Cancelar
            </Button>
            <div className="flex-1" />
            {/* Solo mostrar botón de borrador si no es una solicitud ya enviada */}
            {editingRequest?.status !== 'sent' && (
              <Button 
                variant="secondary" 
                onClick={() => handleSubmit(true)}
                className="flex-1 sm:flex-none"
              >
                Guardar como borrador
              </Button>
            )}
            <Button 
              onClick={() => handleSubmit(false)}
              className="flex-1 sm:flex-none"
            >
              {editingRequest?.status === 'sent' ? 'Guardar cambios' : 'Enviar a Proveedores'}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
