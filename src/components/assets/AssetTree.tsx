import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { 
  ChevronDown, 
  ChevronRight, 
  Building, 
  Building2, 
  Truck, 
  Settings2,
  Plus,
  Minus
} from 'lucide-react';
import { cn } from '@/lib/utils';

interface AssetNode {
  id: string;
  name: string;
  type: 'society' | 'company' | 'asset_class' | 'asset' | 'sub_asset';
  children?: AssetNode[];
  status?: 'active' | 'maintenance' | 'inactive';
  count?: number;
  // Technical data for assets
  manufacturer?: string;
  model?: string;
  serialNumber?: string;
  year?: string;
  assetType?: string;
  classification1?: string;
  classification2?: string;
  provider?: string;
  purchaseDate?: string;
  dailyUsageHours?: string;
  maintenancePlan?: string;
  barCode?: string;
  priority?: string;
  imageUrl?: string;
}

const mockAssets: AssetNode[] = [
  {
    id: '1',
    name: 'EMPRESAS',
    type: 'society',
    children: [
      {
        id: '1-1',
        name: 'EMPRESA SECTOR RETAIL',
        type: 'company',
        status: 'active',
        children: []
      },
      {
        id: '1-2',
        name: 'EMPRESA SECTOR AGUA',
        type: 'company',
        status: 'active',
        children: []
      },
      {
        id: '1-3',
        name: 'EMPRESA SECTOR ADMINISTRACIÓN DE EDIFICIOS/OFICINAS',
        type: 'company',
        status: 'active',
        children: []
      },
      {
        id: '1-4',
        name: 'EMPRESA SECTOR TRANSPORTE/LOGÍSTICA',
        type: 'company',
        status: 'active',
        children: [
          {
            id: '1-4-1',
            name: 'FLOTA DE AUTOBUSES',
            type: 'asset_class',
            status: 'active',
            children: [
              {
                id: '1-4-1-1',
                name: 'BUS MERCEDES BENZ - 01',
                type: 'asset',
                status: 'active',
                manufacturer: 'MERCEDES BENZ',
                model: 'M2 106',
                serialNumber: '0409E05ABB6C81',
                year: '2010',
                assetType: 'CAMION 10 TON',
                classification1: 'BCI LEASING',
                classification2: '3',
                provider: 'MORGAN EMPRESAS',
                purchaseDate: '2017-07-02',
                dailyUsageHours: '24:00',
                maintenancePlan: 'PLAN DE MANTENIMIENTO CAMIÓN FREIGHTLINER M102',
                barCode: '0409E05ABB6C81',
                priority: '3',
                imageUrl: '/src/assets/bus-asset.jpg'
              }
            ]
          },
          {
            id: '1-4-2',
            name: 'FLOTA DE ACTIVOS',
            type: 'asset_class',
            status: 'active',
            children: []
          },
          {
            id: '1-4-3',
            name: 'CENTROS DE ALMACENES',
            type: 'asset_class',
            status: 'active',
            children: []
          }
        ]
      }
    ]
  }
];

export type { AssetNode };

interface AssetTreeProps {
  onAssetSelect?: (asset: AssetNode) => void;
}

