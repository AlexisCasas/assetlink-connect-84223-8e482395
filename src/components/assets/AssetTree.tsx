import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
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
                status: 'active'
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

interface AssetTreeProps {
  onSelectAsset?: (asset: AssetNode) => void;
}

export function AssetTree({ onSelectAsset }: AssetTreeProps) {
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set(['1', '1-4']));
  const [selectedAsset, setSelectedAsset] = useState<string | null>(null);

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
    onSelectAsset?.(asset);
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
            "flex items-center py-2 px-2 rounded-md cursor-pointer hover:bg-muted/50 transition-colors",
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
        <CardTitle className="flex items-center text-lg">
          <Building2 className="h-5 w-5 mr-2" />
          Estructura de Activos
        </CardTitle>
      </CardHeader>
      <CardContent className="p-4">
        <div className="space-y-1">
          {mockAssets.map((node) => renderNode(node))}
        </div>
      </CardContent>
    </Card>
  );
}