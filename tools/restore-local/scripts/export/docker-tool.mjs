#!/usr/bin/env node
import {readFileSync,realpathSync} from 'node:fs';import {resolve} from 'node:path';import {fileURLToPath} from 'node:url';import {spawnSync} from 'node:child_process';
import {IMAGE} from './ci-export.mjs';import {connectionEnv,dumpArgs} from './export-schema.mjs';
const fail=()=>{throw Error('DOCKER_CLIENT_REFUSED')};
export function clientArgs(c,tool,args,env,pid=process.pid){
 if(c?.image!==IMAGE||!/^jolene-ddl-[1-9][0-9]{0,14}-[1-9][0-9]{0,2}$/.test(c.run??'')||!Number.isInteger(c.uid)||c.uid<1||!Number.isInteger(c.gid)||c.gid<1||!['psql','pg_dump','pg_restore'].includes(tool))fail();
 if(!c.root?.startsWith('/')||!c.source?.startsWith('/')||/[\n,]/.test(c.root+c.source)||!c.root.endsWith('/'+c.run))fail();
 const archive=resolve(c.root,'export/schema.private.dump'),isVersion=args.length===1&&args[0]==='--version';
 let allowed=isVersion;
 if(tool==='psql')allowed ||= JSON.stringify(args)===JSON.stringify(['--no-psqlrc','--no-password','--tuples-only','--no-align','--set=ON_ERROR_STOP=1','--file',resolve(c.source,'catalogue-export.sql')]);
 if(tool==='pg_dump')allowed ||= JSON.stringify(args)===JSON.stringify(dumpArgs(resolve(c.root,'export')));
 if(tool==='pg_restore'){
  const forms=[['--list',archive]];
  for(const [file,sel]of [['all.private.sql',[]],['application.private.sql',['--schema=public','--schema=private']],['customizations.private.sql',['--use-list',resolve(c.root,'export/custom.list.private.txt')]],['managed-acl-review.private.sql',['--use-list',resolve(c.root,'export/acl.list.private.txt')]]])forms.push(['--schema-only',...sel,'--file',resolve(c.root,'export',file),archive]);
  allowed ||= forms.some(x=>JSON.stringify(x)===JSON.stringify(args));
 }
 if(!allowed)fail();const remote=!isVersion&&['psql','pg_dump'].includes(tool);
 const base=['run','--rm','--pull','never','--platform','linux/amd64','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true','--log-driver','none','--pids-limit','128','--memory','512m','--cpus','1','--user',c.uid+':'+c.gid,'--name',c.run+'-'+tool+'-'+pid,'--label','org.jolene.restore-export='+c.run,'--network',remote?'bridge':'none','--tmpfs','/tmp:rw,noexec,nosuid,size=64m','--mount','type=bind,src='+c.root+',dst='+c.root,'--mount','type=bind,src='+c.source+',dst='+c.source+',readonly'];
 let child={PATH:env.PATH};if(remote){child={...connectionEnv({...env,RESTORE_SCHEMA_SOURCE_REF:'flripxtsyegjshnhzjkz'})};for(const k of Object.keys(child).filter(x=>x.startsWith('PG')))base.push('--env',k);}
 return {args:[...base,'--entrypoint',tool,IMAGE,...args],env:child};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))try{
 const c=JSON.parse(readFileSync(process.argv[2]));if(realpathSync(c.root)!==c.root||realpathSync(c.source)!==c.source)fail();const p=clientArgs(c,process.argv[3],process.argv.slice(4),process.env);
 const r=spawnSync('docker',p.args,{env:p.env,encoding:'utf8',timeout:170000,maxBuffer:32*1024*1024});if(r.error||r.status!==0||r.stderr?.trim())fail();process.stdout.write(r.stdout);
}catch{process.stderr.write('DOCKER_CLIENT_REFUSED\n');process.exitCode=1}
