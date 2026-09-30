import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { configurationUI, contratEcritures, ORIGINE_UI, projectionEtatUI, requeteUIAutorisee, sqlEtatUI, sqlGardeUI, verifierEtatUI, verifierGardeUI } from '../../scripts/ci/dashboard-ui-contract.mjs';
import { creerDiagnosticUI, bilanCleanupUI } from '../../scripts/ci/dashboard-ui-diagnostic.mjs';
import { dashboardUIValide, preparerHtmlPreview } from '../../scripts/ci/recette-dashboard-staging.mjs';
import { manifestePoolDashboard } from '../../scripts/ci/prepare-dashboard-pool.mjs';
import { STAGING_REF, STAGING_URL } from '../../scripts/ci/prepare-load-fixtures.mjs';
const membres = manifestePoolDashboard('ui-123-1').membres.map(m => ({ slot:m.slot,userId:m.userId,email:m.email,runId:m.runId,password:`Aa1!canari-UI-prive-${m.slot}-aucun-artifact` }));
const env = { STAGING_SUPABASE_PROJECT_REF:STAGING_REF, STAGING_SUPABASE_URL:STAGING_URL, STAGING_SUPABASE_ACCESS_TOKEN:'secret-test',
  STAGING_SUPABASE_ANON_KEY:'anon-test', LOAD_TEST_RUN_ID:'ui-123-1', LOAD_DASHBOARD_POOL_JSON:JSON.stringify(membres) };
const avant = [0,1].map(slot => ({ slot,auth:1,profils:1,preferences:1,preferences_off:1,sessions:1,identites:1,
  profil_empreinte:'a'.repeat(32),activite:null,notifications:0,presences:0,audits:0,audits_connexion:0 }));
const apres = avant.map(r => ({ ...r,sessions:2,activite:'2026-09-30T10:00:00Z',audits:1,audits_connexion:1 }));

test('HTML de recette retire Google Fonts, conserve assets et erreurs externes sans élargir le routage', () => {
  const html=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
  assert.match(html,/<link[^>]+fonts\.googleapis\.com\/css2/);
  const asset='<link crossorigin href="/assets/app.css" rel="stylesheet">';
  const inconnu='<link rel="stylesheet" href="https://externe.invalid/test.css">';
  const variante="<LINK HREF='https://fonts.googleapis.com/css?family=Inter' REL='stylesheet'>";
  const recette=preparerHtmlPreview(html+asset+inconnu+variante);
  assert.doesNotMatch(recette,/<link\b[^>]*(?:fonts\.googleapis\.com|preconnect|dns-prefetch)[^>]*>/i);
  assert.ok(recette.includes(asset)); assert.ok(recette.includes(inconnu));
  assert.ok(recette.includes('<script type="module" src="/src/main.tsx"></script>'));
  assert.equal(preparerHtmlPreview(recette),recette);
  for(const url of ['https://fonts.googleapis.com/css2?family=Inter','https://externe.invalid/test.css'])
    assert.equal(requeteUIAutorisee({url,method:'GET'},membres[0]),false);
  assert.equal(requeteUIAutorisee({url:ORIGINE_UI+'/assets/app.css',method:'GET'},membres[0]),true);
});

