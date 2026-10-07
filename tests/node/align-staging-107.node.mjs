import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {assets,transaction,context,align,PROJECT} from '../../scripts/ci/align-staging-107.mjs';
const c=JSON.parse(readFileSync(new URL('../../scripts/ci/align-staging-107.contract.json',import.meta.url),'utf8'));
const root=new URL('../../',import.meta.url).pathname,m=assets(root,c),head='a'.repeat(40);
const env={GITHUB_ACTIONS:'true',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REF:'refs/heads/main',GITHUB_SHA:head,INVOICE_EXPECTED_SHA:head,STAGING_SUPABASE_ACCESS_TOKEN:'synthetic-test-token'};
const after={schema:'b'.repeat(32),fonctions:'c'.repeat(32),triggers:'d'.repeat(32),crons_actifs:0,audit_fk:0};
test('only reviewed production migration bytes are accepted; no reset or provider operations',()=>{
 assert.equal(m.length,2);for(const migration of m)assert(transaction(c,m,false).includes(migration.body));
 for(const edit of [x=>x.project='flripxtsyegjshnhzjkz',x=>x.migrations[0].sha256='0'.repeat(64),x=>x.migrations[0].path='../outside',x=>x.functions.pop()]){
  const x=structuredClone(c);edit(x);assert.throws(()=>assets(root,x));
 }
 const sql=transaction(c,m,false);assert(sql.endsWith('ROLLBACK;'));assert(transaction(c,m,true).endsWith('COMMIT;'));
 assert(!/DROP SCHEMA|TRUNCATE|cron\.schedule/i.test(sql));
 assert.equal((sql.match(/REVOKE EXECUTE ON FUNCTION/g)||[]).length,12);
 assert.equal((sql.match(/INSERT INTO supabase_migrations.schema_migrations/g)||[]).length,2);
});
test('mutation refuses forks, PRs, wrong commits and dirty working trees',()=>{
 context(env,head,true);
 for(const [k,v] of [['GITHUB_ACTIONS','false'],['GITHUB_REPOSITORY','other/repo'],['GITHUB_EVENT_NAME','pull_request'],['GITHUB_REF','refs/heads/other'],['INVOICE_EXPECTED_SHA','b'.repeat(40)]])assert.throws(()=>context({...env,[k]:v},head,true));
 assert.throws(()=>context(env,head,false));
});
function harness({failAt,moveMainAt,driftRollback=false,driftAfter=false}={}){
 const calls=[];let mains=0,queries=0;
 const fetchImpl=async(url,options)=>{
  calls.push({url,options});if(calls.length===failAt)throw Error('private-provider-error');
  if(url.includes('api.github.com'))return{ok:true,json:async()=>({object:{sha:++mains===moveMainAt?'b'.repeat(40):head}})};
  assert(url.includes(`/projects/${PROJECT}/`));assert(!url.includes('flripxtsyegjshnhzjkz'));
  const values=[[after],[{...c.catalogueBefore,crons_actifs:0,audit_fk:0,...(driftRollback?{fonctions:'e'.repeat(32)}:{})}],[after],[{...after,...(driftAfter?{fonctions:'e'.repeat(32)}:{})}]];
  return{ok:true,json:async()=>values[queries++]};
 };
 return{calls,run:()=>align({env,head,clean:true,contract:c,migrations:m,fetchImpl})};
}
test('full rehearsal and verified rollback precede one commit, with independent readback',async()=>{
 const h=harness(),r=await h.run();assert.equal(r.status,'success');assert(r.dryRunVerified&&r.commitConfirmed);
 const queries=h.calls.filter(x=>x.options.body).map(x=>JSON.parse(x.options.body).query);
 assert(queries[0].endsWith('ROLLBACK;'));assert(queries[2].endsWith('COMMIT;'));assert(queries[3].startsWith('BEGIN READ ONLY;'));
 assert.equal(queries.filter(x=>x.endsWith('COMMIT;')).length,1);assert(!JSON.stringify(r).includes(env.STAGING_SUPABASE_ACCESS_TOKEN));
});
test('a changed rollback snapshot or changed main refuses before commit',async()=>{
 for(const options of [{driftRollback:true},{moveMainAt:2},{failAt:2}]){
  const h=harness(options),r=await h.run();assert.equal(r.commitAttempted,false);assert.equal(r.status,'failed');
  assert(!JSON.stringify(r).includes('private-provider-error'));
 }
});
test('uncertain commit or changed readback never retries or claims success',async()=>{
 for(const options of [{failAt:5},{driftAfter:true}]){
  const h=harness(options),r=await h.run();assert.equal(r.status,'uncertain');assert.equal(r.commitConfirmed,false);
  assert.equal(h.calls.filter(x=>x.options.body&&JSON.parse(x.options.body).query.endsWith('COMMIT;')).length,1);
 }
});
