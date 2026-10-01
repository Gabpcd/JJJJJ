import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { webcrypto, createHash } from 'node:crypto';
import ts from 'typescript';

const read = path => readFileSync(path, 'utf8');
const worker = read('supabase/functions/process-externalisation-actions/index.ts');
function extract(source, names) {
  const ast = ts.createSourceFile('production.ts',source,ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);
  const selected=ast.statements.filter(s=>ts.isFunctionDeclaration(s)&&names.includes(s.name?.text));
  assert.equal(selected.length,names.length,'Toutes les vraies fonctions doivent être extraites');
  return ts.transpile(selected.map(s=>s.getText(ast)).join('\n'), {target:ts.ScriptTarget.ES2022});
}
const uuid = n => `71100000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const payload = {destinataire_id:uuid(1),type_evenement:'CANDIDATURE_RECUE',mission_id:uuid(2),titre:'Nouvelle candidature',corps:'Une candidature a été reçue.',lien:`/etablissement/missions/${uuid(2)}`,data:{candidature_id:uuid(3),mission_id:uuid(2),soignant_id:uuid(4),etablissement_id:uuid(5),notification_id:uuid(6)}};
const action = () => ({id:uuid(7),source:'AUTRE',source_id:uuid(3),type_action:'PUSH_CANDIDATURE_RECUE',payload:structuredClone(payload)});
test('déploiement : le dispatch ancien exact refuse le nouveau type sans relais', async()=>{
 const ast=ts.createSourceFile('worker.ts',worker,ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);
 const current=ast.statements.find(s=>ts.isFunctionDeclaration(s)&&s.name?.text==='dispatch').getText(ast);
 const old=current.replace('    case "PUSH_CANDIDATURE_RECUE":\n','');
 assert.equal(createHash('sha256').update(old).digest('hex'),'4aeea8438fcf0bde13dbb7add1e4a8d05bbd9a8ea391b0770fc0209a80a2c70f','Dispatch ancien dfd62dfb byte-identique');
 for(const [source,expected] of [[old,false],[current,true]]){
  let calls=0;const ctx=vm.createContext({dispatchPush:async()=>{calls++;return {ok:true};}});
  vm.runInContext(ts.transpile(source,{target:ts.ScriptTarget.ES2022})+'\nglobalThis.run=dispatch;',ctx);
  const result=await ctx.run({},action());assert.equal(result.ok,expected);assert.equal(calls,expected?1:0);
 }
});
const migration=read('supabase/migrations/20261001142707_relayer_nouvelles_candidatures_push.sql');
test('déploiement : les deux capacités de claim gardent batch, ordre et verrou',()=>{
 const claims=[...migration.matchAll(/CREATE OR REPLACE FUNCTION public\.fn_externalisations_a_traiter\(([^\n]+)\)[\s\S]*?AS \$function\$([\s\S]*?)\$function\$/g)];
 assert.equal(claims.length,2);
 assert.equal((claims[0][2].match(/a\.type_action <> 'PUSH_CANDIDATURE_RECUE'/g)||[]).length,3);
 assert.match(claims[1][1],/p_push_candidature_v1 boolean$/);assert(!claims[1][1].includes('DEFAULT'));
 for(const [, ,body] of claims){assert.match(body,/ORDER BY a\.cree_le ASC\s+LIMIT p_limit\s+FOR UPDATE SKIP LOCKED/);}
 assert.match(migration,/REVOKE ALL ON FUNCTION public\.fn_externalisations_a_traiter\(integer,text,boolean\) FROM PUBLIC,anon,authenticated/);
 assert.match(worker,/p_limit: 50,[\s\S]*?p_push_candidature_v1: true/);
});
for(const [name,expected] of [['fn_postuler_mission','6770643ffacca5cf53251eb5ee2417ec'],['fn_enregistrer_swipe','e6f173ea468fe85e0c1a34458bd26ba8']])test(`producteur ${name} : logique métier LIVE conservée hors liaison/enfilage`,()=>{
 let definition=migration.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\$function\\$[\\s\\S]*?\\$function\\$`))[0];
 definition=definition.replace('  v_notification_id uuid;\n','').replace(/,\s*type_ressource,\s*id_ressource/g,'');
 definition=definition.replace(/, 'candidature', v_candidature_id\s*\) RETURNING id INTO v_notification_id;\s*PERFORM private\.fn_enfiler_push_candidature_recue\(v_candidature_id, v_notification_id\);/g,');');
 assert.equal(createHash('md5').update(definition.replace(/\s+/g,'')).digest('hex'),expected);
});
async function dispatch({preparation={eligible:true,payload:structuredClone(payload)},error=null,row=action(),failure=false}={}) {
  const rpc=[],sends=[];
  const ctx=vm.createContext({SUPABASE_URL:'https://push-recette.invalid',SERVICE_ROLE_KEY:'fictif',fetch:async(url,init)=>{sends.push({url,body:JSON.parse(init.body)});if(failure)throw Error('transport');return new Response(JSON.stringify({success:true,sent:1}),{status:200});},validatePushResponse:async r=>({ok:true,data:await r.json()})});
  vm.runInContext(extract(worker,['dispatchPush'])+'\nglobalThis.run=dispatchPush;',ctx);
  const result=await ctx.run({rpc:async(name,args)=>{rpc.push({name,args});return {data:preparation,error};}},row);
  return JSON.parse(JSON.stringify({result,rpc,sends}));
}
test('worker : action exacte revalidée puis clef stable et payload canonique au relais',async()=>{
  const r=await dispatch();assert.equal(r.result.ok,true);assert.deepEqual(r.rpc,[{name:'fn_preparer_push_candidature_recue',args:{p_action_id:uuid(7)}}]);
  assert.equal(r.sends.length,1);assert.equal(r.sends[0].url,'https://push-recette.invalid/functions/v1/send-push');
  assert.deepEqual(r.sends[0].body,{destinataire_id:payload.destinataire_id,titre:payload.titre,corps:payload.corps,lien:payload.lien,data:payload.data,type_evenement:payload.type_evenement,idempotency_key:`externalisation.${uuid(7)}.push`});
  assert.deepEqual((await dispatch()).sends,r.sends,'Une reprise garde la même clé, pas une nouvelle notification');
});
for (const raison of ['source_inactive','destinataire_inactif','preference_desactivee']) test(`worker : ${raison} acquitté sans appel relay`,async()=>{
 const r=await dispatch({preparation:{eligible:false,raison}});assert.equal(r.sends.length,0);assert.deepEqual(r.result,{ok:true,resultat:{skipped:true,reason:raison}});
});
for (const preparation of [null,[],{},true,{eligible:false,raison:'texte libre secret'},{eligible:true,payload:[]}]) test(`worker : forme fermée ${JSON.stringify(preparation)}`,async()=>{
 const r=await dispatch({preparation});assert.equal(r.result.ok,false);assert.equal(r.sends.length,0);assert(!JSON.stringify(r.result).includes('secret'));
});
for (const mutation of ['destination','mission','candidature','extra','lien','corps','data']) test(`worker : provenance altérée ${mutation} sans transport`,async()=>{
 const p=structuredClone(payload);if(mutation==='destination')p.destinataire_id=uuid(90);if(mutation==='mission')p.mission_id=uuid(90);if(mutation==='candidature')p.data.candidature_id=uuid(90);if(mutation==='extra')p.secret='CANARI';if(mutation==='lien')p.lien='https://externe.invalid';if(mutation==='corps')p.corps='x'.repeat(501);if(mutation==='data')p.data={};
 const r=await dispatch({preparation:{eligible:true,payload:p}});assert.equal(r.result.ok,false);assert.equal(r.sends.length,0);assert(!JSON.stringify(r.result).includes('CANARI'));
});
test('worker : erreur SQL expurgée ; pas de succès ni de retry fournisseur',async()=>{const r=await dispatch({error:{message:'CANARI_SQL'}});assert.equal(r.result.ok,false);assert.equal(r.sends.length,0);assert(!JSON.stringify(r.result).includes('CANARI'));await assert.rejects(()=>dispatch({failure:true}),/transport/);});
test('worker : une autre source refusée, un autre événement inchangé',async()=>{
 const row=action();row.source='LITIGE_EXEC';const refused=await dispatch({row});assert.equal(refused.result.ok,false);assert.equal(refused.rpc.length,0);assert.equal(refused.sends.length,0);
 row.type_action='PUSH_NOTIF';row.payload.type_evenement='CONTRAT_A_SIGNER';const other=await dispatch({row});assert.equal(other.result.ok,true);assert.equal(other.rpc.length,0);assert.equal(other.sends.length,1);
});

