/** Main-only CI adapter. Provider credentials never enter a saved object. */
import { createHash, createPublicKey, createPrivateKey, publicEncrypt, privateDecrypt, randomBytes, createCipheriv, createDecipheriv, constants } from 'node:crypto';
import { readFile, lstat, mkdir, realpath } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { newManifest, validateManifest, checkContract, executePreparation, privateWrite, Refusal as FixtureRefusal, PROJECT } from './connect-test-fixture.mjs';

const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../..'), REPO='Gabpcd/JJJJJ';
export const SOURCE_FILES=['scripts/ci/connect-test-fixture.mjs','scripts/ci/connect-test-fixture-sql.mjs','scripts/ci/connect-test-fixture-prepare.sql'];
const WORKFLOW='.github/workflows/connect-test-fixture.yml', FORMAT='JOLENE_CONNECT_FIXTURE_ENCRYPTED_V1';
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
export function openJournal(envelope,pem,fingerprint) {
  requireThat(envelope?.format===FORMAT&&envelope.cipher==='AES-256-GCM'&&envelope.keyWrap==='RSA-OAEP-SHA256'
    &&Object.keys(envelope).sort().join() === 'cipher,ciphertext,format,iv,keyWrap,tag,wrappedKey','CI_ENVELOPE');
  const privateKey=createPrivateKey(pem),publicKey=createPublicKey(privateKey);
  recipientKey(publicKey.export({type:'spki',format:'pem'}),fingerprint);
  const bytes=(v,n)=>{requireThat(typeof v==='string'&&v.length<2*1024*1024&&/^[A-Za-z0-9+/]+={0,2}$/.test(v),'CI_ENVELOPE');const b=Buffer.from(v,'base64');requireThat(b.toString('base64')===v&&(!n||b.length===n),'CI_ENVELOPE');return b;};
  const secret=privateDecrypt({key:privateKey,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},bytes(envelope.wrappedKey,512));
  try {const decipher=createDecipheriv('aes-256-gcm',secret,bytes(envelope.iv,12));decipher.setAuthTag(bytes(envelope.tag,16));
    const payload=JSON.parse(Buffer.concat([decipher.update(bytes(envelope.ciphertext)),decipher.final()]));
    requireThat(payload?.format==='JOLENE_CONNECT_FIXTURE_PRIVATE_V1'&&payload.projectRef===PROJECT,'CI_PAYLOAD');validateManifest(payload.manifest);return payload;
  }finally{secret.fill(0);}
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
    summary.preparationAttempted=true;await checkpoint();
    result=await prepare({manifest,contract:fixtureContract,env,seed:sources[SOURCE_FILES[2]],local,fetcher,save:checkpoint});
    summary.prepared=result?.prepared===true;requireThat(summary.prepared,'CI_PREPARATION_RECEIPT');await checkpoint();return summary;
  }catch(error){summary.prepared=false;summary.failed=true;
    // Keep the last persisted encrypted intent even if the final save itself fails.
    try{await checkpoint();}catch{try{await writeSummary({...summary});}catch{}}
    throw error;
  }
}
async function trustedLocal() {
  const git=args=>execFileSync('git',['-C',ROOT,...args],{env:{PATH:process.env.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'},encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:15000}).trim();
  return {sha:git(['rev-parse','HEAD']),clean:git(['status','--porcelain','--untracked-files=all'])===''};
}
async function main() {
  const [mode,...args]=process.argv.slice(2);
  if(mode==='open') {
    requireThat(args.length===5,'CI_OPEN_ARGUMENTS');const [input,keyPath,expectedHash,fingerprint,output]=args;
    const keyStat=await lstat(keyPath);requireThat(keyStat.isFile()&&!keyStat.isSymbolicLink()&&(keyStat.mode&0o077)===0&&keyStat.uid===process.getuid(),'CI_PRIVATE_KEY');
    const encrypted=await readFile(input);requireThat(encrypted.length<2*1024*1024&&hex(expectedHash,64)&&sha(encrypted)===expectedHash,'CI_ENVELOPE_HASH');
    const payload=openJournal(JSON.parse(encrypted),await readFile(keyPath),fingerprint),directory=resolve(output);
    await mkdir(directory,{mode:0o700});requireThat(await realpath(directory)===directory,'CI_PRIVATE_PATH');
    await privateWrite(join(directory,'manifest.private.json'),payload.manifest);
    await privateWrite(join(directory,'journal.private.json'),payload);
    await privateWrite(join(directory,'frontend.private.json'),{mainSha:payload.mainSha,projectUrl:`https://${PROJECT}.supabase.co`,members:payload.manifest.members.slice(0,2),
      missionId:payload.manifest.sql.ids.mission,invoiceId:payload.result?.invoiceId??null,commissionId:payload.result?.commissionId??null,
      customerId:payload.manifest.steps.customer?.result?.id??null,connectedAccountId:payload.manifest.steps.account?.result?.id??null});
    console.log(JSON.stringify({opened:true,credentialsPrinted:false,serviceCredentialsIncluded:false}));return;
  }
  requireThat(['check','run'].includes(mode)&&args.length===0,'CI_ARGUMENTS');
  const contract=JSON.parse(await readFile(join(ROOT,'scripts/ci/connect-test-fixture-ci.contract.json'),'utf8'));
  const sources=Object.fromEntries(await Promise.all(SOURCE_FILES.map(async path=>[path,await readFile(join(ROOT,path),'utf8')]))),local=await trustedLocal();
  checkCi(process.env,local,contract,sources);
  if(mode==='check'){console.log(JSON.stringify({contextVerified:true,remoteCalls:false}));return;}
  const temp=process.env.RUNNER_TEMP;requireThat(typeof temp==='string'&&resolve(temp)===temp&&await realpath(temp)===temp,'CI_RUNNER_TEMP');
  const directory=join(temp,'connect-test-fixture-private'),proof=join(temp,'connect-test-fixture-proof');
  await mkdir(directory,{mode:0o700});await mkdir(proof,{mode:0o700});
  let privateExists=false,checkpointExists=false,summaryExists=false;
  await runCi({env:process.env,local,contract,sources,writePrivateJournal:async payload=>{
    await privateWrite(join(directory,'journal.private.json'),payload,privateExists);privateExists=true;
  },writeCheckpoint:async envelope=>{
    await privateWrite(join(proof,'fixture.encrypted.json'),envelope,checkpointExists);checkpointExists=true;
  },writeSummary:async summary=>{await privateWrite(join(proof,'result.json'),summary,summaryExists);summaryExists=true;}});
  console.log(JSON.stringify({prepared:true,uiPaymentVerified:false,onboardingComplete:false}));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
  const code=(error instanceof Refusal||error instanceof FixtureRefusal)&&/^[A-Z0-9_]+$/.test(error.code??'')?error.code:'CI_UNEXPECTED_FAILURE';
  console.error(JSON.stringify({prepared:false,code}));process.exitCode=1;
});
