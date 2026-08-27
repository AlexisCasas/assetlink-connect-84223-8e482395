import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { useAssets } from '@/hooks/useAssets';
import { AssetTree } from '@/components/assets/AssetTree';
import { AssetDetail } from '@/components/assets/AssetDetail';
import type { Asset } from '@/types/asset';
import type { ClientBranch } from '@/types/request';

/** Owns the single `useAssets()` source of truth so AssetTree and AssetDetail
 * stay in sync (e.g. archiving from the detail panel updates the tree). */
export function AssetsView() {
  const { currentOrganization, memberships } = useAuth();
  const { tree, assets, categories, loading, error, createAsset, archiveAsset } = useAssets();
  const [branches, setBranches] = useState<ClientBranch[]>([]);
  const [selectedAssetId, setSelectedAssetId] = useState<string | null>(null);

  const canEdit = !!currentOrganization && memberships.some((membership) =>
    membership.isActive
    && membership.organizationId === currentOrganization.id
    && ['owner', 'admin', 'manager'].includes(membership.role),
  );

  useEffect(() => {
    const fetchBranches = async () => {
      if (!currentOrganization) {
        setBranches([]);
        return;
      }
      const { data, error: branchesError } = await supabase
        .from('client_branches')
        .select('id, name, city, site, address, is_active')
        .eq('organization_id', currentOrganization.id)
        .eq('is_active', true)
        .order('name', { ascending: true });
      if (branchesError) {
        console.error('Error loading branches for assets:', branchesError);
        setBranches([]);
        return;
      }
      setBranches((data ?? []).map((branch) => ({
        id: branch.id,
        name: branch.name,
        city: branch.city,
        site: branch.site,
        address: branch.address ?? undefined,
        isActive: branch.is_active,
      })));
    };
    void fetchBranches();
  }, [currentOrganization]);

  const selectedAsset: Asset | null = assets.find((asset) => asset.id === selectedAssetId) ?? null;

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 h-full">
      <AssetTree
        tree={tree}
        assets={assets}
        categories={categories}
        branches={branches}
        loading={loading}
        error={error}
        canEdit={canEdit}
        selectedAssetId={selectedAssetId}
        onSelectAsset={(asset) => setSelectedAssetId(asset.id)}
        onCreateAsset={createAsset}
      />
      <AssetDetail asset={selectedAsset} canEdit={canEdit} onArchive={archiveAsset} />
    </div>
  );
}
