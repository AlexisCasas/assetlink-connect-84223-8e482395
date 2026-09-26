import type { Asset } from '@/types/asset';
import type { AssetTrafficLight } from '@/types/assetTrafficLight';
import type { PreventivePlan } from '@/types/preventiveMaintenance';
import type { InspectionPlan, InspectionRunSummary } from '@/types/inspection';
import type { MaintenanceNotice } from '@/types/maintenanceNotice';
import type { AssetHistoryItem } from '@/types/assetHistory';
import type { CriticalityAssessment } from '@/types/criticalityMatrix';
import type { AssignablePlanner } from '@/hooks/useOrganizationPlanners';
import type { AssetReportSectionKey } from './types';
import {
  fetchReportAsset,
  fetchReportAssessments,
  fetchReportBranchName,
  fetchReportCategoryName,
  fetchReportHistory,
  fetchReportInspectionPlans,
  fetchReportInspectionRuns,
  fetchReportNotices,
  fetchReportPlanners,
  fetchReportPreventivePlans,
  fetchReportTrafficLight,
} from './sources';

export interface AssetReportRawSources {
  asset: Asset;
  branchName: string | null;
  categoryName: string | null;
  planners: AssignablePlanner[];
  assessments: CriticalityAssessment[];
  trafficLightAssets: AssetTrafficLight[];
  preventivePlans: PreventivePlan[];
  inspectionPlans: InspectionPlan[];
  inspectionRuns: InspectionRunSummary[];
  notices: MaintenanceNotice[];
  history: AssetHistoryItem[];
}

// A `status` string discriminant, not a boolean `ok` — this project's
// tsconfig runs with `strict: false` (strictNullChecks off), under which
// TypeScript cannot narrow a discriminated union on a `true`/`false`
// literal field (verified: it silently widens to `boolean` and every
// branch access errors). A string-literal discriminant narrows correctly
// either way.
export type AssetReportLoadResult =
  | { status: 'ok'; raw: AssetReportRawSources }
  | { status: 'failed'; failedSections: AssetReportSectionKey[] };

export interface AssetReportLoadInput {
  assetId: string;
  organizationId: string;
  /** Best-known values from the already-selected in-memory asset, used only
   * to kick off the branch/category lookups in the SAME batch instead of
   * waiting on the fresh asset re-read below — the fresh read still
   * re-validates the asset itself independently. */
  knownBranchId: string | null;
  knownCategoryId: string | null;
}

/**
 * Loads every source the report needs in one batch (Promise.allSettled, not
 * Promise.all): a rejected section never hides behind another section's
 * success, and the caller gets the full list of what failed instead of just
 * the first error. Nothing is fetched until this is called — AssetDetail
 * only calls it after the user clicks "Generar Reporte" (see
 * generateAssetReport.ts).
 *
 * An empty result (0 rows) from any source is NOT a failure — it is valid
 * data ("sin planes preventivos", "sin avisos", etc.), handled later by
 * buildAssetReportData. Only a thrown/rejected fetch counts as a failed
 * section, and ANY failed section aborts the whole report — no partial PDF.
 */
export const loadAssetReportData = async (input: AssetReportLoadInput): Promise<AssetReportLoadResult> => {
  const { assetId, organizationId, knownBranchId, knownCategoryId } = input;

  const entries: Array<[AssetReportSectionKey, Promise<unknown>]> = [
    ['asset', fetchReportAsset(assetId)],
    ['branch', fetchReportBranchName(knownBranchId)],
    ['category', fetchReportCategoryName(knownCategoryId)],
    ['responsibleDirectory', fetchReportPlanners(organizationId)],
    ['criticality', fetchReportAssessments(assetId)],
    ['trafficLight', fetchReportTrafficLight(organizationId)],
    ['preventivePlans', fetchReportPreventivePlans(organizationId)],
    ['inspectionPlans', fetchReportInspectionPlans(organizationId)],
    ['inspectionRuns', fetchReportInspectionRuns(organizationId)],
    ['notices', fetchReportNotices(organizationId)],
    ['history', fetchReportHistory(assetId)],
  ];

  const settled = await Promise.allSettled(entries.map(([, promise]) => promise));

  const failedSections: AssetReportSectionKey[] = [];
  settled.forEach((result, index) => {
    if (result.status === 'rejected') failedSections.push(entries[index][0]);
  });

  if (failedSections.length > 0) return { status: 'failed', failedSections };

  const value = <T,>(index: number): T => (settled[index] as PromiseFulfilledResult<T>).value;

  return {
    status: 'ok',
    raw: {
      asset: value<Asset>(0),
      branchName: value<string | null>(1),
      categoryName: value<string | null>(2),
      planners: value<AssignablePlanner[]>(3),
      assessments: value<CriticalityAssessment[]>(4),
      trafficLightAssets: value<AssetTrafficLight[]>(5),
      preventivePlans: value<PreventivePlan[]>(6),
      inspectionPlans: value<InspectionPlan[]>(7),
      inspectionRuns: value<InspectionRunSummary[]>(8),
      notices: value<MaintenanceNotice[]>(9),
      history: value<AssetHistoryItem[]>(10),
    },
  };
};
