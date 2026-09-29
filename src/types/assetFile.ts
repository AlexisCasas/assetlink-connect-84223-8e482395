// Fase 1 · Punto 10 — photos and documents of an asset (Cloudflare R2).

export type AssetFileKind = 'photo' | 'document';

/** pending: upload prepared, not yet confirmed. available: confirmed against
 * the real object in R2. deleting: removal in progress (retryable).
 * failed: the upload never became valid. Only `available` files are shown
 * as usable; managers also see the operational states. */
export type AssetFileStatus = 'pending' | 'available' | 'deleting' | 'failed';

/** Minimized metadata from get_asset_files: never the object key, a URL,
 * the uploader id or the organization. */
export interface AssetFile {
  id: string;
  kind: AssetFileKind;
  name: string;
  contentType: string | null;
  sizeBytes: number | null;
  status: AssetFileStatus;
  isPrimary: boolean;
  createdAt: string;
  confirmedAt: string | null;
}
