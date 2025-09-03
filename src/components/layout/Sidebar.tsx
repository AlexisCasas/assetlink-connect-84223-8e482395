import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { 
  Building2, 
  Wrench, 
  Users, 
  ClipboardList, 
  Settings, 
  Home,
  ChevronLeft,
  ChevronRight
} from 'lucide-react';

interface SidebarProps {
  className?: string;
}

const navigation = [
  { name: 'Dashboard', href: '#', icon: Home, current: true },
  { name: 'Activos', href: '#assets', icon: Building2, current: false },
  { name: 'Tickets', href: '#tickets', icon: ClipboardList, current: false },
  { name: 'Proveedores', href: '#providers', icon: Users, current: false },
  { name: 'Mantenimiento', href: '#maintenance', icon: Wrench, current: false },
  { name: 'Configuración', href: '#settings', icon: Settings, current: false },
];

export function Sidebar({ className }: SidebarProps) {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <div className={cn(
      "flex flex-col bg-card border-r border-border transition-all duration-300",
      collapsed ? "w-16" : "w-64",
      className
    )}>
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-border">
        {!collapsed && (
          <div className="flex items-center space-x-2">
            <Building2 className="h-8 w-8 text-primary" />
            <span className="text-xl font-bold text-foreground">ManagePro</span>
          </div>
        )}
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setCollapsed(!collapsed)}
          className="h-8 w-8 p-0"
        >
          {collapsed ? (
            <ChevronRight className="h-4 w-4" />
          ) : (
            <ChevronLeft className="h-4 w-4" />
          )}
        </Button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 p-4 space-y-2">
        {navigation.map((item) => (
          <Button
            key={item.name}
            variant={item.current ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => {
              // Handle navigation
              window.location.hash = item.href;
            }}
          >
            <item.icon className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && item.name}
          </Button>
        ))}
      </nav>

      {/* User Profile */}
      <div className="p-4 border-t border-border">
        <div className={cn(
          "flex items-center space-x-3",
          collapsed && "justify-center"
        )}>
          <div className="h-8 w-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-medium">
            JD
          </div>
          {!collapsed && (
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-foreground">Juan Perez</p>
              <p className="text-xs text-muted-foreground">Administrador</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}