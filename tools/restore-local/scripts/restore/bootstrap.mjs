#!/usr/bin/env node
// Empty infrastructure by default; an explicit isolated import qualification mode is separate.
import { randomBytes, createHash, createHmac } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {projectExtensions} from './extensions.mjs';
export const QUALIFICATION_DB='jolene_candidatures_pg17_test';
export const QUALIFICATION_ARGS=['-c','cron.database_name='+QUALIFICATION_DB,'-c','cron.launch_active_jobs=off','-c','max_worker_processes=0'];
export const FORBIDDEN=['flripxtsyegjshnhzjkz','mejpriaetwgtcstbgfid','wnepopwygokbhlqghydb'];
const HERE=dirname(fileURLToPath(import.meta.url)), ROOT=resolve(HERE,'../..');
const LABEL='org.jolene.restore-drill', SIDES=['source','target'], ROLES=['db','auth','rest','storage','api'];
const SAFE_ERROR=Symbol('bootstrap-safe-error');
const PHASES=new Set(['plan','read_plan','docker_context','preload','image_preflight','compose_config','resource_preflight','compose_up','inspection','diagnostic','empty_sql_source','empty_sql_target','api_health_source','api_health_target','cleanup_inventory','cleanup_containers','cleanup_volumes','cleanup_network','verify_absence','extensions_source','extensions_target']);
let currentPhase='read_plan';
const fail=(code,detail)=>{const e=new Error(code);e[SAFE_ERROR]=true;e.detail=detail;throw e},sha=b=>createHash('sha256').update(b).digest('hex');
export function projectProcessFailure(result){
 const signals=['SIGTERM','SIGKILL','SIGINT','SIGABRT','SIGSEGV'];
 return {exit_code:Number.isInteger(result.status)&&result.status>=0&&result.status<=255?result.status:null,
  signal:result.signal===null?null:(signals.includes(result.signal)?result.signal:'other'),timed_out:result.error?.code==='ETIMEDOUT'};
}
export function publicFailure(error){
 return {result:'REFUSED',code:error?.[SAFE_ERROR]===true?error.message:'UNCLASSIFIED_FAILURE',phase:PHASES.has(currentPhase)?currentPhase:'other',
  ...(error?.[SAFE_ERROR]===true&&error.detail?{process:projectProcessFailure(error.detail)}:{})};
}

const read=p=>JSON.parse(readFileSync(p,'utf8'));
const name=(run,side,role)=>[run,side,role].join('-');
const write=(p,b)=>writeFileSync(p,b,{mode:0o600,flag:'wx'});
export function verifySources(){
 const manifest=read(resolve(ROOT,'sources/official-sources.json'));
 for(const name of ['webhooks.sql','roles.sql','jwt.sql']){
  const entries=manifest.sources.filter(x=>x.path==='docker/volumes/db/'+name);
  if(entries.length!==1||!entries[0].url.startsWith('https://raw.githubusercontent.com/supabase/supabase/'+manifest.commit+'/')
    ||sha(readFileSync(resolve(ROOT,'sources/volumes/db',name)))!==entries[0].sha256)fail('VENDORED_SOURCE_CHANGED');
 }
}

