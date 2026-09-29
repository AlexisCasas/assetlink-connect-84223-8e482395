import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Label } from '@/components/ui/label';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Check, ChevronsUpDown, Loader2, Package, X } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useAssets } from '@/hooks/useAssets';
import { useFacilityManagementRequestAssets } from '@/hooks/useFacilityManagementReferenceDirectories';
import { ASSET_NODE_TYPE_LABELS } from '@/lib/assetLabels';
import { flattenAssetTree } from '@/lib/assetTree';
import type { Asset, AssetNodeType } from '@/types/asset';

/** What the request form needs from the picked asset (a full Asset in direct
 * mode; the minimal directory row in delegated mode). */
export type RequestAssetSelection = Pick<Asset, 'id' | 'name' | 'nodeType'>;

interface RequestAssetPickerProps {
  assetId: string;
  /** `path` is the "›"-joined hierarchical breadcrumb of the picked asset,
   * or '' when clearing the selection. */
  onChange: (assetId: string, asset: Asset | null, path: string) => void;
  /** El activo es opcional en una solicitud pero obligatorio en un aviso de
   * avería (un aviso siempre es sobre algo). Sin esto, el backlog mostraría
   * "(opcional)" sobre un campo que sí exige. */
  label?: string;
}

interface AssetOption {
  id: string;
  name: string;
  code: string | null;
  nodeType: AssetNodeType;
  path: string;
  searchText: string;
}

/** Combobox to link a request to a real tenant-aware asset of the active
 * organization. Calls useAssets() itself — React Query dedupes the fetch
 * with any other mounted instance (e.g. the Activos module) by query key. */
export function RequestAssetPicker({ assetId, onChange, label = 'Activo asociado (opcional)' }: RequestAssetPickerProps) {
  const { assets, assetTree, loading, error } = useAssets();
  const options = useMemo<AssetOption[]>(() => flattenAssetTree(assetTree).map(({ asset, path }) => ({
    id: asset.id,
    name: asset.name,
    code: asset.code ?? null,
    nodeType: asset.nodeType,
    path,
    searchText: [asset.name, asset.code, asset.serialNumber, path].filter(Boolean).join(' '),
  })), [assetTree]);
  const selected = assetId ? assets.find((asset) => asset.id === assetId) ?? null : null;

  return (
    <RequestAssetCombobox
      label={label}
      assetId={assetId}
      options={options}
      selected={selected ? { id: selected.id, name: selected.name, nodeType: selected.nodeType } : null}
      loading={loading}
      error={error}
      empty={!loading && assets.length === 0}
      emptyMessage="Aún no tienes activos registrados. Puedes crear una solicitud sin activo o registrar activos desde el módulo Activos."
      onSelect={(option) => {
        const asset = option ? assets.find((candidate) => candidate.id === option.id) ?? null : null;
        onChange(option?.id ?? '', asset, option?.path ?? '');
      }}
    />
  );
}

/** Facility Manager (9C.4): the client's non-archived assets from the minimal
 * request directory (get_facility_management_request_assets). requests.* does
 * not imply assets.view, so useAssets() is never used here. */
export function DelegatedRequestAssetPicker({ clientOrganizationId, assetId, onChange, label = 'Activo asociado (opcional)' }: {
  clientOrganizationId: string;
  assetId: string;
  onChange: (assetId: string, asset: RequestAssetSelection | null, path: string) => void;
  label?: string;
}) {
  const { assets, loading, error } = useFacilityManagementRequestAssets(clientOrganizationId);
  const options = useMemo<AssetOption[]>(() => assets.map((asset) => ({
    ...asset,
    searchText: [asset.name, asset.code, asset.path].filter(Boolean).join(' '),
  })), [assets]);
  const selected = assetId ? options.find((option) => option.id === assetId) ?? null : null;

  return (
    <RequestAssetCombobox
      label={label}
      assetId={assetId}
      options={options}
      selected={selected}
      loading={loading}
      error={error}
      empty={!loading && assets.length === 0}
      emptyMessage="El cliente no tiene activos disponibles. Puedes crear la solicitud sin activo."
      onSelect={(option) => onChange(option?.id ?? '', option ? { id: option.id, name: option.name, nodeType: option.nodeType } : null, option?.path ?? '')}
    />
  );
}

function RequestAssetCombobox({ label, assetId, options, selected, loading, error, empty, emptyMessage, onSelect }: {
  label: string;
  assetId: string;
  options: AssetOption[];
  selected: RequestAssetSelection | null;
  loading: boolean;
  error: string | null;
  empty: boolean;
  emptyMessage: string;
  onSelect: (option: AssetOption | null) => void;
}) {
  const [open, setOpen] = useState(false);

  if (empty) {
    return (
      <div className="space-y-2">
        <Label>{label}</Label>
        <p className="rounded-md border border-dashed p-3 text-sm text-muted-foreground">{emptyMessage}</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button
            type="button"
            variant="outline"
            role="combobox"
            aria-expanded={open}
            disabled={loading}
            className="w-full justify-between font-normal"
          >
            {loading ? (
              <span className="flex items-center text-muted-foreground">
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Cargando activos…
              </span>
            ) : selected ? (
              <span className="flex items-center gap-2 truncate">
                <Package className="h-4 w-4 shrink-0 text-muted-foreground" />
                <span className="truncate">{selected.name}</span>
                <Badge variant="secondary" className="shrink-0 text-xs">
                  {ASSET_NODE_TYPE_LABELS[selected.nodeType]}
                </Badge>
              </span>
            ) : (
              <span className="text-muted-foreground">Sin activo específico</span>
            )}
            <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
          <Command>
            <CommandInput placeholder="Buscar por nombre, código o N° de serie…" />
            <CommandList>
              <CommandEmpty>No se encontraron activos.</CommandEmpty>
              <CommandGroup>
                <CommandItem
                  value="__none__"
                  onSelect={() => {
                    onSelect(null);
                    setOpen(false);
                  }}
                >
                  <Check className={cn('mr-2 h-4 w-4', !assetId ? 'opacity-100' : 'opacity-0')} />
                  Sin activo específico
                </CommandItem>
                {options.map((option) => (
                  <CommandItem
                    key={option.id}
                    value={option.searchText}
                    onSelect={() => {
                      onSelect(option);
                      setOpen(false);
                    }}
                  >
                    <Check className={cn('mr-2 h-4 w-4 shrink-0', assetId === option.id ? 'opacity-100' : 'opacity-0')} />
                    <span className="flex min-w-0 flex-col">
                      <span className="truncate">{option.name}{option.code ? ` (${option.code})` : ''}</span>
                      <span className="truncate text-xs text-muted-foreground">{option.path}</span>
                    </span>
                  </CommandItem>
                ))}
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
      {selected && (
        <div className="flex items-center justify-between rounded-md bg-muted/30 p-2 text-xs text-muted-foreground">
          <span className="truncate">
            {options.find((option) => option.id === selected.id)?.path ?? selected.name}
          </span>
          <Button type="button" variant="ghost" size="sm" className="h-6 px-2" onClick={() => onSelect(null)}>
            <X className="h-3 w-3 mr-1" />
            Quitar
          </Button>
        </div>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
