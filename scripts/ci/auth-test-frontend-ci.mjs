/** Auth-only main CI adapter. Historical Connect execution remains separate. */
import { createHash, createPublicKey, createPrivateKey, privateDecrypt, createDecipheriv, constants } from 'node:crypto';
import { readFile, lstat, mkdir, realpath } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { recipientKey, sealJournal, resolveStagingApiKeys } from './connect-test-fixture-ci.mjs';
import { privateWrite, Refusal as FixtureRefusal, PROJECT } from './connect-test-fixture.mjs';
import {
  AUTH_ONLY_PURPOSE,newAuthOnlyManifest,validateAuthOnlyManifest,checkAuthOnlyContract,executeAuthOnlyPreparation,
  projectAuthHooks,authOnlyCatalogueSql,authOnlyReadOnlySql,requireAuthOnlyComplete } from './auth-test-frontend.mjs';

const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../..'), REPO='Gabpcd/JJJJJ';
const WORKFLOW='.github/workflows/connect-test-fixture.yml', FORMAT='JOLENE_CONNECT_FIXTURE_ENCRYPTED_V1';
const canonicalAuth=v=>Array.isArray(v)?v.map(canonicalAuth):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonicalAuth(v[k])])):v;
const sha=x=>createHash('sha256').update(x).digest('hex'), hex=(x,n)=>typeof x==='string'&&new RegExp(`^[a-f0-9]{${n}}$`).test(x)&&!/^0+$/.test(x);
const positive=x=>typeof x==='string'&&/^[1-9][0-9]{0,19}$/.test(x);
class Refusal extends Error { constructor(code){super(code);this.code=code;} }
const requireThat=(ok,code)=>{if(!ok)throw new Refusal(code);};
// The reused historical helpers own a private Refusal class. Only their closed
// constant diagnostics are allowed through this adapter's CLI error projection.
const HELPER_REFUSAL_CODES=new Set(['CI_RECIPIENT','CI_PAYLOAD_SIZE','CI_MANAGEMENT_TOKEN','CI_STAGING_API_READ','CI_STAGING_PROJECT','CI_STAGING_KEYS']);
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
export function openAuthOnlyJournal(envelope,pem,fingerprint) {
  const payload=decryptEnvelope(envelope,pem,fingerprint);
  requireThat(payload?.format==='JOLENE_AUTH_ONLY_PRIVATE_V1'&&payload.projectRef===PROJECT&&payload.purpose===AUTH_ONLY_PURPOSE,'AUTH_ONLY_PAYLOAD');
  validateAuthOnlyManifest(payload.manifest);
  requireThat(payload.mainSha===payload.manifest.sourceSha,'AUTH_ONLY_PAYLOAD');return payload;
}
export const AUTH_ONLY_SOURCE_FILES=['scripts/ci/auth-test-frontend.mjs','scripts/ci/auth-test-frontend-ci.mjs',
  'scripts/ci/connect-test-fixture-ci.mjs','scripts/ci/connect-test-fixture.mjs','scripts/ci/connect-test-fixture-sql.mjs','.github/workflows/connect-test-fixture.yml'];
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
  if(mode==='open-auth-only') {
    requireThat(args.length===5,'CI_OPEN_ARGUMENTS');const [input,keyPath,expectedHash,fingerprint,output]=args;
    const keyStat=await lstat(keyPath);requireThat(keyStat.isFile()&&!keyStat.isSymbolicLink()&&(keyStat.mode&0o077)===0&&keyStat.uid===process.getuid(),'CI_PRIVATE_KEY');
    const encrypted=await readFile(input);requireThat(encrypted.length<2*1024*1024&&hex(expectedHash,64)&&sha(encrypted)===expectedHash,'CI_ENVELOPE_HASH');
    const payload=openAuthOnlyJournal(JSON.parse(encrypted),await readFile(keyPath),fingerprint),directory=resolve(output);
    requireAuthOnlyComplete(payload.manifest,payload.result);
    await mkdir(directory,{mode:0o700});requireThat(await realpath(directory)===directory,'CI_PRIVATE_PATH');
    await privateWrite(join(directory,'manifest.private.json'),payload.manifest);
    await privateWrite(join(directory,'journal.private.json'),payload);
    await privateWrite(join(directory,'frontend.private.json'),{mainSha:payload.mainSha,projectUrl:`https://${PROJECT}.supabase.co`,members:payload.manifest.members,
      purpose:AUTH_ONLY_PURPOSE,authCreatedByOperator:true,frontendCompletionRequired:true,qualificationVerified:false});
    console.log(JSON.stringify({opened:true,credentialsPrinted:false,serviceCredentialsIncluded:false}));return;
  }
  requireThat(['check-auth-only','run-auth-only'].includes(mode)&&args.length===0,'CI_ARGUMENTS');
  const contract=JSON.parse(await readFile(join(ROOT,'scripts/ci/auth-test-frontend-ci.contract.json'),'utf8'));
  const sources=Object.fromEntries(await Promise.all(AUTH_ONLY_SOURCE_FILES.map(async path=>[path,await readFile(join(ROOT,path),'utf8')]))),local=await trustedLocal();
  checkAuthOnlyCi(process.env,local,contract,sources);
  if(mode==='check-auth-only'){console.log(JSON.stringify({contextVerified:true,remoteCalls:false}));return;}
  const temp=process.env.RUNNER_TEMP;requireThat(typeof temp==='string'&&resolve(temp)===temp&&await realpath(temp)===temp,'CI_RUNNER_TEMP');
  const directory=join(temp,'connect-test-fixture-private'),proof=join(temp,'connect-test-fixture-proof');
  await mkdir(directory,{mode:0o700});await mkdir(proof,{mode:0o700});
  let privateExists=false,checkpointExists=false,summaryExists=false;
  await runAuthOnlyCi({env:process.env,local,contract,sources,writePrivateJournal:async payload=>{
    await privateWrite(join(directory,'journal.private.json'),payload,privateExists);privateExists=true;
  },writeCheckpoint:async envelope=>{
    await privateWrite(join(proof,'fixture.encrypted.json'),envelope,checkpointExists);checkpointExists=true;
  },writeSummary:async summary=>{await privateWrite(join(proof,'result.json'),summary,summaryExists);summaryExists=true;}});
  console.log(JSON.stringify({prepared:true,authCreated:2,profilesCreated:0,qualificationVerified:false,frontendCompletionRequired:true}));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
  const known=error instanceof Refusal||error instanceof FixtureRefusal||HELPER_REFUSAL_CODES.has(error?.code);
  const code=known&&/^[A-Z0-9_]+$/.test(error.code??'')?error.code:'CI_UNEXPECTED_FAILURE';
  console.error(JSON.stringify({prepared:false,code}));process.exitCode=1;
});