export function runName(run){
 if(!/^jolene-restore-drill-[a-z0-9][a-z0-9-]{0,25}$/.test(run)||FORBIDDEN.some(x=>run.includes(x)))fail('RUN_INVALID');return run;
}
function jwt(secret,role){
 const part=x=>Buffer.from(JSON.stringify(x)).toString('base64url'),now=Math.floor(Date.now()/1000);
 const s=part({alg:'HS256',typ:'JWT'})+'.'+part({role,iss:'supabase',iat:now,exp:now+86400});
 return s+'.'+createHmac('sha256',secret).update(s).digest('base64url');
}
export function gateway(run,side,anon,service){
 return {_format_version:'2.1',_transform:true,
  consumers:[{username:'anon',keyauth_credentials:[{key:anon}]},{username:'service_role',keyauth_credentials:[{key:service}]}],
  acls:[{consumer:'anon',group:'anon'},{consumer:'service_role',group:'admin'}],
  services:[['auth',9999],['rest',3000],['storage',5000]].map(([role,port])=>({
   name:role+'-v1',url:'http://'+name(run,side,role)+':'+port+'/',
   routes:[{name:role+'-v1',strip_path:true,paths:['/'+role+'/v1/']}],
   plugins:[{name:'cors'},{name:'key-auth',config:{hide_credentials:false}},
    {name:'request-transformer',config:{add:{headers:["Authorization: $((headers.authorization ~= nil and headers.authorization) or headers.apikey)"]}}},
    {name:'acl',config:{hide_groups_header:true,allow:['anon','admin']}}]
  }))};
}
export function makePlan(run,dir,lock,secrets,{qualification=false}={}){
 if(typeof qualification!=='boolean')fail('QUALIFICATION_MODE_INVALID');
 const database=qualification?QUALIFICATION_DB:'postgres';
 runName(run);if(lock.platform!=='linux/amd64'||lock.images.length!==5)fail('IMAGE_LOCK_INVALID');
 const services={},volumes={},labels={[LABEL]:run};
 const img=repo=>{const a=lock.images.filter(x=>x.repository===repo);
  if(a.length!==1||!/^sha256:[a-f0-9]{64}$/.test(a[0].linux_amd64_digest)||a[0].reference!==repo+'@'+a[0].linux_amd64_digest)fail('IMAGE_LOCK_INVALID');return a[0].reference;};
 const base=(s,r,repo)=>({container_name:name(run,s,r),image:img(repo),platform:'linux/amd64',pull_policy:'never',restart:'no',labels,networks:['isolated'],security_opt:['no-new-privileges:true'],logging:{driver:'none'}});
 const health=test=>({test,interval:'5s',timeout:'4s',retries:24,start_period:'15s'});
 const bind=(source,target)=>({type:'bind',source,target,read_only:true,bind:{create_host_path:false}});
 for(const side of SIDES){
  const s=secrets[side],db=name(run,side,'db'),api='http://'+name(run,side,'api')+':8000',anon=jwt(s.jwt,'anon'),service=jwt(s.jwt,'service_role');
  for(const role of ['data','config','files'])volumes[side+'-'+role]={name:name(run,side,role),labels};
  services[side+'-db']={...base(side,'db','supabase/postgres'),
   environment:{POSTGRES_HOST:'/var/run/postgresql',PGPORT:'5432',POSTGRES_PORT:'5432',PGPASSWORD:s.password,POSTGRES_PASSWORD:s.password,PGDATABASE:database,POSTGRES_DB:database,JWT_EXP:'3600'},
   volumes:[{type:'volume',source:side+'-data',target:'/var/lib/postgresql/data'},{type:'volume',source:side+'-config',target:'/etc/postgresql-custom'},
    bind(resolve(ROOT,'sources/volumes/db/webhooks.sql'),'/docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql'),
    bind(resolve(ROOT,'sources/volumes/db/roles.sql'),'/docker-entrypoint-initdb.d/init-scripts/99-roles.sql'),
    bind(resolve(ROOT,'sources/volumes/db/jwt.sql'),'/docker-entrypoint-initdb.d/init-scripts/99-jwt.sql'),
    bind(resolve(HERE,'init-extensions.sql'),'/docker-entrypoint-initdb.d/init-scripts/zz-restore-extensions.sql')],
   command:['postgres','-c','config_file=/etc/postgresql/postgresql.conf','-c','log_min_messages=fatal','-c','log_statement=none',...(qualification?QUALIFICATION_ARGS:[])],
   healthcheck:health(['CMD','pg_isready','-U','postgres','-h','localhost'])};
  const depends_on={[side+'-db']:{condition:'service_healthy'}};
  services[side+'-auth']={...base(side,'auth','supabase/gotrue'),depends_on,
   environment:{GOTRUE_API_HOST:'0.0.0.0',GOTRUE_API_PORT:'9999',API_EXTERNAL_URL:api+'/auth/v1',
    GOTRUE_DB_DRIVER:'postgres',GOTRUE_DB_DATABASE_URL:'postgres://supabase_auth_admin:'+s.password+'@'+db+':5432/'+database,
    GOTRUE_SITE_URL:'http://'+run+'-preview:4173',GOTRUE_URI_ALLOW_LIST:'',GOTRUE_DISABLE_SIGNUP:'true',
    GOTRUE_JWT_ADMIN_ROLES:'service_role',GOTRUE_JWT_AUD:'authenticated',GOTRUE_JWT_DEFAULT_GROUP_NAME:'authenticated',GOTRUE_JWT_EXP:'3600',GOTRUE_JWT_SECRET:s.jwt,GOTRUE_JWT_ISSUER:api+'/auth/v1',
    GOTRUE_EXTERNAL_EMAIL_ENABLED:'true',GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED:'false',GOTRUE_MAILER_AUTOCONFIRM:'true',
    GOTRUE_EXTERNAL_PHONE_ENABLED:'false',GOTRUE_SMS_AUTOCONFIRM:'false',GOTRUE_SMTP_HOST:'127.0.0.1',GOTRUE_SMTP_PORT:'1',
    GOTRUE_HOOK_SEND_EMAIL_ENABLED:'false',GOTRUE_HOOK_SEND_SMS_ENABLED:'false',GOTRUE_LOG_LEVEL:'error'},
   healthcheck:health(['CMD','wget','--no-verbose','--tries=1','--spider','http://localhost:9999/health'])};
  services[side+'-rest']={...base(side,'rest','postgrest/postgrest'),depends_on,
   environment:{PGRST_DB_URI:'postgres://authenticator:'+s.password+'@'+db+':5432/'+database,PGRST_DB_SCHEMAS:'public',PGRST_DB_EXTRA_SEARCH_PATH:'public,extensions',PGRST_DB_ANON_ROLE:'anon',PGRST_JWT_SECRET:s.jwt,PGRST_DB_USE_LEGACY_GUCS:'false',PGRST_ADMIN_SERVER_PORT:'3001',PGRST_ADMIN_SERVER_HOST:'localhost',PGRST_LOG_LEVEL:'crit'},
   command:['postgrest'],healthcheck:health(['CMD','postgrest','--ready'])};
  services[side+'-storage']={...base(side,'storage','supabase/storage-api'),depends_on:{...depends_on,[side+'-rest']:{condition:'service_healthy'}},
   environment:{ANON_KEY:anon,SERVICE_KEY:service,POSTGREST_URL:'http://'+name(run,side,'rest')+':3000',AUTH_JWT_SECRET:s.jwt,
    DATABASE_URL:'postgres://supabase_storage_admin:'+s.password+'@'+db+':5432/'+database,STORAGE_PUBLIC_URL:api,REQUEST_ALLOW_X_FORWARDED_PATH:'true',FILE_SIZE_LIMIT:'1048576',STORAGE_BACKEND:'file',GLOBAL_S3_BUCKET:'stub',FILE_STORAGE_BACKEND_PATH:'/var/lib/storage',TENANT_ID:run+'-'+side,REGION:'local',ENABLE_IMAGE_TRANSFORMATION:'false',LOG_LEVEL:'error'},
   volumes:[{type:'volume',source:side+'-files',target:'/var/lib/storage'}],healthcheck:health(['CMD','wget','--no-verbose','--tries=1','--spider','http://127.0.0.1:5000/status'])};
  services[side+'-api']={...base(side,'api','kong/kong'),user:'0:0',depends_on:{[side+'-auth']:{condition:'service_healthy'},[side+'-rest']:{condition:'service_healthy'},[side+'-storage']:{condition:'service_healthy'}},
   environment:{KONG_DATABASE:'off',KONG_DECLARATIVE_CONFIG:'/home/kong/local.json',KONG_ROUTER_FLAVOR:'traditional_compatible',KONG_PROXY_LISTEN:'0.0.0.0:8000',KONG_ADMIN_LISTEN:'off',KONG_STATUS_LISTEN:'off',KONG_PLUGINS:'cors,key-auth,acl,request-transformer',KONG_PROXY_ACCESS_LOG:'off',KONG_PROXY_ERROR_LOG:'/dev/null',KONG_DNS_ORDER:'LAST,A,CNAME'},
   volumes:[bind(resolve(dir,side+'-gateway.private.json'),'/home/kong/local.json')],healthcheck:health(['CMD','kong','health'])};
 }
 return {name:run,services,volumes,networks:{isolated:{name:run+'-network',internal:true,labels}}};
}
export function validatePlan(plan,run){
 runName(run);
 if(plan.name!==run||Object.keys(plan.services).length!==10||Object.keys(plan.networks).join()!=='isolated'||plan.networks.isolated.internal!==true||plan.networks.isolated.name!==run+'-network')fail('PLAN_INVALID');
 for(const side of SIDES)for(const role of ROLES){
  const s=plan.services[side+'-'+role];
  if(!s||s.container_name!==name(run,side,role)||s.labels?.[LABEL]!==run||s.networks?.join()!=='isolated'||s.ports||s.network_mode||s.privileged||s.cap_add||s.extra_hosts||s.devices||s.pid||s.ipc||s.platform!=='linux/amd64'||s.pull_policy!=='never'||!/@sha256:[a-f0-9]{64}$/.test(s.image)||s.logging?.driver!=='none')fail('PLAN_ISOLATION_INVALID');
  for(const v of s.volumes??[])if(/docker\.sock|containerd\.sock|\/proc|\/sys/.test(v.source)||(v.type==='bind'&&!v.read_only))fail('MOUNT_INVALID');
  const text=JSON.stringify(s.environment);
  if(FORBIDDEN.some(x=>text.includes(x))||/supabase\.co|https:\/\/|host\.docker\.internal|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY/.test(text))fail('REMOTE_ENV_FORBIDDEN');
 }
 const qualified=SIDES.some(side=>plan.services[side+'-db'].environment?.POSTGRES_DB===QUALIFICATION_DB);
 if(qualified)for(const side of SIDES){
  const db=plan.services[side+'-db'];
  if(db.environment.POSTGRES_DB!==QUALIFICATION_DB||db.environment.PGDATABASE!==QUALIFICATION_DB
   ||JSON.stringify(db.command)!==JSON.stringify(['postgres','-c','config_file=/etc/postgresql/postgresql.conf','-c','log_min_messages=fatal','-c','log_statement=none',...QUALIFICATION_ARGS]))fail('QUALIFICATION_PLAN_INVALID');
  for(const [role,key]of [['auth','GOTRUE_DB_DATABASE_URL'],['rest','PGRST_DB_URI'],['storage','DATABASE_URL']]){
   const url=new URL(plan.services[side+'-'+role].environment[key]);
   if(url.hostname!==name(run,side,'db')||url.port!=='5432'||url.pathname!=='/'+QUALIFICATION_DB)fail('QUALIFICATION_DATABASE_INVALID');
  }
 }
 return true;
}
export function validateInspection(plan,network,containers,volumes,{partial=false}={}){
 const run=plan.name,expected=Object.values(plan.services);
 if(network.Name!==run+'-network'||network.Internal!==true||network.Labels?.[LABEL]!==run||network.Driver!=='bridge'||network.Attachable||network.EnableIPv6)fail('NETWORK_INSPECTION_REFUSED');
 if(!partial&&containers.length!==10)fail('CONTAINER_COUNT');const ids=new Set();
 for(const c of containers){
  const s=expected.find(x=>'/'+x.container_name===c.Name);
  if(!s||ids.has(c.Id)||c.Config?.Labels?.[LABEL]!==run||c.Config?.Image!==s.image||Object.keys(c.NetworkSettings?.Networks??{}).join()!==network.Name
   ||c.HostConfig?.Privileged||c.HostConfig?.PublishAllPorts||Object.keys(c.HostConfig?.PortBindings??{}).length||c.HostConfig?.CapAdd?.length
   ||['host','container'].some(x=>c.HostConfig?.NetworkMode?.startsWith(x))||c.HostConfig?.PidMode||c.HostConfig?.IpcMode==='host'||c.HostConfig?.Devices?.length
   ||c.Mounts?.some(x=>/docker\.sock|containerd\.sock/.test(x.Source)))fail('CONTAINER_INSPECTION_REFUSED');
  if(s.environment?.POSTGRES_DB===QUALIFICATION_DB&&!partial){
   if(JSON.stringify(c.Config?.Cmd)!==JSON.stringify(s.command))fail('QUALIFICATION_COMMAND_CHANGED');
   for(const key of ['POSTGRES_DB','PGDATABASE'])if(!(c.Config?.Env??[]).includes(key+'='+QUALIFICATION_DB))fail('QUALIFICATION_DATABASE_CHANGED');
  }
  const expectedMounts=s.volumes??[],actualMounts=c.Mounts??[];
  if(actualMounts.length!==expectedMounts.length)fail('MOUNT_INSPECTION_REFUSED');
  for(const mount of actualMounts){
   const expectedMount=expectedMounts.find(v=>v.target===mount.Destination);
   if(!expectedMount||mount.Type!==expectedMount.type
    ||(mount.Type==='bind'&&(mount.Source!==expectedMount.source||mount.RW!==false))
    ||(mount.Type==='volume'&&mount.Name!==plan.volumes[expectedMount.source]?.name))fail('MOUNT_INSPECTION_REFUSED');
  }
  if(!partial&&(c.State?.Status!=='running'||c.State?.Health?.Status!=='healthy'))fail('CONTAINER_UNHEALTHY');ids.add(c.Id);
 }
 if(Object.keys(network.Containers??{}).some(x=>!ids.has(x)))fail('FOREIGN_NETWORK_CONTAINER');
 if(!partial&&volumes.length!==6)fail('VOLUME_COUNT');
 const expectedVolumes=Object.values(plan.volumes).map(x=>x.name);
 if(volumes.some(v=>!expectedVolumes.includes(v.Name)||v.Labels?.[LABEL]!==run||v.Driver!=='local'||Object.keys(v.Options??{}).length))fail('VOLUME_INSPECTION_REFUSED');return true;
}
function invoke(args,input){
 const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:4*1024*1024,timeout:240000,env:{PATH:process.env.PATH,HOME:process.env.HOME}});
 if(r.error?.code==='ENOENT')fail('DOCKER_UNAVAILABLE',r);
 if(r.error||r.status!==0)fail('DOCKER_COMMAND_FAILED',r);return r.stdout;
}
function localDocker(){
 const ctx=JSON.parse(invoke(['context','inspect']));
 if(ctx.length!==1||!/^unix:\/\/\//.test(ctx[0].Endpoints?.docker?.Host??''))fail('DOCKER_REMOTE_REFUSED');
 const info=JSON.parse(invoke(['info','--format','{{json .}}']));
 if(info.OSType!=='linux'||!['x86_64','amd64'].includes(info.Architecture))fail('DOCKER_PLATFORM_REFUSED');
}
function readRun(dir){
 const m=read(resolve(dir,'manifest.json')),file=resolve(dir,'compose.private.json'),body=readFileSync(file);
 if(sha(body)!==m.compose_sha256||(statSync(file).mode&0o077))fail('PRIVATE_PLAN_ALTERED');
 const plan=JSON.parse(body);validatePlan(plan,m.run);
 for(const [n,h]of Object.entries(m.gateway_sha256))if(sha(readFileSync(resolve(dir,n)))!==h||(statSync(resolve(dir,n)).mode&0o077))fail('GATEWAY_ALTERED');
 return {m,plan,file};
}
function inspect(plan,partial=false){
 const run=plan.name,networkNames=invoke(['network','ls','--format','{{.Name}}']).trim().split('\n');
 const networks=networkNames.includes(run+'-network')?JSON.parse(invoke(['network','inspect',run+'-network'])):[];
 const names=invoke(['ps','-a','--filter','label='+LABEL+'='+run,'--format','{{.Names}}']).trim().split('\n').filter(Boolean);
 const containers=names.length?JSON.parse(invoke(['inspect',...names])):[];
 const namesV=invoke(['volume','ls','--filter','label='+LABEL+'='+run,'--format','{{.Name}}']).trim().split('\n').filter(Boolean);
 const volumes=namesV.length?JSON.parse(invoke(['volume','inspect',...namesV])):[];
 if(networks.length===0){
  if(!partial||containers.length)fail('NETWORK_MISSING_WITH_RESIDUES');
  const allowed=Object.values(plan.volumes).map(v=>v.name);
  if(volumes.some(v=>!allowed.includes(v.Name)||v.Labels?.[LABEL]!==run||v.Driver!=='local'||Object.keys(v.Options??{}).length))fail('VOLUME_INSPECTION_REFUSED');
 }else validateInspection(plan,networks[0],containers,volumes,{partial});
 return {containers,volumes,networkPresent:networks.length===1};
}
// Native migrate.sh assigns ownership to database postgres literally. The named
// qualification DB must be inspected, never repaired on an assumed diagnosis.
export const QUALIFICATION_OWNER_CONTEXT=`
 current_database()='${QUALIFICATION_DB}' AND inet_server_addr() IS NULL
 AND current_setting('server_version_num')::integer BETWEEN 170000 AND 179999
 AND current_setting('cron.database_name')='${QUALIFICATION_DB}'
 AND current_setting('cron.launch_active_jobs')='off'
 AND current_setting('max_worker_processes')='0'
 AND NOT EXISTS(SELECT 1 FROM pg_stat_activity WHERE backend_type IN ('pg_cron launcher','pg_cron worker','pg_net worker'))
 AND NOT EXISTS(SELECT 1 FROM auth.users) AND NOT EXISTS(SELECT 1 FROM auth.sessions)
 AND NOT EXISTS(SELECT 1 FROM storage.objects) AND NOT EXISTS(SELECT 1 FROM storage.buckets)
 AND NOT EXISTS(SELECT 1 FROM cron.job) AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)
 AND NOT EXISTS(SELECT 1 FROM net._http_response) AND NOT EXISTS(SELECT 1 FROM vault.secrets)
 AND NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p'))`;
export const QUALIFICATION_OWNER_PROBE=`
BEGIN READ ONLY;
SELECT jsonb_build_object(
 'local_empty_context',(${QUALIFICATION_OWNER_CONTEXT}),
 'session_postgres',(session_user='postgres' AND current_user=session_user),
 'named_owner',(SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname=current_database()),
 'native_owner',(SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='postgres'),
 'named_create',has_database_privilege('postgres',current_database(),'CREATE'),
 'native_create',has_database_privilege('postgres','postgres','CREATE'),
 'named_connect',has_database_privilege('postgres',current_database(),'CONNECT'),
 'native_connect',has_database_privilege('postgres','postgres','CONNECT'),
 'named_temp',has_database_privilege('postgres',current_database(),'TEMP'),
 'native_temp',has_database_privilege('postgres','postgres','TEMP'),
 'postgres_superuser',(SELECT rolsuper FROM pg_roles WHERE rolname='postgres'),
 'admin_superuser',(SELECT rolsuper FROM pg_roles WHERE rolname='supabase_admin'));
ROLLBACK;`;
export const QUALIFICATION_OWNER_REPAIR=`
BEGIN;
DO $owner$
BEGIN
 IF session_user<>'supabase_admin' OR current_user<>session_user
  OR (${QUALIFICATION_OWNER_CONTEXT}) IS DISTINCT FROM true
  OR (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname=current_database()) IS DISTINCT FROM 'supabase_admin'
  OR (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='postgres') IS DISTINCT FROM 'postgres'
  OR has_database_privilege('postgres',current_database(),'CREATE') IS DISTINCT FROM false
  OR has_database_privilege('postgres','postgres','CREATE') IS DISTINCT FROM true
  OR (SELECT rolsuper FROM pg_roles WHERE rolname='postgres') IS DISTINCT FROM false
  OR (SELECT rolsuper FROM pg_roles WHERE rolname='supabase_admin') IS DISTINCT FROM true
  OR has_database_privilege('postgres',current_database(),'CONNECT') IS DISTINCT FROM true
  OR has_database_privilege('postgres','postgres','CONNECT') IS DISTINCT FROM true
  OR has_database_privilege('postgres',current_database(),'TEMP') IS DISTINCT FROM true
  OR has_database_privilege('postgres','postgres','TEMP') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'QUALIFICATION_OWNER_EXACT_MISMATCH_REQUIRED'; END IF;
END $owner$;
ALTER DATABASE jolene_candidatures_pg17_test OWNER TO postgres;
COMMIT;`;
export function ownerRepairPsqlArgs(run){
 const args=qualificationPsqlArgs(run);args[args.indexOf('-U')+1]='supabase_admin';return args;
}
export function qualificationPsqlArgs(run,{test=false}={}){
 runName(run);if(typeof test!=='boolean')fail('QUALIFICATION_MODE_INVALID');
 return ['exec','-i',...(test?['--env','PGOPTIONS=-c jolene.test_isolated=candidatures_multi_pg17']:[]),
  name(run,'source','db'),'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose',
  '-U','postgres','-h','/var/run/postgresql','-d',QUALIFICATION_DB,'-f','-'];
}
export function qualifiedSession(dir){
 const {m,plan}=readRun(dir);verifySources();localDocker();
 if(m.qualification!==true||m.database!==QUALIFICATION_DB)fail('QUALIFICATION_REQUIRED');
 const locked=new Set(read(resolve(ROOT,'images.lock.json')).images.map(x=>x.reference));
 if(Object.values(plan.services).some(s=>!locked.has(s.image)))fail('IMAGE_NOT_LOCKED');
 const initial=inspect(plan);
 // Stop Auth/REST/Storage/Kong on BOTH stacks before import; no API can run mutations.
 const clients=initial.containers.filter(c=>!SIDES.some(side=>c.Name==='/'+name(m.run,side,'db')));
 invoke(['stop','--time','10',...clients.map(c=>c.Id)]);
 const verify=()=>{
  const state=inspect(plan,true);
  if(state.containers.length!==10||state.volumes.length!==6)fail('QUALIFICATION_RUNTIME_INCOMPLETE');
  for(const c of state.containers){
   const db=SIDES.some(side=>c.Name==='/'+name(m.run,side,'db'));
   if(c.State?.Status!==(db?'running':'exited'))fail('QUALIFICATION_WORKER_STATE');
   if(db&&JSON.stringify(c.Config?.Cmd)!==JSON.stringify(plan.services[c.Name.includes('-source-')?'source-db':'target-db'].command))fail('QUALIFICATION_COMMAND_CHANGED');
  }
  return true;
 };
 verify();
 return {run:m.run,verify,
  probeDatabaseOwner:()=>JSON.parse(invoke(qualificationPsqlArgs(m.run),QUALIFICATION_OWNER_PROBE)),
  repairDatabaseOwner:()=>{verify();invoke(ownerRepairPsqlArgs(m.run),QUALIFICATION_OWNER_REPAIR);},
  sql:(bytes,options={})=>{
  try{return invoke(qualificationPsqlArgs(m.run,options),bytes);}
  catch(error){
   // Only machine codes and input line number leave process memory; never SQL, notices or credentials.
   const stderr=String(error?.detail?.stderr??''),state=stderr.match(/(?:ERROR|FATAL):\s+([0-9A-Z]{5}):/),line=stderr.match(/psql:<stdin>:(\d+):/);
   const code=stderr.match(/\b(CAND_MULTI_[A-Z_]{1,80})\b/);
   const safe=new Error('QUALIFICATION_SQL_FAILED');
   safe.diagnostic={sqlstate:state?.[1]??null,line:line?Number(line[1]):null,assertion:code?.[1]??null};
   throw safe;
  }
 }};
}
export function classifyHealthOutput(output){
 if(typeof output!=='string'||output.length===0)return {category:'no_output',http_status:null,loopback_family:'not_observed'};
 const text=output.slice(0,4096),http=text.match(/\bHTTP\/\d(?:\.\d)?[ \t]+([1-5]\d{2})\b/i);
 // A literal address elsewhere (for example a response body) does not establish the connection target.
 const ipv4=/(?:^|\n)Connecting to (?:localhost|127\.0\.0\.1):5000 \(127\.0\.0\.1:5000\)|(?:^|\n)Connecting to localhost \(localhost\)\|127\.0\.0\.1\|:5000/i.test(text);
 const ipv6=/(?:^|\n)Connecting to (?:localhost|\[::1\]):5000 \(\[::1\]:5000\)|(?:^|\n)Connecting to localhost \(localhost\)\|::1\|:5000/i.test(text);
 const category=/executable file not found|exec: .*: not found|wget: not found/i.test(text)?'executable_missing'
  :/unrecognized option|unknown option|invalid option/i.test(text)?'invalid_option'
  :/connection refused/i.test(text)?'connection_refused'
  :/bad address|name or service not known|temporary failure in name resolution|unable to resolve host/i.test(text)?'dns_failure'
  :/timed out|timeout/i.test(text)?'timeout'
  :/permission denied/i.test(text)?'permission_denied'
  :http?'http_status':'unclassified';
 return {category,http_status:http?Number(http[1]):null,loopback_family:ipv4&&ipv6?'both':ipv4?'ipv4':ipv6?'ipv6':'not_observed'};
}
export function projectContainers(plan,containers,network){
 runName(plan.name);
 const states=['created','running','paused','restarting','removing','exited','dead'],health=['starting','healthy','unhealthy'];
 const integer=(n,max)=>Number.isInteger(n)&&n>=0&&n<=max?n:null;
 const expected=Object.values(plan.services).map(s=>'/'+s.container_name);
 return {result:'CONTAINER_DIAGNOSTIC_ONLY',run:plan.name,network_present:Boolean(network),
  network_internal:network?network.Internal===true:null,network_owned:network?network.Labels?.[LABEL]===plan.name:null,
  unexpected_labelled_containers:containers.filter(c=>!expected.includes(c.Name)).length,
  services:SIDES.flatMap(side=>ROLES.map(service=>{
   const c=containers.find(c=>c.Name==='/'+name(plan.name,side,service));
   const checks=Array.isArray(c?.State?.Health?.Log)?c.State.Health.Log:[];
   return {side,service,present:Boolean(c),state:c?(states.includes(c.State?.Status)?c.State.Status:'other'):null,
    health:c?(health.includes(c.State?.Health?.Status)?c.State.Health.Status:'other'):null,
    exit_code:integer(c?.State?.ExitCode,255),oom_killed:typeof c?.State?.OOMKilled==='boolean'?c.State.OOMKilled:null,
    health_exit_code:integer(checks.at(-1)?.ExitCode,255),failing_streak:integer(c?.State?.Health?.FailingStreak,10000),
    health_output:classifyHealthOutput(checks.at(-1)?.Output)};
  }))};
}
function diagnose(plan){
 const names=invoke(['ps','-a','--filter','label='+LABEL+'='+plan.name,'--format','{{.Names}}']).trim().split('\n').filter(Boolean);
 const containers=names.length?JSON.parse(invoke(['inspect',...names])):[];
 const networks=invoke(['network','ls','--format','{{.Name}}']).trim().split('\n');
 const network=networks.includes(plan.name+'-network')?JSON.parse(invoke(['network','inspect',plan.name+'-network']))[0]:null;
 return projectContainers(plan,containers,network);
}
export function assertAbsent(run,execute=invoke){
 currentPhase='verify_absence';runName(run);
 const expectedContainers=SIDES.flatMap(s=>ROLES.map(r=>name(run,s,r)));
 const expectedVolumes=SIDES.flatMap(s=>['data','config','files'].map(r=>name(run,s,r)));
 for(const [kind,expected]of [['container',expectedContainers],['volume',expectedVolumes],['network',[run+'-network']]]){
  const listArgs=kind==='container'?['ps','-a']: [kind,'ls'];
  const all=execute([...listArgs,'--format',kind==='container'?'{{.Names}}':'{{.Name}}']).trim().split('\n');
  const owned=execute([...listArgs,'--filter','label='+LABEL+'='+run,'--format',kind==='container'?'{{.Names}}':'{{.Name}}']).trim();
  if(owned||expected.some(n=>all.includes(n)))fail('RESOURCES_REMAIN');
 }
 return {result:'EXACT_RESOURCES_ABSENT',run,containers:0,volumes:0,networks:0};
}
export function main(args){
 const [cmd,dirArg,runArg]=args,dir=resolve(dirArg??'.');currentPhase='read_plan';
 if(cmd==='plan'||cmd==='plan-qualification'){
  currentPhase='plan';const run=runName(runArg??'');verifySources();if(existsSync(dir))fail('DIRECTORY_MUST_BE_NEW');
  const lock=read(resolve(ROOT,'images.lock.json')),secrets=Object.fromEntries(SIDES.map(side=>[side,{password:randomBytes(32).toString('hex'),jwt:randomBytes(48).toString('hex')}]));
  const plan=makePlan(run,dir,lock,secrets,{qualification:cmd==='plan-qualification'});validatePlan(plan,run);mkdirSync(dir,{mode:0o700});
  const gateway_sha256={};
  for(const side of SIDES){const env=plan.services[side+'-storage'].environment,n=side+'-gateway.private.json',data=JSON.stringify(gateway(run,side,env.ANON_KEY,env.SERVICE_KEY),null,2);write(resolve(dir,n),data);gateway_sha256[n]=sha(data);}
  const body=JSON.stringify(plan,null,2);write(resolve(dir,'compose.private.json'),body);write(resolve(dir,'empty.env'),'');
  const manifest={version:1,run,qualification:cmd==='plan-qualification',database:cmd==='plan-qualification'?QUALIFICATION_DB:'postgres',compose_sha256:sha(body),gateway_sha256,network:run+'-network',containers:Object.values(plan.services).map(x=>x.container_name),volumes:Object.values(plan.volumes).map(x=>x.name),backend_urls:Object.fromEntries(SIDES.map(s=>[s,'http://'+name(run,s,'api')+':8000'])),schema_imported:false,actors_created:0,files_uploaded:0};
  write(resolve(dir,'manifest.json'),JSON.stringify(manifest,null,2));return {result:'LOCAL_PLAN_ONLY',run,containers:10,schema_imported:false};
 }
 if(cmd==='absent'){currentPhase='docker_context';localDocker();return assertAbsent(runName(dirArg??''));}
 if(!['preload','preflight','up','inspect','diagnose','extensions','down'].includes(cmd))fail('COMMAND_INVALID');
 const {m,plan,file}=readRun(dir);verifySources();currentPhase='docker_context';localDocker();
 const locked=new Set(read(resolve(ROOT,'images.lock.json')).images.map(x=>x.reference));
 if(Object.values(plan.services).some(s=>!locked.has(s.image)))fail('IMAGE_NOT_LOCKED');
 if(cmd==='diagnose'){currentPhase='diagnostic';return diagnose(plan);}
 if(cmd==='preload'){
  assertAbsent(m.run);currentPhase='preload';
  for(const image of new Set(Object.values(plan.services).map(s=>s.image)))invoke(['pull','--platform','linux/amd64',image]);
  return {result:'FIVE_PINNED_IMAGES_PRELOADED',run:m.run};
 }
 if(cmd==='preflight'||cmd==='up'){
  currentPhase='image_preflight';for(const image of new Set(Object.values(plan.services).map(x=>x.image))){
   const a=JSON.parse(invoke(['image','inspect',image]));
   if(a.length!==1||!a[0].RepoDigests?.includes(image)||a[0].Architecture!=='amd64'||a[0].Os!=='linux')fail('IMAGE_NOT_PRELOADED_EXACT');
   for(const service of Object.values(plan.services).filter(s=>s.image===image)){
    const targets=(service.volumes??[]).map(v=>v.target);
    if(Object.keys(a[0].Config?.Volumes??{}).some(t=>!targets.includes(t)))fail('IMAGE_ANONYMOUS_VOLUME_UNPLANNED');
   }
  }
  const base=['compose','--project-name',m.run,'--env-file',resolve(dir,'empty.env'),'--file',file];
  currentPhase='compose_config';invoke([...base,'config','--quiet']);if(cmd==='preflight')return {result:'DOCKER_PREFLIGHT_ONLY',run:m.run};
  currentPhase='resource_preflight';for(const [kind,names]of [['container',m.containers],['volume',m.volumes],['network',[m.network]]]){
   const list=invoke(kind==='container'?['ps','-a','--format','{{.Names}}']:[kind,'ls','--format','{{.Name}}']).trim().split('\n');
   if(names.some(x=>list.includes(x)))fail('RESOURCES_ALREADY_EXIST');
  }
  currentPhase='compose_up';invoke([...base,'up','--detach','--pull','never','--wait','--wait-timeout','180']);
 }
 currentPhase=cmd==='down'?'cleanup_inventory':'inspection';const state=inspect(plan,cmd==='down');
 if(cmd==='extensions'){
  const inventories=SIDES.map(side=>{currentPhase='extensions_'+side;const result=JSON.parse(invoke(['exec','-i',name(m.run,side,'db'),'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U','postgres','-h','/var/run/postgresql','-d',plan.services[side+'-db'].environment.POSTGRES_DB],readFileSync(resolve(HERE,'preflight-extensions.sql'),'utf8')));return {side,...projectExtensions(result)};});
  return {result:'EXTENSION_CATALOGUE_ONLY',run:m.run,inventories,extensions_changed:false,schema_imported:false};
 }
 if(cmd==='down'){
  currentPhase='cleanup_containers';for(const c of state.containers)invoke(['rm','--force',c.Id]);
  currentPhase='cleanup_volumes';for(const v of state.volumes)invoke(['volume','rm',v.Name]);
  currentPhase='cleanup_network';if(state.networkPresent)invoke(['network','rm',m.network]);
  assertAbsent(m.run);return {result:'OWNED_RESOURCES_REMOVED',run:m.run};
 }
 const api_health=[];
 for(const side of SIDES){
  currentPhase='empty_sql_'+side;invoke(['exec','-i',name(m.run,side,'db'),'psql','-X','-q','-v','ON_ERROR_STOP=1','-U','postgres','-h','/var/run/postgresql','-d',plan.services[side+'-db'].environment.POSTGRES_DB],readFileSync(resolve(HERE,'preflight-empty.sql'),'utf8'));
  const origin='http://'+name(m.run,side,'api')+':8000';
  const probe="(async()=>{const statuses=[];for(const path of ['/auth/v1/health','/rest/v1/','/storage/v1/status']){const r=await fetch("+JSON.stringify(origin)+"+path,{headers:{apikey:process.env.ANON_KEY,Authorization:'Bearer '+process.env.ANON_KEY},redirect:'error',signal:AbortSignal.timeout(5000)});statuses.push(r.status);await r.body?.cancel();if(r.status!==200)process.exit(2)}let escaped=false;try{await fetch('https://example.com',{redirect:'error',signal:AbortSignal.timeout(3000)});escaped=true}catch{}if(escaped)process.exit(3);process.stdout.write(JSON.stringify({statuses,outbound:'blocked'}))})().catch(()=>process.exit(4))";
  currentPhase='api_health_'+side;const response=JSON.parse(invoke(['exec',name(m.run,side,'storage'),'node','-e',probe]));
  if(JSON.stringify(response)!==JSON.stringify({statuses:[200,200,200],outbound:'blocked'}))fail('API_HEALTH_RESPONSE_INVALID');
  api_health.push({side,...response});
 }
 return {result:'EMPTY_CORE_ONLY',run:m.run,containers:10,api_health,schema_imported:false,actors_created:0,files_uploaded:0};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{console.log(JSON.stringify(main(process.argv.slice(2))));}catch(e){console.error(JSON.stringify(publicFailure(e)));process.exitCode=1;}
}
