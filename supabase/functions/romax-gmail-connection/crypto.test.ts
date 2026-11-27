import { randomToken, hashState, pkceChallenge, importKey, seal, unseal, exactScope, READ_SCOPE } from './crypto.ts';
function assert(value:unknown) { if(!value) throw new Error('Assertion failed'); }
async function rejects(action:()=>Promise<unknown>) { let failed=false; try { await action(); } catch { failed=true; } assert(failed); }
Deno.test('state and PKCE are random and RFC 7636 compatible',async()=>{
  const a=randomToken(),b=randomToken();
  assert(a!==b && /^[A-Za-z0-9_-]{43}$/.test(a));
  assert((await hashState(a)).length===64 && await hashState(a)!==await hashState(b));
  assert(await pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk')==='E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
});
Deno.test('AES-GCM randomized ciphertext, tenant and purpose binding, tamper rejection',async()=>{
  const key=await importKey(btoa('a'.repeat(32))),other=await importKey(btoa('b'.repeat(32)));
  const a=await seal(key,'synthetic-token','org-a:refresh'),b=await seal(key,'synthetic-token','org-a:refresh');
  assert(a!==b && !a.includes('synthetic-token'));
  assert(await unseal(key,a,'org-a:refresh')==='synthetic-token');
  await rejects(()=>unseal(key,a,'org-b:refresh'));
  await rejects(()=>unseal(key,a,'org-a:pkce'));
  await rejects(()=>unseal(other,a,'org-a:refresh'));
  const pieces=a.split('.'); pieces[2]=(pieces[2][0]==='A'?'B':'A')+pieces[2].slice(1);
  await rejects(()=>unseal(key,pieces.join('.'),'org-a:refresh'));
  await rejects(()=>importKey(btoa('short')));
});
Deno.test('exact readonly scope only',()=>{
  assert(exactScope(READ_SCOPE)); assert(!exactScope(READ_SCOPE+' https://www.googleapis.com/auth/gmail.modify'));
  assert(!exactScope(undefined)); assert(!exactScope('https://mail.google.com/'));
});
