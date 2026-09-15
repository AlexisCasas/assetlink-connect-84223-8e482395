import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Checkbox } from '@/components/ui/checkbox';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { useToast } from '@/hooks/use-toast';
import { Request, RequestType, ServiceType, ClientBranch, VisitScheduleMode, ConvocationMode } from '@/types/request';
import { X, Plus, Trash2, Pencil } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Separator } from '@/components/ui/separator';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ScrollArea, ScrollBar } from '@/components/ui/scroll-area';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { RequestAssetPicker } from './RequestAssetPicker';
import { RequestAssetSummary } from './RequestAssetSummary';
import { RequestProviderSelector } from './RequestProviderSelector';
import { TechnicianSelect } from '@/components/members/TechnicianSelect';
import { CoordinationContactSelect } from '@/components/members/CoordinationContactSelect';
import { useCoordinationContacts } from '@/hooks/useCoordinationContacts';
import { ASSET_NODE_TYPE_LABELS } from '@/lib/assetLabels';
import { generateUuid } from '@/lib/uuid';
import type { Asset } from '@/types/asset';

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

const createEmptyDetail = (): RequestDetail => ({
  id: generateUuid(),
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
  const { user, currentOrganization, currentMembership } = useAuth();
  const { toast } = useToast();
  const currentOrganizationId = currentOrganization?.id;
  const { contacts: coordinationContacts } = useCoordinationContacts(currentOrganizationId);
  
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
  const [requestType, setRequestType] = useState<RequestType>(editingRequest?.requestType || 'external');
  // Once a request has left 'draft' (sent/quoted/etc.), request_type is
  // frozen server-side by trg_requests_lock_request_type — mirrored here
  // so the user sees why before submitting, not just a failed save.
  const isRequestTypeLocked = !!editingRequest && editingRequest.status !== 'draft';
  const [internalResponsibleMemberId, setInternalResponsibleMemberId] = useState<string>(editingRequest?.internalResponsibleMemberId || '');
  const [assetId, setAssetId] = useState<string>(editingRequest?.assetId || '');
  const [selectedAsset, setSelectedAsset] = useState<Asset | null>(null);
  const [assetPath, setAssetPath] = useState<string>('');
  const [assetTouched, setAssetTouched] = useState(false);
  const [requiresVisit, setRequiresVisit] = useState(editingRequest?.requiresVisit || false);
  const [visitDate, setVisitDate] = useState(formatDateForInput(editingRequest?.visitDate));
  const [visitScheduleMode, setVisitScheduleMode] = useState<VisitScheduleMode>(
    editingRequest?.visitScheduleMode || 'scheduled'
  );
  const [visitContactMemberId, setVisitContactMemberId] = useState<string>(editingRequest?.visitContactMemberId || '');
  const [minQuotes, setMinQuotes] = useState<number>(editingRequest?.minQuotes ?? 3);

  // Contacto de coordinación: por defecto, el miembro correspondiente al
  // usuario creador cuando existe (solicitud nueva); una solicitud existente
  // conserva lo que ya tenía guardado.
  const [coordinationContactMemberId, setCoordinationContactMemberId] = useState<string>(
    editingRequest?.coordinationContactMemberId || currentMembership?.id || ''
  );
  const [coordinationContactName, setCoordinationContactName] = useState<string>(editingRequest?.coordinationContactName || '');
  const [coordinationContactEmail, setCoordinationContactEmail] = useState<string>(editingRequest?.coordinationContactEmail || '');
  const [coordinationContactTouched, setCoordinationContactTouched] = useState(false);

  // Dirección del servicio: snapshot de client_branches.address al
  // seleccionar sucursal. Una solicitud histórica conserva su propio snapshot
  // aunque la sucursal cambie de dirección después.
  const [serviceAddress, setServiceAddress] = useState<string>(editingRequest?.serviceAddress || '');

  // Convocatoria (solo external). Reemplaza la regla implícita "0
  // proveedores = pública": ahora es una elección explícita.
  const [convocationMode, setConvocationMode] = useState<ConvocationMode>(
    editingRequest ? (editingRequest.isPublic === false ? 'private' : 'public') : 'public'
  );
  const [selectedProviderOrganizationIds, setSelectedProviderOrganizationIds] = useState<string[]>(
    editingRequest?.selectedProviderOrganizationIds || []
  );
  
  // Detalle (1 a muchos) - inicializar con datos existentes o vacío
  const initialDetails = editingRequest?.details?.length 
    ? editingRequest.details.map(d => ({
        id: generateUuid(),
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
  
  useEffect(() => {
    if (currentOrganizationId) {
      fetchBranches(currentOrganizationId);
    } else {
      setBranches([]);
    }
  }, [currentOrganizationId]);

  // Default the coordination contact's name/email snapshot to the caller's
  // own membership once the real directory loads, only for a brand-new
  // request that hasn't been touched yet — an existing request keeps
  // whatever snapshot it already had.
  useEffect(() => {
    if (editingRequest || coordinationContactTouched) return;
    if (!coordinationContactMemberId) return;
    const own = coordinationContacts.find((c) => c.memberId === coordinationContactMemberId);
    if (own) {
      setCoordinationContactName(own.name);
      setCoordinationContactEmail(own.email);
    }
  }, [coordinationContacts, coordinationContactMemberId, coordinationContactTouched, editingRequest]);

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
      setServiceAddress(b.address || '');
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
      setServiceAddress('');
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
    if (!currentOrganization) {
      toast({
        title: 'Organización requerida',
        description: 'Selecciona una organización activa antes de guardar la solicitud.',
        variant: 'destructive',
      });
      return;
    }

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

    if (requiresVisit && visitScheduleMode === 'scheduled' && !visitDate) {
      toast({
        title: "Error",
        description: "Por favor indica la fecha de visita técnica, o cambia la programación a \"Por coordinar\".",
        variant: "destructive",
      });
      return;
    }

    if (requestType === 'external' && !isDraft && convocationMode === 'private' && selectedProviderOrganizationIds.length === 0) {
      toast({
        title: 'Selecciona al menos un proveedor',
        description: 'Selecciona al menos un proveedor para enviar una invitación privada.',
        variant: 'destructive',
      });
      return;
    }

    const requestNumber = editingRequest?.requestNumber || `SOL-${Date.now().toString().slice(-6)}`;
    
    const priorityMap: { [key in ServiceType]: number } = {
      emergencia: 1,
      correctivo: 2,
      preventivo: 3,
      proyecto: 4,
    };

    // A freshly touched asset picker overrides the legacy text (selected or
    // cleared); an untouched pre-existing selection keeps whatever text is
    // already saved instead of falling back to the per-detail equipment.
    // The full hierarchical path (not just "<Tipo>: <Nombre>") is what gets
    // snapshotted here — it's the only asset context a provider (who has no
    // RLS to read `assets` directly) ever sees, in RequestList, in
    // ProviderRequestList and in this request's own detail dialog.
    const assetDisplayText = assetTouched
      ? (selectedAsset ? (assetPath || `${ASSET_NODE_TYPE_LABELS[selectedAsset.nodeType]}: ${selectedAsset.name}`) : (details[0]?.equipment || ''))
      : (editingRequest?.asset || details[0]?.equipment || '');
    // request_details still has legacy equipment/sub_equipment/area/sub_area
    // columns; every line now mirrors the single request-level asset instead
    // of asking the user to redundantly re-type it per row.
    const detailEquipmentFallback = selectedAsset ? selectedAsset.name : assetDisplayText;
    const detailAreaFallback = selectedAsset && assetPath ? assetPath : '';

    const request: Request = {
      id: editingRequest?.id || generateUuid(),
      organizationId: editingRequest?.organizationId || currentOrganization.id,
      requestNumber,
      title: title.trim(),
      description,
      asset: assetDisplayText,
      assetId: assetId || undefined,
      requestType,
      internalResponsibleMemberId: requestType === 'internal' ? (internalResponsibleMemberId || undefined) : undefined,
      location: `${city} - ${site}`,
      serviceType,
      observations: '',
      deadline,
      startTime: undefined,
      selectedProviders: [],
      // Editing a request that already left draft must never reset its
      // status — only a still-draft request (new or existing) actually
      // toggles between 'draft' and 'sent' from this form.
      status: editingRequest && editingRequest.status !== 'draft'
        ? editingRequest.status
        : (isDraft ? 'draft' : 'sent'),
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
      isPublic: requestType === 'external' ? convocationMode === 'public' : false,
      // Nuevos campos
      city,
      store: site,
      branch: site,
      branchId,
      requiresVisit,
      visitDate: requiresVisit && visitScheduleMode === 'scheduled' ? visitDate : undefined,
      visitScheduleMode: requiresVisit ? visitScheduleMode : undefined,
      visitContactMemberId: requiresVisit ? (visitContactMemberId || coordinationContactMemberId || undefined) : undefined,
      minQuotes,
      coordinationContactMemberId: coordinationContactMemberId || undefined,
      coordinationContactName: coordinationContactName || undefined,
      coordinationContactEmail: coordinationContactEmail || undefined,
      serviceAddress: serviceAddress || undefined,
      convocationMode: requestType === 'external' ? convocationMode : undefined,
      selectedProviderOrganizationIds: requestType === 'external' && convocationMode === 'private' ? selectedProviderOrganizationIds : [],
      details: details.map(d => ({
        equipment: detailEquipmentFallback,
        subEquipment: '',
        area: detailAreaFallback,
        subArea: '',
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

            {/* Fila 1.5: Tipo de gestión */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label htmlFor="requestType">Tipo de gestión *</Label>
                <Select
                  value={requestType}
                  onValueChange={(value) => setRequestType(value as RequestType)}
                  disabled={isRequestTypeLocked}
                >
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent className="bg-popover">
                    <SelectItem value="external">Externa</SelectItem>
                    <SelectItem value="internal">Interna</SelectItem>
                  </SelectContent>
                </Select>
                <p className="text-xs text-muted-foreground">
                  {isRequestTypeLocked
                    ? 'El tipo de gestión no puede modificarse después de enviar la solicitud.'
                    : requestType === 'internal'
                      ? 'Se ejecuta con tu propio equipo, sin proveedores externos ni marketplace.'
                      : 'Se cotiza y ejecuta con proveedores externos.'}
                </p>
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
                <Label htmlFor="serviceAddress">Dirección del servicio</Label>
                <Input
                  id="serviceAddress"
                  value={serviceAddress}
                  readOnly
                  className="bg-muted"
                  placeholder="Auto desde sucursal"
                />
              </div>
              <div className="space-y-2">
                <Label>Creador</Label>
                <Input
                  value={user?.name ? `${user.name} (${user.email})` : (user?.email || '')}
                  disabled
                  className="bg-muted"
                />
              </div>
              {requestType === 'external' && (
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
              )}
            </div>

            {requestType === 'internal' && (
              <div className="space-y-2">
                <Label>Responsable interno / técnico (opcional)</Label>
                {currentOrganization ? (
                  <TechnicianSelect
                    organizationId={currentOrganization.id}
                    value={internalResponsibleMemberId || null}
                    onChange={(memberId) => setInternalResponsibleMemberId(memberId || '')}
                    emptyMessage="Puedes asignar responsable al generar la OT o posteriormente."
                  />
                ) : (
                  <p className="text-xs text-muted-foreground">Puedes asignar responsable al generar la OT o posteriormente.</p>
                )}
              </div>
            )}

            {/* Activo asociado */}
            <RequestAssetPicker
              assetId={assetId}
              onChange={(id, asset, path) => { setAssetId(id); setSelectedAsset(asset); setAssetPath(path); setAssetTouched(true); }}
            />

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
          </div>

          <Separator />

          {/* COORDINACIÓN */}
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-primary">Coordinación</h3>

            <CoordinationContactSelect
              organizationId={currentOrganizationId}
              value={coordinationContactMemberId || null}
              onChange={(memberId, contact) => {
                setCoordinationContactMemberId(memberId || '');
                setCoordinationContactName(contact?.name || '');
                setCoordinationContactEmail(contact?.email || '');
                setCoordinationContactTouched(true);
              }}
            />

            <div className="space-y-3">
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="requiresVisit"
                  checked={requiresVisit}
                  onCheckedChange={(checked) => {
                    const next = checked as boolean;
                    setRequiresVisit(next);
                    if (!next) { setVisitDate(''); }
                  }}
                />
                <Label htmlFor="requiresVisit" className="cursor-pointer">¿Requiere visita técnica?</Label>
              </div>

              {requiresVisit && (
                <div className="space-y-4 rounded-lg border p-4">
                  <div className="space-y-2">
                    <Label>Programación</Label>
                    <RadioGroup
                      value={visitScheduleMode}
                      onValueChange={(value) => setVisitScheduleMode(value as VisitScheduleMode)}
                      className="flex flex-col gap-2 sm:flex-row sm:gap-6"
                    >
                      <div className="flex items-center space-x-2">
                        <RadioGroupItem value="scheduled" id="visit-scheduled" />
                        <Label htmlFor="visit-scheduled" className="cursor-pointer font-normal">Fecha definida</Label>
                      </div>
                      <div className="flex items-center space-x-2">
                        <RadioGroupItem value="to_schedule" id="visit-to-schedule" />
                        <Label htmlFor="visit-to-schedule" className="cursor-pointer font-normal">Por coordinar</Label>
                      </div>
                    </RadioGroup>
                  </div>

                  {visitScheduleMode === 'scheduled' ? (
                    <div className="space-y-2 max-w-xs">
                      <Label htmlFor="visitDate">Fecha Visita Técnica *</Label>
                      <Input
                        id="visitDate"
                        type="date"
                        value={visitDate}
                        onChange={(e) => setVisitDate(e.target.value)}
                        required
                      />
                    </div>
                  ) : (
                    <p className="text-sm text-muted-foreground">
                      El proveedor deberá coordinar la visita con el contacto indicado.
                    </p>
                  )}

                  <CoordinationContactSelect
                    organizationId={currentOrganizationId}
                    value={visitContactMemberId || coordinationContactMemberId || null}
                    onChange={(memberId) => setVisitContactMemberId(memberId || '')}
                    label="Contacto de visita"
                  />
                </div>
              )}
            </div>
          </div>

          {requestType === 'external' && <Separator />}

          {/* CONVOCATORIA: solo aplica a solicitudes externas. Reemplaza la
              regla implícita "0 proveedores = pública" por una elección
              explícita; las internas no usan marketplace ni proveedores. */}
          {requestType === 'external' && (
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-primary">Convocatoria</h3>

            <RadioGroup
              value={convocationMode}
              onValueChange={(value) => setConvocationMode(value as ConvocationMode)}
              className="space-y-3"
            >
              <div className="flex items-start space-x-2 rounded-lg border p-3">
                <RadioGroupItem value="public" id="convocation-public" className="mt-1" />
                <Label htmlFor="convocation-public" className="cursor-pointer font-normal">
                  <span className="block font-medium text-foreground">Marketplace público</span>
                  <span className="block text-sm text-muted-foreground">
                    La solicitud podrá ser consultada por los proveedores habilitados en el marketplace.
                  </span>
                </Label>
              </div>
              <div className="flex items-start space-x-2 rounded-lg border p-3">
                <RadioGroupItem value="private" id="convocation-private" className="mt-1" />
                <Label htmlFor="convocation-private" className="cursor-pointer font-normal">
                  <span className="block font-medium text-foreground">Invitación privada</span>
                  <span className="block text-sm text-muted-foreground">
                    Solo los proveedores seleccionados podrán acceder y cotizar.
                  </span>
                </Label>
              </div>
            </RadioGroup>

            {convocationMode === 'private' && (
              <RequestProviderSelector
                selectedOrganizationIds={selectedProviderOrganizationIds}
                onChange={setSelectedProviderOrganizationIds}
              />
            )}
          </div>
          )}

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
                        <TableHead className="min-w-[220px]">Actividad / Partida</TableHead>
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
                          <TableCell className="max-w-[220px] truncate" title={detail.activities}>
                            {detail.activities || '-'}
                            {(detail.equipment || detail.area) && (
                              <p className="mt-0.5 truncate text-xs text-muted-foreground" title={[detail.equipment, detail.area].filter(Boolean).join(' · ')}>
                                {[detail.equipment, detail.area].filter(Boolean).join(' · ')}
                              </p>
                            )}
                          </TableCell>
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
                <DialogDescription className="sr-only">
                  Completa los datos del detalle de la solicitud.
                </DialogDescription>
              </DialogHeader>

              {assetId && (
                <RequestAssetSummary assetId={assetId} assetText={editingRequest?.asset} title="Detalle asociado a" />
              )}

              {currentDetail && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 py-4">
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
                        {coordinationContacts.map((contact) => (
                          <SelectItem key={contact.memberId} value={contact.name}>{contact.name}</SelectItem>
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

          {/* BOTONES */}
          <div className="flex flex-col sm:flex-row gap-2 pt-4">
            <Button variant="outline" onClick={onClose} className="flex-1 sm:flex-none">
              Cancelar
            </Button>
            <div className="flex-1" />
            {/* Solo mostrar botón de borrador para una solicitud nueva o que
                todavía sigue en draft — una vez enviada (sent/quoted/
                completed/anulado) ya no puede volver a draft. */}
            {(!editingRequest || editingRequest.status === 'draft') && (
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
              {editingRequest && editingRequest.status !== 'draft'
                ? 'Guardar cambios'
                : requestType === 'internal' ? 'Crear solicitud interna' : 'Enviar a Proveedores'}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
