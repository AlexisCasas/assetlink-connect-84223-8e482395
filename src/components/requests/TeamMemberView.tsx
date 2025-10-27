import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { supabase } from '@/integrations/supabase/client';
import { seedDatabase } from '@/lib/seedData';
import { useToast } from '@/hooks/use-toast';
import { Search, Settings2, ArrowUpDown, Upload, FileText, X, Check } from 'lucide-react';
import { QuoteForm } from './QuoteForm';
import { TechnicalVisitDialog } from './TechnicalVisitDialog';
import { 
  Table, 
  TableBody, 
  TableCell, 
  TableHead, 
  TableHeader, 
  TableRow 
} from '@/components/ui/table';
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
} from '@/components/ui/dropdown-menu';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
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
  team_member_id: string;
  team_member_name: string;
  provider_id: string;
  max_deadline: string;
  reason: string | null;
  status: string;
  rejection_reason: string | null;
  responded_at: string | null;
  request: {
    request_number: string;
    description: string;
    asset: string;
    location: string;
    service_type: string;
    deadline: string;
    priority: number;
    client_name: string | null;
    client_branch: string | null;
    observations: string | null;
  };
}

type ColumnKey = 'ticket' | 'estado' | 'equipo' | 'operacion' | 'ubicacion' | 'prioridad' | 'asignado' | 'fecha_limite' | 'comentarios' | 'acciones';

interface ColumnConfig {
  key: ColumnKey;
  label: string;
  visible: boolean;
}

const DEFAULT_COLUMNS: ColumnConfig[] = [
  { key: 'ticket', label: '# Ticket', visible: true },
  { key: 'estado', label: 'Estado', visible: true },
  { key: 'equipo', label: 'Equipo', visible: true },
  { key: 'operacion', label: 'Operación', visible: true },
  { key: 'ubicacion', label: 'Ubicación', visible: true },
  { key: 'prioridad', label: 'Prior.', visible: true },
  { key: 'asignado', label: 'Asignado A', visible: true },
  { key: 'fecha_limite', label: 'Fecha Límite', visible: true },
  { key: 'comentarios', label: 'Comentarios', visible: true },
  { key: 'acciones', label: 'Acciones', visible: true },
];

