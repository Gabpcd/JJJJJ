import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { parse } from 'yaml';
import { configurationFrontendD,identitesFrontendD,requeteFrontendD,budgetEcrituresD,sqlAuditsFrontendD,verifierAuditsD,STAGING_REF,STAGING_URL,ORIGINE_UI } from '../../scripts/ci/candidatures-ui-contract.mjs';
import { executerFrontendD,diagnosticD,lireBackendD,verifierReponseFrontendD,installerReseauD,parcourirFrontendD,projeterErreurNavigateurD,observerErreursNavigateurD,deposerCandidatureD,concurrenceCandidaturesD,verifierConcurrenceD,envoyerCandidaturesConcurrentesD } from '../../scripts/ci/recette-candidatures-staging.mjs';
const now=Date.parse('2026-09-30T12:00:00Z');
const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_RUN_ID:'555',GITHUB_RUN_ATTEMPT:'2',GITHUB_SHA:'a'.repeat(40),RUNNER_TEMP:'/private/tmp/d2-test',
  LOAD_D_FRONTEND_ONLY:'true',LOAD_D_JOUR:'2026-10-07',LOAD_D_SQL_ONLY:'false',LOAD_D_SQL_JOUR:'',LOAD_TEST_SCENARIO:'04-candidatures-simultanees',DASHBOARD_FIXTURE_ONLY:'false',DIAGNOSTIC_SQL:'false',STAGING_SUPABASE_PROJECT_REF:STAGING_REF,STAGING_SUPABASE_URL:STAGING_URL,STAGING_SUPABASE_ACCESS_TOKEN:'CANARI_MANAGEMENT'};
