import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { AssignmentDialog } from './AssignmentDialog';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import { seedDatabase } from '@/lib/seedData';
import { Search, Settings2, ArrowUpDown, Download } from 'lucide-react';
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

type ColumnKey = 'ticket' | 'estado' | 'equipo' | 'operacion' | 'ubicacion' | 'prioridad' | 'coordinador' | 'ingresado' | 'programado' | 'comentarios' | 'acciones';

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
  { key: 'coordinador', label: 'Coordinador', visible: true },
  { key: 'ingresado', label: 'Ingresado', visible: true },
  { key: 'programado', label: 'Programado Para', visible: true },
  { key: 'comentarios', label: 'Comentarios', visible: true },
  { key: 'acciones', label: 'Acciones', visible: true },
];

export const ProviderRequestList = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [requests, setRequests] = useState<RequestData[]>([]);
  const [filteredRequests, setFilteredRequests] = useState<RequestData[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedRequests, setSelectedRequests] = useState<string[]>([]);
  const [showAssignmentDialog, setShowAssignmentDialog] = useState(false);
  const [currentProvider, setCurrentProvider] = useState<any>(null);
  const [assignments, setAssignments] = useState<Record<string, Assignment>>({});
  const [searchQuery, setSearchQuery] = useState('');
  const [columns, setColumns] = useState<ColumnConfig[]>(DEFAULT_COLUMNS);
  const [sortBy, setSortBy] = useState<'created_at' | 'priority' | 'start_time'>('created_at');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [priorityFilter, setPriorityFilter] = useState<string>('all');

  useEffect(() => {
    initializeAndLoadRequests();
  }, [user]);

  useEffect(() => {
    filterAndSortRequests();
  }, [requests, searchQuery, sortBy, sortOrder, statusFilter, priorityFilter]);

  const initializeAndLoadRequests = async () => {
    try {
      setLoading(true);
      
      // Seed database with example data if empty
      await seedDatabase();
      
      // Get current provider - ensure we always have one
      let { data: providerData } = await supabase
        .from('providers')
        .select('*')
        .eq('email', user?.email)
        .maybeSingle();

      // If user doesn't have a provider, use the first available one
      if (!providerData) {
        const { data: firstProvider } = await supabase
          .from('providers')
          .select('*')
          .limit(1)
          .maybeSingle();
        
        providerData = firstProvider;
      }

      // Set provider (should always exist after seeding)
      if (providerData) {
        setCurrentProvider(providerData);
      }

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
    if (selectedRequests.length === filteredRequests.length) {
      setSelectedRequests([]);
    } else {
      setSelectedRequests(filteredRequests.map(r => r.id));
    }
  };

  const filterAndSortRequests = () => {
    let filtered = [...requests];

    // Search filter
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(r => 
        r.request_number.toLowerCase().includes(query) ||
        r.description.toLowerCase().includes(query) ||
        r.asset.toLowerCase().includes(query) ||
        r.location.toLowerCase().includes(query) ||
        (r.client_name && r.client_name.toLowerCase().includes(query)) ||
        (r.observations && r.observations.toLowerCase().includes(query))
      );
    }

    // Status filter
    if (statusFilter !== 'all') {
      filtered = filtered.filter(r => r.service_type === statusFilter);
    }

    // Priority filter
    if (priorityFilter !== 'all') {
      filtered = filtered.filter(r => r.priority === parseInt(priorityFilter));
    }

    // Sort
    filtered.sort((a, b) => {
      let compareValue = 0;
      
      if (sortBy === 'created_at') {
        compareValue = new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
      } else if (sortBy === 'priority') {
        compareValue = a.priority - b.priority;
      } else if (sortBy === 'start_time') {
        const aTime = a.start_time ? new Date(a.start_time).getTime() : 0;
        const bTime = b.start_time ? new Date(b.start_time).getTime() : 0;
        compareValue = aTime - bTime;
      }

      return sortOrder === 'asc' ? compareValue : -compareValue;
    });

    setFilteredRequests(filtered);
  };

  const toggleColumn = (key: ColumnKey) => {
    setColumns(columns.map(col => 
      col.key === key ? { ...col, visible: !col.visible } : col
    ));
  };

  const isColumnVisible = (key: ColumnKey) => {
    return columns.find(col => col.key === key)?.visible ?? true;
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
    <div className="p-6 space-y-4">
      <div className="flex justify-between items-center">
        <div>
          <h2 className="text-2xl font-bold">Solicitudes</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Mostrando {filteredRequests.length} de {requests.length} solicitud(es)
          </p>
        </div>
        <Button 
          variant="outline"
          disabled={selectedRequests.length === 0}
          className="gap-2"
        >
          <Download className="h-4 w-4" />
          Descargar ({selectedRequests.length})
        </Button>
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
            <SelectItem value="emergencia">Emergencia</SelectItem>
            <SelectItem value="correctivo">Correctivo</SelectItem>
            <SelectItem value="preventivo">Preventivo</SelectItem>
            <SelectItem value="proyecto">Proyecto</SelectItem>
          </SelectContent>
        </Select>

        <Select value={priorityFilter} onValueChange={setPriorityFilter}>
          <SelectTrigger className="w-[150px]">
            <SelectValue placeholder="Prioridad" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todas</SelectItem>
            <SelectItem value="1">P1</SelectItem>
            <SelectItem value="2">P2</SelectItem>
            <SelectItem value="3">P3</SelectItem>
            <SelectItem value="4">P4</SelectItem>
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
              <DropdownMenuRadioItem value="created_at">
                Fecha de ingreso
              </DropdownMenuRadioItem>
              <DropdownMenuRadioItem value="priority">
                Prioridad
              </DropdownMenuRadioItem>
              <DropdownMenuRadioItem value="start_time">
                Fecha programada
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

      {filteredRequests.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">
              {searchQuery || statusFilter !== 'all' || priorityFilter !== 'all'
                ? 'No se encontraron solicitudes con los filtros aplicados'
                : 'No tienes nuevas solicitudes'}
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
                        checked={selectedRequests.length === filteredRequests.length && filteredRequests.length > 0}
                        onCheckedChange={handleSelectAll}
                      />
                    </TableHead>
                    {isColumnVisible('ticket') && <TableHead># Ticket</TableHead>}
                    {isColumnVisible('estado') && <TableHead>Estado</TableHead>}
                    {isColumnVisible('equipo') && <TableHead>Equipo</TableHead>}
                    {isColumnVisible('operacion') && <TableHead>Operación</TableHead>}
                    {isColumnVisible('ubicacion') && <TableHead>Ubicación</TableHead>}
                    {isColumnVisible('prioridad') && <TableHead>Prior.</TableHead>}
                    {isColumnVisible('coordinador') && <TableHead>Coordinador</TableHead>}
                    {isColumnVisible('ingresado') && <TableHead>Ingresado</TableHead>}
                    {isColumnVisible('programado') && <TableHead>Programado Para</TableHead>}
                    {isColumnVisible('comentarios') && <TableHead>Comentarios</TableHead>}
                    {isColumnVisible('acciones') && <TableHead>Acciones</TableHead>}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredRequests.map((request) => (
                    <TableRow key={request.id} className="hover:bg-muted/50">
                      <TableCell>
                        <Checkbox
                          checked={selectedRequests.includes(request.id)}
                          onCheckedChange={() => handleSelectRequest(request.id)}
                        />
                      </TableCell>
                      {isColumnVisible('ticket') && (
                        <TableCell className="font-medium text-primary">
                          {request.request_number}
                        </TableCell>
                      )}
                      {isColumnVisible('estado') && (
                        <TableCell>
                          <Badge className={getServiceTypeColor(request.service_type)}>
                            {getServiceTypeText(request.service_type)}
                          </Badge>
                        </TableCell>
                      )}
                      {isColumnVisible('equipo') && (
                        <TableCell className="max-w-[150px] truncate">
                          {request.asset}
                        </TableCell>
                      )}
                      {isColumnVisible('operacion') && (
                        <TableCell className="max-w-[200px]">
                          <div className="truncate">{request.description}</div>
                        </TableCell>
                      )}
                      {isColumnVisible('ubicacion') && (
                        <TableCell>
                          <div className="flex flex-col text-sm">
                            <span>{request.client_name || '-'}</span>
                            <span className="text-xs text-muted-foreground">
                              {request.client_branch || '-'}
                            </span>
                          </div>
                        </TableCell>
                      )}
                      {isColumnVisible('prioridad') && (
                        <TableCell>
                          <Badge variant="outline">P{request.priority}</Badge>
                        </TableCell>
                      )}
                      {isColumnVisible('coordinador') && (
                        <TableCell className="text-sm">
                          {assignments[request.id] ? (
                            <span className="font-medium">{assignments[request.id].team_member_name}</span>
                          ) : (
                            <Badge variant="secondary" className="bg-muted">
                              Sin asignar
                            </Badge>
                          )}
                        </TableCell>
                      )}
                      {isColumnVisible('ingresado') && (
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
                      )}
                      {isColumnVisible('programado') && (
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
                      )}
                      {isColumnVisible('comentarios') && (
                        <TableCell className="max-w-[200px]">
                          <div className="text-sm truncate" title={request.observations || ''}>
                            {request.observations || '-'}
                          </div>
                        </TableCell>
                      )}
                      {isColumnVisible('acciones') && (
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
                      )}
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
              initializeAndLoadRequests();
            }}
         />
       )}
     </div>
   );
 };
