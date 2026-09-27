// Server-side origin used to build invitation/magic-link redirect URLs.
// Deliberately NOT the frontend's VITE_PUBLIC_APP_URL (a client bundle
// value has no place deciding a security-relevant redirect target from the
// backend) and NEVER derived from the request body, Origin or Referer
// headers, which are attacker-controlled. Configure as a Supabase Edge
// Function secret named PUBLIC_APP_URL.
const LOCAL_HOSTNAMES = new Set(['localhost', '127.0.0.1']);

/** Validates and returns the configured PUBLIC_APP_URL as a bare origin
 * (no path/query/hash). Fails closed: throws instead of falling back to
 * any default, so a missing/invalid secret never silently produces a
 * localhost or attacker-influenced link in staging/production. */
export const getPublicAppOrigin = (): string => {
  const raw = Deno.env.get('PUBLIC_APP_URL');
  if (!raw) throw new Error('Missing required Edge Function secret: PUBLIC_APP_URL');

  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error(`PUBLIC_APP_URL is not a valid URL: "${raw}"`);
  }

  if (url.pathname !== '/' && url.pathname !== '') throw new Error('PUBLIC_APP_URL must be a bare origin (no path)');
  if (url.search !== '' || url.hash !== '') throw new Error('PUBLIC_APP_URL must not include query or hash');

  const isLocal = LOCAL_HOSTNAMES.has(url.hostname);
  if (url.protocol === 'http:' && !isLocal) {
    throw new Error('PUBLIC_APP_URL must use https:// outside local development');
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error('PUBLIC_APP_URL must use http:// or https://');
  }

  return url.origin;
};

/** Builds the exact redirect target every invitation link points to. */
export const buildInvitationAcceptUrl = (invitationId: string): string =>
  `${getPublicAppOrigin()}/invitations/accept?invitation=${invitationId}`;
