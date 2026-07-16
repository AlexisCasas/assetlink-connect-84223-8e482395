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