import { createServiceClient, getAuthenticatedUser, isUuid } from '../_shared/adminAuth.ts';
import { randomToken, hashState, pkceChallenge, importKey, seal, unseal, READ_SCOPE, exactScope } from './crypto.ts';

const env = (name: string) => Deno.env.get(name) ?? '';
const table = 'romax_gmail_connections';
const clearAttempt = { attempt_hash: null, attempt_owner: null, attempt_verifier: null, attempt_expires_at: null };
const clearConnection = { mailbox_email: null, refresh_ciphertext: null, connected_by: null, connected_at: null };
class SafeError extends Error { constructor(readonly status: number, message: string) { super(message); } }
function configuration() {
  const organization = env('ROMAX_GMAIL_ORGANIZATION_ID');
  const mailbox = env('ROMAX_GMAIL_EXPECTED_EMAIL').trim().toLowerCase();
  const origin = env('ROMAX_GMAIL_APP_ORIGIN');
  const clientId = env('ROMAX_GMAIL_CLIENT_ID');
  const clientSecret = env('ROMAX_GMAIL_CLIENT_SECRET');
  const key = env('ROMAX_GMAIL_ENCRYPTION_KEY');
  if (!isUuid(organization) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mailbox) || !clientId || !clientSecret || !key) throw new SafeError(503,'Conexión Gmail no configurada');
  let parsed: URL;
  try { parsed = new URL(origin); } catch { throw new SafeError(503,'Conexión Gmail no configurada'); }
  if (parsed.protocol !== 'https:' || parsed.origin !== origin) throw new SafeError(503,'Conexión Gmail no configurada');
  return { organization, mailbox, origin, clientId, clientSecret, key, redirectUri: origin + '/gmail/callback' };
}
type Config = ReturnType<typeof configuration>;
type Db = ReturnType<typeof createServiceClient>;
async function assertOwner(db: Db, organization: string, user: string) {
  const { data, error } = await db.from('organization_members').select('id, organizations!inner(organization_type,status)')
    .eq('organization_id', organization).eq('user_id',user).eq('role','owner').eq('is_active',true)
    .eq('organizations.organization_type','provider_company').eq('organizations.status','active').limit(1);
  if (error) throw new SafeError(503,'No se pudo verificar el acceso');
  if (!data?.length) throw new SafeError(403,'Acceso restringido');
}
async function getRow(db: Db, organization: string) {
  const { data, error } = await db.from(table).select('*').eq('organization_id',organization).maybeSingle();
  if (error) throw new SafeError(503,'Conexión Gmail no disponible');
  return data;
}
async function googleToken(config: Config, values: Record<string,string>) {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method:'POST', body:new URLSearchParams({ client_id:config.clientId, client_secret:config.clientSecret, ...values }),
    signal:AbortSignal.timeout(15000), redirect:'error',
  });
  if (!response.ok) throw new SafeError(409,'Google no autorizó la conexión; vuelve a intentarlo');
  const data = await response.json();
  if (typeof data.access_token !== 'string' || !data.access_token) throw new SafeError(409,'Respuesta de Google incompleta');
  return data;
}
async function verifyMailbox(config: Config, accessToken: string) {
  const response = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', {
    headers:{ Authorization:'Bearer '+accessToken }, signal:AbortSignal.timeout(15000), redirect:'error',
  });
  if (!response.ok) throw new SafeError(409,'No se pudo verificar el buzón de Gmail');
  const data = await response.json();
  if (typeof data.emailAddress !== 'string' || data.emailAddress.trim().toLowerCase() !== config.mailbox) throw new SafeError(403,'Selecciona exclusivamente el buzón comercial autorizado');
}
Deno.serve(async req => {
  const configuredOrigin = env('ROMAX_GMAIL_APP_ORIGIN');
  const headers = { 'Access-Control-Allow-Origin':configuredOrigin, 'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version', 'Access-Control-Allow-Methods':'POST, OPTIONS', 'Vary':'Origin', 'Content-Type':'application/json', 'Cache-Control':'no-store', 'Referrer-Policy':'no-referrer' };
  const reply = (body:unknown,status=200) => new Response(JSON.stringify(body),{status,headers});
  if (!configuredOrigin || req.headers.get('Origin') !== configuredOrigin) return reply({error:'Origen no autorizado'},403);
  if (req.method === 'OPTIONS') return new Response(null,{status:204,headers});
  if (req.method !== 'POST') return reply({error:'Método no permitido'},405);
  try {
    const user = await getAuthenticatedUser(req);
    const config = configuration();
    const body = await req.json();
    if (!body || body.organization_id !== config.organization) throw new SafeError(403,'Acceso restringido');
    const db = createServiceClient();
    await assertOwner(db,config.organization,user.id);
    const organization = config.organization;
    const row = await getRow(db,organization);
    const expired = row?.attempt_expires_at && Date.parse(row.attempt_expires_at) <= Date.now();
    const now = () => new Date().toISOString();
    const key = await importKey(config.key);
    const context = (purpose:string) => organization + ':' + purpose;
    if (body.action === 'status') return reply({
      status: expired ? 'disconnected' : row?.status ?? 'disconnected',
      mailbox: row?.status === 'connected' ? row.mailbox_email : null,
      connected_at: row?.status === 'connected' ? row.connected_at : null,
    });
    if (body.action === 'start') {
      if (row && !['disconnected','pending','exchanging'].includes(row.status)) throw new SafeError(409,'Desconecta la cuenta antes de volver a conectar');
      if (row?.status === 'exchanging' && !expired) throw new SafeError(409,'Hay una conexión en curso');
      const state = randomToken();
      const verifier = randomToken();
      const hash = await hashState(state);
      const values = { status:'pending', attempt_hash:hash, attempt_owner:user.id, attempt_verifier:await seal(key,verifier,context('pkce:'+hash)), attempt_expires_at:new Date(Date.now()+10*60*1000).toISOString(), updated_at:now(), ...clearConnection };
      // Ensure an initial row exists without overwriting a concurrent connection.
      const inserted = await db.from(table).upsert({organization_id:organization},{onConflict:'organization_id',ignoreDuplicates:true});
      if (inserted.error) throw new SafeError(503,'No se pudo iniciar conexión');
      let update = db.from(table).update(values).eq('organization_id',organization);
      if (!row) update = update.eq('status','disconnected');
      else {
        update = update.eq('status',row.status);
        update = row.attempt_hash ? update.eq('attempt_hash',row.attempt_hash) : update.is('attempt_hash',null);
      }
      const result = await update.select('organization_id').maybeSingle();
      if (result.error || !result.data) throw new SafeError(409,'La conexión cambió; vuelve a intentar');
      const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
      url.search = new URLSearchParams({client_id:config.clientId,redirect_uri:config.redirectUri,response_type:'code',scope:READ_SCOPE,access_type:'offline',prompt:'consent select_account',include_granted_scopes:'false',login_hint:config.mailbox,state,code_challenge:await pkceChallenge(verifier),code_challenge_method:'S256'}).toString();
      return reply({authorization_url:url.toString(),state});
    }
    if (body.action === 'complete') {
      if (typeof body.state !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(body.state) || typeof body.code !== 'string' || !body.code || body.code.length>4096) throw new SafeError(400,'Respuesta OAuth inválida');
      const hash = await hashState(body.state);
      if (!row || row.status !== 'pending' || row.attempt_hash !== hash || row.attempt_owner !== user.id || expired) throw new SafeError(409,'La solicitud de conexión expiró o ya fue utilizada');
      // Atomic single-use claim: only one exchange can proceed.
      const claim = await db.from(table).update({status:'exchanging',updated_at:now()}).eq('organization_id',organization).eq('status','pending').eq('attempt_hash',hash).eq('attempt_owner',user.id).gt('attempt_expires_at',now()).select('organization_id').maybeSingle();
      if (claim.error || !claim.data) throw new SafeError(409,'La solicitud de conexión ya fue utilizada');
      try {
        const verifier = await unseal(key,row.attempt_verifier,context('pkce:'+hash));
        const tokens = await googleToken(config,{grant_type:'authorization_code',code:body.code,code_verifier:verifier,redirect_uri:config.redirectUri});
        if (!exactScope(tokens.scope) || typeof tokens.refresh_token !== 'string' || !tokens.refresh_token) throw new SafeError(409,'Google no concedió exclusivamente lectura con acceso persistente');
        await verifyMailbox(config,tokens.access_token);
        await assertOwner(db,organization,user.id);
        const stored = await db.from(table).update({status:'connected',...clearAttempt,mailbox_email:config.mailbox,refresh_ciphertext:await seal(key,tokens.refresh_token,context('refresh')),connected_by:user.id,connected_at:now(),updated_at:now()}).eq('organization_id',organization).eq('status','exchanging').eq('attempt_hash',hash).eq('attempt_owner',user.id).gt('attempt_expires_at',now()).select('organization_id').maybeSingle();
        if (stored.error || !stored.data) throw new SafeError(409,'No se pudo completar la conexión');
        return reply({status:'connected',mailbox:config.mailbox});
      } catch (error) {
        await db.from(table).update({status:'disconnected',...clearAttempt,...clearConnection,updated_at:now()}).eq('organization_id',organization).eq('status','exchanging').eq('attempt_hash',hash);
        throw error;
      }
    }
    if (body.action === 'verify') {
      if (!row || row.status !== 'connected' || row.mailbox_email !== config.mailbox) throw new SafeError(409,'No hay una conexión activa');
      const refresh = await unseal(key,row.refresh_ciphertext,context('refresh'));
      const tokens = await googleToken(config,{grant_type:'refresh_token',refresh_token:refresh});
      if (tokens.scope !== undefined && !exactScope(tokens.scope)) throw new SafeError(409,'Permiso de Google inesperado');
      await verifyMailbox(config,tokens.access_token);
      return reply({status:'connected',mailbox:config.mailbox,verified:true});
    }
    if (body.action === 'disconnect') {
      if (!row || row.status === 'disconnected') return reply({status:'disconnected'});
      if (row.status === 'pending' || (row.status === 'exchanging' && expired)) {
        const cancelled = await db.from(table).update({status:'disconnected',...clearAttempt,...clearConnection,updated_at:now()}).eq('organization_id',organization).eq('status',row.status).eq('attempt_hash',row.attempt_hash).select('organization_id').maybeSingle();
        if (cancelled.error || !cancelled.data) throw new SafeError(409,'La conexión cambió; vuelve a intentar');
        return reply({status:'disconnected'});
      }
      if (row.status !== 'connected' && row.status !== 'revoking') throw new SafeError(409,'Hay una conexión en curso');
      // No new OAuth attempt is allowed while revoking. Retrying revocation is safe.
      const locked = await db.from(table).update({status:'revoking',updated_at:now()}).eq('organization_id',organization).eq('status',row.status).eq('updated_at',row.updated_at).select('updated_at').maybeSingle();
      if (locked.error || !locked.data) throw new SafeError(409,'La conexión cambió; vuelve a intentar');
      const refresh = await unseal(key,row.refresh_ciphertext,context('refresh'));
      const response = await fetch('https://oauth2.googleapis.com/revoke',{method:'POST',body:new URLSearchParams({token:refresh}),signal:AbortSignal.timeout(15000),redirect:'error'});
      if (!response.ok && response.status !== 400) throw new SafeError(503,'Revocación pendiente; vuelve a intentar');
      if (response.status===400) {
        // Do not infer that a generic 400 revoked a credential.
        const data = await response.json().catch(()=>null);
        if (data?.error !== 'invalid_token') throw new SafeError(503,'Revocación pendiente; vuelve a intentar');
      }
      const cleared = await db.from(table).update({status:'disconnected',...clearAttempt,...clearConnection,updated_at:now()}).eq('organization_id',organization).eq('status','revoking').eq('updated_at',locked.data.updated_at).select('organization_id').maybeSingle();
      if (cleared.error || !cleared.data) throw new SafeError(409,'Revocación pendiente; vuelve a intentar');
      return reply({status:'disconnected'});
    }
    throw new SafeError(400,'Acción no disponible');
  } catch (error) {
    // Never log codes, tokens, provider response bodies or raw exceptions.
    if (error instanceof SafeError) return reply({error:error.message},error.status);
    if (error instanceof Error && error.message === 'Unauthorized') return reply({error:'Sesión requerida'},401);
    return reply({error:'No se pudo completar la operación de Gmail'},503);
  }
});
