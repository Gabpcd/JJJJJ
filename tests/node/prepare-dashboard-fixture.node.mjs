import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { STAGING_REF, STAGING_URL } from '../../scripts/ci/prepare-load-fixtures.mjs';
import { configurationDashboard, executerFixtureDashboard, manifesteDashboard, sqlConfirmerNettoyageDashboard,
  sqlNettoyerDashboard, sqlPreparerDashboard, sqlVerifierDashboardAvantAuth, utilisateurFixtureValide } from '../../scripts/ci/prepare-dashboard-fixture.mjs';

const secret = 'Aa1!mot-de-passe-test-entierement-fictif';
const silence = () => {};
function environnement(extra={}) {
  const dir=mkdtempSync(join(tmpdir(),'jolene-dashboard-node-'));
  return { STAGING_SUPABASE_PROJECT_REF:STAGING_REF,STAGING_SUPABASE_URL:STAGING_URL,
    STAGING_SUPABASE_ACCESS_TOKEN:'management-fictif',STAGING_SUPABASE_SERVICE_ROLE_KEY:'service-fictif',
    STAGING_SUPABASE_ANON_KEY:'anon-fictif',LOAD_TEST_RUN_ID:'dashboard-123-1',
    LOAD_DASHBOARD_MANIFEST:join(dir,'manifest.json'),GITHUB_ENV:join(dir,'github-env'),...extra };
}
const profil = { profession:'AS',identite_verifiee:false,tous_documents_valides:false };
const dashboard = { profil,missions_ouvertes:[],mes_missions:[],documents:[],gains_6mois:[],missions_semaine_cal:[],
  propositions:[],heures_semaine:0,notifs_non_lues:0,gains_mois:{net_total:0,brut_total:0,nb_missions:0} };
const response = (body,status=200) => new Response(JSON.stringify(body),{status});
function transport(env, overrides={}) {
  const m=manifesteDashboard(configurationDashboard(env));
  const state={user:null,profile:false,calls:[],deleted:0,cleanup:false,...overrides};
  const fetchImpl=async(url,options={})=>{
    const method=options.method??'GET';const body=options.body?JSON.parse(options.body):null;
    state.calls.push({url,method,body});
    assert.equal(options.redirect,'error');assert.ok(options.signal instanceof AbortSignal);
    assert.ok(url.startsWith(STAGING_URL+'/') || url===`https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`);
    if(url.endsWith('/database/query')){
      assert.equal(options.headers.Authorization,'Bearer management-fictif');
      if(body.query.includes('SELECT true AS pret'))return response([{pret:true}]);
      if(body.query.includes('SELECT true AS profil_prepare')){
        assert.equal(JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST)).status,'auth-created');
        assert.equal(state.user.app_metadata.est_compte_test,true);state.profile=true;
        return response([{profil_prepare:true}]);
      }
      if(body.query.includes('DO $fixture_cleanup$')){
        state.cleanup=true;state.profile=false;
        if(state.user)state.user.app_metadata.load_cleanup_pending=true;
        return response([{profils_restants:0}]);
      }
      if(body.query.includes('AS auth_restants'))return response([{auth_restants:state.user?1:0,profils_restants:state.profile?1:0,preferences_restantes:state.profile?1:0}]);
      throw new Error('SQL simulé inconnu');
    }
    if(url.endsWith('/admin/users') && method==='POST'){
      const onDisk=JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST));
      assert.equal(onDisk.userId,m.userId);assert.equal(onDisk.status,'planned');
      assert.equal(body.password,secret);assert.equal(body.email_confirm,true);
      state.user={id:body.id,email:body.email,app_metadata:body.app_metadata};
      return response(state.user);
    }
    if(url.endsWith('/admin/users/'+m.userId)){
      if(method==='GET')return state.user?response(state.user):response({error:'absent'},404);
      if(method==='DELETE'){
        assert.equal(state.cleanup,true);assert.equal(state.profile,false);
        assert.equal(state.user.app_metadata.load_cleanup_pending,true);
        assert.deepEqual(body,{should_soft_delete:false});state.user=null;state.deleted++;
        return response({});
      }
    }
    if(url.endsWith('/token?grant_type=password')){
      assert.equal(body.email,m.email);assert.equal(body.password,secret);
      return response({access_token:'jwt-fictif',user:state.user});
    }
    if(url.endsWith('/rpc/fn_dashboard_soignant_complet')){
      assert.equal(options.headers.Authorization,'Bearer jwt-fictif');
      return response({...dashboard,profil:{...profil,prenom:m.prenom,nom:m.nom}});
    }
    throw new Error('Endpoint simulé inconnu');
  };
  return {m,state,fetchImpl};
}
const prepare = (env,fetchImpl,extra={})=>executerFixtureDashboard({action:'prepare',env,fetchImpl,log:silence,genererMotDePasse:()=>secret,...extra});
const cleanup = (env,fetchImpl)=>executerFixtureDashboard({action:'cleanup',env,fetchImpl,log:silence});

