import { Badge } from '@/components/ui/badge';

export const getServiceTypeColor = (type: string) => {
  const colors: Record<string, string> = {
    emergencia: 'bg-red-500/10 text-red-500 border-red-500/20',
    correctivo: 'bg-orange-500/10 text-orange-500 border-orange-500/20',
    preventivo: 'bg-blue-500/10 text-blue-500 border-blue-500/20',
    proyecto: 'bg-purple-500/10 text-purple-500 border-purple-500/20',
  };
  return colors[type] || '';
};

export const getServiceTypeText = (type: string) => {
  const texts: Record<string, string> = {
    emergencia: 'Emergencia',
    correctivo: 'Correctivo',
    preventivo: 'Preventivo',
    proyecto: 'Proyecto',
  };
  return texts[type] || type;
};

export const getStatusColor = (status: string) => {
  const colors: Record<string, string> = {
    draft: 'bg-gray-500/10 text-gray-500 border-gray-500/20',
    sent: 'bg-blue-500/10 text-blue-500 border-blue-500/20',
    quoted: 'bg-yellow-500/10 text-yellow-500 border-yellow-500/20',
    completed: 'bg-green-500/10 text-green-500 border-green-500/20',
    anulado: 'bg-red-500/10 text-red-500 border-red-500/20',
  };
  return colors[status] || '';
};

export const getStatusText = (status: string) => {
  const texts: Record<string, string> = {
    draft: 'Borrador',
    sent: 'Enviado',
    quoted: 'Cotizado',
    completed: 'Completado',
    anulado: 'Anulado',
  };
  return texts[status] || status;
};

interface ServiceTypeBadgeProps {
  type: string;
}

export const ServiceTypeBadge = ({ type }: ServiceTypeBadgeProps) => (
  <Badge className={getServiceTypeColor(type)}>{getServiceTypeText(type)}</Badge>
);

interface StatusBadgeProps {
  status: string;
}

export const StatusBadge = ({ status }: StatusBadgeProps) => (
  <Badge variant="outline" className={getStatusColor(status)}>
    {getStatusText(status)}
  </Badge>
);

interface QuotesProgressBadgeProps {
  received: number;
  minRequired: number;
}

export const QuotesProgressBadge = ({ received, minRequired }: QuotesProgressBadgeProps) => {
  const isComplete = received >= minRequired;
  return (
    <Badge
      variant="outline"
      className={
        isComplete
          ? 'bg-green-500/10 text-green-600 border-green-500/20'
          : 'bg-orange-500/10 text-orange-600 border-orange-500/20'
      }
    >
      {received}/{minRequired}
    </Badge>
  );
};

interface RequestTypeBadgeProps {
  /** Legacy rows without request_type are always treated as external. */
  type?: 'internal' | 'external' | string | null;
}

export const RequestTypeBadge = ({ type }: RequestTypeBadgeProps) => (
  type === 'internal'
    ? <Badge variant="outline" className="bg-violet-500/10 text-violet-600 border-violet-500/20">Interna</Badge>
    : <Badge variant="outline" className="bg-slate-500/10 text-slate-600 border-slate-500/20">Externa</Badge>
);

export const WORK_ORDER_STATUS_LABELS: Record<string, string> = {
  pending: 'Pendiente',
  assigned: 'Asignada',
  in_progress: 'En progreso',
  completed: 'Completada',
  closed: 'Cerrada',
};

const WORK_ORDER_STATUS_COLORS: Record<string, string> = {
  pending: 'bg-slate-500/10 text-slate-600 border-slate-500/20',
  assigned: 'bg-blue-500/10 text-blue-600 border-blue-500/20',
  in_progress: 'bg-amber-500/10 text-amber-600 border-amber-500/20',
  completed: 'bg-green-500/10 text-green-600 border-green-500/20',
  closed: 'bg-gray-500/10 text-gray-600 border-gray-500/20',
};

interface WorkOrderStatusBadgeProps {
  status: string;
}

export const WorkOrderStatusBadge = ({ status }: WorkOrderStatusBadgeProps) => (
  <Badge variant="outline" className={WORK_ORDER_STATUS_COLORS[status] ?? ''}>
    {WORK_ORDER_STATUS_LABELS[status] ?? status}
  </Badge>
);

export const WORK_ORDER_PRIORITY_LABELS: Record<string, string> = {
  low: 'Baja',
  medium: 'Media',
  high: 'Alta',
  urgent: 'Urgente',
};

const WORK_ORDER_PRIORITY_COLORS: Record<string, string> = {
  low: 'bg-slate-500/10 text-slate-600 border-slate-500/20',
  medium: 'bg-blue-500/10 text-blue-600 border-blue-500/20',
  high: 'bg-orange-500/10 text-orange-600 border-orange-500/20',
  urgent: 'bg-red-500/10 text-red-600 border-red-500/20',
};

interface WorkOrderPriorityBadgeProps {
  priority: string;
}

export const WorkOrderPriorityBadge = ({ priority }: WorkOrderPriorityBadgeProps) => (
  <Badge variant="outline" className={WORK_ORDER_PRIORITY_COLORS[priority] ?? ''}>
    {WORK_ORDER_PRIORITY_LABELS[priority] ?? priority}
  </Badge>
);

export const WORK_ORDER_ACTIVITY_STATUS_LABELS: Record<string, string> = {
  pending: 'Pendiente',
  assigned: 'Asignada',
  in_progress: 'En ejecución',
  completed: 'Finalizada',
};

const WORK_ORDER_ACTIVITY_STATUS_COLORS: Record<string, string> = {
  pending: 'bg-slate-500/10 text-slate-600 border-slate-500/20',
  assigned: 'bg-blue-500/10 text-blue-600 border-blue-500/20',
  in_progress: 'bg-amber-500/10 text-amber-600 border-amber-500/20',
  completed: 'bg-green-500/10 text-green-600 border-green-500/20',
};

interface WorkOrderActivityStatusBadgeProps {
  status: string;
}

export const WorkOrderActivityStatusBadge = ({ status }: WorkOrderActivityStatusBadgeProps) => (
  <Badge variant="outline" className={WORK_ORDER_ACTIVITY_STATUS_COLORS[status] ?? ''}>
    {WORK_ORDER_ACTIVITY_STATUS_LABELS[status] ?? status}
  </Badge>
);