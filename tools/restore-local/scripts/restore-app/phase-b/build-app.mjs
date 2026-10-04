import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, readdirSync, lstatSync, statfsSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { localRuntime } from '../local-runtime.mjs';
import { validatePlan } from '../../restore/bootstrap.mjs';
import { PRODUCT_SHA, digest, requireValue } from './contract.mjs';
import { sanitizePrivateHtml } from './private-app.mjs';
const GiB=1024**3;
export function checkFreeSpace(where,minimumGiB) { const s=statfsSync(where);const bytes=Number(s.bavail)*Number(s.bsize);requireValue(bytes>=minimumGiB*GiB,'B_DISK');return {freeBytes:bytes,minimumBytes:minimumGiB*GiB}; }
export function localBuildEnvironment(plan,side) {
 validatePlan(plan,plan.name);requireValue(['source','target'].includes(side),'B_BUILD');
 const anon=plan.services[side+'-storage'].environment.ANON_KEY;
 const claims=JSON.parse(Buffer.from(anon.split('.')[1],'base64url').toString());
 requireValue(claims.role==='anon'&&typeof anon==='string'&&anon!==plan.services[side+'-storage'].environment.SERVICE_KEY,'B_BUILD');
 const api=`http://${plan.name}-${side}-api:8000`;
 return {PATH:process.env.PATH,HOME:process.env.HOME,TMPDIR:process.env.TMPDIR??'/tmp',NODE_ENV:'production',
   VITE_SUPABASE_URL:api,VITE_SUPABASE_PUBLISHABLE_KEY:anon,VITE_SUPABASE_ANON_KEY:anon,
   VITE_SENTRY_DSN:'',SENTRY_UPLOAD_ENABLED:'false',VITE_TURNSTILE_SITE_KEY:'',VITE_NATIVE_BUILD:'false',VITE_ENV:'test',
   VERCEL_GIT_COMMIT_SHA:PRODUCT_SHA};
}
function privateRun(command,args,{cwd,env,root,name,timeout=600_000}) {
 const r=spawnSync(command,args,{cwd,env,encoding:null,maxBuffer:16*1024*1024,timeout});
 for(const key of ['stdout','stderr'])writeFileSync(join(root,name+'.'+key+'.private'),r[key]??Buffer.alloc(0),{mode:0o600,flag:'wx'});
 requireValue(!r.error&&r.signal===null&&r.status===0,'B_BUILD');
}
export function prepareDependencies(productDirectory,privateRoot) {
 checkFreeSpace(privateRoot,12);
 const version=JSON.parse(readFileSync(join(productDirectory,'package-lock.json'),'utf8')).packages['node_modules/@playwright/test'].version;
 requireValue(version==='1.58.2','B_BUILD');
 privateRun('npm',['ci','--ignore-scripts','--no-audit','--fund=false'],{cwd:productDirectory,
   env:{PATH:process.env.PATH,HOME:process.env.HOME,PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD:'1'},root:privateRoot,name:'dependencies'});
 requireValue(JSON.parse(readFileSync(join(productDirectory,'node_modules/@playwright/test/package.json'),'utf8')).version===version,'B_BUILD');
 return {dependenciesFromLock:true,browserVersionExact:true,...checkFreeSpace(privateRoot,5)};
}
function files(directory) {const out=[];const walk=(path,prefix='')=>{for(const name of readdirSync(path).sort()){
 const full=join(path,name),rel=prefix+name,info=lstatSync(full);requireValue(!info.isSymbolicLink(),'B_BUILD');
 if(info.isDirectory())walk(full,rel+'/');else{requireValue(info.isFile()&&info.nlink===1,'B_BUILD');const b=readFileSync(full);out.push({path:rel,bytes:b.length,sha256:digest(b)});}
 }};walk(directory);return out;}
export function buildApps(productDirectory,privateRoot,stackDirectory) {
 // Reuse the native plan guards; localRuntime also verifies the local Docker context.
 const plan=localRuntime(stackDirectory).plan;
 const receipts=[];
 for(const side of ['source','target']){
  const output=join(privateRoot,'build-'+side),env=localBuildEnvironment(plan,side);
  privateRun(process.execPath,[join(productDirectory,'node_modules/vite/bin/vite.js'),'build','--outDir',output,'--emptyOutDir'],
    {cwd:productDirectory,env,root:privateRoot,name:'build-'+side});
  const before=readFileSync(join(output,'index.html'),'utf8'),converted=sanitizePrivateHtml(before);
  const after=typeof converted==='string'?converted:converted.html;requireValue(typeof after==='string','B_BUILD');
  writeFileSync(join(privateRoot,'index-'+side+'.before.private.html'),before,{mode:0o600,flag:'wx'});
  writeFileSync(join(output,'index.html'),after);
  const inventory=files(output),scripts=inventory.filter(f=>f.path.endsWith('.js'));
  requireValue(scripts.length>0&&scripts.some(f=>readFileSync(join(output,f.path),'utf8').includes(env.VITE_SUPABASE_URL)),'B_BUILD');
  // The executing client URL and key are explicit. Actual browser traffic must
  // additionally prove local origins; unused product links are never followed.
  const record={productSha:PRODUCT_SHA,run:plan.name,side,apiUrl:env.VITE_SUPABASE_URL,anonRole:true,
    nativeMode:false,providerKeysAbsent:true,htmlBeforeSha256:digest(before),htmlAfterSha256:digest(after),files:inventory};
  writeFileSync(join(privateRoot,'build-'+side+'.private.json'),JSON.stringify(record),{mode:0o600,flag:'wx'});
  receipts.push({side,files:inventory.length,bytes:inventory.reduce((n,f)=>n+f.bytes,0),htmlPrivateTransformation:true});
 }
 return {productSha:PRODUCT_SHA,builds:receipts,...checkFreeSpace(privateRoot,5)};
}
export function verifyBuild(privateRoot,side,run) {
 const record=JSON.parse(readFileSync(join(privateRoot,'build-'+side+'.private.json'),'utf8'));
 requireValue(record.productSha===PRODUCT_SHA&&record.run===run&&record.side===side
  &&record.apiUrl===`http://${run}-${side}-api:8000`&&record.anonRole===true&&record.nativeMode===false
  &&JSON.stringify(files(realpathSync(join(privateRoot,'build-'+side))))===JSON.stringify(record.files),'B_BUILD');
 return true;
}