test('destination stage exacte et run non injectable requis avant tout réseau',async()=>{
  for(const extra of [{STAGING_SUPABASE_PROJECT_REF:'flripxtsyegjshnhzjkz'}, {STAGING_SUPABASE_URL:STAGING_URL+'.evil.invalid'},
    {LOAD_TEST_RUN_ID:"x';delete"},{LOAD_TEST_RUN_ID:''},{STAGING_SUPABASE_SERVICE_ROLE_KEY:''}]){
    let calls=0;await assert.rejects(prepare(environnement(extra),()=>{calls++;}));assert.equal(calls,0);
  }
  assert.throws(()=>configurationDashboard(environnement({LOAD_TEST_RUN_ID:'x\nY'})));
});
test('UUID/email déterministes par run, métadonnées privées strictes',()=>{
  const m=manifesteDashboard({runId:'id-1'});assert.deepEqual(m,manifesteDashboard({runId:'id-1'}));
  assert.notEqual(m.userId,manifesteDashboard({runId:'id-2'}).userId);
  assert.match(m.email,/^recette-dashboard-[a-f0-9-]+@example\.invalid$/);
  const user={id:m.userId,email:m.email,app_metadata:{role:'SOIGNANT',est_compte_test:true,is_test_playwright:true,load_fixture_kind:'DASHBOARD',load_fixture_run:m.runId}};
  assert.equal(utilisateurFixtureValide(user,m),true);
  for(const change of [{email:'playwright-soignant@jolene.app'},{id:'autre'}, {app_metadata:{...user.app_metadata,est_compte_test:'true'}},
    {app_metadata:{...user.app_metadata,load_fixture_run:'autre'}},{app_metadata:{},user_metadata:user.app_metadata}])
    assert.equal(utilisateurFixtureValide({...user,...change},m),false);
});
test('création puis vrai contrat login/dashboard, secret uniquement masque+GITHUB_ENV, aucun artifact secret',async()=>{
  const env=environnement();const t=transport(env);const logs=[];
  const result=await prepare(env,t.fetchImpl,{log:s=>logs.push(s)});
  assert.equal(result.identites,1);assert.equal(result.profession,'AS');
  const file=readFileSync(env.LOAD_DASHBOARD_MANIFEST,'utf8');assert.equal(JSON.parse(file).status,'prepared');
  assert.doesNotMatch(file,/password|token|jwt|service-fictif|management-fictif/);
  assert.equal(logs.filter(l=>l.includes(secret)).length,1);assert.equal(logs[0],`::add-mask::${secret}`);
  assert.match(readFileSync(env.GITHUB_ENV,'utf8'),new RegExp(`LOAD_DASHBOARD_PASSWORD=${secret.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}`));
  assert.equal(t.state.calls.filter(c=>c.url.endsWith('/admin/users')).length,1);
  assert.ok(t.state.calls.every(c=>!c.url.includes('/signup')&&!c.url.includes('/invite')&&!c.url.includes('/recover')));
});
test('cleanup exact du profil puis Auth et vérification SQL finale ; relecture ne supprime pas autre chose',async()=>{
  const env=environnement();const t=transport(env);await prepare(env,t.fetchImpl);
  await cleanup(env,t.fetchImpl);assert.equal(t.state.deleted,1);
  assert.equal(JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST)).status,'cleaned');
  assert.equal(t.state.user,null);assert.equal(t.state.profile,false);
  await cleanup(env,t.fetchImpl);assert.equal(t.state.deleted,1);
});
test('manifeste absent = aucune suppression ; manifeste altéré ou compte réel = refus',async()=>{
  const env=environnement();let calls=0;assert.deepEqual(await cleanup(env,()=>{calls++;}),{skipped:true});assert.equal(calls,0);
  const t=transport(env);await prepare(env,t.fetchImpl);
  t.state.user.app_metadata.est_compte_test=false;
  await assert.rejects(cleanup(env,t.fetchImpl),/hors fixture/);assert.equal(t.state.deleted,0);
  const file=JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST));file.email='playwright-soignant@jolene.app';
  writeFileSync(env.LOAD_DASHBOARD_MANIFEST,JSON.stringify(file));
  await assert.rejects(cleanup(env,t.fetchImpl),/Manifeste/);assert.equal(t.state.deleted,0);
});
test('une dépendance métier signalée par SQL bloque la suppression Auth',async()=>{
  const env=environnement();const t=transport(env);await prepare(env,t.fetchImpl);
  await assert.rejects(cleanup(env,async(url,options)=>{
    if(options.body?.includes('DO $fixture_cleanup$'))return response({error:'secret-serveur'},500);
    return t.fetchImpl(url,options);
  }),/HTTP 500/);
  assert.equal(t.state.deleted,0);assert.equal(t.state.profile,true);
});
test('réponse Auth perdue : UUID conservé avant réseau, compte retrouvé et nettoyé sans deuxième création',async()=>{
  const env=environnement();const t=transport(env);
  await assert.rejects(prepare(env,async(url,options)=>{
    const result=await t.fetchImpl(url,options);
    if(url.endsWith('/admin/users'))throw new Error('contenu-prive');return result;
  }),/ambiguë/);
  assert.equal(JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST)).status,'planned');
  await cleanup(env,t.fetchImpl);assert.equal(t.state.deleted,1);
  assert.equal(t.state.calls.filter(c=>c.url.endsWith('/admin/users')).length,1);
});
test('création Auth encore incertaine et compte absent : pas de faux nettoyage confirmé',async()=>{
  const env=environnement();const t=transport(env);
  await assert.rejects(prepare(env,async(url,options)=>{
    if(url.endsWith('/admin/users'))throw new Error('contenu-prive');return t.fetchImpl(url,options);
  }),/ambiguë/);
  await assert.rejects(cleanup(env,t.fetchImpl),/Création Auth ambiguë/);
  assert.equal(JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST)).status,'planned');assert.equal(t.state.deleted,0);
});
test('commit profil perdu : le cleanup conserve son verrou et retire le profil confirmé côté serveur',async()=>{
  const env=environnement();const t=transport(env);
  await assert.rejects(prepare(env,async(url,options)=>{
    const result=await t.fetchImpl(url,options);
    if(options.body?.includes('AS profil_prepare'))throw new Error('interruption');return result;
  }),/ambiguë/);
  assert.equal(t.state.profile,true);await cleanup(env,t.fetchImpl);assert.equal(t.state.deleted,1);
});
test('suppression Auth perdue : prochaine lecture absente et contrôle SQL confirment sans répétition destructive',async()=>{
  const env=environnement();const t=transport(env);await prepare(env,t.fetchImpl);
  await assert.rejects(cleanup(env,async(url,options)=>{
    const result=await t.fetchImpl(url,options);
    if(options.method==='DELETE')throw new Error('interruption');return result;
  }),/ambiguë/);
  assert.equal(JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST)).status,'cleanup-started');
  await cleanup(env,t.fetchImpl);assert.equal(t.state.deleted,1);assert.equal(JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST)).status,'cleaned');
});
test('dashboard incomplet/refusé ou professionnel validé ne permet pas de commencer la charge',async()=>{
  for(const value of [{error:'pas de profil'},{...dashboard,profil:null},{...dashboard,profil:{...profil,identite_verifiee:true}},
    {...dashboard,profil:{...profil,prenom:'Recette',nom:'Dashboard 10000000-0000-4000-a000-000000000001'}}]){
    const env=environnement();const t=transport(env);
    await assert.rejects(prepare(env,async(url,options)=>url.endsWith('/rpc/fn_dashboard_soignant_complet')?response(value):t.fetchImpl(url,options)));
    assert.equal(JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST)).status,'auth-created');
    await cleanup(env,t.fetchImpl);assert.equal(t.state.deleted,1);
  }
});
test('SQL garde tous les triggers/FK actifs, verrou commun et blocage de seed tardif après nettoyage',()=>{
  const m=manifesteDashboard({runId:'sql-1'});const prepareSql=sqlPreparerDashboard(m);const cleanupSql=sqlNettoyerDashboard(m);
  const lock=/pg_advisory_xact_lock\((\d+)::bigint\)/;
  assert.equal(prepareSql.match(lock)[1],cleanupSql.match(lock)[1]);
  for(const sql of [sqlVerifierDashboardAvantAuth(m),prepareSql,cleanupSql]){
    assert.match(sql,/cron\.job WHERE active/);assert.match(sql,/Trigger non prévu/);assert.match(sql,/rolsuper OR rolbypassrls/);
    assert.match(sql,/SET LOCAL statement_timeout='25s'/);assert.match(sql,/SET LOCAL lock_timeout='5s'/);
    assert.doesNotMatch(sql,/DISABLE TRIGGER|session_replication_role|TRUNCATE|DROP\s|DELETE[^;]*CASCADE|INSERT INTO auth\.users/);
  }
  assert.match(prepareSql,/load_cleanup_pending/);assert.ok(prepareSql.indexOf('Nettoyage déjà commencé')<prepareSql.indexOf('INSERT INTO public.soignants'));
  assert.match(cleanupSql,/c\.confrelid IN \('public\.soignants'::regclass,'auth\.users'::regclass\)/);
  assert.match(cleanupSql,/Dépendance métier/);assert.match(cleanupSql,/source_acquisition IS DISTINCT FROM/);
  assert.ok(cleanupSql.indexOf('load_cleanup_pending')<cleanupSql.indexOf('DELETE FROM public.soignants'));
  assert.match(sqlConfirmerNettoyageDashboard(m),/AS auth_restants/);
});
test('workflow prépare E/all puis nettoie toujours avant artifact sans transmettre de password en paramètre shell',()=>{
  const workflow=readFileSync(new URL('../../.github/workflows/load-tests.yml',import.meta.url),'utf8');
  assert.ok(workflow.indexOf('prepare-dashboard-pool.mjs prepare')<workflow.indexOf('- name: Run scenario'));
  assert.ok(workflow.indexOf('prepare-dashboard-pool.mjs cleanup')>workflow.indexOf('- name: Run scenario'));
  assert.match(workflow,/if: always\(\) && \(inputs\.scenario == '05-dashboard-concurrent' \|\| inputs\.scenario == 'all'\)/);
  assert.doesNotMatch(workflow,/run:.*LOAD_DASHBOARD_PASSWORD/);
});
