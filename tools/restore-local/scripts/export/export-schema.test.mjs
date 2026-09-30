import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync,mkdtempSync,statSync} from 'node:fs';import {tmpdir} from 'node:os';import {resolve} from 'node:path';
import {connectionEnv,validateApproval,validateCatalogue,dumpArgs,selectManagedToc,rejectKnownSecrets,collect,main,publicError} from './export-schema.mjs';
const scope=JSON.parse(readFileSync(new URL('./scope.json',import.meta.url))),ref=scope.source_ref;
const env={PATH:process.env.PATH,RESTORE_SCHEMA_SOURCE_REF:ref,PGHOST:'db.'+ref+'.supabase.co',PGPORT:'5432',PGDATABASE:'postgres',PGUSER:'postgres',PGPASSWORD:'CANARY_PRIVATE_PASSWORD',SUPABASE_ACCESS_TOKEN:'CANARY_API_TOKEN',PGSERVICE:'unsafe',PGOPTIONS:'-c default_transaction_read_only=off'};
const approval=()=>({source_ref:ref,catalogue_md5:'a'.repeat(32),expires_at:new Date(Date.now()+600000).toISOString()});
const catalogue=()=>({version:1,database:'postgres',read_only:true,postgres_major:17,catalogue_md5:'a'.repeat(32),object_count:100,application_schemas:['private','public'],extensions:scope.extensions,foreign_tables:0,direct_secret_pattern_routines:0,managed_policies:scope.custom_policies,auth_triggers:scope.custom_triggers});
const toc=()=>[...scope.custom_policies.map((x,i)=>`${i+1}; 0 0 POLICY ${x.schema} ${x.table} ${x.name} postgres`),...scope.custom_triggers.map((x,i)=>`${i+100}; 0 0 TRIGGER ${x.schema} ${x.table} ${x.name} postgres`),'201; 0 0 ACL auth TABLE users supabase_auth_admin','202; 0 0 ACL - SCHEMA auth supabase_auth_admin','203; 0 0 TRIGGER storage objects update_objects_updated_at supabase_storage_admin'].join('\n');
test('connection is exact production READ ONLY TLS, not inherited arbitrary PG/API environment',()=>{
 const x=connectionEnv(env);assert.equal(x.PGSSLMODE,'verify-full');assert.equal(x.PGSSLROOTCERT,'system');assert.match(x.PGOPTIONS,/default_transaction_read_only=on/);assert.equal(x.PGSERVICE,undefined);assert.equal(x.SUPABASE_ACCESS_TOKEN,undefined);
 assert.equal(connectionEnv({...env,PGHOST:'aws-0-eu-west-3.pooler.supabase.com',PGUSER:'postgres.'+ref}).PGPORT,'5432');
});
for(const change of [{RESTORE_SCHEMA_SOURCE_REF:'mejpriaetwgtcstbgfid'},{RESTORE_SCHEMA_SOURCE_REF:'wnepopwygokbhlqghydb'},{PGHOST:'evil.invalid'},{PGHOST:'db.'+ref+'.supabase.co.evil.invalid'},{PGPORT:'6543'},{PGDATABASE:'other'},{PGUSER:'postgres.other'},{PGPASSWORD:''}])test('refuses destination or missing credential before process '+Object.keys(change)[0],()=>{let calls=0;assert.throws(()=>collect('/unused',approval(),{...env,...change},()=>{calls++}));assert.equal(calls,0)});
test('approval is exact, expiring, and no arbitrary command/schema input',()=>{
 assert.equal(validateApproval(approval()),true);
 for(const a of [{...approval(),extra:true},{...approval(),catalogue_md5:'bad'},{...approval(),expires_at:new Date(0).toISOString()},{...approval(),expires_at:new Date(Date.now()+7200000).toISOString()}])assert.throws(()=>validateApproval(a));
 assert.throws(()=>main(['reset']));assert.equal(main(['plan']).rows,false);
});
test('catalogue drift, extension loss, foreign data and unmanaged policies refuse',()=>{
 assert.equal(validateCatalogue(catalogue(),approval()),true);
 for(const change of [{read_only:false},{postgres_major:16},{catalogue_md5:'b'.repeat(32)},{extensions:scope.extensions.filter(e=>e.name!=='pgjwt')},{foreign_tables:1},{direct_secret_pattern_routines:1},{managed_policies:[]},{auth_triggers:[]}])assert.throws(()=>validateCatalogue({...catalogue(),...change},approval()));
});
test('fixed official dump is schema-only, no roles/data/reset/parallel jobs or secret arguments',()=>{
 const a=dumpArgs('/private/export');assert.ok(a.includes('--schema-only'));assert.ok(a.includes('--format=custom'));assert.deepEqual(a.filter(x=>x.startsWith('--schema=')),['--schema=public','--schema=private','--schema=auth','--schema=storage']);
 assert.ok(!a.some(x=>/--data-only|--clean|--create|--role|--jobs|CANARY|postgres:\/\//.test(x)));
});
test('TOC uses official entries exactly for 14 policies and 1 Auth trigger; Storage internals not replayed',()=>{
 const r=selectManagedToc(toc());assert.equal(r.custom_count,15);assert.equal(r.acl_count,2);assert.ok(!r.custom.includes('update_objects_updated_at'));assert.ok(r.custom.includes('copies_bulletins_select_guard'));
 for(const text of [toc().split('\n').slice(1).join('\n'),toc()+'\n'+toc().split('\n')[0],toc()+'\n301; 0 0 TABLE DATA public missions postgres',toc()+'\n304; 0 0 MATERIALIZED VIEW DATA public mv postgres',toc()+'\n302; 0 0 POLICY storage objects foreign_policy postgres',toc()+'\n303; 0 0 TRIGGER auth users other_hook postgres'])assert.throws(()=>selectManagedToc(text));
});
test('known secret patterns and source password reject with closed errors',()=>{
 for(const value of ['CANARY_PRIVATE_PASSWORD','sk_live_CANARY123456789','sb_secret_CANARY123456789','postgres://user:CANARY@host/db','-----BEGIN PRIVATE KEY-----']){
  let e;try{rejectKnownSecrets(value,env.PGPASSWORD)}catch(x){e=x}assert.equal(publicError(e).code,'SECRET_PATTERN_REFUSED');assert.ok(!JSON.stringify(publicError(e)).includes('CANARY'));
 }
 assert.equal(publicError(new Error('CANARY_PROVIDER_URL_PASSWORD')).code,'EXPORT_INTERNAL_FAILURE');assert.ok(!JSON.stringify(publicError(new Error('CANARY_PROVIDER_URL_PASSWORD'))).includes('CANARY'));
});
test('drift before dump never invokes pg_dump',()=>{
 const calls=[];assert.throws(()=>collect('/unused',approval(),env,(bin,args)=>{calls.push([bin,args]);if(args[0]==='--version')return bin+' (PostgreSQL) 17.6';if(bin==='python3')return '';return JSON.stringify({...catalogue(),catalogue_md5:'b'.repeat(32)})}),/CATALOGUE_REFUSED/);
 assert.ok(!calls.some(([bin,args])=>bin==='pg_dump'&&args[0]!=='--version'));
});
test('provider failure after preflight leaves only private quarantine and no release manifest',()=>{
 const parent=mkdtempSync(resolve(tmpdir(),'ddl-export-test-')),dir=resolve(parent,'private');
 let caught;try{collect(dir,approval(),env,(bin,args)=>{if(args[0]==='--version')return bin+' (PostgreSQL) 17.6';if(bin==='python3')return '';if(bin==='psql')return JSON.stringify(catalogue());throw new Error('CANARY_PRIVATE_PASSWORD PROVIDER_BODY')})}catch(e){caught=e}
 assert.equal(publicError(caught).code,'EXPORT_INTERNAL_FAILURE');assert.equal(statSync(dir).mode&0o077,0);assert.equal(statSync(resolve(dir,'catalogue-before.private.json')).mode&0o077,0);assert.ok(!JSON.stringify(publicError(caught)).includes('CANARY'));
});
