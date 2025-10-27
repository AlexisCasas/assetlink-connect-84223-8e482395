import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { AssignmentDialog } from './AssignmentDialog';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import { User, MessageSquare, FileText } from 'lucide-react';
import { 
  Table, 
  TableBody, 
  TableCell, 
  TableHead, 
  TableHeader, 
  TableRow 
} from '@/components/ui/table';

interface RequestData {
  id: string;
  request_number: string;
  description: string;
  asset: string;
  location: string;
  service_type: string;
  deadline: string;
  start_time: string | null;
  created_at: string;
  status: string;
  priority: number;
  client_name: string | null;
  client_branch: string | null;
  observations: string | null;
}

interface Assignment {
  team_member_name: string;
}

export const ProviderRequestList = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [requests, setRequests] = useState<RequestData[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedRequests, setSelectedRequests] = useState<string[]>([]);
  const [showAssignmentDialog, setShowAssignmentDialog] = useState(false);
  const [currentProvider, setCurrentProvider] = useState<any>(null);
  const [assignments, setAssignments] = useState<Record<string, Assignment>>({});

  useEffect(() => {
    fetchProviderAndRequests();
  }, [user]);

  const fetchProviderAndRequests = async () => {
    try {
      setLoading(true);
      
      // Get current provider
      const { data: providerData } = await supabase
        .from('providers')
        .select('*')
        .eq('email', user?.email)
        .single();

      if (!providerData) {
        setLoading(false);
        return;
      }

      setCurrentProvider(providerData);

      // Fetch ALL requests with status 'sent' - visible to all providers
      const { data: requestsData, error } = await supabase
        .from('requests')
        .select('*')
        .eq('status', 'sent')
        .order('priority', { ascending: true })
        .order('created_at', { ascending: false });

      if (error) throw error;

      setRequests(requestsData || []);

      // Fetch assignments for these requests
      if (requestsData && requestsData.length > 0) {
        const requestIds = requestsData.map(r => r.id);
        const { data: assignmentsData } = await supabase
          .from('assignments')
          .select('request_id, team_member_name')
          .in('request_id', requestIds);

        if (assignmentsData) {
          const assignmentsMap: Record<string, Assignment> = {};
          assignmentsData.forEach(a => {
            assignmentsMap[a.request_id] = { team_member_name: a.team_member_name };
          });
          setAssignments(assignmentsMap);
        }
      }
    } catch (error) {
      console.error('Error fetching requests:', error);
      toast({
        title: 'Error',
        description: 'No se pudieron cargar las solicitudes',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
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

  const handleSelectRequest = (requestId: string) => {
    setSelectedRequests(prev => 
      prev.includes(requestId) 
        ? prev.filter(id => id !== requestId)
        : [...prev, requestId]
    );
  };

  const handleSelectAll = () => {
    if (selectedRequests.length === requests.length) {
      setSelectedRequests([]);
    } else {
      setSelectedRequests(requests.map(r => r.id));
    }
  };

  if (loading) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">Cargando solicitudes...</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h2 className="text-2xl font-bold">Nuevas Solicitudes</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Mostrando {requests.length} solicitud(es)
          </p>
        </div>
      </div>

      {requests.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">No tienes nuevas solicitudes</p>
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
                        checked={selectedRequests.length === requests.length && requests.length > 0}
                        onCheckedChange={handleSelectAll}
                      />
                    </TableHead>
                    <TableHead># Ticket</TableHead>
                    <TableHead>Estado</TableHead>
                    <TableHead>Equipo</TableHead>
                    <TableHead>Operación</TableHead>
                    <TableHead>Ubicación</TableHead>
                    <TableHead>Prior.</TableHead>
                    <TableHead>Coordinador</TableHead>
                    <TableHead>Ingresado</TableHead>
                    <TableHead>Programado Para</TableHead>
                     <TableHead>Comentarios</TableHead>
                     <TableHead>Acciones</TableHead>
                   </TableRow>
                 </TableHeader>
                <TableBody>
                  {requests.map((request) => (
                    <TableRow key={request.id} className="hover:bg-muted/50">
                      <TableCell>
                        <Checkbox
                          checked={selectedRequests.includes(request.id)}
                          onCheckedChange={() => handleSelectRequest(request.id)}
                        />
                      </TableCell>
                      <TableCell className="font-medium text-primary">
                        {request.request_number}
                      </TableCell>
                      <TableCell>
                        <Badge className={getServiceTypeColor(request.service_type)}>
                          {getServiceTypeText(request.service_type)}
                        </Badge>
                      </TableCell>
                      <TableCell className="max-w-[150px] truncate">
                        {request.asset}
                      </TableCell>
                      <TableCell className="max-w-[200px]">
                        <div className="truncate">{request.description}</div>
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-col text-sm">
                          <span>{request.client_name || '-'}</span>
                          <span className="text-xs text-muted-foreground">
                            {request.client_branch || '-'}
                          </span>
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline">P{request.priority}</Badge>
                      </TableCell>
                      <TableCell className="text-sm">
                        {assignments[request.id] ? (
                          <span className="font-medium">{assignments[request.id].team_member_name}</span>
                        ) : (
                          <Badge variant="secondary" className="bg-muted">
                            Sin asignar
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-sm">
                        {new Date(request.created_at).toLocaleDateString('es-ES', {
                          day: '2-digit',
                          month: '2-digit',
                          year: 'numeric'
                        })}
                        <div className="text-xs text-muted-foreground">
                          {new Date(request.created_at).toLocaleTimeString('es-ES', {
                            hour: '2-digit',
                            minute: '2-digit'
                          })}
                        </div>
                      </TableCell>
                      <TableCell className="text-sm">
                        {request.start_time ? (
                          <>
                            {new Date(request.start_time).toLocaleDateString('es-ES', {
                              day: '2-digit',
                              month: '2-digit',
                              year: 'numeric'
                            })}
                            <div className="text-xs text-muted-foreground">
                              {new Date(request.start_time).toLocaleTimeString('es-ES', {
                                hour: '2-digit',
                                minute: '2-digit'
                              })}
                            </div>
                          </>
                        ) : (
                          <span className="text-muted-foreground">-</span>
                        )}
                      </TableCell>
                      <TableCell className="max-w-[200px]">
                        <div className="text-sm truncate" title={request.observations || ''}>
                          {request.observations || '-'}
                        </div>
                       </TableCell>
                       <TableCell>
                         <Button
                           size="sm"
                           variant="outline"
                           onClick={() => {
                             setSelectedRequests([request.id]);
                             setShowAssignmentDialog(true);
                           }}
                         >
                           Asignar
                         </Button>
                       </TableCell>
                     </TableRow>
                   ))}
                 </TableBody>
               </Table>
             </div>
           </CardContent>
         </Card>
       )}

       {showAssignmentDialog && currentProvider && selectedRequests.length > 0 && (
         <AssignmentDialog
           request={{
             id: requests.find(r => r.id === selectedRequests[0])!.id,
             requestNumber: requests.find(r => r.id === selectedRequests[0])!.request_number,
             description: requests.find(r => r.id === selectedRequests[0])!.description,
             asset: requests.find(r => r.id === selectedRequests[0])!.asset,
             location: requests.find(r => r.id === selectedRequests[0])!.location,
             serviceType: requests.find(r => r.id === selectedRequests[0])!.service_type as any,
             deadline: requests.find(r => r.id === selectedRequests[0])!.deadline,
             selectedProviders: [],
             status: 'sent',
             createdAt: requests.find(r => r.id === selectedRequests[0])!.created_at,
             createdBy: 'system',
             priority: requests.find(r => r.id === selectedRequests[0])!.priority,
           }}
           providerId={currentProvider.id}
           onClose={() => {
             setShowAssignmentDialog(false);
             setSelectedRequests([]);
           }}
           onAssign={(assignment) => {
             toast({
               title: 'Asignación exitosa',
               description: `Se asignó correctamente a ${assignment.teamMemberName}`,
             });
             setShowAssignmentDialog(false);
             setSelectedRequests([]);
             fetchProviderAndRequests();
           }}
         />
       )}
     </div>
   );
 };
