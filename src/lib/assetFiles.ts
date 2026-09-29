import { supabase } from '@/integrations/supabase/client';
import type { AssetFile, AssetFileKind, AssetFileStatus } from '@/types/assetFile';

// Fase 1 · Punto 10 — the ONLY frontend API for asset photos/documents on
// Cloudflare R2. Components use these functions; nobody else invokes the
// `asset-files` Edge Function directly.
//
// Product contract: every operation after create-upload is keyed by the
// metadata row id (`fileId`). The object key never reaches the browser and
// no R2 credential exists anywhere in the frontend. Signed URLs are
// short-lived (300 s), generated on demand and never persisted (no DB, no
// localStorage/sessionStorage).

export type { AssetFile, AssetFileKind, AssetFileStatus };

export const ASSET_FILE_ALLOWED_MIME_TYPES: Record<AssetFileKind, readonly string[]> = {
  photo: ['image/jpeg', 'image/png', 'image/webp'],
  document: ['application/pdf'],
};

export const ASSET_FILE_MAX_SIZE_BYTES: Record<AssetFileKind, number> = {
  photo: 10 * 1024 * 1024,
  document: 25 * 1024 * 1024,
};

/** `accept` attribute for the file inputs of each kind. */
export const ASSET_FILE_ACCEPT: Record<AssetFileKind, string> = {
  photo: ASSET_FILE_ALLOWED_MIME_TYPES.photo.join(','),
  document: ASSET_FILE_ALLOWED_MIME_TYPES.document.join(','),
};

/** Early UI validation before anything is requested. The backend re-checks
 * everything (declared type/size at create-upload, and the REAL size, type
 * and magic bytes at confirm-upload). Returns an error message or null. */
export function validateAssetFileForUpload(kind: AssetFileKind, file: File): string | null {
  if (!ASSET_FILE_ALLOWED_MIME_TYPES[kind].includes(file.type)) {
    return kind === 'photo'
      ? 'Formato no permitido. Usa una imagen JPG, PNG o WEBP.'
      : 'Formato no permitido. Solo se aceptan documentos PDF.';
  }
  if (file.size <= 0) return 'El archivo está vacío.';
  if (file.size > ASSET_FILE_MAX_SIZE_BYTES[kind]) {
    return kind === 'photo' ? 'La foto supera el máximo de 10 MB.' : 'El documento supera el máximo de 25 MB.';
  }
  return null;
}

/** Visible name for a file: its original name, trimmed and capped, without
 * control characters. Only metadata — never the object key. */
export function assetFileDisplayName(file: File): string {
  // eslint-disable-next-line no-control-regex
  const name = file.name.replace(/[\u0000-\u001f\u007f-\u009f]/g, '').trim().slice(0, 255);
  return name || (file.type === 'application/pdf' ? 'documento.pdf' : 'foto');
}

export interface CreateAssetUploadInput {
  assetId: string;
  kind: AssetFileKind;
  name: string;
  contentType: string;
  sizeBytes: number;
}

export interface CreateAssetUploadResult {
  fileId: string;
  uploadUrl: string;
  expiresAt: string;
  /** Headers the PUT MUST send exactly as given (Content-Type is signed). */
  requiredHeaders: Record<string, string>;
}

export interface ConfirmAssetUploadResult {
  fileId: string;
  status: AssetFileStatus;
  isPrimary?: boolean;
}

export interface CreateAssetDownloadResult {
  downloadUrl: string;
  expiresAt: string;
}

interface AssetFilesErrorPayload {
  error?: string;
}

/** supabase-js throws a FunctionsHttpError whose `.context` is the raw
 * Response; read its JSON body ({error}). */
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

interface AssetFileRow {
  id: string;
  kind: string;
  name: string;
  content_type: string | null;
  size_bytes: number | null;
  status: string;
  is_primary: boolean;
  created_at: string;
  confirmed_at: string | null;
}

const toAssetFile = (row: AssetFileRow): AssetFile => ({
  id: row.id,
  kind: row.kind as AssetFileKind,
  name: row.name,
  contentType: row.content_type,
  sizeBytes: row.size_bytes,
  status: row.status as AssetFileStatus,
  isPrimary: row.is_primary,
  createdAt: row.created_at,
  confirmedAt: row.confirmed_at,
});

