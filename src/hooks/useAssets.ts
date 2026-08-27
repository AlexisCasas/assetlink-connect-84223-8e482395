import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import type { Database } from '@/integrations/supabase/types';
import type {
  Asset,
  AssetCategory,
  AssetCriticality,
  AssetNodeType,
  AssetStatus,
  AssetTreeNode,
  CreateAssetInput,
  UpdateAssetInput,
} from '@/types/asset';
import type { ClientBranch } from '@/types/request';

type AssetRow = Database['public']['Tables']['assets']['Row'];
type AssetCategoryRow = Database['public']['Tables']['asset_categories']['Row'];

const ASSET_NODE_TYPES: AssetNodeType[] = ['structure', 'site', 'area', 'system', 'fleet', 'equipment', 'component', 'subcomponent'];
const ASSET_STATUSES: AssetStatus[] = ['active', 'maintenance', 'inactive', 'archived'];
const ASSET_CRITICALITIES: AssetCriticality[] = ['low', 'medium', 'high', 'critical'];

const GENERIC_LOAD_ERROR = 'No se pudieron cargar los activos.';

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

/**
 * Builds the tree from `parentAssetId` and defends against corrupted data:
 * - An asset whose declared parent isn't in the loaded set becomes a root
 *   instead of disappearing.
 * - A bounded (visited-set) traversal detects any node unreachable from a
 *   real root (only possible via a cyclic parent chain) and surfaces it as
 *   an extra root too, instead of silently hiding it or risking recursion
 *   that never terminates.
 */
const buildTree = (assets: Asset[]): AssetTreeNode[] => {
  const nodes = new Map<string, AssetTreeNode>(assets.map((asset) => [asset.id, { ...asset, children: [] }]));
  const roots: AssetTreeNode[] = [];

  nodes.forEach((node) => {
    const parent = node.parentAssetId ? nodes.get(node.parentAssetId) : undefined;
    if (parent) parent.children.push(node);
    else roots.push(node);
  });

  const visited = new Set<string>();
  const stack = [...roots];
  while (stack.length > 0) {
    const node = stack.pop()!;
    if (visited.has(node.id)) continue;
    visited.add(node.id);
    stack.push(...node.children);
  }
  nodes.forEach((node) => {
    if (!visited.has(node.id)) roots.push(node);
  });

  const sortTree = (list: AssetTreeNode[]) => {
    list.sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
    list.forEach((node) => sortTree(node.children));
  };
  sortTree(roots);

  return roots;
};

/** Hides archived branches by default; when a parent is archived its whole
 * subtree is hidden too (a visible child can't "hang" under a hidden parent). */
const filterArchived = (nodes: AssetTreeNode[], showArchived: boolean): AssetTreeNode[] => {
  if (showArchived) return nodes;
  return nodes
    .filter((node) => node.status !== 'archived')
    .map((node) => ({ ...node, children: filterArchived(node.children, showArchived) }));
};

const validateAssetInput = (input: UpdateAssetInput, knownAssets: Asset[], selfId?: string): string | null => {
  if (input.name !== undefined && !input.name.trim()) return 'El nombre es obligatorio.';
  if (input.nodeType !== undefined && !ASSET_NODE_TYPES.includes(input.nodeType)) return 'El tipo de nodo no es válido.';
  if (input.status !== undefined && !ASSET_STATUSES.includes(input.status)) return 'El estado no es válido.';
  if (input.criticality !== undefined && input.criticality !== null && !ASSET_CRITICALITIES.includes(input.criticality)) {
    return 'La criticidad no es válida.';
  }
  if (input.parentAssetId) {
    if (input.parentAssetId === selfId) return 'Un activo no puede ser su propio padre.';
    if (!knownAssets.some((asset) => asset.id === input.parentAssetId)) return 'El activo padre seleccionado no es válido.';
  }
  return null;
};

const toClientBranch = (row: { id: string; name: string; city: string; site: string; address: string | null; is_active: boolean }): ClientBranch => ({
  id: row.id,
  name: row.name,
  city: row.city,
  site: row.site,
  address: row.address ?? undefined,
  isActive: row.is_active,
});

export type { CreateAssetInput, UpdateAssetInput };