test('configuration UI strict staging + pool exact ; aucun repli compte fixe ou autre run', () => {
  assert.deepEqual(configurationUI(env), membres.slice(0,2));
  for (const e of [{STAGING_SUPABASE_URL:'https://prod.invalid'}, {STAGING_SUPABASE_PROJECT_REF:'flripxtsyegjshnhzjkz'},
    {LOAD_DASHBOARD_POOL_JSON:''}, {LOAD_TEST_RUN_ID:'autre'}, {STAGING_SUPABASE_ACCESS_TOKEN:''}]) assert.throws(() => configurationUI({...env,...e}));
  const faux = structuredClone(membres); faux[1].userId=faux[2].userId;faux[1].email=faux[2].email;
  assert.throws(() => configurationUI({...env,LOAD_DASHBOARD_POOL_JSON:JSON.stringify(faux)}));
});
test('réseau refuse production, envois, écritures métier, login voisin et opérations Auth autres que connexion', () => {
  const p=membres[0];const req=(path,method='GET',body,origin=STAGING_URL)=>requeteUIAutorisee({url:origin+path,method,body},p);
  assert.equal(req('/connexion','GET',undefined,ORIGINE_UI),true);
  assert.equal(req('/auth/v1/token?grant_type=password','POST',{email:p.email,password:p.password}),true);
  assert.equal(req('/rest/v1/rpc/fn_audit_connexion','POST',{p_action:'CONNEXION'}),true);
  assert.equal(req('/rest/v1/rpc/fn_maj_activite_soignant','POST',{}),true);
  assert.equal(req('/rest/v1/rpc/fn_dashboard_soignant_complet','POST',{}),true);
  for (const [path,method,body,origin] of [
    ['/rest/v1/soignants','GET',undefined,'https://flripxtsyegjshnhzjkz.supabase.co'],
    ['/functions/v1/send-email','POST',{}], ['/rest/v1/rpc/fn_update_presence','POST',{}],
    ['/functions/v1/send-email','OPTIONS'], ['/rest/v1/rpc/fn_mon_token_calendrier','POST',{}],
    ['/rest/v1/rpc/fn_appliquer_parrainage','POST',{p_code:'x'}], ['/rest/v1/soignants','PATCH',{}],
    ['/auth/v1/signup','POST',{}], ['/auth/v1/logout','POST',{}],
    ['/auth/v1/token?grant_type=password','POST',{email:membres[1].email,password:p.password}],
    ['/rest/v1/rpc/fn_audit_connexion','POST',{p_action:'DECONNEXION'}],
    ['/rest/v1/rpc/fn_maj_activite_soignant','POST',{user_id:membres[1].userId}],
  ]) assert.equal(req(path,method,body,origin),false,path);
});
test('backend exact : audit unique conservé, notifications/presence interdites, seul timestamp activité change', () => {
  verifierEtatUI(avant);verifierEtatUI(apres,avant);
  for (const change of [{audits:2},{audits:0,audits_connexion:0},{presences:1},{notifications:1},{profil_empreinte:'b'.repeat(32)},
    {activite:null},{preferences_off:0},{profils:0}]) assert.throws(()=>verifierEtatUI([{...apres[0],...change},apres[1]],avant));
  const fin=apres.map(r=>({...r,auth:0,profils:0,preferences:0,sessions:0,identites:0,profil_empreinte:null,activite:null}));
  verifierEtatUI(fin,avant,true);
  assert.throws(()=>verifierEtatUI([{...fin[0],sessions:1},fin[1]],avant,true));
  assert.throws(()=>verifierEtatUI([{...fin[0],audits:0},fin[1]],avant,true));
});
test('SQL lecture seule ciblé sur deux UUID, aucun détail IP/user-agent ni suppression journal', () => {
  const sql=sqlEtatUI(membres.slice(0,2));
  for(const m of membres.slice(0,2))assert.ok(sql.includes(m.userId));
  assert.doesNotMatch(sqlGardeUI+sql,/DELETE\s|UPDATE\s|INSERT\s|TRUNCATE\s|ip_acteur|navigateur_acteur|decrypted_secrets/i);
  assert.throws(()=>sqlEtatUI([{...membres[0],slot:'0);DROP TABLE x;'},membres[1]]));
  assert.doesNotMatch(sql,/encrypted_password|refresh_token|access_token/);
});
test('empreintes versionnées correspondent aux seuls corps SQL revus, toute dérive refuse le préflight', () => {
  const source=readFileSync(new URL('../../supabase/schema/public.sql',import.meta.url),'utf8');
  for(const [nom,contrat]of Object.entries(contratEcritures)){
    const debut=source.indexOf(`CREATE OR REPLACE FUNCTION "public"."${nom}"(`);
    const portion=source.slice(debut);const marque=portion.match(/AS (\$[^$]*\$)/);const start=marque.index+marque[0].length;
    const body=portion.slice(start,portion.indexOf(marque[1]+';',start));
    assert.equal(createHash('md5').update(body).digest('hex'),contrat.source_md5,nom);
  }
  assert.throws(()=>verifierGardeUI({crons_actifs:1,audit_fk:0}));
  assert.throws(()=>verifierGardeUI({crons_actifs:0,audit_fk:1}));
  assert.throws(()=>verifierGardeUI({crons_actifs:0,audit_fk:0,fonctions:{},triggers:{}}));
});
test('dashboard reçu : propre identité minimale, tableaux vides avant toute capture', () => {
  const p=membres[0];const d={profil:{prenom:'Recette',nom:`Dashboard ${p.userId}`,profession:'AS',identite_verifiee:false,tous_documents_valides:false},
    missions_ouvertes:[],mes_missions:[],documents:[],gains_6mois:[],missions_semaine_cal:[],propositions:[],heures_semaine:0,notifs_non_lues:0,gains_mois:{net_total:0,brut_total:0,nb_missions:0}};
  assert.equal(dashboardUIValide(d,p),true);assert.equal(dashboardUIValide(d,membres[1]),false);
  assert.equal(dashboardUIValide({...d,missions_ouvertes:[{intitule:'Donnée tierce'}]},p),false);
  assert.equal(dashboardUIValide({...d,gains_mois:{...d.gains_mois,net_total:1}},p),false);
});
test('workflow fixture-only construit avant de créer et exécute UI avant cleanup, sans k6 dans ce job', () => {
  const source=readFileSync(new URL('../../.github/workflows/load-tests.yml',import.meta.url),'utf8');
  const job=source.slice(source.indexOf('  dashboard-frontend:')).split(/\n  [a-z][a-z-]+:\n/)[0];
  assert.ok(job.includes("if: ${{ !inputs.candidatures_sql_only && inputs.candidatures_sql_date == '' && inputs.dashboard_fixture_only && inputs.scenario == '05-dashboard-concurrent' }}"));
  assert.ok(job.indexOf('npm run build')<job.indexOf('prepare-dashboard-pool.mjs prepare'));
  assert.ok(job.indexOf('recette-dashboard-staging.mjs run')<job.indexOf('prepare-dashboard-pool.mjs cleanup'));
  assert.match(job,/if: always\(\)/);assert.doesNotMatch(job,/k6 run|storageState|recordHar|trace:/);
  const script=readFileSync(new URL('../../scripts/ci/recette-dashboard-staging.mjs',import.meta.url),'utf8');
  assert.doesNotMatch(script,/console\.error\(error|\.storageState\(|\.tracing\.start\(|recordHar|recordVideo/);
});

test('projection backend exclut tous champs inconnus et canaris de session', () => {
  const resultat = projectionEtatUI(avant.map(r => ({ ...r, access_token:'canari-session-privee', password:'canari-mdp-prive', details:{headers:'canari-header'} })));
  assert.deepEqual(resultat,avant); assert.doesNotMatch(JSON.stringify(resultat),/canari/);
});

test('préflight accepte le contrat des triggers versionnés puis refuse dérive, trigger ajouté et surcharge', () => {
  const source=readFileSync(new URL('../../supabase/schema/public.sql',import.meta.url),'utf8');
  const triggers={};
  for(const line of source.split('\n').filter(l=>l.startsWith('CREATE OR REPLACE TRIGGER '))){
    const profile=line.includes(' ON "public"."soignants" ') && line.includes('UPDATE') && !line.includes('UPDATE OF');
    const journal=line.includes(' ON "public"."journaux_audit" ') && line.includes('INSERT');
    if(!profile&&!journal)continue;
    const name=line.match(/^CREATE OR REPLACE TRIGGER "([^"]+)"/)[1];
    const fonction=line.match(/EXECUTE FUNCTION "public"\."([^"]+)"/)[1];
    triggers[name]={table:profile?'soignants':'journaux_audit',type:1+(line.includes(' BEFORE ')?2:0)+(line.includes('INSERT')?4:0)+(line.includes('UPDATE')?16:0),
      fonction,schema_fonction:'public',enabled:'O',condition:null,arguments:''};
  }
  const data={crons_actifs:0,audit_fk:0,fonctions_count:Object.keys(contratEcritures).length,fonctions:structuredClone(contratEcritures),triggers,triggers_count:Object.keys(triggers).length};
  verifierGardeUI(data);
  for(const changer of [d=>d.fonctions_count++,d=>d.triggers_count++,d=>d.fonctions.fn_audit_connexion.source_md5='x',
    d=>d.fonctions.fn_maj_activite_soignant.config=['search_path=evil'],d=>d.triggers.inconnu={},
    d=>d.triggers.dec_age_minimum.type=21,d=>d.triggers.dec_age_minimum.enabled='A']){
    const modifie=structuredClone(data);changer(modifie);assert.throws(()=>verifierGardeUI(modifie));
  }
});


test('diagnostic fermé : phases, refus et statuts utiles sans canaris de mot de passe, URL, corps ou pile', () => {
  const d = creerDiagnosticUI();
  for (const phase of ['preview','browser','page','login','dashboard','reload','backend','cleanup']) d.phase(phase,0);
  const secret = 'canari-JWT-password-email-UUID-stack';
  d.requete({url:STAGING_URL+'/auth/v1/token?grant_type=password&secret='+secret,method:'POST',statut:200,body:{password:secret},stack:secret});
  d.requete({url:STAGING_URL+'/rest/v1/rpc/fn_update_presence?jwt='+secret,method:'POST',statut:'refusee'});
  d.requete({url:STAGING_URL+'/rest/v1/rpc/'+secret,method:secret,statut:secret});
  d.requete({url:'https://'+secret+'.invalid/'+secret+'?q='+secret,method:'GET',statut:'transport'});
  d.requete({url:secret,method:'GET',statut:500});
  d.javascript(new Error(secret));
  const r=d.resultat();
  assert.equal(r.phase,'cleanup'); assert.equal(r.erreurs_javascript,1);
  assert.deepEqual(r.progression.map(x=>x.phase),['preview','browser','page','login','dashboard','reload','backend','cleanup']);
  assert.ok(r.reseau.some(x=>x.chemin==='auth-token'&&x.statut===200));
  assert.ok(r.reseau.some(x=>x.chemin==='fn_update_presence'&&x.statut==='refusee'));
  assert.ok(r.reseau.some(x=>x.chemin==='rpc-autre'&&x.methode==='AUTRE'&&x.statut==='inconnu'));
  assert.doesNotMatch(JSON.stringify(r),new RegExp(secret+'|https?://|grant_type|password|stack'));
  assert.throws(()=>d.phase(secret,0)); assert.throws(()=>d.phase('login',secret));
  r.progression[0].phase=secret;r.reseau[0].chemin=secret;
  assert.doesNotMatch(JSON.stringify(d.resultat()),new RegExp(secret));
});
test('diagnostic borné : agrège les répétitions et compte explicitement les observations omises', () => {
  const d=creerDiagnosticUI();
  for(let i=0;i<100;i++) d.requete({url:STAGING_URL+'/auth/v1/token',method:'POST',statut:200});
  assert.equal(d.resultat().reseau.length,1);assert.equal(d.resultat().reseau[0].nombre,100);
  for(let statut=300;statut<400;statut++) d.requete({url:STAGING_URL+'/auth/v1/token',method:'POST',statut});
  assert.equal(d.resultat().reseau.length,64);assert.equal(d.resultat().observations_omises,37);
});
test('cleanup distingue les zéros des audits absents après connexion interrompue sans rendre la recette verte', () => {
  const zeros=avant.map(r=>({...r,auth:0,profils:0,preferences:0,sessions:0,identites:0}));
  assert.deepEqual(bilanCleanupUI(zeros),{donnees_absentes:true,audits_connexion_attendus:2,audits_observes:0,audits_connexion_observes:0});
  assert.throws(()=>verifierEtatUI(zeros,avant,true));
  assert.equal(bilanCleanupUI([{...zeros[0],presences:1},zeros[1]]).donnees_absentes,false);
  assert.equal(bilanCleanupUI(zeros.slice(0,1)).donnees_absentes,false);
  assert.equal(bilanCleanupUI([{...zeros[0],audits:'canari'},zeros[1]]).audits_observes,null);
  const valides=zeros.map(r=>({...r,audits:1,audits_connexion:1}));
  verifierEtatUI(valides,avant,true);assert.equal(bilanCleanupUI(valides).audits_connexion_observes,2);
});
test('forme réelle Auth gotrue_meta_security acceptée ; champs supplémentaires et corps étrangers refusés', () => {
  const m=membres[0], requete={url:STAGING_URL+'/auth/v1/token?grant_type=password',method:'POST',
    body:{email:m.email,password:m.password,gotrue_meta_security:{}}};
  assert.equal(requeteUIAutorisee(requete,m),true);
  for(const body of [{...requete.body,redirect_to:'https://canari.invalid'}, {...requete.body,email:membres[1].email},null,{}])
    assert.equal(requeteUIAutorisee({...requete,body},m),false);
});
