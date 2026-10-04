// @vitest-environment node
import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import vm from 'node:vm';
import ts from 'typescript';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import * as retour from '../../../supabase/functions/_shared/psc-return';
import * as security from '../../../supabase/functions/_shared/psc-security';
const M='/etablissement/missions/11111111-1111-4111-8111-111111111111';
const KEY='cle-synthetique-test-PSC';
function chargerEdge(fichier:string,admin:any,fetchMock:any,claims:()=>any,envOverride:any={}){
 let handler:any;const env={PSC_ENVIRONMENT:'sandbox',PSC_CLIENT_ID:'client-synthetique',PSC_CLIENT_SECRET:KEY,PSC_REDIRECT_URI:'https://edge.example.invalid/psc-callback',PSC_FRONTEND_URL:'https://jolene.example.invalid',SUPABASE_URL:'https://supabase.example.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture-sans-droit',...envOverride};
 const require=(name:string)=>{
  if(name.includes('@supabase/supabase-js'))return {createClient:()=>admin};
  if(name.includes('jose'))return {createRemoteJWKSet:()=>({}),jwtVerify:async(_token:any,_jwks:any,options:any)=>{expect(options).toMatchObject({audience:env.PSC_CLIENT_ID,algorithms:['RS256']});return {payload:claims()};}};
  if(name.endsWith('/psc-return.ts'))return retour;if(name.endsWith('/psc-security.ts'))return security;
  if(name.endsWith('/cors.ts'))return {jsonResponse:(_req:any,data:any,status=200)=>Response.json(data,{status}),preflightResponse:()=>new Response(null,{status:204})};
  if(name.endsWith('/rate-limit.ts'))return {applyRateLimit:()=>false,getClientIp:()=> 'fixture'};
  throw new Error('Import imprévu '+name);
 };
 const script=ts.transpileModule(readFileSync(fichier,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 vm.runInNewContext(script,{require,exports:{},Deno:{env:{get:(name:string)=>(env as any)[name]},serve:(fn:any)=>{handler=fn;}},crypto:webcrypto,fetch:fetchMock,URL,URLSearchParams,Request,Response,AbortSignal,TextEncoder,Uint8Array,ArrayBuffer,btoa,atob,console});
 return handler;
}
function contexte(){
 const sessions=new Map<string,any>();const lookups:string[]=[];const dbWrites:any[]=[];const generated=vi.fn(async()=>({data:{properties:{hashed_token:'hash-synthetique-usage-unique'}},error:null}));
 const admin={rpc:vi.fn(async(name:string)=>({data:name==='fn_verifier_rate_limit'?true:null,error:null})),auth:{admin:{getUserById:async()=>({data:{user:{email:'recette@example.invalid'}},error:null}),generateLink:generated,createUser:()=>{throw new Error('Création inattendue');}}},from:(table:string)=>{
  if(table==='psc_auth_sessions')return {insert:async(row:any)=>{sessions.set(row.state,{...row,expire_le:new Date(Date.now()+900_000).toISOString()});return {error:null};},delete:()=>({eq:(_key:string,value:string)=>{lookups.push(value);return {select:()=>({maybeSingle:async()=>{const session=sessions.get(value);sessions.delete(value);return {data:session??null,error:null};}})};}})};
  if(table==='soignants')return {select:()=>({eq:()=>({is:()=>({maybeSingle:async()=>({data:{id:'soignant-synthetique',email:'recette@example.invalid',profession:'IDE',numero_rpps:null,rpps_verifie:false,psc_sub:'psc-synthetique'},error:null})})})}),update:(value:any)=>({eq:async()=>{dbWrites.push(value);return {error:null};}})};
  throw new Error('Table inattendue '+table);
 }};
 const fetchMock=vi.fn(async(url:string)=>{
  if(url.endsWith('/token'))return Response.json({id_token:'id-token-simule',access_token:'access-token-simule'});
  if(url.endsWith('/userinfo'))return Response.json({sub:'psc-synthetique',codeProfession:'60',given_name:'Camille',family_name:'Test'});
  throw new Error('Réseau interdit '+url);
 });
 return {sessions,lookups,dbWrites,generated,admin,fetchMock};
}
beforeEach(()=>vi.stubGlobal('crypto',webcrypto));afterEach(()=>vi.unstubAllGlobals());
it('exécute authorize → state signé complet stocké → callback réel local → retour canonique et consommation unique',async()=>{
 const c=contexte();const authorize=chargerEdge('supabase/functions/psc-authorize/index.ts',c.admin,c.fetchMock,()=>({}));
 const response=await authorize(new Request('https://edge.example.invalid/authorize',{method:'POST',body:JSON.stringify({intention:'login',return_to:M})}));
 expect(response.status).toBe(200);const url=new URL((await response.json()).authorization_url);const state=url.searchParams.get('state')!;
 expect(state.startsWith('v1.')).toBe(true);expect(c.sessions.has(state)).toBe(true);expect(c.sessions.has(state.split('.')[1])).toBe(false);
 const session=c.sessions.get(state);const callback=chargerEdge('supabase/functions/psc-callback/index.ts',c.admin,c.fetchMock,()=>({sub:'psc-synthetique',nonce:session.nonce,codeProfession:'60'}));
 const result=await callback(new Request('https://edge.example.invalid/callback?code=code-simule&state='+encodeURIComponent(state)));
 const target=new URL(result.headers.get('Location'));expect(target.origin).toBe('https://jolene.example.invalid');expect(target.searchParams.get('status')).toBe('success');expect(target.searchParams.get('return')).toBe(M);
 expect(target.searchParams.get('token_hash')).toBe('hash-synthetique-usage-unique');expect(c.sessions.size).toBe(0);expect(c.lookups).toEqual([state]);expect(c.generated).toHaveBeenCalledTimes(1);
 const second=await callback(new Request('https://edge.example.invalid/callback?code=code-simule&state='+encodeURIComponent(state)));
 expect(new URL(second.headers.get('Location')).searchParams.get('status')).toBe('error');expect(c.generated).toHaveBeenCalledTimes(1);
 expect(c.fetchMock).toHaveBeenCalledTimes(2);expect(c.dbWrites.every(v=>!('role' in v))).toBe(true);
});
it('refuse un state falsifié avant DB, fournisseur ou génération de session',async()=>{
 const c=contexte();const state=await retour.signerEtatPsc('A'.repeat(43),M,KEY);const tampered=state.replace('11111111','22222222');
 const callback=chargerEdge('supabase/functions/psc-callback/index.ts',c.admin,c.fetchMock,()=>({}));const result=await callback(new Request('https://edge.example.invalid/callback?code=faux&state='+encodeURIComponent(tampered)+'&return=https://evil.invalid'));
 const target=new URL(result.headers.get('Location'));expect(target.searchParams.get('status')).toBe('error');expect(target.searchParams.has('return')).toBe(false);expect(c.lookups).toEqual([]);expect(c.fetchMock).not.toHaveBeenCalled();expect(c.generated).not.toHaveBeenCalled();
});
it('un state signé tronqué ne retrouve pas la session complète conservée',async()=>{
 const c=contexte();const state=await retour.signerEtatPsc('A'.repeat(43),M,KEY);c.sessions.set(state,{nonce:'nonce',code_verifier:'verifier',expire_le:new Date(Date.now()+10000).toISOString()});
 const callback=chargerEdge('supabase/functions/psc-callback/index.ts',c.admin,c.fetchMock,()=>({}));const response=await callback(new Request('https://edge.example.invalid/callback?code=faux&state='+state.split('.')[1]));
 expect(new URL(response.headers.get('Location')).searchParams.get('status')).toBe('error');expect(c.sessions.has(state)).toBe(true);expect(c.fetchMock).not.toHaveBeenCalled();
});
it('refuse les retours externes et une signature sans clé avant insertion',async()=>{
 const c=contexte();const authorize=chargerEdge('supabase/functions/psc-authorize/index.ts',c.admin,c.fetchMock,()=>({}));
 const invalid=await authorize(new Request('https://edge.example.invalid/authorize',{method:'POST',body:JSON.stringify({return_to:'https://evil.invalid'})}));expect(invalid.status).toBe(400);
 const absent=chargerEdge('supabase/functions/psc-authorize/index.ts',c.admin,c.fetchMock,()=>({}),{PSC_CLIENT_SECRET:undefined});
 const noKey=await absent(new Request('https://edge.example.invalid/authorize',{method:'POST',body:JSON.stringify({return_to:M})}));expect(noKey.status).toBe(503);expect(c.sessions.size).toBe(0);
});
it('conserve le state historique sans destination pour les anciens clients',async()=>{
 const c=contexte();const authorize=chargerEdge('supabase/functions/psc-authorize/index.ts',c.admin,c.fetchMock,()=>({}));
 const r=await authorize(new Request('https://edge.example.invalid/authorize',{method:'POST',body:JSON.stringify({intention:'login'})}));
 const state=new URL((await r.json()).authorization_url).searchParams.get('state')!;expect(state).toMatch(/^[A-Za-z0-9_-]{43}$/);const session=c.sessions.get(state);
 const callback=chargerEdge('supabase/functions/psc-callback/index.ts',c.admin,c.fetchMock,()=>({sub:'psc-synthetique',nonce:session.nonce,codeProfession:'60'}));
 const result=await callback(new Request('https://edge.example.invalid/callback?code=code-simule&state='+state+'&return='+encodeURIComponent(M)));
 const target=new URL(result.headers.get('Location'));expect(target.searchParams.get('status')).toBe('success');expect(target.searchParams.has('return')).toBe(false);
});
it('un nonce incompatible bloque toujours Auth et conserve seulement un retour signé pour réessai',async()=>{
 const c=contexte();const state=await retour.signerEtatPsc('A'.repeat(43),M,KEY);c.sessions.set(state,{nonce:'attendu',code_verifier:'verifier',expire_le:new Date(Date.now()+10000).toISOString()});
 const callback=chargerEdge('supabase/functions/psc-callback/index.ts',c.admin,c.fetchMock,()=>({sub:'psc-synthetique',nonce:'autre',codeProfession:'60'}));
 const r=await callback(new Request('https://edge.example.invalid/callback?code=code-simule&state='+encodeURIComponent(state)));
 const target=new URL(r.headers.get('Location'));expect(target.searchParams.get('status')).toBe('error');expect(target.searchParams.get('return')).toBe(M);expect(c.generated).not.toHaveBeenCalled();expect(c.dbWrites).toEqual([]);
});
