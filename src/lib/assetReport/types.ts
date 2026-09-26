import type { Asset, AssetCriticality } from '@/types/asset';
import type { TrafficLightColor, TrafficLightReason } from '@/types/assetTrafficLight';
import type { PreventiveTriggerType } from '@/types/preventiveMaintenance';
import type { InspectionRunResult } from '@/types/inspection';
import type { MaintenanceNoticePriority, MaintenanceNoticeStatus } from '@/types/maintenanceNotice';
import type { CriticalityThresholdValues } from '@/types/criticalityMatrix';

/**
 * In-memory snapshot for the on-demand asset PDF report (Fase 1 · Punto 5).
 * Built once per click of "Generar Reporte" — never persisted, never written
 * back to Supabase. See docs/ASSET_REPORT.md.
 */

export interface AssetReportResponsible {
  kind: 'none' | 'available' | 'unavailable';
  name: string | null;
}

export interface AssetReportTechnicalField {
  label: string;
  value: string;
}

export interface AssetReportCriticality {
  effective: AssetCriticality | null;
  /** Only present when there is at least one prior evaluation. `isCurrent`
   * tells whether that evaluation's result still matches assets.criticality
   * (false = the asset was changed manually afterwards, or a new matrix
   * would score it differently). */
  latest: {
    score: number;
    calculatedCriticality: AssetCriticality;
    createdAt: string;
    thresholds: CriticalityThresholdValues;
    isCurrent: boolean;
  } | null;
}

export interface AssetReportTrafficLight {
  /** Archived assets are excluded from the traffic light entirely — see
   * docs/ASSET_TRAFFIC_LIGHT.md. Never rendered as "green". */
  archived: boolean;
  direct: TrafficLightColor | null;
  rollup: TrafficLightColor | null;
  hasChildren: boolean;
  directReasons: TrafficLightReason[];
  rollupReasons: TrafficLightReason[];
}

export interface AssetReportPreventivePlan {
  id: string;
  cardCode: string;
  cardName: string;
  isActive: boolean;
  triggerType: PreventiveTriggerType;
  triggerLabel: string;
  timingStatusLabel: string;
  nextCycleLabel: string;
  responsibleName: string | null;
}

export interface AssetReportInspectionPlan {
  id: string;
  title: string;
  templateName: string;
  frequencyLabel: string;
  nextDueAtLabel: string;
  responsibleName: string | null;
  isActive: boolean;
  lastRun: {
    dateLabel: string;
    resultLabel: string;
  } | null;
}

export interface AssetReportNotice {
  id: string;
  noticeNumber: string;
  priority: MaintenanceNoticePriority;
  status: MaintenanceNoticeStatus;
  title: string;
  responsibleName: string | null;
  reportedAt: string;
}

export interface AssetReportHistoryItem {
  id: string;
  eventDate: string;
  eventLabel: string;
  title: string;
  description: string | null;
  status: string | null;
  actorName: string | null;
  /** One extra line built ONLY from the fields the approved spec allows per
   * event type (never the raw metadata object). Null when the event type has
   * nothing extra to add. */
  detail: string | null;
}

export interface AssetReportQr {
  url: string;
  viewBox: string;
  paths: Array<{ d: string; fill: string }>;
  isLocalOrigin: boolean;
}

export interface AssetReportData {
  generatedAt: string;
  generatedByName: string | null;
  organizationName: string;
  asset: Asset;
  pathNames: string[];
  branchName: string | null;
  categoryName: string | null;
  responsible: AssetReportResponsible;
  technicalFields: AssetReportTechnicalField[];
  criticality: AssetReportCriticality;
  trafficLight: AssetReportTrafficLight;
  preventivePlans: AssetReportPreventivePlan[];
  inspectionPlans: AssetReportInspectionPlan[];
  notices: AssetReportNotice[];
  history: AssetReportHistoryItem[];
  qr: AssetReportQr;
  /** Only a real, previously-uploaded photo. Never '/placeholder.svg'. */
  photoUrl: string | null;
}

/** One label per data source the loader reads — used to report EXACTLY
 * which sections failed when the snapshot cannot be completed. */
export type AssetReportSectionKey =
  | 'asset'
  | 'branch'
  | 'category'
  | 'responsibleDirectory'
  | 'criticality'
  | 'trafficLight'
  | 'preventivePlans'
  | 'inspectionPlans'
  | 'inspectionRuns'
  | 'notices'
  | 'history';

export const ASSET_REPORT_SECTION_LABELS: Record<AssetReportSectionKey, string> = {
  asset: 'Ficha del activo',
  branch: 'Sede',
  category: 'Categoría',
  responsibleDirectory: 'Directorio de responsables',
  criticality: 'Criticidad',
  trafficLight: 'Semáforo operativo',
  preventivePlans: 'Mantenimiento preventivo',
  inspectionPlans: 'Planes de inspección',
  inspectionRuns: 'Ejecuciones de inspección',
  notices: 'Avisos',
  history: 'Historial operativo',
};