const m=configurationFrontendD(env,now).m;
const identites=m.membres.map(a=>({...a,password:`CANARI_MOT_DE_PASSE_32_CARACTERES_${a.slot}`}));
const prive={...env,LOAD_CANDIDATURES_JSON:JSON.stringify({...m,identites})};
const concurrenceHTTP={slots:[{slot:0,debutMs:10,receptionMs:30},{slot:1,debutMs:11,receptionMs:31}],chevauchementMs:19};
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
test('fenêtre temporelle : création et parcours refusés à 24h, nettoyage exact encore permis',()=>{
  const borne=Date.parse(m.debut)-86400000;
  for(const action of ['check','catalogue','verify-preview','prepare','run']) {
    assert.deepEqual(configurationFrontendD(env,borne-1,action).m,m);
    for(const instant of [borne,borne+1,Date.parse(m.fin)+7*86400000])assert.throws(()=>configurationFrontendD(env,instant,action));
    assert.throws(()=>configurationFrontendD(env,Date.parse(m.debut)-31*86400000-1,action));
  }
  for(const action of ['snapshot','cleanup','verify-cleanup'])for(const instant of [borne-1,borne,borne+1,Date.parse(m.fin)+7*86400000]) {
    const c=configurationFrontendD(env,instant,action);assert.deepEqual(c.m,m);
    assert.equal(c.env.LOAD_TEST_RUN_ID,m.runId);assert.equal(c.env.LOAD_D_MANIFEST,'/private/tmp/d2-test/d2-frontend-manifest.json');
  }
});
test('reprise tardive : contexte, date ISO, types et action restent stricts avant effets',async()=>{
  const tard=Date.parse(m.fin)+7*86400000;
  for(const action of ['snapshot','cleanup','verify-cleanup']) {
    for(const delta of [{LOAD_D_JOUR:'2026-02-30'},{LOAD_D_JOUR:'2026-10-07T09:00:00Z'},{LOAD_D_JOUR:true},{LOAD_D_JOUR:20261007},
      {GITHUB_RUN_ID:'autre'},{GITHUB_RUN_ATTEMPT:'0'},{GITHUB_SHA:'main'},{RUNNER_TEMP:'relative'},
      {STAGING_SUPABASE_PROJECT_REF:'flripxtsyegjshnhzjkz'},{STAGING_SUPABASE_URL:'https://prod.invalid'},
      {LOAD_D_FRONTEND_ONLY:'false'},{LOAD_D_SQL_ONLY:'true'},{LOAD_TEST_VUS:'2'},{GITHUB_EVENT_NAME:'push'}]) {
      let effets=0;const effet=async()=>{effets++;};
      await assert.rejects(()=>executerFrontendD({action,env:{...env,...delta},now:tard,fixture:effet,sql:effet,naviguer:effet,save:()=>{effets++;}}));
      assert.equal(effets,0);
    }
    for(const instant of [NaN,Infinity,'2026-10-15',null])assert.throws(()=>configurationFrontendD(env,instant,action));
  }
  for(const action of ['autre','CLEANUP',null,{},true])assert.throws(()=>configurationFrontendD(env,now,action));
});
test('snapshot, cleanup et vérification restent orchestrés après franchissement de la borne',async()=>{
  const zero={auth:0,profils:0,etablissements:0,missions:0,creneaux:0,preferences:0,notifications:0,limites:0,sessions:0,identites:0,candidatures:[],audits_conserves:6,recu_cleanup:1,inattendus:0};
  for(const instant of [Date.parse(m.debut)-86400000,Date.parse(m.fin)+7*86400000]) {
    const saved={},sqls=[];let nettoyages=0;
    const common={env,now:instant,save:(k,v)=>saved[k]=v,read:()=>audits('apres'),
      sql:async query=>{sqls.push(query);return query===sqlAuditsFrontendD(m)?audits('cleanup'):[zero];},
      fixture:async({action,env:recu})=>{assert.equal(action,'cleanup');assert.equal(recu.LOAD_D_JOUR,m.jour);assert.equal(recu.LOAD_TEST_RUN_ID,m.runId);nettoyages++;return {skipped:false};},
      naviguer:async()=>{throw Error('Aucun navigateur en cleanup');}};
    assert.deepEqual(await executerFrontendD({...common,action:'snapshot'}),{snapshot:true});
    assert.deepEqual(await executerFrontendD({...common,action:'cleanup'}),{nettoye:true});
    assert.deepEqual(await executerFrontendD({...common,action:'verify-cleanup'}),{zeros:true,audits_conserves:true});
    assert.equal(nettoyages,1);assert.equal(sqls.length,3);assert.deepEqual(saved['cleanup-verifie'],{zeros:true,audits_conserves:true});
    for(const action of ['prepare','run'])await assert.rejects(()=>executerFrontendD({...common,action}));
    assert.equal(nettoyages,1);assert.equal(sqls.length,3);
  }
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
test('dashboard établissement : deux lectures sans argument réservées au slot2',()=>{
  for(const rpc of ['fn_mon_score_etab','fn_bfa_info']) {
    const path=`/rest/v1/rpc/${rpc}`;
    assert.equal(req(path,'POST',{},identites[2]),true);
    assert.equal(req(path,'OPTIONS',undefined,identites[2]),true);
    for(const a of identites.slice(0,2)) {
      assert.equal(req(path,'POST',{},a),false);
      assert.equal(req(path,'OPTIONS',undefined,a),false);
    }
    for(const method of ['GET','HEAD','PATCH','PUT','DELETE'])assert.equal(req(path,method,{},identites[2]),false);
    for(const body of [undefined,null,[],{p_annee:2026},{p_etablissement_id:m.membres[2].userId},{extra:true}])assert.equal(req(path,'POST',body,identites[2]),false);
    assert.equal(req(path+'?p_annee=2026','POST',{},identites[2]),false);
    assert.equal(req(path,'POST',{},identites[2],'https://flripxtsyegjshnhzjkz.supabase.co'),false);
  }
  assert.equal(req('/rest/v1/rpc/fn_verser_bfa','POST',{},identites[2]),false);
  assert.equal(req('/rest/v1/rpc/fn_stats_etab_complements','POST',{},identites[2]),false);
});
test('dashboard : métadonnées de la seule mission du manifeste, aucun ID supplémentaire/projection ou OR',()=>{
  const path=`/rest/v1/missions?select=id%2Cnb_creneaux&id=in.%28${m.missionId}%29`;
  assert.equal(req(path),true);
  for(const p of [path.replace(m.missionId,m.preuveId),path.replace(m.missionId,`${m.missionId},${m.preuveId}`),path.replace(m.missionId,`${m.missionId},${m.missionId}`),
    path.replace('id%2Cnb_creneaux','*'),path.replace('id%2Cnb_creneaux','id%2Cnb_creneaux%2Cdescription'),path+'&or=(statut.eq.OUVERTE)',
    path+'&select=id%2Cnb_creneaux',path+'&id=in.('+m.missionId+')',path+'&order=id',path.replace(m.missionId,'')])assert.equal(req(p),false);
  for(const method of ['HEAD','POST','PATCH','DELETE'])assert.equal(req(path,method),false);
  assert.equal(req(path,'GET',undefined,identites[2]),false);
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
test('refus missions : projection fermée de la forme réelle, aucune valeur ni clé libre, toujours bloquant avant fetch',async()=>{
  let handler,aborts=0;const d=diagnosticD(),secret='CANARI_PASSWORD_EMAIL_JWT';
  await installerReseauD({addInitScript:async()=>{},routeWebSocket:async()=>{},on:()=>{},route:async(p,h)=>{handler=h;}},identites[0],m,d);
  const path=STAGING_URL+`/rest/v1/missions?select=id,nb_creneaux&id=in.(${m.missionId})&${secret}=${secret}`;
  await handler({request:()=>({url:()=>path,method:()=>'GET',postData:()=>null}),fetch:async()=>{throw Error('Ne doit pas transporter');},abort:async()=>{aborts++;}});
  assert.equal(aborts,1);assert.equal(d.resultat().erreurs,1);
  assert.deepEqual(d.resultat().reseau[0].requeteMission,{projection:'id_nb_creneaux',selecteur:'in_manifeste',parametresUniques:true,cles:['autre','id','select']});
  d.reseau(STAGING_URL+`/rest/v1/missions?select=${secret}&id=eq.${m.missionId}&id=eq.${secret}`,'GET','refus',m.missionId);
  assert.deepEqual(d.resultat().reseau[1].requeteMission,{projection:'autre',selecteur:'autre',parametresUniques:false,cles:['id','select']});
  d.reseau(STAGING_URL+`/rest/v1/missions?id=eq.${m.missionId}`,'GET','refus',m.missionId);
  assert.equal(d.resultat().reseau[2].requeteMission.selecteur,'eq_manifeste');
  d.reseau(path,'GET',200,m.missionId);assert.equal(d.resultat().reseau[3].requeteMission,undefined);
  assert.doesNotMatch(JSON.stringify(d.resultat()),new RegExp(`${secret}|${m.missionId}|https?:`));
});
test('erreurs navigateur : aucun texte, stack, URL, query ou classe libre ne sort de la projection',()=>{
  const assets=new Set(['/assets/index-public123.js']),secret='CANARI_PASSWORD_JWT_DONNEE';
  const p=projeterErreurNavigateurD({source:'pageerror',texte:`Failed to fetch ${secret}`,classe:'TypeError',
    stack:`TypeError: ${secret}\nfn@${ORIGINE_UI}/assets/index-public123.js?token=${secret}:12:34`},assets);
  assert.equal(p.categorie,'chargement_reseau');assert.equal(p.classe,'TypeError');assert.deepEqual(p.emplacement,{asset:'/assets/index-public123.js',ligne:12,colonne:34});assert.match(p.empreinte,/^[a-f0-9]{64}$/);
  assert.equal(p.empreinte,projeterErreurNavigateurD({texte:`Failed to fetch ${secret}`}).empreinte);
  assert.notEqual(p.empreinte,projeterErreurNavigateurD({texte:'Failed to fetch autre'}).empreinte);
  for(const url of [`https://externe.invalid/assets/index-public123.js?${secret}`,`${ORIGINE_UI}/assets/${secret}.js`,`${ORIGINE_UI}/soignant/${secret}`,`http://user:${secret}@127.0.0.1:4173/assets/index-public123.js`]){
    const other=projeterErreurNavigateurD({source:'console_error',texte:`Minified React error #418; ${secret}`,classe:secret,location:{url,lineNumber:5,columnNumber:6}},assets);
    assert.equal(other.emplacement,null);assert.equal(other.classe,'autre');assert.equal(other.code,418);assert.equal(other.categorie,'react_minifie');assert.doesNotMatch(JSON.stringify(other),/CANARI|https?:|token|stack/);
  }
  assert.doesNotMatch(JSON.stringify(p),/CANARI|https?:|token|stack/);
});
test('listeners réels : slot du contexte conservé après changement de phase, aucune erreur filtrée',()=>{
  const d=diagnosticD(),events=new Map();let pageCreated;
  observerErreursNavigateurD({on:(event,fn)=>{assert.equal(event,'page');pageCreated=fn;}},0,d);
  pageCreated({on:(event,fn)=>events.set(event,fn),isClosed:()=>false});d.phase('postuler',1);
  events.get('pageerror')(new TypeError('Load failed CANARI_1'));
  for(const text of ['The operation was aborted CANARI_2','WebSocket connection failed CANARI_3','Target page, context or browser has been closed CANARI_4','message non classé CANARI_5'])
    events.get('console')({type:()=> 'error',text:()=>text,location:()=>({url:'https://secret.invalid/CANARI_6',lineNumber:1})});
  const r=d.resultat();assert.equal(r.erreurs,5);assert.deepEqual(r.erreursNavigateur.map(e=>e.categorie),['chargement_reseau','requete_abandonnee','websocket','contexte_ferme','autre']);
  assert.ok(r.erreursNavigateur.every(e=>e.slotEmetteur===0&&e.slotPhase===1&&e.phase==='postuler'));assert.doesNotMatch(JSON.stringify(r),/CANARI|secret\.invalid/);
  events.get('console')({type:()=> 'warning',text:()=>{throw Error('Les autres niveaux n’étaient pas capturés.');}});assert.equal(d.resultat().erreurs,5);
});
test('WebKit : le découpage au premier deux-points conserve la cause par enum sans exporter name ni URL',()=>{
  // Même découpage que Playwright WebKit splitErrorMessage, URL à deux-points.
  const split=text=>{const i=text.indexOf(':');return {classe:i<0?'':text.slice(0,i),texte:i>=0&&i+2<=text.length?text.slice(i+2):text};};
  for(const [text,categorie]of [
    ['Fetch API cannot load https://CANARI_EMAIL:CANARI_PASSWORD@api.invalid/private?jwt=CANARI_JWT due to access control checks.','controle_origine'],
    ['WebSocket connection to https://CANARI_EMAIL:CANARI_PASSWORD@api.invalid/private?jwt=CANARI_JWT failed','websocket'],
    ['Failed to load resource: The network connection was lost. CANARI_JWT','chargement_reseau'],
    ['AbortError: CANARI_PASSWORD','requete_abandonnee'],
    ['CANARI_CUSTOM_CLASS: CANARI_IDENTITE','autre']]) {
    const p=projeterErreurNavigateurD({source:'pageerror',...split(text)});
    assert.equal(p.categorie,categorie);assert.match(p.empreinteNom,/^[a-f0-9]{64}$/);
    if(text.startsWith('Fetch API')||text.startsWith('WebSocket')||text.startsWith('Failed to'))assert.equal(p.typeNom,'prefixe_webkit');
    assert.doesNotMatch(JSON.stringify(p),/CANARI|api\.invalid|https?:|jwt=|private\?/);
  }
  const p=projeterErreurNavigateurD({source:'pageerror',classe:'AbortError',texte:'CANARI'});
  assert.equal(p.typeNom,'classe_connue');assert.equal(p.classe,'AbortError');
});
test('horloge relative : ordre erreur/réception et agrégation conservés, recul/NaN/grande valeur bornés',()=>{
  let temps=1000;const d=diagnosticD({temps:()=>temps});
  temps=1010;d.phase('mission',1);d.action('mission_navigation');
  temps=1012;const p=projeterErreurNavigateurD({source:'pageerror',classe:'AbortError',texte:'CANARI'});d.erreurNavigateur(1,p);
  temps=1015;d.reseau(STAGING_URL+'/rest/v1/rpc/fn_note_moyenne','POST',200);
  temps=1020;d.erreurNavigateur(1,p);d.reseau(STAGING_URL+'/rest/v1/rpc/fn_note_moyenne','POST',200);
  const r=d.resultat();assert.equal(r.actionDepuisMs,10);assert.equal(r.erreurs,2);assert.equal(r.erreursNavigateur.length,1);
  assert.deepEqual([r.erreursNavigateur[0].premierMs,r.erreursNavigateur[0].dernierMs,r.erreursNavigateur[0].nombre],[12,20,2]);
  assert.deepEqual([r.reseau[0].premierMs,r.reseau[0].dernierMs,r.reseau[0].nombre],[15,20,2]);
  temps=0;assert.equal(d.resultat().tempsMs,20);temps=NaN;assert.equal(d.resultat().tempsMs,20);
  temps=Number.MAX_SAFE_INTEGER;d.exceptionFinale(new Error('CANARI'));assert.equal(d.resultat().erreurFinale.tempsMs,1_800_000);
  assert.doesNotMatch(JSON.stringify(d.resultat()),/CANARI|1970-|2026-/);
});
test('projection bornée : la saturation conserve le total bloquant et compte les entrées non détaillées',()=>{
  const d=diagnosticD();for(let i=0;i<40;i++)d.erreurNavigateur(1,projeterErreurNavigateurD({source:'console_error',texte:`CANARI_${i}`}));
  d.erreurNavigateur(1,projeterErreurNavigateurD({source:'console_error',texte:'CANARI_0'}));
  const r=d.resultat();assert.equal(r.erreurs,41);assert.equal(r.erreursNavigateur.length,32);assert.equal(r.erreursNavigateurTronquees,8);assert.equal(r.erreursNavigateur[0].nombre,2);assert.doesNotMatch(JSON.stringify(r),/CANARI/);
});
test('exception finale : chaque échec injecté dans le vrai parcours conserve son action et remonte intact',async()=>{
  for(const cible of ['mission_navigation','mission_titre','candidature_bouton_actif','candidature_debut','candidature_envoyer','recharge_attente']) {
    let action;const saved={},erreur=new Error('expect(CANARI_IDENTITE).toBeVisible failed: Timeout 5000ms password=CANARI_SECRET');
    const fail=async()=>{if(action===cible)throw erreur;};
    const locator={fill:fail,click:fail,getByRole:()=>locator};
    const page={goto:fail,reload:fail,waitForLoadState:fail,getByRole:()=>locator,getByPlaceholder:()=>locator,getByText:()=>locator};
    const expect=()=>({toBeVisible:fail,toBeHidden:fail,toBeEnabled:fail,toContainText:fail});
    await assert.rejects(()=>executerFrontendD({action:'run',env:prive,now,save:(k,v)=>saved[k]=v,fixture:async()=>({}),sql:async()=>audits('avant'),
      naviguer:async({diagnostic})=>deposerCandidatureD(page,m,{expect,phase:p=>diagnostic.phase(p,0),action:n=>{diagnostic.action(n);action=n;}})}),e=>e===erreur);
    assert.equal(saved.resultat.succes,false);const d=saved.resultat.diagnostic;
    assert.equal(d.action,cible);assert.equal(d.erreurFinale.action,cible);assert.equal(d.erreurFinale.slot,0);assert.equal(d.erreurFinale.source,'exception_finale');assert.equal(d.erreurFinale.categorie,'delai_attente');
    assert.equal(d.erreurs,0);assert.doesNotMatch(JSON.stringify(saved),/CANARI|password=/);
  }
});
test('actions fermées et classes finales connues, aucune URL extraite du message',()=>{
  const d=diagnosticD();assert.throws(()=>d.action('CANARI_LIBRE'));d.phase('mission',0);d.action('mission_navigation');
  d.exceptionFinale(Object.assign(new Error('Navigation to https://secret.invalid/CANARI is interrupted by another navigation'),{name:'CANARI_CLASSE'}));
  const p=d.resultat().erreurFinale;assert.equal(p.categorie,'navigation_interrompue');assert.equal(p.classe,'autre');assert.equal(p.emplacement,null);assert.doesNotMatch(JSON.stringify(p),/CANARI|https?:/);
  d.phase('reload',0);assert.equal(d.resultat().action,null);
  assert.equal(projeterErreurNavigateurD({source:'exception_finale',texte:'expect(locator).toBeVisible() failed',classe:'AssertionError'}).categorie,'assertion');
});
test('une violation stricte reste distincte du timeout mentionné par le matcher',()=>{
  const r=projeterErreurNavigateurD({source:'exception_finale',classe:'Error',texte:
    'expect(locator).toBeVisible() failed\nTimeout: 5000ms\nError: strict mode violation: CANARI_IDENTITE https://secret.invalid/?jwt=CANARI_SECRET resolved to 2 elements'});
  assert.equal(r.categorie,'strict_mode');assert.equal(r.emplacement,null);
  assert.doesNotMatch(JSON.stringify(r),/CANARI|secret\.invalid|jwt=|5000/);
  assert.equal(projeterErreurNavigateurD({source:'exception_finale',classe:'Error',texte:'expect(locator).toBeVisible() failed: Timeout 5000ms'}).categorie,'delai_attente');
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
  await assert.rejects(()=>executerFrontendD({...common,action:'run',fixture:async()=>({}),sql:async()=>audits('avant'),naviguer:async({diagnostic})=>{try{diagnostic.phase('login',0);diagnostic.action('connexion_motdepasse');throw Error('email=CANARI_EMAIL@example.invalid password=CANARI_PASSWORD url=https://secret.invalid/?token=CANARI_JWT');}finally{closed=true;}}}));
  assert.equal(closed,true);assert.equal(saved.resultat.succes,false);assert.doesNotMatch(JSON.stringify(saved),/CANARI/);
  assert.equal(saved.resultat.diagnostic.erreurFinale.action,'connexion_motdepasse');assert.doesNotMatch(JSON.stringify(saved),/example\.invalid|https?:|password=/);
  await executerFrontendD({...common,env,action:'snapshot',sql:async()=>audits('avant')});
  let cleanup=0;await executerFrontendD({...common,env,action:'cleanup',fixture:async({action})=>{assert.equal(action,'cleanup');cleanup++;return{skipped:false};}});assert.equal(cleanup,1);
});
test('échec page : le vrai finally ferme contexte puis navigateur et preview avant de rendre la main au cleanup',async()=>{
  const ordre=[];
  const context={addInitScript:async()=>{},routeWebSocket:async()=>{},on:()=>{},route:async()=>{},close:async()=>ordre.push('contexte-ferme'),
    newPage:async()=>({setDefaultTimeout:()=>{},setDefaultNavigationTimeout:()=>{},goto:async()=>{ordre.push('page');throw Error('CANARI_PAGE');}})};
  const browser={newContext:async()=>context,close:async()=>ordre.push('navigateur-ferme')};
  await assert.rejects(()=>parcourirFrontendD({m,identites,env,diagnostic:diagnosticD(),lireAssets:()=>new Set(),preparerBuild:()=>ordre.push('build'),previewFn:async()=>({kill:()=>ordre.push('preview-stop')}),
    chargerPlaywright:async()=>({webkit:{launch:async options=>{assert.deepEqual(options.env,{});assert.doesNotMatch(JSON.stringify(options),/CANARI|SUPABASE|LOAD_CANDIDATURES/);return browser;}},devices:{},expect:{}})}));
  ordre.push('cleanup-possible');assert.deepEqual(ordre,['build','page','contexte-ferme','navigateur-ferme','preview-stop','cleanup-possible']);
});
test('succès orchestré exige corrélation UI/backend et audit avancé, rapport sans IDs/password/JWT',async()=>{
  for(const voisin of [false,true]){
    const saved={};let lecture=0,ferme=false;
    const cands=m.membres.slice(0,2).map((a,slot)=>({slot,id:slot?m.preuveId:m.nettoyageId}));
    const resultat=()=>executerFrontendD({action:'run',env:prive,now,save:(k,v)=>saved[k]=v,
      sql:async()=>audits(lecture++?'apres':'avant'),naviguer:async()=>{ferme=true;return{preuves:[],candidatures:cands,concurrenceHTTP};},
      fixture:async({action})=>{if(action==='catalogue')return{};assert.equal(ferme,true);return{notifications:4,candidatures:cands.map(c=>({id:c.id,soignant_id:m.membres[voisin?1-c.slot:c.slot].userId}))};}});
    if(voisin)await assert.rejects(resultat);else assert.deepEqual(await resultat(),{succes:true,candidatures:2});
    assert.equal(saved.resultat.succes,!voisin);assert.doesNotMatch(JSON.stringify(saved),/CANARI|access_token|password/);
    for(const a of identites)assert.ok(!JSON.stringify(saved).includes(a.userId));
  }
});
test('erreur du dernier contexte pendant fermeture interdit le succès malgré backend valide',async()=>{
  const saved={};let lecture=0,fermetures=0;
  const cands=m.membres.slice(0,2).map((a,slot)=>({slot,id:slot?m.preuveId:m.nettoyageId}));
  await assert.rejects(()=>executerFrontendD({action:'run',env:prive,now,save:(k,v)=>saved[k]=v,
    sql:async()=>audits(lecture++?'apres':'avant'),
    naviguer:async({diagnostic})=>{
      try{return {preuves:[],candidatures:cands,concurrenceHTTP};}
      finally {
        diagnostic.phase('etablissement',2);diagnostic.action('contexte_fermer');
        await Promise.resolve();fermetures++;
        diagnostic.erreurNavigateur(2,projeterErreurNavigateurD({source:'pageerror',classe:'TypeError',texte:'Failed to fetch CANARI_FERMETURE'}));
      }
    },
    fixture:async({action})=>action==='catalogue'?{}:{notifications:4,candidatures:cands.map(c=>({id:c.id,soignant_id:m.membres[c.slot].userId}))},
  }),/Anomalie UI D2/);
  assert.equal(fermetures,1);assert.equal(saved.resultat.succes,false);assert.equal(saved.resultat.diagnostic.erreurs,1);
  assert.equal(saved.resultat.diagnostic.erreursNavigateur[0].phase,'etablissement');
  assert.equal(saved.resultat.diagnostic.erreursNavigateur[0].slotPhase,2);
  assert.equal(saved.resultat.diagnostic.erreursNavigateur[0].action,'contexte_fermer');
  assert.equal(saved.resultat.diagnostic.erreursNavigateur[0].slotEmetteur,2);
  assert.doesNotMatch(JSON.stringify(saved),/CANARI/);
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

const differee=()=>{let resolve,reject;const promise=new Promise((oui,non)=>{resolve=oui;reject=non;});return {promise,resolve,reject};};
test('barrière : aucun transport avant les deux interfaces, puis deux appels réellement en vol',async()=>{
  let temps=100,actifs=0,maximum=0;const b=concurrenceCandidaturesD({temps:()=>temps}),reponses=[differee(),differee()],debuts=[];
  const transport=slot=>b.transporter(slot,async()=>{debuts.push(slot);maximum=Math.max(maximum,++actifs);try{return await reponses[slot].promise;}finally{actifs--;}});
  const p0=transport(0);await Promise.resolve();assert.deepEqual(debuts,[]);
  temps=110;const p1=transport(1);await Promise.resolve();assert.deepEqual(debuts,[0,1]);assert.equal(maximum,2);
  temps=120;reponses[0].resolve('zero');await p0;assert.equal(actifs,1);
  temps=125;reponses[1].resolve('un');await p1;
  assert.deepEqual(b.verifier(),{slots:[{slot:0,debutMs:10,receptionMs:20},{slot:1,debutMs:10,receptionMs:25}],chevauchementMs:10});
  await assert.rejects(()=>transport(0));assert.equal(debuts.length,2);b.annuler();
});
test('preuve temporelle : séquentiel, borne touchée, durée nulle, slot dupliqué, temps libre ou incomplet refusés',()=>{
  for(const rows of [[],[{slot:0,debutMs:1,receptionMs:3}],
    [{slot:0,debutMs:1,receptionMs:3},{slot:1,debutMs:4,receptionMs:6}],
    [{slot:0,debutMs:1,receptionMs:3},{slot:1,debutMs:3,receptionMs:6}],
    [{slot:0,debutMs:1,receptionMs:1},{slot:1,debutMs:0,receptionMs:6}],
    concurrenceHTTP.slots.map(r=>({...r,slot:0})),concurrenceHTTP.slots.map(r=>({...r,receptionMs:null})),
    concurrenceHTTP.slots.map(r=>({...r,debutMs:-1})),concurrenceHTTP.slots.map(r=>({...r,debutMs:NaN})),
    concurrenceHTTP.slots.map(r=>({...r,receptionMs:1800001})),concurrenceHTTP.slots.map(r=>({...r,libre:'CANARI'}))])assert.throws(()=>verifierConcurrenceD(rows));
});
test('participant absent, inconnu ou annulé : zéro transport, aucun rejeu et délai borné',async()=>{
  let n=0;const transport=()=>{n++;};const b=concurrenceCandidaturesD({delaiMs:5});
  await assert.rejects(()=>b.transporter(2,transport));
  await assert.rejects(()=>b.transporter(0,transport),/interrompue/);
  await assert.rejects(()=>b.transporter(1,transport));assert.equal(n,0);assert.throws(()=>b.verifier());
  const c=concurrenceCandidaturesD();const attente=c.transporter(0,transport);c.annuler();await assert.rejects(()=>attente);assert.equal(n,0);
  for(const delaiMs of [0,-1,NaN,20001])assert.throws(()=>concurrenceCandidaturesD({delaiMs}));
});
test('deux clics : allSettled conserve le premier échec et attend le second avant tout retour',async()=>{
  const suite=differee(),erreur=new Error('CANARI_SECRET'),ordre=[];
  const participants=[0,1].map(slot=>{
    const loc={getByRole:()=>loc,click:async()=>{ordre.push(`clic-${slot}`);if(slot===0)throw erreur;await suite.promise;ordre.push('second-fini');}};
    return {slot,page:{getByRole:()=>loc,getByText:()=>loc},options:{expect:()=>({toBeHidden:async()=>{},toBeVisible:async()=>{}}),echec:()=>ordre.push(`echec-${slot}`)}};
  });
  let fini=false;const p=envoyerCandidaturesConcurrentesD(participants,{annuler:()=>ordre.push('annuler'),verifier:()=>{throw Error('Ne doit pas valider');}}).finally(()=>{fini=true;});
  await Promise.resolve();await Promise.resolve();assert.equal(fini,false);assert.deepEqual(ordre.slice(0,2),['clic-0','clic-1']);
  suite.resolve();await assert.rejects(()=>p,e=>e===erreur);assert.equal(ordre.includes('second-fini'),true);assert.equal(fini,true);
  await assert.rejects(()=>envoyerCandidaturesConcurrentesD([participants[0],participants[0]],{}));
});
test('diagnostic concurrent : phases/actions/réseau liés au bon contexte et exception conservée sans secrets',()=>{
  let temps=100;const d=diagnosticD({temps:()=>temps}),a=d.pourSlot(0),b=d.pourSlot(1);
  a.phase('postuler');a.action('candidature_envoyer');temps=110;b.phase('mission');b.action('mission_titre');
  a.reseau(STAGING_URL+'/rest/v1/rpc/fn_confirmer_action_planning_v1','POST',200);
  a.erreurNavigateur(0,projeterErreurNavigateurD({source:'pageerror',texte:'AbortError CANARI_EMAIL'}));
  b.reseau(STAGING_URL+'/rest/v1/missions','GET',200);
  a.exceptionFinale(new Error('CANARI_PASSWORD'));d.exceptionFinale(new Error('CANARI_JWT'));
  const r=d.resultat();assert.deepEqual(r.reseau.map(x=>[x.slot,x.phase]),[[0,'postuler'],[1,'mission']]);
  assert.equal(r.erreursNavigateur[0].slotPhase,0);assert.equal(r.erreursNavigateur[0].action,'candidature_envoyer');assert.equal(r.erreurs,1);
  assert.equal(r.erreurFinale.slot,0);assert.equal(r.erreurFinale.action,'candidature_envoyer');
  assert.throws(()=>a.phase('postuler',1));assert.throws(()=>d.pourSlot(3));assert.doesNotMatch(JSON.stringify(r),/CANARI|https?:|password/);
});
test('vraies interceptions : budgets avant barrière, drain attend les deux transports, fermeture refuse les écritures tardives',async()=>{
  const handlers=[],reseaux=[],reponses=[differee(),differee()],departs=[],d=diagnosticD();let temps=0,aborts=0;
  const b=concurrenceCandidaturesD({temps:()=>temps});
  for(const slot of [0,1])reseaux.push(await installerReseauD({addInitScript:async()=>{},routeWebSocket:async()=>{},on:()=>{},route:async(_,h)=>{handlers[slot]=h;}},identites[slot],m,d.pourSlot(slot),{concurrence:b}));
  const route=slot=>({request:()=>({url:()=>STAGING_URL+'/rest/v1/rpc/fn_confirmer_action_planning_v1',method:()=>'POST',postData:()=>'yes',postDataJSON:()=>postuler}),
    fetch:async options=>{assert.deepEqual(options,{maxRedirects:0,maxRetries:0,timeout:25000});departs.push(slot);return reponses[slot].promise;},fulfill:async()=>{},abort:async()=>{aborts++;}});
  const p0=handlers[0](route(0));assert.deepEqual(reseaux[0].budget.projection(),{fn_confirmer_action_planning_v1:1});assert.deepEqual(departs,[]);
  const p1=handlers[1](route(1));await Promise.resolve();await Promise.resolve();assert.deepEqual(departs,[0,1]);
  for(const r of reseaux)r.fermer();let fini=false;const drains=Promise.allSettled(reseaux.map(r=>r.drainer())).then(()=>{fini=true;});
  await handlers[0](route(0));assert.equal(aborts,1);assert.deepEqual(departs,[0,1]);assert.equal(fini,false);
  const response=slot=>({status:()=>200,ok:()=>true,json:async()=>({success:true,choix_contrat:'SALARIE',profession_requise:'AS',docs_a_completer:true,candidature_id:slot?m.preuveId:m.nettoyageId})});
  temps=10;reponses[0].resolve(response(0));await p0;assert.equal(fini,false);
  temps=20;reponses[1].resolve(response(1));await p1;await drains;assert.equal(fini,true);
  assert.equal(b.verifier().chevauchementMs,10);assert.deepEqual(reseaux.map(r=>r.candidatures[0].slot),[0,1]);assert.equal(d.resultat().erreurs,1);
});
test('échec transport : aucune réponse perdue rejouée, pair en vol attendu et preuve refusée',async()=>{
  const r0=differee(),r1=differee(),b=concurrenceCandidaturesD();let fini=false;
  const p0=b.transporter(0,()=>r0.promise),p1=b.transporter(1,()=>r1.promise);
  const issues=Promise.allSettled([p0,p1]).then(r=>{fini=true;return r;});await Promise.resolve();
  r0.reject(Error('CANARI_PROVIDER'));await assert.rejects(()=>p0);assert.equal(fini,false);
  r1.resolve('ok');const result=await issues;assert.equal(result[1].status,'fulfilled');assert.throws(()=>b.verifier());
});
test('résultat : deux IDs distincts et chevauchement requis même si le backend accepte les corrélations',async()=>{
  for(const defect of ['double-id','double-slot','slot-etablissement','sans-mesure','sequentiel']){
    let lectures=0;const saved={};const cs=[{slot:0,id:m.preuveId},{slot:1,id:defect==='double-id'?m.preuveId:m.nettoyageId}];if(defect==='double-slot')cs[1].slot=0;if(defect==='slot-etablissement')cs[1].slot=2;
    const mesure=defect==='sans-mesure'?undefined:defect==='sequentiel'?{slots:[{slot:0,debutMs:0,receptionMs:1},{slot:1,debutMs:2,receptionMs:3}]}:concurrenceHTTP;
    await assert.rejects(()=>executerFrontendD({action:'run',env:prive,now,save:(k,v)=>saved[k]=v,sql:async()=>audits(lectures++?'apres':'avant'),
      naviguer:async()=>({preuves:[],candidatures:cs,concurrenceHTTP:mesure}),fixture:async()=>({notifications:4,candidatures:cs.map(c=>({id:c.id,soignant_id:m.membres[c.slot].userId}))})}));
    assert.equal(saved.resultat.succes,false);
  }
});
test('finally réel avec deux envois : aucun contexte ni cleanup ne finit avant les deux transports pendants',async()=>{
  const ordre=[],departs=[],reponses=[differee(),differee()],deuxDeparts=differee(),handlers=[],transports=[];let n=0;
  const erreur=Error('CANARI_ECHEC_INTERFACE');
  const browser={newContext:async()=>{
    const slot=n++;
    const loc=(name='')=>({slot,name,fill:async()=>{},getByRole:(_,o)=>loc(o?.name),click:async()=>{
      if(name!=='Envoyer ma candidature')return;
      transports[slot]=handlers[slot]({request:()=>({url:()=>STAGING_URL+'/rest/v1/rpc/fn_confirmer_action_planning_v1',method:()=>'POST',postData:()=>'yes',postDataJSON:()=>postuler}),
        fetch:async()=>{departs.push(slot);if(departs.length===2)deuxDeparts.resolve();return reponses[slot].promise;},fulfill:async()=>ordre.push(`reponse-${slot}`),abort:async()=>ordre.push(`abort-${slot}`)});
      await deuxDeparts.promise;
    }});
    const page={setDefaultTimeout:()=>{},setDefaultNavigationTimeout:()=>{},goto:async()=>{},waitForLoadState:async()=>{},
      getByLabel:()=>loc(),getByRole:(_,o)=>loc(o?.name),getByPlaceholder:()=>loc(),getByText:name=>loc(name)};
    return {addInitScript:async()=>{},routeWebSocket:async()=>{},on:()=>{},route:async(_,h)=>{handlers[slot]=h;},newPage:async()=>page,close:async()=>ordre.push(`fermer-${slot}`)};
  },close:async()=>ordre.push('browser')};
  const expect=loc=>({toHaveURL:async()=>{},toBeEnabled:async()=>{},toContainText:async()=>{},toBeHidden:async()=>{},toBeVisible:async()=>{
    if(loc.name==='✅ Candidature envoyée — En attente de réponse'){
      if(loc.slot===0)throw erreur;await transports[1];
    }
  }});expect.poll=()=>({toBe:async()=>{}});
  let fini=false;const p=parcourirFrontendD({m,identites,env,diagnostic:diagnosticD(),preparerBuild:()=>{},lireAssets:()=>new Set(),previewFn:async()=>({kill:()=>ordre.push('preview')}),
    chargerPlaywright:async()=>({webkit:{launch:async()=>browser},devices:{},expect})}).finally(()=>{fini=true;});
  await deuxDeparts.promise;await Promise.resolve();assert.equal(fini,false);assert.deepEqual(ordre,[]);
  const response=slot=>({status:()=>200,ok:()=>true,json:async()=>({success:true,choix_contrat:'SALARIE',profession_requise:'AS',docs_a_completer:true,candidature_id:slot?m.preuveId:m.nettoyageId})});
  reponses[1].resolve(response(1));await transports[1];await Promise.resolve();assert.equal(fini,false);assert.deepEqual(ordre,['reponse-1']);
  reponses[0].resolve(response(0));await assert.rejects(()=>p,e=>e===erreur);
  ordre.push('cleanup-possible');assert.deepEqual(ordre,['reponse-1','reponse-0','fermer-0','fermer-1','browser','preview','cleanup-possible']);
});
