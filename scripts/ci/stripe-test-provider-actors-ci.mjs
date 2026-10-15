/** Dedicated manual provider-only adapter. Builtins + the dedicated module only. */
import {createPrivateKey,createPublicKey,privateDecrypt,createDecipheriv,constants} from 'node:crypto';
import {readFile,lstat,realpath,mkdir,open,rename} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,PLATFORM,PURPOSE,SOURCE_FILES,Refusal,hash,recipientKey,checkVersionedContext,discoverySql,deriveActors,prepareStripeTestActors,writeEncryptedCheckpoint,requireComplete} from './stripe-test-provider-actors.mjs';
const HERE=dirname(fileURLToPath(import.meta.url)),ROOT=resolve(HERE,'../..');
const need=(ok,code)=>{if(!ok)throw new Refusal(code);};
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
export function openCompleteJournal(envelope,pem,fingerprint) {
  need(envelope?.format==='JOLENE_STRIPE_PROVIDER_ACTORS_ENCRYPTED_V1'&&envelope.cipher==='AES-256-GCM'&&envelope.keyWrap==='RSA-OAEP-SHA256'
    &&Object.keys(envelope).sort().join()==='cipher,ciphertext,format,iv,keyWrap,tag,wrappedKey','ENVELOPE');
  const key=createPrivateKey(pem),pub=createPublicKey(key);recipientKey(pub.export({type:'spki',format:'pem'}),fingerprint);
  const bytes=(x,n)=>{need(typeof x==='string'&&x.length<2*1024*1024&&/^[A-Za-z0-9+/]+={0,2}$/.test(x),'ENVELOPE');const b=Buffer.from(x,'base64');need(b.toString('base64')===x&&(!n||b.length===n),'ENVELOPE');return b;};
  const secret=privateDecrypt({key,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},bytes(envelope.wrappedKey,512));let plaintext;
  try{const d=createDecipheriv('aes-256-gcm',secret,bytes(envelope.iv,12));d.setAuthTag(bytes(envelope.tag,16));plaintext=Buffer.concat([d.update(bytes(envelope.ciphertext)),d.final()]);
    return requireComplete(JSON.parse(plaintext));}finally{secret.fill(0);plaintext?.fill(0);}
}
async function privateWrite(path,value,replace=false) {
  const target=replace?`${path}.next`:path,fd=await open(target,'wx',0o600);
  try{await fd.writeFile(JSON.stringify(value,null,2));await fd.sync();}finally{await fd.close();}
  if(replace)await rename(target,path);
}
async function privateDirectory(path) {
  need(resolve(path)===path,'PRIVATE_PATH');const stat=await lstat(path);
  need(stat.isDirectory()&&!stat.isSymbolicLink()&&(stat.mode&0o077)===0&&stat.uid===process.getuid()&&await realpath(path)===path,'PRIVATE_DIRECTORY');
}
export async function openPrivateHandoff({input,keyPath,expectedHash,fingerprint,output}) {
  need([input,keyPath,output].every(x=>typeof x==='string'&&resolve(x)===x)&&hex(expectedHash)&&hex(fingerprint),'OPEN_ARGUMENTS');
  const stat=await lstat(keyPath);need(stat.isFile()&&!stat.isSymbolicLink()&&(stat.mode&0o077)===0&&stat.uid===process.getuid()&&stat.size<=16384,'PRIVATE_KEY');
  const encryptedStat=await lstat(input);need(encryptedStat.isFile()&&!encryptedStat.isSymbolicLink()&&encryptedStat.size<=2*1024*1024,'ENVELOPE');
  const encrypted=await readFile(input);need(hash(encrypted)===expectedHash,'ENVELOPE_HASH');
  // All cryptographic, projection and receipt checks precede mkdir/handoff.
  const payload=openCompleteJournal(JSON.parse(encrypted),await readFile(keyPath),fingerprint);
  await mkdir(output,{mode:0o700});await privateDirectory(output);
  await privateWrite(join(output,'journal.private.json'),payload);
  await privateWrite(join(output,'provider-handoff.private.json'),{projectRef:PROJECT,platformId:PLATFORM,purpose:PURPOSE,mainSha:payload.mainSha,
    actors:payload.manifest.actors,authOwner:payload.manifest.authOwner,uiEvidenceSha256:payload.manifest.uiEvidenceSha256,
    customerId:payload.manifest.steps.customer.result.id,connectedAccountId:payload.manifest.steps.account.result.id,
    dbLinked:false,qualificationVerified:false,onboardingVerified:false,paymentCreated:false,refundCreated:false});
  return {opened:true,credentialsPrinted:false,providerIdsPrinted:false,dbLinked:false};
}
async function trustedLocal() {
  const git=args=>execFileSync('git',['-C',ROOT,...args],{env:{PATH:process.env.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'},encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:15000}).trim();
  return {sha:git(['rev-parse','HEAD']),clean:git(['status','--porcelain','--untracked-files=all'])==='',
    sources:Object.fromEntries(await Promise.all(SOURCE_FILES.map(async p=>[p,await readFile(join(ROOT,p),'utf8')])))};
}
export async function readOwnedActors(contract,env,fetcher) {
  need(contract.actors===null&&typeof fetcher==='function'&&typeof env.STAGING_SUPABASE_ACCESS_TOKEN==='string'&&env.STAGING_SUPABASE_ACCESS_TOKEN.length>10,'DISCOVERY_CONTEXT');
  const read=async(path,body)=>{try {
    const r=await fetcher(`https://api.supabase.com/v1/projects/${PROJECT}${path}`,{method:body?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(25000),
      headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
    need(r.ok&&!r.redirected,'DISCOVERY_READ');const text=await r.text();need(Buffer.byteLength(text)<2_000_000,'DISCOVERY_SIZE');return JSON.parse(text);
  }catch(error){if(error instanceof Refusal)throw error;throw new Refusal('DISCOVERY_READ');}};
  const project=await read('');need(project.id===PROJECT&&project.status==='ACTIVE_HEALTHY'&&project.database?.host===`db.${PROJECT}.supabase.co`,'PROJECT_IDENTITY');
  const rows=await read('/database/query',{query:discoverySql(contract),read_only:false});
  need(Array.isArray(rows)&&rows.length===1&&Object.keys(rows[0]).join()==='receipt','DISCOVERY_SHAPE');return deriveActors(rows[0].receipt,contract);
}
export async function main(argv=process.argv.slice(2),env=process.env) {
  const [mode,...args]=argv;
  if(mode==='open') {need(args.length===5,'OPEN_ARGUMENTS');const [input,keyPath,expectedHash,fingerprint,output]=args;return openPrivateHandoff({input,keyPath,expectedHash,fingerprint,output});}
  need(['check','run'].includes(mode)&&args.length===0,'ARGUMENTS');
  const contract=JSON.parse(await readFile(join(HERE,'stripe-test-provider-actors.contract.json'),'utf8'));
  need(contract.ready===true&&contract.canExecute===true,'READINESS_CLOSED');
  const local=await trustedLocal();checkVersionedContext(contract,env,local,Date.now(),mode==='run');recipientKey(env.RECIPIENT_PUBLIC_KEY,env.RECIPIENT_SHA256);
  if(mode==='check')return {contextVerified:true,remoteCalls:false};
  need(typeof env.RUNNER_TEMP==='string'&&resolve(env.RUNNER_TEMP)===env.RUNNER_TEMP&&await realpath(env.RUNNER_TEMP)===env.RUNNER_TEMP,'RUNNER_TEMP');
  const directory=join(env.RUNNER_TEMP,'stripe-provider-proof');await mkdir(directory,{mode:0o700});await privateDirectory(directory);
  const bound=await readOwnedActors(contract,env,fetch),manifest=bound.manifest;
  const summary={prepared:false,failed:false,uncertain:false,customerCreated:false,connectedAccountCreated:false,dbLinked:false,qualificationVerified:false,onboardingVerified:false,paymentCreated:false,refundCreated:false};
  let checkpointExists=false,summaryExists=false;
  const persistSummary=async()=>{await privateWrite(join(directory,'result.json'),summary,summaryExists);summaryExists=true;};
  try {
    const result=await prepareStripeTestActors({manifest,contract:bound.contract,env,local,fetcher:fetch,save:async envelope=>{
      await writeEncryptedCheckpoint(join(directory,'stripe-provider.encrypted.json'),envelope,checkpointExists);checkpointExists=true;
      summary.uncertain=Object.values(manifest.steps).some(x=>x.state==='intent');summary.customerCreated=manifest.steps.customer?.state==='done';summary.connectedAccountCreated=manifest.steps.account?.state==='done';await persistSummary();
    }});
    summary.prepared=result.prepared===true;await persistSummary();return {...summary};
  }catch(error){summary.failed=true;summary.prepared=false;try{await persistSummary();}catch{}throw error;}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().then(value=>console.log(JSON.stringify(value))).catch(error=>{
  console.error(JSON.stringify({prepared:false,code:error instanceof Refusal&&/^[A-Z0-9_]+$/.test(error.code)?error.code:'LOCAL_OR_UNEXPECTED_FAILURE'}));process.exitCode=1;
});
