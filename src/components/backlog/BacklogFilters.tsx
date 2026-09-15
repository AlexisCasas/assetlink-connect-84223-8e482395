import { Search } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import type { BacklogFilterState } from '@/types/maintenanceNotice';
import {
  MAINTENANCE_NOTICE_PRIORITY_LABELS,
  MAINTENANCE_NOTICE_SOURCE_LABELS,
  MAINTENANCE_NOTICE_STATUS_LABELS,
} from '@/types/maintenanceNotice';

interface BacklogFiltersProps {
  value: BacklogFilterState;
  onChange: (next: BacklogFilterState) => void;
  /** Sedes presentes en los avisos cargados (snapshot), no el catálogo
   * completo: filtrar por una sede sin avisos no aporta nada. */
  branches: Array<{ id: string; name: string }>;
}

export function BacklogFilters({ value, onChange, branches }: BacklogFiltersProps) {
  const set = <K extends keyof BacklogFilterState>(key: K, next: BacklogFilterState[K]) =>
    onChange({ ...value, [key]: next });

  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
      <div className="space-y-1.5 lg:col-span-1">
        <Label className="text-xs">Buscar</Label>
        <div className="relative">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            value={value.search}
            onChange={(event) => set('search', event.target.value)}
            placeholder="N° de aviso, título, activo…"
            className="pl-8"
          />
        </div>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">Estado</Label>
        <Select value={value.status} onValueChange={(next) => set('status', next as BacklogFilterState['status'])}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="pending">Pendientes (sin revisar + revisados)</SelectItem>
            <SelectItem value="all">Todos</SelectItem>
            <SelectItem value="open">{MAINTENANCE_NOTICE_STATUS_LABELS.open}</SelectItem>
            <SelectItem value="triaged">{MAINTENANCE_NOTICE_STATUS_LABELS.triaged}</SelectItem>
            <SelectItem value="converted">{MAINTENANCE_NOTICE_STATUS_LABELS.converted}</SelectItem>
            <SelectItem value="dismissed">{MAINTENANCE_NOTICE_STATUS_LABELS.dismissed}</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">Prioridad</Label>
        <Select value={value.priority} onValueChange={(next) => set('priority', next as BacklogFilterState['priority'])}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todas</SelectItem>
            <SelectItem value="urgent">{MAINTENANCE_NOTICE_PRIORITY_LABELS.urgent}</SelectItem>
            <SelectItem value="high">{MAINTENANCE_NOTICE_PRIORITY_LABELS.high}</SelectItem>
            <SelectItem value="medium">{MAINTENANCE_NOTICE_PRIORITY_LABELS.medium}</SelectItem>
            <SelectItem value="low">{MAINTENANCE_NOTICE_PRIORITY_LABELS.low}</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">Sede</Label>
        <Select value={value.branchId} onValueChange={(next) => set('branchId', next)}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todas</SelectItem>
            {branches.map((branch) => (
              <SelectItem key={branch.id} value={branch.id}>{branch.name}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">Origen</Label>
        <Select value={value.source} onValueChange={(next) => set('source', next as BacklogFilterState['source'])}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos</SelectItem>
            <SelectItem value="manual">{MAINTENANCE_NOTICE_SOURCE_LABELS.manual}</SelectItem>
            <SelectItem value="inspection_run">{MAINTENANCE_NOTICE_SOURCE_LABELS.inspection_run}</SelectItem>
          </SelectContent>
        </Select>
      </div>
    </div>
  );
}
