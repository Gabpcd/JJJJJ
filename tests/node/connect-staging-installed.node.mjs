import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { inspectInstallation, proveInstalledRegressions, installedSql } from '../../scripts/ci/connect-staging-installed-proof.mjs';
import { MIGRATION, CAPACITY, ADMISSION, canonical, digest } from '../../scripts/ci/connect-staging-closed.mjs';
import { renderStagingAdmission } from '../../scripts/ci/connect-staging-admission-render.mjs';

function scenario() {
  const contract = JSON.parse(readFileSync('scripts/ci/connect-staging-closed.contract.json','utf8'));
  const migration = readFileSync(MIGRATION,'utf8'), capacity = readFileSync(CAPACITY,'utf8');
  const admission = renderStagingAdmission(migration,readFileSync(ADMISSION,'utf8'));
  const candidate = {sha:'a'.repeat(40),tree:'b'.repeat(40)};
  const pins = {migrationSha256:digest(migration),capacitySha256:digest(capacity),admissionSha256:digest(admission)};
  const manifest = {candidate,...pins}, manifestSha256 = digest(JSON.stringify(canonical(manifest)));
  const source = {...manifest,manifestSha256,migration,capacity,admission};
  const reference = {schemaVersion:1,sources:{...manifest,manifestSha256},deltaMd5:'d'.repeat(32),
    counts:{routines:34,relations:3,triggers:2,inventory:19,views:0,policies:0,columns:75,constraints:58,indexes:11}};
  const versions = ['20261001194201'];
  const snapshot = {catalogue:contract.expectedAfter.catalogue,registry:contract.expectedAfter.registry,
    rows:'1'.repeat(32),all_rows:'2'.repeat(32),connect_rows:'3'.repeat(32),delta_md5:reference.deltaMd5,
    default_acl_md5:'4'.repeat(32),sequences_md5:'5'.repeat(32),versions:[...versions,'20261001201055'],
    capacity_count:1,operation_count:1,quiescent:true,gate_closed:true,capacity_revoked:true,
    operation_terminal:true,cohort_known:true,no_transfer:true,database_role:'postgres',read_only:true};
  const env = {GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'pull_request',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',
    STAGING_SUPABASE_PROJECT_REF:'mejpriaetwgtcstbgfid',STAGING_SUPABASE_ACCESS_TOKEN:'SENTINELLE_NON_CREDENTIAL',
    CANDIDATE_SHA:candidate.sha,BASE_SHA:'c'.repeat(40)};
  const calls = [], responses = [];
  const fetcher = async(url, options) => {
    assert.equal(url,'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');
    assert.equal(options.redirect,'error'); calls.push(JSON.parse(options.body));
    const next = responses.shift(); if (next instanceof Error) throw next;
    return {ok:true,status:200,text:async()=>JSON.stringify(next)};
  };
  const args = {env,source,contract,reference,versions,changes:[['A',MIGRATION]],fetcher,
    sql:'BEGIN;\nSET LOCAL statement_timeout=\'120s\';\nSAVEPOINT test;\nSELECT 1;\nROLLBACK TO SAVEPOINT test;\nRELEASE SAVEPOINT test;\nROLLBACK;\n'};
  return {args,snapshot,calls,responses,
    inspect:()=>inspectInstallation(args), run:()=>proveInstalledRegressions(args)};
}

