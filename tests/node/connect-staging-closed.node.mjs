import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { checkContract, checkContext, checkAssets, checkSnapshot, checkPending, executeClosed, digest, canonical, git, PROJECT, REPOSITORY } from '../../scripts/ci/connect-staging-closed.mjs';
import { catalogueSql, transactionSql } from '../../scripts/ci/connect-staging-closed-sql.mjs';
const main='1'.repeat(40),candidate='2'.repeat(40),tree='3'.repeat(40);
const migration='-- Source synthétique de transport uniquement\nBEGIN;\nSELECT 1;\nCOMMIT;\n';
const capacity='-- Fragment synthétique sans acteur ni effet fournisseur\nSELECT 2;';
const admission='-- Fragment admission synthétique fermé\nSELECT 3;';
const manifest={candidate:{sha:candidate,tree},migrationSha256:digest(migration),capacitySha256:digest(capacity),admissionSha256:digest(admission)};
const contract={schemaVersion:1,ready:true,projectRef:PROJECT,protocolEnabled:false,capabilityEnabled:false,
 candidate:manifest.candidate,reviewedManifest:{migrationSha256:manifest.migrationSha256,capacitySha256:manifest.capacitySha256,admissionSha256:manifest.admissionSha256,manifestSha256:digest(JSON.stringify(canonical(manifest)))},
 requiredCiRuns:['123','456'],expectedBefore:{catalogue:'a'.repeat(32),registry:'b'.repeat(32)},expectedAfter:{catalogue:'c'.repeat(32),registry:'d'.repeat(32)},reason:'Fixture de transport hors réseau'};
const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:REPOSITORY,GITHUB_REF:'refs/heads/main',GITHUB_SHA:main,
 EXPECTED_MAIN_SHA:main,EXPECTED_CANDIDATE_SHA:candidate,EXPECTED_CANDIDATE_TREE:tree,EXPECTED_MANIFEST_SHA256:contract.reviewedManifest.manifestSha256,
 GITHUB_RUN_ID:'789',GITHUB_RUN_ATTEMPT:'1',STAGING_SUPABASE_ACCESS_TOKEN:'management-secret-sentinel',GITHUB_TOKEN:'github-secret-sentinel'};
