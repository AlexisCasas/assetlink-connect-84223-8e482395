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
import { persistRequest } from '@/lib/requestPersistence';
import {
  deleteDelegatedDraft,
  fetchDelegatedRequest,
  fetchDelegatedRequests,
  loadDelegatedRequestForEdit,
  loadDirectRequestForEdit,
  mapRequestRow,
} from '@/lib/requestData';
import { useDirectRequestScope, type RequestScope } from '@/hooks/useRequestScope';
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

interface DraftListProps {
  /** Direct (default, historic) or delegated (Facility Manager, 9C.4): the FM
   * only ever sees and operates its OWN drafts for the operated client. */
  scope?: RequestScope;
}

export const DraftList = ({ scope }: DraftListProps = {}) => {
  const { user } = useAuth();
  const { toast } = useToast();
  const directScope = useDirectRequestScope();
  const requestScope = scope ?? directScope;
  const isDelegated = requestScope.mode === 'facility_manager';
  const organizationId = requestScope.organizationId;
  const [knownProviders, setKnownProviders] = useState<{ organizationId: string; organizationName: string }[]>([]);
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
    if (!organizationId) {
      setDrafts([]);
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      if (isDelegated) {
        setDrafts(await fetchDelegatedRequests(organizationId, 'drafts'));
        return;
      }
      const { data, error } = await supabase
        .from('requests')
        .select('*')
        .eq('status', 'draft')
        .eq('organization_id', organizationId)
        .order('created_at', { ascending: false });

      if (error) throw error;

      // Mapeo completo compartido con RequestList (antes faltaban el activo,
      // el tipo, los contactos, la visita y la convocatoria).
      const transformedDrafts: Request[] = (data || []).map(mapRequestRow);

      setDrafts(transformedDrafts);
    } catch (error) {
      console.error('Error loading drafts:', error);
      setDrafts([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { loadDrafts(); }, [user, organizationId, isDelegated]);

  const loadDraftDetails = async (requestId: string) => {
    if (isDelegated) {
      setDraftDetails(organizationId ? (await fetchDelegatedRequest(organizationId, requestId))?.detailRows ?? [] : []);
      return;
    }
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
    if (!organizationId) {
      toast({ title: 'Organización requerida', description: 'Selecciona una organización activa antes de guardar.', variant: 'destructive' });
      return;
    }

    try {
      // Misma persistencia que RequestList (src/lib/requestPersistence.ts):
      // borrador -> audiencia -> 'sent', nunca a medio camino. Antes este
      // listado escribía is_public y el estado directamente, sin sincronizar
      // las invitaciones.
      await persistRequest({
        request,
        isDraft,
        organizationId,
        actor: { id: user?.id, email: user?.email, name: user?.name },
        mode: isDelegated ? 'delegated' : 'direct',
      });

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
        description: error instanceof Error && error.message ? error.message : "No se pudo guardar la solicitud",
        variant: "destructive",
      });
    }
  };

  const handleDelete = async () => {
    if (!draftToDelete) return;

    try {
      if (isDelegated) {
        await deleteDelegatedDraft(organizationId!, draftToDelete);
      } else {
        // Eliminar detalles primero
        await supabase
          .from('request_details')
          .delete()
          .eq('request_id', draftToDelete);

        // Eliminar la solicitud
        const { error } = await supabase
          .from('requests')
          .delete()
          .eq('id', draftToDelete)
          .eq('organization_id', organizationId!);

        if (error) throw error;
      }

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
    try {
      // Detalle + invitaciones actuales (una convocatoria privada no se
      // pierde al reabrir el borrador).
      if (isDelegated) {
        const loaded = await loadDelegatedRequestForEdit(organizationId!, draft.id);
        setKnownProviders(loaded.knownProviders);
        setEditingDraft(loaded.request);
      } else {
        setEditingDraft(await loadDirectRequestForEdit(draft));
      }
      setShowForm(true);
    } catch (error) {
      toast({ title: 'No se pudo abrir el borrador', description: error instanceof Error ? error.message : undefined, variant: 'destructive' });
    }
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
        <h2 className="text-2xl font-bold">{isDelegated ? `Mis borradores para ${requestScope.organizationName ?? 'el cliente'}` : 'Borradores'}</h2>
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
            <p className="text-muted-foreground">
              {organizationId
                ? 'No tienes borradores guardados'
                : 'Selecciona una organización activa para ver tus borradores'}
            </p>
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
            setKnownProviders([]);
          }}
          onSave={handleSaveRequest}
          editingRequest={editingDraft}
          scope={requestScope}
          knownProviders={knownProviders}
        />
      )}
    </div>
  );
};
