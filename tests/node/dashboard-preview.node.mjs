import assert from 'node:assert/strict';
import { test } from 'node:test';
import { EventEmitter } from 'node:events';
import { readFileSync } from 'node:fs';
import { demarrerPreview } from '../../scripts/ci/dashboard-ui-preview.mjs';
import { ORIGINE_UI, requeteUIAutorisee } from '../../scripts/ci/dashboard-ui-contract.mjs';

function banc(overrides = {}) {
  const child = Object.assign(new EventEmitter(), { exitCode:null, kills:[], kill(signal) { this.kills.push(signal); } });
  const observations=[],commandes=[],requetes=[];
  const options={env:{PATH:'chemin-local',HOME:'/tmp/fictif',STAGING_SUPABASE_ACCESS_TOKEN:'canari-management',LOAD_DASHBOARD_POOL_JSON:'canari-pool'},
    observer:r=>observations.push(r),lancer:(...args)=>{commandes.push(args);return child;},
    sonder:async(...args)=>{requetes.push(args);return {ok:true,status:200};},pause:async()=>{},...overrides};
  return {child,observations,commandes,requetes,options};
}
test('une seule origine IPv4 loopback exacte pour listen, readiness et garde ; aucune variable privée enfant',async()=>{
  const b=banc();assert.equal(await demarrerPreview(b.options),b.child);
  assert.equal(ORIGINE_UI,'http://127.0.0.1:5173');
  assert.deepEqual(b.commandes[0][1],['node_modules/vite/bin/vite.js','preview','--host','127.0.0.1','--port','5173','--strictPort']);
  assert.deepEqual(b.commandes[0][2].env,{PATH:'chemin-local',HOME:'/tmp/fictif'});
  assert.equal(b.requetes[0][0],ORIGINE_UI);assert.equal(b.requetes[0][1].redirect,'error');
  assert.equal(requeteUIAutorisee({url:ORIGINE_UI+'/connexion',method:'GET'},{}),true);
  assert.equal(requeteUIAutorisee({url:'http://localhost:5173/connexion',method:'GET'},{}),false);
  assert.equal(requeteUIAutorisee({url:ORIGINE_UI+'/connexion',method:'POST'},{}),false);
});
test('écoute inaccessible : 60 refus bornés, arrêt enfant, code fermé sans message ni secret',async()=>{
  const secret='canari-password-token-provider-stack';
  const b=banc({sonder:async()=>{throw Object.assign(new Error(secret),{cause:new AggregateError([Object.assign(new Error(secret),{code:'ECONNREFUSED'})])});}});
  await assert.rejects(demarrerPreview(b.options),/Preview UI non démarrée/);
  assert.equal(b.observations.length,60);assert.equal(b.observations.at(-1).code_reseau,'ECONNREFUSED');
  assert.equal(b.observations.at(-1).tentatives,60);assert.deepEqual(b.child.kills,['SIGTERM']);
  assert.doesNotMatch(JSON.stringify(b.observations),/canari|stack|password|token|provider/);
});
test('serveur HTTP 503 ne valide pas readiness ; une réponse 200 valide la reprise sans masquer le statut précédent',async()=>{
  let appel=0;const b=banc({sonder:async()=>++appel===1?{ok:false,status:503}:{ok:true,status:200}});
  await demarrerPreview(b.options);assert.deepEqual(b.observations.map(r=>r.statut_http),[503,200]);
});
test('sortie enfant ou échec spawn interdit toute readiness ; erreur arbitraire projetée en AUTRE',async()=>{
  const b=banc();b.child.exitCode=1;
  await assert.rejects(demarrerPreview(b.options),/Preview UI indisponible/);
  assert.equal(b.requetes.length,0);assert.equal(b.observations.at(-1).code_sortie,1);
  const c=banc({pause:async()=>{c.child.emit('error',Object.assign(new Error('canari'),{code:'code-secret'}));},sonder:async()=>({ok:false,status:503})});
  await assert.rejects(demarrerPreview(c.options),/Preview UI indisponible/);
  assert.equal(c.observations.at(-1).erreur_lancement,'AUTRE');assert.doesNotMatch(JSON.stringify(c.observations),/canari|secret/);
});
test('workflow vérifie la preview après build et avant création ; le mode préflight ne charge aucun pool/Auth',()=>{
  const workflow=readFileSync(new URL('../../.github/workflows/load-tests.yml',import.meta.url),'utf8').split('  dashboard-frontend:')[1];
  assert.ok(workflow.indexOf('npm run build')<workflow.indexOf('recette-dashboard-staging.mjs verify-preview'));
  assert.ok(workflow.indexOf('recette-dashboard-staging.mjs verify-preview')<workflow.indexOf('prepare-dashboard-pool.mjs prepare'));
  const script=readFileSync(new URL('../../scripts/ci/recette-dashboard-staging.mjs',import.meta.url),'utf8');
  const avantPool=script.slice(script.indexOf("if (action === 'verify-preview')"),script.indexOf('const membres = configurationUI(env)'));
  assert.match(avantPool,/demarrerPreview/);assert.doesNotMatch(avantPool,/lireSQL|configurationUI|webkit|\.rpc|\.auth/);
});
