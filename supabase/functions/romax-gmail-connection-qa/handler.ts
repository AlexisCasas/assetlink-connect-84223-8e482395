import { createServiceClient, getAuthenticatedUser, isUuid } from '../_shared/adminAuth.ts';
import { randomToken, hashState, pkceChallenge, importKey, seal, unseal, READ_SCOPE, exactScope } from './crypto.ts';

import { DAY_MS, readPreview, importPolicy } from './preview.ts';
import { candidateDigest, issueConfirmation, openConfirmation, senderEmail } from './import.ts';

const env = (name: string) => Deno.env.get(name) ?? '';
const table = 'romax_gmail_connections';
const clearAttempt = { attempt_hash: null, attempt_owner: null, attempt_verifier: null, attempt_expires_at: null };
const clearConnection = { mailbox_email: null, refresh_ciphertext: null, connected_by: null, connected_at: null };
class SafeError extends Error { constructor(readonly status: number, message: string) { super(message); } }
function configuration(readEnv: typeof env) {
  const organization = readEnv('ROMAX_GMAIL_ORGANIZATION_ID');
  const mailbox = readEnv('ROMAX_GMAIL_EXPECTED_EMAIL').trim().toLowerCase();
  const origin = readEnv('ROMAX_GMAIL_APP_ORIGIN');
  const clientId = readEnv('ROMAX_GMAIL_CLIENT_ID');
  const clientSecret = readEnv('ROMAX_GMAIL_CLIENT_SECRET');
  const key = readEnv('ROMAX_GMAIL_ENCRYPTION_KEY');
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
async function googleToken(config: Config, values: Record<string,string>, request: typeof fetch) {
  const response = await request('https://oauth2.googleapis.com/token', {
    method:'POST', body:new URLSearchParams({ client_id:config.clientId, client_secret:config.clientSecret, ...values }),
    signal:AbortSignal.timeout(15000), redirect:'error',
  });
  if (!response.ok) throw new SafeError(409,'Google no autorizó la conexión; vuelve a intentarlo');
  const data = await response.json();
  if (typeof data.access_token !== 'string' || !data.access_token) throw new SafeError(409,'Respuesta de Google incompleta');
  return data;
}
async function verifyMailbox(config: Config, accessToken: string, request: typeof fetch) {
  const response = await request('https://gmail.googleapis.com/gmail/v1/users/me/profile', {
    headers:{ Authorization:'Bearer '+accessToken }, signal:AbortSignal.timeout(15000), redirect:'error',
  });
  if (!response.ok) throw new SafeError(409,'No se pudo verificar el buzón de Gmail');
  const data = await response.json();
  if (typeof data.emailAddress !== 'string' || data.emailAddress.trim().toLowerCase() !== config.mailbox) throw new SafeError(403,'Selecciona exclusivamente el buzón comercial autorizado');
}
type Dependencies = { authenticate: (req: Request) => Promise<{id:string}>; service: () => Db; request: typeof fetch; readEnv: typeof env };
export function createHandler(deps: Dependencies = { authenticate:getAuthenticatedUser, service:createServiceClient, request:fetch, readEnv:env }, allowedActions?: ReadonlySet<string>) {
  const { request, readEnv } = deps;
  return async (req: Request): Promise<Response> => {
  const configuredOrigin = readEnv('ROMAX_GMAIL_APP_ORIGIN');
  const headers = { 'Access-Control-Allow-Origin':configuredOrigin, 'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version', 'Access-Control-Allow-Methods':'POST, OPTIONS', 'Vary':'Origin', 'Content-Type':'application/json', 'Cache-Control':'no-store', 'Referrer-Policy':'no-referrer' };
  const reply = (body:unknown,status=200) => new Response(JSON.stringify(body),{status,headers});
  if (!configuredOrigin || req.headers.get('Origin') !== configuredOrigin) return reply({error:'Origen no autorizado'},403);
  if (req.method === 'OPTIONS') return new Response(null,{status:204,headers});
  if (req.method !== 'POST') return reply({error:'Método no permitido'},405);
  try {
    const user = await deps.authenticate(req);
    const config = configuration(readEnv);
    const body = await req.json();
    if (!body || body.organization_id !== config.organization) throw new SafeError(403,'Acceso restringido');
    if (allowedActions && (typeof body.action !== 'string' || !allowedActions.has(body.action))) throw new SafeError(403,'Acción no habilitada en este entorno');
    const db = deps.service();
    await assertOwner(db,config.organization,user.id);
    const organization = config.organization;
    const row = await getRow(db,organization);
    const expired = row?.attempt_expires_at && Date.parse(row.attempt_expires_at) <= Date.now();
    const now = () => new Date().toISOString();
    const key = await importKey(config.key);
    const context = (purpose:string) => organization + ':' + purpose;
    const importEnabled=readEnv('ROMAX_GMAIL_IMPORT_ENABLED')==='true';
    const confirmationContext=context('import:'+user.id+':'+row?.connected_at+':'+config.origin);
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
        const tokens = await googleToken(config,{grant_type:'authorization_code',code:body.code,code_verifier:verifier,redirect_uri:config.redirectUri},request);
        if (!exactScope(tokens.scope) || typeof tokens.refresh_token !== 'string' || !tokens.refresh_token) throw new SafeError(409,'Google no concedió exclusivamente lectura con acceso persistente');
        await verifyMailbox(config,tokens.access_token,request);
        await assertOwner(db,organization,user.id);
        const stored = await db.from(table).update({status:'connected',...clearAttempt,mailbox_email:config.mailbox,refresh_ciphertext:await seal(key,tokens.refresh_token,context('refresh')),connected_by:user.id,connected_at:now(),updated_at:now()}).eq('organization_id',organization).eq('status','exchanging').eq('attempt_hash',hash).eq('attempt_owner',user.id).gt('attempt_expires_at',now()).select('organization_id').maybeSingle();
        if (stored.error || !stored.data) throw new SafeError(409,'No se pudo completar la conexión');
        return reply({status:'connected',mailbox:config.mailbox});
      } catch (error) {
        await db.from(table).update({status:'disconnected',...clearAttempt,...clearConnection,updated_at:now()}).eq('organization_id',organization).eq('status','exchanging').eq('attempt_hash',hash);
        throw error;
      }
    }
    if (body.action === 'preview') {
      if (!row || row.status !== 'connected' || row.mailbox_email !== config.mailbox) throw new SafeError(409,'No hay una conexión activa');
      let to = Date.now(), pageToken: string|undefined;
      const cursorContext = context('preview:'+user.id+':'+row.connected_at);
      if (body.cursor !== undefined) {
        if(typeof body.cursor !== 'string' || body.cursor.length>12000) throw new SafeError(400,'Página inválida');
        try {
          const cursor=JSON.parse(await unseal(key,body.cursor,cursorContext));
          if(!Number.isSafeInteger(cursor.to)||cursor.to>Date.now()||Date.now()-cursor.to>15*60*1000||typeof cursor.next!=='string'||!cursor.next||cursor.next.length>=4096) throw new Error('Invalid cursor');
          to=cursor.to;pageToken=cursor.next;
        } catch { throw new SafeError(400,'La revisión expiró. Sincroniza nuevamente.'); }
      }
      const from=to-7*DAY_MS;
      const refresh=await unseal(key,row.refresh_ciphertext,context('refresh'));
      const tokens=await googleToken(config,{grant_type:'refresh_token',refresh_token:refresh},request);
      if(tokens.scope!==undefined&&!exactScope(tokens.scope))throw new SafeError(409,'Permiso de Google inesperado');
      await verifyMailbox(config,tokens.access_token,request);
      let page;
      try { page=await readPreview(request,tokens.access_token,from,to,pageToken); }
      catch { throw new SafeError(503,'No se pudo leer esta página de Gmail. Reintenta sin importar datos.'); }
      await assertOwner(db,organization,user.id);
      const current=await getRow(db,organization);
      if(current?.status!=='connected'||current.connected_at!==row.connected_at)throw new SafeError(409,'La conexión cambió');
      if(page.candidates.length){
        const existing=await db.from('romax_opportunities').select('id,source_thread_id,status').eq('organization_id',organization).eq('source_system','gmail').in('source_thread_id',page.candidates.map(x=>x.thread_id));
        if(existing.error)throw new SafeError(503,'No se pudo comprobar duplicados');
        for(const candidate of page.candidates){const linked=existing.data?.find(x=>x.source_thread_id===candidate.thread_id);candidate.existing_status=linked?.status??null;candidate.existing_opportunity_id=linked?.id??null;candidate.import_policy=importPolicy(candidate);}
      }
      const candidates=await Promise.all(page.candidates.map(async candidate=>({ ...candidate, confirmation_token:importEnabled&&candidate.import_policy==='new_candidate'?await issueConfirmation(key,confirmationContext,candidate,from):null })));
      const next_cursor=page.next?await seal(key,JSON.stringify({to,next:page.next}),cursorContext):null;
      return reply({status:'connected',window_start:new Date(from).toISOString(),window_end:new Date(to).toISOString(),candidates,scanned:page.scanned,estimate:page.estimate,next_cursor});
    }
    if (body.action === 'confirm_import') {
      if(!importEnabled)throw new SafeError(403,'Importación no habilitada');
      if(body.confirmed!==true||!row||row.status!=='connected'||row.mailbox_email!==config.mailbox)throw new SafeError(409,'Confirma la importación con una conexión activa');
      let confirmation;
      try{confirmation=await openConfirmation(key,confirmationContext,body.confirmation_token);}
      catch{throw new SafeError(409,'La confirmación expiró o cambió; sincroniza nuevamente');}
      const refresh=await unseal(key,row.refresh_ciphertext,context('refresh'));
      const tokens=await googleToken(config,{grant_type:'refresh_token',refresh_token:refresh},request);
      if(tokens.scope!==undefined&&!exactScope(tokens.scope))throw new SafeError(409,'Permiso de Google inesperado');
      await verifyMailbox(config,tokens.access_token,request);
      const page=await readPreview(request,tokens.access_token,confirmation.from,Date.now(),undefined,confirmation.thread);
      const candidate=page.candidates[0];
      if(!candidate||candidate.message_id!==confirmation.message||importPolicy(candidate)!=='new_candidate'||await candidateDigest(candidate)!==confirmation.digest)
        throw new SafeError(409,'La conversación cambió o requiere revisión; sincroniza nuevamente');
      await assertOwner(db,organization,user.id);
      const result=await db.rpc('romax_confirm_gmail_import',{
        p_org:organization,p_actor:user.id,p_connected_at:row.connected_at,
        p_confirmation_hash:await hashState(confirmation.nonce),p_digest:confirmation.digest,
        p_expires_at:new Date(confirmation.expires).toISOString(),
        p_thread:candidate.thread_id,p_message:candidate.message_id,p_subject:candidate.subject,
        p_sender:senderEmail(candidate.sender),p_received_at:candidate.received_at,
        p_snippet:candidate.snippet.slice(0,500),p_reason:candidate.reason
      });
      if(result.error||!result.data)throw new SafeError(409,'No se pudo confirmar la importación; sincroniza para comprobar su estado');
      return reply(result.data);
    }
    if (body.action === 'verify') {
      if (!row || row.status !== 'connected' || row.mailbox_email !== config.mailbox) throw new SafeError(409,'No hay una conexión activa');
      const refresh = await unseal(key,row.refresh_ciphertext,context('refresh'));
      const tokens = await googleToken(config,{grant_type:'refresh_token',refresh_token:refresh},request);
      if (tokens.scope !== undefined && !exactScope(tokens.scope)) throw new SafeError(409,'Permiso de Google inesperado');
      await verifyMailbox(config,tokens.access_token,request);
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
      if (row.status === 'revoking' && Date.now() - Date.parse(row.updated_at) < 60000) throw new SafeError(409,'Revocación en curso; vuelve a consultar el estado');
      // No new OAuth attempt is allowed while revoking. Retrying revocation is safe.
      const locked = await db.from(table).update({status:'revoking',updated_at:now()}).eq('organization_id',organization).eq('status',row.status).eq('updated_at',row.updated_at).select('updated_at').maybeSingle();
      if (locked.error || !locked.data) throw new SafeError(409,'La conexión cambió; vuelve a intentar');
      const refresh = await unseal(key,row.refresh_ciphertext,context('refresh'));
      const response = await request('https://oauth2.googleapis.com/revoke',{method:'POST',body:new URLSearchParams({token:refresh}),signal:AbortSignal.timeout(15000),redirect:'error'});
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
  };
}


// Isolated Preview-only entrypoint. This origin is the stable Vercel branch alias;
// OAuth lifecycle is blocked; confirmation is disabled unless its separate QA flag is enabled.
export const QA_APP_ORIGIN = 'https://one-facility-git-feature-romax-r3-29c35c-alexiscasasrs-projects.vercel.app';
export function createQaHandler() {
  const readEnv = (name: string) => name === 'ROMAX_GMAIL_APP_ORIGIN' ? (env('ROMAX_GMAIL_QA_APP_ORIGIN')||QA_APP_ORIGIN) : name==='ROMAX_GMAIL_IMPORT_ENABLED' ? env('ROMAX_GMAIL_QA_IMPORT_ENABLED') : env(name);
  return createHandler({ authenticate:getAuthenticatedUser, service:createServiceClient, request:fetch, readEnv }, new Set(['status','preview','confirm_import']));
}
