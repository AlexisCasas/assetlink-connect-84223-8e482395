import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Label } from '@/components/ui/label';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Check, ChevronsUpDown, Loader2, Package, X } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useAssets } from '@/hooks/useAssets';
import { ASSET_NODE_TYPE_LABELS } from '@/lib/assetLabels';
import { flattenAssetTree } from '@/lib/assetTree';
import type { Asset } from '@/types/asset';

interface RequestAssetPickerProps {
  assetId: string;
  onChange: (assetId: string, asset: Asset | null) => void;
}

/** Combobox to link a request to a real tenant-aware asset of the active
 * organization. Calls useAssets() itself — React Query dedupes the fetch
 * with any other mounted instance (e.g. the Activos module) by query key. */
export function RequestAssetPicker({ assetId, onChange }: RequestAssetPickerProps) {
  const { assets, assetTree, loading, error } = useAssets();
  const [open, setOpen] = useState(false);

  const options = useMemo(() => flattenAssetTree(assetTree), [assetTree]);
  const selected = assetId ? assets.find((asset) => asset.id === assetId) ?? null : null;

  if (!loading && assets.length === 0) {
    return (
      <div className="space-y-2">
        <Label>Activo asociado (opcional)</Label>
        <p className="rounded-md border border-dashed p-3 text-sm text-muted-foreground">
          Aún no tienes activos registrados. Puedes crear una solicitud sin activo o registrar
          activos desde el módulo Activos.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <Label>Activo asociado (opcional)</Label>
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
                    onChange('', null);
                    setOpen(false);
                  }}
                >
                  <Check className={cn('mr-2 h-4 w-4', !assetId ? 'opacity-100' : 'opacity-0')} />
                  Sin activo específico
                </CommandItem>
                {options.map(({ asset, path }) => (
                  <CommandItem
                    key={asset.id}
                    value={[asset.name, asset.code, asset.serialNumber, path].filter(Boolean).join(' ')}
                    onSelect={() => {
                      onChange(asset.id, asset);
                      setOpen(false);
                    }}
                  >
                    <Check className={cn('mr-2 h-4 w-4 shrink-0', assetId === asset.id ? 'opacity-100' : 'opacity-0')} />
                    <span className="flex min-w-0 flex-col">
                      <span className="truncate">{asset.name}{asset.code ? ` (${asset.code})` : ''}</span>
                      <span className="truncate text-xs text-muted-foreground">{path}</span>
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
            {options.find((option) => option.asset.id === selected.id)?.path ?? selected.name}
          </span>
          <Button type="button" variant="ghost" size="sm" className="h-6 px-2" onClick={() => onChange('', null)}>
            <X className="h-3 w-3 mr-1" />
            Quitar
          </Button>
        </div>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
