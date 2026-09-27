import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

const source=ts.transpileModule(readFileSync('supabase/functions/delete-account/index.ts','utf8'),{
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},
}).outputText;
function simulation(role:'SOIGNANT'|'ETABLISSEMENT',options:{rpc?:any;preuve?:any;erreurPreuve?:boolean;erreurAuth?:boolean}={}) {
  const userId='69400000-0000-4000-8000-000000000099';const appels:{nom:string;p?:any}[]=[];
  let handler!:(r:Request)=>Promise<Response>;
  const autorisees=['soignants','etablissements','membres_etablissement','admins_groupe_sante','alertes_systeme','tokens_push','tokens_calendrier',
    'calendar_connections','preferences_notifications','preferences_notifications_par_evenement','filtres_sauvegardes'];
  const admin={from:(table:string)=>{
    if(!autorisees.includes(table))throw new Error(`Table imprévue ${table}`);
    let write=false;const rows=table===(role==='SOIGNANT'?'soignants':'etablissements')?[{id:userId,supprime_le:'2026-09-24T10:00:00Z'}]:[];
    const query={select(){return query;},eq(){return query;},neq(){return query;},
      delete(){write=true;return query;},insert(){write=true;return query;},update(){write=true;return query;},
      maybeSingle(){return Promise.resolve({data:rows[0]??null,error:null});},
      then(resolve:any,reject:any){return Promise.resolve({data:write?null:rows,error:null,count:rows.length}).then(resolve,reject);}};return query;
  },rpc:async(nom:string,p:any)=>{
    if(nom!=='fn_anonymisation_compte_confirmee')throw new Error(`RPC service imprévue ${nom}`);
    appels.push({nom,p});return{data:'preuve'in options?options.preuve:true,error:options.erreurPreuve?{message:'503'}:null};
  },auth:{admin:{
    signOut:async()=>{appels.push({nom:'signOut'});return{error:null};},
    deleteUser:async(id:string,soft:boolean)=>{appels.push({nom:'deleteUser',p:{id,soft}});return{error:options.erreurAuth?{message:'panne Auth'}:null};},
    getUserById:async()=>({data:{user:{app_metadata:{role}}},error:null}),
    updateUserById:async()=>{appels.push({nom:'ban'});return{error:null};},
  }}};
  const user={rpc:async(nom:string)=>{
    expect(nom).toBe(role==='SOIGNANT'?'fn_supprimer_compte_rate_limited':'fn_supprimer_compte_etablissement_rate_limited');
    appels.push({nom});return{data:'rpc'in options?options.rpc:{success:true},error:null};
  }};
  const modules:Record<string,unknown>={
    'npm:@supabase/supabase-js@2.99.2':{createClient:(_url:string,key:string)=>key==='service'?admin:user},
    '../_shared/cors.ts':{jsonResponse:(_req:Request,data:unknown,status=200)=>new Response(JSON.stringify(data),{status})},
    '../_shared/admin-auth.ts':{verifyUserOrServiceRole:async()=>({ok:true,isServiceRole:false,userId,role:role==='SOIGNANT'?role:'ADMIN_ETABLISSEMENT'})},
    '../_shared/rate-limit.ts':{applyRateLimit:()=>false,getClientIp:()=> '127.0.0.1'},
  };
  runInNewContext(source,{exports:{},require:(nom:string)=>{if(!(nom in modules))throw new Error(`Import imprévu ${nom}`);return modules[nom];},
    Deno:{env:{get:(cle:string)=>({SUPABASE_URL:'https://example.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service'}[cle])},serve:(h:typeof handler)=>{handler=h;}},
    Date,Request,Response,Promise,console:{warn(){},error(){}},fetch:()=>{throw new Error('Réseau interdit');}});
  return{appels,lancer:()=>handler(new Request('https://example.invalid/delete-account',{method:'POST',headers:{Authorization:'Bearer jeton-simule'}}))};
}
describe.each(['SOIGNANT','ETABLISSEMENT'] as const)('Suppression %s : le marqueur de suspension ne vaut pas anonymisation',role=>{
  it('appelle la RPC et exige une preuve serveur malgré supprime_le déjà renseigné',async()=>{
    const s=simulation(role);const r=await s.lancer();expect(r.status).toBe(200);
    expect(await r.json()).toMatchObject({success:true,auth_deleted:true});
    expect(s.appels.map(a=>a.nom)).toEqual([role==='SOIGNANT'?'fn_supprimer_compte_rate_limited':'fn_supprimer_compte_etablissement_rate_limited',
      'fn_anonymisation_compte_confirmee','signOut','deleteUser']);
    expect(s.appels[1].p).toEqual({p_utilisateur_id:'69400000-0000-4000-8000-000000000099',p_type_profil:role});
  });
  it.each([false,null,'true'])('refuse de supprimer Auth si la preuve vaut %j, même après success RPC',async preuve=>{
    const s=simulation(role,{preuve});const r=await s.lancer();expect(r.status).toBe(503);
    expect(await r.json()).toMatchObject({success:false,auth_deleted:false,error_code:'ANONYMISATION_NON_CONFIRMEE'});
    expect(s.appels.some(a=>['signOut','deleteUser','ban'].includes(a.nom))).toBe(false);
  });
  it('une erreur de vérification garde Auth intact',async()=>{
    const s=simulation(role,{erreurPreuve:true});expect((await s.lancer()).status).toBe(503);
    expect(s.appels.some(a=>a.nom==='deleteUser')).toBe(false);
  });
  it.each([null,{}, {success:false},{error:'Demande de suppression déjà en cours.'}])('une RPC non concluante ne poursuit aucune étape Auth : %j',async rpc=>{
    const s=simulation(role,{rpc});const r=await s.lancer();expect(r.status).toBe(409);
    expect((await r.json()).success).toBe(false);expect(s.appels).toHaveLength(1);
  });
  it('une reprise reconnue en base reste soumise à la preuve avant finalisation',async()=>{
    const s=simulation(role,{rpc:{success:true,deja_anonymise:true}});expect((await s.lancer()).status).toBe(200);
    expect(s.appels.map(a=>a.nom)).toContain('fn_anonymisation_compte_confirmee');
    expect(s.appels.at(-1)?.p).toEqual({id:'69400000-0000-4000-8000-000000000099',soft:true});
  });
  it('échec Auth après anonymisation reste un état partiel explicite',async()=>{
    const s=simulation(role,{erreurAuth:true});const r=await s.lancer();expect(r.status).toBe(503);
    const body=await r.json();expect(body.error_code).toBe('AUTH_DELETE_PENDING');expect(body.success).not.toBe(true);
    expect(s.appels.map(a=>a.nom)).toContain('ban');
  });
});
