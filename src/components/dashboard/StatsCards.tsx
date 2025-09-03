import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { 
  Building2, 
  ClipboardList, 
  Users, 
  TrendingUp,
  AlertTriangle,
  CheckCircle,
  Clock,
  DollarSign
} from 'lucide-react';

const stats = [
  {
    title: 'Total Activos',
    value: '147',
    change: '+12%',
    trend: 'up',
    icon: Building2,
    color: 'text-primary'
  },
  {
    title: 'Tickets Activos',
    value: '23',
    change: '-8%',
    trend: 'down',
    icon: ClipboardList,
    color: 'text-info'
  },
  {
    title: 'Proveedores',
    value: '45',
    change: '+3%',
    trend: 'up',
    icon: Users,
    color: 'text-success'
  },
  {
    title: 'Costo Mensual',
    value: '$28,450',
    change: '+15%',
    trend: 'up',
    icon: DollarSign,
    color: 'text-warning'
  }
];

const quickStats = [
  {
    title: 'Mantenimientos Urgentes',
    value: '3',
    icon: AlertTriangle,
    color: 'text-destructive bg-destructive/10'
  },
  {
    title: 'Completados Hoy',
    value: '8',
    icon: CheckCircle,
    color: 'text-success bg-success/10'
  },
  {
    title: 'En Progreso',
    value: '12',
    icon: Clock,
    color: 'text-warning bg-warning/10'
  }
];

export function StatsCards() {
  return (
    <div className="space-y-6">
      {/* Main Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((stat) => {
          const Icon = stat.icon;
          return (
            <Card key={stat.title}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground">
                  {stat.title}
                </CardTitle>
                <Icon className={`h-4 w-4 ${stat.color}`} />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{stat.value}</div>
                <div className="flex items-center text-xs text-muted-foreground">
                  <TrendingUp className={`h-3 w-3 mr-1 ${
                    stat.trend === 'up' ? 'text-success' : 'text-destructive'
                  }`} />
                  {stat.change} desde el mes pasado
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>

      {/* Quick Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {quickStats.map((stat) => {
          const Icon = stat.icon;
          return (
            <Card key={stat.title} className="border-l-4 border-l-primary">
              <CardContent className="p-4">
                <div className="flex items-center space-x-3">
                  <div className={`p-2 rounded-full ${stat.color}`}>
                    <Icon className="h-4 w-4" />
                  </div>
                  <div>
                    <p className="text-sm font-medium text-muted-foreground">{stat.title}</p>
                    <p className="text-xl font-bold">{stat.value}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
}