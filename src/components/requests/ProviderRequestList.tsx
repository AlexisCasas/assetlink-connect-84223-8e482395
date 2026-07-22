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
import { Search, Settings2, ArrowUpDown, Download, GripVertical, Eye, FileText, UserCog, Pencil, FilePlus } from 'lucide-react';
import { RequestDetailDialog } from './RequestDetailDialog';
import { QuoteDetailDialog } from './QuoteDetailDialog';
import { QuoteForm } from './QuoteForm';
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
  is_public?: boolean | null;
}

interface Assignment {
  team_member_name: string;
}

type ColumnKey = 'ticket' | 'estado' | 'equipo' | 'operacion' | 'ubicacion' | 'prioridad' | 'coordinador' | 'ingresado' | 'programado' | 'comentarios' | 'cotizacion' | 'acciones';

interface ColumnConfig {
  key: ColumnKey;
  label: string;
  visible: boolean;
  order: number;
}

const DEFAULT_COLUMNS: ColumnConfig[] = [
  { key: 'ticket', label: '# Ticket', visible: true, order: 0 },
  { key: 'estado', label: 'Estado', visible: true, order: 1 },
  { key: 'equipo', label: 'Equipo', visible: true, order: 2 },
  { key: 'operacion', label: 'Operación', visible: true, order: 3 },
  { key: 'ubicacion', label: 'Ubicación', visible: true, order: 4 },
  { key: 'prioridad', label: 'Prior.', visible: true, order: 5 },
  { key: 'coordinador', label: 'Coordinador', visible: true, order: 6 },
  { key: 'ingresado', label: 'Ingresado', visible: true, order: 7 },
  { key: 'programado', label: 'Programado Para', visible: true, order: 8 },
  { key: 'comentarios', label: 'Comentarios', visible: true, order: 9 },
  { key: 'cotizacion', label: 'Estado cotización', visible: true, order: 10 },
  { key: 'acciones', label: 'Acciones', visible: true, order: 11 },
];

