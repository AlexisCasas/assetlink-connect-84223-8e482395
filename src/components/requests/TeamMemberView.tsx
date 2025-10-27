import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { QuoteForm } from './QuoteForm';
import { FileText, Calendar, MapPin, Building2, Clock, CheckCircle, XCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { seedDatabase } from '@/lib/seedData';
import { useToast } from '@/hooks/use-toast';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';

interface AssignmentWithRequest {
  id: string;
  request_id: string;
  team_member_name: string;
  max_deadline: string;
  reason: string | null;
  status: 'pending' | 'accepted' | 'rejected';
  responded_at: string | null;
  rejection_reason: string | null;
  request: {
    id: string;
    request_number: string;
    description: string;
    asset: string;
    location: string;
    service_type: string;
    created_at: string;
    observations: string | null;
    client_name: string | null;
  };
}

export const TeamMemberView = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [assignments, setAssignments] = useState<AssignmentWithRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [showQuoteForm, setShowQuoteForm] = useState(false);
  const [selectedAssignment, setSelectedAssignment] = useState<AssignmentWithRequest | null>(null);
  const [showRejectDialog, setShowRejectDialog] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [rejectingAssignment, setRejectingAssignment] = useState<AssignmentWithRequest | null>(null);

  useEffect(() => {
    loadAssignments();
  }, [user]);

  const loadAssignments = async () => {
    try {
      setLoading(true);
      
      // Seed database with example data if empty
      await seedDatabase();

      // Load ALL assignments with their requests (no filtering by user for demo purposes)
      const { data, error } = await supabase
        .from('assignments')
        .select(`
          id,
          request_id,
          team_member_name,
          max_deadline,
          reason,
          status,
          responded_at,
          rejection_reason,
          requests (
            id,
            request_number,
            description,
            asset,
            location,
            service_type,
            created_at,
            observations,
            client_name
          )
        `)
        .order('max_deadline', { ascending: true });

      if (error) throw error;

      // Transform the data to match our interface
      const transformedData = (data || [])
        .filter(item => item.requests) // Only keep assignments with valid requests
        .map(item => ({
          id: item.id,
          request_id: item.request_id,
          team_member_name: item.team_member_name,
          max_deadline: item.max_deadline,
          reason: item.reason,
          status: item.status as 'pending' | 'accepted' | 'rejected',
          responded_at: item.responded_at,
          rejection_reason: item.rejection_reason,
          request: Array.isArray(item.requests) ? item.requests[0] : item.requests
        }));

      setAssignments(transformedData);
    } catch (error) {
      console.error('Error loading assignments:', error);
      toast({
        title: 'Error',
        description: 'No se pudieron cargar las asignaciones',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  const handleAccept = async (assignment: AssignmentWithRequest) => {
    try {
      const { error } = await supabase
        .from('assignments')
        .update({
          status: 'accepted',
          responded_at: new Date().toISOString()
        })
        .eq('id', assignment.id);

      if (error) throw error;

      toast({
        title: 'Asignación aceptada',
        description: 'Ahora puedes crear la cotización',
      });

      loadAssignments();
    } catch (error) {
      console.error('Error accepting assignment:', error);
      toast({
        title: 'Error',
        description: 'No se pudo aceptar la asignación',
        variant: 'destructive',
      });
    }
  };

  const handleRejectClick = (assignment: AssignmentWithRequest) => {
    setRejectingAssignment(assignment);
    setRejectReason('');
    setShowRejectDialog(true);
  };

  const handleRejectConfirm = async () => {
    if (!rejectingAssignment || !rejectReason.trim()) {
      toast({
        title: 'Error',
        description: 'Debes proporcionar una razón para rechazar',
        variant: 'destructive',
      });
      return;
    }

    try {
      const { error } = await supabase
        .from('assignments')
        .update({
          status: 'rejected',
          responded_at: new Date().toISOString(),
          rejection_reason: rejectReason
        })
        .eq('id', rejectingAssignment.id);

      if (error) throw error;

      toast({
        title: 'Asignación rechazada',
        description: 'Se ha notificado al supervisor',
      });

      setShowRejectDialog(false);
      setRejectingAssignment(null);
      setRejectReason('');
      loadAssignments();
    } catch (error) {
      console.error('Error rejecting assignment:', error);
      toast({
        title: 'Error',
        description: 'No se pudo rechazar la asignación',
        variant: 'destructive',
      });
    }
  };

  const handleSaveQuote = async (quote: any) => {
    if (!selectedAssignment) return;

    try {
      const { error } = await supabase
        .from('quotes')
        .insert({
          request_id: selectedAssignment.request_id,
          provider_id: selectedAssignment.id, // Using assignment id as temporary provider reference
          team_member_id: selectedAssignment.id,
          description: quote.description || '',
          amount: quote.total || 0,
          status: 'draft'
        });

      if (error) throw error;

      toast({
        title: 'Cotización guardada',
        description: 'La cotización ha sido enviada exitosamente',
      });

      setShowQuoteForm(false);
      setSelectedAssignment(null);
      loadAssignments();
    } catch (error) {
      console.error('Error saving quote:', error);
      toast({
        title: 'Error',
        description: 'No se pudo guardar la cotización',
        variant: 'destructive',
      });
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

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'pending':
        return <Badge variant="outline" className="bg-yellow-500/10 text-yellow-600 border-yellow-500/20">Pendiente</Badge>;
      case 'accepted':
        return <Badge variant="outline" className="bg-green-500/10 text-green-600 border-green-500/20">Aceptada</Badge>;
      case 'rejected':
        return <Badge variant="outline" className="bg-red-500/10 text-red-600 border-red-500/20">Rechazada</Badge>;
      default:
        return null;
    }
  };

  if (loading) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">Cargando asignaciones...</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h2 className="text-2xl font-bold">Mis Asignaciones</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Solicitudes asignadas para cotizar
          </p>
        </div>
        <Badge variant="outline" className="text-lg px-4 py-2">
          {assignments.length} asignación(es)
        </Badge>
      </div>

      {assignments.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <FileText className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <p className="text-muted-foreground">No tienes solicitudes asignadas</p>
            <p className="text-sm text-muted-foreground mt-2">
              Las solicitudes asignadas por tu supervisor aparecerán aquí
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {assignments.map((assignment) => {
            const request = assignment.request;
            
            return (
              <Card key={assignment.id} className="hover:shadow-lg transition-shadow">
                <CardHeader>
                  <div className="flex justify-between items-start gap-4">
                    <div className="flex-1">
                      <CardTitle className="text-lg">{request.request_number}</CardTitle>
                      <p className="text-sm text-muted-foreground mt-1">
                        Cliente: {request.client_name || 'No especificado'}
                      </p>
                    </div>
                    <div className="flex gap-2 flex-wrap justify-end">
                      <Badge className={getServiceTypeColor(request.service_type)}>
                        {getServiceTypeText(request.service_type)}
                      </Badge>
                      {getStatusBadge(assignment.status)}
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="p-3 bg-primary/5 border border-primary/20 rounded-lg">
                    <div className="flex items-center gap-2 text-sm">
                      <Clock className="w-4 h-4" />
                      <span className="text-muted-foreground">Fecha límite:</span>
                      <span className="font-medium text-primary">
                        {new Date(assignment.max_deadline).toLocaleDateString('es-ES', {
                          day: '2-digit',
                          month: 'long',
                          year: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit'
                        })}
                      </span>
                    </div>
                    {assignment.reason && (
                      <p className="text-xs text-muted-foreground mt-2">
                        Motivo de asignación: {assignment.reason}
                      </p>
                    )}
                    {assignment.rejection_reason && (
                      <div className="mt-2 p-2 bg-red-500/10 border border-red-500/20 rounded">
                        <p className="text-xs font-medium text-red-600">
                          Razón del rechazo: {assignment.rejection_reason}
                        </p>
                      </div>
                    )}
                  </div>

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
                  </div>

                  {request.observations && (
                    <div className="pt-3 border-t">
                      <p className="text-sm font-medium mb-1">Observaciones:</p>
                      <p className="text-sm text-muted-foreground">{request.observations}</p>
                    </div>
                  )}

                  <div className="pt-3 border-t flex justify-end gap-2">
                    {assignment.status === 'pending' && (
                      <>
                        <Button 
                          variant="outline"
                          onClick={() => handleRejectClick(assignment)}
                          className="gap-2"
                        >
                          <XCircle className="w-4 h-4" />
                          Rechazar
                        </Button>
                        <Button 
                          onClick={() => handleAccept(assignment)}
                          className="gap-2"
                        >
                          <CheckCircle className="w-4 h-4" />
                          Aceptar
                        </Button>
                      </>
                    )}
                    {assignment.status === 'accepted' && (
                      <Button 
                        onClick={() => {
                          setSelectedAssignment(assignment);
                          setShowQuoteForm(true);
                        }}
                      >
                        Crear cotización
                      </Button>
                    )}
                    {assignment.status === 'rejected' && (
                      <Badge variant="outline" className="text-red-600 border-red-600">
                        Rechazada
                      </Badge>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {showQuoteForm && selectedAssignment && (
        <QuoteForm
          request={{
            id: selectedAssignment.request.id,
            requestNumber: selectedAssignment.request.request_number,
            description: selectedAssignment.request.description,
            asset: selectedAssignment.request.asset,
            location: selectedAssignment.request.location,
            serviceType: selectedAssignment.request.service_type as any,
            deadline: selectedAssignment.max_deadline,
            selectedProviders: [],
            status: 'sent',
            createdAt: selectedAssignment.request.created_at,
            createdBy: selectedAssignment.request.client_name || 'Sistema',
            priority: 4,
          }}
          onClose={() => {
            setShowQuoteForm(false);
            setSelectedAssignment(null);
          }}
          onSave={handleSaveQuote}
        />
      )}

      <Dialog open={showRejectDialog} onOpenChange={setShowRejectDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rechazar asignación</DialogTitle>
            <DialogDescription>
              Por favor, explica por qué rechazas esta asignación. Esta información será enviada al supervisor.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="reject-reason">Razón del rechazo *</Label>
              <Textarea
                id="reject-reason"
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                placeholder="Ej: No tengo las herramientas necesarias para este trabajo"
                rows={4}
                className="resize-none"
              />
            </div>
          </div>
          <DialogFooter>
            <Button 
              variant="outline" 
              onClick={() => {
                setShowRejectDialog(false);
                setRejectingAssignment(null);
                setRejectReason('');
              }}
            >
              Cancelar
            </Button>
            <Button 
              variant="destructive"
              onClick={handleRejectConfirm}
              disabled={!rejectReason.trim()}
            >
              Confirmar rechazo
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
