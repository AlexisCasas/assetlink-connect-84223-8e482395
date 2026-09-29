import {
  createCallerClient,
  createServiceClient,
  errorResponse,
  getAuthenticatedUser,
  handleCors,
  isUuid,
  jsonResponse,
  requirePost,
} from '../_shared/adminAuth.ts';
import { deleteObject, getObjectRange, getR2Config, headObject, signGetUrl, signPutUrl, type R2Config } from '../_shared/r2.ts';
import {
  bytesMatchContentType,
  buildAssetFileKey,
  extensionForContentType,
  isValidAssetFileKind,
  MAGIC_BYTES_TO_READ,
  MAX_SIZE_BYTES,
  parseAssetFileKey,
  validateAssetFileDisplayName,
  type AssetFileKind,
} from '../_shared/assetFileKeys.ts';

// Fase 1 · Punto 10 — photos and documents of an asset on Cloudflare R2.
// Single Edge Function for every asset-file operation, now keyed by the
// metadata row id (`file_id`) instead of a raw object key:
//
//   create-upload   {asset_id, kind, name, content_type, size_bytes}
//                   -> pending metadata row + presigned PUT (300 s)
//   confirm-upload  {file_id}  -> real HEAD/size/type/magic bytes -> available
//   create-download {file_id}  -> presigned GET (300 s), never persisted
//   delete          {file_id}  -> deleting -> server-side R2 DELETE -> removed
//
// Authorization ALWAYS runs first, with the CALLER's own JWT
// (authorize_asset_file_access / authorize_asset_file_operation — direct
// client members and, since Punto 10, delegated Facility Managers with the
// 9C.1 assets.* matrix). The service-role client is used ONLY afterwards,
// to persist metadata the caller was just authorized to change — it never
// decides authorization. The browser never sends organization_id,
// storage_path/key or uploaded_by: all of them are derived server-side.
// See docs/ASSET_FILES_R2_PRODUCTIZATION.md.

const PUT_EXPIRES_SECONDS = 300;
const GET_EXPIRES_SECONDS = 300;

type Operation = 'read' | 'write' | 'delete';
interface HttpError { status: number; message: string }

interface FileRow {
  id: string;
  organization_id: string;
  asset_id: string;
  kind: AssetFileKind;
  name: string;
  storage_path: string;
  content_type: string;
  status: 'pending' | 'available' | 'deleting' | 'failed';
}

/** Maps the authorization RPCs' exact RAISE EXCEPTION messages to an HTTP
 * status. Never echoes anything beyond that already-safe message. */
function authorizeErrorStatus(message: string): number {
  if (message === 'Authentication is required') return 401;
  if (message === 'Asset not found' || message === 'File not found') return 404;
  if (message.includes('Not authorized')) return 403;
  if (message.includes('archived asset')) return 403;
  if (message.includes('not available')) return 403;
  return 400;
}

function toHttpError(error: { code?: string; message: string }): HttpError {
  // anon has no EXECUTE on these functions at all (Postgres 42501).
  if (error.code === '42501') return { status: 403, message: 'Not authorized' };
  return { status: authorizeErrorStatus(error.message), message: error.message };
}

/** Asset-level authorization with the caller's JWT (create-upload). */
async function authorizeAsset(req: Request, assetId: string, operation: Operation): Promise<string> {
  const caller = createCallerClient(req);
  const { data, error } = await caller.rpc('authorize_asset_file_access', { p_asset_id: assetId, p_operation: operation });
  if (error) throw toHttpError(error);
  return data as string;
}

/** File-level authorization with the caller's JWT, THEN (only then) the
 * service-role read of the row's internal fields. A missing file and a
 * file of an asset the caller cannot read both answer 404 "File not found"
 * — no cross-tenant enumeration. Cross-checks the row's organization
 * against the one the authorization resolved, and the stored object key's
 * embedded organization/asset/kind against the row itself. */
async function authorizeFile(req: Request, fileId: unknown, operation: Operation): Promise<FileRow> {
  if (!isUuid(fileId)) throw { status: 400, message: 'file_id must be a UUID' } as HttpError;
  const caller = createCallerClient(req);
  const { data: organizationId, error } = await caller.rpc('authorize_asset_file_operation', { p_file_id: fileId, p_operation: operation });
  if (error) throw toHttpError(error);

  const service = createServiceClient();
  const { data: row, error: rowError } = await service
    .from('asset_documents')
    .select('id, organization_id, asset_id, kind, name, storage_path, content_type, status')
    .eq('id', fileId)
    .maybeSingle();
  if (rowError) throw { status: 500, message: 'Could not load the file' } as HttpError;
  if (!row || !row.kind) throw { status: 404, message: 'File not found' } as HttpError;
  if (row.organization_id !== organizationId) throw { status: 403, message: 'File does not match the asset\'s organization' } as HttpError;

  let parsed;
  try {
    parsed = parseAssetFileKey(row.storage_path);
  } catch {
    throw { status: 500, message: 'Stored object key is invalid' } as HttpError;
  }
  if (parsed.organizationId !== row.organization_id || parsed.assetId !== row.asset_id || parsed.kind !== row.kind
    || extensionForContentType(row.kind, row.content_type) !== parsed.extension) {
    throw { status: 500, message: 'Stored object key does not match its metadata' } as HttpError;
  }
  return row as FileRow;
}