/** Minimized list (get_asset_files). Everyone with read access sees the
 * available files; users who can manage them also see pending/failed/
 * deleting ones. */
export async function listAssetFiles(assetId: string): Promise<AssetFile[]> {
  const { data, error } = await supabase.rpc('get_asset_files', { p_asset_id: assetId });
  if (error) throw error;
  return (data ?? []).map(toAssetFile);
}

/** Step 1: authorizes the asset for write, creates the `pending` metadata
 * row and returns a 300 s presigned PUT. The key is generated server-side. */
export async function createAssetUpload(input: CreateAssetUploadInput): Promise<CreateAssetUploadResult> {
  const result = await invoke<{ file_id: string; upload_url: string; expires_at: string; required_headers: Record<string, string> }>(
    'create-upload',
    { asset_id: input.assetId, kind: input.kind, name: input.name, content_type: input.contentType, size_bytes: input.sizeBytes },
  );
  return { fileId: result.file_id, uploadUrl: result.upload_url, expiresAt: result.expires_at, requiredHeaders: result.required_headers };
}

/** Step 2: the browser → R2 PUT, sending EXACTLY `requiredHeaders`. */
export async function putFileToUploadUrl(uploadUrl: string, file: Blob, requiredHeaders: Record<string, string>): Promise<void> {
  const response = await fetch(uploadUrl, { method: 'PUT', headers: requiredHeaders, body: file });
  if (!response.ok) {
    throw new Error(`La subida al almacenamiento falló (HTTP ${response.status})`);
  }
}

/** Step 3: the server HEADs the real object (size, type, magic bytes) and
 * only then marks it `available`; an invalid object is deleted and the
 * file marked `failed`. */
export async function confirmAssetUpload(fileId: string): Promise<ConfirmAssetUploadResult> {
  const result = await invoke<{ file_id: string; status: AssetFileStatus; is_primary?: boolean }>('confirm-upload', { file_id: fileId });
  return { fileId: result.file_id, status: result.status, isPrimary: result.is_primary };
}

/** 300 s presigned GET for an available file. Photos render inline;
 * documents download as an attachment. Never persist the URL. */
export async function createAssetDownload(fileId: string): Promise<CreateAssetDownloadResult> {
  const result = await invoke<{ download_url: string; expires_at: string }>('create-download', { file_id: fileId });
  return { downloadUrl: result.download_url, expiresAt: result.expires_at };
}

/** Server-side delete (never a presigned DELETE). A failed storage delete
 * leaves the file `deleting` and the call can be retried. */
export async function deleteAssetFile(fileId: string): Promise<void> {
  await invoke<{ file_id: string; deleted: true }>('delete', { file_id: fileId });
}

/** Makes an available photo the asset's primary photo (atomic, server-side). */
export async function setAssetPrimaryPhoto(fileId: string): Promise<void> {
  const { error } = await supabase.rpc('set_asset_primary_photo', { p_file_id: fileId });
  if (error) throw error;
}

/** Full upload: create-upload → PUT to R2 → confirm-upload. `onStage`
 * reports real stages only (no fake percentage). */
export type AssetUploadStage = 'preparing' | 'uploading' | 'validating' | 'done';

export const UPLOAD_STAGE_LABELS: Record<AssetUploadStage, string> = {
  preparing: 'Preparando…',
  uploading: 'Subiendo…',
  validating: 'Validando…',
  done: 'Completado',
};

export async function uploadAssetFile(
  assetId: string,
  kind: AssetFileKind,
  file: File,
  onStage?: (stage: AssetUploadStage) => void,
): Promise<ConfirmAssetUploadResult> {
  onStage?.('preparing');
  const upload = await createAssetUpload({
    assetId,
    kind,
    name: assetFileDisplayName(file),
    contentType: file.type,
    sizeBytes: file.size,
  });
  onStage?.('uploading');
  await putFileToUploadUrl(upload.uploadUrl, file, upload.requiredHeaders);
  onStage?.('validating');
  const confirmed = await confirmAssetUpload(upload.fileId);
  onStage?.('done');
  return confirmed;
}