export function useAssets() {
  const { currentOrganization, currentMembership, user } = useAuth();
  const queryClient = useQueryClient();
  const organizationId = currentOrganization?.id;

  const [selectedAssetId, setSelectedAssetId] = useState<string | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const [mutationError, setMutationError] = useState<string | null>(null);

  // --- Permissions -----------------------------------------------------
  const isClientCompany = currentOrganization?.organizationType === 'client_company';
  const hasActiveMembership = !!currentMembership?.isActive;
  const canManageAssets = isClientCompany && hasActiveMembership && ['owner', 'admin', 'manager'].includes(currentMembership!.role);

  let canViewAssets = false;
  let accessReason: string | undefined;
  if (!currentOrganization) {
    accessReason = 'Selecciona una organización cliente.';
  } else if (!isClientCompany) {
    accessReason = currentOrganization.organizationType === 'platform_admin'
      ? 'Los activos se administran desde la organización cliente, no desde la organización de plataforma.'
      : 'Los activos aún no están disponibles para organizaciones proveedoras.';
  } else if (!hasActiveMembership) {
    accessReason = 'No tienes una membresía activa en esta organización.';
  } else {
    canViewAssets = true;
  }

  // --- Queries -----------------------------------------------------------
  const assetsQuery = useQuery({
    queryKey: ['assets', organizationId],
    queryFn: async () => {
      const { data, error } = await supabase.from('assets').select('*').eq('organization_id', organizationId!).order('name', { ascending: true });
      if (error) throw error;
      return (data ?? []).map(toAsset);
    },
    enabled: !!organizationId && canViewAssets,
  });

  const categoriesQuery = useQuery({
    queryKey: ['asset-categories', organizationId],
    queryFn: async () => {
      const { data, error } = await supabase.from('asset_categories').select('*').eq('organization_id', organizationId!).order('name', { ascending: true });
      if (error) throw error;
      return (data ?? []).map(toCategory);
    },
    enabled: !!organizationId && canViewAssets,
  });

  const branchesQuery = useQuery({
    queryKey: ['asset-branches', organizationId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('client_branches')
        .select('id, name, city, site, address, is_active')
        .eq('organization_id', organizationId!)
        .eq('is_active', true)
        .order('name', { ascending: true });
      if (error) throw error;
      return (data ?? []).map(toClientBranch);
    },
    enabled: !!organizationId && canViewAssets,
  });

  const assets = assetsQuery.data ?? [];
  const categories = categoriesQuery.data ?? [];
  const branches = branchesQuery.data ?? [];
  const loading = assetsQuery.isLoading || categoriesQuery.isLoading || branchesQuery.isLoading;

  const loadError = assetsQuery.isError
    ? GENERIC_LOAD_ERROR
    : categoriesQuery.isError
      ? 'No se pudieron cargar las categorías de activos.'
      : branchesQuery.isError
        ? 'No se pudieron cargar las sucursales.'
        : null;
  const error = loadError ?? mutationError;

  const assetTree = useMemo(() => filterArchived(buildTree(assets), showArchived), [assets, showArchived]);
  const selectedAsset = useMemo(() => assets.find((asset) => asset.id === selectedAssetId) ?? null, [assets, selectedAssetId]);

  const selectAsset = (assetId: string) => setSelectedAssetId(assetId);
  const clearSelection = () => setSelectedAssetId(null);

  const refreshAssets = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ['assets', organizationId] }),
      queryClient.invalidateQueries({ queryKey: ['asset-categories', organizationId] }),
      queryClient.invalidateQueries({ queryKey: ['asset-branches', organizationId] }),
    ]);
  };

  const invalidateAssets = () => queryClient.invalidateQueries({ queryKey: ['assets', organizationId] });

  // Best-effort audit trail: never lets a failure break the caller's
  // create/update/archive/restore result, and never logs input payloads.
  const logEvent = async (assetId: string, eventType: string, description: string) => {
    if (!organizationId) return;
    try {
      const { error: eventError } = await supabase.from('asset_events').insert({
        organization_id: organizationId,
        asset_id: assetId,
        event_type: eventType,
        description,
        created_by_user_id: user?.id ?? null,
      });
      if (eventError) console.error('Error logging asset event:', eventError.message);
    } catch {
      console.error('Unexpected error logging asset event.');
    }
  };

  // --- Mutations -----------------------------------------------------------
  const createMutation = useMutation({
    mutationFn: async (input: CreateAssetInput) => {
      if (!organizationId) throw new Error('Selecciona una organización cliente.');
      if (!canManageAssets) throw new Error('No tienes permisos para gestionar activos.');
      const validationError = validateAssetInput(input, assets);
      if (validationError) throw new Error(validationError);

      const { data, error: insertError } = await supabase.from('assets').insert({
        organization_id: organizationId,
        parent_asset_id: input.parentAssetId ?? null,
        branch_id: input.branchId ?? null,
        asset_category_id: input.assetCategoryId ?? null,
        code: input.code ?? null,
        name: input.name.trim(),
        node_type: input.nodeType,
        status: input.status ?? 'active',
        criticality: input.criticality ?? null,
        description: input.description ?? null,
        created_by_user_id: user?.id ?? null,
      }).select('*').single();

      if (insertError || !data) throw new Error('No se pudo crear el activo.');
      return toAsset(data);
    },
    onSuccess: (created) => {
      setMutationError(null);
      void invalidateAssets();
      void logEvent(created.id, 'created', `Activo "${created.name}" creado.`);
    },
    onError: (err) => setMutationError(err instanceof Error ? err.message : 'No se pudo crear el activo.'),
  });

  const updateMutation = useMutation({
    mutationFn: async ({ assetId, changes, eventType, eventDescription, failureMessage }: {
      assetId: string;
      changes: UpdateAssetInput;
      eventType: string;
      eventDescription: string;
      failureMessage: string;
    }) => {
      if (!canManageAssets) throw new Error('No tienes permisos para gestionar activos.');
      const validationError = validateAssetInput(changes, assets, assetId);
      if (validationError) throw new Error(validationError);

      const payload: Record<string, unknown> = {};
      if (changes.name !== undefined) payload.name = changes.name.trim();
      if (changes.nodeType !== undefined) payload.node_type = changes.nodeType;
      if (changes.status !== undefined) payload.status = changes.status;
      if (changes.criticality !== undefined) payload.criticality = changes.criticality;
      if (changes.parentAssetId !== undefined) payload.parent_asset_id = changes.parentAssetId;
      if (changes.branchId !== undefined) payload.branch_id = changes.branchId;
      if (changes.assetCategoryId !== undefined) payload.asset_category_id = changes.assetCategoryId;
      if (changes.code !== undefined) payload.code = changes.code;
      if (changes.description !== undefined) payload.description = changes.description;

      const { data, error: updateError } = await supabase.from('assets').update(payload).eq('id', assetId).select('*').single();
      if (updateError || !data) throw new Error(failureMessage);
      return { updated: toAsset(data), eventType, eventDescription };
    },
    onSuccess: ({ updated, eventType, eventDescription }) => {
      setMutationError(null);
      void invalidateAssets();
      void logEvent(updated.id, eventType, eventDescription);
    },
    onError: (err) => setMutationError(err instanceof Error ? err.message : 'No se pudo actualizar el activo.'),
  });

  const createAsset = async (input: CreateAssetInput): Promise<Asset | null> => {
    try {
      return await createMutation.mutateAsync(input);
    } catch {
      return null;
    }
  };

  const updateAsset = async (assetId: string, changes: UpdateAssetInput): Promise<boolean> => {
    try {
      await updateMutation.mutateAsync({ assetId, changes, eventType: 'updated', eventDescription: 'Activo actualizado.', failureMessage: 'No se pudo actualizar el activo.' });
      return true;
    } catch {
      return false;
    }
  };

  const archiveAsset = async (assetId: string): Promise<boolean> => {
    try {
      await updateMutation.mutateAsync({ assetId, changes: { status: 'archived' }, eventType: 'archived', eventDescription: 'Activo archivado.', failureMessage: 'No se pudo archivar el activo.' });
      return true;
    } catch {
      return false;
    }
  };

  const restoreAsset = async (assetId: string): Promise<boolean> => {
    try {
      await updateMutation.mutateAsync({ assetId, changes: { status: 'active' }, eventType: 'restored', eventDescription: 'Activo restaurado.', failureMessage: 'No se pudo restaurar el activo.' });
      return true;
    } catch {
      return false;
    }
  };

  return {
    assets,
    assetTree,
    selectedAsset,
    selectedAssetId,
    categories,
    branches,
    loading,
    error,
    canViewAssets,
    canManageAssets,
    accessReason,
    showArchived,
    setShowArchived,
    selectAsset,
    clearSelection,
    createAsset,
    updateAsset,
    archiveAsset,
    restoreAsset,
    refreshAssets,
    saving: createMutation.isPending || updateMutation.isPending,
  };
}

export type UseAssetsResult = ReturnType<typeof useAssets>;