export const ProviderRequestList = () => {
  const { currentOrganization } = useAuth();
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
  const [draggedColumn, setDraggedColumn] = useState<ColumnKey | null>(null);
  const [quotes, setQuotes] = useState<Record<string, any>>({});
  const [showDetailDialog, setShowDetailDialog] = useState(false);
  const [showQuoteDialog, setShowQuoteDialog] = useState(false);
  const [selectedRequestForDetail, setSelectedRequestForDetail] = useState<RequestData | null>(null);
  const [selectedRequestForQuote, setSelectedRequestForQuote] = useState<RequestData | null>(null);
  const [showQuoteForm, setShowQuoteForm] = useState(false);
  const [selectedRequestForForm, setSelectedRequestForForm] = useState<RequestData | null>(null);
  const [existingQuoteForForm, setExistingQuoteForForm] = useState<any>(null);
  const canViewProviderRequests = currentOrganization?.organizationType === 'provider_company'
    || currentOrganization?.organizationType === 'facility_manager';

  useEffect(() => {
    const savedColumns = localStorage.getItem('providerRequestColumns');
    if (savedColumns) {
      try {
        setColumns(JSON.parse(savedColumns));
      } catch (e) {
        console.error('Error loading saved columns:', e);
      }
    }
  }, []);

  useEffect(() => {
    initializeAndLoadRequests();
  }, [currentOrganization?.id, canViewProviderRequests]);

  useEffect(() => {
    filterAndSortRequests();
  }, [requests, searchQuery, sortBy, sortOrder, statusFilter, priorityFilter]);

  const initializeAndLoadRequests = async () => {
    if (!currentOrganization || !canViewProviderRequests) {
      setRequests([]);
      setFilteredRequests([]);
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setCurrentProvider(null);

      const { data: accessData } = await supabase
        .from('request_provider_access')
        .select('request_id')
        .eq('provider_organization_id', currentOrganization.id)
        .eq('status', 'active');
      const accessRequestIds = new Set((accessData || []).map((access) => access.request_id));

      const { data: requestsData, error } = await supabase
        .from('requests')
        .select('*')
        .neq('status', 'draft')
        .order('priority', { ascending: true })
        .order('created_at', { ascending: false });

      if (error) throw error;

      const visibleRequests = (requestsData || []).filter((request) => request.is_public || accessRequestIds.has(request.id));
      setRequests(visibleRequests);
      setQuotes({});

      // Assignments remain a legacy module. Keep the provider list tenant-aware
      // and show its existing empty-state placeholder instead of querying it.
      setAssignments({});
      if (visibleRequests.length > 0) {
        const requestIds = visibleRequests.map(r => r.id);

        // A provider only loads its active organization's quotes. provider_id
        // remains legacy data and is never used to authorize this view.
        const { data: quotesData, error: quotesError } = await supabase
          .from('quotes')
          .select('*')
          .in('request_id', requestIds)
          .eq('provider_organization_id', currentOrganization.id);
        if (quotesError) throw quotesError;
        const quotesMap: Record<string, any> = {};
        (quotesData || []).forEach((q: any) => {
          const existing = quotesMap[q.request_id];
          const qDate = new Date(q.updated_at || q.created_at).getTime();
          const eDate = existing ? new Date(existing.updated_at || existing.created_at).getTime() : 0;
          if (!existing || qDate > eDate) quotesMap[q.request_id] = q;
        });
        setQuotes(quotesMap);
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
    const newColumns = columns.map(col => 
      col.key === key ? { ...col, visible: !col.visible } : col
    );
    setColumns(newColumns);
    localStorage.setItem('providerRequestColumns', JSON.stringify(newColumns));
  };

  const isColumnVisible = (key: ColumnKey) => {
    return columns.find(col => col.key === key)?.visible ?? true;
  };

  const handleDragStart = (e: React.DragEvent, key: ColumnKey) => {
    if (key === 'ticket') return;
    setDraggedColumn(key);
    e.dataTransfer.effectAllowed = 'move';
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  };

  const handleDrop = (e: React.DragEvent, targetKey: ColumnKey) => {
    e.preventDefault();
    
    if (!draggedColumn || draggedColumn === targetKey || targetKey === 'ticket') {
      setDraggedColumn(null);
      return;
    }

    const draggedCol = columns.find(col => col.key === draggedColumn);
    const targetCol = columns.find(col => col.key === targetKey);
    
    if (!draggedCol || !targetCol) return;

    const newColumns = columns.map(col => {
      if (col.key === draggedColumn) {
        return { ...col, order: targetCol.order };
      }
      if (col.key === targetKey) {
        return { ...col, order: draggedCol.order };
      }
      return col;
    });

    const sortedColumns = newColumns.sort((a, b) => a.order - b.order);
    setColumns(sortedColumns);
    localStorage.setItem('providerRequestColumns', JSON.stringify(sortedColumns));
    setDraggedColumn(null);
  };

  const handleDragEnd = () => {
    setDraggedColumn(null);
  };

  const resetColumns = () => {
    setColumns(DEFAULT_COLUMNS);
    localStorage.setItem('providerRequestColumns', JSON.stringify(DEFAULT_COLUMNS));
  };

  const renderCell = (key: ColumnKey, request: RequestData) => {
    switch (key) {
      case 'ticket':
        return (
          <TableCell key={key} className="font-medium text-primary">
            {request.request_number}
          </TableCell>
        );
      case 'estado':
        return (
          <TableCell key={key}>
            <Badge className={getServiceTypeColor(request.service_type)}>
              {getServiceTypeText(request.service_type)}
            </Badge>
          </TableCell>
        );
      case 'equipo':
        return (
          <TableCell key={key} className="max-w-[150px] truncate">
            {request.asset}
          </TableCell>
        );
      case 'operacion':
        return (
          <TableCell key={key} className="max-w-[200px]">
            <div className="truncate">{request.description}</div>
          </TableCell>
        );
      case 'ubicacion':
        return (
          <TableCell key={key}>
            <div className="flex flex-col text-sm">
              <span>{request.client_name || '-'}</span>
              <span className="text-xs text-muted-foreground">
                {request.client_branch || '-'}
              </span>
            </div>
          </TableCell>
        );
      case 'prioridad':
        return (
          <TableCell key={key}>
            <Badge variant="outline">P{request.priority}</Badge>
          </TableCell>
        );
      case 'coordinador':
        return (
          <TableCell key={key}>
            {assignments[request.id]?.team_member_name || '-'}
          </TableCell>
        );
      case 'ingresado':
        return (
          <TableCell key={key}>
            {new Date(request.created_at).toLocaleDateString('es-ES', {
              day: '2-digit',
              month: '2-digit',
              year: 'numeric'
            })}
          </TableCell>
        );
      case 'programado':
        return (
          <TableCell key={key}>
            {request.start_time 
              ? new Date(request.start_time).toLocaleString('es-ES', {
                  day: '2-digit',
                  month: '2-digit',
                  year: 'numeric',
                  hour: '2-digit',
                  minute: '2-digit'
                })
              : '-'}
          </TableCell>
        );
      case 'comentarios':
        return (
          <TableCell key={key} className="max-w-[200px]">
            <div className="truncate text-sm text-muted-foreground">
              {request.observations || '-'}
            </div>
          </TableCell>
        );
      case 'cotizacion': {
        const q = quotes[request.id];
        let label = 'Sin cotizar';
        let cls = 'bg-muted text-muted-foreground';
        if (q) {
          if (q.status === 'approved') { label = 'Aprobada'; cls = 'bg-green-600 text-white'; }
          else if (q.status === 'rejected') { label = 'Rechazada'; cls = 'bg-red-600 text-white'; }
          else if (q.emailed_at) { label = 'Enviada por correo'; cls = 'bg-blue-600 text-white'; }
          else if (q.status === 'submitted') { label = 'Enviada'; cls = 'bg-primary text-primary-foreground'; }
          else if (q.status === 'draft') { label = 'Borrador'; cls = 'bg-yellow-500 text-white'; }
        }
        return (
          <TableCell key={key}>
            <Badge className={cls}>{label}</Badge>
          </TableCell>
        );
      }
      case 'acciones':
        {
          const q = quotes[request.id];
          const isDraft = q && q.status === 'draft';
          const isSubmitted = q && (q.status === 'submitted' || q.emailed_at);
          return (
          <TableCell key={key}>
            <div className="flex gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={(e) => {
                  e.stopPropagation();
                  setSelectedRequestForDetail(request);
                  setShowDetailDialog(true);
                }}
                title="Ver detalles completos"
              >
                <Eye className="h-4 w-4" />
              </Button>

              {isSubmitted && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={(e) => {
                    e.stopPropagation();
                    setSelectedRequestForQuote(request);
                    setShowQuoteDialog(true);
                  }}
                  title="Ver cotización"
                >
                  <FileText className="h-4 w-4" />
                </Button>
              )}

              {!q && (
                <Button
                  size="sm"
                  onClick={(e) => {
                    e.stopPropagation();
                    setSelectedRequestForForm(request);
                    setExistingQuoteForForm(null);
                    setShowQuoteForm(true);
                  }}
                >
                  <FilePlus className="h-4 w-4 mr-1" /> Cotizar
                </Button>
              )}
              {isDraft && (
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={(e) => {
                    e.stopPropagation();
                    setSelectedRequestForForm(request);
                    setExistingQuoteForForm(q);
                    setShowQuoteForm(true);
                  }}
                >
                  <Pencil className="h-4 w-4 mr-1" /> Editar borrador
                </Button>
              )}

              {false && <Button
                size="sm"
                variant="outline"
                onClick={(e) => {
                  e.stopPropagation();
                  setSelectedRequests([request.id]);
                  setShowAssignmentDialog(true);
                }}
              >
                <UserCog className="h-4 w-4 mr-1" />
                Asignar
              </Button>}
            </div>
          </TableCell>
        );
        }
      default:
        return null;
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

  if (!canViewProviderRequests) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="py-12 text-center">
            <p className="text-muted-foreground">Selecciona una organización proveedora para ver solicitudes disponibles</p>
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
            <DropdownMenuSeparator />
            <Button
              variant="ghost"
              size="sm"
              onClick={resetColumns}
              className="w-full"
            >
              Restablecer orden
            </Button>
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
                    {[...columns]
                      .sort((a, b) => a.order - b.order)
                      .filter(col => col.visible)
                      .map(col => (
                        <TableHead
                          key={col.key}
                          draggable={col.key !== 'ticket'}
                          onDragStart={(e) => handleDragStart(e, col.key)}
                          onDragOver={handleDragOver}
                          onDrop={(e) => handleDrop(e, col.key)}
                          onDragEnd={handleDragEnd}
                          className={`${col.key !== 'ticket' ? 'cursor-move' : ''} ${draggedColumn === col.key ? 'opacity-50' : ''}`}
                          title={col.key !== 'ticket' ? 'Arrastra para reordenar' : ''}
                        >
                          <div className="flex items-center gap-2">
                            {col.key !== 'ticket' && <GripVertical className="h-4 w-4 text-muted-foreground" />}
                            {col.label}
                          </div>
                        </TableHead>
                      ))}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredRequests.map((request) => (
                    <TableRow 
                      key={request.id} 
                      className="hover:bg-muted/50 cursor-pointer"
                      onDoubleClick={() => {
                        setSelectedRequestForDetail(request);
                        setShowDetailDialog(true);
                      }}
                      title="Doble click para ver detalle"
                    >
                      <TableCell>
                        <Checkbox
                          checked={selectedRequests.includes(request.id)}
                          onCheckedChange={() => handleSelectRequest(request.id)}
                        />
                      </TableCell>
                      {[...columns]
                        .sort((a, b) => a.order - b.order)
                        .filter(col => col.visible)
                        .map(col => renderCell(col.key, request))}
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

       {showDetailDialog && selectedRequestForDetail && (
         <RequestDetailDialog
           request={selectedRequestForDetail}
           assignment={assignments[selectedRequestForDetail.id]}
           onClose={() => {
             setShowDetailDialog(false);
             setSelectedRequestForDetail(null);
           }}
         />
       )}

       {showQuoteDialog && selectedRequestForQuote && quotes[selectedRequestForQuote.id] && (
         <QuoteDetailDialog
           quote={quotes[selectedRequestForQuote.id]}
           request={selectedRequestForQuote}
           onClose={() => {
             setShowQuoteDialog(false);
             setSelectedRequestForQuote(null);
           }}
         />
       )}

       {showQuoteForm && selectedRequestForForm && (
         <QuoteForm
           request={{
             id: selectedRequestForForm.id,
             requestNumber: selectedRequestForForm.request_number,
             description: selectedRequestForForm.description,
             asset: selectedRequestForForm.asset,
             location: selectedRequestForForm.location,
             serviceType: selectedRequestForForm.service_type as any,
             deadline: selectedRequestForForm.deadline,
             selectedProviders: [],
             status: 'sent',
             createdAt: selectedRequestForForm.created_at,
             createdBy: (selectedRequestForForm as any).created_by || '',
             priority: selectedRequestForForm.priority,
           } as any}
           existingQuote={existingQuoteForForm}
           onClose={() => {
             setShowQuoteForm(false);
             setSelectedRequestForForm(null);
             setExistingQuoteForForm(null);
           }}
           onSave={() => {
             setShowQuoteForm(false);
             setSelectedRequestForForm(null);
             setExistingQuoteForForm(null);
             initializeAndLoadRequests();
           }}
         />
       )}
     </div>
   );
 };
