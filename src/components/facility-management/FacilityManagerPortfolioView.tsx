import { useCallback, useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Briefcase } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { useFacilityManagement } from '@/hooks/useFacilityManagement';
import { canFacilityManagerViewReports, canFacilityManagerViewWorkOrders, isFacilityManagementRelationshipEditable } from '@/lib/facilityManagement';
import { useFacilityManagementOperationalClients } from '@/hooks/useFacilityManagementOperationalClients';
import { navigateToEntity } from '@/lib/entityNavigation';
import { delegatedReportsAccessReason } from '@/lib/delegatedReportsAccessReason';
import type { FacilityManagementMember, FacilityManagementPortfolioEntry } from '@/types/facilityManagement';
import { FacilityManagementPermissionsEditor } from './FacilityManagementPermissionsEditor';
import { FacilityManagementMembersEditor } from './FacilityManagementMembersEditor';
import { FacilityManagementStatusBadge } from './FacilityManagementStatusBadge';

/** Vista del Facility Manager (owner/admin): cartera administrativa, permisos
 * recibidos en solo lectura y asignación de personas de su propia
 * organización. Ver la cartera no da acceso operativo al cliente. */
/** The reports entry stays discoverable even without access; the route gate is unchanged. */
function ReportsAccessAction({ entry, allowed, loading, error, context, onOpen }: {
  entry: FacilityManagementPortfolioEntry;
  allowed: boolean;
  loading: boolean;
  error: boolean;
  context: 'row' | 'dialog';
  onOpen: () => void;
}) {
  const reason = delegatedReportsAccessReason({ entry, allowed, loading, error });
  const reasonId = `fm-reports-reason-${context}-${entry.relationshipId}`;

  return (
    <div className={context === 'row' ? 'flex max-w-64 flex-col items-end gap-1' : 'flex flex-col items-start gap-1'}
      data-testid={`fm-reports-action-${context}`}>
      <Button type="button" size={context === 'row' ? 'sm' : 'default'} variant="outline"
        disabled={reason !== null}
        aria-describedby={reason ? reasonId : undefined}
        onClick={() => { if (reason === null) onOpen(); }}>
        Ver indicadores
      </Button>
      {reason && (
        <p id={reasonId} data-testid={`fm-reports-reason-${context}`}
          className={context === 'row' ? 'text-right text-xs text-muted-foreground' : 'text-xs text-muted-foreground'}>
          {reason}
        </p>
      )}
    </div>
  );
}

