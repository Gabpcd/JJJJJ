import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {controlerCataloguePushCandidatures} from '../../scripts/ci/push-candidatures-catalogue.mjs';

const source=readFileSync('tests/fixtures/push-candidatures/catalogue.sql','utf8');
const keys=[...source.matchAll(/'([a-z_]+)',\(SELECT count\(\*\)/g)].map(x=>x[1]);
const hashes=['routines_md5','triggers_md5','inventaire_md5','contraintes_md5','indexes_md5','parametre_md5'];
const row=()=>({residus:0,compteurs:Object.fromEntries(keys.map(k=>[k,0])),...Object.fromEntries(hashes.map(k=>[k,'a'.repeat(32)]))});
function harness() {
 const files=new Map(), calls=[], state={rows:[row()],status:200};
 const env={STAGING_SUPABASE_PROJECT_REF:'mejpriaetwgtcstbgfid',STAGING_SUPABASE_ACCESS_TOKEN:'factice',RUNNER_TEMP:'/factice'};
 const options={env,read:p=>p.endsWith('catalogue.sql')?source:files.get(p),write:(p,s,o)=>{assert.equal(o.mode,0o600);assert.equal(o.flag,'wx');assert(!files.has(p));files.set(p,s);},
 fetcher:async(url,init)=>{calls.push({url,init});return {ok:state.status===200,status:state.status,json:async()=>structuredClone(state.rows)};}};
 return {files,calls,state,env,options};
}
test('SELECT seul : 24 compteurs, catalogue et préfixe exact, aucun payload ni token renvoyé',()=>{
 assert.equal(keys.length,24);assert.equal(new Set(keys).size,24);assert.match(source,/BEGIN READ ONLY;/);assert.match(source,/ROLLBACK;\s*$/);
 assert.doesNotMatch(source,/\b(?:INSERT|UPDATE|DELETE|CREATE|DROP|TRUNCATE|ALTER|GRANT|REVOKE)\b/i);
 for(const name of ['badges_soignant','streaks_soignant','preferences_notifications_par_evenement','types_comptes_auth','membres_etablissement','swipes','missions_sauvegardees'])assert(source.includes('public.'+name));
 for(const name of ['pg_get_indexdef','pg_get_constraintdef','p.proacl','security_definer_inventory',"cle='inscriptions_publiques_actives'","LIKE '71140000-%'"])assert(source.includes(name));
 assert.doesNotMatch(source,/SELECT\s+(?:\*|token|endpoint|p256dh|auth_key|payload|email)\s+FROM/i);
});
test('avant/après stricts, deux lectures sans relance ; preuves locales privées',async()=>{
 const h=harness();await controlerCataloguePushCandidatures('avant',h.options);await controlerCataloguePushCandidatures('apres',h.options);
 assert.equal(h.calls.length,2);assert.equal(h.files.size,2);
 for(const c of h.calls){assert.equal(c.url,'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');assert.equal(c.init.redirect,'error');assert(c.init.signal);assert.equal(JSON.parse(c.init.body).query,source);}
});
for(const project of ['flripxtsyegjshnhzjkz','wnepopwygokbhlqghydb','autre',''])test(`destination refusée avant transport : ${project}`,async()=>{
 const h=harness();h.env.STAGING_SUPABASE_PROJECT_REF=project;await assert.rejects(controlerCataloguePushCandidatures('avant',h.options),/CONTEXTE_REFUSE/);assert.equal(h.calls.length,0);
});
for(const key of hashes)test(`dérive ${key} refuse la preuve d’annulation`,async()=>{
 const h=harness();await controlerCataloguePushCandidatures('avant',h.options);h.state.rows[0][key]='b'.repeat(32);
 await assert.rejects(controlerCataloguePushCandidatures('apres',h.options),/MODIFIE/);assert.equal(h.files.size,1);
});
for(const state of ['residus','net','cron','nouveau_membre','compteur_absent','compteur_remplace','extra_libre','negatif','nombre_non_entier'])test(`état inattendu ${state} refusé`,async()=>{
 const h=harness();await controlerCataloguePushCandidatures('avant',h.options);const r=h.state.rows[0];
 if(state==='residus')r.residus=1;
 if(state==='net')r.compteurs.net_requests=1;
 if(state==='cron')r.compteurs.cron_actifs=1;
 if(state==='nouveau_membre')r.compteurs.membres=1;
 if(state==='compteur_absent')delete r.compteurs.badges;
 if(state==='compteur_remplace'){delete r.compteurs.badges;r.compteurs.libre=0;}
 if(state==='extra_libre')r.secret='CANARI';
 if(state==='negatif')r.compteurs.swipes=-1;
 if(state==='nombre_non_entier')r.compteurs.swipes=1.5;
 await assert.rejects(controlerCataloguePushCandidatures('apres',h.options),/PUSH_CATALOGUE_(MODIFIE|ETAT_REFUSE)/);assert.equal(h.files.size,1);
});
test('erreur HTTP : pas de contenu brut ni de retry',async()=>{
 const h=harness();h.state.status=500;await assert.rejects(controlerCataloguePushCandidatures('avant',h.options),/^Error: PUSH_CATALOGUE_HTTP_500$/);assert.equal(h.calls.length,1);assert.equal(h.files.size,0);
});
test('après sans preuve avant refuse, aucun faux constat indépendant',async()=>{
 const h=harness();await assert.rejects(controlerCataloguePushCandidatures('apres',h.options));assert.equal(h.files.size,0);
});
test('raccord sans nouveau gate : migration, verrou existant et contrôle always',()=>{
 const y=readFileSync('.github/workflows/validate-pr.yml','utf8');
 assert.match(y,/node --test tests\/node\/push-candidatures.node.mjs tests\/node\/push-candidatures-catalogue.node.mjs/);
 assert.match(y,/name: Push candidatures — catalogue avant transaction\n\s+if: steps.migration_scope.outputs.has_migrations == 'true'/);
 assert.match(y,/name: Push candidatures — SELECT indépendant après succès ou échec\n\s+if: always\(\) && steps.migration_scope.outputs.has_migrations == 'true'/);
 assert.equal((y.match(/tests\/security\/push-candidatures.test.sql/g)||[]).length,1);
 assert(y.indexOf('run: node scripts/ci/push-candidatures-catalogue.mjs avant')<y.indexOf('name: Exécuter les migrations ajoutées'));
 assert(y.indexOf('run: node scripts/ci/push-candidatures-catalogue.mjs apres')>y.indexOf('name: Exécuter les migrations ajoutées'));
});
