const encoder = new TextEncoder();
const decoder = new TextDecoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const unb64 = (value: string) => Uint8Array.from(atob(value), c => c.charCodeAt(0));
const url64 = (bytes: Uint8Array) => b64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
export const randomToken = () => url64(crypto.getRandomValues(new Uint8Array(32)));
export const hashState = async (value: string) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))), x => x.toString(16).padStart(2, '0')).join('');
export const pkceChallenge = async (value: string) => url64(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))));
export async function importKey(value: string) {
  const raw = unb64(value);
  if (raw.length !== 32) throw new Error('Invalid encryption key');
  return await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt','decrypt']);
}
export async function seal(key: CryptoKey, value: string, context: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(context) }, key, encoder.encode(value));
  return 'v1.' + b64(iv) + '.' + b64(new Uint8Array(ciphertext));
}
export async function unseal(key: CryptoKey, value: string, context: string) {
  const parts = value.split('.');
  if (parts.length !== 3 || parts[0] !== 'v1') throw new Error('Invalid ciphertext');
  return decoder.decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(parts[1]), additionalData: encoder.encode(context) }, key, unb64(parts[2])));
}
export const READ_SCOPE = 'https://www.googleapis.com/auth/gmail.readonly';
export function exactScope(scope: unknown): boolean {
  return typeof scope === 'string' && scope.trim().split(/\s+/).length === 1 && scope.trim() === READ_SCOPE;
}
