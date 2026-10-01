import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {controlerCataloguePushCandidatures} from '../../scripts/ci/push-candidatures-catalogue.mjs';

const source=readFileSync('tests/fixtures/push-candidatures/catalogue.sql','utf8');
const keys=[...source.matchAll(/'([a-z_]+)',\(SELECT count\(\*\)/g)].map(x=>x[1]);
const hashes=['routines_md5','triggers_md5','inventaire_md5','contraintes_md5','indexes_md5','parametre_md5','externalisations_md5'];
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

const fixture=readFileSync('tests/security/push-candidatures.test.sql','utf8');
const migration=readFileSync('supabase/migrations/20261001142707_relayer_nouvelles_candidatures_push.sql','utf8');
test('isolement : verrou borné, photo privée complète et aucune désactivation de garde',()=>{
 assert.match(fixture,/SET LOCAL statement_timeout='90s';/);
 assert.match(fixture,/SET LOCAL lock_timeout='5s';/);
 const lock=fixture.indexOf('LOCK TABLE public.externalisation_actions IN SHARE ROW EXCLUSIVE MODE;');
 const photo=fixture.indexOf('SELECT id,to_jsonb(a) AS ligne FROM public.externalisation_actions a;');
 const update=fixture.indexOf('UPDATE public.externalisation_actions a');
 assert(lock>fixture.indexOf("SET LOCAL lock_timeout='5s';") && photo>lock && update>photo);
 assert.match(fixture,/tgenabled<>'D' AND \(tgtype::integer&16\)<>0/);
 assert.match(fixture,/ev_type='2' AND ev_enabled<>'D'/);
 assert.doesNotMatch(fixture,/DISABLE|session_replication_role|TRUNCATE|DELETE FROM public\.externalisation_actions/i);
 assert.doesNotMatch(fixture,/GRANT[^;]*push_candidatures_etrangeres/i);
 assert.match(fixture,/ROLLBACK;\s*$/);
});
test('isolement : les empreintes et le prédicat temporel viennent des deux claims réels',()=>{
 const claims=[...migration.matchAll(/CREATE OR REPLACE FUNCTION public\.fn_externalisations_a_traiter\([^\n]+\)[\s\S]*?AS \$function\$([\s\S]*?)\$function\$/g)];
 assert.equal(claims.length,2);
 const normal=s=>s.replace(/\s+/g,' ');
 const eligibility=s=>s.match(/\(a\.statut = 'PENDING'[\s\S]*?a\.cron_lock_at < now\(\) - interval '10 minutes'\)/)?.[0];
 const predicate=eligibility(fixture);assert(predicate);
 for(const [,body] of claims){
  assert(fixture.includes(createHash('md5').update(body).digest('hex')));
  assert.equal(normal(eligibility(body)),normal(predicate));
 }
 const classification=migration.match(/'private\.fn_externalisation_est_reelle\(externalisation_actions\)','([a-f0-9]{32})'/)[1];
 assert(fixture.includes(classification));
});
test('isolement : tous les workers fixes sont refusés en cas de collision, chaque retour est vérifié',()=>{
 const collision=fixture.match(/ligne->>'cron_lock_par' IN\s*\(([\s\S]*?)\)\)/)[1];
 const expected=['ancien-push-premier',...Array.from({length:3},(_,i)=>`ancien-push-recette-${i+1}`),
  'nouveau-push-sans-capacite','nouveau-push-recette-lot1','nouveau-push-recette-lot2'];
 assert.deepEqual([...collision.matchAll(/'([^']+)'/g)].map(x=>x[1]),expected);
 const assigned=[...fixture.matchAll(/r:=public\.fn_externalisations_a_traiter\([^\n]+;\n([^\n]+)/g)];
 assert.equal(assigned.length,4);
 for(const [,next] of assigned)assert.equal(next.trim(),'PERFORM pg_temp.verifier_claim_push(r);');
 assert.match(fixture,/FOR r IN SELECT public\.fn_externalisations_a_traiter\([^\n]+LOOP\s+PERFORM pg_temp\.verifier_claim_push\(r\);\s+END LOOP;/);
 assert.doesNotMatch(fixture,/LOOP NULL/);
 assert.match(fixture,/EXISTS\(SELECT 1 FROM push_candidatures_etrangeres e WHERE e.id::text=x->>'id'\)/);
 assert.match(fixture,/NOT EXISTS\(SELECT 1 FROM push_candidatures_actions_fixture f WHERE f.id::text=x->>'id'\)/);
});
test('isolement : seule projection des deux dates, contrôle complet avant restauration et ROLLBACK',()=>{
 assert.match(fixture,/\(to_jsonb\(a\)-'next_retry_at'-'cron_lock_at'\)\s+IS DISTINCT FROM \(e.ligne-'next_retry_at'-'cron_lock_at'\)/);
 assert.match(fixture,/a.next_retry_at IS DISTINCT FROM CASE/);
 assert.match(fixture,/a.cron_lock_at IS DISTINCT FROM CASE/);
 const restoration=fixture.slice(fixture.indexOf('DO $restauration$'));
 assert(restoration.indexOf('PERFORM pg_temp.verifier_isolement_push();')<restoration.indexOf('UPDATE public.externalisation_actions'));
 assert.match(restoration,/NOT EXISTS\(SELECT 1 FROM push_candidatures_actions_fixture f WHERE f.id=a.id\)/);
 assert.match(restoration,/to_jsonb\(a\) IS DISTINCT FROM e.ligne/);
 assert.match(restoration,/net.http_request_queue/);
 const updates=[...fixture.matchAll(/UPDATE public\.externalisation_actions a\s+SET ([\s\S]*?)\s+FROM push_candidatures_etrangeres/g)];
 assert.equal(updates.length,2);
 for(const [,set] of updates)assert.deepEqual([...set.matchAll(/(?:^|,)\s*([a-z_]+)=/g)].map(x=>x[1]),['next_retry_at','cron_lock_at']);
});
test('catalogue : empreinte complète ordonnée sans contenu de file exposé',()=>{
 assert.match(source,/SET LOCAL timezone='UTC';/);
 assert.match(source,/md5\(COALESCE\(jsonb_agg\(to_jsonb\(a\) ORDER BY a.id\)::text,'\[\]'\)\)\s+FROM public\.externalisation_actions a\) AS externalisations_md5/);
});
test('catalogue : file non vide inchangée acceptée, contenu dérivé sans différence de compte refusé',async()=>{
 const h=harness();h.state.rows[0].compteurs.externalisations=3;
 await controlerCataloguePushCandidatures('avant',h.options);
 await controlerCataloguePushCandidatures('apres',h.options);
 const changed=harness();changed.state.rows[0].compteurs.externalisations=3;
 await controlerCataloguePushCandidatures('avant',changed.options);
 changed.state.rows[0].externalisations_md5='c'.repeat(32);
 await assert.rejects(controlerCataloguePushCandidatures('apres',changed.options),/PUSH_CATALOGUE_MODIFIE/);
 assert.equal(changed.files.size,1);
});