// Exécuter le vrai handler, avec tout transport remplacé localement. Aucun
// token existant, secret, appel réseau ou fournisseur réel n'est lu/contacté.
async function handler({platforms=['WEB','IOS','ANDROID'],preference=true,classification={ok:true,isTest:false},reservation='RESERVE',failPlatform=null}={}) {
 const requests=[],effects=[],rpc=[];let serve;
 const sa={client_email:'push@example.invalid',project_id:'fictif',private_key:'-----BEGIN PRIVATE KEY-----\nAA==\n-----END PRIVATE KEY-----'};
 const env={SUPABASE_URL:'https://push-recette.invalid',SUPABASE_SERVICE_ROLE_KEY:'fictif',SUPABASE_ANON_KEY:'fictif',VAPID_PUBLIC_KEY:'fictif',VAPID_PRIVATE_KEY:'fictif',FIREBASE_SERVICE_ACCOUNT_JSON:JSON.stringify(sa)};
 const tokens=platforms.map((plateforme,i)=>({id:uuid(20+i),plateforme,token:'fictif',endpoint:'https://fcm.googleapis.com/fictif',p256dh:'fictif',auth_key:'fictif'}));
 const client={rpc:async(name,args)=>{rpc.push({name,args});if(name==='fn_doit_notifier')return {data:preference,error:null};if(name==='fn_reserver_envoi_push_idempotent')return {data:{statut:reservation},error:null};if(name==='fn_finaliser_envoi_push_idempotent')return {data:null,error:null};throw Error('RPC inattendue '+name);},from:table=>{const query={select(){return this;},eq(){return this;},in(){return this;},update(){return this;},insert(){return this;},then(resolve){assert(['tokens_push','journaux_audit'].includes(table));return Promise.resolve({data:table==='tokens_push'?tokens:null,error:null}).then(resolve);}};return query;}};
 const ctx=vm.createContext({Request,Response,URL,URLSearchParams,TextEncoder,Uint8Array,atob,btoa,console:{log(){},error(){},warn(){}},Deno:{env:{get:key=>env[key]},serve:fn=>{serve=fn;}},createClient:()=>client,
  crypto:{subtle:{digest:(...a)=>webcrypto.subtle.digest(...a),importKey:async()=>({}),sign:async()=>new Uint8Array([1,2,3])}},
  webpush:{setVapidDetails(){},sendNotification:async(_subscription,body)=>{effects.push({platform:'WEB',body:JSON.parse(body)});if(failPlatform==='WEB')throw Error('provider unavailable');}},apnsConfigured:()=>true,sendApns:async data=>{effects.push({platform:'IOS',body:data});return {ok:failPlatform!=='IOS',expired:false,error:'provider unavailable'};},
  corsHeaders:()=>({}),preflightResponse:()=>new Response('',{status:204}),jsonResponse:(_req,body,status=200)=>new Response(JSON.stringify(body),{status}),verifyUserOrServiceRole:async()=>({ok:true,isServiceRole:true}),verifyAdminOrServiceRole:async()=>({ok:true}),applyRateLimit:()=>false,getClientIp:()=>'',resolveOperationalTestAccount:async()=>classification,resolveOperationalTestSource:async()=>({ok:true,isTest:false}),
  fetch:async(url,init)=>{requests.push(url);if(url==='https://oauth2.googleapis.com/token')return Response.json({access_token:'fictif',expires_in:3600});assert.equal(url,'https://fcm.googleapis.com/v1/projects/fictif/messages:send');effects.push({platform:'ANDROID',body:JSON.parse(init.body)});return new Response('{}',{status:failPlatform==='ANDROID'?503:200});}});
 const ast=ts.createSourceFile('send-push.ts',read('supabase/functions/send-push/index.ts'),ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);
 const source=ast.statements.filter(s=>!ts.isImportDeclaration(s)).map(s=>s.getText(ast)).join('\n');
 vm.runInContext(ts.transpile(source,{target:ts.ScriptTarget.ES2022}),ctx);
 const response=await serve(new Request('https://push-recette.invalid/functions/v1/send-push',{method:'POST',body:JSON.stringify({...payload,idempotency_key:`externalisation.${uuid(7)}.push`})}));
 return {status:response.status,body:await response.json(),effects,requests,rpc};
}
for(const platform of ['WEB','IOS','ANDROID'])test(`handler réel : routage ${platform} simulé, IDs/lien transmis`,async()=>{
 const r=await handler({platforms:[platform]});assert.equal(r.status,200);assert.equal(r.body.success,true);assert.equal(r.effects.length,1);assert.equal(r.effects[0].platform,platform);
 const data=platform==='ANDROID'?r.effects[0].body.message.data:r.effects[0].body.data;assert.equal(data.candidature_id,uuid(3));assert.equal(data.notification_id,uuid(6));assert.equal(data.lien,payload.lien);assert.equal(data.type_evenement,'CANDIDATURE_RECUE');
 assert.equal(r.rpc.filter(x=>x.name==='fn_finaliser_envoi_push_idempotent')[0].args.p_statut,'ENVOYE');
});
test('handler réel : préférences et comptes TEST arrêtent avant tokens/fournisseurs',async()=>{
 for(const args of [{preference:false},{classification:{ok:true,isTest:true}},{classification:{ok:false,error:'inconnu'}}]){const r=await handler(args);assert.equal(r.effects.length,0);assert.equal(r.requests.length,0);assert.equal(r.rpc.filter(x=>x.name==='fn_reserver_envoi_push_idempotent').length,0);}
});
for(const reservation of ['DEJA_ENVOYE','EN_COURS','INDETERMINE'])test(`handler réel : réservation ${reservation} ne renvoie rien`,async()=>{const r=await handler({reservation});assert.equal(r.effects.length,0);assert.equal(r.status,reservation==='DEJA_ENVOYE'?200:202);});
test('handler réel : erreur fournisseur ambiguë reste rouge sans retry',async()=>{const r=await handler({platforms:['IOS'],failPlatform:'IOS'});assert.notEqual(r.status,200);assert.equal(r.effects.length,1);assert.equal(r.rpc.find(x=>x.name==='fn_finaliser_envoi_push_idempotent').args.p_statut,'INDETERMINE');});
