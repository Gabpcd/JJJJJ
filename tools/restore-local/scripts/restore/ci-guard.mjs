#!/usr/bin/env node
import {runName,main} from './bootstrap.mjs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
export function ciIdentity(env,head){
 if(!['workflow_dispatch','pull_request'].includes(env.GITHUB_EVENT_NAME))throw Error('CI_EVENT_REFUSED');
 if(env.GITHUB_REPOSITORY!=='Gabpcd/JJJJJ')throw Error('CI_REPOSITORY_REFUSED');
 if(!/^[1-9][0-9]{0,14}$/.test(env.GITHUB_RUN_ID??'')||!/^[1-9][0-9]{0,2}$/.test(env.GITHUB_RUN_ATTEMPT??''))throw Error('CI_RUN_INVALID');
 if(!/^[a-f0-9]{40}$/.test(env.GITHUB_SHA??'')||env.GITHUB_SHA!==head)throw Error('CI_HEAD_MISMATCH');
 return {run:runName('jolene-restore-drill-'+env.GITHUB_RUN_ID+'-'+env.GITHUB_RUN_ATTEMPT),sha:head,event:env.GITHUB_EVENT_NAME};
}
export function requireExistingRefusal(dir,execute=main){
 try{execute(['up',dir]);}catch(e){if(e.message==='RESOURCES_ALREADY_EXIST')return {result:'EXISTING_START_REFUSED'};throw Error('UNEXPECTED_NEGATIVE_RESULT');}
 throw Error('SECOND_START_WAS_NOT_REFUSED');
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const head=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();const identity=ciIdentity(process.env,head);
  if(process.argv[2]==='existing-refusal')console.log(JSON.stringify({...identity,...requireExistingRefusal(process.argv[3])}));
  else if(process.argv[2]==='identity')console.log(JSON.stringify(identity));
  else throw Error('CI_COMMAND_INVALID');
 }catch(e){console.error(JSON.stringify({result:'REFUSED',code:/^[A-Z_]+$/.test(e.message)?e.message:'CI_FAILURE'}));process.exitCode=1;}
}
