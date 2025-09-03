import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { 
  ClipboardList, 
  Search, 
  Plus, 
  Calendar,
  User,
  AlertCircle,
  Clock,
  CheckCircle,
  XCircle
} from 'lucide-react';
import { cn } from '@/lib/utils';

interface Ticket {
  id: string;
  title: string;
  description: string;
  asset: string;
  status: 'pending' | 'in_progress' | 'completed' | 'cancelled';
  priority: 'low' | 'medium' | 'high' | 'urgent';
  createdAt: string;
  assignedTo?: string;
  estimatedCost?: number;
}

const mockTickets: Ticket[] = [
  {
    id: 'TICK-001',
    title: 'Mantenimiento preventivo del bus',
    description: 'Revisión general del motor y sistema de frenos',
    asset: 'BUS MERCEDES BENZ - 01',
    status: 'pending',
    priority: 'high',
    createdAt: '2024-01-15',
    estimatedCost: 1500
  },
  {
    id: 'TICK-002',
    title: 'Cambio de aceite',
    description: 'Cambio de aceite y filtros según plan de mantenimiento',
    asset: 'BUS MERCEDES BENZ - 01',
    status: 'in_progress',
    priority: 'medium',
    createdAt: '2024-01-10',
    assignedTo: 'Carlos Mechanics',
    estimatedCost: 300
  },
  {
    id: 'TICK-003',
    title: 'Reparación del sistema eléctrico',
    description: 'Falla en el sistema de luces traseras',
    asset: 'BUS MERCEDES BENZ - 01',
    status: 'completed',
    priority: 'urgent',
    createdAt: '2024-01-05',
    assignedTo: 'ElectroService',
    estimatedCost: 800
  }
];

export function TicketList() {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');

  const getStatusIcon = (status: Ticket['status']) => {
    switch (status) {
      case 'pending':
        return Clock;
      case 'in_progress':
        return AlertCircle;
      case 'completed':
        return CheckCircle;
      case 'cancelled':
        return XCircle;
      default:
        return Clock;
    }
  };

  const getStatusColor = (status: Ticket['status']) => {
    switch (status) {
      case 'pending':
        return 'bg-warning/10 text-warning border-warning/20';
      case 'in_progress':
        return 'bg-info/10 text-info border-info/20';
      case 'completed':
        return 'bg-success/10 text-success border-success/20';
      case 'cancelled':
        return 'bg-destructive/10 text-destructive border-destructive/20';
      default:
        return 'bg-muted text-muted-foreground border-border';
    }
  };

  const getPriorityColor = (priority: Ticket['priority']) => {
    switch (priority) {
      case 'low':
        return 'bg-muted text-muted-foreground border-border';
      case 'medium':
        return 'bg-info/10 text-info border-info/20';
      case 'high':
        return 'bg-warning/10 text-warning border-warning/20';
      case 'urgent':
        return 'bg-destructive/10 text-destructive border-destructive/20';
      default:
        return 'bg-muted text-muted-foreground border-border';
    }
  };

  const getStatusText = (status: Ticket['status']) => {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'in_progress':
        return 'En Progreso';
      case 'completed':
        return 'Completado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  };

  const getPriorityText = (priority: Ticket['priority']) => {
    switch (priority) {
      case 'low':
        return 'Baja';
      case 'medium':
        return 'Media';
      case 'high':
        return 'Alta';
      case 'urgent':
        return 'Urgente';
      default:
        return priority;
    }
  };

  const filteredTickets = mockTickets.filter(ticket => {
    const matchesSearch = ticket.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         ticket.asset.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         ticket.id.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesStatus = selectedStatus === 'all' || ticket.status === selectedStatus;
    return matchesSearch && matchesStatus;
  });

  return (
    <Card className="h-full">
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="flex items-center text-lg">
            <ClipboardList className="h-5 w-5 mr-2" />
            Tickets de Mantenimiento
          </CardTitle>
          <Button>
            <Plus className="h-4 w-4 mr-2" />
            Nuevo Ticket
          </Button>
        </div>
      </CardHeader>
      
      <CardContent className="space-y-4">
        {/* Filters */}
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Buscar tickets..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10"
            />
          </div>
          <div className="flex gap-2">
            {['all', 'pending', 'in_progress', 'completed'].map((status) => (
              <Button
                key={status}
                variant={selectedStatus === status ? 'default' : 'outline'}
                size="sm"
                onClick={() => setSelectedStatus(status)}
              >
                {status === 'all' ? 'Todos' : getStatusText(status as Ticket['status'])}
              </Button>
            ))}
          </div>
        </div>

        {/* Tickets List */}
        <div className="space-y-3">
          {filteredTickets.map((ticket) => {
            const StatusIcon = getStatusIcon(ticket.status);
            
            return (
              <Card key={ticket.id} className="p-4 hover:shadow-md transition-shadow cursor-pointer">
                <div className="flex items-start justify-between">
                  <div className="flex-1 space-y-2">
                    <div className="flex items-center space-x-2">
                      <h3 className="font-medium text-foreground">{ticket.title}</h3>
                      <Badge 
                        variant="outline"
                        className={cn("text-xs", getStatusColor(ticket.status))}
                      >
                        <StatusIcon className="h-3 w-3 mr-1" />
                        {getStatusText(ticket.status)}
                      </Badge>
                      <Badge 
                        variant="outline"
                        className={cn("text-xs", getPriorityColor(ticket.priority))}
                      >
                        {getPriorityText(ticket.priority)}
                      </Badge>
                    </div>
                    
                    <p className="text-sm text-muted-foreground">{ticket.description}</p>
                    
                    <div className="flex items-center space-x-4 text-xs text-muted-foreground">
                      <span className="flex items-center">
                        <Calendar className="h-3 w-3 mr-1" />
                        {ticket.createdAt}
                      </span>
                      <span>{ticket.asset}</span>
                      {ticket.assignedTo && (
                        <span className="flex items-center">
                          <User className="h-3 w-3 mr-1" />
                          {ticket.assignedTo}
                        </span>
                      )}
                      {ticket.estimatedCost && (
                        <span className="font-medium">
                          ${ticket.estimatedCost.toLocaleString()}
                        </span>
                      )}
                    </div>
                  </div>
                  
                  <div className="ml-4">
                    <Button variant="outline" size="sm">
                      Ver Detalles
                    </Button>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>

        {filteredTickets.length === 0 && (
          <div className="text-center py-8">
            <ClipboardList className="h-12 w-12 mx-auto text-muted-foreground mb-4" />
            <p className="text-muted-foreground">No se encontraron tickets</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}