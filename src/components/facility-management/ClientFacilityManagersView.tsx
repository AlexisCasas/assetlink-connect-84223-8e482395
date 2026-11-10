import { useCallback, useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Building2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { useAuth } from '@/contexts/AuthContext';
import { useFacilityManagement } from '@/hooks/useFacilityManagement';
import { getFacilityManagementTransitions, isFacilityManagementRelationshipEditable } from '@/lib/facilityManagement';
import type { OrganizationRelationshipStatus } from '@/types/organization';
import type {
  FacilityManagementMember,
  FacilityManagementPermission,
  FacilityManagementRelationship,
  FacilityManagerDirectoryEntry,
} from '@/types/facilityManagement';
import { FacilityManagementPermissionsEditor } from './FacilityManagementPermissionsEditor';
import { FacilityManagementMembersList } from './FacilityManagementMembersList';
import { FacilityManagementStatusBadge } from './FacilityManagementStatusBadge';

/** Vista del cliente (owner/admin): vincula empresas FM, concede permisos,
 * cambia el estado de la relación y ve el equipo asignado en solo lectura.
 * Nunca asigna personas del FM ni toca sus roles internos. */
export function ClientFacilityManagersView() {
  const { currentOrganization } = useAuth();
  const clientId = currentOrganization?.id ?? null;
  const { listDirectory, getRelationships, createRelationship, setPermissions, setStatus, getMembers } = useFacilityManagement();
  const [directory, setDirectory] = useState<FacilityManagerDirectoryEntry[]>([]);
  const [relationships, setRelationships] = useState<FacilityManagementRelationship[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [members, setMembers] = useState<FacilityManagementMember[]>([]);
  const [membersLoading, setMembersLoading] = useState(false);

  const reload = useCallback(async () => {
    if (!clientId) return;
    setLoading(true);
    setError(null);
    try {
      const [nextDirectory, nextRelationships] = await Promise.all([listDirectory(clientId), getRelationships(clientId)]);
      setDirectory(nextDirectory);
      setRelationships(nextRelationships);
    } catch (reloadError) {
      setError(reloadError instanceof Error ? reloadError.message : 'No se pudo cargar la información.');
    } finally {
      setLoading(false);
    }
  }, [clientId, listDirectory, getRelationships]);

  useEffect(() => { void reload(); }, [reload]);

  const selected = relationships.find((relationship) => relationship.relationshipId === selectedId) ?? null;

  useEffect(() => {
    if (!selectedId) { setMembers([]); return; }
    let cancelled = false;
    setMembersLoading(true);
    getMembers(selectedId)
      .then((rows) => { if (!cancelled) setMembers(rows); })
      .catch((membersError) => { if (!cancelled) toast.error(membersError instanceof Error ? membersError.message : 'No se pudo cargar el equipo'); })
      .finally(() => { if (!cancelled) setMembersLoading(false); });
    return () => { cancelled = true; };
  }, [selectedId, getMembers]);

  const run = async (id: string, action: () => Promise<unknown>, success: string) => {
    setBusyId(id);
    try {
      await action();
      toast.success(success);
      await reload();
    } catch (actionError) {
      toast.error(actionError instanceof Error ? actionError.message : 'No se pudo completar la acción');
    } finally {
      setBusyId(null);
    }
  };

  const handleLink = (entry: FacilityManagerDirectoryEntry) =>
    run(entry.facilityManagerOrganizationId, () => createRelationship(entry.facilityManagerOrganizationId),
      `${entry.facilityManagerOrganizationName} vinculado como pendiente`);

  const handleStatus = (relationship: FacilityManagementRelationship, next: OrganizationRelationshipStatus, label: string) =>
    run(relationship.relationshipId, () => setStatus(relationship.relationshipId, next), `${relationship.facilityManagerOrganizationName}: ${label.toLowerCase()} correctamente`);

  const handlePermissions = async (permissions: FacilityManagementPermission[]) => {
    if (!selected) return;
    try {
      await setPermissions(selected.relationshipId, permissions);
      toast.success('Permisos actualizados');
      await reload();
    } catch (saveError) {
      toast.error(saveError instanceof Error ? saveError.message : 'No se pudieron guardar los permisos');
    }
  };

  const unlinked = directory.filter((entry) => !entry.relationshipId);

  return (
    <div className="space-y-6 p-6">
      <div>
        <h1 className="flex items-center gap-3 text-3xl font-bold"><Building2 className="h-8 w-8 text-primary" />Facility Managers</h1>
        <p className="mt-1 text-muted-foreground">
          Empresas que administran tus activos y operación. Concedes permisos a la empresa; ella decide qué personas de su equipo te atienden.
        </p>
      </div>

      {error && <div role="status" className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">{error}</div>}

      <Card>
        <CardHeader><CardTitle className="text-lg">Relaciones ({relationships.length})</CardTitle></CardHeader>
        <CardContent>
          {loading ? <p className="py-6 text-center text-sm text-muted-foreground">Cargando…</p> : relationships.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">Todavía no vinculaste ningún Facility Manager.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow><TableHead>Facility Manager</TableHead><TableHead>Estado</TableHead><TableHead>Permisos</TableHead><TableHead className="text-right">Acciones</TableHead></TableRow>
              </TableHeader>
              <TableBody>
                {relationships.map((relationship) => (
                  <TableRow key={relationship.relationshipId}>
                    <TableCell className="font-medium">{relationship.facilityManagerOrganizationName}</TableCell>
                    <TableCell><FacilityManagementStatusBadge status={relationship.status} /></TableCell>
                    <TableCell>{relationship.permissions.length}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex flex-wrap justify-end gap-2">
                        {getFacilityManagementTransitions(relationship.status).map((transition) => (
                          <Button
                            key={transition.next}
                            size="sm"
                            variant={transition.next === 'ended' ? 'outline' : 'secondary'}
                            disabled={busyId === relationship.relationshipId}
                            onClick={() => void handleStatus(relationship, transition.next, transition.label)}
                          >
                            {transition.label}
                          </Button>
                        ))}
                        <Button size="sm" onClick={() => setSelectedId(relationship.relationshipId)}>Gestionar</Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-lg">Facility Managers disponibles ({unlinked.length})</CardTitle></CardHeader>
        <CardContent>
          {loading ? <p className="py-6 text-center text-sm text-muted-foreground">Cargando…</p> : unlinked.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">No hay otros Facility Managers activos para vincular.</p>
          ) : (
            <Table>
              <TableHeader><TableRow><TableHead>Empresa</TableHead><TableHead className="text-right">Acción</TableHead></TableRow></TableHeader>
              <TableBody>
                {unlinked.map((entry) => (
                  <TableRow key={entry.facilityManagerOrganizationId}>
                    <TableCell className="font-medium">{entry.facilityManagerOrganizationName}</TableCell>
                    <TableCell className="text-right">
                      <Button size="sm" variant="outline" disabled={busyId === entry.facilityManagerOrganizationId} onClick={() => void handleLink(entry)}>
                        {busyId === entry.facilityManagerOrganizationId ? 'Vinculando…' : 'Vincular'}
                      </Button>
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
                <DialogTitle className="flex items-center gap-2">{selected.facilityManagerOrganizationName} <FacilityManagementStatusBadge status={selected.status} /></DialogTitle>
                <DialogDescription>
                  Los permisos se administran por cliente. Cada módulo requiere sus permisos específicos y la asignación del equipo del Facility Manager.
                </DialogDescription>
              </DialogHeader>
              <section className="space-y-3">
                <h3 className="text-sm font-semibold">Permisos delegados</h3>
                <FacilityManagementPermissionsEditor
                  value={selected.permissions}
                  onSave={handlePermissions}
                  disabled={!isFacilityManagementRelationshipEditable(selected.status)}
                  disabledReason="La relación está finalizada. Reábrela como pendiente para volver a configurar permisos."
                />
              </section>
              <section className="space-y-3">
                <h3 className="text-sm font-semibold">Equipo asignado por el Facility Manager</h3>
                <FacilityManagementMembersList members={members} loading={membersLoading} />
              </section>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
