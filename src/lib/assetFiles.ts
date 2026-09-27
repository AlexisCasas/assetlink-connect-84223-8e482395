import { supabase } from '@/integrations/supabase/client';

// Fase 1 · Punto 7 — Cloudflare R2 Foundation. Thin, typed client for the
// `asset-files` Edge Function. Deliberately NO UI here — this file only
// fixes the contract Fase 1 · Punto 10 (photos/documents UI) will build on.
// No R2 credential of any kind exists in this file, or reaches the
// browser at all: every call below returns either a short-lived signed
// URL or a plain confirmation object.

export type AssetFileKind = 'photo' | 'document';

export const ASSET_FILE_ALLOWED_MIME_TYPES: Record<AssetFileKind, readonly string[]> = {
  photo: ['image/jpeg', 'image/png', 'image/webp'],
  document: ['application/pdf'],
};

export const ASSET_FILE_MAX_SIZE_BYTES: Record<AssetFileKind, number> = {
  photo: 10 * 1024 * 1024,
  document: 25 * 1024 * 1024,
};

export interface CreateAssetUploadInput {
  assetId: string;
  kind: AssetFileKind;
  contentType: string;
  sizeBytes: number;
}

export interface CreateAssetUploadResult {
  key: string;
  uploadUrl: string;
  expiresAt: string;
  /** Headers the browser's PUT to `uploadUrl` MUST send exactly as given —
   * Content-Type is part of the signature, so any other value (or a
   * missing header) makes R2 reject the upload with 403. */
  requiredHeaders: Record<string, string>;
}

export interface ConfirmAssetUploadResult {
  key: string;
  sizeBytes: number;
  contentType: string;
  etag: string | null;
}

export interface CreateAssetDownloadResult {
  downloadUrl: string;
  expiresAt: string;
}

export interface DeleteAssetFileResult {
  key: string;
  deleted: true;
}

interface AssetFilesErrorPayload {
  error?: string;
}

/** supabase-js throws a FunctionsHttpError whose `.context` is the raw
 * Response; this reads its JSON body ({error}) rather than assuming a
 * specific supabase-js version's error shape — same pattern already used
 * for send-organization-invitation. */
async function readErrorPayload(error: unknown): Promise<AssetFilesErrorPayload | null> {
  const context = (error as { context?: unknown } | null)?.context;
  if (!context || typeof (context as Response).json !== 'function') return null;
  try {
    return await (context as Response).json() as AssetFilesErrorPayload;
  } catch {
    return null;
  }
}

async function invoke<T>(action: string, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('asset-files', { body: { action, ...body } });
  if (error) {
    const payload = await readErrorPayload(error);
    throw new Error(payload?.error ?? error.message);
  }
  return data as T;
}

/** Step 1: authorizes `assetId` for write, then returns a key generated
 * entirely server-side plus a 300s presigned PUT URL for it. The browser
 * never chooses or sends a key. */
export async function createAssetUpload(input: CreateAssetUploadInput): Promise<CreateAssetUploadResult> {
  const result = await invoke<{ key: string; upload_url: string; expires_at: string; required_headers: Record<string, string> }>(
    'create-upload',
    { asset_id: input.assetId, kind: input.kind, content_type: input.contentType, size_bytes: input.sizeBytes },
  );
  return { key: result.key, uploadUrl: result.upload_url, expiresAt: result.expires_at, requiredHeaders: result.required_headers };
}

/** Performs the actual browser → R2 PUT. Sends EXACTLY `requiredHeaders`
 * from createAssetUpload's result — nothing added, nothing dropped —
 * since that header set is part of what was signed. */
export async function putFileToUploadUrl(uploadUrl: string, file: Blob, requiredHeaders: Record<string, string>): Promise<void> {
  const response = await fetch(uploadUrl, { method: 'PUT', headers: requiredHeaders, body: file });
  if (!response.ok) {
    throw new Error(`Upload to storage failed (HTTP ${response.status})`);
  }
}

/** Step 2: the PUT succeeding proves nothing about what actually landed in
 * R2 — this asks the server to HEAD the real object, check its real size/
 * Content-Type, and check its real magic bytes, deleting it if any of
 * those checks fail. Never writes anything to the app database (Fase 1 ·
 * Punto 10's job) — this phase is foundation only. */
export async function confirmAssetUpload(key: string): Promise<ConfirmAssetUploadResult> {
  const result = await invoke<{ key: string; size_bytes: number; content_type: string; etag: string | null }>(
    'confirm-upload',
    { key },
  );
  return { key: result.key, sizeBytes: result.size_bytes, contentType: result.content_type, etag: result.etag };
}

/** Authorizes `key` for read (re-deriving its asset from the key itself,
 * cross-checked against the database) and returns a 300s presigned GET
 * URL. Never persisted — always generated on demand. */
export async function createAssetDownload(key: string): Promise<CreateAssetDownloadResult> {
  const result = await invoke<{ download_url: string; expires_at: string }>('create-download', { key });
  return { downloadUrl: result.download_url, expiresAt: result.expires_at };
}

/** Authorizes `key` for delete and removes it from R2 server-side — never
 * a presigned DELETE URL (that would be a bearer-token capability to
 * destroy data). Idempotent: deleting an already-deleted key succeeds. */
export async function deleteAssetFile(key: string): Promise<DeleteAssetFileResult> {
  return invoke<DeleteAssetFileResult>('delete', { key });
}