export function FacilityManagerPortfolioView() {
  const { getPortfolio, getMembers, setMembers } = useFacilityManagement();
  // Only assigned users with effective grants can open a client's delegated OTs.
  const { clients: operationalClients, loading: reportsAccessLoading, error: reportsAccessError } = useFacilityManagementOperationalClients();
  const accessibleWorkOrderClientIds = new Set(
    operationalClients.filter(canFacilityManagerViewWorkOrders).map((client) => client.clientOrganizationId),
  );
  const accessibleReportClientIds = new Set(
    operationalClients.filter(canFacilityManagerViewReports).map((client) => client.clientOrganizationId),
  );
  const [portfolio, setPortfolio] = useState<FacilityManagementPortfolioEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [members, setAssigned] = useState<FacilityManagementMember[]>([]);
  const [membersLoading, setMembersLoading] = useState(false);

  const reload = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setPortfolio(await getPortfolio());
    } catch (reloadError) {
      setError(reloadError instanceof Error ? reloadError.message : 'No se pudo cargar la cartera.');
    } finally {
      setLoading(false);
    }
  }, [getPortfolio]);

  useEffect(() => { void reload(); }, [reload]);

  const loadMembers = useCallback(async (relationshipId: string) => {
    setMembersLoading(true);
    try {
      setAssigned(await getMembers(relationshipId));
    } catch (membersError) {
      toast.error(membersError instanceof Error ? membersError.message : 'No se pudo cargar el equipo');
    } finally {
      setMembersLoading(false);
    }
  }, [getMembers]);

  useEffect(() => {
    if (selectedId) void loadMembers(selectedId); else setAssigned([]);
  }, [selectedId, loadMembers]);

  const selected = portfolio.find((entry) => entry.relationshipId === selectedId) ?? null;

  const handleSaveMembers = async (membershipIds: string[]) => {
    if (!selected) return;
    await setMembers(selected.relationshipId, membershipIds);
    await Promise.all([loadMembers(selected.relationshipId), reload()]);
  };

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="flex items-center gap-3 text-3xl font-bold"><Briefcase className="h-8 w-8 text-primary" />Clientes administrados</h1>
        <p className="mt-1 text-muted-foreground">
          Clientes que delegaron en tu empresa. Asigna qué personas de tu equipo atienden a cada uno; los permisos los define el cliente.
        </p>
      </div>

      {error && <div role="status" className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">{error}</div>}

      <Card>
        <CardHeader><CardTitle className="text-lg">Cartera ({portfolio.length})</CardTitle></CardHeader>
        <CardContent>
          {loading ? <p className="py-6 text-center text-sm text-muted-foreground">Cargando…</p> : portfolio.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">Ningún cliente delegó todavía en tu empresa.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow><TableHead>Cliente</TableHead><TableHead>Estado</TableHead><TableHead>Permisos recibidos</TableHead><TableHead>Equipo asignado</TableHead><TableHead className="text-right">Acción</TableHead></TableRow>
              </TableHeader>
              <TableBody>
                {portfolio.map((entry) => (
                  <TableRow key={entry.relationshipId}>
                    <TableCell className="font-medium">
                      {entry.clientOrganizationName}
                      {entry.clientOrganizationStatus !== 'active' && <span className="ml-2 text-xs text-muted-foreground">(cliente no activo)</span>}
                    </TableCell>
                    <TableCell><FacilityManagementStatusBadge status={entry.status} /></TableCell>
                    <TableCell>{entry.permissions.length}</TableCell>
                    <TableCell>{entry.assignedMemberCount}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-2">
                        <ReportsAccessAction entry={entry}
                          allowed={accessibleReportClientIds.has(entry.clientOrganizationId)}
                          loading={reportsAccessLoading} error={!!reportsAccessError} context="row"
                          onOpen={() => navigateToEntity({
                            view: 'managed-reports', managedClientId: entry.clientOrganizationId,
                          })} />
                        {accessibleWorkOrderClientIds.has(entry.clientOrganizationId) && (
                          <Button size="sm" variant="outline" onClick={() => navigateToEntity({
                            view: 'managed-work-orders',
                            managedClientId: entry.clientOrganizationId,
                          })}>Ver OT</Button>
                        )}
                        <Button size="sm" onClick={() => setSelectedId(entry.relationshipId)}>Gestionar</Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={!!selected} onOpenChange={(open) => { if (!open) setSelectedId(null); }}>
        <DialogContent className="max-h-[90vh] max-w-3xl overflow-y-auto">
          {selected && (
            <>
              <DialogHeader>
                <DialogTitle className="flex items-center gap-2">{selected.clientOrganizationName} <FacilityManagementStatusBadge status={selected.status} /></DialogTitle>
                <DialogDescription>
                  Solo el cliente puede cambiar permisos o el estado de la relación. El acceso operativo depende de los permisos concedidos y de tu asignación al cliente.
                </DialogDescription>
              </DialogHeader>
              <ReportsAccessAction entry={selected}
                allowed={accessibleReportClientIds.has(selected.clientOrganizationId)}
                loading={reportsAccessLoading} error={!!reportsAccessError} context="dialog"
                onOpen={() => {
                  setSelectedId(null);
                  navigateToEntity({ view: 'managed-reports', managedClientId: selected.clientOrganizationId });
                }} />
              {accessibleWorkOrderClientIds.has(selected.clientOrganizationId) && (
                <Button variant="outline" onClick={() => {
                  setSelectedId(null);
                  navigateToEntity({ view: 'managed-work-orders', managedClientId: selected.clientOrganizationId });
                }}>Ver órdenes de trabajo</Button>
              )}
              <section className="space-y-3">
                <h3 className="text-sm font-semibold">Permisos recibidos</h3>
                <FacilityManagementPermissionsEditor value={selected.permissions} />
              </section>
              <section className="space-y-3">
                <h3 className="text-sm font-semibold">Equipo asignado</h3>
                <FacilityManagementMembersEditor
                  assigned={members}
                  loading={membersLoading}
                  editable={isFacilityManagementRelationshipEditable(selected.status)}
                  onSave={handleSaveMembers}
                />
              </section>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
