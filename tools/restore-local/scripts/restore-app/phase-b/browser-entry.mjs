// Runs only in the owned isolated Playwright container; never on the host.
import { readFileSync, writeFileSync, existsSync, lstatSync, openSync, closeSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { startPrivateServer } from './private-app.mjs';
import { assertRestoreMatrix } from './matrix-contract.mjs';
import { PRODUCT_SHA, requireValue } from './contract.mjs';
// Playwright matches grep against project + file + case, not the case alone.
// A pure seam keeps the actual CLI selection covered before any browser starts.
export function browserArguments(side) {
 requireValue(['source','target'].includes(side),'B_BROWSER');
 const args=['/node_modules/@playwright/test/cli.js','test','--config=/restore-code/e2e/restore-app.config.ts','--global-timeout='+(side==='source'?'180000':'600000')];
 if(side==='source')args.push('--project=ordinateur','--grep= RESTORE_OWNER_[SE]$');
 return args;
}
async function main(side) {
 requireValue(['source','target'].includes(side)&&process.env.JOLENE_RESTORE_BROWSER_INPUT==='/restore-private/input.json','B_BROWSER');
 const input=JSON.parse(readFileSync('/restore-private/input.json','utf8'));
 requireValue(input.side===side,'B_BROWSER');
 let permit;
 for(let count=0;count<120;count++){
  if(existsSync('/restore-output/permit.json')){permit=JSON.parse(readFileSync('/restore-output/permit.json','utf8'));break;}
  await new Promise(done=>setTimeout(done,250));
 }
 requireValue(permit?.approved===true&&permit.run===input.run&&permit.side===side,'B_BROWSER');
 const server=await startPrivateServer('/restore-dist');
 let code=1;
 try {
  const args=browserArguments(side);
  const out=openSync('/restore-output/playwright.stdout.private','wx',0o600),err=openSync('/restore-output/playwright.stderr.private','wx',0o600);
  try{code=await new Promise((done,reject)=>{const child=spawn(process.execPath,args,{cwd:'/restore-code',env:process.env,stdio:['ignore',out,err]});
    child.once('error',reject);child.once('exit',(status,signal)=>signal?reject(Error('B_BROWSER')):done(status??1));});}
  finally{closeSync(out);closeSync(err);}
  const path='/restore-output/report.json',stat=lstatSync(path);
  requireValue(stat.isFile()&&!stat.isSymbolicLink()&&stat.nlink===1&&stat.size>0&&stat.size<=16*1024*1024,'B_REPORT');
  const raw=JSON.parse(readFileSync(path,'utf8'));
  const {projectReport}=await import('/restore-projector.mjs');
  const projected=await projectReport(raw,{phase:'simulation-admin',cwd:'/restore-code'});
  const tests=assertRestoreMatrix(raw,projected.tests,side);
  const expected=side==='source'?2:25;
  const pass=code===0&&projected.globalErrorCount===0&&projected.counts.expected===expected
   &&['unexpected','flaky','skipped'].every(key=>projected.counts[key]===0);
  writeFileSync('/restore-output/public-browser.json',JSON.stringify({schemaVersion:1,productSha:PRODUCT_SHA,side,
   complete:true,passed:pass,expectedCount:expected,counts:projected.counts,globalErrorCount:projected.globalErrorCount,
   tests:tests.map(value=>({caseId:value.caseId,project:value.project,outcome:value.outcome,
     attempts:value.attempts.map(attempt=>({status:attempt.status,retry:attempt.retry,code:attempt.code}))}))}),{mode:0o600,flag:'wx'});
  process.exitCode=pass?0:code||1;
 }finally{server.closeAllConnections();await new Promise(done=>server.close(done));}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 main(process.argv[2]).catch(()=>{
  if(!existsSync('/restore-output/public-browser.json'))writeFileSync('/restore-output/public-browser.json',
   JSON.stringify({schemaVersion:1,productSha:PRODUCT_SHA,complete:false,passed:false,code:'B_REPORT'}),{mode:0o600,flag:'wx'});
  process.exitCode=1;
 });
}
