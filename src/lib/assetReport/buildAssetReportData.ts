import type { Asset } from '@/types/asset';
import type { AssetHistoryItem } from '@/types/assetHistory';
import type { InspectionRunSummary } from '@/types/inspection';
import type { AssetReportRawSources } from './loadAssetReportData';
import type {
  AssetReportData,
  AssetReportHistoryItem,
  AssetReportInspectionPlan,
  AssetReportNotice,
  AssetReportPreventivePlan,
  AssetReportQr,
  AssetReportResponsible,
} from './types';
import {
  CUSTOM_UNIT_LABELS,
  INSPECTION_FREQUENCY_LABELS,
  INSPECTION_RESULT_LABELS,
  INSPECTION_RUN_STATUS_LABELS,
  PREVENTIVE_FREQUENCY_LABELS,
  PREVENTIVE_TIMING_STATUS_LABELS,
  formatReportDate,
  formatReportDateTime,
  extractTechnicalFields,
  pdfText,
  resolveAssetPathNames,
} from './utils';

export interface BuildAssetReportDataInput {
  raw: AssetReportRawSources;
  allAssets: Asset[];
  organizationName: string;
  generatedByName: string | null;
  qr: AssetReportQr;
}

const resolvePathNames = (allAssets: Asset[], asset: Asset): string[] => {
  const inMemory = allAssets.find((item) => item.id === asset.id);
  const ancestorPath = resolveAssetPathNames(allAssets, inMemory ?? asset);
  // The walk's own last segment may be a stale in-memory name — the freshly
  // re-read `asset.name` always wins for the asset itself, ancestors keep
  // whatever was already loaded (no extra query, per the approved decision).
  return ancestorPath.length > 0 ? [...ancestorPath.slice(0, -1), asset.name] : [asset.name];
};

const resolveResponsible = (asset: Asset, planners: AssetReportRawSources['planners']): AssetReportResponsible => {
  if (!asset.defaultResponsibleMemberId) return { kind: 'none', name: null };
  const match = planners.find((planner) => planner.memberId === asset.defaultResponsibleMemberId);
  return match ? { kind: 'available', name: match.name } : { kind: 'unavailable', name: null };
};

const buildPreventiveTriggerLabel = (plan: AssetReportRawSources['preventivePlans'][number]): string => {
  if (plan.trigger_type === 'meter') {
    const name = plan.meter_name ?? 'medidor sin nombre';
    const interval = plan.interval_value != null ? ` · cada ${plan.interval_value} ${plan.meter_unit ?? ''}`.trim() : '';
    return `Medidor: ${name}${interval}`;
  }
  const base = plan.frequency ? PREVENTIVE_FREQUENCY_LABELS[plan.frequency] : 'Calendario';
  if (plan.frequency === 'custom' && plan.custom_interval && plan.custom_unit) {
    return `${base} (cada ${plan.custom_interval} ${CUSTOM_UNIT_LABELS[plan.custom_unit]})`;
  }
  return base ?? 'Calendario';
};

const buildPreventiveNextCycleLabel = (plan: AssetReportRawSources['preventivePlans'][number]): string => {
  const occurrence = plan.current_occurrence;
  if (!occurrence) return 'Sin ciclo programado';
  const when = occurrence.due_at
    ? formatReportDate(occurrence.due_at)
    : `${occurrence.due_meter_value ?? '-'} ${plan.meter_unit ?? ''}`.trim();
  return `Ciclo #${occurrence.sequence} - ${when}`;
};

