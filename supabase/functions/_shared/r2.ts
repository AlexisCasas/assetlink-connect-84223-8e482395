import { AwsClient } from 'npm:aws4fetch@1.0.20';

// Cloudflare R2 access, server-side only. Credentials never leave this
// module: every caller gets a signed URL, a Response, or a plain object —
// never the AwsClient/config itself. Nothing here ever logs a secret value
// or a signed URL (a signed URL IS a bearer credential until it expires).

export interface R2Config {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucketName: string;
  /** https://<accountId>.r2.cloudflarestorage.com — path-style, no trailing slash. */
  endpoint: string;
}

const ACCOUNT_ID_RE = /^[0-9a-f]{32}$/;
// S3/R2 bucket naming: lowercase letters, digits, hyphens or dots, 3-63
// chars, must start and end with a letter or digit.
const BUCKET_NAME_RE = /^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/;

// Exact .env.example placeholder values. R2_ACCOUNT_ID's and
// R2_BUCKET_NAME's placeholders happen to be syntactically valid-shaped
// (a real 32-hex string would look nothing like "your-r2-account-id", but
// "your-r2-bucket-name" and "your-r2-access-key-id" are, respectively, a
// syntactically legal bucket name and long enough to pass the access-key
// length heuristic below) — format validation alone does not catch them,
// so every value is also checked against this exact list.
const KNOWN_PLACEHOLDER_VALUES = new Set([
  'your-r2-account-id',
  'your-r2-access-key-id',
  'your-r2-secret-access-key',
  'your-r2-bucket-name',
]);

