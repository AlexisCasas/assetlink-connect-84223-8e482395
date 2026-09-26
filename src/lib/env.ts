const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim();
const supabaseKey = (
  import.meta.env.VITE_SUPABASE_ANON_KEY
  ?? import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
)?.trim();

const missingSupabaseVariables = [
  !supabaseUrl && 'VITE_SUPABASE_URL',
  !supabaseKey && 'VITE_SUPABASE_ANON_KEY',
].filter(Boolean) as string[];

export const supabaseEnvironment = {
  url: supabaseUrl,
  key: supabaseKey,
};

export const supabaseConfigurationError = missingSupabaseVariables.length > 0
  ? `Faltan variables de configuración: ${missingSupabaseVariables.join(', ')}.`
  : null;

if (import.meta.env.DEV && supabaseConfigurationError) {
  console.error(
    `[One Facility] ${supabaseConfigurationError} Define las variables en .env.local; nunca subas ese archivo al repositorio.`,
  );
}

// -----------------------------------------------------------------------
// Public app URL — NOT secret. Used only to build printable/shareable QR
// deep links (see src/lib/assetQr.ts). Never used for auth, routing, or any
// server-side check: it only decides what origin gets printed on a label.
// -----------------------------------------------------------------------

/** Validates a configured VITE_PUBLIC_APP_URL: it must be a bare origin
 * (http/https, no path other than "/", no query, no hash) — anything else
 * would silently bake an unrelated path/query/hash into every QR link. */
export const normalizeConfiguredPublicAppUrl = (raw: string | undefined): { origin: string } | { error: string } | null => {
  const trimmed = raw?.trim();
  if (!trimmed) return null;

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return { error: `VITE_PUBLIC_APP_URL no es una URL válida: "${trimmed}".` };
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    return { error: 'VITE_PUBLIC_APP_URL debe usar http:// o https://.' };
  }
  if (url.pathname !== '/' && url.pathname !== '') {
    return { error: 'VITE_PUBLIC_APP_URL debe ser un origen (sin ruta), ej: https://app.tudominio.com' };
  }
  if (url.search !== '' || url.hash !== '') {
    return { error: 'VITE_PUBLIC_APP_URL no debe incluir query ni hash.' };
  }

  return { origin: url.origin };
};

/** localhost, 127.0.0.1/::1, *.localhost, and the common private IPv4
 * ranges — "development" origins that should never end up printed on a
 * physical label. Deliberately conservative: this only drives a warning, it
 * never blocks anything. */
export const isLocalOrDevOrigin = (origin: string): boolean => {
  let hostname: string;
  try {
    hostname = new URL(origin).hostname;
  } catch {
    return false;
  }
  if (hostname === 'localhost' || hostname.endsWith('.localhost') || hostname === '::1') return true;
  if (/^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  if (/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  if (/^172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  return false;
};

const configuredPublicAppUrl = normalizeConfiguredPublicAppUrl(import.meta.env.VITE_PUBLIC_APP_URL);
const configuredPublicAppUrlError = configuredPublicAppUrl && 'error' in configuredPublicAppUrl
  ? configuredPublicAppUrl.error
  : null;

/** The origin QR/deep links get built against: the validated
 * VITE_PUBLIC_APP_URL, or window.location.origin as a development fallback
 * (so localhost keeps working with zero configuration). Never throws. */
export const publicAppUrl = configuredPublicAppUrl && 'origin' in configuredPublicAppUrl
  ? configuredPublicAppUrl.origin
  : (typeof window !== 'undefined' ? window.location.origin : '');

/** True when publicAppUrl came from the window.location.origin fallback
 * (VITE_PUBLIC_APP_URL missing or invalid) rather than the configured
 * variable — regardless of whether that origin happens to be local. */
export const isPublicAppUrlFallback = !(configuredPublicAppUrl && 'origin' in configuredPublicAppUrl);

/** True when publicAppUrl currently resolves to a local/dev-looking origin
 * — drives the "QR de desarrollo" warning in AssetQrDialog. */
export const isPublicAppUrlLocal = isLocalOrDevOrigin(publicAppUrl);

if (import.meta.env.DEV && configuredPublicAppUrlError) {
  console.warn(`[One Facility] ${configuredPublicAppUrlError} Usando ${publicAppUrl} como origen de respaldo para enlaces QR.`);
}
