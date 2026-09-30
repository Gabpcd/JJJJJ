#!/usr/bin/env node
// PREPARATION ONLY until an exact catalogue is reviewed. No import, reset, data dump or cloud provisioning.
import {readFileSync,writeFileSync,mkdirSync,existsSync,statSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const HERE=dirname(fileURLToPath(import.meta.url)), SOURCE='flripxtsyegjshnhzjkz';
const SAFE=Symbol('closed-export-error');
let phase='input';
const fail=code=>{const e=new Error(code);e[SAFE]=true;throw e};
const hash=b=>createHash('sha256').update(b).digest('hex');
const scope=()=>JSON.parse(readFileSync(resolve(HERE,'scope.json'),'utf8'));
export function publicError(e){return {result:'REFUSED',code:e?.[SAFE]===true?e.message:'EXPORT_INTERNAL_FAILURE',release_authorized:false,phase};}
export function connectionEnv(env){
 if(env.RESTORE_SCHEMA_SOURCE_REF!==SOURCE)fail('SOURCE_REF_REFUSED');
 const direct=env.PGHOST==='db.'+SOURCE+'.supabase.co'&&env.PGUSER==='postgres';
 const pooler=/^aws-[0-9]+-[a-z]+-[a-z]+-[0-9]+\.pooler\.supabase\.com$/.test(env.PGHOST??'')&&env.PGUSER==='postgres.'+SOURCE;
 if((!direct&&!pooler)||env.PGPORT!=='5432'||env.PGDATABASE!=='postgres'||typeof env.PGPASSWORD!=='string'||env.PGPASSWORD.length<8)fail('CONNECTION_REFUSED');
 return {PATH:env.PATH,PGHOST:env.PGHOST,PGPORT:'5432',PGDATABASE:'postgres',PGUSER:env.PGUSER,PGPASSWORD:env.PGPASSWORD,
  PGSSLMODE:'verify-full',PGSSLROOTCERT:'system',PGGSSENCMODE:'disable',PGCONNECT_TIMEOUT:'10',
  PGOPTIONS:'-c default_transaction_read_only=on -c statement_timeout=60000 -c lock_timeout=5000',PGAPPNAME:'jolene-schema-export-read-only'};
}
export function validateApproval(a,now=Date.now()){
 if(!a||Object.keys(a).sort().join()!=='catalogue_md5,expires_at,source_ref'||a.source_ref!==SOURCE||!/^[a-f0-9]{32}$/.test(a.catalogue_md5??''))fail('APPROVAL_REFUSED');
 const until=Date.parse(a.expires_at);if(!Number.isFinite(until)||until<now||until>now+3600000)fail('APPROVAL_EXPIRED_OR_TOO_LONG');
 return true;
}
const sorted=x=>JSON.stringify([...x].sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))));
export function validateCatalogue(c,a,s=scope()){
 if(c?.version!==1||c.database!=='postgres'||c.read_only!==true||c.postgres_major!==17||c.catalogue_md5!==a.catalogue_md5)fail('CATALOGUE_REFUSED');
 if(JSON.stringify(c.application_schemas)!=='["private","public"]'||c.foreign_tables!==0||c.direct_secret_pattern_routines!==0)fail('UNSAFE_OR_INCOMPLETE_CATALOGUE');
 const canonical=x=>x.map(e=>({name:e.name,version:e.version,schema:e.schema}));
 if(sorted(canonical(c.extensions??[]))!==sorted(canonical(s.extensions)))fail('EXTENSIONS_CHANGED');
 const ids=x=>x.map(e=>({schema:e.schema,table:e.table,name:e.name}));
 if(sorted(ids(c.managed_policies??[]))!==sorted(ids(s.custom_policies))||sorted(ids(c.auth_triggers??[]))!==sorted(ids(s.custom_triggers)))fail('MANAGED_OBJECTS_CHANGED');
 return true;
}
export function dumpArgs(dir){return ['--schema-only','--format=custom','--no-large-objects','--no-comments','--no-security-labels','--no-publications','--no-subscriptions','--schema=public','--schema=private','--schema=auth','--schema=storage','--lock-wait-timeout=5000','--file',resolve(dir,'schema.private.dump')];}
export function selectManagedToc(toc,s=scope()){
 const expected=new Set([...s.custom_policies.map(x=>'POLICY '+x.schema+' '+x.table+' '+x.name),...s.custom_triggers.map(x=>'TRIGGER '+x.schema+' '+x.table+' '+x.name)]),found=new Set(),selected=[],acl=[];
 for(const line of toc.split('\n')){
  if(!line||line.startsWith(';'))continue;
  if(!/^\d+; \d+ \d+ /.test(line))fail('TOC_FORMAT_REFUSED');
  if(/\b(TABLE DATA|MATERIALIZED VIEW DATA|SEQUENCE SET|BLOB|BLOBS|LARGE OBJECT)\b/.test(line))fail('TOC_DATA_REFUSED');
  const m=line.match(/^\d+; \d+ \d+ (POLICY|TRIGGER) (auth|storage) ([a-z_][a-z0-9_]*) ([a-z_][a-z0-9_]*) ([a-z_][a-z0-9_]*)$/);
  if(m){const id=m.slice(1,5).join(' ');if(expected.has(id)){if(found.has(id))fail('TOC_DUPLICATE');found.add(id);selected.push(line);}else if(m[1]==='POLICY'||m[2]==='auth')fail('MANAGED_OBJECTS_CHANGED');}
  else if(/\b(POLICY|TRIGGER) (auth|storage)\b/.test(line))fail('TOC_MANAGED_FORMAT_REFUSED');
  if(/^\d+; \d+ \d+ (?:DEFAULT )?ACL (auth|storage) /.test(line)||/^\d+; \d+ \d+ ACL - SCHEMA (auth|storage) /.test(line))acl.push(line);
 }
 if(found.size!==expected.size)fail('MANAGED_OBJECT_MISSING');
 return {custom:selected.join('\n')+'\n',acl:acl.join('\n')+'\n',custom_count:selected.length,acl_count:acl.length};
}
export function rejectKnownSecrets(text,password){
 if((password&&text.includes(password))||/-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?:sk_live_|sk_test_|sb_secret_|sbp_)[A-Za-z0-9_-]{8,}|\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|(?:postgres(?:ql)?|https?):\/\/[^\s/'"]+:[^\s/'"]+@/.test(text))fail('SECRET_PATTERN_REFUSED');
}
function execute(bin,args,env,input){
 const r=spawnSync(bin,args,{input,env,encoding:'utf8',timeout:180000,maxBuffer:32*1024*1024});
 if(r.error||r.status!==0)fail('EXPORT_TOOL_FAILED');if(r.stderr?.trim())fail('EXPORT_TOOL_WARNING_REFUSED');return r.stdout;
}
export function collect(dir,approval,env=process.env,run=execute){
 phase='input';validateApproval(approval);const db=connectionEnv(env),local={PATH:env.PATH,PYTHONDONTWRITEBYTECODE:'1'};
 if(existsSync(dir))fail('OUTPUT_MUST_BE_NEW');
 phase='tool_versions';const tool_versions={};
 for(const tool of ['psql','pg_dump','pg_restore']){const output=run(tool,['--version'],local).trim();const v=output.match(/^\w+ \(PostgreSQL\) (17\.[0-9]+)(?:\s|$)/);if(!v)fail('PG17_TOOLS_REQUIRED');tool_versions[tool]=v[1];}
 // AST validator must be available before any remote read. No installer is invoked here.
 run('python3',['-c','import pglast; assert pglast.__version__ == "v7.10"'],local);
 const readCatalogue=()=>JSON.parse(run('psql',['--no-psqlrc','--no-password','--tuples-only','--no-align','--set=ON_ERROR_STOP=1','--file',resolve(HERE,'catalogue-export.sql')],db));
 phase='catalogue_before';const before=readCatalogue();validateCatalogue(before,approval);
 process.umask(0o077);mkdirSync(dir,{mode:0o700});
 const write=(name,text)=>writeFileSync(resolve(dir,name),text,{mode:0o600,flag:'wx'});
 write('catalogue-before.private.json',JSON.stringify(before));
 phase='schema_dump';run('pg_dump',dumpArgs(dir),db);
 const archive=resolve(dir,'schema.private.dump');if(statSync(archive).size>32*1024*1024)fail('ARCHIVE_TOO_LARGE');
 phase='toc';const toc=run('pg_restore',['--list',archive],local);rejectKnownSecrets(toc,db.PGPASSWORD);write('toc.private.txt',toc);
 const lists=selectManagedToc(toc);write('custom.list.private.txt',lists.custom);write('acl.list.private.txt',lists.acl);
 const extracts=[['all.private.sql',[]],['application.private.sql',['--schema=public','--schema=private']],['customizations.private.sql',['--use-list',resolve(dir,'custom.list.private.txt')]],['managed-acl-review.private.sql',['--use-list',resolve(dir,'acl.list.private.txt')]]];
 const files={};
 for(const [name,selection]of extracts){
  phase='extract_ddl';const path=resolve(dir,name);run('pg_restore',['--schema-only',...selection,'--file',path,archive],local);
  const text=readFileSync(path,'utf8');if(Buffer.byteLength(text)>32*1024*1024)fail('DDL_TOO_LARGE');rejectKnownSecrets(text,db.PGPASSWORD);
  phase='scan_ddl';const scan=JSON.parse(run('python3',[resolve(HERE,'audit-ddl.py'),path],local));if(scan.result!=='DDL_STRUCTURALLY_SCANNED')fail('DDL_SCAN_REFUSED');
  files[name]={sha256:hash(text),bytes:Buffer.byteLength(text),statements:scan.statements};
 }
 phase='catalogue_after';const after=readCatalogue();validateCatalogue(after,approval);if(JSON.stringify(before)!==JSON.stringify(after))fail('CATALOGUE_CHANGED_DURING_EXPORT');
 write('catalogue-after.private.json',JSON.stringify(after));
 phase='manifest';const result={tool_versions,result:'DDL_QUARANTINED_ONLY',source_ref:SOURCE,catalogue_md5:before.catalogue_md5,files,custom_count:lists.custom_count,acl_count:lists.acl_count,release_authorized:false,import_ready:false,manual_secret_and_effect_review_required:true,pgjwt_compatibility:'RUNTIME_AVAILABLE_VERSIONS_REQUIRED'};
 write('manifest.json',JSON.stringify(result,null,2)+'\n');return result;
}
export function main(args){
 if(args[0]==='plan')return {result:'READ_ONLY_DDL_PLAN',source_ref:SOURCE,schemas:['public','private','auth','storage'],rows:false,roles_passwords:false,commands:['psql catalogue SELECT','pg_dump --schema-only --format=custom','pg_restore to files only','offline pglast and secret scan','psql catalogue SELECT'],release_authorized:false,import_ready:false};
 if(args[0]!=='collect'||args.length!==3)fail('COMMAND_REFUSED');
 return collect(resolve(args[1]),JSON.parse(readFileSync(args[2],'utf8')));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))try{console.log(JSON.stringify(main(process.argv.slice(2))))}catch(e){console.error(JSON.stringify(publicError(e)));process.exitCode=1}
