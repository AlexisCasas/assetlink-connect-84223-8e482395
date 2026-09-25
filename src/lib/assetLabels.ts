import type { AssetCriticality, AssetNodeType, AssetStatus } from '@/types/asset';

export const ASSET_NODE_TYPE_ORDER: AssetNodeType[] = ['structure', 'site', 'area', 'system', 'fleet', 'equipment', 'component', 'subcomponent'];

export const ASSET_NODE_TYPE_LABELS: Record<AssetNodeType, string> = {
  structure: 'Estructura / Unidad',
  site: 'Sede',
  area: 'Área / Sector',
  system: 'Sistema / Línea',
  fleet: 'Flota',
  equipment: 'Equipo',
  component: 'Componente',
  subcomponent: 'Subcomponente',
};

/** Editable statuses only — archiving/restoring go through their own dedicated actions. */
export const ASSET_EDITABLE_STATUSES: AssetStatus[] = ['active', 'maintenance', 'inactive'];

export const ASSET_STATUS_LABELS: Record<AssetStatus, string> = {
  active: 'Activo',
  maintenance: 'Mantenimiento',
  inactive: 'Inactivo',
  archived: 'Archivado',
};

/** Shown when an asset (or process) still references a responsible who is no
 * longer an active owner/admin/manager. The reference is kept as history
 * but never reused for new processes. */
export const RESPONSIBLE_UNAVAILABLE_LABEL = 'Responsable no disponible (inactivo o ya no elegible)';

export const ASSET_CRITICALITY_ORDER: AssetCriticality[] = ['low', 'medium', 'high', 'critical'];

/** Single source of the criticality labels shown in the UI. The internal
 * enum keeps `critical`; it is presented as "Muy Alta". */
export const ASSET_CRITICALITY_LABELS: Record<AssetCriticality, string> = {
  low: 'Baja',
  medium: 'Media',
  high: 'Alta',
  critical: 'Muy Alta',
};

export const getAssetStatusBadgeClass = (status: AssetStatus) => {
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