export const TeamMemberView = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [assignments, setAssignments] = useState<AssignmentWithRequest[]>([]);
  const [filteredAssignments, setFilteredAssignments] = useState<AssignmentWithRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [showQuoteForm, setShowQuoteForm] = useState(false);
  const [selectedAssignment, setSelectedAssignment] = useState<AssignmentWithRequest | null>(null);
  const [showRejectDialog, setShowRejectDialog] = useState(false);
  const [rejectionReason, setRejectionReason] = useState('');
  const [assignmentToReject, setAssignmentToReject] = useState<string | null>(null);
  const [selectedAssignments, setSelectedAssignments] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [columns, setColumns] = useState<ColumnConfig[]>(DEFAULT_COLUMNS);
  const [sortBy, setSortBy] = useState<'max_deadline' | 'priority'>('max_deadline');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [showTechnicalVisitDialog, setShowTechnicalVisitDialog] = useState(false);
  const [selectedAssignmentForVisit, setSelectedAssignmentForVisit] = useState<AssignmentWithRequest | null>(null);

  useEffect(() => {
    loadAssignments();
  }, [user]);

  useEffect(() => {
    filterAndSortAssignments();
  }, [assignments, searchQuery, sortBy, sortOrder, statusFilter]);

  const loadAssignments = async () => {
    try {
      setLoading(true);
      
      // Seed database with example data if empty
      await seedDatabase();
      
      // Fetch ALL assignments - visible to all team members
      const { data: assignmentsData, error } = await supabase
        .from('assignments')
        .select(`
          *,
          request:requests(*)
        `)
        .order('max_deadline', { ascending: true });

      if (error) throw error;

      const transformedAssignments = (assignmentsData || []).map((a: any) => ({
        id: a.id,
        request_id: a.request_id,
        team_member_id: a.team_member_id,
        team_member_name: a.team_member_name,
        provider_id: a.provider_id,
        max_deadline: a.max_deadline,
        reason: a.reason,
        status: a.status,
        rejection_reason: a.rejection_reason,
        responded_at: a.responded_at,
        request: {
          request_number: a.request.request_number,
          description: a.request.description,
          asset: a.request.asset,
          location: a.request.location,
          service_type: a.request.service_type,
          deadline: a.request.deadline,
          priority: a.request.priority,
          client_name: a.request.client_name,
          client_branch: a.request.client_branch,
          observations: a.request.observations,
        },
      }));

      setAssignments(transformedAssignments);
    } catch (error) {
      console.error('Error fetching assignments:', error);
      toast({
        title: 'Error',
        description: 'No se pudieron cargar las asignaciones',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  const filterAndSortAssignments = () => {
    let filtered = [...assignments];

    // Search filter
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(a => 
        a.request.request_number.toLowerCase().includes(query) ||
        a.request.description.toLowerCase().includes(query) ||
        a.request.asset.toLowerCase().includes(query) ||
        a.request.location.toLowerCase().includes(query) ||
        a.team_member_name.toLowerCase().includes(query) ||
        (a.reason && a.reason.toLowerCase().includes(query)) ||
        (a.rejection_reason && a.rejection_reason.toLowerCase().includes(query))
      );
    }

    // Status filter
    if (statusFilter !== 'all') {
      filtered = filtered.filter(a => a.status === statusFilter);
    }

    // Sort
    filtered.sort((a, b) => {
      let compareValue = 0;
      
      if (sortBy === 'max_deadline') {
        compareValue = new Date(a.max_deadline).getTime() - new Date(b.max_deadline).getTime();
      } else if (sortBy === 'priority') {
        compareValue = a.request.priority - b.request.priority;
      }

      return sortOrder === 'asc' ? compareValue : -compareValue;
    });

    setFilteredAssignments(filtered);
  };

  const toggleColumn = (key: ColumnKey) => {
    setColumns(columns.map(col => 
      col.key === key ? { ...col, visible: !col.visible } : col
    ));
  };

  const isColumnVisible = (key: ColumnKey) => {
    return columns.find(col => col.key === key)?.visible ?? true;
  };

  const handleSelectAssignment = (assignmentId: string) => {
    setSelectedAssignments(prev => 
      prev.includes(assignmentId) 
        ? prev.filter(id => id !== assignmentId)
        : [...prev, assignmentId]
    );
  };

  const handleSelectAll = () => {
    if (selectedAssignments.length === filteredAssignments.length) {
      setSelectedAssignments([]);
    } else {
      setSelectedAssignments(filteredAssignments.map(a => a.id));
    }
  };

  const handleAccept = async (assignmentId: string) => {
    try {
      const { error } = await supabase
        .from('assignments')
        .update({ 
          status: 'accepted',
          responded_at: new Date().toISOString()
        })
        .eq('id', assignmentId);

      if (error) throw error;

      toast({
        title: 'Asignación aceptada',
        description: 'Ahora puedes crear una cotización para esta solicitud',
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

  const handleRejectClick = (assignmentId: string) => {
    setAssignmentToReject(assignmentId);
    setRejectionReason('');
    setShowRejectDialog(true);
  };

  const handleRejectConfirm = async () => {
    if (!assignmentToReject || !rejectionReason.trim()) {
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
          rejection_reason: rejectionReason
        })
        .eq('id', assignmentToReject);

      if (error) throw error;

      toast({
        title: 'Asignación rechazada',
        description: 'Se ha notificado al supervisor',
      });

      setShowRejectDialog(false);
      setAssignmentToReject(null);
      setRejectionReason('');
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
          provider_id: selectedAssignment.provider_id,
          team_member_id: selectedAssignment.team_member_id,
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
      emergencia: 'bg-red-500 hover:bg-red-600',
      correctivo: 'bg-orange-500 hover:bg-orange-600',
      preventivo: 'bg-blue-500 hover:bg-blue-600',
      proyecto: 'bg-purple-500 hover:bg-purple-600',
    };
    return colors[type as keyof typeof colors] || 'bg-gray-500';
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
        return { text: 'Pendiente', className: 'bg-yellow-500 hover:bg-yellow-600' };
      case 'accepted':
        return { text: 'Aceptada', className: 'bg-green-500 hover:bg-green-600' };
      case 'rejected':
        return { text: 'Rechazada', className: 'bg-red-500 hover:bg-red-600' };
      default:
        return { text: status, className: 'bg-gray-500' };
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
    <div className="p-6 space-y-4">
      <div className="flex justify-between items-center">
        <div>
          <h2 className="text-2xl font-bold">Mis Asignaciones</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Mostrando {filteredAssignments.length} de {assignments.length} asignación(es)
          </p>
        </div>
      </div>

      {/* Búsqueda y filtros */}
      <div className="flex gap-3 items-center flex-wrap">
        <div className="relative flex-1 min-w-[300px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Buscar por ticket, descripción, equipo, ubicación..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9"
          />
        </div>

        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-[180px]">
            <SelectValue placeholder="Estado" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos los estados</SelectItem>
            <SelectItem value="pending">Pendientes</SelectItem>
            <SelectItem value="accepted">Aceptadas</SelectItem>
            <SelectItem value="rejected">Rechazadas</SelectItem>
          </SelectContent>
        </Select>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="icon">
              <ArrowUpDown className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-[200px]">
            <DropdownMenuLabel>Ordenar por</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuRadioGroup value={sortBy} onValueChange={(v) => setSortBy(v as any)}>
              <DropdownMenuRadioItem value="max_deadline">
                Fecha límite
              </DropdownMenuRadioItem>
              <DropdownMenuRadioItem value="priority">
                Prioridad
              </DropdownMenuRadioItem>
            </DropdownMenuRadioGroup>
            <DropdownMenuSeparator />
            <DropdownMenuRadioGroup value={sortOrder} onValueChange={(v) => setSortOrder(v as any)}>
              <DropdownMenuRadioItem value="asc">Ascendente</DropdownMenuRadioItem>
              <DropdownMenuRadioItem value="desc">Descendente</DropdownMenuRadioItem>
            </DropdownMenuRadioGroup>
          </DropdownMenuContent>
        </DropdownMenu>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="icon">
              <Settings2 className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-[200px]">
            <DropdownMenuLabel>Columnas visibles</DropdownMenuLabel>
            <DropdownMenuSeparator />
            {columns.map(col => (
              <DropdownMenuCheckboxItem
                key={col.key}
                checked={col.visible}
                onCheckedChange={() => toggleColumn(col.key)}
                disabled={col.key === 'ticket'}
              >
                {col.label}
              </DropdownMenuCheckboxItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      {filteredAssignments.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">
              {searchQuery || statusFilter !== 'all'
                ? 'No se encontraron asignaciones con los filtros aplicados'
                : 'No tienes asignaciones'}
            </p>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-12">
                      <Checkbox
                        checked={selectedAssignments.length === filteredAssignments.length && filteredAssignments.length > 0}
                        onCheckedChange={handleSelectAll}
                      />
                    </TableHead>
                    {isColumnVisible('ticket') && <TableHead># Ticket</TableHead>}
                    {isColumnVisible('estado') && <TableHead>Estado</TableHead>}
                    {isColumnVisible('equipo') && <TableHead>Equipo</TableHead>}
                    {isColumnVisible('operacion') && <TableHead>Operación</TableHead>}
                    {isColumnVisible('ubicacion') && <TableHead>Ubicación</TableHead>}
                    {isColumnVisible('prioridad') && <TableHead>Prior.</TableHead>}
                    {isColumnVisible('asignado') && <TableHead>Asignado A</TableHead>}
                    {isColumnVisible('fecha_limite') && <TableHead>Fecha Límite</TableHead>}
                    {isColumnVisible('comentarios') && <TableHead>Comentarios</TableHead>}
                    {isColumnVisible('acciones') && <TableHead>Acciones</TableHead>}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredAssignments.map((assignment) => (
                    <TableRow key={assignment.id} className="hover:bg-muted/50">
                      <TableCell>
                        <Checkbox
                          checked={selectedAssignments.includes(assignment.id)}
                          onCheckedChange={() => handleSelectAssignment(assignment.id)}
                        />
                      </TableCell>
                      {isColumnVisible('ticket') && (
                        <TableCell className="font-medium text-primary">
                          {assignment.request.request_number}
                        </TableCell>
                      )}
                      {isColumnVisible('estado') && (
                        <TableCell>
                          <Badge className={getStatusBadge(assignment.status).className}>
                            {getStatusBadge(assignment.status).text}
                          </Badge>
                        </TableCell>
                      )}
                      {isColumnVisible('equipo') && (
                        <TableCell className="max-w-[150px] truncate">
                          {assignment.request.asset}
                        </TableCell>
                      )}
                      {isColumnVisible('operacion') && (
                        <TableCell>
                          <Badge className={getServiceTypeColor(assignment.request.service_type)}>
                            {getServiceTypeText(assignment.request.service_type)}
                          </Badge>
                        </TableCell>
                      )}
                      {isColumnVisible('ubicacion') && (
                        <TableCell>
                          <div className="flex flex-col text-sm">
                            <span>{assignment.request.client_name || '-'}</span>
                            <span className="text-xs text-muted-foreground">
                              {assignment.request.client_branch || '-'}
                            </span>
                          </div>
                        </TableCell>
                      )}
                      {isColumnVisible('prioridad') && (
                        <TableCell>
                          <Badge variant="outline">P{assignment.request.priority}</Badge>
                        </TableCell>
                      )}
                      {isColumnVisible('asignado') && (
                        <TableCell className="text-sm font-medium">
                          {assignment.team_member_name}
                        </TableCell>
                      )}
                      {isColumnVisible('fecha_limite') && (
                        <TableCell className="text-sm">
                          {new Date(assignment.max_deadline).toLocaleDateString('es-ES', {
                            day: '2-digit',
                            month: '2-digit',
                            year: 'numeric'
                          })}
                          <div className="text-xs text-muted-foreground">
                            {new Date(assignment.max_deadline).toLocaleTimeString('es-ES', {
                              hour: '2-digit',
                              minute: '2-digit'
                            })}
                          </div>
                        </TableCell>
                      )}
                      {isColumnVisible('comentarios') && (
                        <TableCell className="max-w-[200px]">
                          <div className="text-sm truncate" title={assignment.reason || assignment.rejection_reason || ''}>
                            {assignment.status === 'rejected' 
                              ? assignment.rejection_reason 
                              : assignment.reason || '-'}
                          </div>
                        </TableCell>
                      )}
                      {isColumnVisible('acciones') && (
                        <TableCell>
                          {assignment.status === 'pending' && (
                            <div className="flex gap-2">
                              <Button
                                size="sm"
                                variant="outline"
                                onClick={() => handleAccept(assignment.id)}
                              >
                                Aceptar
                              </Button>
                              <Button
                                size="sm"
                                variant="destructive"
                                onClick={() => handleRejectClick(assignment.id)}
                              >
                                Rechazar
                              </Button>
                            </div>
                          )}
                          {assignment.status === 'accepted' && (
                            <div className="flex gap-2">
                              <Button
                                size="sm"
                                onClick={() => {
                                  setSelectedAssignment(assignment);
                                  setShowQuoteForm(true);
                                }}
                              >
                                <FileText className="h-4 w-4 mr-1" />
                                Cotizar
                              </Button>
                              <Button
                                size="sm"
                                variant="outline"
                                onClick={() => {
                                  setSelectedAssignmentForVisit(assignment);
                                  setShowTechnicalVisitDialog(true);
                                }}
                              >
                                <Upload className="h-4 w-4 mr-1" />
                                Documentar Visita
                              </Button>
                            </div>
                          )}
                          {assignment.status === 'rejected' && (
                            <Badge variant="secondary" className="bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-100">
                              Rechazada
                            </Badge>
                          )}
                        </TableCell>
                      )}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      )}

      {showQuoteForm && selectedAssignment && (
        <QuoteForm
          request={{
            id: selectedAssignment.request_id,
            requestNumber: selectedAssignment.request.request_number,
            description: selectedAssignment.request.description,
            asset: selectedAssignment.request.asset,
            location: selectedAssignment.request.location,
            serviceType: selectedAssignment.request.service_type as any,
            deadline: selectedAssignment.request.deadline,
            selectedProviders: [],
            status: 'sent',
            createdAt: new Date().toISOString(),
            createdBy: 'system',
            priority: selectedAssignment.request.priority,
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
              Por favor, explica por qué rechazas esta asignación.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="reject-reason">Razón del rechazo *</Label>
              <Textarea
                id="reject-reason"
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                placeholder="Ej: No tengo las herramientas necesarias"
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
                setAssignmentToReject(null);
                setRejectionReason('');
              }}
            >
              Cancelar
            </Button>
            <Button 
              variant="destructive"
              onClick={handleRejectConfirm}
              disabled={!rejectionReason.trim()}
            >
              Confirmar rechazo
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {showTechnicalVisitDialog && selectedAssignmentForVisit && (
        <TechnicalVisitDialog
          open={showTechnicalVisitDialog}
          onClose={() => {
            setShowTechnicalVisitDialog(false);
            setSelectedAssignmentForVisit(null);
          }}
          requestId={selectedAssignmentForVisit.request_id}
          assignmentId={selectedAssignmentForVisit.id}
          teamMemberId={selectedAssignmentForVisit.team_member_id}
        />
      )}
    </div>
  );
};