const fail = (error: unknown): Response => {
  const { status, message } = error as HttpError;
  if (typeof status === 'number' && typeof message === 'string') return errorResponse(message, status);
  throw error;
};

async function handleCreateUpload(req: Request, input: Record<string, unknown>, config: R2Config): Promise<Response> {
  const assetId = input.asset_id;
  const kind = input.kind;
  const contentType = input.content_type;
  const sizeBytes = input.size_bytes;

  if (!isUuid(assetId)) return errorResponse('asset_id must be a UUID');
  if (!isValidAssetFileKind(kind)) return errorResponse('kind must be "photo" or "document"');
  const name = validateAssetFileDisplayName(input.name);
  if (!name) return errorResponse('name must be a non-empty string of at most 255 characters without control characters');
  if (typeof contentType !== 'string') return errorResponse('content_type is required');
  if (typeof sizeBytes !== 'number' || !Number.isFinite(sizeBytes) || sizeBytes <= 0) {
    return errorResponse('size_bytes must be a positive number');
  }
  try {
    extensionForContentType(kind, contentType);
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : 'Invalid content_type', 400);
  }
  const limit = MAX_SIZE_BYTES[kind];
  if (sizeBytes > limit) {
    // Early, client-declared rejection only; confirm-upload re-checks the
    // REAL Content-Length that R2 reports.
    return errorResponse(`size_bytes exceeds the ${limit} byte limit for kind "${kind}"`, 400);
  }

  let organizationId: string;
  try {
    organizationId = await authorizeAsset(req, assetId, 'write');
  } catch (error) {
    return fail(error);
  }
  // Authorized: now (and only now) persist, as the real caller.
  const user = await getAuthenticatedUser(req);
  const key = buildAssetFileKey(organizationId, assetId, kind, contentType);
  const service = createServiceClient();
  const { data: row, error: insertError } = await service
    .from('asset_documents')
    .insert({
      organization_id: organizationId,
      asset_id: assetId,
      kind,
      name,
      storage_path: key,
      content_type: contentType,
      status: 'pending',
      uploaded_by_user_id: user.id,
    })
    .select('id')
    .single();
  if (insertError || !row) {
    console.error('asset-files: could not create the pending file row', insertError?.code ?? 'unknown');
    return errorResponse('Could not prepare the upload', 500);
  }

  let uploadUrl: string;
  try {
    uploadUrl = await signPutUrl(config, key, contentType, PUT_EXPIRES_SECONDS);
  } catch (error) {
    // Failure mode A: authorized + pending row, but signing failed in this
    // same request => the row is closed as failed (nothing was uploaded).
    await service.rpc('asset_file_mark_failed', { p_file_id: row.id });
    console.error('asset-files: signing failed', error instanceof Error ? error.message : 'unknown');
    return errorResponse('Could not prepare the upload', 500);
  }

  return jsonResponse({
    file_id: row.id,
    upload_url: uploadUrl,
    expires_at: new Date(Date.now() + PUT_EXPIRES_SECONDS * 1000).toISOString(),
    required_headers: { 'Content-Type': contentType },
  }, 201);
}