export function AssetTree({ onAssetSelect }: AssetTreeProps) {
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set(['1', '1-4']));
  const [selectedAsset, setSelectedAsset] = useState<string | null>(null);
  const [assets, setAssets] = useState<AssetNode[]>(mockAssets);
  const [newItemDialog, setNewItemDialog] = useState<{ open: boolean; parentId?: string; parentType?: AssetNode['type'] }>({ open: false });
  const [newItemForm, setNewItemForm] = useState<{ name: string; status: 'active' | 'maintenance' | 'inactive' }>({ name: '', status: 'active' });

  const toggleNode = (nodeId: string) => {
    const newExpanded = new Set(expandedNodes);
    if (newExpanded.has(nodeId)) {
      newExpanded.delete(nodeId);
    } else {
      newExpanded.add(nodeId);
    }
    setExpandedNodes(newExpanded);
  };

  const getIcon = (type: AssetNode['type']) => {
    switch (type) {
      case 'society':
        return Building2;
      case 'company':
        return Building;
      case 'asset_class':
        return Settings2;
      case 'asset':
        return Truck;
      case 'sub_asset':
        return Settings2;
      default:
        return Building2;
    }
  };

  const getStatusColor = (status?: string) => {
    switch (status) {
      case 'active':
        return 'bg-success/10 text-success border-success/20';
      case 'maintenance':
        return 'bg-warning/10 text-warning border-warning/20';
      case 'inactive':
        return 'bg-muted text-muted-foreground border-border';
      default:
        return 'bg-muted text-muted-foreground border-border';
    }
  };

  const handleSelectAsset = (asset: AssetNode) => {
    setSelectedAsset(asset.id);
    onAssetSelect?.(asset);
  };

  const getNextType = (parentType: AssetNode['type']): AssetNode['type'] | null => {
    switch (parentType) {
      case 'society': return 'company';
      case 'company': return 'asset_class';
      case 'asset_class': return 'asset';
      case 'asset': return 'sub_asset';
      default: return null;
    }
  };

  const generateId = () => {
    return Math.random().toString(36).substr(2, 9);
  };

  const addNewItem = (parentId?: string) => {
    if (!newItemForm.name.trim()) return;

    const newItem: AssetNode = {
      id: generateId(),
      name: newItemForm.name,
      type: parentId ? getNextType(findNodeById(assets, parentId)?.type || 'society') || 'society' : 'society',
      status: newItemForm.status,
      children: []
    };

    if (!parentId) {
      // Add as root level (society)
      setAssets([...assets, newItem]);
    } else {
      // Add as child
      const updateTree = (nodes: AssetNode[]): AssetNode[] => {
        return nodes.map(node => {
          if (node.id === parentId) {
            return {
              ...node,
              children: [...(node.children || []), newItem]
            };
          }
          if (node.children) {
            return {
              ...node,
              children: updateTree(node.children)
            };
          }
          return node;
        });
      };
      setAssets(updateTree(assets));
      setExpandedNodes(new Set([...expandedNodes, parentId]));
    }

    setNewItemForm({ name: '', status: 'active' });
    setNewItemDialog({ open: false });
  };

  const findNodeById = (nodes: AssetNode[], id: string): AssetNode | null => {
    for (const node of nodes) {
      if (node.id === id) return node;
      if (node.children) {
        const found = findNodeById(node.children, id);
        if (found) return found;
      }
    }
    return null;
  };

  const getTypeName = (type: AssetNode['type']) => {
    switch (type) {
      case 'society': return 'Sociedad';
      case 'company': return 'Compañía';
      case 'asset_class': return 'Clase de Activo';
      case 'asset': return 'Activo';
      case 'sub_asset': return 'Subactivo';
      default: return 'Elemento';
    }
  };

  const canAddChild = (type: AssetNode['type']) => {
    return type !== 'sub_asset';
  };

  const renderNode = (node: AssetNode, level: number = 0) => {
    const hasChildren = node.children && node.children.length > 0;
    const isExpanded = expandedNodes.has(node.id);
    const isSelected = selectedAsset === node.id;
    const Icon = getIcon(node.type);

    return (
      <div key={node.id} className="select-none">
        <div
          className={cn(
            "group flex items-center py-2 px-2 rounded-md cursor-pointer hover:bg-muted/50 transition-colors",
            isSelected && "bg-primary/10 border-l-2 border-l-primary",
            level === 0 && "font-semibold"
          )}
          style={{ paddingLeft: `${level * 20 + 8}px` }}
          onClick={() => handleSelectAsset(node)}
        >
          {hasChildren && (
            <Button
              variant="ghost"
              size="sm"
              className="h-6 w-6 p-0 mr-1"
              onClick={(e) => {
                e.stopPropagation();
                toggleNode(node.id);
              }}
            >
              {isExpanded ? (
                <Minus className="h-3 w-3" />
              ) : (
                <Plus className="h-3 w-3" />
              )}
            </Button>
          )}
          
          <Icon className="h-4 w-4 mr-2 text-muted-foreground" />
          
          <span className="flex-1 text-sm">{node.name}</span>
          
          {node.status && (
            <Badge 
              variant="outline" 
              className={cn("ml-2 text-xs", getStatusColor(node.status))}
            >
              {node.status}
            </Badge>
          )}

          {canAddChild(node.type) && (
            <Dialog 
              open={newItemDialog.open && newItemDialog.parentId === node.id} 
              onOpenChange={(open) => setNewItemDialog({ open, parentId: open ? node.id : undefined, parentType: node.type })}
            >
              <DialogTrigger asChild>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-6 w-6 p-0 ml-1 opacity-0 group-hover:opacity-100 transition-opacity"
                  onClick={(e) => {
                    e.stopPropagation();
                    setNewItemDialog({ open: true, parentId: node.id, parentType: node.type });
                  }}
                >
                  <Plus className="h-3 w-3" />
                </Button>
              </DialogTrigger>
            </Dialog>
          )}
        </div>

        {hasChildren && isExpanded && (
          <div className="ml-2">
            {node.children?.map((child) => renderNode(child, level + 1))}
          </div>
        )}
      </div>
    );
  };

  return (
    <Card className="h-full">
      <CardHeader>
        <CardTitle className="flex items-center justify-between text-lg">
          <div className="flex items-center">
            <Building2 className="h-5 w-5 mr-2" />
            Estructura de Activos
          </div>
          <Dialog 
            open={newItemDialog.open && !newItemDialog.parentId} 
            onOpenChange={(open) => setNewItemDialog({ open })}
          >
            <DialogTrigger asChild>
              <Button 
                variant="default" 
                size="sm"
                onClick={() => setNewItemDialog({ open: true })}
              >
                <Plus className="h-4 w-4 mr-1" />
                Agregar Sociedad
              </Button>
            </DialogTrigger>
          </Dialog>
        </CardTitle>
      </CardHeader>
      <CardContent className="p-4">
        <div className="space-y-1">
          {assets.map((node) => renderNode(node))}
        </div>

        {/* Dialog for adding new items */}
        <Dialog 
          open={newItemDialog.open} 
          onOpenChange={(open) => setNewItemDialog({ open: false })}
        >
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                Agregar {newItemDialog.parentId 
                  ? getTypeName(getNextType(findNodeById(assets, newItemDialog.parentId)?.type || 'society') || 'society')
                  : 'Sociedad'
                }
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-4">
              <div>
                <Label htmlFor="name">Nombre</Label>
                <Input
                  id="name"
                  value={newItemForm.name}
                  onChange={(e) => setNewItemForm({ ...newItemForm, name: e.target.value })}
                  placeholder="Ingrese el nombre"
                />
              </div>
              <div>
                <Label htmlFor="status">Estado</Label>
                <Select 
                  value={newItemForm.status} 
                  onValueChange={(value: 'active' | 'maintenance' | 'inactive') => 
                    setNewItemForm({ ...newItemForm, status: value })
                  }
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="active">Activo</SelectItem>
                    <SelectItem value="maintenance">Mantenimiento</SelectItem>
                    <SelectItem value="inactive">Inactivo</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="flex justify-end space-x-2">
                <Button 
                  variant="outline" 
                  onClick={() => setNewItemDialog({ open: false })}
                >
                  Cancelar
                </Button>
                <Button 
                  onClick={() => addNewItem(newItemDialog.parentId)}
                  disabled={!newItemForm.name.trim()}
                >
                  Agregar
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </CardContent>
    </Card>
  );
}