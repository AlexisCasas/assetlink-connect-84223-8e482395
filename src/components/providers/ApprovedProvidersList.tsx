import { useMemo, useState } from 'react';
import { useProviderRelationships } from '@/hooks/useProviderRelationships';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { Users, Search, Briefcase } from 'lucide-react';
import type { OrganizationRelationshipStatus, OrganizationType } from '@/types/organization';
import type { ProviderDirectoryEntry } from '@/types/providerRelationship';

type StatusFilter = 'all' | 'none' | OrganizationRelationshipStatus;
// Desde Fase 1 · Punto 9B los Facility Managers se administran en su propia
// pantalla (#facility-management); este directorio solo trae proveedores y
// subcontratistas.
type HomologationOrganizationType = Extract<OrganizationType, 'provider_company' | 'subcontractor_company'>;
type TypeFilter = 'all' | HomologationOrganizationType;

const ORGANIZATION_TYPE_LABELS: Record<HomologationOrganizationType, string> = {
  provider_company: 'Proveedor',
  subcontractor_company: 'Subcontratista',
};

const STATUS_META: Record<'none' | OrganizationRelationshipStatus, { label: string; badgeClass: string }> = {
  none: { label: 'Disponible', badgeClass: 'text-muted-foreground' },
  pending: { label: 'Pendiente', badgeClass: 'text-warning border-warning/40' },
  active: { label: 'Homologado', badgeClass: 'text-success border-success/40' },
  suspended: { label: 'Inactivo', badgeClass: 'text-destructive border-destructive/40' },
  ended: { label: 'Finalizado', badgeClass: 'text-muted-foreground' },
};

const statusKey = (status: OrganizationRelationshipStatus | null): 'none' | OrganizationRelationshipStatus =>
  status ?? 'none';

// Next status per current status, and the label of the action that gets
// there — mirrors the state machine described for this screen. Every
// transition goes exclusively through set_provider_relationship_status.
const NEXT_ACTION: Record<'none' | OrganizationRelationshipStatus, { label: string; next: OrganizationRelationshipStatus }> = {
  none: { label: 'Agregar como pendiente', next: 'pending' },
  pending: { label: 'Homologar', next: 'active' },
  active: { label: 'Suspender', next: 'suspended' },
  suspended: { label: 'Reactivar', next: 'active' },
  ended: { label: 'Reabrir como pendiente', next: 'pending' },
};

export const ApprovedProvidersList = () => {
  const { directory, loading, error, setStatus } = useProviderRelationships();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [typeFilter, setTypeFilter] = useState<TypeFilter>('all');
  const [specialtyFilter, setSpecialtyFilter] = useState<string>('all');
  const [pendingActionId, setPendingActionId] = useState<string | null>(null);

  const availableSpecialties = useMemo(() => {
    const set = new Set<string>();
    directory.forEach((entry) => entry.specialties.forEach((specialty) => set.add(specialty)));
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }, [directory]);

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return directory.filter((entry) => {
      if (term && !entry.organizationName.toLowerCase().includes(term)) return false;
      if (statusFilter !== 'all' && statusKey(entry.relationshipStatus) !== statusFilter) return false;
      if (typeFilter !== 'all' && entry.organizationType !== typeFilter) return false;
      if (specialtyFilter !== 'all' && !entry.specialties.includes(specialtyFilter)) return false;
      return true;
    });
  }, [directory, search, statusFilter, typeFilter, specialtyFilter]);

  const handleAction = async (entry: ProviderDirectoryEntry) => {
    const action = NEXT_ACTION[statusKey(entry.relationshipStatus)];
    setPendingActionId(entry.organizationId);
    try {
      await setStatus(entry.organizationId, action.next);
      toast.success(`${entry.organizationName}: ${action.label.toLowerCase()} correctamente`);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'No se pudo actualizar la relación con el proveedor');
    } finally {
      setPendingActionId(null);
    }
  };

  if (loading) {
    return (
      <div className="p-6">
        <div className="animate-pulse space-y-4">
          <div className="h-8 bg-muted rounded w-1/3"></div>
          <div className="h-64 bg-muted rounded"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold flex items-center gap-3">
          <Users className="h-8 w-8 text-primary" />
          Proveedores Homologados
        </h1>
        <p className="text-muted-foreground mt-1">
          Proveedores y subcontratistas disponibles, y tu relación de homologación con cada uno. Los Facility Managers se gestionan en su propia sección.
        </p>
      </div>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          {error}
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Filtros</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-4">
          <div className="relative md:col-span-2">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              className="pl-9"
              placeholder="Buscar proveedor o subcontratista..."
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </div>
          <Select value={statusFilter} onValueChange={(value) => setStatusFilter(value as StatusFilter)}>
            <SelectTrigger><SelectValue placeholder="Estado" /></SelectTrigger>
            <SelectContent className="bg-popover">
              <SelectItem value="all">Todos los estados</SelectItem>
              <SelectItem value="none">Disponible</SelectItem>
              <SelectItem value="pending">Pendiente</SelectItem>
              <SelectItem value="active">Homologado</SelectItem>
              <SelectItem value="suspended">Inactivo</SelectItem>
              <SelectItem value="ended">Finalizado</SelectItem>
            </SelectContent>
          </Select>
          <Select value={typeFilter} onValueChange={(value) => setTypeFilter(value as TypeFilter)}>
            <SelectTrigger><SelectValue placeholder="Tipo de organización" /></SelectTrigger>
            <SelectContent className="bg-popover">
              <SelectItem value="all">Todos los tipos</SelectItem>
              <SelectItem value="provider_company">Proveedor</SelectItem>
              <SelectItem value="subcontractor_company">Subcontratista</SelectItem>
            </SelectContent>
          </Select>
          {availableSpecialties.length > 0 && (
            <Select value={specialtyFilter} onValueChange={setSpecialtyFilter}>
              <SelectTrigger><SelectValue placeholder="Especialidad" /></SelectTrigger>
              <SelectContent className="bg-popover">
                <SelectItem value="all">Todas las especialidades</SelectItem>
                {availableSpecialties.map((specialty) => (
                  <SelectItem key={specialty} value={specialty}>{specialty}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Organizaciones ({filtered.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {filtered.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <Users className="h-12 w-12 mx-auto mb-4 opacity-50" />
              <p>No hay organizaciones que coincidan con los filtros.</p>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Organización</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Especialidades</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead className="text-right">Acción</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((entry) => {
                  const key = statusKey(entry.relationshipStatus);
                  const meta = STATUS_META[key];
                  const action = NEXT_ACTION[key];
                  return (
                    <TableRow key={entry.organizationId}>
                      <TableCell className="font-medium">{entry.organizationName}</TableCell>
                      <TableCell>{ORGANIZATION_TYPE_LABELS[entry.organizationType as HomologationOrganizationType] ?? '-'}</TableCell>
                      <TableCell>
                        {entry.specialties.length > 0 ? (
                          <div className="flex flex-wrap gap-1">
                            {entry.specialties.map((specialty) => (
                              <Badge key={specialty} variant="outline">
                                <Briefcase className="h-3 w-3 mr-1" />
                                {specialty}
                              </Badge>
                            ))}
                          </div>
                        ) : (
                          <span className="text-muted-foreground">-</span>
                        )}
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline" className={meta.badgeClass}>{meta.label}</Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <Button
                          variant="outline"
                          size="sm"
                          disabled={pendingActionId === entry.organizationId}
                          onClick={() => void handleAction(entry)}
                        >
                          {pendingActionId === entry.organizationId ? 'Guardando…' : action.label}
                        </Button>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
};
