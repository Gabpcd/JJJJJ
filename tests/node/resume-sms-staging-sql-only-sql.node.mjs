import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {transactionSql,snapshotSql} from '../../scripts/ci/install-sms-staging-closed-sql.mjs';
import {transactionSqlOnly} from '../../scripts/ci/resume-sms-staging-sql-only-sql.mjs';
import {renderSignatureSmsStaging} from '../../scripts/ci/sms-signature-staging-render.mjs';
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const c=JSON.parse(read('scripts/ci/install-sms-staging-closed.contract.json'));
const before={quiet:true,absent:true,closed:false,routines:structuredClone(c.beforeRoutines),
 invariant:Object.fromEntries(['structure','routines','inventory','registry','rows'].map((k,i)=>[k,String(i+1).repeat(32)])),targets:'6'.repeat(32)};
const rendered=renderSignatureSmsStaging(read('scripts/ci/sms-signature-staging-otp.source.sql'),read('scripts/ci/sms-signature-staging.sql'));

test('only the cron.job lock changes; render, guards, all snapshots and 36 blocking locks stay exact',()=>{
 for(const commit of [false,true]){
  const original=transactionSql(c,rendered,before,commit),actual=transactionSqlOnly(c,rendered,before,commit);
  const oldLine=original.match(/^ LOCK TABLE (.+) IN SHARE MODE NOWAIT;$/m)[0];
  const oldTables=oldLine.slice(' LOCK TABLE '.length,-' IN SHARE MODE NOWAIT;'.length).split(',');
  const newLine=actual.match(/^ LOCK TABLE (.+) IN SHARE MODE NOWAIT;$/m)[0];
  assert.equal(oldTables.length,35);
  assert.equal(newLine,` LOCK TABLE ${oldTables.filter(t=>t!=='cron.job').join(',')} IN SHARE MODE NOWAIT;`);
  assert.match(actual,/LOCK TABLE supabase_migrations.schema_migrations,private.security_definer_inventory IN SHARE ROW EXCLUSIVE MODE NOWAIT;/);
  const replacement=newLine+'\n -- cron.job is observed before/after; ACCESS SHARE does not block its writers.\n LOCK TABLE cron.job IN ACCESS SHARE MODE NOWAIT;';
  assert.equal(actual.replace(replacement,oldLine),original);
  assert.equal(actual.split(rendered).length,2);
  assert.equal(actual.match(/LOCK TABLE cron\.job IN ACCESS SHARE MODE NOWAIT;/g)?.length,1);
  assert.match(actual,commit?/COMMIT;$/:/ROLLBACK;$/);
 }
});
test('cron data and quiet predicates remain observed in every before/after snapshot',()=>{
 const tx=transactionSqlOnly(c,rendered,before,false);
 assert.ok((tx.match(/FROM cron\.job t/g)||[]).length>=3);
 assert.ok((tx.match(/NOT EXISTS\(SELECT 1 FROM cron\.job WHERE active\)/g)||[]).length>=3);
 for(const after of [false,true]){
  assert.match(snapshotSql(c,after),/FROM cron\.job t/);
  assert.match(snapshotSql(c,after),/NOT EXISTS\(SELECT 1 FROM cron\.job WHERE active\)/);
 }
});
test('the historical strict contract and transaction boundary refusals remain active',()=>{
 for(const fragment of ['',rendered+'\nCOMMIT;',rendered+'\nROLLBACK;'])
  assert.throws(()=>transactionSqlOnly(c,fragment,before,false),/SMS_INSTALL_RENDER_FRAGMENT_REFUSED/);
 assert.throws(()=>transactionSqlOnly(c,rendered,{...before,quiet:false},false),/SMS_INSTALL_SQL_CONTRACT_REFUSED/);
 assert.throws(()=>transactionSqlOnly(c,rendered,before,'yes'),/SMS_INSTALL_RENDER_FRAGMENT_REFUSED/);
});
