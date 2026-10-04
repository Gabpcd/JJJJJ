#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, existsSync, lstatSync, realpathSync, renameSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { source, recoverySource, ROOT } from './identity.mjs';
import { IMAGE, assertReview, requireValue, closedFailure } from './contract.mjs';
import { closedFailure as phaseAFailure } from '../projection.mjs';
import { FAILURE_CODES } from '../failure.mjs';
import { parseTap } from '../phase-a.mjs';
import { preparePlan } from '../local-runtime.mjs';
import { nativeRuntime } from './native-runtime.mjs';
import { browserDriver } from './browser-driver.mjs';
import { buildApps, prepareDependencies, checkFreeSpace } from './build-app.mjs';
import { runPhaseB } from './core.mjs';
import { main as bootstrap } from '../../restore/bootstrap.mjs';
import { compareInventories } from '../../restore/extensions.mjs';
import { requireExistingRefusal } from '../../restore/ci-guard.mjs';
const PUBLIC=new Set(['identity.json','units.json','dependencies.json','build.json','bootstrap-proof.json','phase-a-capture.json',
 'browser-source.json','browser-target.json','target-objects.json','controlled-negative.json','phase-b.json','diagnostic.json','cleanup.json','cleanup-again.json','absence.json']);
let stage='identity',paths,evidence;
function directory(path){if(!existsSync(path))mkdirSync(path,{mode:0o700});requireValue(lstatSync(path).isDirectory()&&!lstatSync(path).isSymbolicLink()
 &&realpathSync(path)===path&&(lstatSync(path).mode&0o077)===0,'B_CONTEXT');}
