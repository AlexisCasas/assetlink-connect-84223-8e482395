import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  ChevronDown,
  Building,
  Building2,
  MapPin,
  Settings2,
  Truck,
  Wrench,
  Cog,
  CircleDot,
  Plus,
  Minus,
  Eye,
  EyeOff,
  Loader2,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { UseAssetsResult } from '@/hooks/useAssets';
import type { AssetNodeType, AssetStatus, AssetTreeNode } from '@/types/asset';
import { ASSET_NODE_TYPE_ORDER, ASSET_NODE_TYPE_LABELS, ASSET_EDITABLE_STATUSES, ASSET_STATUS_LABELS, getAssetStatusBadgeClass } from '@/lib/assetLabels';

const NODE_TYPE_ICONS: Record<AssetNodeType, typeof Building2> = {
  structure: Building2,
  site: Building,
  area: MapPin,
  system: Settings2,
  fleet: Truck,
  equipment: Wrench,
  component: Cog,
  subcomponent: CircleDot,
};

const suggestNextNodeType = (parentType?: AssetNodeType): AssetNodeType => {
  if (!parentType) return 'structure';
  const index = ASSET_NODE_TYPE_ORDER.indexOf(parentType);
  return ASSET_NODE_TYPE_ORDER[Math.min(index + 1, ASSET_NODE_TYPE_ORDER.length - 1)];
};

interface AssetTreeProps {
  state: UseAssetsResult;
}

