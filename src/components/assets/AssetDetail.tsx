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
import { useAuth } from '@/contexts/AuthContext';
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
  Gauge,
  TrafficCone,
  AlertTriangle,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { UseAssetsResult } from '@/hooks/useAssets';
import type { UseAssetTrafficLightResult } from '@/hooks/useAssetTrafficLight';
import type { Asset, AssetCriticality, AssetNodeType, AssetStatus } from '@/types/asset';
import { ASSET_NODE_TYPE_ORDER, ASSET_NODE_TYPE_LABELS, ASSET_EDITABLE_STATUSES, ASSET_CRITICALITY_ORDER, ASSET_CRITICALITY_LABELS, getAssetStatusBadgeClass } from '@/lib/assetLabels';
import { TRAFFIC_LIGHT_BADGE_CLASS, TRAFFIC_LIGHT_DOT_CLASS, TRAFFIC_LIGHT_LABELS, TRAFFIC_LIGHT_SOURCE_LABELS } from '@/lib/trafficLightLabels';
import { AssetHistory } from './AssetHistory';
import { useCriticalityMatrix } from '@/hooks/useCriticalityMatrix';
import { CriticalityAssessmentDialog } from '@/components/criticality/CriticalityAssessmentDialog';
import { CriticalityAssessmentHistory } from '@/components/criticality/CriticalityAssessmentHistory';
import type { CriticalityAssessment } from '@/types/criticalityMatrix';
import { useMaintenanceNotices } from '@/hooks/useMaintenanceNotices';
import { MaintenanceNoticeDialog } from '@/components/backlog/MaintenanceNoticeDialog';

