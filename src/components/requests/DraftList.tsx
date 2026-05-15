import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { RequestForm } from './RequestForm';
import { Request } from '@/types/request';
import { FileText, Edit, Trash2, Eye } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Separator } from '@/components/ui/separator';
import { format } from 'date-fns';
import { es } from 'date-fns/locale';

export const DraftList = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [showForm, setShowForm] = useState(false);
  const [editingDraft, setEditingDraft] = useState<Request | undefined>();
  const [drafts, setDrafts] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [draftToDelete, setDraftToDelete] = useState<string | null>(null);
  const [showViewDialog, setShowViewDialog] = useState(false);
  const [selectedDraft, setSelectedDraft] = useState<Request | null>(null);
  const [draftDetails, setDraftDetails] = useState<any[]>([]);

  const loadDrafts = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('requests')
        .select('*')
        .eq('status', 'draft')
        .eq('created_by', user?.email || '')
        .order('created_at', { ascending: false });

      if (error) throw error;

      const transformedDrafts: Request[] = (data || []).map((req: any) => ({
        id: req.id,
        requestNumber: req.request_number,
        title: req.title,
        description: req.description,
        asset: req.asset,
        location: req.location,
        serviceType: req.service_type,
        observations: req.observations,
        images: req.image_urls || [],
        documents: req.document_urls || [],
        deadline: req.deadline,
        startTime: req.start_time,
        selectedProviders: [],
        status: req.status,
        createdAt: req.created_at,
        createdBy: req.created_by,
        createdByUserId: req.created_by_user_id,
        createdByName: req.created_by_name,
        createdByEmail: req.created_by_email,
        priority: req.priority,
        clientName: req.client_name,
        clientBranch: req.client_branch,
        isPublic: req.is_public,
        city: req.city,
        store: req.store,
        branch: req.branch,
        branchId: req.branch_id,
        requiresVisit: req.requires_visit,
        visitDate: req.visit_date,
        minQuotes: req.min_quotes ?? 3,
      }));

      setDrafts(transformedDrafts);
    } catch (error) {
      console.error('Error loading drafts:', error);
      setDrafts([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (user?.email) {
      loadDrafts();
    }
  }, [user]);

  const loadDraftDetails = async (requestId: string) => {
    const { data } = await supabase
      .from('request_details')
      .select('*')
      .eq('request_id', requestId);
    setDraftDetails(data || []);
  };

  const handleViewDraft = async (draft: Request) => {
    setSelectedDraft(draft);
    await loadDraftDetails(draft.id);
    setShowViewDialog(true);
  };

  const handleSaveRequest = async (request: Request, isDraft: boolean) => {
    try {
      // Verificar si existe
      const { data: existing } = await supabase
        .from('requests')
        .select('id')
        .eq('id', request.id)
        .maybeSingle();

      if (existing) {
        // Actualizar
        const { error: requestError } = await supabase
          .from('requests')
          .update({
            title: request.title || null,
            description: request.description,
            service_type: request.serviceType,
            deadline: request.deadline,
            branch_id: request.branchId || null,
            city: request.city,
            store: request.store,
            branch: request.branch,
            location: request.location,
            requires_visit: request.requiresVisit,
            visit_date: request.visitDate || null,
            asset: request.asset,
            status: isDraft ? 'draft' : 'sent',
            is_public: request.isPublic,
            min_quotes: request.minQuotes ?? 3,
          })
          .eq('id', request.id);

        if (requestError) throw requestError;

        // Eliminar detalles antiguos
        await supabase
          .from('request_details')
          .delete()
          .eq('request_id', request.id);
      } else {
        // Crear nuevo
        const { error: insertError } = await supabase
          .from('requests')
          .insert({
            id: request.id,
            request_number: request.requestNumber,
            title: request.title || null,
            description: request.description,
            service_type: request.serviceType,
            deadline: request.deadline,
            branch_id: request.branchId || null,
            city: request.city,
            store: request.store,
            branch: request.branch,
            location: request.location,
            requires_visit: request.requiresVisit,
            visit_date: request.visitDate || null,
            asset: request.asset,
            status: isDraft ? 'draft' : 'sent',
            created_by: user?.email || '',
            created_by_user_id: user?.id || null,
            created_by_name: user?.name || null,
            created_by_email: user?.email || null,
            is_public: request.isPublic,
            client_name: request.clientName,
            client_branch: request.clientBranch,
            priority: request.priority,
            min_quotes: request.minQuotes ?? 3,
          });

        if (insertError) throw insertError;
      }

      // Insertar detalles
      if (request.details && request.details.length > 0) {
        const detailsToInsert = request.details.map(d => ({
          request_id: request.id,
          equipment: d.equipment || null,
          sub_equipment: d.subEquipment || null,
          area: d.area || null,
          sub_area: d.subArea || null,
          activities: d.activities || null,
          relevant_materials: d.relevantMaterials || null,
          quantity: d.quantity || null,
          unit_measure: d.unitMeasure || null,
          observation: d.observation || null,
          responsible_user: d.responsibleUser || null,
          delegate_type: d.delegateType || null,
        }));

        await supabase
          .from('request_details')
          .insert(detailsToInsert);
      }

      toast({
        title: isDraft ? "Borrador guardado" : "Solicitud enviada",
        description: isDraft 
          ? "Tu solicitud ha sido guardada como borrador" 
          : "La solicitud ha sido enviada correctamente",
      });

      setShowForm(false);
      setEditingDraft(undefined);
      loadDrafts();
    } catch (error) {
      console.error('Error saving draft:', error);
      toast({
        title: "Error",
        description: "No se pudo guardar la solicitud",
        variant: "destructive",
      });
    }
  };

  const handleDelete = async () => {
    if (!draftToDelete) return;

    try {
      // Eliminar detalles primero
      await supabase
        .from('request_details')
        .delete()
        .eq('request_id', draftToDelete);

      // Eliminar la solicitud
      const { error } = await supabase
        .from('requests')
        .delete()
        .eq('id', draftToDelete);

      if (error) throw error;

      toast({
        title: "Borrador eliminado",
        description: "El borrador ha sido eliminado correctamente",
      });
      
      loadDrafts();
    } catch (error) {
      console.error('Error deleting draft:', error);
      toast({
        title: "Error",
        description: "No se pudo eliminar el borrador",
        variant: "destructive",
      });
    } finally {
      setDeleteDialogOpen(false);
      setDraftToDelete(null);
    }
  };

  const handleEdit = async (draft: Request) => {
    // Cargar detalles
    const { data: detailsData } = await supabase
      .from('request_details')
      .select('*')
      .eq('request_id', draft.id);

    const details = (detailsData || []).map((d: any) => ({
      equipment: d.equipment || '',
      subEquipment: d.sub_equipment || '',
      area: d.area || '',
      subArea: d.sub_area || '',
      activities: d.activities || '',
      relevantMaterials: d.relevant_materials || '',
      quantity: d.quantity,
      unitMeasure: d.unit_measure || '',
      observation: d.observation || '',
      responsibleUser: d.responsible_user || '',
      delegateType: d.delegate_type || '',
    }));

    setEditingDraft({
      ...draft,
      details,
    });
    setShowForm(true);
  };

  const confirmDelete = (id: string) => {
    setDraftToDelete(id);
    setDeleteDialogOpen(true);
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

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold">Borradores</h2>
      </div>

      {loading ? (
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">Cargando borradores...</p>
          </CardContent>
        </Card>
      ) : drafts.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <FileText className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <p className="text-muted-foreground">No tienes borradores guardados</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {drafts.map((draft) => (
            <Card key={draft.id}>
              <CardHeader>
                <div className="flex justify-between items-start">
                  <div className="flex-1">
                    <div className="flex items-center gap-3">
                      <CardTitle className="text-lg">{draft.requestNumber}</CardTitle>
                      <Badge variant="outline">Borrador</Badge>
                    </div>
                    <p className="text-sm text-muted-foreground mt-1">{draft.description}</p>
                  </div>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() => handleViewDraft(draft)}
                      title="Ver"
                    >
                      <Eye className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() => handleEdit(draft)}
                      title="Editar"
                    >
                      <Edit className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() => confirmDelete(draft.id)}
                      title="Eliminar"
                      className="text-destructive hover:text-destructive"
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex items-center gap-4 text-sm">
                  <Badge className={getServiceTypeColor(draft.serviceType)}>
                    {getServiceTypeText(draft.serviceType)}
                  </Badge>
                  <span className="text-muted-foreground">
                    Creado: {new Date(draft.createdAt).toLocaleDateString()}
                  </span>
                  {draft.store && (
                    <span className="text-muted-foreground">Tienda: {draft.store}</span>
                  )}
                  {draft.branch && (
                    <span className="text-muted-foreground">Sede: {draft.branch}</span>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Diálogo de confirmación para eliminar */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>¿Eliminar borrador?</AlertDialogTitle>
            <AlertDialogDescription>
              Esta acción no se puede deshacer. El borrador será eliminado permanentemente.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
              Eliminar
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Diálogo para ver detalle */}
      <Dialog open={showViewDialog} onOpenChange={setShowViewDialog}>
        <DialogContent className="max-w-3xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Detalle del Borrador - {selectedDraft?.requestNumber}</DialogTitle>
          </DialogHeader>
          
          {selectedDraft && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="font-medium">Descripción:</span>
                  <p className="text-muted-foreground">{selectedDraft.description}</p>
                </div>
                <div>
                  <span className="font-medium">Tipo de Servicio:</span>
                  <Badge className={`ml-2 ${getServiceTypeColor(selectedDraft.serviceType)}`}>
                    {getServiceTypeText(selectedDraft.serviceType)}
                  </Badge>
                </div>
                <div>
                  <span className="font-medium">Ciudad:</span>
                  <p className="text-muted-foreground">{selectedDraft.city || '-'}</p>
                </div>
                <div>
                  <span className="font-medium">Tienda:</span>
                  <p className="text-muted-foreground">{selectedDraft.store || '-'}</p>
                </div>
                <div>
                  <span className="font-medium">Sede:</span>
                  <p className="text-muted-foreground">{selectedDraft.branch || '-'}</p>
                </div>
                <div>
                  <span className="font-medium">Fecha Límite:</span>
                  <p className="text-muted-foreground">
                    {selectedDraft.deadline 
                      ? format(new Date(selectedDraft.deadline), 'dd/MM/yyyy', { locale: es })
                      : '-'}
                  </p>
                </div>
              </div>

              {draftDetails.length > 0 && (
                <>
                  <Separator />
                  <div>
                    <h4 className="font-medium mb-3">Detalles de la Solicitud</h4>
                    <div className="space-y-3">
                      {draftDetails.map((detail, index) => (
                        <Card key={detail.id} className="p-3 bg-muted/30">
                          <p className="font-medium text-sm mb-2">Detalle #{index + 1}</p>
                          <div className="grid grid-cols-2 gap-2 text-sm">
                            {detail.equipment && (
                              <div><span className="text-muted-foreground">Equipo:</span> {detail.equipment}</div>
                            )}
                            {detail.area && (
                              <div><span className="text-muted-foreground">Área:</span> {detail.area}</div>
                            )}
                            {detail.activities && (
                              <div className="col-span-2"><span className="text-muted-foreground">Actividades:</span> {detail.activities}</div>
                            )}
                          </div>
                        </Card>
                      ))}
                    </div>
                  </div>
                </>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {showForm && (
        <RequestForm
          onClose={() => {
            setShowForm(false);
            setEditingDraft(undefined);
          }}
          onSave={handleSaveRequest}
          editingRequest={editingDraft}
        />
      )}
    </div>
  );
};
