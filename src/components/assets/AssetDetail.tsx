import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import {
  Settings2,
  QrCode,
  MapPin,
  Calendar,
  FileText,
  User,
  Camera,
  CheckCircle,
  Archive,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { Asset, AssetStatus } from '@/types/asset';

interface AssetDetailProps {
  asset: Asset | null;
  canEdit: boolean;
  onArchive: (assetId: string) => Promise<boolean>;
}

const STATUS_LABELS: Record<AssetStatus, string> = {
  active: 'Habilitado',
  maintenance: 'Mantenimiento',
  inactive: 'Inactivo',
  archived: 'Archivado',
};

const getStatusColor = (status: AssetStatus) => {
  switch (status) {
    case 'active':
      return 'bg-success/10 text-success border-success/20';
    case 'maintenance':
      return 'bg-warning/10 text-warning border-warning/20';
    case 'archived':
      return 'bg-muted text-muted-foreground border-border';
    default:
      return 'bg-muted text-muted-foreground border-border';
  }
};

export function AssetDetail({ asset, canEdit, onArchive }: AssetDetailProps) {
  const [archiving, setArchiving] = useState(false);

  if (!asset) {
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

  const technicalData = asset.technicalData as Record<string, unknown>;
  const technicalText = (key: string) => {
    const value = technicalData?.[key];
    return typeof value === 'string' && value.trim() ? value : null;
  };

  const handleArchive = async () => {
    setArchiving(true);
    await onArchive(asset.id);
    setArchiving(false);
  };

  return (
    <Card className="h-full overflow-auto">
      <CardHeader className="pb-4">
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center space-x-3">
            <Settings2 className="h-6 w-6 text-primary" />
            <div>
              <CardTitle className="text-xl">{asset.name}</CardTitle>
              {asset.code && <p className="text-sm text-muted-foreground">{asset.code}</p>}
            </div>
          </div>
          <Badge className={cn('ml-2 shrink-0', getStatusColor(asset.status))} variant="outline">
            <CheckCircle className="h-3 w-3 mr-1" />
            {STATUS_LABELS[asset.status]}
          </Badge>
        </div>
      </CardHeader>

      <CardContent className="space-y-6">
        {/* Asset Image and QR Code */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="relative">
            <img
              src={asset.imageUrl || '/placeholder.svg'}
              alt={`${asset.name}`}
              className="w-full h-32 object-cover rounded-lg bg-muted border"
            />
            <Button size="sm" variant="secondary" className="absolute top-2 right-2" disabled>
              <Camera className="h-4 w-4" />
            </Button>
          </div>
          <div className="flex flex-col items-center justify-center p-4 border rounded-lg">
            <QrCode className="h-16 w-16 text-muted-foreground mb-2" />
            <p className="text-xs text-muted-foreground text-center">
              {asset.qrCode ? asset.qrCode : 'Código QR pendiente'}
            </p>
          </div>
        </div>

        {/* Location */}
        <div className="space-y-2">
          <div className="flex items-center text-sm text-muted-foreground">
            <MapPin className="h-4 w-4 mr-2" />
            Ubicación
          </div>
          <p className="text-sm bg-muted/30 p-2 rounded border">
            {asset.locationText || 'No especificado'}
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
              <label className="text-sm font-medium text-muted-foreground">Criticidad</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.criticality || 'No especificado'}</p>
            </div>
          </div>

          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium text-muted-foreground">Modelo</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.model || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Fecha de Compra</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.purchaseDate || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Garantía hasta</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.warrantyUntil || 'No especificado'}</p>
            </div>
          </div>
        </div>

        <Separator />

        {/* Additional Information */}
        <div className="space-y-4">
          <h3 className="font-medium text-foreground">Información Adicional</h3>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="text-sm font-medium text-muted-foreground">Código de Barras</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.barcode || 'No especificado'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">Descripción</label>
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.description || 'No especificado'}</p>
            </div>
          </div>

          {(technicalText('plan_mantenimiento') || technicalText('maintenance_plan')) && (
            <div>
              <label className="text-sm font-medium text-muted-foreground">Plan de Mantenimiento</label>
              <div className="bg-info/10 border border-info/20 rounded-lg p-4 mt-1">
                <p className="text-sm text-info-foreground">
                  {technicalText('plan_mantenimiento') || technicalText('maintenance_plan')}
                </p>
              </div>
            </div>
          )}
        </div>

        {/* Action Buttons */}
        <div className="flex flex-wrap gap-2 pt-4">
          <Button variant="outline" size="sm" disabled>
            <FileText className="h-4 w-4 mr-2" />
            Generar Reporte
          </Button>
          <Button variant="outline" size="sm" disabled>
            <Calendar className="h-4 w-4 mr-2" />
            Historial
          </Button>
          <Button variant="outline" size="sm" disabled>
            <User className="h-4 w-4 mr-2" />
            Asignar Técnico
          </Button>
          {canEdit && asset.status !== 'archived' && (
            <Button variant="outline" size="sm" onClick={() => void handleArchive()} disabled={archiving}>
              <Archive className="h-4 w-4 mr-2" />
              {archiving ? 'Archivando…' : 'Archivar'}
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
