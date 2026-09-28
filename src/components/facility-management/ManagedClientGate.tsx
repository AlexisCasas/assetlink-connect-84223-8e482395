import type { ReactNode } from 'react';
import { Building2 } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useManagedClient } from '@/hooks/useFacilityManagementOperationalClients';
import { navigateToEntity } from '@/lib/entityNavigation';
import { ORGANIZATION_ROLE_LABELS } from '@/lib/organizationRoles';
import type {
  FacilityManagementOperationalClient,
  FacilityManagementOperationalModule,
} from '@/types/facilityManagement';

const MODULE_LABELS: Record<FacilityManagementOperationalModule, string> = {
  assets: 'Activos',
  criticality: 'Criticidad',
  inspections: 'Inspecciones',
  'preventive-maintenance': 'Mantenimiento preventivo',
};

interface Props {
  module: FacilityManagementOperationalModule;
  /** `managedClient` from the hash — a request, never an authorization. */
  requestedClientId?: string;
  children: (client: FacilityManagementOperationalClient) => ReactNode;
}

/** Delegated (Facility Manager) entry point for an operational module. The
 * active organization stays the FM; the operated client is resolved ONLY
 * from get_my_facility_management_clients(). An unknown/unauthorized
 * `managedClient` renders "no disponible" and mounts nothing, so no data is
 * ever requested for it (RLS/RPCs would reject it anyway). Reusable for the
 * next delegated modules (9C.2+). */
export function ManagedClientGate({ module, requestedClientId, children }: Props) {
  const resolution = useManagedClient(module, requestedClientId);
  const moduleLabel = MODULE_LABELS[module];
  const select = (clientId: string) => navigateToEntity({ view: module, managedClientId: clientId });

  if (resolution.status === 'loading') return <GateMessage text="Cargando tus clientes operativos…" />;
  if (resolution.status === 'error') return <GateMessage text={resolution.message} />;
  if (resolution.status === 'none') {
    return <GateMessage text={`No tienes clientes con acceso delegado a ${moduleLabel}. El cliente debe conceder el permiso y tu empresa asignarte a la relación.`} />;
  }
  if (resolution.status === 'unavailable') {
    return (
      <GateMessage text="Cliente no disponible: no tienes acceso delegado a este cliente para este módulo.">
        <Button variant="outline" onClick={() => navigateToEntity({ view: module })}>Ver mis clientes</Button>
      </GateMessage>
    );
  }
  if (resolution.status === 'choose') {
    return (
      <div className="space-y-4 p-6">
        <div>
          <h1 className="text-2xl font-semibold">{moduleLabel} de clientes</h1>
          <p className="mt-1 text-sm text-muted-foreground">Selecciona el cliente para el que vas a operar.</p>
        </div>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {resolution.eligible.map((client) => (
            <Card key={client.clientOrganizationId} className="cursor-pointer hover:bg-muted/40" onClick={() => select(client.clientOrganizationId)}>
              <CardContent className="flex items-center gap-3 p-4">
                <Building2 className="h-5 w-5 text-muted-foreground" />
                <div className="min-w-0">
                  <p className="truncate font-medium">{client.clientOrganizationName}</p>
                  <p className="text-xs text-muted-foreground">Tu rol: {ORGANIZATION_ROLE_LABELS[client.membershipRole]}</p>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    );
  }

  const { client, eligible } = resolution;
  return (
    <div className="flex h-full flex-col">
      <div className="flex flex-wrap items-center gap-3 border-b bg-muted/30 px-6 py-3" data-testid="managed-client-bar">
        <Badge variant="outline">Acceso delegado</Badge>
        <span className="text-sm text-muted-foreground">Operando para</span>
        {eligible.length > 1 ? (
          <Select value={client.clientOrganizationId} onValueChange={select}>
            <SelectTrigger className="w-64" aria-label="Cliente operado"><SelectValue /></SelectTrigger>
            <SelectContent>
              {eligible.map((candidate) => (
                <SelectItem key={candidate.clientOrganizationId} value={candidate.clientOrganizationId}>{candidate.clientOrganizationName}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        ) : (
          <span className="text-sm font-medium">{client.clientOrganizationName}</span>
        )}
      </div>
      <div className="min-h-0 flex-1">{children(client)}</div>
    </div>
  );
}

function GateMessage({ text, children }: { text: string; children?: ReactNode }) {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="max-w-md space-y-3 text-center text-muted-foreground">
        <Building2 className="mx-auto h-8 w-8 opacity-50" />
        <p>{text}</p>
        {children}
      </div>
    </div>
  );
}
