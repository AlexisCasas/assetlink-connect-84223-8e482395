import { createClient, type SupabaseClient, type User } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const environment = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required Edge Function secret: ${name}`);
  return value;
};

export const createServiceClient = (): SupabaseClient => createClient(
  environment('SUPABASE_URL'),
  environment('SUPABASE_SERVICE_ROLE_KEY'),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

/** A client authenticated as the caller (anon key + their JWT in
 * Authorization), used to run RPCs so Postgres resolves auth.uid() to the
 * real caller and every authorization rule enforced in SQL — role,
 * hierarchy, tenant — still applies exactly as it would from the browser.
 * Never use createServiceClient() for these calls: that would bypass the
 * RPC's own auth.uid()-based checks entirely. */
export const createCallerClient = (req: Request): SupabaseClient => {
  const authorization = req.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) throw new Error('Unauthorized');

  return createClient(
    environment('SUPABASE_URL'),
    environment('SUPABASE_ANON_KEY'),
    {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authorization } },
    },
  );
};

export const getAuthenticatedUser = async (req: Request): Promise<User> => {
  const userClient = createCallerClient(req);
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) throw new Error('Unauthorized');
  return user;
};

export const assertPlatformAdmin = async (userId: string): Promise<void> => {
  const service = createServiceClient();
  const { data, error } = await service
    .from('organization_members')
    .select('id, organizations!inner(organization_type, status)')
    .eq('user_id', userId)
    .eq('is_active', true)
    .in('role', ['owner', 'admin'])
    .eq('organizations.organization_type', 'platform_admin')
    .eq('organizations.status', 'active')
    .limit(1);

  if (error) throw new Error('Unable to verify platform administrator permissions');
  if (!data?.length) throw new Error('Forbidden');
};

export const assertOrganizationAdmin = async (userId: string, organizationId: string): Promise<void> => {
  const service = createServiceClient();
  const { data, error } = await service
    .from('organization_members')
    .select('id')
    .eq('organization_id', organizationId)
    .eq('user_id', userId)
    .eq('is_active', true)
    .in('role', ['owner', 'admin'])
    .limit(1);

  if (error) throw new Error('Unable to verify organization administrator permissions');
  if (!data?.length) throw new Error('Forbidden');
};

export const jsonResponse = (body: unknown, status = 200): Response => new Response(
  JSON.stringify(body),
  { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
);

export const errorResponse = (message: string, status = 400): Response => jsonResponse({ error: message }, status);

export const handleCors = (req: Request): Response | null => (
  req.method === 'OPTIONS' ? new Response('ok', { headers: corsHeaders }) : null
);

export const requirePost = (req: Request): void => {
  if (req.method !== 'POST') throw new Error('Method not allowed');
};

export const isUuid = (value: unknown): value is string => (
  typeof value === 'string'
  && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
);

export const normalizeEmail = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
};

export const isForbidden = (error: unknown): boolean => error instanceof Error && error.message === 'Forbidden';
