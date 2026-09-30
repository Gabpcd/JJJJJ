import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { parse } from 'yaml';
import { configurationFrontendD,identitesFrontendD,requeteFrontendD,budgetEcrituresD,sqlAuditsFrontendD,verifierAuditsD,STAGING_REF,STAGING_URL,ORIGINE_UI } from '../../scripts/ci/candidatures-ui-contract.mjs';
import { executerFrontendD,diagnosticD,lireBackendD,verifierReponseFrontendD,installerReseauD,parcourirFrontendD } from '../../scripts/ci/recette-candidatures-staging.mjs';
const now=Date.parse('2026-09-30T12:00:00Z');
const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_RUN_ID:'555',GITHUB_RUN_ATTEMPT:'2',GITHUB_SHA:'a'.repeat(40),RUNNER_TEMP:'/private/tmp/d2-test',
  LOAD_D_FRONTEND_ONLY:'true',LOAD_D_JOUR:'2026-10-07',LOAD_D_SQL_ONLY:'false',LOAD_D_SQL_JOUR:'',LOAD_TEST_SCENARIO:'04-candidatures-simultanees',DASHBOARD_FIXTURE_ONLY:'false',DIAGNOSTIC_SQL:'false',STAGING_SUPABASE_PROJECT_REF:STAGING_REF,STAGING_SUPABASE_URL:STAGING_URL,STAGING_SUPABASE_ACCESS_TOKEN:'CANARI_MANAGEMENT'};
