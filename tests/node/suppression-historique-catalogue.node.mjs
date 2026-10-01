import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { controlerCatalogueSuppression } from '../../scripts/ci/suppression-historique-catalogue.mjs';
const source=readFileSync('tests/fixtures/suppression-historique-financier/catalogue.sql','utf8');
const keys=[...source.matchAll(/'([a-z_]+)',\(SELECT count\(\*\)/g)].map(x=>x[1]);
function harness() {
  const files=new Map(); const calls=[];
  const state={rows:[{residus:0,compteurs:Object.fromEntries(keys.map(k=>[k,0])),routines_md5:'a'.repeat(32),triggers_md5:'b'.repeat(32),inventaire_md5:'c'.repeat(32)}],status:200};
  const env={STAGING_SUPABASE_PROJECT_REF:'mejpriaetwgtcstbgfid',STAGING_SUPABASE_ACCESS_TOKEN:'factice',RUNNER_TEMP:'/factice'};
  const options={env,read:(p)=>p.endsWith('catalogue.sql')?source:files.get(p),
    write:(p,s,o)=>{assert.equal(o.mode,0o600);assert.equal(o.flag,'wx');assert.ok(!files.has(p));files.set(p,s);},
    fetcher:async(url,init)=>{calls.push({url,init});return {ok:state.status===200,status:state.status,json:async()=>structuredClone(state.rows)};}};
  return {files,calls,state,env,options};
}
test('SELECT seul : métadonnées et 24 compteurs, sans lignes personnelles',()=>{
  assert.equal(keys.length,24);assert.match(source,/BEGIN READ ONLY;/);assert.match(source,/p\.proacl/);
  assert.match(source,/suppressions_compte_confirmees/);assert.match(source,/rate_limits/);
  assert.doesNotMatch(source,/\b(?:INSERT|UPDATE|DELETE|CREATE|DROP|TRUNCATE|ALTER)\b/i);
});
test('avant/après strict, cible unique, transport borné et deux fichiers exclusifs',async()=>{
  const h=harness();await controlerCatalogueSuppression('avant',h.options);await controlerCatalogueSuppression('apres',h.options);
  assert.equal(h.calls.length,2);assert.equal(h.files.size,2);
  for(const {url,init} of h.calls) {
    assert.equal(url,'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');
    assert.equal(init.redirect,'error');assert.ok(init.signal instanceof AbortSignal);assert.equal(JSON.parse(init.body).query,source);
  }
});
for(const bad of ['flripxtsyegjshnhzjkz','autre',''])test(`cible refusée avant transport : ${bad}`,async()=>{
  const h=harness();h.env.STAGING_SUPABASE_PROJECT_REF=bad;
  await assert.rejects(controlerCatalogueSuppression('avant',h.options),/CONTEXTE_REFUSE/);assert.equal(h.calls.length,0);
});
for(const change of ['compteur','catalogue','residu','reseau','nombre','nom','negatif','null'])test(`écart/refus : ${change}`,async()=>{
  const h=harness();await controlerCatalogueSuppression('avant',h.options);
  const row=h.state.rows[0];
  if(change==='compteur')row.compteurs.recus=1;
  if(change==='catalogue')row.inventaire_md5='d'.repeat(32);
  if(change==='residu')row.residus=1;
  if(change==='reseau')row.compteurs.net_requests=1;
  if(change==='nombre')delete row.compteurs.auth_users;
  if(change==='nom'){delete row.compteurs.auth_users;row.compteurs.inconnu=0;}
  if(change==='negatif')row.compteurs.paiements=-1;
  if(change==='null')h.state.rows=[null];
  await assert.rejects(controlerCatalogueSuppression('apres',h.options),/SUPPRESSION_CATALOGUE_(MODIFIE|ETAT_REFUSE)/);
  assert.equal(h.files.size,1);
});
test('HTTP en échec : aucun retry ni preuve écrite',async()=>{
  const h=harness();h.state.status=500;
  await assert.rejects(controlerCatalogueSuppression('avant',h.options),/HTTP_500/);assert.equal(h.calls.length,1);assert.equal(h.files.size,0);
});
test('preuve avant absente : aucun succès ni fichier après',async()=>{
  const h=harness();await assert.rejects(controlerCatalogueSuppression('apres',h.options));assert.equal(h.files.size,0);
});
test('CI garde le témoin PSC et impose un SELECT après, même après erreur SQL',()=>{
  const y=readFileSync('.github/workflows/validate-pr.yml','utf8');
  assert.match(y,/tests\/security\/suppression-compte-isolation-psc.test.sql\s+tests\/security\/suppression-compte-historique-financier.test.sql/);
  assert.match(y,/name: Suppression — SELECT indépendant après succès ou échec\n\s+if: always\(\) && steps.migration_scope.outputs.has_migrations == 'true'/);
  assert.match(y,/node --test tests\/node\/suppression-historique-catalogue.node.mjs/);
});
