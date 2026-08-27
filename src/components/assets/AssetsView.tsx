import { useAuth } from '@/contexts/AuthContext';
import { useAssets } from '@/hooks/useAssets';
import { useAssetTrafficLight } from '@/hooks/useAssetTrafficLight';
import { AssetTree } from '@/components/assets/AssetTree';
import { AssetDetail } from '@/components/assets/AssetDetail';
import { Building2 } from 'lucide-react';

/** Owns the single `useAssets()` source of truth so AssetTree and AssetDetail
 * stay in sync (e.g. archiving from the detail panel updates the tree).
 * Also owns the single `useAssetTrafficLight()` source of truth so both the
 * tree's dots and the detail panel's "Semáforo operativo" section always
 * agree — computed live from real sources, never a mirror table, see
 * docs/ASSET_TRAFFIC_LIGHT.md. */
export function AssetsView() {
  const { currentOrganization } = useAuth();
  const state = useAssets();
  const trafficLight = useAssetTrafficLight(currentOrganization?.id);

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