const buildPreventivePlans = (raw: AssetReportRawSources, asset: Asset): AssetReportPreventivePlan[] =>
  raw.preventivePlans
    .filter((plan) => plan.asset_id === asset.id)
    .map((plan) => ({
      id: plan.id,
      cardCode: plan.card_code,
      cardName: pdfText(plan.card_name),
      isActive: plan.is_active,
      triggerType: plan.trigger_type,
      triggerLabel: pdfText(buildPreventiveTriggerLabel(plan)),
      timingStatusLabel: plan.timing_status ? PREVENTIVE_TIMING_STATUS_LABELS[plan.timing_status] : 'Sin estado',
      nextCycleLabel: pdfText(buildPreventiveNextCycleLabel(plan)),
      responsibleName: plan.responsible_member_id
        ? raw.planners.find((planner) => planner.memberId === plan.responsible_member_id)?.name ?? null
        : null,
    }));

const runTimestamp = (run: InspectionRunSummary): number => {
  const value = run.completedAt ?? run.startedAt ?? run.scheduledFor;
  const time = value ? new Date(value).getTime() : NaN;
  return Number.isNaN(time) ? -Infinity : time;
};

/** Picks the latest run for a plan by explicit date comparison
 * (completedAt, falling back to startedAt then scheduledFor) — never assumes
 * get_inspection_runs returns rows in any particular order. */
const findLastRun = (runs: InspectionRunSummary[], planId: string): InspectionRunSummary | null =>
  runs
    .filter((run) => run.planId === planId)
    .reduce<InspectionRunSummary | null>((latest, run) => (
      !latest || runTimestamp(run) > runTimestamp(latest) ? run : latest
    ), null);

const buildInspectionFrequencyLabel = (plan: AssetReportRawSources['inspectionPlans'][number]): string => {
  const base = INSPECTION_FREQUENCY_LABELS[plan.frequency] ?? plan.frequency;
  if (plan.frequency === 'custom' && plan.customInterval && plan.customUnit) {
    return `${base} (cada ${plan.customInterval} ${CUSTOM_UNIT_LABELS[plan.customUnit]})`;
  }
  return base;
};

const buildInspectionPlans = (raw: AssetReportRawSources, asset: Asset): AssetReportInspectionPlan[] =>
  raw.inspectionPlans
    // Exactly assetId === asset.id — never areaAssetId/branchId (an area or
    // sede-level plan is never attributed to one of its assets here).
    .filter((plan) => plan.assetId === asset.id)
    .map((plan) => {
      const lastRun = findLastRun(raw.inspectionRuns, plan.id);
      return {
        id: plan.id,
        title: pdfText(plan.title),
        templateName: pdfText(plan.templateName),
        frequencyLabel: pdfText(buildInspectionFrequencyLabel(plan)),
        nextDueAtLabel: formatReportDate(plan.nextDueAt),
        responsibleName: plan.responsibleName,
        isActive: plan.isActive,
        lastRun: lastRun ? {
          dateLabel: formatReportDate(lastRun.completedAt ?? lastRun.startedAt ?? lastRun.scheduledFor),
          resultLabel: lastRun.result
            ? INSPECTION_RESULT_LABELS[lastRun.result]
            : INSPECTION_RUN_STATUS_LABELS[lastRun.status] ?? lastRun.status,
        } : null,
      };
    });

const buildNotices = (raw: AssetReportRawSources, asset: Asset): AssetReportNotice[] =>
  raw.notices
    .filter((notice) => notice.assetId === asset.id)
    .map((notice) => ({
      id: notice.id,
      noticeNumber: notice.noticeNumber,
      priority: notice.priority,
      status: notice.status,
      title: pdfText(notice.title),
      responsibleName: notice.responsibleName,
      reportedAt: notice.reportedAt,
    }));

/** Builds the ONE extra detail line the approved spec allows per event type
 * — never the raw metadata object, never actorEmail/file_url/payload. */
