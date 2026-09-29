// Object key convention for asset files on R2 (Fase 1 · Punto 7 — R2
// Foundation). Keys are ALWAYS generated server-side (buildAssetFileKey) —
// the browser only ever sends asset_id/kind/name/content_type/size, never a
// key. Since Punto 10 every other action (confirm-upload, create-download,
// delete) is keyed by the metadata row id: the key is read server-side from
// asset_documents.storage_path and STILL runs through parseAssetFileKey
// (cross-checked against the row) before touching R2: the
// regexes below are fully anchored (^...$), built from a strict UUID
// pattern and a closed kind/extension set, so no path-traversal segment,
// percent-encoding, extra path segment, or mismatched kind/extension
// combination (e.g. "photos/<uuid>.pdf") can ever parse successfully.

export type AssetFileKind = 'photo' | 'document';

const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const UUID_RE = new RegExp(`^${UUID}$`);

// Kept as two separate, fully-closed patterns (not one pattern with a
// shared extension group) so a photo key can never end in .pdf and a
// document key can never end in .jpg/.png/.webp — the shape of the key
// itself enforces the kind/extension pairing, on top of the MIME
// allowlist enforced when the key is built.
const PHOTO_KEY_RE = new RegExp(`^organizations/(${UUID})/assets/(${UUID})/photos/(${UUID})\\.(jpg|png|webp)$`);
const DOCUMENT_KEY_RE = new RegExp(`^organizations/(${UUID})/assets/(${UUID})/documents/(${UUID})\\.(pdf)$`);

export const PHOTO_MIME_TO_EXTENSION: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

export const DOCUMENT_MIME_TO_EXTENSION: Record<string, string> = {
  'application/pdf': 'pdf',
};

/** Maximum accepted upload size, in bytes, per kind. Enforced twice: as an
 * early rejection in create-upload against the client-declared size, and
 * — the actual control — against R2's own real Content-Length in
 * confirm-upload's HEAD. */
export const MAX_SIZE_BYTES: Record<AssetFileKind, number> = {
  photo: 10 * 1024 * 1024,
  document: 25 * 1024 * 1024,
};

/** The allowed Content-Type set for `kind`, and the file extension a valid
 * value maps to. Throws (never silently falls back) for anything outside
 * the allowlist — no SVG, no HTML, no JS, no Office formats in this
 * phase. */
export const extensionForContentType = (kind: AssetFileKind, contentType: string): string => {
  const table = kind === 'photo' ? PHOTO_MIME_TO_EXTENSION : DOCUMENT_MIME_TO_EXTENSION;
  const extension = table[contentType];
  if (!extension) {
    throw new Error(`Content-Type "${contentType}" is not allowed for kind "${kind}"`);
  }
  return extension;
};

export const isValidAssetFileKind = (value: unknown): value is AssetFileKind => value === 'photo' || value === 'document';

/** Builds a brand-new object key server-side. Never accepts anything from
 * the client except the three inputs that decide its shape — the uuid
 * segment is always freshly generated here with crypto.randomUUID(). */
export const buildAssetFileKey = (
  organizationId: string,
  assetId: string,
  kind: AssetFileKind,
  contentType: string,
): string => {
  if (!UUID_RE.test(organizationId) || !UUID_RE.test(assetId)) {
    throw new Error('organization_id/asset_id must be UUIDs');
  }
  const extension = extensionForContentType(kind, contentType);
  const segment = kind === 'photo' ? 'photos' : 'documents';
  const id = crypto.randomUUID();
  return `organizations/${organizationId}/assets/${assetId}/${segment}/${id}.${extension}`;
};

export interface ParsedAssetFileKey {
  organizationId: string;
  assetId: string;
  kind: AssetFileKind;
  id: string;
  extension: string;
}

/** The single point every action other than create-upload MUST call
 * before doing anything with a client-supplied key. Rejects (throws) on
 * anything that is not EXACTLY the shape this module generates — including
 * "..", "%2e", extra "/" segments, uppercase hex, a kind/extension
 * mismatch, or a non-v4-shaped uuid. Parsing success alone is NEVER
 * authorization: callers still must check the returned organizationId/
 * assetId against authorize_asset_file_access's own result. */
export const parseAssetFileKey = (key: string): ParsedAssetFileKey => {
  if (typeof key !== 'string' || key.length === 0 || key.length > 512) {
    throw new Error('Invalid object key');
  }
  // Defense in depth ahead of the regex match below: an anchored regex
  // built from closed character classes cannot match a traversal/percent-
  // encoded/double-slash payload anyway, but failing on it explicitly
  // keeps the reason legible instead of a generic "no match".
  if (key.includes('..') || key.includes('%') || key.includes('//') || key !== key.trim()) {
    throw new Error('Invalid object key');
  }

  const photoMatch = key.match(PHOTO_KEY_RE);
  if (photoMatch) {
    return { organizationId: photoMatch[1], assetId: photoMatch[2], kind: 'photo', id: photoMatch[3], extension: photoMatch[4] };
  }
  const documentMatch = key.match(DOCUMENT_KEY_RE);
  if (documentMatch) {
    return { organizationId: documentMatch[1], assetId: documentMatch[2], kind: 'document', id: documentMatch[3], extension: documentMatch[4] };
  }
  throw new Error('Invalid object key');
};

/** Bytes needed from a ranged GET to check every supported format's magic
 * number (WEBP's is the longest: "RIFF" + 4-byte size + "WEBP" = 12). */
export const MAGIC_BYTES_TO_READ = 16;

const startsWith = (bytes: Uint8Array, signature: number[], offset = 0): boolean =>
  signature.every((byte, index) => bytes[offset + index] === byte);

/** Confirms the object's REAL bytes match its claimed Content-Type — a
 * signed PUT's Content-Type header is enforced by R2's signature, but
 * nothing stops a client from lying about what bytes it actually sends
 * behind that header. Never trusts the extension or the stored
 * Content-Type alone. */
export const bytesMatchContentType = (contentType: string, bytes: Uint8Array): boolean => {
  switch (contentType) {
    case 'image/jpeg':
      return startsWith(bytes, [0xff, 0xd8, 0xff]);
    case 'image/png':
      return startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case 'image/webp':
      return startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && startsWith(bytes, [0x57, 0x45, 0x42, 0x50], 8);
    case 'application/pdf':
      return startsWith(bytes, [0x25, 0x50, 0x44, 0x46, 0x2d]); // "%PDF-"
    default:
      return false;
  }
};

/** Maximum length of a file's visible name (metadata only). */
export const MAX_DISPLAY_NAME_LENGTH = 255;

/** Validates the human-visible file name sent at create-upload (Punto 10).
 * It is ONLY metadata shown in the UI — never part of the object key, which
 * stays a server-generated UUID. Returns the trimmed name, or null when it
 * is not a string, is empty after trimming, is longer than 255 characters,
 * or contains control characters (C0/C1, including newlines and tabs). */
export const validateAssetFileDisplayName = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const name = value.trim();
  if (name.length === 0 || name.length > MAX_DISPLAY_NAME_LENGTH) return null;
  // deno-lint-ignore no-control-regex
  if (/[\u0000-\u001f\u007f-\u009f]/.test(name)) return null; // eslint-disable-line no-control-regex
  return name;
};
