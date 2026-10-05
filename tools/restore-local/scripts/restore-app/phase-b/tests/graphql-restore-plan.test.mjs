import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {GRAPHQL_SOURCE,GRAPHQL_PREREQUISITES,assertGraphqlWitness,assertGraphqlRestored,
  normalizedGraphqlTocHash,partitionGraphqlRestore,graphqlExportArgs,graphqlTransactionArgs,
  prepareGraphqlRestore} from '../graphql-restore-plan.mjs';
const hash=v=>createHash('sha256').update(v).digest('hex');
import {GRAPHQL_NATIVE_BASELINE_SQL} from '../graphql-native-baseline.mjs';
import {witness,descriptions,tocOf,input} from './graphql-test-fixture.mjs';
const lines=buffer=>buffer.toString().split('\n').filter(v=>v&&!v.startsWith(';'));
const refuse=fn=>assert.throws(fn,e=>e.code==='B_GRAPHQL_RESTORE_REFUSED'&&e.message==='B_GRAPHQL_RESTORE_REFUSED');

test('all original entries, owners, ACLs, data and other event triggers occur exactly once',()=>{
 const source=input(),p=partitionGraphqlRestore(source),before=lines(source.toc),first=lines(p.prerequisites),rest=lines(p.remainder);
 assert.deepEqual([...first,...rest].sort(),before.sort());assert.equal(first.length,5);
 assert.equal(new Set([...first,...rest].map(l=>l.split(';')[0])).size,before.length);
 assert.deepEqual(first.map(l=>l.replace(/^\d+; \d+ \d+ /,'')),GRAPHQL_PREREQUISITES);
 for(const kind of ['TABLE DATA','ACL','EXTENSION']){const pattern=new RegExp('^\\d+; \\d+ \\d+ '+kind+' ');assert.equal(rest.filter(l=>pattern.test(l)).length,before.filter(l=>pattern.test(l)).length);}
 assert.ok(rest.some(l=>l.includes('unrelated_native_hook')));assert.equal(p.archive,source.archive);
 assert.equal(p.proof.allEntriesPreservedExactlyOnce,true);assert.equal(p.proof.restored,false);assert.equal(p.proof.appVerified,false);
});
test('fixed native function default ACL is part of prerequisites, before enabling event trigger',()=>{
 const p=partitionGraphqlRestore(input()),first=lines(p.prerequisites);
 assert.ok(first.findIndex(l=>l.includes('DEFAULT ACL'))<first.findIndex(l=>l.includes('EVENT TRIGGER')));
 assert.ok(!p.remainder.toString().includes('DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS'));
});
test('unreviewed assembly refuses before any export callback',async()=>{
 for(const review of [undefined,{}, {nativeGraphqlRepairReviewed:false,nativeRestoreTocSha256:'a'.repeat(64)}]) {
  let calls=0;await assert.rejects(()=>prepareGraphqlRestore({...input(),review},()=>{calls++;}),/B_GRAPHQL_RESTORE_REFUSED/);assert.equal(calls,0);
 }
});
test('hashes bind archive and full reviewed normalized inventory',()=>{
 for(const edit of [x=>x.archive[6]=120,x=>x.archiveSha256='0'.repeat(64),x=>x.toc=Buffer.concat([x.toc,Buffer.from('9999; 0 0 ACL public TABLE injected postgres\n')]),x=>x.review.nativeRestoreTocSha256='0'.repeat(64)]){const x=input();edit(x);refuse(()=>partitionGraphqlRestore(x));}
});
for(const [name,edit] of [
 ['missing native schema',r=>r.filter(l=>l!=='SCHEMA - graphql_public supabase_admin')],
 ['different schema owner',r=>r.map(l=>l==='SCHEMA - graphql_public supabase_admin'?l.replace('supabase_admin','postgres'):l)],
 ['duplicate native hook',r=>[...r,'FUNCTION extensions grant_pg_graphql_access() supabase_admin']],
 ['hook overload',r=>[...r,'FUNCTION extensions grant_pg_graphql_access(text) supabase_admin']],
 ['wrong event trigger owner',r=>r.map(l=>l==='EVENT TRIGGER - issue_pg_graphql_access supabase_admin'?l.replace('supabase_admin','postgres'):l)],
 ['missing extension',r=>r.filter(l=>!l.startsWith('EXTENSION - pg_graphql'))],
 ['wrapper definition would collide',r=>[...r,'FUNCTION graphql_public graphql(text, text, jsonb, jsonb) supabase_admin']],
 ['another wrapper signature',r=>[...r,'FUNCTION graphql_public graphql(text) supabase_admin']],
 ['missing wrapper ACL',r=>r.filter(l=>!l.startsWith('ACL graphql_public FUNCTION graphql('))],
 ['wrong wrapper ACL signature',r=>r.map(l=>l.startsWith('ACL graphql_public FUNCTION graphql(')?'ACL graphql_public FUNCTION graphql(query text) supabase_admin':l)],
 ['missing default function privileges',r=>r.filter(l=>!l.startsWith('DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS'))],
 ['other default privilege creator',r=>[...r,'DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS postgres']],
])test('refuses even rehashed fixture: '+name,()=>refuse(()=>partitionGraphqlRestore(input(edit(descriptions())))));
test('duplicate TOC IDs, invalid control bytes and forbidden database objects refuse',()=>{
 for(const toc of [Buffer.from('1; 0 0 TABLE public a postgres\n1; 0 0 TABLE public b postgres\n'),Buffer.from('1; 0 0 TABLE public a\tpostgres\n'),tocOf([...descriptions(),'DATABASE - forbidden postgres']),Buffer.from([0xff])])refuse(()=>normalizedGraphqlTocHash(toc));
});
test('every exact native source property must be true, without extra data or unbounded fingerprints',()=>{
 const source=witness();assertGraphqlWitness(source);
 for(const key of Object.keys(source).filter(k=>source[k]===true))for(const value of [false,null,1,'true'])refuse(()=>assertGraphqlWitness({...source,[key]:value}));
 for(const patch of [{initialPrivilegesCount:2},{schemaVersion:6},{fingerprint:'not-a-hash'},{raw:'PRIVATE_CANARY'}])refuse(()=>assertGraphqlWitness({...source,...patch}));
});
test('target parity covers native definitions, ACLs, owner and initial privileges via fingerprint',()=>{
 assert.deepEqual(assertGraphqlRestored(witness(),witness()),{nativeGraphqlPrerequisiteVerified:true,nativeGraphqlRestoredExact:true,nativeGraphqlWrapperSchemaRawEqual:true,nativeGraphqlWrapperSchemaSemanticEqual:true});
 for(const change of [{fingerprint:'b'.repeat(64)},{initialPrivilegesCount:0},{wrapperMembershipExact:false},{triggerExact:false}])refuse(()=>assertGraphqlRestored(witness(),{...witness(),...change}));
});
test('both official exports stay byte-exact around the native prerequisite in one psql transaction',async()=>{
 const x=input(),calls=[],fragments=[Buffer.from('-- prerequisite\nALTER SCHEMA extensions OWNER TO postgres;\n'),Buffer.from('-- remainder\nCOPY synthetic FROM stdin;\n1\n\\.\nGRANT SELECT ON synthetic TO anon;\n')];
 const result=await prepareGraphqlRestore(x,async request=>{calls.push(request);return fragments[calls.length-1];});
 assert.deepEqual(calls.map(c=>c.partition),['prerequisites','remainder']);assert.ok(calls.every(c=>c.archive===x.archive));
 assert.deepEqual(result.sql,Buffer.concat([fragments[0],Buffer.from('\n'),Buffer.from(GRAPHQL_NATIVE_BASELINE_SQL),fragments[1],Buffer.from('\n')]));
 assert.deepEqual(result.transactionArgs,graphqlTransactionArgs());assert.equal(result.transactionArgs.filter(v=>v==='--single-transaction').length,1);
 assert.ok(result.transactionArgs.includes('ON_ERROR_STOP=1'));assert.equal(result.transactionArgs.at(-1),'-');
 for(const request of calls){assert.deepEqual(request.args,graphqlExportArgs(request.partition));assert.ok(!request.args.includes('--single-transaction'));assert.ok(!request.args.some(v=>v.startsWith('--no-owner')||v.startsWith('--no-acl')||v==='--clean'||v==='--dbname'||v==='-d'));}
 assert.equal(result.proof.restored,false);assert.equal(result.proof.appVerified,false);
});
test('export errors stop composition; no target executor exists in this preparation module',async()=>{
 for(const failure of ['first','second','empty','wrong-type','nul']){
  let calls=0;await assert.rejects(()=>prepareGraphqlRestore(input(),async()=>{calls++;
   if((failure==='first'&&calls===1)||(failure==='second'&&calls===2))throw Error('SYNTHETIC_EXPORT_FAILURE');
   return failure==='empty'?Buffer.alloc(0):failure==='wrong-type'?'sql':failure==='nul'?Buffer.from('x\0y'):Buffer.from('SELECT 1;');
  }));assert.equal(calls,failure==='second'?2:1);
 }
 const src=readFileSync(new URL('../graphql-restore-plan.mjs',import.meta.url),'utf8');assert.ok(!/from ['"]node:(child_process|net|http|https|tls)['"]/.test(src));
});
test('archive/list mutation by the exporter refuses before any composed SQL is returned',async()=>{
 for(const field of ['archive','list'])await assert.rejects(()=>prepareGraphqlRestore(input(),async request=>{request[field][0]=120;return Buffer.from('SELECT 1;');}),/B_GRAPHQL_RESTORE_REFUSED/);
});
test('source witness remains private and caller mutation cannot change captured parity proof',async()=>{
 const x=input(),r=await prepareGraphqlRestore(x,async()=>Buffer.from('SELECT 1;'));x.witness.fingerprint='b'.repeat(64);
 assert.equal(r.sourceWitness.fingerprint,'a'.repeat(64));assert.ok(!JSON.stringify(r.proof).includes('fingerprint'));
});
test('witness is readonly, hashes exact native bodies, and covers all fidelity fields',()=>{
 const sql=readFileSync(new URL('../graphql-native-witness.sql',import.meta.url),'utf8');
 assert.match(sql,/BEGIN READ ONLY;/);assert.match(sql,/ROLLBACK;/);const statements=sql.replace(/--[^\n]*/g,'').replace(/'(?:''|[^'])*'/g,"''");assert.ok(!/\b(CREATE|ALTER|DROP|GRANT|REVOKE|INSERT|UPDATE|DELETE|TRUNCATE)\s+(FUNCTION|EXTENSION|SCHEMA|TABLE|DATABASE)\b/.test(statements));
 assert.ok(sql.includes(GRAPHQL_SOURCE.hookBodySha256));assert.ok(sql.includes(GRAPHQL_SOURCE.wrapperBodySha256));
 for(const term of ['pg_init_privs','pg_get_functiondef','p.proacl','p.proowner','pg_depend','pg_default_acl','evttags','evtenabled','current_database()','inet_server_addr()','max_worker_processes','cron.launch_active_jobs'])assert.ok(sql.includes(term),term);
});
