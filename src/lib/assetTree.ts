import type { Asset, AssetTreeNode } from '@/types/asset';

export interface FlatAssetOption {
  asset: Asset;
  path: string;
}

/** Flattens a tree (as built by useAssets()) into a list of { asset, path },
 * where path is a "›"-joined breadcrumb from the root down to that node. */
export const flattenAssetTree = (nodes: AssetTreeNode[], parentPath: string[] = []): FlatAssetOption[] => {
  const options: FlatAssetOption[] = [];
  for (const node of nodes) {
    const path = [...parentPath, node.name];
    options.push({ asset: node, path: path.join(' › ') });
    options.push(...flattenAssetTree(node.children, path));
  }
  return options;
};

/** Maps assetId -> short hierarchical path, for lightweight display (e.g.
 * request lists) without re-walking the tree per row. */
export const buildAssetPathMap = (nodes: AssetTreeNode[]): Map<string, string> => {
  const map = new Map<string, string>();
  flattenAssetTree(nodes).forEach(({ asset, path }) => map.set(asset.id, path));
  return map;
};