test('staging vierge conserve le chemin initial, sans écriture ni assouplissement des pins installés',async()=>{
  const s=scenario(); s.responses.push([{present:0}]);
  s.args.changes.push(['A','supabase/migrations/20990101000000_future.sql']);
  assert.deepEqual(await s.inspect(),{mode:'empty'});
  assert.equal(s.calls.length,1); assert.equal(s.calls[0].read_only,false); assert.match(s.calls[0].query,/^BEGIN READ ONLY;/);
});
test('installation reconnue uniquement par source, catalogue, registre, témoin et cohorte fermée',async()=>{
  const s=scenario(); s.responses.push([{present:3}],[s.snapshot]);
  assert.deepEqual(await s.inspect(),{mode:'installed',snapshot:s.snapshot});
  assert.deepEqual(s.calls.map(c=>c.read_only),[false,false]);
  assert.ok(s.calls.every(c=>c.query.startsWith('BEGIN READ ONLY;') && c.query.trimEnd().endsWith('ROLLBACK;')));
});
for(const present of [1,2,4,'3',null]) test(`installation partielle/ambiguë refuse sans fallback (${present})`,async()=>{
  const s=scenario(); s.responses.push([{present}]);
  await assert.rejects(s.inspect(),/PARTIAL_INSTALLATION/); assert.equal(s.calls.length,1);
});
for(const [name,mutate] of [
  ['production',a=>a.env.STAGING_SUPABASE_PROJECT_REF='flripxtsyegjshnhzjkz'],
  ['push main',a=>a.env.GITHUB_EVENT_NAME='push'], ['autre dépôt',a=>a.env.GITHUB_REPOSITORY='autre/repo'],
  ['SHA différent',a=>a.env.CANDIDATE_SHA='f'.repeat(40)],
  ['référence autre source',a=>a.reference.sources.capacitySha256='f'.repeat(64)],
  ['source modifiée',a=>a.source.admission+='\n-- changed'],
]) test(`contexte invalide avant toute requête : ${name}`,async()=>{
  const s=scenario(); mutate(s.args); await assert.rejects(s.inspect()); assert.equal(s.calls.length,0);
});
for(const [name,mutate] of [
  ['migration supplémentaire',a=>a.changes.push(['A','supabase/migrations/20990101000000_future.sql'])],
  ['migration modifiée',a=>a.changes[0][0]='M'],
  ['pins différents',a=>{a.contract.reviewedManifest.capacitySha256='f'.repeat(64);}],
]) test(`installation existante refuse ${name} sans bootstrap`,async()=>{
  const s=scenario(); mutate(s.args); s.responses.push([{present:3}]);
  await assert.rejects(s.inspect()); assert.equal(s.calls.length,1);
});
for(const [key,value] of [
  ['catalogue','0'.repeat(32)],['registry','0'.repeat(32)],['delta_md5','0'.repeat(32)],
  ['versions',['20261001201055']],['capacity_count',0],['capacity_count',2],['operation_count',2],
  ['database_role','authenticated'],
  ...['quiescent','gate_closed','capacity_revoked','operation_terminal','cohort_known','no_transfer','read_only'].map(k=>[k,false]),
]) test(`préflight refuse ${key}=${JSON.stringify(value)}`,async()=>{
  const s=scenario(); s.snapshot[key]=value; s.responses.push([s.snapshot]);
  await assert.rejects(s.run()); assert.equal(s.calls.length,1); assert.equal(s.calls[0].read_only,false); assert.match(s.calls[0].query,/^BEGIN READ ONLY;/);
});
test('suites conservées sous rollback et trois transports, aucune nouvelle installation',async()=>{
  const s=scenario(); s.responses.push([s.snapshot],[],[structuredClone(s.snapshot)]);
  const proof=await s.run(); assert.equal(proof.rollbackVerified,true); assert.equal(proof.migrationReapplied,false);
  assert.deepEqual(s.calls.map(c=>c.read_only),[false,false,false]);
  for (const index of [0,2]) assert.match(s.calls[index].query,/^BEGIN READ ONLY;/);
  assert.equal(s.calls[1].query,s.args.sql); assert.equal(s.calls[0].query,s.calls[2].query);
  assert.doesNotMatch(JSON.stringify(proof),/SENTINELLE/);
});
for(const key of ['rows','all_rows','connect_rows','default_acl_md5','sequences_md5']) test(`aucun succès si ${key} change malgré rollback`,async()=>{
  const s=scenario(); const after=structuredClone(s.snapshot); after[key]='9'.repeat(32);
  s.responses.push([s.snapshot],[],[after]);
  await assert.rejects(s.run(),/ROLLBACK_NOT_RESTORED/); assert.equal(s.calls.length,3);
});
test('réponse perdue : une seule transaction puis relecture indépendante, jamais un retry',async()=>{
  const s=scenario(); s.responses.push([s.snapshot],new Error('SENTINELLE'),[s.snapshot]);
  await assert.rejects(s.run(),/REGRESSIONS_TRANSPORT_REFUSED/);
  assert.deepEqual(s.calls.map(c=>c.read_only),[false,false,false]);
  for (const index of [0,2]) assert.match(s.calls[index].query,/^BEGIN READ ONLY;/);
});
for(const sql of ['SELECT 1;', 'BEGIN;\nCOMMIT;', 'BEGIN;\n-- migration: forbidden\nROLLBACK;',
  'BEGIN;\nCOMMIT;\nBEGIN;\nROLLBACK;']) test('transaction de régression ambiguë refuse avant transport',async()=>{
  const s=scenario(); s.args.sql=sql; await assert.rejects(s.run(),/REGRESSION_TRANSACTION_REFUSED/);
  assert.equal(s.calls.length,0);
});
test('aucune ligne supplémentaire ou privée du transport ne devient artefact',async()=>{
  const s=scenario(); s.snapshot.unexpected='SENTINELLE'; s.responses.push([s.snapshot]);
  await assert.rejects(s.run(),/SNAPSHOT_SHAPE/);
});
test('lecture inclut données Connect, défauts ACL et état non transactionnel des séquences',()=>{
  const sql=installedSql(); assert.ok(sql.startsWith('BEGIN READ ONLY;'));
  assert.match(sql,/SET LOCAL row_security=off/);
  assert.match(sql,/pg_default_acl/); assert.match(sql,/last_value,is_called/);
  assert.match(sql,/owner_token IS NULL AND lease_until IS NULL/);
  assert.match(sql,/refund_status='SUCCEEDED'/); assert.match(sql,/stripe_transfer_id IS NULL/);
  assert.doesNotMatch(sql,/\b(?:INSERT|UPDATE|DELETE|TRUNCATE|DROP|setval)\b/i);
});

