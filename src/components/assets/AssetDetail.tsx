import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { 
  Settings2, 
  QrCode, 
  MapPin, 
  Calendar, 
  Truck,
  User,
  FileText,
  Eye,
  Camera,
  CheckCircle
} from 'lucide-react';
import { cn } from '@/lib/utils';

interface AssetNode {
  id: string;
  name: string;
  type: 'society' | 'company' | 'asset_class' | 'asset' | 'sub_asset';
  status?: 'active' | 'maintenance' | 'inactive';
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

interface AssetDetailProps {
  asset?: AssetNode;
}

const mockAssetData = {
  id: '0x0409E05ABB6C81',
  name: 'BUS MERCEDES BENZ - 01',
  manufacturer: 'MERCEDES BENZ',
  model: 'M2 106',
  serialNumber: '0409E05ABB6C81',
  year: '2010',
  location: 'EMPRESAS/ EMPRESA SECTOR TRANSPORTE/LOGÍSTICA/ FLOTA DE AUTOBUSES/',
  type: 'CAMION 10 TON',
  classification1: 'BCI LEASING',
  classification2: '3',
  provider: 'MORGAN EMPRESAS',
  purchaseDate: '2017-07-02',
  dailyUsageHours: '24:00',
  status: 'active',
  maintenancePlan: 'PLAN DE MANTENIMIENTO CAMIÓN FREIGHTLINER M102',
  isPublic: false,
  others: {
    code: '0409E05ABB6C81',
    priority: '3',
    barCode: '0409E05ABB6C81'
  }
};

export function AssetDetail({ asset }: AssetDetailProps) {
  if (!asset || (asset.type !== 'asset' && asset.type !== 'sub_asset')) {
    return (
      <Card className="h-full">
        <CardContent className="flex items-center justify-center h-full">
          <div className="text-center text-muted-foreground">
            <Settings2 className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>Selecciona un activo para ver sus detalles</p>
          </div>
        </CardContent>
      </Card>
    );
  }

  const getStatusColor = (status: string) => {
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

  return (
    <Card className="h-full overflow-auto">
      <CardHeader className="pb-4">
          <div className="flex items-start justify-between">
          <div className="flex items-center space-x-3">
            <Truck className="h-6 w-6 text-primary" />
            <div>
              <CardTitle className="text-xl">{asset.name}</CardTitle>
              <p className="text-sm text-muted-foreground">{asset.id}</p>
            </div>
          </div>
          <Badge 
            className={cn("ml-2", getStatusColor(asset.status || 'active'))}
            variant="outline"
          >
            <CheckCircle className="h-3 w-3 mr-1" />
            {asset.status === 'active' ? 'Habilitado' : asset.status === 'maintenance' ? 'Mantenimiento' : 'Inactivo'}
          </Badge>
        </div>
      </CardHeader>

      <CardContent className="space-y-6">
        {/* Asset Image and QR Code */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="relative">
            <img 
              src={asset.imageUrl || "/src/assets/bus-asset.jpg"} 
              alt={`${asset.name} Asset`}
              className="w-full h-32 object-cover rounded-lg bg-muted border"
            />
            <Button
              size="sm"
              variant="secondary"
              className="absolute top-2 right-2"
            >
              <Camera className="h-4 w-4" />
            </Button>
          </div>
          <div className="flex flex-col items-center justify-center p-4 border rounded-lg">
            <QrCode className="h-16 w-16 text-muted-foreground mb-2" />
            <p className="text-xs text-muted-foreground text-center">Código QR</p>
          </div>
        </div>

        {/* Location */}
        <div className="space-y-2">
          <div className="flex items-center text-sm text-muted-foreground">
            <MapPin className="h-4 w-4 mr-2" />
            Ubicado en &amp; es Parte de
          </div>
          <p className="text-sm bg-muted/30 p-2 rounded border">
            EMPRESAS/ EMPRESA SECTOR TRANSPORTE/LOGÍSTICA/ FLOTA DE AUTOBUSES/
          </p>
        </div>

        {/* Basic Information */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium text-muted-foreground">Fabricante</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.manufacturer || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Número de Serie</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.serialNumber || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Tipo</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.assetType || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Proveedor</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.provider || 'No especificado'}</p>
            </div>
          </div>

          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium text-muted-foreground">Modelo</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.model || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Año</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.year || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Clasificación 1</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.classification1 || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Fecha de Compra</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.purchaseDate || 'No especificado'}</p>
            </div>
          </div>
        </div>

        <Separator />

        {/* Additional Information */}
        <div className="space-y-4">
          <h3 className="font-medium text-foreground">Información Adicional</h3>
          
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="text-sm font-medium text-muted-foreground">Código de Barras</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.barCode || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Clasificación 2</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.classification2 || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Prioridad</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.priority || 'No especificado'}</p>
            </div>
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">Horas de uso promedio diario</label>
            <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.dailyUsageHours || 'No especificado'}</p>
          </div>
        </div>

        <Separator />

        {/* Maintenance Plan */}
        <div className="space-y-4">
          <h3 className="font-medium text-foreground flex items-center">
            <Settings2 className="h-4 w-4 mr-2" />
            Plan de Mantenimiento
          </h3>
          <div className="bg-info/10 border border-info/20 rounded-lg p-4">
            <p className="text-sm text-info-foreground">{asset.maintenancePlan || 'No especificado'}</p>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex flex-wrap gap-2 pt-4">
          <Button variant="outline" size="sm">
            <FileText className="h-4 w-4 mr-2" />
            Generar Reporte
          </Button>
          <Button variant="outline" size="sm">
            <Calendar className="h-4 w-4 mr-2" />
            Historial
          </Button>
          <Button variant="outline" size="sm">
            <User className="h-4 w-4 mr-2" />
            Asignar Técnico
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}