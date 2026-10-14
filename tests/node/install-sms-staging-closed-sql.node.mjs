import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {snapshotSql,transactionSql} from '../../scripts/ci/install-sms-staging-closed-sql.mjs';
import {renderSignatureSmsStaging} from '../../scripts/ci/sms-signature-staging-render.mjs';

const sender='public.fn_envoyer_otp_signature(uuid)';
const privateLedger=['private.fn_reserver_envoi_sms_idempotent(text,text)',
 'private.fn_finaliser_envoi_sms_idempotent(text,text,text,text,text)'];
const wrappers=['public.fn_reserver_envoi_sms_idempotent(text,text)',
 'public.fn_finaliser_envoi_sms_idempotent(text,text,text,text,text)'];
const added=['private.fn_signature_sms_test_immutable()','private.fn_signature_sms_test_telephone(text)',
 'private.fn_signature_sms_test_scope(uuid,uuid)','public.fn_admission_otp_signature_recette(uuid)',
 'public.fn_reserver_sms_signature_recette(text,text,text,uuid,uuid,uuid,text,text,text,text,text,text)'];
const meta=(signature,definition=true)=>({signature,body_md5:'a'.repeat(32),...(definition?{definition_md5:'b'.repeat(32)}:{}),
 owner:'postgres',security_definer:!wrappers.includes(signature),config:['search_path=""'],acl:['postgres=X/postgres'],
 language:wrappers.includes(signature)?'sql':'plpgsql',volatility:'v',returns_set:false,strict:false});
const contract=()=>({beforeRoutines:[sender,...privateLedger,...wrappers].map(s=>meta(s)),
 afterRoutines:[sender,...added].map(s=>meta(s,false)).concat(wrappers.map(s=>meta(s)))});
const before=(c=contract())=>({quiet:true,absent:true,closed:false,routines:structuredClone(c.beforeRoutines).toSorted((a,b)=>a.signature.localeCompare(b.signature)),
 invariant:Object.fromEntries(['structure','routines','inventory','registry','rows'].map((k,i)=>[k,String(i+1).repeat(32)])),targets:'6'.repeat(32)});
const read=path=>readFileSync(new URL('../../'+path,import.meta.url),'utf8');
const rendered=renderSignatureSmsStaging(read('scripts/ci/sms-signature-staging-otp.source.sql'),read('scripts/ci/sms-signature-staging.sql'));

