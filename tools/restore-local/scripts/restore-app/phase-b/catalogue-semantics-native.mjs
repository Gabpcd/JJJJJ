import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { runName } from '../../restore/bootstrap.mjs';
import { buildB21NativeWitnessSql,decodeB21Witness,validateB21NativeWitnesses,b21WitnessFailure } from './catalogue-semantics-witness.mjs';

export const B21_IMAGE='supabase/postgres@sha256:432d12926b09e10eb3317b0e2e9672c9ce8ea6bccb359857a31ff9f90683161d';
export const B21_LABEL='org.jolene.restore-b21';
export const B21_DATABASE='jolene_b21_semantics_test';
// Bypass the vendor entrypoint: a fresh initdb, no Supabase bootstrap roles,
// shared volumes, configuration, APIs or provider credentials enter this cluster.
export const B21_START_SCRIPT="umask 077\ninitdb -D /tmp/b21-data -U postgres --encoding=UTF8 --locale=C --auth-local=trust --auth-host=reject --no-instructions >/dev/null\nexec postgres -D /tmp/b21-data -c listen_addresses= -c unix_socket_directories=/var/run/postgresql -c shared_preload_libraries= -c cron.database_name="+B21_DATABASE+" -c cron.launch_active_jobs=off -c max_worker_processes=0 -c autovacuum=off -c logging_collector=off -c log_statement=none -c log_min_messages=fatal -c log_min_error_statement=panic";
const invariant=(ok,reason)=>{if(!ok)throw b21WitnessFailure(reason);};
const decode=(bytes,reason)=>{try{return JSON.parse(bytes.toString('utf8'));}catch{throw b21WitnessFailure(reason);}};
function executor(){
 const call=(args,input,reason='CONTEXT')=>{
  const r=spawnSync('docker',args,{input,encoding:null,maxBuffer:12*1024*1024,timeout:90_000,env:{PATH:process.env.PATH,HOME:process.env.HOME}});
  invariant(!r.error&&r.status===0&&r.signal===null,reason);return r.stdout;
 };
 const contexts=decode(call(['context','inspect']),'CONTEXT');
 invariant(Array.isArray(contexts)&&contexts.length===1&&/^unix:\/\/\//.test(contexts[0].Endpoints?.docker?.Host??''),'CONTEXT');
 return call;
}
const named=(run)=>runName(run)+'-b21-semantics';
function resources(call,run){
 const byLabel=call(['ps','-a','--filter',`label=${B21_LABEL}=${run}`,'--format','{{.Names}}']).toString().trim().split('\n').filter(Boolean);
 const byName=call(['ps','-a','--filter',`name=^/${named(run)}$`,'--format','{{.Names}}']).toString().trim().split('\n').filter(Boolean);
 invariant(byLabel.every(n=>n===named(run))&&byLabel.length<=1&&JSON.stringify(byLabel)===JSON.stringify(byName),'ISOLATION');
 return byLabel;
}
export function validateB21NativeContainer(c,run){
 invariant(c?.Name==='/'+named(run)&&c.Config?.Labels?.[B21_LABEL]===run&&c.Config?.Image===B21_IMAGE
  &&c.Config?.User==='postgres'&&JSON.stringify(c.Config?.Entrypoint)===JSON.stringify(['sh'])
  &&JSON.stringify(c.Config?.Cmd)===JSON.stringify(['-ceu',B21_START_SCRIPT])
  &&Object.keys(c.Config?.Volumes??{}).length===0
  &&c.HostConfig?.NetworkMode==='none'&&c.HostConfig?.ReadonlyRootfs===true&&c.HostConfig?.Privileged===false
  &&c.HostConfig?.LogConfig?.Type==='none'&&Object.keys(c.HostConfig?.PortBindings??{}).length===0
  &&Object.keys(c.NetworkSettings?.Ports??{}).every(p=>c.NetworkSettings.Ports[p]===null)
  &&Object.keys(c.NetworkSettings?.Networks??{}).every(n=>n==='none')
  &&!(c.HostConfig?.Binds?.length)&&!(c.HostConfig?.CapAdd?.length)
  &&JSON.stringify(c.HostConfig?.CapDrop)===JSON.stringify(['ALL'])
  &&c.HostConfig?.SecurityOpt?.includes('no-new-privileges')
  &&c.HostConfig?.Memory===768*1024*1024&&c.HostConfig?.PidsLimit===128&&c.HostConfig?.NanoCpus===1_000_000_000&&c.HostConfig?.ShmSize===64*1024*1024
  &&Object.keys(c.HostConfig?.Tmpfs??{}).length===2
  &&c.HostConfig.Tmpfs['/tmp']==='rw,noexec,nosuid,size=256m,mode=1777'
  &&c.HostConfig.Tmpfs['/var/run/postgresql']==='rw,noexec,nosuid,size=16m,mode=1777'
  &&Array.isArray(c.Mounts)&&c.Mounts.every(m=>m.Type==='tmpfs'&&['/tmp','/var/run/postgresql'].includes(m.Destination)), 'ISOLATION');
 return true;
}
function inspect(call,run){const rows=decode(call(['inspect',named(run)],undefined,'ISOLATION'),'ISOLATION');invariant(Array.isArray(rows)&&rows.length===1,'ISOLATION');validateB21NativeContainer(rows[0],run);return rows[0];}
function clean(call,run){if(resources(call,run).length){inspect(call,run);call(['rm','--force',named(run)],undefined,'CLEANUP');}invariant(resources(call,run).length===0,'CLEANUP');}
export function cleanupB21NativeWitnesses(run){const call=executor();clean(call,run);return {b21WitnessAbsent:true};}
export function assertB21NativeWitnessAbsent(run){const call=executor();invariant(resources(call,run).length===0,'CLEANUP');return {b21WitnessAbsent:true};}
export async function runB21NativeWitnesses(run){
 const call=executor();runName(run);
 const images=JSON.parse(readFileSync(new URL('../../../images.lock.json',import.meta.url),'utf8'));
 invariant(images.images.some(i=>i.repository==='supabase/postgres'&&i.reference===B21_IMAGE&&i.tag==='17.6.1.063'),'CONTEXT');
 // Refuse image-declared anonymous volumes before Docker can create any.
 // The Dockerfile alone is not evidence for the metadata of the pinned image.
 const image=decode(call(['image','inspect',B21_IMAGE],undefined,'ISOLATION'),'ISOLATION');
 invariant(Array.isArray(image)&&image.length===1&&image[0].RepoDigests?.includes(B21_IMAGE)
  &&image[0].Os==='linux'&&image[0].Architecture==='amd64'&&image[0].Config
  &&Object.keys(image[0].Config.Volumes??{}).length===0,'ISOLATION');
 invariant(resources(call,run).length===0,'EXISTING_RESOURCE');
 for(const label of ['org.jolene.restore-drill','org.jolene.restore-browser'])invariant(call(['ps','-a','--filter',`label=${label}=${run}`,'--format','{{.Names}}']).toString().trim()==='','EXISTING_RESOURCE');
 let createAttempted=false,receipt;
 try{
  createAttempted=true;
  call(['create','--name',named(run),'--label',`${B21_LABEL}=${run}`,'--platform','linux/amd64','--pull','never',
   '--network','none','--log-driver','none','--user','postgres','--entrypoint','sh','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges',
   '--memory','768m','--pids-limit','128','--cpus','1','--shm-size','64m','--no-healthcheck',
   '--tmpfs','/tmp:rw,noexec,nosuid,size=256m,mode=1777','--tmpfs','/var/run/postgresql:rw,noexec,nosuid,size=16m,mode=1777',
   B21_IMAGE,'-ceu',B21_START_SCRIPT],undefined,'STARTUP');inspect(call,run);
  call(['start',named(run)],undefined,'STARTUP');
  let ready=false;
  for(let attempt=0;attempt<45;attempt++){
   const c=inspect(call,run);invariant(c.State?.Status==='running'&&c.State?.OOMKilled!==true,'STARTUP');
   const r=spawnSync('docker',['exec',named(run),'pg_isready','-q','-U','postgres','-h','/var/run/postgresql'],{encoding:null,maxBuffer:1024,timeout:5000,env:{PATH:process.env.PATH,HOME:process.env.HOME}});
   invariant(!r.error&&r.signal===null&&[0,1,2].includes(r.status),'STARTUP');if(r.status===0){ready=true;break;}
   if(attempt<44)await new Promise(resolve=>setTimeout(resolve,1000));
  }
  invariant(ready,'STARTUP');
  const sql=(body,database=B21_DATABASE)=>{inspect(call,run);return call(['exec','-i',named(run),'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1',
   '-U','postgres','-h','/var/run/postgresql','-d',database,'-f','-'],Buffer.from(body),'SQL');};
  sql(`CREATE DATABASE ${B21_DATABASE} OWNER postgres TEMPLATE template0;`,'postgres');
  const outputs=[];
  for(const kind of ['acl','expression']){
   const original=readFileSync(new URL(`./catalogue-semantics-${kind}-witness.sql`,import.meta.url),'utf8');
   outputs.push(decodeB21Witness(sql(buildB21NativeWitnessSql(kind,original))));
   const rolled=decode(sql("SELECT jsonb_build_object('clean',NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname IN('b21_fixture','b21_expr')) AND NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('b21_owner','b21_reader','b21_delegate','b21_member','b21_other_owner')));"),'ROLLBACK');
   invariant(rolled?.clean===true&&Object.keys(rolled).length===1,'ROLLBACK');
  }
  receipt=validateB21NativeWitnesses(...outputs);
 }finally{if(createAttempted)clean(call,run);}
 invariant(resources(call,run).length===0,'CLEANUP');return receipt;
}
