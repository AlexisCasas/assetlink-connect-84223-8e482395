import { useMemo } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Package } from 'lucide-react';
import { useAssets } from '@/hooks/useAssets';
import { buildAssetPathMap } from '@/lib/assetTree';
import { ASSET_NODE_TYPE_LABELS } from '@/lib/assetLabels';
import type { Asset } from '@/types/asset';

interface RequestAssetSummaryProps {
  assetId?: string | null;
  /** Legacy denormalized text (requests.asset) — the only thing a provider
   * (or anyone without RLS access to the full asset row) ever sees. */
  assetText?: string | null;
  /** Card title. Defaults to "Activo asociado"; callers with a different
   * framing (e.g. the request-detail dialog) can override it. */
  title?: string;
}

/**
 * Shows the asset linked to a request, resolved live from useAssets() when
 * the viewer's organization can read it (client owner). useAssets() itself
 * gates the query on canViewAssets, so for a provider (or anyone outside the
 * asset's organization) `assets`/`assetTree` simply come back empty — no new
 * or insecure query is ever attempted, and the component falls back to the
 * safe denormalized `assetText` automatically.
 */
export function RequestAssetSummary({ assetId, assetText, title = 'Activo asociado' }: RequestAssetSummaryProps) {
  const { assets, assetTree } = useAssets();

  const resolvedAsset = useMemo(
    () => (assetId ? assets.find((asset) => asset.id === assetId) : undefined),
    [assets, assetId],
  );
  const path = useMemo(() => {
    if (!assetId || !resolvedAsset) return undefined;
    return buildAssetPathMap(assetTree).get(assetId);
  }, [assetTree, assetId, resolvedAsset]);

  return <RequestAssetSummaryView assetId={assetId} assetText={assetText} title={title} resolvedAsset={resolvedAsset} path={path} />;
}

/** Facility Manager (9C.4): same card from the request's own snapshot only.
 * requests.* does not imply assets.view, so nothing is queried. */
export function StaticRequestAssetSummary({ assetId, assetText, title = 'Activo asociado' }: RequestAssetSummaryProps) {
  return <RequestAssetSummaryView assetId={assetId} assetText={assetText} title={title} resolvedAsset={undefined} path={undefined} />;
}

function RequestAssetSummaryView({ assetId, assetText, title, resolvedAsset, path }: Required<Pick<RequestAssetSummaryProps, 'title'>> & RequestAssetSummaryProps & {
  resolvedAsset: Pick<Asset, 'name' | 'nodeType'> | undefined;
  path: string | undefined;
}) {
  const trimmedText = assetText?.trim();
  if (!assetId && !trimmedText) return null;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Package className="h-4 w-4" />
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {resolvedAsset ? (
          <div className="flex items-start gap-3">
            <Package className="h-5 w-5 mt-0.5 text-primary shrink-0" />
            <div className="min-w-0 space-y-1">
              <div className="flex flex-wrap items-center gap-2">
                <p className="font-medium">{resolvedAsset.name}</p>
                <Badge variant="secondary" className="text-xs">
                  {ASSET_NODE_TYPE_LABELS[resolvedAsset.nodeType]}
                </Badge>
              </div>
              {path && <p className="text-xs text-muted-foreground">{path}</p>}
            </div>
          </div>
        ) : assetId ? (
          <div className="space-y-1">
            <p className="font-medium">{trimmedText || 'Activo vinculado'}</p>
            <p className="text-xs text-muted-foreground">Activo vinculado</p>
          </div>
        ) : (
          <p className="font-medium">{trimmedText}</p>
        )}
      </CardContent>
    </Card>
  );
}
