import {test} from 'node:test';import assert from 'node:assert/strict';
import {generateKeyPairSync,createHash,privateDecrypt,createDecipheriv,constants} from 'node:crypto';
import {readFileSync,mkdtempSync,writeFileSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {resolve} from 'node:path';
import {decryptQuarantine} from './open-quarantine.mjs';
import {identity,recipient,envelope,sealFiles,cleanupPlan,IMAGE,REPO} from './ci-export.mjs';import {clientArgs} from './docker-tool.mjs';import {dumpArgs} from './export-schema.mjs';
const hash=x=>createHash('sha256').update(x).digest('hex'),head='a'.repeat(40);
const env=()=>({GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REF:'refs/heads/main',GITHUB_SHA:head,GITHUB_REPOSITORY:REPO,GITHUB_RUN_ID:'123',GITHUB_RUN_ATTEMPT:'1',RESTORE_EXPORT_APPROVED_HEAD:head,RESTORE_EXPORT_CATALOGUE_MD5:'b'.repeat(32),RESTORE_EXPORT_EXPIRES_AT:new Date(Date.now()+300000).toISOString()});
const event=()=>({repository:{full_name:REPO}});
test('trusted main exact approved SHA, repository and fresh catalogue approval',()=>{assert.equal(identity(env(),event(),head).head,head)});
test('PR/fork/branch/unapproved checked out or dispatched SHA all refuse',()=>{
 assert.throws(()=>identity(env(),{repository:{full_name:'fork/other'}},head));
 for(const change of [{GITHUB_EVENT_NAME:'pull_request'},{GITHUB_REF:'refs/heads/test/other'},{GITHUB_SHA:'c'.repeat(40)}])assert.throws(()=>identity({...env(),...change},event(),head));
 assert.throws(()=>identity(env(),event(),'c'.repeat(40)));
});
test('push, target event, absent SHA, expired approval and malformed run all refuse before tool stage',()=>{
 for(const change of [{GITHUB_EVENT_NAME:'push'},{GITHUB_EVENT_NAME:'pull_request_target'},{RESTORE_EXPORT_APPROVED_HEAD:''},{RESTORE_EXPORT_EXPIRES_AT:new Date(0).toISOString()},{GITHUB_RUN_ID:'1;exec'},{GITHUB_RUN_ATTEMPT:'0'}])assert.throws(()=>identity({...env(),...change},event(),head));
});
const pair=generateKeyPairSync('rsa',{modulusLength:4096}),pem=pair.publicKey.export({type:'spki',format:'pem'}),fp=hash(pair.publicKey.export({type:'spki',format:'der'}));
test('recipient is RSA4096 public SPKI matched by external fingerprint, no private key',()=>{
 assert.equal(recipient(pem,fp).asymmetricKeyDetails.modulusLength,4096);assert.throws(()=>recipient(pem,'a'.repeat(64)));assert.throws(()=>recipient(pair.privateKey.export({type:'pkcs8',format:'pem'}),fp));
 const small=generateKeyPairSync('rsa',{modulusLength:2048}).publicKey;assert.throws(()=>recipient(small.export({type:'spki',format:'pem'}),hash(small.export({type:'spki',format:'der'}))));
});
test('real encryption roundtrip contains no plaintext and rejects changed authenticated ciphertext',()=>{
 const files={'application.private.sql':'CANARY_DDL_PRIVATE'},e=envelope(files,recipient(pem,fp));assert.ok(!JSON.stringify(e).includes('CANARY'));
 const key=privateDecrypt({key:pair.privateKey,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(e.wrapped_key,'base64'));
 const decode=(b)=>{const d=createDecipheriv('aes-256-gcm',key,Buffer.from(e.iv,'base64'));d.setAuthTag(Buffer.from(e.tag,'base64'));return Buffer.concat([d.update(b),d.final()])};
 assert.deepEqual(JSON.parse(decode(Buffer.from(e.ciphertext,'base64'))).files,files);const bad=Buffer.from(e.ciphertext,'base64');bad[0]^=1;assert.throws(()=>decode(bad));key.fill(0);
});
const context={image:IMAGE,run:'jolene-ddl-123-1',root:'/tmp/jolene-ddl-123-1',source:'/checkout/tools/restore-local/scripts/export',uid:1001,gid:1001};
const db={PATH:'/usr/bin',RESTORE_SCHEMA_SOURCE_REF:'flripxtsyegjshnhzjkz',PGHOST:'aws-0-eu-west-3.pooler.supabase.com',PGUSER:'postgres.flripxtsyegjshnhzjkz',PGPORT:'5432',PGDATABASE:'postgres',PGPASSWORD:'CANARY_SECRET_PASSWORD',SUPABASE_ACCESS_TOKEN:'CANARY_API'};
test('only psql catalogue and schema-only dump obtain network plus exact read-only DB env; secret never in argv',()=>{
 const args=['--no-psqlrc','--no-password','--tuples-only','--no-align','--set=ON_ERROR_STOP=1','--file',context.source+'/catalogue-export.sql'];
 for(const [tool,a]of [['psql',args],['pg_dump',dumpArgs(context.root+'/export')]]){const p=clientArgs(context,tool,a,db,10);assert.equal(p.args[p.args.indexOf('--network')+1],'bridge');assert.equal(p.env.PGSSLMODE,'verify-full');assert.match(p.env.PGOPTIONS,/default_transaction_read_only=on/);assert.equal(p.env.SUPABASE_ACCESS_TOKEN,undefined);assert.ok(!JSON.stringify(p.args).includes('CANARY'));assert.equal(p.args[p.args.indexOf('--entrypoint')+1],tool);}
});
test('versions and pg_restore file extraction have no network and no credentials',()=>{
 for(const [tool,a]of [['psql',['--version']],['pg_dump',['--version']],['pg_restore',['--list',context.root+'/export/schema.private.dump']]]){const p=clientArgs(context,tool,a,db,10);assert.equal(p.args[p.args.indexOf('--network')+1],'none');assert.equal(p.env.PGPASSWORD,undefined);assert.ok(!p.args.includes('--env'));}
});
test('arbitrary SQL, data dump, restore database target, extra args, image override and mount injection refuse',()=>{
 for(const [tool,a]of [['psql',['-c','DROP SCHEMA public']],['pg_dump',['--data-only']],['pg_restore',['--dbname=postgres']],['psql',['--version','-c','SELECT 1']]])assert.throws(()=>clientArgs(context,tool,a,db));
 for(const c of [{...context,image:'other:latest'},{...context,root:context.root+',rw'},{...context,uid:0}])assert.throws(()=>clientArgs(c,'psql',['--version'],db));
});
test('cleanup rejects wrong name, image, label or malformed ID before removing anything',()=>{
 const row={Id:'d'.repeat(64),Name:'/jolene-ddl-123-1-psql-10',Image:IMAGE,Labels:{'org.jolene.restore-export':'jolene-ddl-123-1'}};
 assert.deepEqual(cleanupPlan([row],context.run),[row.Id]);for(const change of [{Name:'/other'},{Image:'other'},{Labels:{}},{Id:'evil'}])assert.throws(()=>cleanupPlan([{...row,...change}],context.run));
});
test('sealing verifies every scanned hash and refuses known-secret reintroduction or changed file',()=>{
 const dir=mkdtempSync(resolve(tmpdir(),'ddl-seal-test-'));try{
 const files={};for(const name of ['all.private.sql','application.private.sql','customizations.private.sql','managed-acl-review.private.sql']){const text='CREATE SCHEMA example;';writeFileSync(resolve(dir,name),text);files[name]={sha256:hash(text),bytes:Buffer.byteLength(text),statements:1};}
 const manifest={result:'DDL_QUARANTINED_ONLY',release_authorized:false,import_ready:false,files};writeFileSync(resolve(dir,'manifest.json'),JSON.stringify(manifest));
 const sealed=sealFiles(dir,recipient(pem,fp)).encrypted;assert.equal(sealed.format,'JOLENE_DDL_ENCRYPTED_V1');
 const opened=decryptQuarantine(sealed,pair.privateKey.export({type:'pkcs8',format:'pem'}),fp);assert.equal(opened['application.private.sql'].toString(),'CREATE SCHEMA example;');
 assert.throws(()=>decryptQuarantine(sealed,pair.privateKey.export({type:'pkcs8',format:'pem'}),'0'.repeat(64)));
 const escaped=envelope({'../outside':'YQ=='},recipient(pem,fp));assert.throws(()=>decryptQuarantine(escaped,pair.privateKey.export({type:'pkcs8',format:'pem'}),fp));
 writeFileSync(resolve(dir,'application.private.sql'),'ALTERED');assert.throws(()=>sealFiles(dir,recipient(pem,fp)),/FILE_CHANGED/);
 const text='SELECT sk_live_CANARY123456789;';writeFileSync(resolve(dir,'application.private.sql'),text);manifest.files['application.private.sql']={sha256:hash(text),bytes:Buffer.byteLength(text),statements:1};writeFileSync(resolve(dir,'manifest.json'),JSON.stringify(manifest));assert.throws(()=>sealFiles(dir,recipient(pem,fp)),/SECRET_PATTERN/);
 }finally{rmSync(dir,{recursive:true,force:true})}
});
test('workflow keeps PR tests credential-free and dispatch main-only with one DB credential step, no unsafe triggers/bootstrap/reset or raw dump upload',()=>{
 const w=readFileSync(new URL('../../../../.github/workflows/restore-schema-export.yml',import.meta.url),'utf8');
 assert.ok(w.includes('pull_request:'));assert.ok(w.includes('workflow_dispatch:'));assert.ok(!/pull_request_target:|\n  push:|\n  schedule:/.test(w));assert.equal((w.match(/secrets\./g)||[]).length,1);assert.ok(w.includes('contents: read'));assert.ok(w.includes('persist-credentials: false'));assert.ok(w.includes('needs: approved-main-head'));assert.ok(w.includes("github.event_name == 'workflow_dispatch'"));assert.ok(w.includes("github.ref == 'refs/heads/main'"));assert.ok(!w.includes('ref: ${{ github.event.pull_request.head.sha }}'));assert.ok(!w.includes('inputs:'));
 assert.ok(!/deploy-supabase|supabase db|bootstrap\.mjs|\.private\.sql|schema\.private\.dump/.test(w));assert.ok(w.includes('ddl-quarantine.encrypted.json'));assert.ok(w.includes('if: always()'));assert.ok(!/continue-on-error|\|\| true/.test(w));
});