async function handleConfirmUpload(req: Request, input: Record<string, unknown>, config: R2Config): Promise<Response> {
  let file: FileRow;
  try {
    file = await authorizeFile(req, input.file_id, 'write');
  } catch (error) {
    return fail(error);
  }
  const service = createServiceClient();
  if (file.status === 'available') {
    return jsonResponse({ file_id: file.id, status: 'available' });
  }
  if (file.status !== 'pending') {
    return errorResponse(`Only a pending file can be confirmed (status: ${file.status})`, 409);
  }

  const head = await headObject(config, file.storage_path);
  if (!head.exists) {
    // Failure modes B/C: the PUT URL was never used (or not yet). The row
    // stays pending — never available without a real object.
    return errorResponse('Nothing was uploaded for this file yet', 404);
  }

  const reject = async (message: string): Promise<Response> => {
    // Failure mode D: never leave an invalid object under a legitimate key.
    await deleteObject(config, file.storage_path);
    await service.rpc('asset_file_mark_failed', { p_file_id: file.id });
    return errorResponse(message, 422);
  };

  const limit = MAX_SIZE_BYTES[file.kind];
  if (head.contentLength <= 0 || head.contentLength > limit) {
    return await reject(`Uploaded file size (${head.contentLength} bytes) is invalid for kind "${file.kind}" (limit ${limit} bytes)`);
  }
  if (head.contentType !== file.content_type) {
    return await reject('Uploaded file Content-Type does not match the upload intent');
  }
  const bytes = await getObjectRange(config, file.storage_path, MAGIC_BYTES_TO_READ);
  if (!bytesMatchContentType(file.content_type, bytes)) {
    return await reject('Uploaded file content does not match its declared type (magic bytes mismatch)');
  }

  const { data: saved, error } = await service.rpc('asset_file_mark_available', {
    p_file_id: file.id,
    p_size_bytes: head.contentLength,
    p_content_type: file.content_type,
    p_etag: head.etag,
  });
  if (error || !saved) {
    // Failure mode E: validated in R2 but the DB update failed. The row is
    // still pending (never a false "available"); confirm-upload is
    // idempotent and can simply be retried against the same object.
    console.error('asset-files: could not mark the file available', error?.code ?? 'unknown');
    return errorResponse('Could not confirm the upload, please retry', 500);
  }
  return jsonResponse({
    file_id: file.id,
    status: 'available',
    size_bytes: head.contentLength,
    content_type: file.content_type,
    is_primary: (saved as { is_primary: boolean }).is_primary,
  });
}

/** Safe `filename` for Content-Disposition: the display name reduced to a
 * conservative ASCII set, with the real extension. Never trusted as a key. */
const attachmentFilename = (name: string, extension: string): string => {
  const base = name.replace(/\.[A-Za-z0-9]{1,5}$/, '').normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^A-Za-z0-9._ -]+/g, '_').trim().slice(0, 120) || 'documento';
  return `${base}.${extension}`;
};

async function handleCreateDownload(req: Request, input: Record<string, unknown>, config: R2Config): Promise<Response> {
  let file: FileRow;
  try {
    file = await authorizeFile(req, input.file_id, 'read');
  } catch (error) {
    return fail(error);
  }
  if (file.status !== 'available') return errorResponse('File is not available', 409);

  const extension = extensionForContentType(file.kind, file.content_type);
  // Photos render inline (gallery); documents always download.
  const disposition = file.kind === 'photo' ? 'inline' : `attachment; filename="${attachmentFilename(file.name, extension)}"`;
  const downloadUrl = await signGetUrl(config, file.storage_path, GET_EXPIRES_SECONDS, file.content_type, disposition);
  return jsonResponse({
    download_url: downloadUrl,
    expires_at: new Date(Date.now() + GET_EXPIRES_SECONDS * 1000).toISOString(),
  });
}

async function handleDelete(req: Request, input: Record<string, unknown>, config: R2Config): Promise<Response> {
  let file: FileRow;
  try {
    file = await authorizeFile(req, input.file_id, 'delete');
  } catch (error) {
    return fail(error);
  }
  const service = createServiceClient();
  // deleting: out of the gallery, primary moved to the oldest remaining
  // photo, and retryable if R2 fails below.
  const { error: beginError } = await service.rpc('asset_file_begin_delete', { p_file_id: file.id });
  if (beginError) return errorResponse('Could not delete the file', 500);

  try {
    // Server-side, never presigned; idempotent (a missing object is fine).
    await deleteObject(config, file.storage_path);
  } catch (error) {
    // Failure mode F: the row stays `deleting` — reconcilable/retryable.
    console.error('asset-files: R2 delete failed', error instanceof Error ? error.message : 'unknown');
    return errorResponse('Storage delete failed; the file is marked for deletion and can be retried', 502);
  }

  const { error: finishError } = await service.rpc('asset_file_finish_delete', { p_file_id: file.id });
  if (finishError) return errorResponse('The file was removed from storage but its record could not be closed; retry the delete', 500);
  return jsonResponse({ file_id: file.id, deleted: true });
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    requirePost(req);
    const input = await req.json();
    const action = input?.action;

    let config: R2Config;
    try {
      config = getR2Config();
    } catch (error) {
      // Fail closed; never logs the secret values, only which one failed.
      console.error('asset-files: R2 configuration error:', error instanceof Error ? error.message : error);
      return errorResponse('Storage is not configured', 500);
    }

    switch (action) {
      case 'create-upload': return await handleCreateUpload(req, input, config);
      case 'confirm-upload': return await handleConfirmUpload(req, input, config);
      case 'create-download': return await handleCreateDownload(req, input, config);
      case 'delete': return await handleDelete(req, input, config);
      default: return errorResponse('Invalid action');
    }
  } catch (error) {
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('asset-files failed', error instanceof Error ? error.message : 'unknown');
    return errorResponse('Internal server error', 500);
  }
});
