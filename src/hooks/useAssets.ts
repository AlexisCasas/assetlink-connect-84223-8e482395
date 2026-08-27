import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import type { Database } from '@/integrations/supabase/types';
import type { Asset, AssetCategory, AssetCriticality, AssetNodeType, AssetStatus, AssetTreeNode } from '@/types/asset';

type AssetRow = Database['public']['Tables']['assets']['Row'];
type AssetCategoryRow = Database['public']['Tables']['asset_categories']['Row'];

const toAsset = (row: AssetRow): Asset => ({
  id: row.id,
  organizationId: row.organization_id,
  branchId: row.branch_id,
  parentAssetId: row.parent_asset_id,
  assetCategoryId: row.asset_category_id,
  code: row.code,
  name: row.name,
  description: row.description,
  nodeType: row.node_type as AssetNodeType,
  status: row.status as AssetStatus,
  criticality: row.criticality as AssetCriticality | null,
  manufacturer: row.manufacturer,
  model: row.model,
  serialNumber: row.serial_number,
  barcode: row.barcode,
  qrCode: row.qr_code,
  purchaseDate: row.purchase_date,
  warrantyUntil: row.warranty_until,
  locationText: row.location_text,
  imageUrl: row.image_url,
  technicalData: (row.technical_data as Record<string, unknown> | null) ?? {},
  metadata: (row.metadata as Record<string, unknown> | null) ?? {},
  createdByUserId: row.created_by_user_id,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const toCategory = (row: AssetCategoryRow): AssetCategory => ({
  id: row.id,
  organizationId: row.organization_id,
  parentCategoryId: row.parent_category_id,
  name: row.name,
  description: row.description,
  isActive: row.is_active,
  createdByUserId: row.created_by_user_id,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const buildTree = (assets: Asset[]): AssetTreeNode[] => {
  const nodes = new Map<string, AssetTreeNode>(assets.map((asset) => [asset.id, { ...asset, children: [] }]));
  const roots: AssetTreeNode[] = [];

  nodes.forEach((node) => {
    const parent = node.parentAssetId ? nodes.get(node.parentAssetId) : undefined;
    if (parent) parent.children.push(node);
    else roots.push(node);
  });

  const sortTree = (list: AssetTreeNode[]) => {
    list.sort((a, b) => a.name.localeCompare(b.name));
    list.forEach((node) => sortTree(node.children));
  };
  sortTree(roots);

  return roots;
};

export interface CreateAssetInput {
  name: string;
  nodeType: AssetNodeType;
  status?: AssetStatus;
  parentAssetId?: string | null;
  branchId?: string | null;
  assetCategoryId?: string | null;
  description?: string | null;
}

export interface CreateCategoryInput {
  name: string;
  description?: string | null;
  parentCategoryId?: string | null;
}

export function useAssets() {
  const { currentOrganization, user } = useAuth();
  const [assets, setAssets] = useState<Asset[]>([]);
  const [categories, setCategories] = useState<AssetCategory[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!currentOrganization) {
      setAssets([]);
      setCategories([]);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const [assetsResult, categoriesResult] = await Promise.all([
        supabase.from('assets').select('*').eq('organization_id', currentOrganization.id).order('name', { ascending: true }),
        supabase.from('asset_categories').select('*').eq('organization_id', currentOrganization.id).order('name', { ascending: true }),
      ]);
      if (assetsResult.error) throw assetsResult.error;
      if (categoriesResult.error) throw categoriesResult.error;
      setAssets((assetsResult.data ?? []).map(toAsset));
      setCategories((categoriesResult.data ?? []).map(toCategory));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los activos.');
    } finally {
      setLoading(false);
    }
  }, [currentOrganization]);

  useEffect(() => { void load(); }, [load]);

  const logEvent = async (assetId: string, eventType: string, description: string) => {
    if (!currentOrganization) return;
    const { error: eventError } = await supabase.from('asset_events').insert({
      organization_id: currentOrganization.id,
      asset_id: assetId,
      event_type: eventType,
      description,
      created_by_user_id: user?.id ?? null,
    });
    if (eventError) console.error('Error logging asset event:', eventError);
  };

  const createAsset = async (input: CreateAssetInput): Promise<Asset | null> => {
    if (!currentOrganization) return null;
    setError(null);
    const { data, error: insertError } = await supabase.from('assets').insert({
      organization_id: currentOrganization.id,
      parent_asset_id: input.parentAssetId ?? null,
      branch_id: input.branchId ?? null,
      asset_category_id: input.assetCategoryId ?? null,
      name: input.name,
      node_type: input.nodeType,
      status: input.status ?? 'active',
      description: input.description ?? null,
      created_by_user_id: user?.id ?? null,
    }).select('*').single();

    if (insertError || !data) {
      setError(insertError?.message ?? 'No se pudo crear el activo.');
      return null;
    }

    const created = toAsset(data);
    setAssets((current) => [...current, created]);
    void logEvent(created.id, 'created', `Activo "${created.name}" creado.`);
    return created;
  };

  const updateAsset = async (assetId: string, changes: Partial<CreateAssetInput>): Promise<boolean> => {
    setError(null);
    const payload: Record<string, unknown> = {};
    if (changes.name !== undefined) payload.name = changes.name;
    if (changes.nodeType !== undefined) payload.node_type = changes.nodeType;
    if (changes.status !== undefined) payload.status = changes.status;
    if (changes.parentAssetId !== undefined) payload.parent_asset_id = changes.parentAssetId;
    if (changes.branchId !== undefined) payload.branch_id = changes.branchId;
    if (changes.assetCategoryId !== undefined) payload.asset_category_id = changes.assetCategoryId;
    if (changes.description !== undefined) payload.description = changes.description;

    const { data, error: updateError } = await supabase.from('assets').update(payload).eq('id', assetId).select('*').single();
    if (updateError || !data) {
      setError(updateError?.message ?? 'No se pudo actualizar el activo.');
      return false;
    }

    const updated = toAsset(data);
    setAssets((current) => current.map((asset) => (asset.id === assetId ? updated : asset)));
    return true;
  };

  const archiveAsset = async (assetId: string): Promise<boolean> => {
    const ok = await updateAsset(assetId, { status: 'archived' });
    if (ok) void logEvent(assetId, 'archived', 'Activo archivado.');
    return ok;
  };

  const createCategory = async (input: CreateCategoryInput): Promise<AssetCategory | null> => {
    if (!currentOrganization) return null;
    setError(null);
    const { data, error: insertError } = await supabase.from('asset_categories').insert({
      organization_id: currentOrganization.id,
      name: input.name,
      description: input.description ?? null,
      parent_category_id: input.parentCategoryId ?? null,
      created_by_user_id: user?.id ?? null,
    }).select('*').single();

    if (insertError || !data) {
      setError(insertError?.message ?? 'No se pudo crear la categoría.');
      return null;
    }

    const created = toCategory(data);
    setCategories((current) => [...current, created]);
    return created;
  };

  return {
    assets,
    categories,
    tree: buildTree(assets),
    loading,
    error,
    refresh: load,
    createAsset,
    updateAsset,
    archiveAsset,
    createCategory,
  };
}
