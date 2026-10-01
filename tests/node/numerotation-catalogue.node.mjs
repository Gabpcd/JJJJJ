import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {controlerCatalogueNumerotation} from '../../scripts/ci/numerotation-catalogue.mjs';
const source=readFileSync('tests/fixtures/numerotation-catalogue.sql','utf8');
const keys='auth_users soignants etablissements missions presences creneaux equipes litiges honoraires commissions audit_factures audits notifications preferences conformite suivi emails externalisations escrow refunds cessions scoring escrow_release stripe_transfers paiements_soignant claims archives net_requests baux'.split(' ');
const row=()=>({residus:0,compteurs:Object.fromEntries(keys.map(k=>[k,0])),routines_md5:'a'.repeat(32),triggers_md5:'b'.repeat(32),inventaire_md5:'c'.repeat(32),baux_schema_md5:'d'.repeat(32)});
function harness() {
 const files=new Map(); const calls=[]; const state={rows:[row()],status:200};
 const env={STAGING_SUPABASE_PROJECT_REF:'mejpriaetwgtcstbgfid',STAGING_SUPABASE_ACCESS_TOKEN:'factice',RUNNER_TEMP:'/factice'};
 const options={env,read:(p)=>p.endsWith('.sql')?source:files.get(p),write:(p,s,o)=>{assert.equal(o.mode,0o600);assert.equal(o.flag,'wx');assert.ok(!files.has(p));files.set(p,s);},
 fetcher:async(url,init)=>{calls.push({url,init});return {ok:state.status===200,status:state.status,json:async()=>structuredClone(state.rows)};}};
 return {files,calls,state,env,options};
}
test('catalogue réel en lecture seule : 29 compteurs, bail optionnel, corps/ACL et DDL',()=>{
 assert.equal(keys.length,29);assert.match(source,/BEGIN READ ONLY;/);assert.match(source,/p\.proacl/);assert.match(source,/security_definer_inventory/);
 assert.match(source,/c\.relforcerowsecurity/);assert.match(source,/pg_get_constraintdef/);assert.match(source,/pg_policy/);
 assert.match(source,/CASE WHEN to_regclass\('private.generations_factures_honoraires'\) IS NULL THEN 0/);
 assert.equal([...source.matchAll(/query_to_xml\(/g)].length,1);
 assert.match(source,/'SELECT count\(\*\) AS compteur FROM private.generations_factures_honoraires'/);
 assert.doesNotMatch(source,/\b(?:INSERT|UPDATE|DELETE|CREATE|DROP|TRUNCATE|ALTER)\b/i);
});
test('deux lectures indépendantes et égalité stricte, sans retry',async()=>{
 const h=harness();await controlerCatalogueNumerotation('avant',h.options);await controlerCatalogueNumerotation('apres',h.options);
 assert.equal(h.calls.length,2);assert.equal(h.files.size,2);
 for(const call of h.calls){assert.equal(call.url,'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');assert.equal(call.init.redirect,'error');assert.equal(JSON.parse(call.init.body).query,source);}
});
for(const bad of ['flripxtsyegjshnhzjkz','autre',''])test(`projet refusé avant transport ${bad}`,async()=>{
 const h=harness();h.env.STAGING_SUPABASE_PROJECT_REF=bad;await assert.rejects(controlerCatalogueNumerotation('avant',h.options),/CONTEXTE_REFUSE/);assert.equal(h.calls.length,0);
});
for(const change of ['archive','bail','catalogue','ddl','residu','net','schema','cle_inconnue','cle_compteur_inconnue','compteur_null','compteur_negatif'])test(`écart/refus ${change}`,async()=>{
 const h=harness();await controlerCatalogueNumerotation('avant',h.options);
 if(change==='archive')h.state.rows[0].compteurs.archives=1;
 if(change==='bail')h.state.rows[0].compteurs.baux=1;
 if(change==='catalogue')h.state.rows[0].routines_md5='e'.repeat(32);
 if(change==='ddl')h.state.rows[0].baux_schema_md5='f'.repeat(32);
 if(change==='residu')h.state.rows[0].residus=1;
 if(change==='net')h.state.rows[0].compteurs.net_requests=1;
 if(change==='schema')delete h.state.rows[0].compteurs.auth_users;
 if(change==='cle_inconnue')h.state.rows[0].autre=true;
 if(change==='cle_compteur_inconnue'){delete h.state.rows[0].compteurs.auth_users;h.state.rows[0].compteurs.inconnu=0;}
 if(change==='compteur_null')h.state.rows[0].compteurs.baux=null;
 if(change==='compteur_negatif')h.state.rows[0].compteurs.baux=-1;
 await assert.rejects(controlerCatalogueNumerotation('apres',h.options),/NUMEROTATION_CATALOGUE_(MODIFIE|ETAT_REFUSE)/);assert.equal(h.files.size,1);
});
test('échec HTTP fermé sans corps ni retry',async()=>{
 const h=harness();h.state.status=500;await assert.rejects(controlerCatalogueNumerotation('avant',h.options),/^Error: NUMEROTATION_CATALOGUE_HTTP_500$/);assert.equal(h.calls.length,1);assert.equal(h.files.size,0);
});
test('raccord transactionnel seulement et catalogue indépendant même après erreur',()=>{
 const y=readFileSync('.github/workflows/validate-pr.yml','utf8');
 assert.match(y,/tests\/security\/paiements-liberaux-facture.test.sql\s+tests\/security\/numerotation-factures.test.sql/);
 assert.match(y,/name: Numérotation — SELECT indépendant après succès ou échec\n\s+if: always\(\) && steps.migration_scope.outputs.has_migrations == 'true'/);
 assert.match(y,/false\) SQL_TESTS=\(tests\/security\/facturation-remplacement-commission-f1.test.sql tests\/security\/facturation-heures-ajustees-chainage-f1.test.sql tests\/security\/facturation-commissions-pieces-matrice-f1.test.sql\)/);
 assert.match(y,/postgres:17.6-bookworm@sha256:f3bd19c606e442c3d7bdfa8002e03fe260a1023351e0ea4598032022b68dd6e3/);
});
