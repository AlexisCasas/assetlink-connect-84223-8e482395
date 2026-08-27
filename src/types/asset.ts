export type AssetNodeType =
  | 'structure'
  | 'site'
  | 'area'
  | 'system'
  | 'fleet'
  | 'equipment'
  | 'component'
  | 'subcomponent';

export type AssetStatus = 'active' | 'maintenance' | 'inactive' | 'archived';

export type AssetCriticality = 'low' | 'medium' | 'high' | 'critical';

export interface AssetCategory {
  id: string;
  organizationId: string;
  parentCategoryId: string | null;
  name: string;
  description: string | null;
  isActive: boolean;
  createdByUserId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface Asset {
  id: string;
  organizationId: string;
  branchId: string | null;
  parentAssetId: string | null;
  assetCategoryId: string | null;
  code: string | null;
  name: string;
  description: string | null;
  nodeType: AssetNodeType;
  status: AssetStatus;
  criticality: AssetCriticality | null;
  manufacturer: string | null;
  model: string | null;
  serialNumber: string | null;
  barcode: string | null;
  qrCode: string | null;
  purchaseDate: string | null;
  warrantyUntil: string | null;
  locationText: string | null;
  imageUrl: string | null;
  technicalData: Record<string, unknown>;
  metadata: Record<string, unknown>;
  createdByUserId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AssetDocument {
  id: string;
  organizationId: string;
  assetId: string;
  documentType: string | null;
  name: string;
  fileUrl: string | null;
  storagePath: string | null;
  uploadedByUserId: string | null;
  createdAt: string;
}

export interface AssetEvent {
  id: string;
  organizationId: string;
  assetId: string;
  eventType: string;
  description: string | null;
  payload: Record<string, unknown>;
  createdByUserId: string | null;
  createdAt: string;
}

/** In-memory tree node built from `Asset.parentAssetId`, not a persisted shape. */
export interface AssetTreeNode extends Asset {
  children: AssetTreeNode[];
}

/** Alias for call sites that only care about a single selected/flat asset. */
export type AssetNode = Asset;

export interface CreateAssetInput {
  name: string;
  nodeType: AssetNodeType;
  status?: AssetStatus;
  criticality?: AssetCriticality | null;
  parentAssetId?: string | null;
  branchId?: string | null;
  assetCategoryId?: string | null;
  code?: string | null;
  description?: string | null;
  manufacturer?: string | null;
  model?: string | null;
  serialNumber?: string | null;
  barcode?: string | null;
  purchaseDate?: string | null;
  warrantyUntil?: string | null;
  locationText?: string | null;
}

export type UpdateAssetInput = Partial<CreateAssetInput>;
