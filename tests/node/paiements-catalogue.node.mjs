import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {controlerCataloguePaiements} from '../../scripts/ci/paiements-catalogue.mjs';
const source=readFileSync('tests/fixtures/paiements-liberaux/catalogue.sql','utf8');
const keys=[...source.matchAll(/'([a-z_]+)',\(SELECT count\(\*\)/g)].map(x=>x[1]);
const row=()=>({residus:0,compteurs:Object.fromEntries(keys.map(k=>[k,0])),routines_md5:'a'.repeat(32),triggers_md5:'b'.repeat(32),inventaire_md5:'c'.repeat(32)});
function harness() {
 const files=new Map(); const calls=[]; const state={rows:[row()],status:200};
 const env={STAGING_SUPABASE_PROJECT_REF:'mejpriaetwgtcstbgfid',STAGING_SUPABASE_ACCESS_TOKEN:'factice',RUNNER_TEMP:'/factice'};
 const options={env,read:(p)=>p.endsWith('catalogue.sql')?source:files.get(p),write:(p,s,o)=>{assert.equal(o.mode,0o600);assert.equal(o.flag,'wx');assert.ok(!files.has(p));files.set(p,s);},
 fetcher:async(url,init)=>{calls.push({url,init});return {ok:state.status===200,status:state.status,json:async()=>structuredClone(state.rows)};}};
 return {files,calls,state,env,options};
}
test('catalogue réel = lecture seule, 28 compteurs et droits/ACL',()=>{
 assert.equal(keys.length,28);assert.match(source,/BEGIN READ ONLY;/);assert.match(source,/p\.proacl/);assert.match(source,/security_definer_inventory/);
 assert.doesNotMatch(source,/\b(?:INSERT|UPDATE|DELETE|CREATE|DROP|TRUNCATE|ALTER)\b/i);
});
test('avant/après indépendante et égalité stricte, sans retry',async()=>{
 const h=harness();await controlerCataloguePaiements('avant',h.options);await controlerCataloguePaiements('apres',h.options);
 assert.equal(h.calls.length,2);assert.equal(h.files.size,2);
 for(const call of h.calls){assert.equal(call.url,'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');assert.equal(call.init.redirect,'error');assert.equal(JSON.parse(call.init.body).query,source);}
});
for(const bad of ['flripxtsyegjshnhzjkz','autre',''])test(`projet refusé avant transport ${bad}`,async()=>{
 const h=harness();h.env.STAGING_SUPABASE_PROJECT_REF=bad;await assert.rejects(controlerCataloguePaiements('avant',h.options),/CONTEXTE_REFUSE/);assert.equal(h.calls.length,0);
});
for(const change of ['montant','catalogue','residu','net','schema'])test(`écart/refus ${change}`,async()=>{
 const h=harness();await controlerCataloguePaiements('avant',h.options);
 if(change==='montant')h.state.rows[0].compteurs.paiements_soignant=1;
 if(change==='catalogue')h.state.rows[0].routines_md5='d'.repeat(32);
 if(change==='residu')h.state.rows[0].residus=1;
 if(change==='net')h.state.rows[0].compteurs.net_requests=1;
 if(change==='schema')delete h.state.rows[0].compteurs.auth_users;
 await assert.rejects(controlerCataloguePaiements('apres',h.options),/PAIEMENTS_CATALOGUE_(MODIFIE|ETAT_REFUSE)/);assert.equal(h.files.size,1);
});
test('échec HTTP ferme la preuve et ne relance pas',async()=>{
 const h=harness();h.state.status=500;await assert.rejects(controlerCataloguePaiements('avant',h.options),/^Error: PAIEMENTS_CATALOGUE_HTTP_500$/);assert.equal(h.calls.length,1);assert.equal(h.files.size,0);
});
test('routage migration : 51 suites conservées puis nouvelle suite, postcheck always',()=>{
 const y=readFileSync('.github/workflows/validate-pr.yml','utf8');
 assert.match(y,/tests\/security\/facturation-commissions-pieces-matrice-f1.test.sql\s+tests\/security\/paiements-liberaux-facture.test.sql/);
 assert.match(y,/name: Paiements — SELECT indépendant après succès ou échec\n\s+if: always\(\) && steps.migration_scope.outputs.has_migrations == 'true'/);
 assert.match(y,/postgres:17.6-bookworm@sha256:f3bd19c606e442c3d7bdfa8002e03fe260a1023351e0ea4598032022b68dd6e3/);
});