export function AssetTree({ state }: AssetTreeProps) {
  const { assetTree, assets, categories, branches, loading, error, canManageAssets, showArchived, setShowArchived, selectedAssetId, selectAsset, createAsset } = state;

  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set());
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogParentId, setDialogParentId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [form, setForm] = useState<{ name: string; nodeType: AssetNodeType; status: AssetStatus; branchId: string; assetCategoryId: string }>({
    name: '',
    nodeType: 'structure',
    status: 'active',
    branchId: '',
    assetCategoryId: '',
  });

  const findAssetById = (id: string) => assets.find((asset) => asset.id === id) ?? null;
  const selectedParent = dialogParentId ? findAssetById(dialogParentId) : null;

  const toggleNode = (nodeId: string) => {
    setExpandedNodes((current) => {
      const next = new Set(current);
      if (next.has(nodeId)) next.delete(nodeId);
      else next.add(nodeId);
      return next;
    });
  };

  const openDialog = (parentId: string | null) => {
    setDialogParentId(parentId);
    const parent = parentId ? findAssetById(parentId) : null;
    setForm({
      name: '',
      nodeType: suggestNextNodeType(parent?.nodeType),
      status: 'active',
      branchId: parent?.branchId ?? '',
      assetCategoryId: '',
    });
    setDialogOpen(true);
  };

  const submitDialog = async () => {
    if (!form.name.trim()) return;
    setSubmitting(true);
    const created = await createAsset({
      name: form.name.trim(),
      nodeType: form.nodeType,
      status: form.status,
      parentAssetId: dialogParentId,
      branchId: form.branchId || null,
      assetCategoryId: form.assetCategoryId || null,
    });
    setSubmitting(false);
    if (created) {
      if (dialogParentId) setExpandedNodes((current) => new Set(current).add(dialogParentId));
      setDialogOpen(false);
    }
  };

  const renderNode = (node: AssetTreeNode, level: number = 0) => {
    const hasChildren = node.children.length > 0;
    const isExpanded = expandedNodes.has(node.id);
    const isSelected = selectedAssetId === node.id;
    const Icon = NODE_TYPE_ICONS[node.nodeType] ?? Building2;

    return (
      <div key={node.id} className="select-none">
        <div
          className={cn(
            'group flex items-center py-2 px-2 rounded-md cursor-pointer hover:bg-muted/50 transition-colors',
            isSelected && 'bg-primary/10 border-l-2 border-l-primary',
            level === 0 && 'font-semibold',
          )}
          style={{ paddingLeft: `${level * 20 + 8}px` }}
          onClick={() => selectAsset(node.id)}
        >
          {hasChildren && (
            <Button
              variant="ghost"
              size="sm"
              className="h-6 w-6 p-0 mr-1"
              onClick={(event) => {
                event.stopPropagation();
                toggleNode(node.id);
              }}
            >
              {isExpanded ? <Minus className="h-3 w-3" /> : <Plus className="h-3 w-3" />}
            </Button>
          )}

          <Icon className="h-4 w-4 mr-2 text-muted-foreground shrink-0" />

          <span className="flex-1 text-sm truncate">{node.name}</span>

          <Badge variant="outline" className={cn('ml-2 shrink-0 text-xs', getAssetStatusBadgeClass(node.status))}>
            {ASSET_STATUS_LABELS[node.status]}
          </Badge>

          {canManageAssets && (
            <Button
              variant="ghost"
              size="sm"
              className="h-6 w-6 p-0 ml-1 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
              onClick={(event) => {
                event.stopPropagation();
                openDialog(node.id);
              }}
              title="Agregar subactivo"
            >
              <Plus className="h-3 w-3" />
            </Button>
          )}
        </div>

        {hasChildren && isExpanded && (
          <div className="ml-2">
            {node.children.map((child) => renderNode(child, level + 1))}
          </div>
        )}
      </div>
    );
  };

  return (
    <Card className="h-full">
      <CardHeader>
        <CardTitle className="flex items-center justify-between gap-2 text-lg">
          <div className="flex items-center">
            <Building2 className="h-5 w-5 mr-2" />
            Estructura de Activos
          </div>
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={() => setShowArchived(!showArchived)}>
              {showArchived ? <EyeOff className="h-4 w-4 mr-1" /> : <Eye className="h-4 w-4 mr-1" />}
              {showArchived ? 'Ocultar archivados' : 'Ver archivados'}
            </Button>
            {canManageAssets && (
              <Button variant="default" size="sm" onClick={() => openDialog(selectedAssetId)}>
                <Plus className="h-4 w-4 mr-1" />
                {selectedAssetId ? 'Agregar subactivo' : 'Agregar activo raíz'}
              </Button>
            )}
          </div>
        </CardTitle>
      </CardHeader>
      <CardContent className="p-4">
        {loading ? (
          <div className="flex items-center justify-center py-10 text-muted-foreground">
            <Loader2 className="h-5 w-5 mr-2 animate-spin" />
            Cargando activos…
          </div>
        ) : error ? (
          <p className="py-8 text-center text-sm text-destructive">{error}</p>
        ) : assets.length === 0 ? (
          <div className="py-12 text-center text-muted-foreground">
            <Building2 className="mx-auto mb-3 h-8 w-8 opacity-50" />
            <p className="font-medium">Aún no tienes activos registrados. Crea tu primera estructura.</p>
          </div>
        ) : assetTree.length === 0 ? (
          <div className="py-12 text-center text-muted-foreground">
            <ChevronDown className="mx-auto mb-3 h-8 w-8 opacity-50" />
            <p>Todos tus activos están archivados.</p>
            <Button variant="link" size="sm" onClick={() => setShowArchived(true)}>Ver archivados</Button>
          </div>
        ) : (
          <div className="space-y-1">
            {assetTree.map((node) => renderNode(node))}
          </div>
        )}

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                {dialogParentId ? `Agregar subactivo${selectedParent ? ` bajo "${selectedParent.name}"` : ''}` : 'Agregar activo raíz'}
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-4">
              <div>
                <Label htmlFor="asset-name">Nombre</Label>
                <Input
                  id="asset-name"
                  value={form.name}
                  onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))}
                  placeholder="Ingrese el nombre"
                />
              </div>
              <div>
                <Label>Tipo de nodo</Label>
                <Select value={form.nodeType} onValueChange={(value: AssetNodeType) => setForm((current) => ({ ...current, nodeType: value }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ASSET_NODE_TYPE_ORDER.map((type) => (
                      <SelectItem key={type} value={type}>{ASSET_NODE_TYPE_LABELS[type]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label>Estado</Label>
                <Select value={form.status} onValueChange={(value: AssetStatus) => setForm((current) => ({ ...current, status: value }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ASSET_EDITABLE_STATUSES.map((status) => (
                      <SelectItem key={status} value={status}>{ASSET_STATUS_LABELS[status]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label>Sucursal (opcional)</Label>
                <Select value={form.branchId || 'none'} onValueChange={(value) => setForm((current) => ({ ...current, branchId: value === 'none' ? '' : value }))}>
                  <SelectTrigger><SelectValue placeholder={branches.length === 0 ? 'Sin sucursales' : 'Selecciona sucursal'} /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">Sin sucursal</SelectItem>
                    {branches.map((branch) => (
                      <SelectItem key={branch.id} value={branch.id}>{branch.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              {categories.length > 0 && (
                <div>
                  <Label>Categoría (opcional)</Label>
                  <Select value={form.assetCategoryId || 'none'} onValueChange={(value) => setForm((current) => ({ ...current, assetCategoryId: value === 'none' ? '' : value }))}>
                    <SelectTrigger><SelectValue placeholder="Selecciona categoría" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">Sin categoría</SelectItem>
                      {categories.map((category) => (
                        <SelectItem key={category.id} value={category.id}>{category.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)} disabled={submitting}>Cancelar</Button>
              <Button onClick={() => void submitDialog()} disabled={submitting || !form.name.trim()}>
                {submitting ? 'Agregando…' : 'Agregar'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </CardContent>
    </Card>
  );
}
