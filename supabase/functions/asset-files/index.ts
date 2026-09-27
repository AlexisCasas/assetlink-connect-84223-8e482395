import { createCallerClient, errorResponse, handleCors, isUuid, jsonResponse, requirePost } from '../_shared/adminAuth.ts';
import { deleteObject, getObjectRange, getR2Config, headObject, signGetUrl, signPutUrl, type R2Config } from '../_shared/r2.ts';
import {
  bytesMatchContentType,
  buildAssetFileKey,
  DOCUMENT_MIME_TO_EXTENSION,
  extensionForContentType,
  isValidAssetFileKind,
  MAGIC_BYTES_TO_READ,
  MAX_SIZE_BYTES,
  parseAssetFileKey,
  PHOTO_MIME_TO_EXTENSION,
  type AssetFileKind,
} from '../_shared/assetFileKeys.ts';

// Fase 1 · Punto 7 — Cloudflare R2 Foundation. Single Edge Function for
// every asset-file operation (create-upload / confirm-upload /
// create-download / delete): one place to audit for the authorization +
// key-parsing + R2 config concerns every action shares, instead of four
// functions that could each get that wrong independently. No UI consumes
// this yet — that is Fase 1 · Punto 10. See docs/R2_FOUNDATION.md.
//
// Every action's very first authorization step runs
// authorize_asset_file_access with the CALLER's own JWT (never
// service_role) — same pattern as Fase 1 · Punto 6B — so tenant/role
// authorization lives exactly once, in SQL, and is exercised by pgTAP
// independent of this file.

const PUT_EXPIRES_SECONDS = 300;
const GET_EXPIRES_SECONDS = 300;

const EXTENSION_TO_CONTENT_TYPE: Record<string, string> = {
  ...Object.fromEntries(Object.entries(PHOTO_MIME_TO_EXTENSION).map(([mime, ext]) => [ext, mime])),
  ...Object.fromEntries(Object.entries(DOCUMENT_MIME_TO_EXTENSION).map(([mime, ext]) => [ext, mime])),
};

/** Maps authorize_asset_file_access's exact RAISE EXCEPTION messages
 * (supabase/migrations/20260927012526_asset_file_access_authorization.sql)
 * to an HTTP status. Never echoes internal detail beyond that message —
 * it is already written to be safe to show the caller. */
function authorizeErrorStatus(message: string): number {
  if (message === 'Authentication is required') return 401;
  if (message === 'Asset not found') return 404;
  if (message.includes('Not authorized')) return 403;
  if (message.includes('archived asset')) return 403;
  if (message.includes('not available')) return 403;
  return 400;
}

/** Runs authorize_asset_file_access with the caller's own JWT. Throws an
 * object with {status, message} — never the raw Postgres error — so the
 * caller can jsonResponse it directly without leaking anything beyond the
 * RPC's own already-safe message.
 *
 * `anon` has no EXECUTE grant on this function at all (verified: calling
 * it as anon fails with Postgres code 42501, "permission denied for
 * function...", not one of the RAISE EXCEPTION messages above) — that is
 * mapped straight to 403 rather than falling through to the generic 400,
 * since it is a real authorization rejection, not a malformed request. */
async function authorize(req: Request, assetId: string, operation: 'read' | 'write' | 'delete'): Promise<string> {
  const caller = createCallerClient(req);
  const { data, error } = await caller.rpc('authorize_asset_file_access', { p_asset_id: assetId, p_operation: operation });
  if (error) {
    const status = error.code === '42501' ? 403 : authorizeErrorStatus(error.message);
    throw { status, message: status === 403 && error.code === '42501' ? 'Not authorized' : error.message };
  }
  return data as string;
}

/** Every non-create-upload action receives a key from the client. This
 * parses it (rejecting anything not exactly the shape this module
 * generates) AND cross-checks its embedded organization_id against what
 * authorize_asset_file_access actually resolved for the asset_id embedded
 * in that SAME key — the defense against a key whose org segment was
 * edited to point at a different tenant while keeping a real asset uuid
 * from elsewhere. Returns the parsed key. */
async function parseAndAuthorize(req: Request, key: unknown, operation: 'read' | 'write' | 'delete') {
  if (typeof key !== 'string') throw { status: 400, message: 'key is required' };
  let parsed;
  try {
    parsed = parseAssetFileKey(key);
  } catch {
    throw { status: 400, message: 'Invalid object key' };
  }
  const organizationId = await authorize(req, parsed.assetId, operation);
  if (organizationId !== parsed.organizationId) {
    // The asset is real and the caller may be authorized for it, but the
    // key's own organization segment does not match — never trust the
    // path over the database.
    throw { status: 403, message: 'Object key does not match the asset\'s organization' };
  }
  return parsed;
}

