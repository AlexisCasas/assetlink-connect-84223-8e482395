import { useEffect, useRef } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useAssets } from '@/hooks/useAssets';
import { useAssetTrafficLight } from '@/hooks/useAssetTrafficLight';
import { useToast } from '@/hooks/use-toast';
import { AssetTree } from '@/components/assets/AssetTree';
import { AssetDetail } from '@/components/assets/AssetDetail';
import { Building2 } from 'lucide-react';

interface AssetsViewProps {
  /** assets.id from a QR / "abrir activo" deep link
   * (#assets?org=<uuid>&assetId=<uuid>). Dashboard already resolved `org`
   * (switching the active organization, or refusing with its own toast when
   * the user has no access to it) before this ever reaches AssetsView, so
   * here it only remains to resolve the asset WITHIN the now-active
   * organization. */
  focusAssetId?: string;
}

/** Owns the single `useAssets()` source of truth so AssetTree and AssetDetail
 * stay in sync (e.g. archiving from the detail panel updates the tree).
 * Also owns the single `useAssetTrafficLight()` source of truth so both the
 * tree's dots and the detail panel's "Semáforo operativo" section always
 * agree — computed live from real sources, never a mirror table, see
 * docs/ASSET_TRAFFIC_LIGHT.md. */
export function AssetsView({ focusAssetId }: AssetsViewProps) {
  const { currentOrganization } = useAuth();
  const state = useAssets();
  const trafficLight = useAssetTrafficLight(currentOrganization?.id);
  const { toast } = useToast();

  // Resolves focusAssetId exactly once per (organization, asset) pair, only
  // once the assets query for that organization has actually loaded — never
  // on every render/refetch, so it can neither re-select an asset the user
  // already navigated away from nor spam the "no se pudo abrir" toast.
  const processedFocusRef = useRef<string | null>(null);

  useEffect(() => {
    const organizationId = currentOrganization?.id;
    if (!focusAssetId || !organizationId || state.loading) return;
    const key = `${organizationId}:${focusAssetId}`;
    if (processedFocusRef.current === key) return;
    processedFocusRef.current = key;

    const target = state.assets.find((asset) => asset.id === focusAssetId);
    if (!target) {
      // Exactly the same message whether the asset doesn't exist, belongs to
      // another tenant, or RLS simply doesn't return it — never revealing
      // which case it is.
      toast({
        title: 'No se pudo abrir el activo',
        description: 'Puede no existir o no tienes acceso.',
        variant: 'destructive',
      });
      return;
    }

    // A QR of an archived asset must still open its sheet for an authorized
    // user — the tree only needs "Ver archivados" turned on to render it.
    if (target.status === 'archived' && !state.showArchived) state.setShowArchived(true);
    state.selectAsset(target.id);
    // `state` (from useAssets()) is a fresh object every render — same
    // unstable-dependency pattern already used for deep-link effects
    // elsewhere (e.g. ProviderRequestList's focusRequestId effect): the
    // processedFocusRef guard above makes every re-run after the first a
    // cheap no-op, so depending on the whole object is safe here.
  }, [focusAssetId, currentOrganization?.id, state, toast]);

  if (!state.canViewAssets) {
    return (
      <div className="flex h-full items-center justify-center p-6">
        <div className="max-w-md text-center text-muted-foreground">
          <Building2 className="mx-auto mb-3 h-8 w-8 opacity-50" />
          <p>{state.accessReason ?? 'No tienes acceso al módulo de Activos.'}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 h-full">
      <AssetTree state={state} trafficLight={trafficLight} />
      <AssetDetail state={state} trafficLight={trafficLight} />
    </div>
  );
}