const buildHistoryDetail = (item: AssetHistoryItem): string | null => {
  const meta = item.metadata;
  const str = (key: string): string | null => (typeof meta[key] === 'string' ? meta[key] as string : null);
  const num = (key: string): number | null => (typeof meta[key] === 'number' ? meta[key] as number : null);

  switch (item.eventType) {
    case 'technician_report': {
      const started = str('started_at');
      const finished = str('finished_at');
      const hours = num('actual_hours');
      const parts = [
        started ? `Inicio: ${formatReportDateTime(started)}` : null,
        finished ? `Fin: ${formatReportDateTime(finished)}` : null,
        hours !== null ? `${hours} h reales` : null,
      ].filter((part): part is string => !!part);
      return parts.length > 0 ? parts.join(' · ') : null;
    }
    case 'material_used': {
      const qty = num('quantity_used');
      const unit = str('unit') ?? '';
      const code = str('material_code');
      if (qty === null) return null;
      return `${code ? `${code} · ` : ''}${qty} ${unit}`.trim();
    }
    case 'request_created': {
      const number = str('request_number');
      return number ? `Solicitud ${number}` : null;
    }
    case 'work_order_created':
    case 'activity_created': {
      const number = str('work_order_number');
      return number ? `OT ${number}` : null;
    }
    case 'evidence_added': {
      const fileName = str('file_name');
      return fileName ? `Archivo: ${fileName}` : null;
    }
    default:
      return null;
  }
};

const buildHistory = (raw: AssetReportRawSources): AssetReportHistoryItem[] =>
  raw.history.map((item) => ({
    id: item.id,
    eventDate: item.eventDate,
    eventLabel: pdfText(item.eventLabel),
    title: pdfText(item.title),
    description: item.description ? pdfText(item.description) : null,
    status: item.status,
    actorName: item.actorName,
    detail: buildHistoryDetail(item),
  }));

/**
 * Pure transform: raw fetched sources → the final report snapshot. Never
 * touches Supabase, the DOM, or any Blob/PDF API — trivially unit-testable
 * with plain fixtures. Filtering rules here (asset_id/assetId exact match,
 * archived exclusion, etc.) mirror the approved diagnosis exactly.
 */
export const buildAssetReportData = (input: BuildAssetReportDataInput): AssetReportData => {
  const { raw, allAssets, organizationName, generatedByName, qr } = input;
  const asset = raw.asset;
  const archived = asset.status === 'archived';
  const hasChildren = allAssets.some((item) => item.parentAssetId === asset.id);
  const trafficLight = raw.trafficLightAssets.find((item) => item.assetId === asset.id) ?? null;
  const latestAssessment = raw.assessments[0] ?? null;
  const rawPhoto = asset.imageUrl?.trim() || null;

  return {
    generatedAt: new Date().toISOString(),
    generatedByName,
    organizationName,
    asset,
    pathNames: resolvePathNames(allAssets, asset),
    branchName: raw.branchName,
    categoryName: raw.categoryName,
    responsible: resolveResponsible(asset, raw.planners),
    technicalFields: extractTechnicalFields(asset.technicalData),
    criticality: {
      effective: asset.criticality,
      latest: latestAssessment ? {
        score: latestAssessment.score,
        calculatedCriticality: latestAssessment.calculatedCriticality,
        createdAt: latestAssessment.createdAt,
        thresholds: latestAssessment.thresholds,
        isCurrent: latestAssessment.calculatedCriticality === asset.criticality,
      } : null,
    },
    trafficLight: archived
      ? { archived: true, direct: null, rollup: null, hasChildren, directReasons: [], rollupReasons: [] }
      : {
        archived: false,
        direct: trafficLight?.directColor ?? null,
        rollup: hasChildren ? (trafficLight?.rollupColor ?? null) : null,
        hasChildren,
        directReasons: trafficLight?.directReasons ?? [],
        rollupReasons: hasChildren ? (trafficLight?.rollupReasons ?? []) : [],
      },
    preventivePlans: buildPreventivePlans(raw, asset),
    inspectionPlans: buildInspectionPlans(raw, asset),
    notices: buildNotices(raw, asset),
    history: buildHistory(raw),
    qr,
    photoUrl: rawPhoto && rawPhoto !== '/placeholder.svg' ? rawPhoto : null,
  };
};