test('le chemin installé reste limité à la PR qui ajoute Connect, sans changer le déploiement main',()=>{
  const workflow=readFileSync('.github/workflows/validate-pr.yml','utf8');
  assert.match(workflow,/sql-transaction:\n\s+name:.*\n\s+if: github\.event_name == 'pull_request'/);
  assert.match(workflow,/--diff-filter=A.*supabase\/migrations\/\*\.sql.*\| grep -Fxq 'supabase\/migrations\/20261001201055_/);
  assert.ok(workflow.indexOf('Connect — référence du delta fermé')<workflow.indexOf('Connect — reconnaître strictement'));
  assert.ok(workflow.indexOf('Connect — reconnaître strictement')<workflow.indexOf('Synchroniser le schéma main'));
  assert.match(workflow,/if: steps\.migration_scope\.outputs\.has_migrations == 'true' && steps\.connect_installation\.outputs\.mode != 'installed'/);
  assert.match(workflow,/MIGRATIONS=\(\)/);
  assert.match(workflow,/true\) ;;\n\s+\*\) echo/); // No shortening of the existing regression suites.
});

for (const [name,response,expected] of [
  ['HTTP SQL', {ok:false,status:403,text:async()=>JSON.stringify({code:'42501',message:'PRIVATE_SENTINELLE'})}, /PRESENCE_HTTP_403_BYTES_\d+_SQLSTATE_42501_QUERY_REFUSED/],
  ['HTTP sans code SQL', {ok:false,status:502,text:async()=>JSON.stringify({message:'PRIVATE_SENTINELLE'})}, /PRESENCE_HTTP_502_BYTES_\d+_SQLSTATE_UNAVAILABLE_QUERY_REFUSED/],
  ['code non autorisé', {ok:false,status:400,text:async()=>JSON.stringify({code:'PRIVATE_SENTINELLE'})}, /SQLSTATE_UNAVAILABLE_QUERY_REFUSED/],
  ['réponse non JSON', {ok:true,status:200,text:async()=>'PRIVATE_SENTINELLE'}, /PRESENCE_HTTP_200_BYTES_18_INVALID_JSON/],
  ['taille excessive', {ok:true,status:200,text:async()=>'x'.repeat(100000)}, /PRESENCE_HTTP_200_BYTES_100000_RESPONSE_TOO_LARGE/],
]) test(`diagnostic expurgé refuse sans fallback : ${name}`,async()=>{
  const s=scenario(); let calls=0;
  s.args.fetcher=async()=>{ calls++; return response; };
  await assert.rejects(s.inspect(),error=>{
    assert.match(error.message,expected); assert.doesNotMatch(error.message,/PRIVATE_SENTINELLE|SENTINELLE_NON_CREDENTIAL/); return true;
  });
  assert.equal(calls,1);
});
test('diagnostic distingue le second SELECT et ne rejoue aucune requête',async()=>{
  const s=scenario(); let calls=0;
  s.args.fetcher=async()=> ++calls===1
    ? {ok:true,status:200,text:async()=>JSON.stringify([{present:3}])}
    : {ok:false,status:503,text:async()=>JSON.stringify({message:'PRIVATE_SENTINELLE'})};
  await assert.rejects(s.inspect(),/INSPECT_HTTP_503_BYTES_\d+_SQLSTATE_UNAVAILABLE_QUERY_REFUSED/);
  assert.equal(calls,2);
});

test('le rôle opérateur est conservé sans élargissement SQL ni fallback de rôle',()=>{
  const source=readFileSync('scripts/ci/connect-staging-installed-proof.mjs','utf8');
  assert.match(source,/body:JSON\.stringify\(\{query:sql, read_only:false\}\)/);
  assert.match(source,/s\.database_role === 'postgres'/);
  assert.match(source,/'read_only'/);
  assert.doesNotMatch(installedSql(),/\b(?:GRANT|ALTER ROLE|SET (?:LOCAL )?ROLE)\b/i);
});
