import { useEffect, useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useToast } from '@/hooks/use-toast';
import {
  Settings2,
  QrCode,
  MapPin,
  FileText,
  User,
  Camera,
  CheckCircle,
  Archive,
  RotateCcw,
  Pencil,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { UseAssetsResult } from '@/hooks/useAssets';
import type { Asset, AssetCriticality, AssetNodeType, AssetStatus } from '@/types/asset';
import { ASSET_NODE_TYPE_ORDER, ASSET_NODE_TYPE_LABELS, ASSET_EDITABLE_STATUSES, ASSET_CRITICALITY_ORDER, ASSET_CRITICALITY_LABELS, getAssetStatusBadgeClass } from '@/lib/assetLabels';
import { AssetHistory } from './AssetHistory';

interface AssetDetailProps {
  state: UseAssetsResult;
}

const STATUS_LABELS: Record<AssetStatus, string> = {
  active: 'Habilitado',
  maintenance: 'Mantenimiento',
  inactive: 'Inactivo',
  archived: 'Archivado',
};

interface EditForm {
  name: string;
  nodeType: AssetNodeType;
  status: AssetStatus;
  code: string;
  description: string;
  criticality: AssetCriticality | '';
  manufacturer: string;
  model: string;
  serialNumber: string;
  barcode: string;
  purchaseDate: string;
  warrantyUntil: string;
  branchId: string;
  assetCategoryId: string;
  locationText: string;
}

const toEditForm = (asset: Asset): EditForm => ({
  name: asset.name,
  nodeType: asset.nodeType,
  status: asset.status === 'archived' ? 'active' : asset.status,
  code: asset.code ?? '',
  description: asset.description ?? '',
  criticality: asset.criticality ?? '',
  manufacturer: asset.manufacturer ?? '',
  model: asset.model ?? '',
  serialNumber: asset.serialNumber ?? '',
  barcode: asset.barcode ?? '',
  purchaseDate: asset.purchaseDate ?? '',
  warrantyUntil: asset.warrantyUntil ?? '',
  branchId: asset.branchId ?? '',
  assetCategoryId: asset.assetCategoryId ?? '',
  locationText: asset.locationText ?? '',
});

export function AssetDetail({ state }: AssetDetailProps) {
  const { selectedAsset: asset, canManageAssets, categories, branches, error, saving, archiveAsset, restoreAsset, updateAsset } = state;
  const { toast } = useToast();
  const [archiving, setArchiving] = useState(false);
  const [restoring, setRestoring] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState<EditForm | null>(null);

  // Switching the selected asset (or losing selection) must drop any
  // in-progress edit instead of showing a stale form over different data.
  useEffect(() => {
    setIsEditing(false);
    setForm(null);
  }, [asset?.id]);

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
    const ok = await archiveAsset(asset.id);
    setArchiving(false);
    if (ok) toast({ title: 'Activo archivado', description: `"${asset.name}" se archivó correctamente.` });
    else toast({ title: 'No se pudo archivar', description: 'Revisa los datos e inténtalo nuevamente.', variant: 'destructive' });
  };

  const handleRestore = async () => {
    setRestoring(true);
    const ok = await restoreAsset(asset.id);
    setRestoring(false);
    if (ok) toast({ title: 'Activo restaurado', description: `"${asset.name}" se restauró correctamente.` });
    else toast({ title: 'No se pudo restaurar', description: 'Revisa los datos e inténtalo nuevamente.', variant: 'destructive' });
  };

  const startEdit = () => {
    setForm(toEditForm(asset));
    setIsEditing(true);
  };

  const cancelEdit = () => {
    setForm(null);
    setIsEditing(false);
  };

  const setField = <K extends keyof EditForm>(key: K, value: EditForm[K]) => {
    setForm((current) => (current ? { ...current, [key]: value } : current));
  };

  const handleSave = async () => {
    if (!form) return;
    if (!form.name.trim()) {
      toast({ title: 'Falta el nombre', description: 'El nombre del activo es obligatorio.', variant: 'destructive' });
      return;
    }

    const ok = await updateAsset(asset.id, {
      name: form.name.trim(),
      nodeType: form.nodeType,
      status: form.status,
      code: form.code.trim() || null,
      description: form.description.trim() || null,
      criticality: form.criticality || null,
      manufacturer: form.manufacturer.trim() || null,
      model: form.model.trim() || null,
      serialNumber: form.serialNumber.trim() || null,
      barcode: form.barcode.trim() || null,
      purchaseDate: form.purchaseDate || null,
      warrantyUntil: form.warrantyUntil || null,
      branchId: form.branchId || null,
      assetCategoryId: form.assetCategoryId || null,
      locationText: form.locationText.trim() || null,
    });

    if (ok) {
      toast({ title: 'Activo actualizado', description: `Los cambios en "${form.name.trim()}" se guardaron correctamente.` });
      setForm(null);
      setIsEditing(false);
    } else {
      toast({ title: 'No se pudo guardar', description: 'Revisa los datos e inténtalo nuevamente.', variant: 'destructive' });
    }
  };

  if (isEditing && form) {
    const tabTriggerClass = 'data-[state=active]:bg-onefacility-blue data-[state=active]:text-white';

    return (
      <Card className="h-full overflow-auto">
        <CardHeader className="pb-4">
          <div className="flex items-start justify-between gap-3">
            <CardTitle className="text-xl">Editar activo</CardTitle>
            <Badge className={cn('ml-2 shrink-0', getAssetStatusBadgeClass(asset.status))} variant="outline">
              {STATUS_LABELS[asset.status]}
            </Badge>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {error && <p className="text-sm text-destructive">{error}</p>}

          <Tabs defaultValue="general" className="space-y-4">
            <TabsList className="inline-flex w-max gap-1 rounded-lg border border-onefacility-border bg-onefacility-surface p-1">
              <TabsTrigger value="general" className={tabTriggerClass}>General</TabsTrigger>
              <TabsTrigger value="technical" className={tabTriggerClass}>Técnica</TabsTrigger>
              <TabsTrigger value="location" className={tabTriggerClass}>Ubicación / clasificación</TabsTrigger>
            </TabsList>

            <TabsContent value="general" className="grid gap-4 md:grid-cols-2">
              <div className="md:col-span-2">
                <Label>Nombre</Label>
                <Input value={form.name} onChange={(event) => setField('name', event.target.value)} />
              </div>
              <div>
                <Label>Tipo de nodo</Label>
                <Select value={form.nodeType} onValueChange={(value: AssetNodeType) => setField('nodeType', value)}>
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
                <Select value={form.status} onValueChange={(value: AssetStatus) => setField('status', value)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ASSET_EDITABLE_STATUSES.map((status) => (
                      <SelectItem key={status} value={status}>{STATUS_LABELS[status]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label>Código</Label>
                <Input value={form.code} onChange={(event) => setField('code', event.target.value)} placeholder="Código interno" />
              </div>
              <div className="md:col-span-2">
                <Label>Descripción</Label>
                <Textarea value={form.description} onChange={(event) => setField('description', event.target.value)} />
              </div>
            </TabsContent>

            <TabsContent value="technical" className="grid gap-4 md:grid-cols-2">
              <div>
                <Label>Fabricante</Label>
                <Input value={form.manufacturer} onChange={(event) => setField('manufacturer', event.target.value)} />
              </div>
              <div>
                <Label>Modelo</Label>
                <Input value={form.model} onChange={(event) => setField('model', event.target.value)} />
              </div>
              <div>
                <Label>Número de serie</Label>
                <Input value={form.serialNumber} onChange={(event) => setField('serialNumber', event.target.value)} />
              </div>
              <div>
                <Label>Código de barras</Label>
                <Input value={form.barcode} onChange={(event) => setField('barcode', event.target.value)} />
              </div>
              <div>
                <Label>Criticidad</Label>
                <Select value={form.criticality || 'none'} onValueChange={(value) => setField('criticality', value === 'none' ? '' : value as AssetCriticality)}>
                  <SelectTrigger><SelectValue placeholder="Sin especificar" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">Sin especificar</SelectItem>
                    {ASSET_CRITICALITY_ORDER.map((criticality) => (
                      <SelectItem key={criticality} value={criticality}>{ASSET_CRITICALITY_LABELS[criticality]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label>Fecha de compra</Label>
                <Input type="date" value={form.purchaseDate} onChange={(event) => setField('purchaseDate', event.target.value)} />
              </div>
              <div>
                <Label>Garantía hasta</Label>
                <Input type="date" value={form.warrantyUntil} onChange={(event) => setField('warrantyUntil', event.target.value)} />
              </div>
            </TabsContent>

            <TabsContent value="location" className="grid gap-4 md:grid-cols-2">
              <div>
                <Label>Sucursal</Label>
                <Select value={form.branchId || 'none'} onValueChange={(value) => setField('branchId', value === 'none' ? '' : value)}>
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
                  <Label>Categoría</Label>
                  <Select value={form.assetCategoryId || 'none'} onValueChange={(value) => setField('assetCategoryId', value === 'none' ? '' : value)}>
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
              <div className="md:col-span-2">
                <Label>Ubicación (texto libre)</Label>
                <Input value={form.locationText} onChange={(event) => setField('locationText', event.target.value)} placeholder="Ej: Planta 2, patio de maniobras" />
              </div>
            </TabsContent>
          </Tabs>

          <div className="flex justify-end gap-2 border-t border-onefacility-border pt-4">
            <Button variant="outline" onClick={cancelEdit} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSave()} disabled={saving || !form.name.trim()}>
              {saving ? 'Guardando…' : 'Guardar cambios'}
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

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
          <Badge className={cn('ml-2 shrink-0', getAssetStatusBadgeClass(asset.status))} variant="outline">
            <CheckCircle className="h-3 w-3 mr-1" />
            {STATUS_LABELS[asset.status]}
          </Badge>
        </div>
      </CardHeader>

      <CardContent className="space-y-6">
        <Tabs defaultValue="summary" className="space-y-4">
          <TabsList className="inline-flex w-max gap-1 rounded-lg border border-onefacility-border bg-onefacility-surface p-1">
            <TabsTrigger value="summary" className="data-[state=active]:bg-onefacility-blue data-[state=active]:text-white">Resumen</TabsTrigger>
            <TabsTrigger value="history" className="data-[state=active]:bg-onefacility-blue data-[state=active]:text-white">Historial</TabsTrigger>
          </TabsList>

          <TabsContent value="summary" className="space-y-6">
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
              <p className="text-sm bg-muted/30 p-2 rounded mt-1">{asset.criticality ? ASSET_CRITICALITY_LABELS[asset.criticality] : 'No especificado'}</p>
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
          </TabsContent>

          <TabsContent value="history">
            <AssetHistory assetId={asset.id} />
          </TabsContent>
        </Tabs>

        {/* Action Buttons */}
        <div className="flex flex-wrap gap-2 pt-4">
          <Button variant="outline" size="sm" disabled>
            <FileText className="h-4 w-4 mr-2" />
            Generar Reporte
          </Button>
          <Button variant="outline" size="sm" disabled>
            <User className="h-4 w-4 mr-2" />
            Asignar Técnico
          </Button>
          {canManageAssets && asset.status !== 'archived' && (
            <Button variant="outline" size="sm" onClick={startEdit}>
              <Pencil className="h-4 w-4 mr-2" />
              Editar
            </Button>
          )}
          {canManageAssets && asset.status !== 'archived' && (
            <Button variant="outline" size="sm" onClick={() => void handleArchive()} disabled={archiving}>
              <Archive className="h-4 w-4 mr-2" />
              {archiving ? 'Archivando…' : 'Archivar'}
            </Button>
          )}
          {canManageAssets && asset.status === 'archived' && (
            <Button variant="outline" size="sm" onClick={() => void handleRestore()} disabled={restoring}>
              <RotateCcw className="h-4 w-4 mr-2" />
              {restoring ? 'Restaurando…' : 'Restaurar'}
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
