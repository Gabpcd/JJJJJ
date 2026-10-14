/** Main-only CI adapter. Provider credentials never enter a saved object. */
import { createHash, createPublicKey, createPrivateKey, publicEncrypt, privateDecrypt, randomBytes, createCipheriv, createDecipheriv, constants } from 'node:crypto';
import { readFile, lstat, mkdir, realpath } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { newManifest, validateManifest, checkContract, executePreparation, privateWrite, Refusal as FixtureRefusal, PROJECT } from './connect-test-fixture.mjs';
import {
  AUTH_ONLY_PURPOSE,newAuthOnlyManifest,validateAuthOnlyManifest,checkAuthOnlyContract,executeAuthOnlyPreparation,
  projectAuthHooks,authOnlyCatalogueSql,authOnlyReadOnlySql,requireAuthOnlyComplete } from './auth-test-frontend.mjs';

const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../..'), REPO='Gabpcd/JJJJJ';
export const SOURCE_FILES=['scripts/ci/connect-test-fixture.mjs','scripts/ci/connect-test-fixture-sql.mjs','scripts/ci/connect-test-fixture-prepare.sql'];
const WORKFLOW='.github/workflows/connect-test-fixture.yml', FORMAT='JOLENE_CONNECT_FIXTURE_ENCRYPTED_V1';
const canonicalAuth=v=>Array.isArray(v)?v.map(canonicalAuth):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonicalAuth(v[k])])):v;
const sha=x=>createHash('sha256').update(x).digest('hex'), hex=(x,n)=>typeof x==='string'&&new RegExp(`^[a-f0-9]{${n}}$`).test(x)&&!/^0+$/.test(x);
const positive=x=>typeof x==='string'&&/^[1-9][0-9]{0,19}$/.test(x);
class Refusal extends Error { constructor(code){super(code);this.code=code;} }
const requireThat=(ok,code)=>{if(!ok)throw new Refusal(code);};
export function recipientKey(pem,fingerprint) {
  requireThat(typeof pem==='string'&&pem.startsWith('-----BEGIN PUBLIC KEY-----')&&!pem.includes('PRIVATE')&&hex(fingerprint,64),'CI_RECIPIENT');
  let key;try{key=createPublicKey(pem);}catch{throw new Refusal('CI_RECIPIENT');}
  requireThat(key.asymmetricKeyType==='rsa'&&key.asymmetricKeyDetails.modulusLength===4096&&sha(key.export({type:'spki',format:'der'}))===fingerprint,'CI_RECIPIENT');return key;
}
export function sealJournal(payload,key) {
  const plaintext=Buffer.from(JSON.stringify(payload));requireThat(plaintext.length<=1024*1024,'CI_PAYLOAD_SIZE');
  const secret=randomBytes(32),iv=randomBytes(12);
  try {const cipher=createCipheriv('aes-256-gcm',secret,iv),ciphertext=Buffer.concat([cipher.update(plaintext),cipher.final()]);
    return {format:FORMAT,cipher:'AES-256-GCM',keyWrap:'RSA-OAEP-SHA256',wrappedKey:publicEncrypt({key,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},secret).toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),ciphertext:ciphertext.toString('base64')};
  } finally {secret.fill(0);plaintext.fill(0);}
}
function decryptEnvelope(envelope,pem,fingerprint) {
  requireThat(envelope?.format===FORMAT&&envelope.cipher==='AES-256-GCM'&&envelope.keyWrap==='RSA-OAEP-SHA256'
    &&Object.keys(envelope).sort().join() === 'cipher,ciphertext,format,iv,keyWrap,tag,wrappedKey','CI_ENVELOPE');
  const privateKey=createPrivateKey(pem),publicKey=createPublicKey(privateKey);
  recipientKey(publicKey.export({type:'spki',format:'pem'}),fingerprint);
  const bytes=(v,n)=>{requireThat(typeof v==='string'&&v.length<2*1024*1024&&/^[A-Za-z0-9+/]+={0,2}$/.test(v),'CI_ENVELOPE');const b=Buffer.from(v,'base64');requireThat(b.toString('base64')===v&&(!n||b.length===n),'CI_ENVELOPE');return b;};
  const secret=privateDecrypt({key:privateKey,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},bytes(envelope.wrappedKey,512));
  try {const decipher=createDecipheriv('aes-256-gcm',secret,bytes(envelope.iv,12));decipher.setAuthTag(bytes(envelope.tag,16));
    const payload=JSON.parse(Buffer.concat([decipher.update(bytes(envelope.ciphertext)),decipher.final()]));
    return payload;
  }finally{secret.fill(0);}
}
export function openJournal(envelope,pem,fingerprint) {
  const payload=decryptEnvelope(envelope,pem,fingerprint);
  requireThat(payload?.format==='JOLENE_CONNECT_FIXTURE_PRIVATE_V1'&&payload.projectRef===PROJECT,'CI_PAYLOAD');validateManifest(payload.manifest);return payload;
}
export function openAuthOnlyJournal(envelope,pem,fingerprint) {
  const payload=decryptEnvelope(envelope,pem,fingerprint);
  requireThat(payload?.format==='JOLENE_AUTH_ONLY_PRIVATE_V1'&&payload.projectRef===PROJECT&&payload.purpose===AUTH_ONLY_PURPOSE,'AUTH_ONLY_PAYLOAD');
  validateAuthOnlyManifest(payload.manifest);
  requireThat(payload.mainSha===payload.manifest.sourceSha,'AUTH_ONLY_PAYLOAD');return payload;
}
export function checkCi(env,local,contract,sources,now=Date.now()) {
  requireThat(contract?.ready===true,'CI_READINESS_CLOSED');
  requireThat(env.GITHUB_ACTIONS==='true'&&env.GITHUB_EVENT_NAME==='workflow_dispatch'&&env.GITHUB_REPOSITORY===REPO&&env.GITHUB_REF==='refs/heads/main'
    &&hex(env.EXPECTED_MAIN_SHA,40)&&env.GITHUB_SHA===env.EXPECTED_MAIN_SHA&&local?.sha===env.GITHUB_SHA&&local.clean===true
    &&positive(env.GITHUB_RUN_ID)&&env.GITHUB_RUN_ATTEMPT==='1','CI_TRUSTED_MAIN');
  requireThat(contract.schemaVersion===1&&contract.projectRef===PROJECT&&hex(contract.reviewedFixtureSha,40)&&hex(contract.reviewedFixtureTree,40)
    &&typeof contract.reviewedBy==='string'&&contract.reviewedBy.trim().length>=3
    &&Date.parse(contract.expiresAt)>now&&Date.parse(contract.expiresAt)-now<=4*3600000,'CI_CONTRACT');
  requireThat(Object.keys(contract.sourcePins??{}).sort().join() === [...SOURCE_FILES].sort().join()
    &&SOURCE_FILES.every(p=>hex(contract.sourcePins[p],64)&&typeof sources[p]==='string'&&sha(sources[p])===contract.sourcePins[p]),'CI_SOURCE_PINS');
  const p=contract.pgProof;
  requireThat(positive(p?.runId)&&Number.isSafeInteger(p.runAttempt)&&p.runAttempt>0&&typeof p.jobName==='string'&&p.jobName.length>5
    &&/^\.github\/workflows\/[a-z0-9-]+\.yml$/.test(p.workflowPath??'')&&p.fixtureSqlReviewed===true,'CI_PG_PROOF');
  const m=newManifest(`connect-test-ci-${env.GITHUB_RUN_ID}-1`,local.sha);
  const c={...contract.fixtureContract,sourceSha:local.sha,expiresAt:contract.expiresAt,reviewedBy:contract.reviewedBy};
  checkContract(c,m,sources[SOURCE_FILES[2]],now);
  return {manifest:m,fixtureContract:c,key:recipientKey(env.RECIPIENT_PUBLIC_KEY,env.RECIPIENT_SHA256)};
}
export async function verifyProvenance(env,contract,sources,fetcher=fetch) {
  const read=async path=>{let response;try{response=await fetcher(`https://api.github.com/repos/${REPO}${path}`,{headers:{Accept:'application/vnd.github+json',Authorization:`Bearer ${env.GITHUB_TOKEN}`},redirect:'error',signal:AbortSignal.timeout(15000)});}catch{throw new Refusal('CI_GITHUB_READ');}
    requireThat(response.ok&&!response.redirected,'CI_GITHUB_READ');let value;try{const text=await response.text();requireThat(Buffer.byteLength(text)<2*1024*1024,'CI_GITHUB_SIZE');value=JSON.parse(text);}catch{throw new Refusal('CI_GITHUB_SHAPE');}return value;};
  requireThat(typeof env.GITHUB_TOKEN==='string'&&env.GITHUB_TOKEN.length>10,'CI_GITHUB_TOKEN');
  const p=contract.pgProof;
  const [main,commit,run,jobs,runs]=await Promise.all([
    read('/git/ref/heads/main'),read(`/git/commits/${contract.reviewedFixtureSha}`),read(`/actions/runs/${p.runId}`),
    read(`/actions/runs/${p.runId}/attempts/${p.runAttempt}/jobs?per_page=100`),
    read(`/actions/workflows/connect-test-fixture.yml/runs?event=workflow_dispatch&head_sha=${env.GITHUB_SHA}&per_page=100`),
  ]);
  requireThat(main.ref==='refs/heads/main'&&main.object?.sha===env.GITHUB_SHA&&main.object.type==='commit','CI_MAIN_MOVED');
  requireThat(commit.sha===contract.reviewedFixtureSha&&commit.tree?.sha===contract.reviewedFixtureTree,'CI_REVIEWED_SOURCE');
  requireThat(String(run.id)===p.runId&&run.run_attempt===p.runAttempt&&run.head_sha===contract.reviewedFixtureSha&&run.path===p.workflowPath
    &&run.repository?.full_name===REPO&&run.head_repository?.full_name===REPO&&run.status==='completed'&&run.conclusion==='success','CI_SQL_RUN');
  const selected=jobs.jobs?.filter(x=>x.name===p.jobName);
  requireThat(Array.isArray(jobs.jobs)&&jobs.total_count===jobs.jobs.length&&selected?.length===1&&selected[0].status==='completed'&&selected[0].conclusion==='success','CI_SQL_JOB');
  requireThat(Array.isArray(runs.workflow_runs)&&runs.total_count===1&&runs.workflow_runs.length===1&&String(runs.workflow_runs[0].id)===env.GITHUB_RUN_ID
    &&runs.workflow_runs[0].path===WORKFLOW,'CI_PREVIOUS_DISPATCH');
  const files=await Promise.all(SOURCE_FILES.map(path=>read(`/contents/${path}?ref=${contract.reviewedFixtureSha}`)));
  requireThat(files.every((x,i)=>x.type==='file'&&x.encoding==='base64'&&sha(Buffer.from(x.content,'base64'))===contract.sourcePins[SOURCE_FILES[i]]
    &&sha(sources[SOURCE_FILES[i]])===contract.sourcePins[SOURCE_FILES[i]]),'CI_REVIEWED_BYTES');
}
export async function resolveStagingApiKeys(env,fetcher=fetch) {
  requireThat(typeof env.STAGING_SUPABASE_ACCESS_TOKEN==='string'&&env.STAGING_SUPABASE_ACCESS_TOKEN.length>10,'CI_MANAGEMENT_TOKEN');
  const read=async path=>{try {
    const response=await fetcher(`https://api.supabase.com/v1/projects/${PROJECT}${path}`,{headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`},redirect:'error',signal:AbortSignal.timeout(15000)});
    requireThat(response.ok&&!response.redirected,'CI_STAGING_API_READ');const text=await response.text();requireThat(Buffer.byteLength(text)<1024*1024,'CI_STAGING_API_SIZE');return JSON.parse(text);
  }catch{throw new Refusal('CI_STAGING_API_READ');}};
  const project=await read('');
  requireThat(project?.id===PROJECT&&project.status==='ACTIVE_HEALTHY'&&project.database?.host===`db.${PROJECT}.supabase.co`,'CI_STAGING_PROJECT');
  const rows=await read('/api-keys');requireThat(Array.isArray(rows),'CI_STAGING_KEYS');
  const keys={};
  for(const [name,variable]of [['anon','STAGING_SUPABASE_ANON_KEY'],['service_role','STAGING_SUPABASE_SERVICE_ROLE_KEY']]) {
    const matches=rows.filter(x=>x?.name===name);
    requireThat(matches.length===1&&typeof matches[0].api_key==='string'&&matches[0].api_key.length>10&&!/\s/.test(matches[0].api_key),'CI_STAGING_KEYS');
    keys[variable]=matches[0].api_key;
  }
  requireThat(keys.STAGING_SUPABASE_ANON_KEY!==keys.STAGING_SUPABASE_SERVICE_ROLE_KEY,'CI_STAGING_KEYS');return keys;
}
export async function runCi({env,local,contract,sources,fetcher=fetch,prepare=executePreparation,writePrivateJournal,writeCheckpoint,writeSummary}) {
  const {manifest,fixtureContract,key}=checkCi(env,local,contract,sources);
  const summary={preparationAttempted:false,prepared:false,encryptedCheckpoint:false,failed:false,onboardingComplete:false,uiPaymentVerified:false,paymentCreated:false,capabilityAllocated:false};
  let result=null;
  const checkpoint=async()=>{const payload={format:'JOLENE_CONNECT_FIXTURE_PRIVATE_V1',projectRef:PROJECT,mainSha:local.sha,
    reviewedFixtureSha:contract.reviewedFixtureSha,runId:env.GITHUB_RUN_ID,runAttempt:1,recipientSha256:env.RECIPIENT_SHA256,manifest,fixtureContract,result};
    await writePrivateJournal(payload);await writeCheckpoint(sealJournal(payload,key));
    summary.encryptedCheckpoint=true;await writeSummary({...summary});};
  await checkpoint();
  try {
    await verifyProvenance(env,contract,sources,fetcher);
    const keys=await resolveStagingApiKeys(env,fetcher);
    const preparationEnv={STAGING_SUPABASE_ACCESS_TOKEN:env.STAGING_SUPABASE_ACCESS_TOKEN,STRIPE_TEST_SECRET_KEY:env.STRIPE_TEST_SECRET_KEY,...keys};
    summary.preparationAttempted=true;await checkpoint();
    result=await prepare({manifest,contract:fixtureContract,env:preparationEnv,seed:sources[SOURCE_FILES[2]],local,fetcher,save:checkpoint});
    summary.prepared=result?.prepared===true;requireThat(summary.prepared,'CI_PREPARATION_RECEIPT');await checkpoint();return summary;
  }catch(error){summary.prepared=false;summary.failed=true;
    // Keep the last persisted encrypted intent even if the final save itself fails.
    try{await checkpoint();}catch{try{await writeSummary({...summary});}catch{}}
    throw error;
  }
}
export const AUTH_ONLY_SOURCE_FILES=['scripts/ci/auth-test-frontend.mjs','scripts/ci/connect-test-fixture-ci.mjs',
  'scripts/ci/connect-test-fixture.mjs','scripts/ci/connect-test-fixture-sql.mjs','.github/workflows/connect-test-fixture.yml'];
export function checkAuthOnlyCi(env,local,contract,sources,now=Date.now()) {
  requireThat(contract?.ready===true,'AUTH_ONLY_READINESS_CLOSED');
  requireThat(env.GITHUB_ACTIONS==='true'&&env.GITHUB_EVENT_NAME==='workflow_dispatch'&&env.GITHUB_REPOSITORY===REPO&&env.GITHUB_REF==='refs/heads/main'
    &&hex(env.EXPECTED_MAIN_SHA,40)&&env.GITHUB_SHA===env.EXPECTED_MAIN_SHA&&local?.sha===env.GITHUB_SHA&&local.clean===true
    &&positive(env.GITHUB_RUN_ID)&&env.GITHUB_RUN_ATTEMPT==='1'&&!env.STRIPE_TEST_SECRET_KEY,'AUTH_ONLY_TRUSTED_MAIN');
  requireThat(hex(contract.reviewedSourceSha,40)&&hex(contract.reviewedSourceTree,40),'AUTH_ONLY_REVIEW');
  requireThat(Object.keys(contract.sourcePins??{}).sort().join()===[...AUTH_ONLY_SOURCE_FILES].sort().join()
    &&AUTH_ONLY_SOURCE_FILES.every(p=>hex(contract.sourcePins[p],64)&&typeof sources[p]==='string'&&sha(sources[p])===contract.sourcePins[p]),'AUTH_ONLY_SOURCE_PINS');
  const manifest=newAuthOnlyManifest(`auth-test-ci-${env.GITHUB_RUN_ID}-1`,local.sha);
  const operatorContract={...contract,sourceSha:local.sha};checkAuthOnlyContract(operatorContract,manifest,now);
  return {manifest,operatorContract,key:recipientKey(env.RECIPIENT_PUBLIC_KEY,env.RECIPIENT_SHA256)};
}
export async function verifyAuthOnlyProvenance(env,c,sources,fetcher=fetch) {
  requireThat(typeof env.GITHUB_TOKEN==='string'&&env.GITHUB_TOKEN.length>10,'AUTH_ONLY_GITHUB_TOKEN');
  const read=async path=>{
    try {
      const response=await fetcher(`https://api.github.com/repos/${REPO}${path}`,{headers:{Accept:'application/vnd.github+json',Authorization:`Bearer ${env.GITHUB_TOKEN}`},redirect:'error',signal:AbortSignal.timeout(15000)});
      requireThat(response.ok&&!response.redirected,'AUTH_ONLY_GITHUB_READ');const bytes=await response.text();requireThat(Buffer.byteLength(bytes)<2*1024*1024,'AUTH_ONLY_GITHUB_SIZE');return JSON.parse(bytes);
    }catch(error){if(error instanceof Refusal)throw error;throw new Refusal('AUTH_ONLY_GITHUB_READ');}
  };
  const main=await read('/git/ref/heads/main');requireThat(main?.ref==='refs/heads/main'&&main.object?.sha===env.GITHUB_SHA&&main.object?.type==='commit','AUTH_ONLY_MAIN_MOVED');
  const commit=await read(`/git/commits/${c.reviewedSourceSha}`);requireThat(commit?.sha===c.reviewedSourceSha&&commit.tree?.sha===c.reviewedSourceTree,'AUTH_ONLY_REVIEWED_SOURCE');
  const runs=await read(`/actions/workflows/connect-test-fixture.yml/runs?event=workflow_dispatch&head_sha=${env.GITHUB_SHA}&per_page=100`);
  requireThat(runs.total_count===1&&Array.isArray(runs.workflow_runs)&&runs.workflow_runs.length===1&&String(runs.workflow_runs[0].id)===env.GITHUB_RUN_ID&&runs.workflow_runs[0].path===WORKFLOW,'AUTH_ONLY_PREVIOUS_DISPATCH');
  for(const path of AUTH_ONLY_SOURCE_FILES) {
    const file=await read(`/contents/${path}?ref=${c.reviewedSourceSha}`);
    requireThat(file?.type==='file'&&file.encoding==='base64'&&sha(Buffer.from(file.content,'base64'))===c.sourcePins[path]&&sha(sources[path])===c.sourcePins[path],'AUTH_ONLY_REVIEWED_BYTES');
  }
}
export async function readAuthOnlyPreflight(env,fetcher=fetch) {
  requireThat(typeof env.STAGING_SUPABASE_ACCESS_TOKEN==='string'&&env.STAGING_SUPABASE_ACCESS_TOKEN.length>10,'AUTH_ONLY_MANAGEMENT_TOKEN');
  const read=async(path,sql)=>{
    try {
      const response=await fetcher(`https://api.supabase.com/v1/projects/${PROJECT}${path}`,{method:sql?'POST':'GET',headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},redirect:'error',signal:AbortSignal.timeout(25000),
        ...(sql?{body:JSON.stringify({query:authOnlyReadOnlySql(sql),read_only:false})}:{})});
      requireThat(response.ok&&!response.redirected,'AUTH_ONLY_MANAGEMENT_READ');const bytes=await response.text();requireThat(Buffer.byteLength(bytes)<2_000_000,'AUTH_ONLY_MANAGEMENT_SIZE');return JSON.parse(bytes);
    }catch(error){if(error instanceof Refusal||error instanceof FixtureRefusal)throw error;throw new Refusal('AUTH_ONLY_MANAGEMENT_READ');}
  };
  // Fixed project identity precedes configuration, catalogue and API keys.
  const project=await read('');requireThat(project?.id===PROJECT&&project.status==='ACTIVE_HEALTHY'&&project.database?.host===`db.${PROJECT}.supabase.co`,'AUTH_ONLY_PROJECT');
  const authHooks=projectAuthHooks(await read('/config/auth'));
  const rows=await read('/database/query',authOnlyCatalogueSql());
  requireThat(Array.isArray(rows)&&rows.length===1&&Object.keys(rows[0]).join()==='receipt','AUTH_ONLY_SQL_SHAPE');
  return {authHooks,catalogue:rows[0].receipt};
}
export async function runAuthOnlyCi({env,local,contract,sources,fetcher=fetch,prepare=executeAuthOnlyPreparation,writePrivateJournal,writeCheckpoint,writeSummary}) {
  const {manifest,operatorContract,key}=checkAuthOnlyCi(env,local,contract,sources);
  const summary={preparationAttempted:false,prepared:false,encryptedCheckpoint:false,failed:false,uncertain:false,authCreated:0,profilesCreated:0,missionsCreated:0,
    stripeObjectsCreated:0,paymentCreated:false,smsSent:false,mailSent:false,qualificationVerified:false,frontendCompletionRequired:true};
  let result=null;
  const checkpoint=async()=>{
    summary.uncertain=Object.values(manifest.steps).some(step=>step.state==='intent');
    summary.authCreated=Object.values(manifest.steps).filter(step=>step.state==='done').length;
    const payload={format:'JOLENE_AUTH_ONLY_PRIVATE_V1',purpose:AUTH_ONLY_PURPOSE,projectRef:PROJECT,mainSha:local.sha,
      runId:env.GITHUB_RUN_ID,runAttempt:1,recipientSha256:env.RECIPIENT_SHA256,manifest,result};
    await writePrivateJournal(payload);await writeCheckpoint(sealJournal(payload,key));summary.encryptedCheckpoint=true;await writeSummary({...summary});
  };
  await checkpoint();
  try {
    await verifyAuthOnlyProvenance(env,contract,sources,fetcher);
    const preflight=await readAuthOnlyPreflight(env,fetcher);
    requireThat(JSON.stringify(canonicalAuth(preflight))===JSON.stringify(canonicalAuth({authHooks:contract.authHooks,catalogue:contract.catalogue})),'AUTH_ONLY_PREFLIGHT_DRIFT');
    const keys=await resolveStagingApiKeys(env,fetcher);
    summary.preparationAttempted=true;await checkpoint();
    result=await prepare({manifest,contract:operatorContract,local,fetcher,save:checkpoint,env:{STAGING_SUPABASE_ACCESS_TOKEN:env.STAGING_SUPABASE_ACCESS_TOKEN,
      STAGING_SUPABASE_SERVICE_ROLE_KEY:keys.STAGING_SUPABASE_SERVICE_ROLE_KEY,GITHUB_TOKEN:env.GITHUB_TOKEN}});
    requireAuthOnlyComplete(manifest,result);
    summary.prepared=true;summary.authCreated=2;await checkpoint();return summary;
  }catch(error){summary.failed=true;summary.prepared=false;try{await checkpoint();}catch{try{await writeSummary({...summary});}catch{}}throw error;}
}
async function trustedLocal() {
  const git=args=>execFileSync('git',['-C',ROOT,...args],{env:{PATH:process.env.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'},encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:15000}).trim();
  return {sha:git(['rev-parse','HEAD']),clean:git(['status','--porcelain','--untracked-files=all'])===''};
}
async function main() {
  const [mode,...args]=process.argv.slice(2);
  if(mode==='open'||mode==='open-auth-only') {
    requireThat(args.length===5,'CI_OPEN_ARGUMENTS');const [input,keyPath,expectedHash,fingerprint,output]=args;
    const keyStat=await lstat(keyPath);requireThat(keyStat.isFile()&&!keyStat.isSymbolicLink()&&(keyStat.mode&0o077)===0&&keyStat.uid===process.getuid(),'CI_PRIVATE_KEY');
    const encrypted=await readFile(input);requireThat(encrypted.length<2*1024*1024&&hex(expectedHash,64)&&sha(encrypted)===expectedHash,'CI_ENVELOPE_HASH');
    const payload=(mode==='open-auth-only'?openAuthOnlyJournal:openJournal)(JSON.parse(encrypted),await readFile(keyPath),fingerprint),directory=resolve(output);
    if(mode==='open-auth-only')requireAuthOnlyComplete(payload.manifest,payload.result);
    await mkdir(directory,{mode:0o700});requireThat(await realpath(directory)===directory,'CI_PRIVATE_PATH');
    await privateWrite(join(directory,'manifest.private.json'),payload.manifest);
    await privateWrite(join(directory,'journal.private.json'),payload);
    await privateWrite(join(directory,'frontend.private.json'),mode==='open-auth-only'
      ?{mainSha:payload.mainSha,projectUrl:`https://${PROJECT}.supabase.co`,members:payload.manifest.members,
        purpose:AUTH_ONLY_PURPOSE,authCreatedByOperator:true,frontendCompletionRequired:true,qualificationVerified:false}
      :{mainSha:payload.mainSha,projectUrl:`https://${PROJECT}.supabase.co`,members:payload.manifest.members.slice(0,2),
      missionId:payload.manifest.sql.ids.mission,invoiceId:payload.result?.invoiceId??null,commissionId:payload.result?.commissionId??null,
      customerId:payload.manifest.steps.customer?.result?.id??null,connectedAccountId:payload.manifest.steps.account?.result?.id??null});
    console.log(JSON.stringify({opened:true,credentialsPrinted:false,serviceCredentialsIncluded:false}));return;
  }
  requireThat(['check','run','check-auth-only','run-auth-only'].includes(mode)&&args.length===0,'CI_ARGUMENTS');
  const authOnly=mode.endsWith('-auth-only');
  const contract=JSON.parse(await readFile(join(ROOT,authOnly?'scripts/ci/auth-test-frontend-ci.contract.json':'scripts/ci/connect-test-fixture-ci.contract.json'),'utf8'));
  const sources=Object.fromEntries(await Promise.all((authOnly?AUTH_ONLY_SOURCE_FILES:SOURCE_FILES).map(async path=>[path,await readFile(join(ROOT,path),'utf8')]))),local=await trustedLocal();
  (authOnly?checkAuthOnlyCi:checkCi)(process.env,local,contract,sources);
  if(mode.startsWith('check')){console.log(JSON.stringify({contextVerified:true,remoteCalls:false}));return;}
  const temp=process.env.RUNNER_TEMP;requireThat(typeof temp==='string'&&resolve(temp)===temp&&await realpath(temp)===temp,'CI_RUNNER_TEMP');
  const directory=join(temp,'connect-test-fixture-private'),proof=join(temp,'connect-test-fixture-proof');
  await mkdir(directory,{mode:0o700});await mkdir(proof,{mode:0o700});
  let privateExists=false,checkpointExists=false,summaryExists=false;
  await (authOnly?runAuthOnlyCi:runCi)({env:process.env,local,contract,sources,writePrivateJournal:async payload=>{
    await privateWrite(join(directory,'journal.private.json'),payload,privateExists);privateExists=true;
  },writeCheckpoint:async envelope=>{
    await privateWrite(join(proof,'fixture.encrypted.json'),envelope,checkpointExists);checkpointExists=true;
  },writeSummary:async summary=>{await privateWrite(join(proof,'result.json'),summary,summaryExists);summaryExists=true;}});
  console.log(JSON.stringify(authOnly?{prepared:true,authCreated:2,profilesCreated:0,qualificationVerified:false,frontendCompletionRequired:true}:{prepared:true,uiPaymentVerified:false,onboardingComplete:false}));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
  const code=(error instanceof Refusal||error instanceof FixtureRefusal)&&/^[A-Z0-9_]+$/.test(error.code??'')?error.code:'CI_UNEXPECTED_FAILURE';
  console.error(JSON.stringify({prepared:false,code}));process.exitCode=1;
});
