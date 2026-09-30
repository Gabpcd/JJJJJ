import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync,readFileSync,writeFileSync,rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { executerD } from '../../scripts/ci/prepare-candidatures-fixture.mjs';
import { catalogueD,manifesteD,validerCatalogueD,configurationD,STAGING_REF,STAGING_URL,validerEtatD } from '../../scripts/ci/candidatures-fixture-contract.mjs';
import { sqlAvantD,sqlSeedD,sqlEtatD } from '../../scripts/ci/candidatures-fixture-sql.mjs';
function banc(t){const dir=mkdtempSync(join(tmpdir(),'jolene-D2-node-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
 const env={STAGING_SUPABASE_PROJECT_REF:STAGING_REF,STAGING_SUPABASE_URL:STAGING_URL,STAGING_SUPABASE_ACCESS_TOKEN:'faux-management',STAGING_SUPABASE_SERVICE_ROLE_KEY:'faux-service',STAGING_SUPABASE_ANON_KEY:'faux-anon',LOAD_TEST_RUN_ID:'node-D2',LOAD_D_JOUR:'2026-10-14',LOAD_D_MANIFEST:join(dir,'manifest.json'),GITHUB_ENV:join(dir,'env-prive'),LOAD_D_EXECUTION_APPROUVEE:'DEUX_PROFILS'};
 const m=manifesteD(env.LOAD_TEST_RUN_ID,env.LOAD_D_JOUR), users=new Map(),calls=[],logs=[];let seeded=false,receipt=false,gen=0;
 const state=()=>({auth:users.size,profils:seeded?2:0,etablissements:seeded?1:0,missions:seeded?1:0,creneaux:seeded?1:0,preferences:seeded?3:0,notifications:0,limites:0,sessions:users.size,identites:users.size,candidatures:[],audits_conserves:receipt?2:seeded?1:0,recu_cleanup:receipt?1:0,inattendus:0});
 const b={env,m,users,calls,logs,fail:null,posts:0,deletes:0,state,fetchImpl:async(url,opts)=>{
   const body=opts.body?JSON.parse(opts.body):null;calls.push({url,method:opts.method,body});
   const res=(body,status=200)=>({status,ok:status>=200&&status<300,json:async()=>body});
   if(body?.query){if(b.fail==='sql')throw Error('CANARI-secret-SQL');
    if(body.query.includes('DO $d_seed$')){if(receipt)return res({message:'late'},500);seeded=true;if(b.fail==='seed-lost'){b.fail=null;throw Error('CANARI-secret-seed');}return res([{prepare:true}]);}
    if(body.query.includes('DO $d_guard$'))return res([{pret:true}]);
    if(body.query.includes('DO $d_check$')){if(b.fail==='dependance')return res({message:'CANARI-secret-dependance'},500);if(body.query.includes('DELETE FROM public.candidatures')){seeded=false;receipt=true;for(const u of users.values())u.app_metadata.load_cleanup_pending=true;if(b.fail==='cleanup-lost'){b.fail=null;throw Error('CANARI-secret-cleanup');}}return res([state()]);}
    return res([{...catalogueD,crons_actifs:0,audit_fk:0}]);
   }
   if(url.endsWith('/auth/v1/admin/users')){b.posts++;const manifest=JSON.parse(readFileSync(env.LOAD_D_MANIFEST));assert.equal(manifest.membres.length,3);assert.equal(manifest.authStatus[b.posts-1],'planned');
    const user={id:body.id,email:body.email,app_metadata:body.app_metadata};users.set(body.id,user);
    if(b.fail===`auth-${b.posts}`)throw Error('CANARI-secret-Auth');return res(user);}
   if(url.includes('/token?')){const u=[...users.values()].find(u=>u.email===body.email);if(b.fail==='login')return res({access_token:'CANARI-secret-token',user:{...u,id:'autre'} });return res({access_token:'CANARI-secret-token',user:u});}
   const id=url.split('/').at(-1);
   if(opts.method==='DELETE'){b.deletes++;users.delete(id);if(b.fail==='delete'){b.fail=null;throw Error('CANARI-secret-delete');}return res({});}
   return users.has(id)?res(users.get(id)):res({},404);
 }};
 b.run=action=>executerD({action,env,fetchImpl:b.fetchImpl,log:l=>logs.push(l),genererMotDePasse:()=>`Aa1!CANARI-secret-password-${gen++}-longueur-adequate`});return b;}
test('D2 destination, activation, overrides et run invalides refusent avant réseau',async t=>{const b=banc(t);
 for(const [key,value]of [['STAGING_SUPABASE_URL','https://flripxtsyegjshnhzjkz.supabase.co'],['LOAD_TEST_RUN_ID',"';SQL"],['LOAD_TEST_VUS','50'],['LOAD_D_EXECUTION_APPROUVEE','']]){const old=b.env[key];b.env[key]=value;await assert.rejects(b.run('prepare'));assert.equal(b.calls.length,0);b.env[key]=old;}
 assert.throws(()=>configurationD({...b.env,LOAD_D_JOUR:'2026-02-30'}));
});
test('catalogue est lecture seule et refuse toute dérive/cron actif/audit FK',async t=>{const b=banc(t);delete b.env.LOAD_D_EXECUTION_APPROUVEE;await b.run('catalogue');assert.equal(b.calls.length,1);assert.ok(b.calls[0].body.query.startsWith('SELECT'));
 for(const delta of [{fonctions:'autre'},{triggers:'autre'},{crons_actifs:1},{audit_fk:1}])assert.throws(()=>validerCatalogueD({...catalogueD,crons_actifs:0,audit_fk:0,...delta}));
});
test('3 identités distinctes préparées, secrets uniquement canal privé, cleanup puis reprise sans DELETE',async t=>{const b=banc(t);await b.run('prepare');assert.equal(b.posts,3);
 const file=readFileSync(b.env.LOAD_D_MANIFEST,'utf8');assert.ok(!file.includes('CANARI'));assert.equal(JSON.parse(file).status,'prepared');
 const privateEnv=readFileSync(b.env.GITHUB_ENV,'utf8');assert.ok(privateEnv.includes('CANARI-secret-password'));assert.ok(!privateEnv.includes('CANARI-secret-token'));
 assert.ok(!b.logs.filter(x=>!x.startsWith('::add-mask::')).join().includes('CANARI'));
 const result=await b.run('cleanup');assert.equal(result.auth,0);assert.equal(result.audits_conserves,2);assert.equal(b.deletes,3);await b.run('cleanup');assert.equal(b.deletes,3);
 await assert.rejects(b.run('prepare'),/déjà présent/);
});
for(const n of [1,2,3])test(`création Auth ${n} réponse perdue : IDs connus retrouvés sans recréation`,async t=>{const b=banc(t);b.fail=`auth-${n}`;await assert.rejects(b.run('prepare'),/ambiguë/);assert.equal(b.posts,n);assert.equal(b.users.size,n);b.fail=null;await b.run('cleanup');assert.equal(b.posts,n);assert.equal(b.deletes,n);});
test('login incohérent refuse préparation et ne transmet aucun secret au runner',async t=>{const b=banc(t);b.fail='login';await assert.rejects(b.run('prepare'),/Session D/);assert.throws(()=>readFileSync(b.env.GITHUB_ENV));b.fail=null;await b.run('cleanup');assert.equal(b.users.size,0);});
test('suppression réponse perdue : reprise GET + SQL sans deuxième DELETE du même utilisateur',async t=>{const b=banc(t);await b.run('prepare');b.fail='delete';await assert.rejects(b.run('cleanup'),/incomplet/);assert.equal(b.deletes,3);assert.equal(b.users.size,0);await b.run('cleanup');assert.equal(b.deletes,3);assert.equal(JSON.parse(readFileSync(b.env.LOAD_D_MANIFEST)).status,'cleaned');});
test('manifestes altérés/IDs additionnels/état invalide bloquent avant tout réseau',async t=>{for(const mutate of [m=>m.membres[1]=m.membres[0],m=>m.membres.push(m.membres[0]),m=>m.runId='autre',m=>m.status='inventé',m=>m.jwt='CANARI',m=>m.authStatus.pop()]){const b=banc(t);await b.run('prepare');const m=JSON.parse(readFileSync(b.env.LOAD_D_MANIFEST));mutate(m);writeFileSync(b.env.LOAD_D_MANIFEST,JSON.stringify(m));b.calls.length=0;await assert.rejects(b.run('cleanup'),/Manifeste/);assert.equal(b.calls.length,0);assert.equal(b.deletes,0);}});
test('profil altéré ou dépendance SQL : aucun DELETE Auth ni faux cleaned',async t=>{for(const fault of ['auth','dependance']){const b=banc(t);await b.run('prepare');if(fault==='auth')b.users.get(b.m.membres[2].userId).app_metadata.load_fixture_run='autre';else b.fail='dependance';await assert.rejects(b.run('cleanup'));assert.equal(b.deletes,0);assert.notEqual(JSON.parse(readFileSync(b.env.LOAD_D_MANIFEST)).status,'cleaned');}});
test('POST Auth lancé puis absent : résultat ambigu non transformé en cleaned',async t=>{const b=banc(t);b.fail='auth-1';await assert.rejects(b.run('prepare'));b.users.clear();b.fail=null;await assert.rejects(b.run('cleanup'),/incomplet/);assert.equal(b.deletes,0);assert.notEqual(JSON.parse(readFileSync(b.env.LOAD_D_MANIFEST)).status,'cleaned');});
test('SQL conserve triggers et audits, relie les refus FK et les verrous à prepare/cleanup',()=>{const m=manifesteD('controle-sql','2026-10-14');const seed=sqlSeedD(m),clean=sqlEtatD(m,true);
 for(const sql of [sqlAvantD(m),seed,sqlEtatD(m),clean]){assert.match(sql,/pg_advisory_xact_lock/);assert.match(sql,/SHARE ROW EXCLUSIVE/);assert.match(sql,/Catalogue D non conforme/);assert.doesNotMatch(sql,/DISABLE TRIGGER|session_replication_role|TRUNCATE/);}
 assert.match(seed,/seed tardif refusé/);assert.match(seed,/app.test_mode='true'/);assert.match(seed,/favoris_soignant_etab/);assert.match(clean,/Dépendance hors lot D/);assert.match(clean,/Ligne D modifiée/);assert.match(clean,/load_cleanup_pending/);assert.doesNotMatch(clean,/DELETE FROM public.journaux_audit/);assert.match(clean,/recu_cleanup/);
});
test('état vide ne prouve pas candidature, notification ou cleanup complet',()=>{const s={inattendus:0,candidatures:[],auth:0,profils:0,etablissements:0,missions:0,creneaux:0,preferences:0,notifications:0,limites:0,sessions:0,identites:0,recu_cleanup:1};assert.throws(()=>validerEtatD(s,'apres'));validerEtatD(s,'cleaned');assert.throws(()=>validerEtatD({...s,sessions:1},'cleaned'));});

test('réponses SQL seed/cleanup perdues après commit : reprise sans recréation',async t=>{
 for(const fault of ['seed-lost','cleanup-lost']){const b=banc(t);if(fault==='seed-lost'){b.fail=fault;await assert.rejects(b.run('prepare'),/ambiguë/);}else{await b.run('prepare');b.fail=fault;await assert.rejects(b.run('cleanup'),/ambiguë/);}
 await b.run('cleanup');assert.equal(b.posts,3);assert.equal(b.deletes,3);assert.equal(b.users.size,0);}
});
test('projection des résultats exclut les champs inconnus des fournisseurs',()=>{const s={inattendus:0,candidatures:[],auth:0,profils:0,etablissements:0,missions:0,creneaux:0,preferences:0,notifications:0,limites:0,sessions:0,identites:0,recu_cleanup:1,canari:'CANARI-secret-provider'};assert.ok(!JSON.stringify(validerEtatD(s,'cleaned')).includes('CANARI'));});

test('guards SQL rejettent les formes NULL avant tout DELETE ; recette réelle négative préparée',async()=>{
 const {sqlRecetteRollbackD}=await import('../../scripts/ci/generate-candidatures-rollback.mjs');
 const m=manifesteD('controle-null','2026-10-14'),clean=sqlEtatD(m,true);
 const notif=clean.slice(clean.indexOf('IF EXISTS(SELECT 1 FROM public.notifications'),clean.indexOf('Notifications D non corrélées'));
 assert.match(notif,/puisse vous accepter\.'\)\) IS NOT TRUE\)/);
 assert.doesNotMatch(notif,/AND NOT \(/);
 assert.match(clean,/load_fixture_run'='controle-null'\) IS NOT TRUE/);
 assert.ok(clean.indexOf('Notification D imprévue ou expédiée')<clean.indexOf('DELETE FROM public.notifications'));
 const proof=sqlRecetteRollbackD('regression-null','2026-10-14');
 assert.match(proof,/UPDATE public\.notifications SET lien=NULL/);
 assert.match(proof,/raw_app_meta_data=raw_app_meta_data-'role'/);
 assert.match(proof,/D2 négatif accepté/);assert.match(proof,/SQLERRM<>'Notification D imprévue ou expédiée'/);
 // La preuve réutilise le bloc cleanup du préparateur, pas une copie simplifiée.
 const proofManifest=manifesteD('sql-d2-regression-null','2026-10-14');
 const block=sqlEtatD(proofManifest,true).split('DO $d_check$')[1].split('END $d_check$;')[0];
 assert.ok(proof.includes(block.replaceAll("'","''")));
 assert.match(proof,/ERRCODE='JD201'/);assert.match(proof,/EXCEPTION WHEN SQLSTATE 'JD201'/);
 assert.match(proof,/D2 sentinelle rollback incomplète/);assert.match(proof,/ROLLBACK;\nSELECT 'D2_SQL_ROLLBACK'/);
 assert.doesNotMatch(proof,/COMMIT;|DISABLE TRIGGER|session_replication_role|DELETE FROM public.journaux_audit|https?:\/\/|encrypted_password|access_token/);
 assert.throws(()=>sqlRecetteRollbackD('', '2026-10-14'));
});

test('claim établissement détourné ou absent bloque cleanup avant SQL et DELETE',async t=>{
 for(const value of [undefined,'10000000-0000-4000-a000-000000000099']){
  const b=banc(t);await b.run('prepare');b.users.get(b.m.membres[2].userId).app_metadata.etablissement_id=value;
  b.calls.length=0;await assert.rejects(b.run('cleanup'),/altérée/);
  assert.equal(b.deletes,0);assert.equal(b.calls.some(c=>c.body?.query),false);
 }
 const m=manifesteD('confirmation-auth','2026-10-14');
 assert.match(sqlSeedD(m),/email_confirmed_at IS NOT NULL/);
 assert.ok(sqlSeedD(m).includes(`u.raw_app_meta_data->>'etablissement_id'='${m.membres[2].userId}'`));
});