const m=configurationFrontendD(env,now).m;
const identites=m.membres.map(a=>({...a,password:`CANARI_MOT_DE_PASSE_32_CARACTERES_${a.slot}`}));
const prive={...env,LOAD_CANDIDATURES_JSON:JSON.stringify({...m,identites})};
const audits=phase=>m.membres.map(a=>({slot:a.slot,total:phase==='avant'?0:a.slot===2?2:1,connexions:phase==='avant'?0:1,consultation:phase==='avant'||a.slot<2?0:1,activite:phase==='cleanup'||a.slot===2?null:true,activite_empreinte:phase==='cleanup'||a.slot===2?null:(phase==='avant'?'a':'b').repeat(32),presences:0,push:0,emails:0}));
test('refus paramètres avant tout accès, aucune identité de repli ni volume configurable',async()=>{
  for(const delta of [{GITHUB_ACTIONS:'false'},{GITHUB_EVENT_NAME:'push'},{GITHUB_REPOSITORY:'autre/repo'},{GITHUB_SHA:'main'},{GITHUB_RUN_ATTEMPT:'0'},
    {LOAD_D_FRONTEND_ONLY:'false'},{LOAD_D_SQL_ONLY:'true'},{LOAD_D_SQL_JOUR:'2026-10-07'},{LOAD_TEST_SCENARIO:'all'},{LOAD_TEST_SCENARIO:'05-dashboard-concurrent'},
    {LOAD_TEST_VUS:'2'},{LOAD_TEST_DURATION:'1m'},{LOAD_FIXTURE_COUNT:'2'},{DASHBOARD_FIXTURE_ONLY:'true'},{DIAGNOSTIC_SQL:'true'},
    {STAGING_SUPABASE_PROJECT_REF:'flripxtsyegjshnhzjkz'},{STAGING_SUPABASE_URL:'https://prod.invalid'},{LOAD_D_JOUR:'2026-09-30'},{LOAD_D_JOUR:'2026-12-30'},{LOAD_D_JOUR:'2026-10-32'},{RUNNER_TEMP:'relative'}]){
    let appels=0;await assert.rejects(()=>executerFrontendD({action:'prepare',env:{...env,...delta},now,fixture:async()=>{appels++;},save:()=>{}}));assert.equal(appels,0);
  }
  const c=configurationFrontendD({...env,LOAD_D_MANIFEST:'tests/load/results/secret.json',LOAD_TEST_RUN_ID:'autre'},now);
  assert.equal(c.env.LOAD_TEST_RUN_ID,'ui-d2-ci-555-2');assert.equal(c.env.LOAD_D_MANIFEST,'/private/tmp/d2-test/d2-frontend-manifest.json');
});
test('trois identités privées exactes, sans mot de passe partagé, champ extra ou autre run',()=>{
  assert.deepEqual(identitesFrontendD(prive,m),identites);
  for(const modifier of [d=>d.identites.pop(),d=>d.identites[1].password=d.identites[0].password,d=>d.identites[1].userId=d.identites[0].userId,d=>d.runId='autre',d=>d.identites[0].access_token='CANARI',d=>d.identites[2].role='SOIGNANT']){
    const data=JSON.parse(prive.LOAD_CANDIDATURES_JSON);modifier(data);assert.throws(()=>identitesFrontendD({...env,LOAD_CANDIDATURES_JSON:JSON.stringify(data)},m));
  }
});
const req=(path,method='GET',body,a=identites[0],origin=STAGING_URL)=>requeteFrontendD({url:origin+path,method,body},a,m);
const postuler={p_mission_id:m.missionId,p_action:'POSTULER',p_creneaux_confirmes:[{debut:m.debut,fin:m.fin}],p_message:m.marker,p_choix_contrat:null,p_candidature_id:null};
test('réseau : seul POSTULER exact par AS, aucun tiers/paiement/présence/réinitialisation',()=>{
  assert.equal(req('/auth/v1/token?grant_type=password','POST',{email:identites[0].email,password:identites[0].password,gotrue_meta_security:{}}),true);
  assert.equal(req('/rest/v1/rpc/fn_confirmer_action_planning_v1','POST',postuler),true);
  for(const body of [{...postuler,p_action:'ACCEPTER'},{...postuler,p_message:'autre'},{...postuler,p_mission_id:m.preuveId},{...postuler,p_creneaux_confirmes:[]},{...postuler,p_choix_contrat:'LIBERAL'}])assert.equal(req('/rest/v1/rpc/fn_confirmer_action_planning_v1','POST',body),false);
  assert.equal(req('/rest/v1/rpc/fn_confirmer_action_planning_v1','POST',postuler,identites[2]),false);
  for(const path of ['/auth/v1/signup','/auth/v1/logout','/auth/v1/recover','/functions/v1/send-email','/rest/v1/rpc/fn_update_presence','/rest/v1/rpc/fn_obtenir_conversation','/rest/v1/rpc/fn_accepter_mission'])assert.equal(req(path,'POST',{}),false);
  assert.equal(req('/rest/v1/notifications','PATCH',{lue:true}),false);
  assert.equal(req('/rest/v1/soignants?id=eq.'+identites[1].userId),false);
  assert.equal(req('/rest/v1/missions?id=eq.'+m.missionId),true);
  assert.equal(req('/rest/v1/missions'),false);
  assert.equal(req('/assets/main.js','GET',undefined,identites[0],ORIGINE_UI),true);
  assert.equal(req('/sdk.js','GET',undefined,identites[0],'https://js.stripe.com'),false);
  assert.equal(req('/rest/v1/missions','GET',undefined,identites[0],'https://flripxtsyegjshnhzjkz.supabase.co'),false);
});
test('budget consommé avant transport : aucun rejeu login/candidature, même si réponse perdue',()=>{
  for(const a of identites){const b=budgetEcrituresD(a);assert.equal(b.complet(),false);for(const n of ['auth-token','fn_audit_connexion',...(a.slot<2?['fn_maj_activite_soignant','fn_confirmer_action_planning_v1']:['fn_ecrire_audit_safe'])]){b.consommer(n);assert.throws(()=>b.consommer(n));}assert.equal(b.complet(),true);assert.throws(()=>b.consommer('fn_update_presence'));}
});
test('créneaux PostgREST +00:00 : mêmes instants acceptés, fuseau absent/voisin/microseconde ou clé extra refusés',()=>{
  const c={debut:'2026-10-07T09:00:00+00:00',fin:'2026-10-07T13:00:00+00:00'};
  assert.equal(req('/rest/v1/rpc/fn_confirmer_action_planning_v1','POST',{...postuler,p_creneaux_confirmes:[c]}),true);
  for(const creneaux of [[{...c,debut:'2026-10-07T09:00:00'}],[{...c,debut:'2026-10-07T09:01:00Z'}],[{...c,debut:'2026-10-07T09:00:00.000001Z'}],[{...c,est_pause:false}],[c,c],[]])
    assert.equal(req('/rest/v1/rpc/fn_confirmer_action_planning_v1','POST',{...postuler,p_creneaux_confirmes:creneaux}),false);
});
test('interception installée avant page, deuxième écriture bloquée avant fetch et secrets absents du diagnostic',async()=>{
  let handler,fetches=0,aborts=0;const ordre=[];const d=diagnosticD();d.phase('postuler',0);
  const context={addInitScript:async()=>ordre.push('init'),routeWebSocket:async(pattern,close)=>{ordre.push('websocket');let closed=0;close({close:()=>closed++});assert.equal(closed,1);},on:()=>{},route:async(pattern,h)=>{ordre.push('route');handler=h;}};
  await installerReseauD(context,identites[0],m,d);assert.deepEqual(ordre,['init','websocket','route']);
  const route={request:()=>({url:()=>STAGING_URL+'/rest/v1/rpc/fn_confirmer_action_planning_v1',method:()=>'POST',postData:()=>'yes',postDataJSON:()=>postuler}),fetch:async options=>{fetches++;assert.equal(options.maxRedirects,0);assert.equal(options.maxRetries,0);throw Error('CANARI_ERREUR_FOURNISSEUR');},abort:async()=>aborts++};
  await handler(route);await handler(route);assert.equal(fetches,1);assert.equal(aborts,2);assert.equal(d.resultat().erreurs,2);assert.doesNotMatch(JSON.stringify(d.resultat()),/CANARI|password|https?:\/\//);
});
test('réponses d’Auth et de candidature doivent confirmer la bonne identité, pas seulement HTTP200',()=>{
  const user={id:identites[0].userId,email:identites[0].email,app_metadata:{role:'SOIGNANT',est_compte_test:true,is_test_playwright:true,load_fixture_kind:'CANDIDATURES_D2',load_fixture_run:m.runId}};
  verifierReponseFrontendD({path:'/auth/v1/token',data:{access_token:'CANARI_JWT',user}},identites[0],m);
  assert.throws(()=>verifierReponseFrontendD({path:'/auth/v1/token',data:{access_token:'CANARI_JWT',user:{...user,id:identites[1].userId}}},identites[0],m));
  for(const data of [{success:false},{success:true},{success:true,choix_contrat:'SALARIE',profession_requise:'AS',docs_a_completer:false,candidature_id:m.preuveId}])assert.throws(()=>verifierReponseFrontendD({path:'/rest/v1/rpc/fn_confirmer_action_planning_v1',data},identites[0],m));
});
test('audits exacts conservés : trois connexions, consultation établissement, aucun effet présence/email/push',()=>{
  verifierAuditsD(audits('avant'),'avant');verifierAuditsD(audits('apres'),'apres',audits('avant'));verifierAuditsD(audits('cleanup'),'cleanup',audits('apres'));
  for(const change of [{total:2},{connexions:0},{presences:1},{emails:1},{push:1},{activite:false},{activite_empreinte:'a'.repeat(32)}])assert.throws(()=>verifierAuditsD([{...audits('apres')[0],...change},...audits('apres').slice(1)],'apres',audits('avant')));
  assert.throws(()=>verifierAuditsD(audits('avant').map(r=>({...r,activite:null})),'cleanup',audits('apres')));
  assert.doesNotMatch(sqlAuditsFrontendD(m),/DELETE\s|UPDATE\s|INSERT\s|ip_acteur|navigateur_acteur|encrypted_password|access_token|refresh_token/i);
});
test('lecture backend refus réseau/JSON/HTTP ne fuit jamais le corps, zéro retry',async()=>{
  for(const forme of ['throw','http','json']){let n=0;await assert.rejects(()=>lireBackendD('SELECT 1',env,async()=>{n++;if(forme==='throw')throw Error('CANARI_SECRET');return{ok:forme!=='http',json:async()=>{throw Error('CANARI_SECRET');}};}),e=>!e.message.includes('CANARI'));assert.equal(n,1);}
});
test('échec navigateur conserve résultat fermé ; snapshot et cleanup restent appelables sans credentials UI',async()=>{
  const saved={};const common={env:prive,now,save:(k,v)=>saved[k]=v};let closed=false;
  await assert.rejects(()=>executerFrontendD({...common,action:'run',fixture:async()=>({}),sql:async()=>audits('avant'),naviguer:async()=>{try{throw Error('CANARI_NAV');}finally{closed=true;}}}));
  assert.equal(closed,true);assert.equal(saved.resultat.succes,false);assert.doesNotMatch(JSON.stringify(saved),/CANARI/);
  await executerFrontendD({...common,env,action:'snapshot',sql:async()=>audits('avant')});
  let cleanup=0;await executerFrontendD({...common,env,action:'cleanup',fixture:async({action})=>{assert.equal(action,'cleanup');cleanup++;return{skipped:false};}});assert.equal(cleanup,1);
});
test('échec page : le vrai finally ferme contexte puis navigateur et preview avant de rendre la main au cleanup',async()=>{
  const ordre=[];
  const context={addInitScript:async()=>{},routeWebSocket:async()=>{},on:()=>{},route:async()=>{},close:async()=>ordre.push('contexte-ferme'),
    newPage:async()=>({setDefaultTimeout:()=>{},setDefaultNavigationTimeout:()=>{},goto:async()=>{ordre.push('page');throw Error('CANARI_PAGE');}})};
  const browser={newContext:async()=>context,close:async()=>ordre.push('navigateur-ferme')};
  await assert.rejects(()=>parcourirFrontendD({m,identites,env,diagnostic:diagnosticD(),preparerBuild:()=>ordre.push('build'),previewFn:async()=>({kill:()=>ordre.push('preview-stop')}),
    chargerPlaywright:async()=>({webkit:{launch:async options=>{assert.deepEqual(options.env,{});assert.doesNotMatch(JSON.stringify(options),/CANARI|SUPABASE|LOAD_CANDIDATURES/);return browser;}},devices:{},expect:{}})}));
  ordre.push('cleanup-possible');assert.deepEqual(ordre,['build','page','contexte-ferme','navigateur-ferme','preview-stop','cleanup-possible']);
});
test('succès orchestré exige corrélation UI/backend et audit avancé, rapport sans IDs/password/JWT',async()=>{
  for(const voisin of [false,true]){
    const saved={};let lecture=0,ferme=false;
    const cands=m.membres.slice(0,2).map((a,slot)=>({slot,id:slot?m.preuveId:m.nettoyageId}));
    const resultat=()=>executerFrontendD({action:'run',env:prive,now,save:(k,v)=>saved[k]=v,
      sql:async()=>audits(lecture++?'apres':'avant'),naviguer:async()=>{ferme=true;return{preuves:[],candidatures:cands};},
      fixture:async({action})=>{if(action==='catalogue')return{};assert.equal(ferme,true);return{notifications:4,candidatures:cands.map(c=>({id:c.id,soignant_id:m.membres[voisin?1-c.slot:c.slot].userId}))};}});
    if(voisin)await assert.rejects(resultat);else assert.deepEqual(await resultat(),{succes:true,candidatures:2});
    assert.equal(saved.resultat.succes,!voisin);assert.doesNotMatch(JSON.stringify(saved),/CANARI|access_token|password/);
    for(const a of identites)assert.ok(!JSON.stringify(saved).includes(a.userId));
  }
});
const workflow=parse(readFileSync('.github/workflows/load-tests.yml','utf8'));
const defaults=Object.fromEntries(Object.entries(workflow.on.workflow_dispatch.inputs).map(([k,v])=>[k,v.default]));
const selection=inputs=>Object.entries(workflow.jobs).filter(([,job])=>Function('inputs',`return (${job.if.replace(/^\$\{\{\s*|\s*\}\}$/g,'')});`)(inputs)).map(([id])=>id);
test('routage des entrées UI exclusif même date seule/combinations malformées, k6/SQL/E jamais simultanés',()=>{
  for(const scenario of ['all','04-candidatures-simultanees','05-dashboard-concurrent'])for(const flags of [{candidatures_frontend_only:true},{candidatures_frontend_date:'2026-10-07'},{candidatures_frontend_only:true,candidatures_sql_only:true,dashboard_fixture_only:true}])assert.deepEqual(selection({...defaults,scenario,...flags}),['candidatures-frontend']);
  assert.deepEqual(workflow.concurrency,{group:'jolene-supabase-staging-writes','cancel-in-progress':false});
  assert.deepEqual(Object.keys(workflow.on),['workflow_dispatch']);
});
test('workflow ordonne check/catalogue/build/preview/prepare/UI/snapshot/cleanup et exclut le manifeste privé des artifacts',()=>{
  const job=workflow.jobs['candidatures-frontend'],steps=job.steps;
  const ix=action=>steps.findIndex(s=>s.run===`node scripts/ci/recette-candidatures-staging.mjs ${action}`);
  for(const [a,b]of [['check','catalogue'],['catalogue','verify-preview'],['verify-preview','prepare'],['prepare','run'],['run','snapshot'],['snapshot','cleanup'],['cleanup','verify-cleanup']])assert.ok(ix(a)<ix(b));
  assert.ok(steps.findIndex(s=>s.run==='npm run build')<ix('prepare'));
  assert.equal(steps[ix('check')].env,undefined);assert.equal(job.env.STAGING_SUPABASE_URL,STAGING_URL);
  assert.equal(steps[ix('cleanup')].if,"always() && steps.prepare.outcome != 'skipped'");assert.equal(steps[ix('snapshot')].if,steps[ix('cleanup')].if);
  assert.equal(steps.at(-1).with.path,'tests/load/results/d2-frontend/');
  assert.doesNotMatch(JSON.stringify(job),/k6 run|apply.*migration|db push|deploy-supabase|recordHar|storageState/);
});
