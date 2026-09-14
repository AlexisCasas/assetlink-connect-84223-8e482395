import { useMemo, useState } from 'react';
import { useProviderRelationships } from '@/hooks/useProviderRelationships';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Search, CheckCheck, X, Briefcase } from 'lucide-react';
import type { OrganizationType } from '@/types/organization';
import type { ProviderDirectoryEntry } from '@/types/providerRelationship';

interface RequestProviderSelectorProps {
  selectedOrganizationIds: string[];
  onChange: (organizationIds: string[]) => void;
}

const ORGANIZATION_TYPE_LABELS: Record<OrganizationType, string> = {
  provider_company: 'Proveedor',
  facility_manager: 'Facility Manager',
  subcontractor_company: 'Subcontratista',
  client_company: 'Cliente',
  platform_admin: 'Administración',
};

const STATUS_LABEL: Record<string, string> = {
  none: 'Disponible (no homologado)',
  pending: 'Pendiente de homologación',
  active: 'Homologado',
  suspended: 'Inactivo',
  ended: 'Finalizado',
};

const isSelectable = (entry: ProviderDirectoryEntry) => entry.relationshipStatus === 'active';

/**
 * Provider audience picker for private invitations (Bloque D/K). Its
 * EXCLUSIVE source is get_provider_relationship_directory (Fase 18) via
 * useProviderRelationships() — the same directory that backs "Proveedores
 * Homologados" (ApprovedProvidersList.tsx). Only organizations with an
 * 'active' relationship to the current client organization are selectable;
 * others render disabled with an explanation, never silently hidden.
 */
export function RequestProviderSelector({ selectedOrganizationIds, onChange }: RequestProviderSelectorProps) {
  const { directory, loading, error } = useProviderRelationships();
  const [search, setSearch] = useState('');
  const [specialtyFilter, setSpecialtyFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState<'all' | 'active'>('active');

  const availableSpecialties = useMemo(() => {
    const set = new Set<string>();
    directory.forEach((entry) => entry.specialties.forEach((specialty) => set.add(specialty)));
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }, [directory]);

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return directory.filter((entry) => {
      if (term && !entry.organizationName.toLowerCase().includes(term)) return false;
      if (specialtyFilter !== 'all' && !entry.specialties.includes(specialtyFilter)) return false;
      if (statusFilter === 'active' && !isSelectable(entry)) return false;
      return true;
    });
  }, [directory, search, specialtyFilter, statusFilter]);

  const selectedSet = useMemo(() => new Set(selectedOrganizationIds), [selectedOrganizationIds]);

  const toggle = (organizationId: string) => {
    if (selectedSet.has(organizationId)) {
      onChange(selectedOrganizationIds.filter((id) => id !== organizationId));
    } else {
      onChange([...selectedOrganizationIds, organizationId]);
    }
  };

  const selectAllFiltered = () => {
    const selectableIds = filtered.filter(isSelectable).map((entry) => entry.organizationId);
    const merged = new Set([...selectedOrganizationIds, ...selectableIds]);
    onChange(Array.from(merged));
  };

  const selectedEntries = useMemo(
    () => directory.filter((entry) => selectedSet.has(entry.organizationId)),
    [directory, selectedSet],
  );

  if (loading) {
    return <p className="text-sm text-muted-foreground">Cargando proveedores homologados…</p>;
  }

  return (
    <div className="space-y-3">
      {error && <p className="text-sm text-destructive">{error}</p>}

      {selectedEntries.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {selectedEntries.map((entry) => (
            <Badge key={entry.organizationId} variant="secondary" className="pl-2 pr-1 py-1">
              {entry.organizationName}
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="h-4 w-4 ml-1 hover:bg-transparent"
                onClick={() => toggle(entry.organizationId)}
              >
                <X className="h-3 w-3" />
              </Button>
            </Badge>
          ))}
        </div>
      )}

      <div className="flex flex-col md:flex-row gap-2">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Buscar por nombre…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
        {availableSpecialties.length > 0 && (
          <Select value={specialtyFilter} onValueChange={setSpecialtyFilter}>
            <SelectTrigger className="w-full md:w-[200px]">
              <SelectValue placeholder="Especialidad" />
            </SelectTrigger>
            <SelectContent className="bg-popover">
              <SelectItem value="all">Todas las especialidades</SelectItem>
              {availableSpecialties.map((specialty) => (
                <SelectItem key={specialty} value={specialty}>{specialty}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}
        <Select value={statusFilter} onValueChange={(value) => setStatusFilter(value as 'all' | 'active')}>
          <SelectTrigger className="w-full md:w-[200px]">
            <SelectValue placeholder="Estado" />
          </SelectTrigger>
          <SelectContent className="bg-popover">
            <SelectItem value="active">Solo homologados</SelectItem>
            <SelectItem value="all">Todos los estados</SelectItem>
          </SelectContent>
        </Select>
        <Button type="button" variant="outline" size="sm" onClick={selectAllFiltered} disabled={filtered.length === 0}>
          <CheckCheck className="h-4 w-4 mr-2" />
          Seleccionar todos los resultados filtrados
        </Button>
      </div>

      <div className="border rounded-lg max-h-64 overflow-y-auto divide-y">
        {filtered.length === 0 ? (
          <div className="p-4 text-center text-muted-foreground text-sm">
            No se encontraron proveedores con estos filtros.
          </div>
        ) : (
          filtered.map((entry) => {
            const selectable = isSelectable(entry);
            const checked = selectedSet.has(entry.organizationId);
            return (
              <div
                key={entry.organizationId}
                className={`flex items-center justify-between p-3 ${selectable ? 'cursor-pointer hover:bg-muted/50' : 'opacity-60'} ${checked ? 'bg-primary/10' : ''}`}
                onClick={() => selectable && toggle(entry.organizationId)}
                title={selectable ? undefined : 'Solo proveedores homologados/activos pueden seleccionarse.'}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <Checkbox checked={checked} disabled={!selectable} onCheckedChange={() => selectable && toggle(entry.organizationId)} />
                  <div className="min-w-0">
                    <p className="font-medium text-sm truncate">{entry.organizationName}</p>
                    <div className="flex flex-wrap items-center gap-1 mt-0.5">
                      <Badge variant="outline" className="text-xs">{ORGANIZATION_TYPE_LABELS[entry.organizationType]}</Badge>
                      {entry.specialties.slice(0, 3).map((specialty) => (
                        <Badge key={specialty} variant="outline" className="text-xs">
                          <Briefcase className="h-3 w-3 mr-1" />
                          {specialty}
                        </Badge>
                      ))}
                    </div>
                  </div>
                </div>
                <Badge
                  variant="outline"
                  className={selectable ? 'text-success border-success/40 shrink-0' : 'text-muted-foreground shrink-0'}
                >
                  {STATUS_LABEL[entry.relationshipStatus ?? 'none']}
                </Badge>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