interface AssetDetailProps {
  state: UseAssetsResult;
  trafficLight: UseAssetTrafficLightResult;
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

export function AssetDetail({ state, trafficLight }: AssetDetailProps) {
  const { selectedAsset: asset, assets: allAssets, canManageAssets, categories, branches, error, saving, archiveAsset, restoreAsset, updateAsset, refreshAssets } = state;
  const { toast } = useToast();
  const { currentMembership } = useAuth();
  const [noticeDialogOpen, setNoticeDialogOpen] = useState(false);
  // Reportar una avería es más amplio que administrar activos: un técnico o
  // un solicitante reportan, aunque no puedan editar la ficha. El backend
  // vuelve a validarlo en create_maintenance_notice.
  const canReportNotice = !!currentMembership?.isActive
    && ['owner', 'admin', 'manager', 'technician', 'requester'].includes(currentMembership.role);
  // El hook solo consulta cuando el diálogo está abierto: la ficha del
  // activo no necesita cargar todo el backlog para mostrar un botón.
  const { createNotice } = useMaintenanceNotices(noticeDialogOpen ? asset?.organizationId : null);
  const [archiving, setArchiving] = useState(false);
  const [restoring, setRestoring] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState<EditForm | null>(null);
  const [assessmentDialogOpen, setAssessmentDialogOpen] = useState(false);
  const [latestAssessment, setLatestAssessment] = useState<CriticalityAssessment | null>(null);
  const [historyRefreshToken, setHistoryRefreshToken] = useState(0);

  // Matrix is scoped to the asset's own organization — hook must be called
  // unconditionally (asset can still be null here), so organizationId is
  // undefined until an asset is selected.
  const { activeParameters, calculateCriticality, loadAssessments, saving: assessmentSaving } = useCriticalityMatrix(asset?.organizationId);

  // Switching the selected asset (or losing selection) must drop any
  // in-progress edit instead of showing a stale form over different data.
  useEffect(() => {
    setIsEditing(false);
    setForm(null);
  }, [asset?.id]);

  // Latest evaluation drives the "score" line next to Criticidad — refetched
  // whenever the selected asset changes or a new evaluation is saved.
  useEffect(() => {
    if (!asset) {
      setLatestAssessment(null);
      return;
    }
    let cancelled = false;
    loadAssessments(asset.id)
      .then((assessments) => { if (!cancelled) setLatestAssessment(assessments[0] ?? null); })
      .catch(() => { if (!cancelled) setLatestAssessment(null); });
    return () => { cancelled = true; };
  }, [asset?.id, historyRefreshToken, loadAssessments]);

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

  const tl = trafficLight.getAsset(asset.id);
  const hasChildren = allAssets.some((a) => a.parentAssetId === asset.id);

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

        {/* Semáforo operativo — calculado en vivo desde OT/inspecciones/estado
            reales, nunca un color manual. Ver docs/ASSET_TRAFFIC_LIGHT.md. */}
        <div className="space-y-3">
          <div className="flex items-center gap-2 text-sm font-medium text-foreground">
            <TrafficCone className="h-4 w-4 text-muted-foreground" />
            Semáforo operativo
          </div>
          <p className="text-xs text-muted-foreground">
            Estado calculado en este momento a partir de OT, inspecciones y estado del activo — no es un historial ni queda registrado como evento.
          </p>

          {!tl ? (
            <p className="text-sm text-muted-foreground">Cargando semáforo…</p>
          ) : (
            <div className="space-y-3">
              <div className="flex flex-wrap items-center gap-4">
                <div className="flex items-center gap-2">
                  <span className="text-xs text-muted-foreground">Directo</span>
                  <Badge variant="outline" className={cn('gap-1.5', TRAFFIC_LIGHT_BADGE_CLASS[tl.directColor])}>
                    <span className={cn('h-2 w-2 rounded-full', TRAFFIC_LIGHT_DOT_CLASS[tl.directColor])} />
                    {TRAFFIC_LIGHT_LABELS[tl.directColor]}
                  </Badge>
                </div>
                {hasChildren && (
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-muted-foreground">Heredado (rollup)</span>
                    <Badge variant="outline" className={cn('gap-1.5', TRAFFIC_LIGHT_BADGE_CLASS[tl.rollupColor])}>
                      <span className={cn('h-2 w-2 rounded-full', TRAFFIC_LIGHT_DOT_CLASS[tl.rollupColor])} />
                      {TRAFFIC_LIGHT_LABELS[tl.rollupColor]}
                    </Badge>
                  </div>
                )}
                {tl.criticality && (
                  <span className="text-xs text-muted-foreground">
                    Criticidad: {ASSET_CRITICALITY_LABELS[tl.criticality as AssetCriticality] ?? tl.criticality} (contexto, no determina el color)
                  </span>
                )}
              </div>

              {tl.directColor === 'green' && (!hasChildren || tl.rollupColor === 'green') ? (
                <p className="text-sm text-muted-foreground">Todo en regla — sin OT vencidas, inspecciones vencidas ni no conformidades.</p>
              ) : (
                <>
                  {tl.directReasons.length > 0 && (
                    <div className="space-y-1.5">
                      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Razones directas</p>
                      {tl.directReasons.map((reason) => (
                        <div key={reason.sourceType + reason.sourceId} className="rounded-md border p-2 text-sm">
                          <div className="flex items-center justify-between gap-2">
                            <span className="font-medium">{TRAFFIC_LIGHT_SOURCE_LABELS[reason.sourceType]}</span>
                            <Badge variant="outline" className={TRAFFIC_LIGHT_BADGE_CLASS[reason.severity]}>{TRAFFIC_LIGHT_LABELS[reason.severity]}</Badge>
                          </div>
                          <p className="mt-0.5 text-xs text-muted-foreground">{reason.description}</p>
                        </div>
                      ))}
                    </div>
                  )}

                  {hasChildren && tl.causingAssetIds.length > 0 && (
                    <div className="space-y-1.5">
                      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Activos causantes</p>
                      {tl.causingAssetIds.map((causingId) => {
                        const causing = trafficLight.getAsset(causingId);
                        return (
                          <button
                            key={causingId}
                            type="button"
                            className="flex w-full items-center gap-2 rounded-md border p-2 text-left text-sm hover:bg-muted/50"
                            onClick={() => state.selectAsset(causingId)}
                          >
                            {causing && <span className={cn('h-2 w-2 shrink-0 rounded-full', TRAFFIC_LIGHT_DOT_CLASS[causing.rollupColor])} />}
                            <span className="truncate">{causing?.assetName ?? causingId}</span>
                          </button>
                        );
                      })}
                    </div>
                  )}

                  {hasChildren && tl.rollupReasons.length > 0 && (
                    <div className="space-y-1.5">
                      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Razones heredadas (incluye descendientes)</p>
                      {tl.rollupReasons.map((reason, index) => (
                        <div key={`${reason.sourceType}-${reason.sourceId}-${index}`} className="rounded-md border p-2 text-sm">
                          <div className="flex items-center justify-between gap-2">
                            <span className="font-medium">
                              {reason.assetName ? `${reason.assetName} — ` : ''}{TRAFFIC_LIGHT_SOURCE_LABELS[reason.sourceType]}
                            </span>
                            <Badge variant="outline" className={TRAFFIC_LIGHT_BADGE_CLASS[reason.severity]}>{TRAFFIC_LIGHT_LABELS[reason.severity]}</Badge>
                          </div>
                          <p className="mt-0.5 text-xs text-muted-foreground">{reason.description}</p>
                        </div>
                      ))}
                    </div>
                  )}
                </>
              )}
            </div>
          )}
        </div>

        <Separator />

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
              <label className="text-sm font-medium text-muted-foreground">Criticidad (efectiva)</label>
              <div className="mt-1 flex flex-wrap items-center gap-2 rounded bg-muted/30 p-2 text-sm">
                <span>{asset.criticality ? ASSET_CRITICALITY_LABELS[asset.criticality] : 'No especificado'}</span>
                {latestAssessment && latestAssessment.calculatedCriticality === asset.criticality && (
                  <Badge variant="secondary">Score: {latestAssessment.score} (última evaluación)</Badge>
                )}
              </div>
              <p className="mt-1 text-xs text-muted-foreground">
                {latestAssessment && latestAssessment.calculatedCriticality === asset.criticality
                  ? 'Calculada con la matriz de criticidad configurada.'
                  : 'Valor manual — no hay una evaluación calculada vigente para este activo.'}
              </p>
              {canManageAssets && (
                <Button variant="outline" size="sm" className="mt-2" onClick={() => setAssessmentDialogOpen(true)}>
                  <Gauge className="h-3.5 w-3.5 mr-2" /> Evaluar criticidad
                </Button>
              )}
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

          <TabsContent value="history" className="space-y-6">
            <CriticalityAssessmentHistory assetId={asset.id} refreshToken={historyRefreshToken} loadAssessments={loadAssessments} />
            <Separator />
            <AssetHistory assetId={asset.id} refreshToken={historyRefreshToken} />
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
          {canReportNotice && asset.status !== 'archived' && (
            <Button variant="outline" size="sm" onClick={() => setNoticeDialogOpen(true)}>
              <AlertTriangle className="h-4 w-4 mr-2" />
              Crear aviso
            </Button>
          )}
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

      <MaintenanceNoticeDialog
        open={noticeDialogOpen}
        onOpenChange={setNoticeDialogOpen}
        onCreate={createNotice}
        fixedAsset={{ id: asset.id, label: asset.code ? `${asset.name} (${asset.code})` : asset.name }}
      />

      <CriticalityAssessmentDialog
        open={assessmentDialogOpen}
        onOpenChange={setAssessmentDialogOpen}
        assetId={asset.id}
        assetName={asset.name}
        activeParameters={activeParameters}
        saving={assessmentSaving}
        onSave={calculateCriticality}
        onSaved={() => {
          setHistoryRefreshToken((token) => token + 1);
          void refreshAssets();
          toast({ title: 'Criticidad evaluada', description: `Se guardó una nueva evaluación de criticidad para "${asset.name}".` });
        }}
      />
    </Card>
  );
}
