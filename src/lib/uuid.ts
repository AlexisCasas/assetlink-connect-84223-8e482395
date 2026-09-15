/**
 * `crypto.randomUUID()` is only exposed by browsers in a "secure context"
 * (HTTPS, or `localhost`/`127.0.0.1`) — `window.crypto` itself still exists
 * over plain HTTP on a LAN IP (e.g. `http://192.168.1.10:8080` during QA),
 * but `randomUUID` is `undefined` there, so any direct call throws
 * `TypeError: crypto.randomUUID is not a function`. `generateUuid()` is the
 * single place every client-side UUID in this codebase should come from, so
 * that degrades safely instead of crashing the caller.
 */

const toUuidString = (bytes: Uint8Array): string => {
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};

/** Stamps the RFC 4122 version 4 + variant bits onto 16 random bytes in place. */
const applyRfc4122VersionAndVariant = (bytes: Uint8Array): Uint8Array => {
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant RFC 4122 (10xxxxxx)
  return bytes;
};

/**
 * Generates a UUID v4 string, in order of preference:
 * 1. `crypto.randomUUID()` when the browser exposes it (secure context).
 * 2. `crypto.getRandomValues()` otherwise — unlike `randomUUID`, this is
 *    available in both secure and non-secure contexts in every browser this
 *    app targets, and still yields cryptographically random bytes.
 * 3. `Math.random()` only if Web Crypto is entirely unavailable (no real
 *    browser this app supports should ever reach this branch). NOT
 *    cryptographically secure — safe here only because every current caller
 *    uses the result as a collision-resistant identifier (a client-side
 *    React list key, or a client-chosen primary key for a row whose access
 *    is still fully gated by RLS/tenant checks), never as a secret,
 *    capability token, or anything auth/RLS would trust as unguessable. If
 *    a future caller needs an unguessable id, it must not rely on this
 *    fallback path.
 */
export function generateUuid(): string {
  const cryptoObj = globalThis.crypto;

  if (typeof cryptoObj?.randomUUID === 'function') {
    return cryptoObj.randomUUID();
  }

  if (typeof cryptoObj?.getRandomValues === 'function') {
    return toUuidString(applyRfc4122VersionAndVariant(cryptoObj.getRandomValues(new Uint8Array(16))));
  }

  console.warn(
    'generateUuid(): Web Crypto API is unavailable in this environment — falling back to Math.random(), which is not cryptographically secure.',
  );
  const bytes = Uint8Array.from({ length: 16 }, () => Math.floor(Math.random() * 256));
  return toUuidString(applyRfc4122VersionAndVariant(bytes));
}
