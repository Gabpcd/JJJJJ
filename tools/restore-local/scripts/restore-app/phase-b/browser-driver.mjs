import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, lstatSync, readdirSync, realpathSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateInspection } from '../../restore/bootstrap.mjs';
import { IMAGE, LABEL, requireValue } from './contract.mjs';
const HERE=fileURLToPath(new URL('.',import.meta.url));
const ROLES=['db','auth','rest','storage','api'];
const BROWSER_LABEL='org.jolene.restore-browser';
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
export function browserMounts(root,side,productDirectory) {
  return [
    {source:realpathSync(HERE),target:'/restore-code',readOnly:true},
    {source:realpathSync(join(root,'build-'+side)),target:'/restore-dist',readOnly:true},
    {source:realpathSync(join(root,'browser-'+side,'input')),target:'/restore-private',readOnly:true},
    {source:realpathSync(join(root,'browser-'+side,'output')),target:'/restore-output',readOnly:false},
    {source:realpathSync(join(productDirectory,'node_modules')),target:'/node_modules',readOnly:true},
    {source:realpathSync(join(productDirectory,'scripts/ci/run-playwright-public.mjs')),target:'/restore-projector.mjs',readOnly:true},
  ];
}
export function validateBrowser(plan,side,container,network,natives,volumes,mounts,imageId,{allowStopped=false}={}) {
  const run=plan.name, name=run+'-browser';
  requireValue(['source','target'].includes(side)&&container.Name==='/'+name
    &&container.Config?.Image===IMAGE&&container.Image===imageId&&container.Config?.Labels?.[BROWSER_LABEL]===run
    &&container.Config?.Labels?.['org.jolene.restore-browser-side']===side
    &&(allowStopped||container.State?.Status==='running'),'B_BROWSER');
  const env=container.Config.Env??[];
  requireValue(['JOLENE_RESTORE_BROWSER_INPUT=/restore-private/input.json','PLAYWRIGHT_BROWSERS_PATH=/ms-playwright','HOME=/tmp','TMPDIR=/tmp','NODE_ENV=test'].every(item=>env.includes(item))
    &&env.every(item=>!/(?:SERVICE(?:_ROLE)?_KEY|SERVICE_ROLE|JWT_SECRET|POSTGRES_PASSWORD|GITHUB_TOKEN|SENTRY_AUTH_TOKEN|HTTPS?_PROXY|ALL_PROXY)=/i.test(item)), 'B_BROWSER');
  const host=container.HostConfig;
  requireValue(host?.NetworkMode===run+'-network'&&host.Privileged===false&&host.ReadonlyRootfs===true
    &&!host.PublishAllPorts&&!Object.keys(host.PortBindings??{}).length&&!Object.keys(container.Config.ExposedPorts??{}).length
    &&!(host.CapAdd?.length)&&same(host.CapDrop,['ALL'])&&host.SecurityOpt?.includes('no-new-privileges')
    &&!host.PidMode&&host.IpcMode==='private'&&!(host.ExtraHosts?.length)&&!(host.Devices?.length)
    &&!(host.DeviceRequests?.length)&&host.LogConfig?.Type==='none'
    &&same(Object.keys(container.NetworkSettings?.Networks??{}),[run+'-network']),'B_BROWSER');
  requireValue(container.Mounts?.length===mounts.length&&mounts.every(expected=>container.Mounts.some(actual=>
    actual.Type==='bind'&&actual.Source===expected.source&&actual.Destination===expected.target&&actual.RW===!expected.readOnly)),'B_BROWSER');
  requireValue(network.Internal===true&&network.Labels?.[LABEL]===run,'B_BROWSER');
  const running=side==='source'?[...ROLES.map(role=>`${run}-source-${role}`),`${run}-target-db`,name]:[...ROLES.map(role=>`${run}-target-${role}`),name];
  const names=Object.values(network.Containers??{}).map(value=>value.Name).sort();
  if(!allowStopped)requireValue(same(names,running.sort()),'B_BROWSER');
  else requireValue(names.every(value=>running.includes(value)),'B_BROWSER');
  requireValue(natives.length===10&&volumes.length===6,'B_BROWSER');
  const nativeNetwork={...network,Containers:Object.fromEntries(Object.entries(network.Containers??{}).filter(([,value])=>value.Name!==name))};
  validateInspection(plan,nativeNetwork,natives,volumes,{partial:true});
  for(const native of natives) {
    const expectedRunning=side==='source'?native.Name.startsWith('/'+run+'-source-')||native.Name==='/'+run+'-target-db':native.Name.startsWith('/'+run+'-target-');
    if(!allowStopped)requireValue(native.State?.Status===(expectedRunning?'running':'exited'),'B_BROWSER');
    const service=Object.values(plan.services).find(value=>'/'+value.container_name===native.Name);
    requireValue(service&&Object.entries(service.environment).every(([key,value])=>native.Config.Env.includes(key+'='+value))
      &&(!native.Name.endsWith('-db')||same(native.Config.Cmd,service.command)),'B_BROWSER');
  }
  return true;
}
export function boundedOutput(directory,limit=64*1024*1024) {
  let total=0,count=0;
  const walk=path=>{for(const item of readdirSync(path)){const next=join(path,item),stat=lstatSync(next);
    requireValue(!stat.isSymbolicLink(),'B_REPORT');if(stat.isDirectory())walk(next);else{
      requireValue(stat.isFile()&&stat.nlink===1&&++count<=100,'B_REPORT');total+=stat.size;requireValue(total<=limit,'B_REPORT');
    }}};
  walk(directory);return {bytes:total,files:count};
}
export function browserDriver(privateRoot,productDirectory,runtime) {
  const run=runtime.run, name=run+'-browser',callId=randomUUID();let calls=0;
  const call=(args,{input,allowFailure=false}={})=>{
    const result=spawnSync('docker',args,{input,encoding:null,maxBuffer:16*1024*1024,timeout:15*60_000,env:{PATH:process.env.PATH,HOME:process.env.HOME}});
    writeFileSync(join(privateRoot,`browser-command-${callId}-${++calls}.stderr.private`),result.stderr??Buffer.alloc(0),{mode:0o600,flag:'wx'});
    requireValue(!result.error&&result.signal===null&&(allowFailure||result.status===0),'B_CALL');return result;
  };
  const imageId=()=>JSON.parse(call(['image','inspect',IMAGE]).stdout)[0].Id;
  const inspect=(side,mounts,allowStopped=false)=>{
    const browser=JSON.parse(call(['inspect',name]).stdout)[0];
    const names=['source','target'].flatMap(s=>ROLES.map(r=>`${run}-${s}-${r}`));
    const natives=JSON.parse(call(['inspect',...names]).stdout);
    const network=JSON.parse(call(['network','inspect',run+'-network']).stdout)[0];
    const volumes=JSON.parse(call(['volume','inspect',...Object.values(runtime.plan.volumes).map(v=>v.name)]).stdout);
    validateBrowser(runtime.plan,side,browser,network,natives,volumes,mounts,imageId(),{allowStopped});return browser;
  };
  const absent=()=>{
    const names=call(['ps','-a','--filter','label='+BROWSER_LABEL+'='+run,'--format','{{.Names}}']).stdout.toString().trim();
    requireValue(names==='','B_CLEANUP');return {browserAbsent:true};
  };
  return {
    preload:()=>{call(['pull','--platform','linux/amd64',IMAGE]);return {browserImagePinned:true};},
    async run(side,writeInput) {
      requireValue(['source','target'].includes(side),'B_CONTEXT');
      await runtime.verifyState({source:side==='source'?'running':'off',target:side==='source'?'db-only':'running',browser:'absent'});absent();
      const dir=join(privateRoot,'browser-'+side);mkdirSync(dir,{mode:0o700});
      mkdirSync(join(dir,'input'),{mode:0o700});mkdirSync(join(dir,'output'),{mode:0o700});
      await writeInput(join(dir,'input','input.json'));
      const mounts=browserMounts(privateRoot,side,productDirectory);
      const args=['create','--platform','linux/amd64','--name',name,'--label',BROWSER_LABEL+'='+run,
        '--label','org.jolene.restore-browser-side='+side,'--network',run+'-network','--read-only','--log-driver','none',
        '--security-opt','no-new-privileges','--cap-drop','ALL','--ipc','private','--shm-size','512m','--memory','2g','--cpus','2','--pids-limit','512',
        '--user',`${process.getuid()}:${process.getgid()}`,'--tmpfs','/tmp:rw,nosuid,nodev,size=536870912,mode=1777','--workdir','/restore-code',
        '--env','JOLENE_RESTORE_BROWSER_INPUT=/restore-private/input.json','--env','PLAYWRIGHT_BROWSERS_PATH=/ms-playwright',
        '--env','HOME=/tmp','--env','TMPDIR=/tmp','--env','NODE_ENV=test'];
      for(const m of mounts)args.push('--mount',`type=bind,src=${m.source},dst=${m.target}${m.readOnly?',readonly':''}`);
      args.push(IMAGE,'node','/restore-code/browser-entry.mjs',side);
      let created=false;
      try {
        call(args);created=true;call(['start',name]);inspect(side,mounts);
        writeFileSync(join(dir,'output','permit.json'),JSON.stringify({run,side,approved:true}),{mode:0o600,flag:'wx'});
        const status=call(['wait',name]).stdout.toString().trim();requireValue(/^[0-9]{1,3}$/.test(status)&&Number(status)<=255,'B_BROWSER');
        inspect(side,mounts,true);boundedOutput(join(dir,'output'));
        const report=join(dir,'output','public-browser.json'),stat=lstatSync(report);
        requireValue(stat.isFile()&&!stat.isSymbolicLink()&&stat.nlink===1&&stat.size<=16*1024*1024,'B_REPORT');
        return {exitCode:Number(status),report:JSON.parse(readFileSync(report,'utf8'))};
      } finally {
        if(created){inspect(side,mounts,true);call(['rm','-f',name]);}
        absent();
        await runtime.verifyState({source:side==='source'?'running':'off',target:side==='source'?'db-only':'running',browser:'absent'});
      }
    },
    cleanup:()=>{
      const names=call(['ps','-a','--filter','label='+BROWSER_LABEL+'='+run,'--format','{{.Names}}']).stdout.toString().trim();
      if(names==='')return absent();
      requireValue(names===name,'B_CLEANUP');
      const value=JSON.parse(call(['inspect',name]).stdout)[0],side=value.Config?.Labels?.['org.jolene.restore-browser-side'];
      requireValue(['source','target'].includes(side),'B_CLEANUP');
      inspect(side,browserMounts(privateRoot,side,productDirectory),true);call(['rm','-f',name]);return absent();
    },
    absent,
  };
}