const local={mainSha:main,mainClean:true,candidateSha:candidate,candidateTree:tree,candidateClean:true,migration,capacity,admission,migrationVersions:['20260930082312','20261001201055']};
const before={...contract.expectedBefore,versions:['20260930082312'],rows:'e'.repeat(32),quiescent:true,gate_closed:true,capacity_closed:true};
const after={...contract.expectedAfter,versions:local.migrationVersions,rows:before.rows,quiescent:true,gate_closed:true,capacity_closed:true};
const response=x=>({ok:true,text:async()=>JSON.stringify(x)});
function harness(options={}){
 const calls=[],reports=[];let mutation=0,catalogue=0;
 const fetchImpl=async(url,request)=>{
  calls.push({url,...request});
  assert.equal(request.redirect,'error');assert.ok(request.signal instanceof AbortSignal);
  if(url.startsWith('https://api.github.com/')){
   assert.equal(request.headers.Authorization,'Bearer github-secret-sentinel');
   if(url.endsWith('/git/ref/heads/main'))return response({ref:'refs/heads/main',object:{sha:options.mainMoved?'9'.repeat(40):main,type:'commit'}});
   if(url.includes('/git/commits/'))return response({sha:candidate,tree:{sha:options.treeDrift?'9'.repeat(40):tree}});
   if(url.includes('/actions/runs/'))return response({id:Number(url.split('/').at(-1)),status:'completed',conclusion:options.badCi?'failure':'success',head_sha:options.ciShaDrift?'9'.repeat(40):candidate,
     repository:{full_name:REPOSITORY},head_repository:{full_name:options.fork?'attacker/repo':REPOSITORY},event:'pull_request'});
  }
  assert.ok(url.startsWith(`https://api.supabase.com/v1/projects/${PROJECT}`));
  assert.equal(request.headers.Authorization,'Bearer management-secret-sentinel');
  if(request.method==='GET')return response({id:PROJECT,region:'eu-west-1',status:'ACTIVE_HEALTHY',database:{host:options.badHost?'db.other.supabase.co':`db.${PROJECT}.supabase.co`}});
  assert.equal(url,`https://api.supabase.com/v1/projects/${PROJECT}/database/query`);
  const body=JSON.parse(request.body);
  if(body.read_only){catalogue++;if(options.rawError) return {ok:false,text:async()=>'{"secret":"raw provider detail"}'};
   if(mutation>=2)return response([{...after,...(options.afterChange?{rows:'f'.repeat(32)}:{})}]);
   return response([{...before,...(options.driftRollback&&catalogue===2?{rows:'f'.repeat(32)}:{}),...(options.notQuiet?{quiescent:false}:{})}]);}
  mutation++;
  if(mutation===1){assert.match(body.query,/ROLLBACK;$/);if(options.dryFailure)throw new Error('private SQL raw failure');}
  else {assert.equal(mutation,2);assert.match(body.query,/COMMIT;$/);if(options.lostCommit)throw new Error('lost response with private token');}
  return response([]);
 };
 return {calls,reports,run:()=>executeClosed({env:{...env,...options.env},local:{...local,...options.local},contract:options.contract??contract,fetchImpl,checkpoint:r=>{reports.push(r);if(options.checkpointFailure||(options.commitCheckpointFailure&&r.phase==='commit_once'))throw Error('disk detail');}})};
}
test('contrat versionné livré fermé : aucun appel ni credential requis',async()=>{
 const c=JSON.parse(readFileSync('scripts/ci/connect-staging-closed.contract.json','utf8'));const h=harness({contract:c,env:{STAGING_SUPABASE_ACCESS_TOKEN:undefined,GITHUB_TOKEN:undefined}});
 const r=await h.run();assert.equal(r.code,'READINESS_CLOSED');assert.equal(h.calls.length,0);assert.equal(r.commitAttempted,false);
});
for(const [key,value] of [['GITHUB_EVENT_NAME','push'],['GITHUB_REPOSITORY','attacker/repo'],['GITHUB_REF','refs/heads/feature'],['GITHUB_RUN_ATTEMPT','2'],['GITHUB_SHA','f'.repeat(40)],['EXPECTED_MAIN_SHA','f'.repeat(40)]])
 test(`refus avant réseau : ${key}`,async()=>{const h=harness({env:{[key]:value}});assert.equal((await h.run()).code,'TRUSTED_MAIN_FIRST_ATTEMPT_REQUIRED');assert.equal(h.calls.length,0);});
for(const key of ['EXPECTED_CANDIDATE_SHA','EXPECTED_CANDIDATE_TREE','EXPECTED_MANIFEST_SHA256'])
 test(`pin dispatch ${key}`,async()=>{const h=harness({env:{[key]:'9'.repeat(key.includes('256')?64:40)}});assert.equal((await h.run()).code,'DISPATCH_PIN_MISMATCH');assert.equal(h.calls.length,0);});
for(const [key,value] of [['projectRef','flripxtsyegjshnhzjkz'],['protocolEnabled',true],['capabilityEnabled',true]])
 test(`aucune ouverture ${key}`,()=>assert.throws(()=>checkContract({...contract,[key]:value}),/CONTRACT_REFUSED/));