async function handleCreateUpload(req: Request, input: Record<string, unknown>, config: R2Config): Promise<Response> {
  const assetId = input.asset_id;
  const kind = input.kind;
  const contentType = input.content_type;
  const sizeBytes = input.size_bytes;

  if (!isUuid(assetId)) return errorResponse('asset_id must be a UUID');
  if (!isValidAssetFileKind(kind)) return errorResponse('kind must be "photo" or "document"');
  if (typeof contentType !== 'string') return errorResponse('content_type is required');
  if (typeof sizeBytes !== 'number' || !Number.isFinite(sizeBytes) || sizeBytes <= 0) {
    return errorResponse('size_bytes must be a positive number');
  }

  try {
    // Only validated here for its side effect (throws on any Content-Type
    // outside the kind's allowlist) — buildAssetFileKey below re-derives
    // the extension itself once we actually have an authorized
    // organization_id to build the key against.
    extensionForContentType(kind, contentType);
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : 'Invalid content_type', 400);
  }

  const limit = MAX_SIZE_BYTES[kind as AssetFileKind];
  if (sizeBytes > limit) {
    // Only an early, client-declared rejection — not the real control.
    // confirm-upload re-checks against R2's own reported Content-Length.
    return errorResponse(`size_bytes exceeds the ${limit} byte limit for kind "${kind}"`, 400);
  }

  let organizationId: string;
  try {
    organizationId = await authorize(req, assetId, 'write');
  } catch (error) {
    const { status, message } = error as { status: number; message: string };
    return errorResponse(message, status);
  }

  const key = buildAssetFileKey(organizationId, assetId, kind as AssetFileKind, contentType);
  const uploadUrl = await signPutUrl(config, key, contentType, PUT_EXPIRES_SECONDS);

  return jsonResponse({
    key,
    upload_url: uploadUrl,
    expires_at: new Date(Date.now() + PUT_EXPIRES_SECONDS * 1000).toISOString(),
    required_headers: { 'Content-Type': contentType },
  }, 201);
}

async function handleConfirmUpload(req: Request, input: Record<string, unknown>, config: R2Config): Promise<Response> {
  let parsed;
  try {
    parsed = await parseAndAuthorize(req, input.key, 'write');
  } catch (error) {
    const { status, message } = error as { status: number; message: string };
    return errorResponse(message, status);
  }

  const key = input.key as string;
  const expectedContentType = EXTENSION_TO_CONTENT_TYPE[parsed.extension];
  const limit = MAX_SIZE_BYTES[parsed.kind];

  const head = await headObject(config, key);
  if (!head.exists) {
    // A PUT URL was issued but nothing was ever uploaded to it (or it
    // expired first) — not an inconsistency, just nothing to confirm yet.
    return errorResponse('Object not found: nothing was uploaded to this key yet', 404);
  }

  const reject = async (message: string): Promise<Response> => {
    // Never leave a half-valid object under a key that looks legitimate —
    // confirm-upload is the only gate before a key would ever be trusted
    // (e.g. persisted) by a future caller.
    await deleteObject(config, key);
    return errorResponse(message, 422);
  };

  if (head.contentLength <= 0 || head.contentLength > limit) {
    return await reject(`Uploaded object size (${head.contentLength} bytes) is invalid for kind "${parsed.kind}" (limit ${limit} bytes)`);
  }
  if (head.contentType !== expectedContentType) {
    return await reject(`Uploaded object Content-Type ("${head.contentType}") does not match the key's extension`);
  }

  const bytes = await getObjectRange(config, key, MAGIC_BYTES_TO_READ);
  if (!bytesMatchContentType(expectedContentType, bytes)) {
    return await reject('Uploaded object content does not match its declared Content-Type (magic bytes mismatch)');
  }

  return jsonResponse({
    key,
    size_bytes: head.contentLength,
    content_type: expectedContentType,
    etag: head.etag,
  });
}

async function handleCreateDownload(req: Request, input: Record<string, unknown>, config: R2Config): Promise<Response> {
  let parsed;
  try {
    parsed = await parseAndAuthorize(req, input.key, 'read');
  } catch (error) {
    const { status, message } = error as { status: number; message: string };
    return errorResponse(message, status);
  }

  const key = input.key as string;
  const contentType = EXTENSION_TO_CONTENT_TYPE[parsed.extension];
  // Photos render inline (asset galleries in Punto 10); documents always
  // download — never render a PDF inline from an unfamiliar origin.
  const disposition = parsed.kind === 'photo' ? 'inline' : `attachment; filename="${parsed.id}.${parsed.extension}"`;
  const downloadUrl = await signGetUrl(config, key, GET_EXPIRES_SECONDS, contentType, disposition);

  return jsonResponse({
    download_url: downloadUrl,
    expires_at: new Date(Date.now() + GET_EXPIRES_SECONDS * 1000).toISOString(),
  });
}

async function handleDelete(req: Request, input: Record<string, unknown>, config: R2Config): Promise<Response> {
  try {
    await parseAndAuthorize(req, input.key, 'delete');
  } catch (error) {
    const { status, message } = error as { status: number; message: string };
    return errorResponse(message, status);
  }

  await deleteObject(config, input.key as string);
  return jsonResponse({ key: input.key, deleted: true });
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    requirePost(req);
    const input = await req.json();
    const action = input.action;

    let config: R2Config;
    try {
      config = getR2Config();
    } catch (error) {
      // Fail closed: never a fallback origin/bucket, never logs the
      // secrets themselves — only which one is missing/invalid.
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
    console.error('asset-files failed', error instanceof Error ? error.message : error);
    return errorResponse('Internal server error', 500);
  }
});
