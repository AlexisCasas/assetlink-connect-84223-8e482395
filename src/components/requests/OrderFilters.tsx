import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuCheckboxItem,
  DropdownMenuTrigger,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import { Filter, Columns3 } from 'lucide-react';

export interface OrderFiltersProps<TColumnKey extends string> {
  filterStore: string;
  filterBranch: string;
  filterDate: string;
  filterServiceType: string;
  /** Optional for request lists, without changing other consumers. */
  filterStatus?: string;
  uniqueStores: string[];
  uniqueBranches: string[];
  onFilterStoreChange: (value: string) => void;
  onFilterBranchChange: (value: string) => void;
  onFilterDateChange: (value: string) => void;
  onFilterServiceTypeChange: (value: string) => void;
  onFilterStatusChange?: (value: string) => void;
  onClearFilters: () => void;
  columnLabels: Record<TColumnKey, string>;
  visibleColumns: Record<TColumnKey, boolean>;
  onToggleColumn: (column: TColumnKey) => void;
  onResetColumns: () => void;
}

export function OrderFilters<TColumnKey extends string>({
  filterStore,
  filterBranch,
  filterDate,
  filterServiceType,
  filterStatus = 'all',
  uniqueStores,
  uniqueBranches,
  onFilterStoreChange,
  onFilterBranchChange,
  onFilterDateChange,
  onFilterServiceTypeChange,
  onFilterStatusChange,
  onClearFilters,
  columnLabels,
  visibleColumns,
  onToggleColumn,
  onResetColumns,
}: OrderFiltersProps<TColumnKey>) {
  return (
    <Card className="p-4">
      <div className="flex items-center gap-2 mb-3">
        <Filter className="h-4 w-4 text-muted-foreground" />
        <span className="text-sm font-medium">Filtros</span>
      </div>
      <div className={`grid grid-cols-1 md:grid-cols-2 gap-4 ${onFilterStatusChange ? "lg:grid-cols-6" : "lg:grid-cols-5"}`}>
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Sucursal</Label>
          <Select value={filterStore} onValueChange={onFilterStoreChange}>
            <SelectTrigger>
              <SelectValue placeholder="Todas las sucursales" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todas las sucursales</SelectItem>
              {uniqueStores.map((store) => (
                <SelectItem key={store} value={store}>{store}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Sede</Label>
          <Select value={filterBranch} onValueChange={onFilterBranchChange}>
            <SelectTrigger>
              <SelectValue placeholder="Todas las sedes" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todas las sedes</SelectItem>
              {uniqueBranches.map((branch) => (
                <SelectItem key={branch} value={branch}>{branch}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Fecha de Registro</Label>
          <Input
            type="date"
            value={filterDate}
            onChange={(e) => onFilterDateChange(e.target.value)}
            className="h-10"
          />
        </div>

        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">Tipo de Servicio</Label>
          <Select value={filterServiceType} onValueChange={onFilterServiceTypeChange}>
            <SelectTrigger>
              <SelectValue placeholder="Todos los tipos" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos los tipos</SelectItem>
              <SelectItem value="emergencia">Emergencia</SelectItem>
              <SelectItem value="correctivo">Correctivo</SelectItem>
              <SelectItem value="preventivo">Preventivo</SelectItem>
              <SelectItem value="proyecto">Proyecto</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {onFilterStatusChange && (
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Estado</Label>
            <Select value={filterStatus} onValueChange={onFilterStatusChange}>
              <SelectTrigger>
                <SelectValue placeholder="Todos los estados" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos los estados</SelectItem>
                <SelectItem value="sent">Enviadas</SelectItem>
                <SelectItem value="quoted">Cotizadas</SelectItem>
                <SelectItem value="completed">Completadas</SelectItem>
              </SelectContent>
            </Select>
          </div>
        )}
        <div className="flex items-end gap-2">
          <Button variant="outline" size="sm" onClick={onClearFilters} className="flex-1">
            Limpiar filtros
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm">
                <Columns3 className="h-4 w-4 mr-2" />
                Columnas
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuLabel>Columnas visibles</DropdownMenuLabel>
              <DropdownMenuSeparator />
              {(Object.keys(columnLabels) as TColumnKey[]).map((column) => (
                <DropdownMenuCheckboxItem
                  key={column}
                  checked={visibleColumns[column]}
                  onCheckedChange={() => onToggleColumn(column)}
                >
                  {columnLabels[column]}
                </DropdownMenuCheckboxItem>
              ))}
              <DropdownMenuSeparator />
              <div className="px-2 py-1.5">
                <Button variant="ghost" size="sm" onClick={onResetColumns} className="w-full text-xs">
                  Mostrar todas
                </Button>
              </div>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>
    </Card>
  );
}