test('manifest obligatoire et authentifié par son empreinte',()=>assert.throws(()=>checkContract({...contract,reviewedManifest:{...contract.reviewedManifest,capacitySha256:'f'.repeat(64)}}),/MANIFEST_PIN_REQUIRED/));
for(const v of [[],['123','123'],['abc']])test(`liste CI explicitement fermée ${JSON.stringify(v)}`,()=>assert.throws(()=>checkContract({...contract,requiredCiRuns:v}),/CI_RUN_PINS_REQUIRED/));
for(const key of ['candidateSha','candidateTree','candidateClean'])test(`arbre local ${key}`,()=>assert.throws(()=>checkAssets(contract,{...local,[key]:false}),/CANDIDATE_TREE_MISMATCH/));
for(const key of ['migration','capacity','admission'])test(`octets ${key} différents`,()=>assert.throws(()=>checkAssets(contract,{...local,[key]:local[key]+'\n'}),/ASSET_DIGEST_MISMATCH/));
for(const options of [{mainMoved:true},{treeDrift:true},{badCi:true},{ciShaDrift:true},{fork:true},{badHost:true},{notQuiet:true},{rawError:true}])test(`précontrôle refuse ${Object.keys(options)[0]}`,async()=>{
 const h=harness(options),r=await h.run();assert.equal(r.status,'failed');assert.equal(r.commitAttempted,false);
 assert.equal(h.calls.filter(x=>x.body&&JSON.parse(x.body).read_only===false).length,0);
});
test('seul chemin de succès : rollback puis COMMIT unique, catalogue strict',async()=>{
 const h=harness(),r=await h.run();assert.equal(r.status,'success');assert.equal(r.dryRunVerified,true);assert.equal(r.commitConfirmed,true);assert.equal(r.businessRowsUnchanged,true);
 const writes=h.calls.filter(x=>x.body&&JSON.parse(x.body).read_only===false);assert.equal(writes.length,2);
 assert.ok(h.reports.some(x=>x.commitAttempted&&!x.commitConfirmed));
 assert.equal(r.providerInvoked,false);assert.equal(r.authCreated,false);assert.equal(r.edgeDeployed,false);
 const evidence=JSON.stringify(h.reports);assert.ok(!/secret-sentinel|SELECT|INSERT|Bearer|private SQL/.test(evidence));
});
for(const options of [{dryFailure:true},{driftRollback:true},{checkpointFailure:true},{commitCheckpointFailure:true}])test(`aucun COMMIT après ${Object.keys(options)[0]}`,async()=>{
 const h=harness(options),r=await h.run();assert.equal(r.status,'failed');assert.equal(r.commitAttempted,false);
 assert.ok(!h.calls.some(x=>x.body&&JSON.parse(x.body).read_only===false&&JSON.parse(x.body).query.endsWith('COMMIT;')));
});
test('réponse COMMIT perdue : rouge ambigu, constat uniquement, aucun deuxième COMMIT',async()=>{
 const h=harness({lostCommit:true}),r=await h.run();assert.equal(r.status,'uncertain');assert.equal(r.commitConfirmed,false);assert.equal(r.closedStateVerified,true);
 assert.equal(h.calls.filter(x=>x.body&&JSON.parse(x.body).query.endsWith('COMMIT;')).length,1);
 assert.ok(!JSON.stringify(r).includes('private token'));
});
test('post-catalogue incohérent ne devient pas succès',async()=>{const h=harness({afterChange:true}),r=await h.run();assert.equal(r.status,'uncertain');assert.equal(r.businessRowsUnchanged,false);assert.equal(r.commitConfirmed,false);});
test('inventaire incomplet, migration étrangère et historique déjà appliqué refusés',()=>{
 assert.throws(()=>checkPending(local,{...before,versions:[]},'before'),/MIGRATION_HISTORY_MISMATCH/);
 assert.throws(()=>checkPending(local,{...before,versions:[...before.versions,'20261099999999']},'before'),/MIGRATION_HISTORY_MISMATCH/);
 assert.throws(()=>checkPending(local,after,'before'),/MIGRATION_HISTORY_MISMATCH/);
});
test('forme fermée des constats, état et empreinte des données',()=>{
 for(const changed of [{extra:'raw'},{gate_closed:false},{capacity_closed:false},{rows:'raw'}])assert.throws(()=>checkSnapshot([{...before,...changed}],contract,'before'));
 assert.throws(()=>checkSnapshot([{...after,rows:'f'.repeat(32)}],contract,'after',before),/BUSINESS_ROWS_CHANGED/);
});
test('SQL : unique transaction, assertions avant/après, aucune activation',()=>{
 const sql=transactionSql(local,contract,before,true);
 const executable=sql.replace(/\$jolene_migration_source\$[\s\S]*?\$jolene_migration_source\$/g,"'SOURCE'");
 assert.equal((executable.match(/^BEGIN;/gm)||[]).length,1);assert.equal((executable.match(/^ COMMIT;/gm)||[]).length,1);
 assert.match(sql,/LOCK TABLE supabase_migrations.schema_migrations/);assert.match(sql,/INSERT INTO supabase_migrations.schema_migrations/);
 assert.equal((sql.match(/CONNECT_STAGING_CATALOGUE_REFUSED/g)||[]).length,2);
 assert.equal((sql.match(/SET LOCAL search_path=pg_catalog;\n DO \$closed_check\$/g)||[]).length,2);
 assert.ok(!/enabled\s*=\s*true|http_post|http_get|stripe\.com|service_role.*Bearer/i.test(sql));
 for(const after of [false,true]){const ro=catalogueSql(after);assert.match(ro,/^BEGIN READ ONLY; SET LOCAL search_path=pg_catalog;/);assert.match(ro,/ROLLBACK;$/);assert.ok(!/vault\.|decrypted_secret/.test(ro));}
});
test('fragments non transactionnels ou injection de délimiteur refusés',()=>{
 assert.throws(()=>transactionSql({...local,migration:'SELECT 1;'},contract,before,true),/MIGRATION_TRANSACTION_REFUSED/);
 assert.throws(()=>transactionSql({...local,capacity:'COMMIT;'},contract,before,true),/CAPACITY_FRAGMENT_REFUSED/);
 assert.throws(()=>transactionSql({...local,admission:'COMMIT;'},contract,before,true),/ADMISSION_FRAGMENT_REFUSED/);
 assert.throws(()=>transactionSql({...local,migration:migration.replace('SELECT 1;','SELECT $jolene_migration_source$;')},contract,before,true),/SQL_DELIMITER_COLLISION/);
});
test('workflow manuel, main, staging séquentiel, aucun CLI/secrets fournisseurs',()=>{
 const yaml=readFileSync('.github/workflows/connect-staging-closed.yml','utf8');
 assert.match(yaml,/workflow_dispatch:/);assert.ok(!/^  (push|pull_request|schedule):/m.test(yaml));
 assert.match(yaml,/group: jolene-supabase-staging-writes\n  queue: max\n  cancel-in-progress: false/);
 assert.match(yaml,/github.ref == 'refs\/heads\/main'/);
 assert.ok(yaml.indexOf('mjs resolve')<yaml.indexOf('secrets.STAGING_SUPABASE_ACCESS_TOKEN'));
 assert.ok(!/npm (ci|install)|supabase .*deploy|STRIPE_TEST_SECRET|SERVICE_ROLE|DB_PASSWORD/.test(yaml));
});

