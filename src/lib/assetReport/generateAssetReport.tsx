import { pdf } from '@react-pdf/renderer';
import type { Asset } from '@/types/asset';
import { buildAssetQrUrl } from '@/lib/assetQr';
import { isPublicAppUrlLocal, publicAppUrl } from '@/lib/env';
import { buildAssetReportData } from './buildAssetReportData';
import { AssetReportDocument } from './AssetReportDocument';
import { loadAssetReportData } from './loadAssetReportData';
import { buildVectorQr } from './qr';
import { buildAssetReportFilename } from './utils';
import { ASSET_REPORT_SECTION_LABELS, type AssetReportSectionKey } from './types';

export interface GenerateAssetReportInput {
  asset: Asset;
  allAssets: Asset[];
  organizationName: string;
  generatedByName: string | null;
}

// String `status` discriminant, not a boolean `ok` — see the comment on
// AssetReportLoadResult in loadAssetReportData.ts for why (this project's
// tsconfig has strict: false, which breaks narrowing on boolean literals).
export type GenerateAssetReportResult =
  | { status: 'ok' }
  | { status: 'load-failed'; failedSectionLabels: string[] }
  | { status: 'render-failed' };

const downloadBlob = (blob: Blob, filename: string): void => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
};

/**
 * Entry point dynamically imported by AssetDetail on "Generar Reporte" — see
 * docs/ASSET_REPORT.md. Everything here is read-only: it never inserts an
 * asset_event, never touches assets.updated_at, never uploads anything.
 * Loading → building the snapshot → rendering are kept in separate modules
 * (loadAssetReportData / buildAssetReportData / AssetReportDocument) so each
 * stays independently testable; this file only wires them together and
 * triggers the browser download.
 */
export async function generateAssetReport(input: GenerateAssetReportInput): Promise<GenerateAssetReportResult> {
  const { asset, allAssets, organizationName, generatedByName } = input;

  const loadResult = await loadAssetReportData({
    assetId: asset.id,
    organizationId: asset.organizationId,
    knownBranchId: asset.branchId,
    knownCategoryId: asset.assetCategoryId,
  });

  if (loadResult.status === 'failed') {
    return {
      status: 'load-failed',
      failedSectionLabels: loadResult.failedSections.map((key: AssetReportSectionKey) => ASSET_REPORT_SECTION_LABELS[key]),
    };
  }

  try {
    const qrUrl = buildAssetQrUrl(publicAppUrl, asset.organizationId, asset.id);
    const vectorQr = buildVectorQr(qrUrl);

    const data = buildAssetReportData({
      raw: loadResult.raw,
      allAssets,
      organizationName,
      generatedByName,
      qr: { url: qrUrl, viewBox: vectorQr.viewBox, paths: vectorQr.paths, isLocalOrigin: isPublicAppUrlLocal },
    });

    const logoUrl = new URL('/brand/logo-primary.png', window.location.origin).href;
    const blob = await pdf(<AssetReportDocument data={data} logoUrl={logoUrl} />).toBlob();
    downloadBlob(blob, buildAssetReportFilename(asset, new Date(data.generatedAt)));
    return { status: 'ok' };
  } catch {
    return { status: 'render-failed' };
  }
}