function save(name,value){requireValue(PUBLIC.has(name),'B_CONTEXT');const file=join(paths.proof,name);
 if(existsSync(file))requireValue(lstatSync(file).isFile()&&!lstatSync(file).isSymbolicLink()&&lstatSync(file).nlink===1,'B_CONTEXT');
 writeFileSync(file+'.writing',JSON.stringify(value,null,2)+'\n',{mode:0o600,flag:'wx'});renameSync(file+'.writing',file);
}
function localProcess(command,args,name,timeout=600_000){const r=spawnSync(command,args,{cwd:ROOT,encoding:null,maxBuffer:16*1024*1024,timeout,env:{PATH:process.env.PATH,HOME:process.env.HOME}});
 for(const key of ['stdout','stderr'])writeFileSync(join(paths.private,name+'.'+key+'.private'),r[key]??Buffer.alloc(0),{mode:0o600,flag:'wx'});
 requireValue(!r.error&&r.signal===null&&r.status===0,'B_CALL');return r.stdout;
}
// Host-only bridge: preserve the exact A V9 closed diagnostics without importing
// native modules into the isolated browser's self-contained contract.
export function runtimeFailure(error,stage) {
 const result=closedFailure(error,stage);
 return FAILURE_CODES.has(error?.publicCode)?{...result,phaseA:phaseAFailure(error,stage)}:result;
}
export async function main(args,env=process.env){
 requireValue(args.length===1&&['identity','units','plan','dependencies','build','bootstrap','native','diagnose','cleanup','absence'].includes(args[0]),'B_CONTEXT');
 const command=args[0],recovery=['diagnose','cleanup','absence'].includes(command);
 evidence=recovery?recoverySource(env):source(env);evidence.productDirectory=ROOT;
 directory(evidence.privateRoot);directory(evidence.proofRoot);paths={private:evidence.privateRoot,proof:evidence.proofRoot,stack:join(evidence.privateRoot,'stack')};
 const review=JSON.parse(readFileSync(new URL('./review.json',import.meta.url),'utf8'));
 if(!recovery)assertReview(review); // Missing A review refuses before resource preparation or downloads.
 if(command==='identity'){const result={result:'PHASE_B_IDENTITY_PASSED',productSha:evidence.productSha,harnessSha:evidence.harnessSha,migrationCount:219,
   phaseAReviewed:true,reviewedPhaseARun:review.phaseARunId,readyForNationalLaunch:false};save('identity.json',result);return result;}
 if(command==='units'){
  stage='units';const tests=evidence.pins.nodeTests;
  requireValue(tests.length>=7&&tests.every(path=>evidence.pins.pinnedFiles.some(file=>file.path===path)),'B_PIN');
  const tap=localProcess(process.execPath,['--test','--test-reporter=tap',...tests],'units',120_000);
  const result=parseTap(tap.toString(),0);save('units.json',result);return result;
 }
 if(command==='plan'){stage='plan';checkFreeSpace(paths.private,12);return preparePlan(paths.stack,evidence.run);}
 if(command==='dependencies'){stage='dependencies';const result=prepareDependencies(ROOT,paths.private);save('dependencies.json',result);return result;}
 if(command==='build'){stage='build';const result=buildApps(ROOT,paths.stack,paths.stack);save('build.json',result);return result;}
 if(command==='bootstrap'){
  const passed=[];for(const operation of ['preload','preflight','up','inspect']){
   stage=operation;bootstrap([operation,paths.stack]);passed.push(operation);
   if(operation==='preload'){localProcess('docker',['pull','--platform','linux/amd64',IMAGE],'browser-image');checkFreeSpace(paths.private,5);}
   save('bootstrap-proof.json',{result:'NATIVE_BOOTSTRAP_IN_PROGRESS',passed,appVerified:false});
  }
  requireValue(requireExistingRefusal(paths.stack).result==='EXISTING_START_REFUSED','B_CONTEXT');stage='extensions';
  const inventory=bootstrap(['extensions',paths.stack]);
  const requirements=JSON.parse(readFileSync(new URL('../../export/scope.json',import.meta.url))).extensions;
  requireValue(compareInventories(requirements,inventory,evidence.run).declarations_compatible===true,'B_CONTEXT');
  const result={result:'NATIVE_BOOTSTRAP_PASSED',passed,repeatedStartRefused:true,extensionsExact:true,containers:10,volumes:6,networkInternal:true,publishedPorts:0};save('bootstrap-proof.json',result);return result;
 }
 if(command==='native')return runPhaseB(evidence,paths,review,(name,value)=>{if(value.stage)stage=value.stage;save(name,value);});
 if(command==='diagnose'){
  if(!existsSync(join(paths.stack,'manifest.json')))return {result:'NO_PLAN'};
  // Browser may be present on interruption: cleanup it with its separate fixed contract before native inspection.
  const browser=browserDriver(paths.stack,ROOT,nativeRuntime(paths.stack));browser.cleanup();
  const result=bootstrap(['diagnose',paths.stack]);save('diagnostic.json',result);return result;
 }
 if(command==='cleanup'){
  stage='cleanup';const planned=existsSync(join(paths.stack,'manifest.json'));
  if(planned)browserDriver(paths.stack,ROOT,nativeRuntime(paths.stack)).cleanup();
  const first=planned?bootstrap(['down',paths.stack]):bootstrap(['absent',evidence.run]);save('cleanup.json',first);
  const second=planned?bootstrap(['down',paths.stack]):bootstrap(['absent',evidence.run]);save('cleanup-again.json',second);return second;
 }
 stage='absence';
 const result=bootstrap(['absent',evidence.run]);
 const names=localProcess('docker',['ps','-a','--filter','label=org.jolene.restore-browser='+evidence.run,'--format','{{.Names}}'],'browser-absence');
 requireValue(names.toString().trim()==='','B_CLEANUP');const final={...result,browserAbsent:true};save('absence.json',final);return final;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 main(process.argv.slice(2)).then(result=>process.stdout.write(JSON.stringify({result:result.result??'PHASE_B_STEP_PASSED'})+'\n')).catch(error=>{
  const result=runtimeFailure(error,stage);if(paths)try{save(['cleanup','absence'].includes(stage)?stage+'.json':'phase-b.json',result);}catch{}
  process.stdout.write(JSON.stringify(result)+'\n');process.exitCode=1;
 });
}