test('le processus Git ne reçoit aucun secret ni override hérité du job',()=>{
 const directory=mkdtempSync(join(tmpdir(),'jolene-git-env-'));
 try{
  // Véritable execFileSync, remplaçant seulement le binaire par un témoin
  // local qui rapporte son environnement ; aucun dépôt ni réseau n'est touché.
  writeFileSync(join(directory,'git'),`#!${process.execPath}\nprocess.stdout.write(JSON.stringify(process.env));\n`,{mode:0o700});
  const received=JSON.parse(git(directory,['status','--porcelain'],{
   PATH:directory,STAGING_SUPABASE_ACCESS_TOKEN:'staging-secret-sentinel',GITHUB_TOKEN:'github-secret-sentinel',GH_TOKEN:'gh-secret-sentinel',
   SUPABASE_SERVICE_ROLE_KEY:'service-secret-sentinel',STRIPE_SECRET_KEY:'stripe-secret-sentinel',
   HOME:'/untrusted-home',XDG_CONFIG_HOME:'/untrusted-config',SSH_AUTH_SOCK:'/untrusted-agent',NODE_OPTIONS:'--require=/untrusted-preload',
   GIT_DIR:'/untrusted-repo',GIT_WORK_TREE:'/untrusted-tree',GIT_EXEC_PATH:'/untrusted-bin',GIT_ASKPASS:'/untrusted-askpass',GIT_SSH_COMMAND:'/untrusted-ssh',
   GIT_CONFIG_NOSYSTEM:'0',GIT_CONFIG_GLOBAL:'/untrusted-global',GIT_TERMINAL_PROMPT:'1',GIT_CONFIG_COUNT:'1',GIT_CONFIG_KEY_0:'alias.status',GIT_CONFIG_VALUE_0:'!untrusted',
  }));
  // CoreFoundation ajoute cette valeur locale lors du démarrage de Node sur
  // macOS ; elle ne provient pas de l'environnement transmis à execFileSync.
  if(process.platform==='darwin' && '__CF_USER_TEXT_ENCODING' in received){
   assert.match(received.__CF_USER_TEXT_ENCODING,/^0x[0-9a-f]+:0x[0-9a-f]+:0x[0-9a-f]+$/i);
   delete received.__CF_USER_TEXT_ENCODING;
  }
  assert.deepEqual(received,{PATH:directory,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'});
 }finally{rmSync(directory,{recursive:true,force:true});}
});
