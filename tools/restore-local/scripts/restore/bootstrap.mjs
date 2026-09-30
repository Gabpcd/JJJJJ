#!/usr/bin/env node
// Two EMPTY local stacks only. Neither schema import nor restoration is implied.
import { randomBytes, createHash, createHmac } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
export const FORBIDDEN=['flripxtsyegjshnhzjkz','mejpriaetwgtcstbgfid','wnepopwygokbhlqghydb'];
const HERE=dirname(fileURLToPath(import.meta.url)), ROOT=resolve(HERE,'../..');
const LABEL='org.jolene.restore-drill', SIDES=['source','target'], ROLES=['db','auth','rest','storage','api'];
const fail=code=>{throw new Error(code)}, sha=b=>createHash('sha256').update(b).digest('hex');
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
export function makePlan(run,dir,lock,secrets){
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
   environment:{POSTGRES_HOST:'/var/run/postgresql',PGPORT:'5432',POSTGRES_PORT:'5432',PGPASSWORD:s.password,POSTGRES_PASSWORD:s.password,PGDATABASE:'postgres',POSTGRES_DB:'postgres',JWT_EXP:'3600'},
   volumes:[{type:'volume',source:side+'-data',target:'/var/lib/postgresql/data'},{type:'volume',source:side+'-config',target:'/etc/postgresql-custom'},
    bind(resolve(ROOT,'sources/volumes/db/webhooks.sql'),'/docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql'),
    bind(resolve(ROOT,'sources/volumes/db/roles.sql'),'/docker-entrypoint-initdb.d/init-scripts/99-roles.sql'),
    bind(resolve(ROOT,'sources/volumes/db/jwt.sql'),'/docker-entrypoint-initdb.d/init-scripts/99-jwt.sql'),
    bind(resolve(HERE,'init-extensions.sql'),'/docker-entrypoint-initdb.d/init-scripts/zz-restore-extensions.sql')],
   command:['postgres','-c','config_file=/etc/postgresql/postgresql.conf','-c','log_min_messages=fatal','-c','log_statement=none'],
   healthcheck:health(['CMD','pg_isready','-U','postgres','-h','localhost'])};
  const depends_on={[side+'-db']:{condition:'service_healthy'}};
  services[side+'-auth']={...base(side,'auth','supabase/gotrue'),depends_on,
   environment:{GOTRUE_API_HOST:'0.0.0.0',GOTRUE_API_PORT:'9999',API_EXTERNAL_URL:api+'/auth/v1',
    GOTRUE_DB_DRIVER:'postgres',GOTRUE_DB_DATABASE_URL:'postgres://supabase_auth_admin:'+s.password+'@'+db+':5432/postgres',
    GOTRUE_SITE_URL:'http://'+run+'-preview:4173',GOTRUE_URI_ALLOW_LIST:'',GOTRUE_DISABLE_SIGNUP:'true',
    GOTRUE_JWT_ADMIN_ROLES:'service_role',GOTRUE_JWT_AUD:'authenticated',GOTRUE_JWT_DEFAULT_GROUP_NAME:'authenticated',GOTRUE_JWT_EXP:'3600',GOTRUE_JWT_SECRET:s.jwt,GOTRUE_JWT_ISSUER:api+'/auth/v1',
    GOTRUE_EXTERNAL_EMAIL_ENABLED:'true',GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED:'false',GOTRUE_MAILER_AUTOCONFIRM:'true',
    GOTRUE_EXTERNAL_PHONE_ENABLED:'false',GOTRUE_SMS_AUTOCONFIRM:'false',GOTRUE_SMTP_HOST:'127.0.0.1',GOTRUE_SMTP_PORT:'1',
    GOTRUE_HOOK_SEND_EMAIL_ENABLED:'false',GOTRUE_HOOK_SEND_SMS_ENABLED:'false',GOTRUE_LOG_LEVEL:'error'},
   healthcheck:health(['CMD','wget','--no-verbose','--tries=1','--spider','http://localhost:9999/health'])};
  services[side+'-rest']={...base(side,'rest','postgrest/postgrest'),depends_on,
   environment:{PGRST_DB_URI:'postgres://authenticator:'+s.password+'@'+db+':5432/postgres',PGRST_DB_SCHEMAS:'public',PGRST_DB_EXTRA_SEARCH_PATH:'public,extensions',PGRST_DB_ANON_ROLE:'anon',PGRST_JWT_SECRET:s.jwt,PGRST_DB_USE_LEGACY_GUCS:'false',PGRST_ADMIN_SERVER_PORT:'3001',PGRST_ADMIN_SERVER_HOST:'localhost',PGRST_LOG_LEVEL:'crit'},
   command:['postgrest'],healthcheck:health(['CMD','postgrest','--ready'])};
  services[side+'-storage']={...base(side,'storage','supabase/storage-api'),depends_on:{...depends_on,[side+'-rest']:{condition:'service_healthy'}},
   environment:{ANON_KEY:anon,SERVICE_KEY:service,POSTGREST_URL:'http://'+name(run,side,'rest')+':3000',AUTH_JWT_SECRET:s.jwt,
    DATABASE_URL:'postgres://supabase_storage_admin:'+s.password+'@'+db+':5432/postgres',STORAGE_PUBLIC_URL:api,REQUEST_ALLOW_X_FORWARDED_PATH:'true',FILE_SIZE_LIMIT:'1048576',STORAGE_BACKEND:'file',GLOBAL_S3_BUCKET:'stub',FILE_STORAGE_BACKEND_PATH:'/var/lib/storage',TENANT_ID:run+'-'+side,REGION:'local',ENABLE_IMAGE_TRANSFORMATION:'false',LOG_LEVEL:'error'},
   volumes:[{type:'volume',source:side+'-files',target:'/var/lib/storage'}],healthcheck:health(['CMD','wget','--no-verbose','--tries=1','--spider','http://localhost:5000/status'])};
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
 }return true;
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
 if(r.error?.code==='ENOENT')fail('DOCKER_UNAVAILABLE');
 if(r.error||r.status!==0)fail('DOCKER_COMMAND_FAILED');return r.stdout;
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
export function assertAbsent(run,execute=invoke){
 runName(run);
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
 const [cmd,dirArg,runArg]=args,dir=resolve(dirArg??'.');
 if(cmd==='plan'){
  const run=runName(runArg??'');verifySources();if(existsSync(dir))fail('DIRECTORY_MUST_BE_NEW');
  const lock=read(resolve(ROOT,'images.lock.json')),secrets=Object.fromEntries(SIDES.map(side=>[side,{password:randomBytes(32).toString('hex'),jwt:randomBytes(48).toString('hex')}]));
  const plan=makePlan(run,dir,lock,secrets);validatePlan(plan,run);mkdirSync(dir,{mode:0o700});
  const gateway_sha256={};
  for(const side of SIDES){const env=plan.services[side+'-storage'].environment,n=side+'-gateway.private.json',data=JSON.stringify(gateway(run,side,env.ANON_KEY,env.SERVICE_KEY),null,2);write(resolve(dir,n),data);gateway_sha256[n]=sha(data);}
  const body=JSON.stringify(plan,null,2);write(resolve(dir,'compose.private.json'),body);write(resolve(dir,'empty.env'),'');
  const manifest={version:1,run,compose_sha256:sha(body),gateway_sha256,network:run+'-network',containers:Object.values(plan.services).map(x=>x.container_name),volumes:Object.values(plan.volumes).map(x=>x.name),backend_urls:Object.fromEntries(SIDES.map(s=>[s,'http://'+name(run,s,'api')+':8000'])),schema_imported:false,actors_created:0,files_uploaded:0};
  write(resolve(dir,'manifest.json'),JSON.stringify(manifest,null,2));return {result:'LOCAL_PLAN_ONLY',run,containers:10,schema_imported:false};
 }
 if(cmd==='absent'){localDocker();return assertAbsent(runName(dirArg??''));}
 if(!['preload','preflight','up','inspect','down'].includes(cmd))fail('COMMAND_INVALID');
 const {m,plan,file}=readRun(dir);verifySources();localDocker();
 const locked=new Set(read(resolve(ROOT,'images.lock.json')).images.map(x=>x.reference));
 if(Object.values(plan.services).some(s=>!locked.has(s.image)))fail('IMAGE_NOT_LOCKED');
 if(cmd==='preload'){
  assertAbsent(m.run);
  for(const image of new Set(Object.values(plan.services).map(s=>s.image)))invoke(['pull','--platform','linux/amd64',image]);
  return {result:'FIVE_PINNED_IMAGES_PRELOADED',run:m.run};
 }
 if(cmd==='preflight'||cmd==='up'){
  for(const image of new Set(Object.values(plan.services).map(x=>x.image))){
   const a=JSON.parse(invoke(['image','inspect',image]));
   if(a.length!==1||!a[0].RepoDigests?.includes(image)||a[0].Architecture!=='amd64'||a[0].Os!=='linux')fail('IMAGE_NOT_PRELOADED_EXACT');
   for(const service of Object.values(plan.services).filter(s=>s.image===image)){
    const targets=(service.volumes??[]).map(v=>v.target);
    if(Object.keys(a[0].Config?.Volumes??{}).some(t=>!targets.includes(t)))fail('IMAGE_ANONYMOUS_VOLUME_UNPLANNED');
   }
  }
  const base=['compose','--project-name',m.run,'--env-file',resolve(dir,'empty.env'),'--file',file];
  invoke([...base,'config','--quiet']);if(cmd==='preflight')return {result:'DOCKER_PREFLIGHT_ONLY',run:m.run};
  for(const [kind,names]of [['container',m.containers],['volume',m.volumes],['network',[m.network]]]){
   const list=invoke(kind==='container'?['ps','-a','--format','{{.Names}}']:[kind,'ls','--format','{{.Name}}']).trim().split('\n');
   if(names.some(x=>list.includes(x)))fail('RESOURCES_ALREADY_EXIST');
  }
  invoke([...base,'up','--detach','--pull','never','--wait','--wait-timeout','180']);
 }
 const state=inspect(plan,cmd==='down');
 if(cmd==='down'){
  for(const c of state.containers)invoke(['rm','--force',c.Id]);
  for(const v of state.volumes)invoke(['volume','rm',v.Name]);
  if(state.networkPresent)invoke(['network','rm',m.network]);
  assertAbsent(m.run);return {result:'OWNED_RESOURCES_REMOVED',run:m.run};
 }
 const api_health=[];
 for(const side of SIDES){
  invoke(['exec','-i',name(m.run,side,'db'),'psql','-X','-q','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],readFileSync(resolve(HERE,'preflight-empty.sql'),'utf8'));
  const origin='http://'+name(m.run,side,'api')+':8000';
  const probe="(async()=>{const statuses=[];for(const path of ['/auth/v1/health','/rest/v1/','/storage/v1/status']){const r=await fetch("+JSON.stringify(origin)+"+path,{headers:{apikey:process.env.ANON_KEY,Authorization:'Bearer '+process.env.ANON_KEY},redirect:'error',signal:AbortSignal.timeout(5000)});statuses.push(r.status);await r.body?.cancel();if(r.status!==200)process.exit(2)}let escaped=false;try{await fetch('https://example.com',{redirect:'error',signal:AbortSignal.timeout(3000)});escaped=true}catch{}if(escaped)process.exit(3);process.stdout.write(JSON.stringify({statuses,outbound:'blocked'}))})().catch(()=>process.exit(4))";
  const response=JSON.parse(invoke(['exec',name(m.run,side,'storage'),'node','-e',probe]));
  if(JSON.stringify(response)!==JSON.stringify({statuses:[200,200,200],outbound:'blocked'}))fail('API_HEALTH_RESPONSE_INVALID');
  api_health.push({side,...response});
 }
 return {result:'EMPTY_CORE_ONLY',run:m.run,containers:10,api_health,schema_imported:false,actors_created:0,files_uploaded:0};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{console.log(JSON.stringify(main(process.argv.slice(2))));}catch(e){console.error(JSON.stringify({result:'REFUSED',code:/^[A-Z_]+$/.test(e.message)?e.message:'UNCLASSIFIED_FAILURE'}));process.exitCode=1;}
}

