import { Building2, Check, ChevronsUpDown } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAuth } from '@/contexts/AuthContext';
import { cn } from '@/lib/utils';
import { ORGANIZATION_ROLE_LABELS as roleLabels } from '@/lib/organizationRoles';
import type { OrganizationType } from '@/types/organization';

const organizationTypeLabels: Record<OrganizationType, string> = {
  client_company: 'Cliente',
  provider_company: 'Proveedor',
  facility_manager: 'Facility Manager',
  subcontractor_company: 'Subcontratista',
  platform_admin: 'Administrador Plataforma',
};

interface OrganizationSwitcherProps {
  collapsed?: boolean;
}

export const OrganizationSwitcher = ({ collapsed = false }: OrganizationSwitcherProps) => {
  const {
    organizations,
    memberships,
    currentOrganization,
    currentMembership,
    setCurrentOrganization,
  } = useAuth();

  if (!currentOrganization) {
    return (
      <div
        className={cn(
          'mx-4 rounded-md border border-dashed border-border px-3 py-2 text-muted-foreground',
          collapsed && 'mx-2 flex justify-center px-2',
        )}
        title="Sin organización asignada"
      >
        <Building2 className="h-4 w-4" />
        {!collapsed && <span className="ml-2 text-xs">Sin organización asignada</span>}
      </div>
    );
  }

  const organizationRole = currentMembership ? roleLabels[currentMembership.role] : 'Sin rol asignado';
  const hasMultipleOrganizations = organizations.length > 1;

  const trigger = (
    <Button
      variant="ghost"
      className={cn(
        'h-auto w-full border border-border bg-muted/30 px-3 py-2 text-left hover:bg-muted',
        collapsed ? 'justify-center px-2' : 'justify-start',
      )}
      title={currentOrganization.name}
      disabled={!hasMultipleOrganizations}
    >
      <Building2 className="h-4 w-4 shrink-0 text-primary" />
      {!collapsed && (
        <span className="ml-2 min-w-0 flex-1">
          <span className="block truncate text-sm font-medium">{currentOrganization.name}</span>
          <span className="mt-1 flex flex-wrap items-center gap-1">
            <Badge variant="secondary" className="px-1.5 py-0 text-[10px] font-normal">
              {organizationTypeLabels[currentOrganization.organizationType]}
            </Badge>
            <span className="text-xs text-muted-foreground">{organizationRole}</span>
          </span>
        </span>
      )}
      {hasMultipleOrganizations && !collapsed && <ChevronsUpDown className="ml-2 h-4 w-4 text-muted-foreground" />}
    </Button>
  );

  if (!hasMultipleOrganizations) return <div className={cn('px-4', collapsed && 'px-2')}>{trigger}</div>;

  return (
    <div className={cn('px-4', collapsed && 'px-2')}>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>{trigger}</DropdownMenuTrigger>
        <DropdownMenuContent align={collapsed ? 'start' : 'center'} className="w-64">
          <DropdownMenuLabel>Cambiar organización</DropdownMenuLabel>
          <DropdownMenuSeparator />
          {organizations.map((organization) => {
            const membership = memberships.find((candidate) => candidate.organizationId === organization.id);
            const isCurrent = organization.id === currentOrganization.id;

            return (
              <DropdownMenuItem
                key={organization.id}
                className="items-start gap-2 py-2"
                onSelect={() => setCurrentOrganization(organization.id)}
              >
                <Building2 className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-medium">{organization.name}</span>
                  <span className="block text-xs text-muted-foreground">
                    {organizationTypeLabels[organization.organizationType]} · {membership ? roleLabels[membership.role] : 'Sin rol asignado'}
                  </span>
                </span>
                {isCurrent && <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" />}
              </DropdownMenuItem>
            );
          })}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
};
