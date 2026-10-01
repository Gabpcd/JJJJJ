#!/usr/bin/env node
// Dedicated read-only exporter. Does not import, link, migrate or reset any database.
import {readFileSync,writeFileSync,mkdirSync,existsSync,rmSync,realpathSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash,createPublicKey,publicEncrypt,randomBytes,createCipheriv,constants} from 'node:crypto';
import {collect,publicError,validateApproval,rejectKnownSecrets} from './export-schema.mjs';
export const IMAGE='supabase/postgres@sha256:5a4314708484bec672de2c09653a5c01fb1c84a998564ac231b0325e2238ed5b';
export const REPO='Gabpcd/JJJJJ';
const SAFE=Symbol('closed-ci-export');
const HERE=dirname(fileURLToPath(import.meta.url)),fail=code=>{const e=Error(code);e[SAFE]=true;throw e},sha=x=>createHash('sha256').update(x).digest('hex');
export function identity(env,event,head,now=Date.now()){
 if(env.GITHUB_EVENT_NAME!=='workflow_dispatch'||env.GITHUB_REPOSITORY!==REPO||event?.repository?.full_name!==REPO||env.GITHUB_REF!=='refs/heads/main')fail('CI_REPOSITORY_OR_EVENT_REFUSED');
 if(!/^[a-f0-9]{40}$/.test(env.RESTORE_EXPORT_APPROVED_HEAD??'')||env.GITHUB_SHA!==env.RESTORE_EXPORT_APPROVED_HEAD||head!==env.RESTORE_EXPORT_APPROVED_HEAD)fail('CI_HEAD_OR_BRANCH_REFUSED');
 if(!/^[1-9][0-9]{0,14}$/.test(env.GITHUB_RUN_ID??'')||!/^[1-9][0-9]{0,2}$/.test(env.GITHUB_RUN_ATTEMPT??''))fail('CI_RUN_REFUSED');
 const approval={source_ref:'flripxtsyegjshnhzjkz',catalogue_md5:env.RESTORE_EXPORT_CATALOGUE_MD5,expires_at:env.RESTORE_EXPORT_EXPIRES_AT};validateApproval(approval,now);
 return {run:'jolene-ddl-'+env.GITHUB_RUN_ID+'-'+env.GITHUB_RUN_ATTEMPT,head,approval};
}
export function recipient(pem,expected){
 if(typeof pem!=='string'||!pem.startsWith('-----BEGIN PUBLIC KEY-----')||pem.includes('PRIVATE')||!/^[a-f0-9]{64}$/.test(expected??''))fail('RECIPIENT_REFUSED');
 const key=createPublicKey(pem);if(key.asymmetricKeyType!=='rsa'||key.asymmetricKeyDetails.modulusLength!==4096)fail('RECIPIENT_REFUSED');
 const der=key.export({type:'spki',format:'der'});if(sha(der)!==expected)fail('RECIPIENT_FINGERPRINT_REFUSED');return key;
}
function execute(bin,args,env={PATH:process.env.PATH}){
 const r=spawnSync(bin,args,{env,encoding:'utf8',timeout:300000,maxBuffer:4*1024*1024});if(r.error||r.status!==0)fail('CI_TOOL_FAILED');return r.stdout;
}
function runPaths(env){
 if(!/^[1-9][0-9]{0,14}$/.test(env.GITHUB_RUN_ID??'')||!/^[1-9][0-9]{0,2}$/.test(env.GITHUB_RUN_ATTEMPT??''))fail('CI_RUN_REFUSED');
 const run='jolene-ddl-'+env.GITHUB_RUN_ID+'-'+env.GITHUB_RUN_ATTEMPT;
 if(!env.RUNNER_TEMP||!env.RUNNER_TEMP.startsWith('/')||realpathSync(env.RUNNER_TEMP)!==env.RUNNER_TEMP)fail('RUNNER_TEMP_REFUSED');
 return {run,dir:resolve(env.RUNNER_TEMP,run),proof:resolve('/tmp',run+'-proof')};
}
function approved(env){return identity(env,JSON.parse(readFileSync(env.GITHUB_EVENT_PATH)),execute('git',['rev-parse','HEAD']).trim());}
const q=x=>"'"+x.replaceAll("'","'\\''")+"'";
export function envelope(files,key){
 const plaintext=Buffer.from(JSON.stringify({format:'JOLENE_DDL_QUARANTINE_V1',files}));if(plaintext.length>96*1024*1024)fail('ENVELOPE_TOO_LARGE');
 const secret=randomBytes(32),iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',secret,iv),ciphertext=Buffer.concat([cipher.update(plaintext),cipher.final()]);
 const out={format:'JOLENE_DDL_ENCRYPTED_V1',cipher:'AES-256-GCM',key_wrap:'RSA-OAEP-SHA256',wrapped_key:publicEncrypt({key,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},secret).toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),ciphertext:ciphertext.toString('base64')};secret.fill(0);return out;
}
export function sealFiles(dir,key){
 const manifest=JSON.parse(readFileSync(resolve(dir,'manifest.json')));if(manifest.result!=='DDL_QUARANTINED_ONLY'||manifest.release_authorized!==false||manifest.import_ready!==false)fail('MANIFEST_REFUSED');
 const names=['all.private.sql','application.private.sql','customizations.private.sql','managed-acl-review.private.sql'];
 if(Object.keys(manifest.files??{}).sort().join()!==[...names].sort().join())fail('MANIFEST_FILES_REFUSED');
 const files={};for(const name of names){const b=readFileSync(resolve(dir,name));if(b.length>32*1024*1024||manifest.files[name].sha256!==sha(b)||manifest.files[name].bytes!==b.length)fail('FILE_CHANGED_AFTER_SCAN');rejectKnownSecrets(b.toString());files[name]=b.toString('base64');}
 files['manifest.json']=Buffer.from(JSON.stringify(manifest)).toString('base64');return {encrypted:envelope(files,key),manifest};
}
export function cleanupPlan(rows,run){
 if(!Array.isArray(rows))fail('CLEANUP_INVENTORY_REFUSED');
 return rows.map(r=>{if(!/^[a-f0-9]{12,64}$/.test(r.Id??'')||!new RegExp('^'+run+'-(psql|pg_dump|pg_restore)-[0-9]+$').test((r.Name??'').replace(/^\//,''))||r.Image!==IMAGE||r.Labels?.['org.jolene.restore-export']!==run)fail('CLEANUP_OWNERSHIP_REFUSED');return r.Id});
}
export function main(cmd,env=process.env){
 const p=runPaths(env);process.umask(0o077);
 if(cmd==='cleanup'){
  const ids=execute('docker',['ps','-aq','--filter','label=org.jolene.restore-export='+p.run]).trim().split(/\s+/).filter(Boolean);
  if(ids.length){if(ids.some(x=>!/^[a-f0-9]{12,64}$/.test(x)))fail('CLEANUP_INVENTORY_REFUSED');
   const format='{"Id":{{json .Id}},"Name":{{json .Name}},"Image":{{json .Config.Image}},"Labels":{{json .Config.Labels}}}';
   const rows=execute('docker',['inspect','--format',format,...ids]).trim().split('\n').map(x=>JSON.parse(x));
   for(const id of cleanupPlan(rows,p.run))execute('docker',['rm','--force',id]);
  }
  if(execute('docker',['ps','-aq','--filter','label=org.jolene.restore-export='+p.run]).trim())fail('CLEANUP_REMAINS');
  if(existsSync(p.dir)){if(realpathSync(p.dir)!==p.dir)fail('CLEANUP_PATH_REFUSED');rmSync(p.dir,{recursive:true});}
  return {result:'EXPORT_PRIVATE_CLEANED',containers:0,private_directory_absent:!existsSync(p.dir)};
 }
 const id=approved(env),key=recipient(env.RESTORE_EXPORT_RECIPIENT_PUBLIC_KEY,env.RESTORE_EXPORT_RECIPIENT_SHA256);
 if(cmd==='identity')return {result:'EXPORT_MAIN_APPROVED',run:id.run,head:id.head,recipient_sha256:env.RESTORE_EXPORT_RECIPIENT_SHA256};
 if(cmd==='prepare'){
  if(existsSync(p.dir)||existsSync(p.proof))fail('OUTPUT_MUST_BE_NEW');mkdirSync(p.dir,{mode:0o700});mkdirSync(p.proof,{mode:0o700});mkdirSync(resolve(p.dir,'bin'),{mode:0o700});
  const context={image:IMAGE,run:id.run,root:p.dir,source:HERE,uid:process.getuid(),gid:process.getgid()};const contextPath=resolve(p.dir,'context.json');writeFileSync(contextPath,JSON.stringify(context),{mode:0o600,flag:'wx'});
  for(const tool of ['psql','pg_dump','pg_restore'])writeFileSync(resolve(p.dir,'bin',tool),'#!/bin/sh\nexec '+q(process.execPath)+' '+q(resolve(HERE,'docker-tool.mjs'))+' '+q(contextPath)+' '+tool+' "$@"\n',{mode:0o700,flag:'wx'});
  execute('docker',['pull','--platform','linux/amd64','--quiet',IMAGE]);
  const digests=JSON.parse(execute('docker',['image','inspect',IMAGE,'--format','{{json .RepoDigests}}']));if(!digests.includes(IMAGE))fail('IMAGE_DIGEST_MISMATCH');
  return {result:'EXPORT_TOOLS_PREPARED',image:IMAGE,run:id.run};
 }
 if(cmd==='collect'){
  const result=collect(resolve(p.dir,'export'),id.approval,{...env,PATH:resolve(p.dir,'bin')+':'+env.PATH});
  return {result:result.result,run:id.run,head:id.head,files:result.files,release_authorized:false,import_ready:false};
 }
 if(cmd==='seal'){
  const {encrypted,manifest}=sealFiles(resolve(p.dir,'export'),key);const bytes=Buffer.from(JSON.stringify(encrypted));
  writeFileSync(resolve(p.proof,'ddl-quarantine.encrypted.json'),bytes,{mode:0o600,flag:'wx'});
  const report={result:'ENCRYPTED_QUARANTINE_ONLY',run:id.run,head:id.head,catalogue_md5:manifest.catalogue_md5,files:manifest.files,custom_count:manifest.custom_count,acl_count:manifest.acl_count,recipient_sha256:env.RESTORE_EXPORT_RECIPIENT_SHA256,envelope_sha256:sha(bytes),release_authorized:false,import_ready:false};
  writeFileSync(resolve(p.proof,'manifest.json'),JSON.stringify(report,null,2)+'\n',{mode:0o600,flag:'wx'});return report;
 }
 fail('CI_COMMAND_REFUSED');
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))try{console.log(JSON.stringify(main(process.argv[2])))}catch(e){const detail=publicError(e);console.error(JSON.stringify({result:'REFUSED',code:e?.[SAFE]===true?e.message:detail.code,phase:detail.phase}));process.exitCode=1}