test('read-only snapshots expose one JSON column, only hashes and metadata',()=>{
 for(const after of [false,true]){
  const sql=snapshotSql(contract(),after);
  assert.match(sql,/^BEGIN READ ONLY; SET LOCAL search_path=pg_catalog;/);
  assert.match(sql,/SET LOCAL row_security=off/);
  assert.match(sql,/current_user<>'postgres' OR session_user<>'postgres'/);
  assert.match(sql,/current_setting\('transaction_read_only'\)<>'on'/);
  assert.match(sql,/current_setting\('row_security'\)<>'off'/);
  assert.match(sql,/AS snapshot/);assert.match(sql,/ROLLBACK;$/);
  for(const key of ['quiet','absent','closed','routines','invariant','targets'])assert.ok(sql.includes("'"+key+"'"));
  assert.ok(!/vault\.|decrypted_secret|http_post|https?:\/\//.test(sql));
  assert.ok(!/CREATE |INSERT |UPDATE |DELETE |GRANT |REVOKE /.test(sql));
 }
});
test('absent routines never turn exclusions into NOT IN(NULL), and overloads stay covered',()=>{
 const sql=snapshotSql(contract(),false);
 assert.ok(!/NOT IN\s*\(/.test(sql));assert.ok(!/::regprocedure/.test(sql));
 assert.ok(sql.includes("replace(oidvectortypes(p.proargtypes),', ',',')"));
 for(const signature of [sender,...added])assert.ok(sql.includes("'"+signature+"'"));
 assert.match(sql,/to_regclass\('private\.signature_sms_test_capacities'\) IS NULL/);
 assert.match(sql,/to_regtype\('private\.signature_sms_test_capacities'\) IS NULL/);
});
test('every function metadata property is emitted; wrappers retain complete definitions',()=>{
 const c=contract(),sql=transactionSql(c,rendered,before(c),false);
 for(const key of ['signature','body_md5','definition_md5','owner','security_definer','config','acl','language','volatility','returns_set','strict'])
  assert.ok(sql.includes("'"+key+"'"));
 for(const wrapper of wrappers)assert.ok(sql.includes(JSON.stringify(meta(wrapper)).replaceAll("'","''")));
 assert.match(sql,/r-'definition_md5'/);
 assert.match(sql,/jsonb_agg\(x::text ORDER BY x::text\) FROM unnest\(p\.proacl\) x/);
 assert.equal((sql.match(/SMS_INSTALL_ROUTINE_METADATA/g)||[]).length,13);
});
test('inventory outside the three exact public signatures retains timestamps',()=>{
 const sql=snapshotSql(contract(),true);
 assert.match(sql,/jsonb_agg\(to_jsonb\(i\) ORDER BY signature\)::text,'\[\]'\)\)\s+FROM private\.security_definer_inventory i WHERE NOT/);
 assert.match(sql,/jsonb_agg\(to_jsonb\(i\)-'recense_le' ORDER BY signature\)/);
 assert.ok(sql.includes("'fn_admission_otp_signature_recette(uuid)'"));
 assert.ok(sql.includes("'fn_envoyer_otp_signature(uuid)'"));
 assert.ok(!sql.includes("'private.fn_signature_sms_test_scope(uuid,uuid)'::regprocedure"));
});
test('closed table checks cover row count, owner, RLS, ACL, columns, policies, constraints and trigger',()=>{
 const sql=snapshotSql(contract(),true);
 for(const pattern of [/NOT EXISTS\(SELECT 1 FROM private\.signature_sms_test_capacities\)/,/relowner='postgres'::regrole/,
  /c\.relrowsecurity AND NOT c\.relforcerowsecurity/,/a\.grantee<>c\.relowner/,/FROM pg_policy/,
  /attisdropped OR attacl IS NOT NULL/,/REFERENCES,TRIGGER,MAINTAIN/,/format_type\(atttypid,atttypmod\)/,
  /signature_sms_test_one_active_run/,/tgtype=19/,/NOT convalidated/,/"c":15,"f":4,"p":1,"u":3/])assert.match(sql,pattern);
 assert.match(sql,/\["etablissement_attempts","smallint",true\]/);
});
test('unchanged business hashes and locks include all SMS effects and quiescence tables',()=>{
 const c=contract(),sql=transactionSql(c,rendered,before(c),true);
 for(const table of ['auth.users','auth.sessions','auth.refresh_tokens','public.preferences_notifications',
  'private.sms_dispatch_idempotency','public.signature_rate_limit_ip','public.sms_envoyes','public.journaux_audit',
  'public.signatures_contrats','public.contrats_mission','cron.job','cron.job_run_details','net.http_request_queue']){
  assert.ok(sql.includes('FROM '+table+' t'));
  assert.ok(sql.slice(sql.indexOf('LOCK TABLE auth.users'),sql.indexOf('CREATE TEMP TABLE')).includes(table));
 }
 assert.match(sql,/pg_advisory_xact_lock\(184731,1017\)/);
 assert.match(sql,/IN SHARE MODE NOWAIT/);
 assert.match(sql,/statut IN \('EN_COURS','INDETERMINE'\)/);
 assert.match(sql,/backend_type='client backend' AND state IS DISTINCT FROM 'idle'/);
});
test('the exact complete render appears once inside one guarded transaction',()=>{
 const c=contract(),sql=transactionSql(c,rendered,before(c),true);
 assert.equal(sql.split(rendered).length,2);
 assert.match(sql,/^BEGIN;/);assert.match(sql,/COMMIT;$/);
 assert.match(sql,/current_user<>'postgres' OR session_user<>'postgres'/);
 assert.match(sql,/current_setting\('transaction_read_only'\)<>'off'/);
 assert.equal((sql.match(/^BEGIN;/gm)||[]).length,1);assert.equal((sql.match(/^ COMMIT;/gm)||[]).length,1);
 assert.ok(sql.indexOf('SMS_INSTALL_BEFORE_CHANGED')<sql.indexOf(rendered));
 assert.ok(sql.indexOf('SMS_INSTALL_UNRELATED_CHANGE')>sql.indexOf(rendered));
 assert.ok(sql.lastIndexOf('AS snapshot')<sql.lastIndexOf('COMMIT;'));
 assert.ok(!/INSERT INTO supabase_migrations\.schema_migrations|migration repair|TRUNCATE TABLE|DROP SCHEMA/.test(sql));
 assert.match(transactionSql(c,rendered,before(c),false),/ROLLBACK;$/);
});
test('strict before shape and metadata reject missing, extra or changed observations',()=>{
 for(const change of [b=>b.quiet=false,b=>b.absent=false,b=>b.closed=true,b=>b.extra='raw',
  b=>b.targets='not-a-hash',b=>delete b.invariant.rows,b=>b.invariant.extra='7'.repeat(32),
  b=>b.routines.pop(),b=>b.routines[0].owner='attacker',b=>b.routines[0].body_md5='f'.repeat(32)]){
  const c=contract(),b=before(c);change(b);assert.throws(()=>transactionSql(c,rendered,b,false),/SMS_INSTALL_SQL_CONTRACT_REFUSED/);
 }
});
test('contract cannot hide a wrapper, an overload, an ACL change or metadata field',()=>{
 for(const change of [c=>c.beforeRoutines.pop(),c=>c.afterRoutines.pop(),
  c=>c.afterRoutines[0].signature=sender.replace('uuid','text'),c=>c.afterRoutines[0].extra='raw',
  c=>delete c.beforeRoutines[0].definition_md5,c=>c.afterRoutines.at(-1).acl=['=X/postgres'],
  c=>c.afterRoutines.at(-1).definition_md5='f'.repeat(32),c=>c.afterRoutines[0].body_md5="'); COMMIT; --"]){
  const c=contract();change(c);assert.throws(()=>snapshotSql(c,true),/SMS_INSTALL_SQL_CONTRACT_REFUSED/);
 }
});
test('transaction boundaries and local assertion delimiter injection are rejected',()=>{
 const c=contract(),b=before(c);
 for(const fragment of ['',rendered+'\nCOMMIT;',rendered+'\nROLLBACK;',rendered+'\nBEGIN;',rendered+'\n$sms_install_after$'])
  assert.throws(()=>transactionSql(c,fragment,b,true),/SMS_INSTALL_RENDER_FRAGMENT_REFUSED/);
 assert.throws(()=>transactionSql(c,rendered,b,'yes'),/SMS_INSTALL_RENDER_FRAGMENT_REFUSED/);
 assert.throws(()=>snapshotSql(c,'yes'),/SMS_INSTALL_SQL_CONTRACT_REFUSED/);
});