const required = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required Edge Function secret: ${name}`);
  if (KNOWN_PLACEHOLDER_VALUES.has(value)) {
    throw new Error(`${name} is still set to its .env.example placeholder value`);
  }
  return value;
};

/** Fails closed: throws (naming only the variable, never its value) if any
 * of the four R2 secrets is missing, still the literal .env.example
 * placeholder, or fails a basic format check. Access/secret key checks are
 * a heuristic sanity check (minimum length, no whitespace) — R2 does not
 * publish a guaranteed key format, so this cannot be a hard format
 * contract, only a guard against an obviously wrong or empty value
 * slipping through. */
export const getR2Config = (): R2Config => {
  const accountId = required('R2_ACCOUNT_ID');
  const accessKeyId = required('R2_ACCESS_KEY_ID');
  const secretAccessKey = required('R2_SECRET_ACCESS_KEY');
  const bucketName = required('R2_BUCKET_NAME');

  if (!ACCOUNT_ID_RE.test(accountId)) {
    throw new Error('R2_ACCOUNT_ID is not a valid Cloudflare account id (expected 32 hex characters)');
  }
  if (!BUCKET_NAME_RE.test(bucketName)) {
    throw new Error('R2_BUCKET_NAME is not a valid bucket name');
  }
  if (/\s/.test(accessKeyId) || accessKeyId.length < 16) {
    throw new Error('R2_ACCESS_KEY_ID does not look like a valid access key');
  }
  if (/\s/.test(secretAccessKey) || secretAccessKey.length < 32) {
    throw new Error('R2_SECRET_ACCESS_KEY does not look like a valid secret key');
  }

  return {
    accountId,
    accessKeyId,
    secretAccessKey,
    bucketName,
    endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
  };
};

const createClient = (config: R2Config): AwsClient => new AwsClient({
  accessKeyId: config.accessKeyId,
  secretAccessKey: config.secretAccessKey,
  service: 's3',
  region: 'auto',
});

const objectUrl = (config: R2Config, key: string): string =>
  `${config.endpoint}/${config.bucketName}/${key.split('/').map(encodeURIComponent).join('/')}`;

/** Presigned PUT — Content-Type is part of the signed request, so R2
 * rejects (403/SignatureDoesNotMatch) an upload sent with any other
 * Content-Type than the one authorized here.
 *
 * `allHeaders: true` is NOT optional here: aws4fetch's default query
 * signing (`signQuery: true` alone) only signs the `host` header —
 * verified empirically against real R2 (`X-Amz-SignedHeaders=host`), which
 * meant a PUT with a DIFFERENT Content-Type than the one requested at
 * create-upload was silently accepted (200), contradicting Cloudflare's
 * own presigned-URL documentation. With `allHeaders: true`,
 * `X-Amz-SignedHeaders` becomes `content-type;host` and a mismatched
 * Content-Type is rejected by R2 itself with 403/SignatureDoesNotMatch —
 * confirmed against real R2. confirm-upload's own Content-Type + magic-byte
 * check remains the actual, load-bearing control regardless (defense in
 * depth, not a replacement for it). */
export const signPutUrl = async (
  config: R2Config,
  key: string,
  contentType: string,
  expiresSeconds: number,
): Promise<string> => {
  const client = createClient(config);
  const url = new URL(objectUrl(config, key));
  url.searchParams.set('X-Amz-Expires', String(expiresSeconds));
  const signed = await client.sign(
    new Request(url, { method: 'PUT', headers: { 'Content-Type': contentType } }),
    { aws: { signQuery: true, allHeaders: true } },
  );
  return signed.url;
};

/** Presigned GET, with the response Content-Type/Content-Disposition R2
 * should send back baked into the signed query string (response-content-*
 * overrides) — never something the browser has to trust separately. */
export const signGetUrl = async (
  config: R2Config,
  key: string,
  expiresSeconds: number,
  responseContentType: string,
  responseContentDisposition: string,
): Promise<string> => {
  const client = createClient(config);
  const url = new URL(objectUrl(config, key));
  url.searchParams.set('X-Amz-Expires', String(expiresSeconds));
  url.searchParams.set('response-content-type', responseContentType);
  url.searchParams.set('response-content-disposition', responseContentDisposition);
  const signed = await client.sign(new Request(url, { method: 'GET' }), { aws: { signQuery: true } });
  return signed.url;
};

export interface R2HeadResult {
  exists: boolean;
  contentLength: number;
  contentType: string | null;
  etag: string | null;
}

/** Real, server-side HEAD (never presigned — the browser never needs it).
 * Confirms the object actually exists and reports R2's own recorded size/
 * type: a PUT having been signed proves nothing about what actually landed
 * in the bucket. */
export const headObject = async (config: R2Config, key: string): Promise<R2HeadResult> => {
  const client = createClient(config);
  const response = await client.fetch(objectUrl(config, key), { method: 'HEAD' });
  if (response.status === 404) return { exists: false, contentLength: 0, contentType: null, etag: null };
  if (!response.ok) throw new Error(`R2 HEAD failed with status ${response.status}`);
  return {
    exists: true,
    contentLength: Number(response.headers.get('content-length') ?? '0'),
    contentType: response.headers.get('content-type'),
    etag: response.headers.get('etag'),
  };
};

/** First `length` bytes of the object, for magic-byte validation — never
 * downloads the whole file just to check its signature. */
export const getObjectRange = async (config: R2Config, key: string, length: number): Promise<Uint8Array> => {
  const client = createClient(config);
  const response = await client.fetch(objectUrl(config, key), { headers: { Range: `bytes=0-${length - 1}` } });
  if (!response.ok && response.status !== 206) throw new Error(`R2 ranged GET failed with status ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
};

/** Real, server-side DELETE — never presigned (a leaked signed DELETE URL
 * would be a bearer-token capability to destroy data). Idempotent: R2/S3
 * return 204 for DELETE whether or not the object existed, and this
 * treats a 404 the same way, so a repeated or out-of-order delete call is
 * always safe. */
export const deleteObject = async (config: R2Config, key: string): Promise<void> => {
  const client = createClient(config);
  const response = await client.fetch(objectUrl(config, key), { method: 'DELETE' });
  if (!response.ok && response.status !== 404) throw new Error(`R2 DELETE failed with status ${response.status}`);
};
