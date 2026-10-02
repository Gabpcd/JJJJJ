import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, lstatSync } from 'node:fs';
import { resolve, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { catalogueSql, transactionSql } from './connect-staging-closed-sql.mjs';
import { renderStagingAdmission } from './connect-staging-admission-render.mjs';

export const PROJECT = 'mejpriaetwgtcstbgfid';
export const REPOSITORY = 'Gabpcd/JJJJJ';
export const MIGRATION = 'supabase/migrations/20261001201055_reserver_remboursement_connect_avant_transfert.sql';
export const CAPACITY = 'scripts/ci/connect-staging-test-capacity.sql';
export const ADMISSION = 'scripts/ci/connect-staging-admission.sql';
const API = `https://api.supabase.com/v1/projects/${PROJECT}`;
const GH = `https://api.github.com/repos/${REPOSITORY}`;
const sha = (v, n=40) => typeof v==='string' && new RegExp(`^[a-f0-9]{${n}}$`).test(v) && !/^0+$/.test(v);
const id = v => typeof v==='string' && /^[1-9][0-9]{0,19}$/.test(v);
const exact = (v,keys) => v!==null && typeof v==='object' && !Array.isArray(v) && Object.keys(v).sort().join(',')===keys.slice().sort().join(',');
export const digest = text => createHash('sha256').update(text).digest('hex');
export const canonical = v => Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
class Refusal extends Error { constructor(code){super(code);this.code=code;} }
const fail = code => {throw new Refusal(code);};

export function checkContract(c) {
  if (!exact(c,['schemaVersion','ready','projectRef','protocolEnabled','capabilityEnabled','candidate','reviewedManifest','requiredCiRuns','expectedBefore','expectedAfter','reason'])
    || c.schemaVersion!==1 || c.projectRef!==PROJECT || c.protocolEnabled!==false || c.capabilityEnabled!==false) fail('CONTRACT_REFUSED');
  if(c.ready!==true) fail('READINESS_CLOSED');
  if(!exact(c.candidate,['sha','tree']) || !sha(c.candidate.sha) || !sha(c.candidate.tree)) fail('CANDIDATE_PIN_REQUIRED');
  const m=c.reviewedManifest;
  if(!exact(m,['migrationSha256','capacitySha256','admissionSha256','manifestSha256']) || !sha(m.migrationSha256,64) || !sha(m.capacitySha256,64) || !sha(m.admissionSha256,64)
    || m.manifestSha256!==digest(JSON.stringify(canonical({candidate:c.candidate,migrationSha256:m.migrationSha256,capacitySha256:m.capacitySha256,admissionSha256:m.admissionSha256})))) fail('MANIFEST_PIN_REQUIRED');
  if(!Array.isArray(c.requiredCiRuns) || !c.requiredCiRuns.length || c.requiredCiRuns.length>10
    || new Set(c.requiredCiRuns).size!==c.requiredCiRuns.length || c.requiredCiRuns.some(x=>!id(x))) fail('CI_RUN_PINS_REQUIRED');
  for(const v of [c.expectedBefore,c.expectedAfter]) if(!exact(v,['catalogue','registry']) || !sha(v.catalogue,32) || !sha(v.registry,32)) fail('CATALOGUE_PIN_REQUIRED');
  return c.candidate;
}
export function checkContext(env,local,c) {
  if(env.GITHUB_ACTIONS!=='true' || env.GITHUB_EVENT_NAME!=='workflow_dispatch' || env.GITHUB_REPOSITORY!==REPOSITORY
    || env.GITHUB_REF!=='refs/heads/main' || !sha(env.GITHUB_SHA) || env.EXPECTED_MAIN_SHA!==env.GITHUB_SHA
    || local.mainSha!==env.GITHUB_SHA || local.mainClean!==true || !id(env.GITHUB_RUN_ID) || env.GITHUB_RUN_ATTEMPT!=='1') fail('TRUSTED_MAIN_FIRST_ATTEMPT_REQUIRED');
  checkContract(c);
  if(env.EXPECTED_CANDIDATE_SHA!==c.candidate.sha || env.EXPECTED_CANDIDATE_TREE!==c.candidate.tree
    || env.EXPECTED_MANIFEST_SHA256!==c.reviewedManifest.manifestSha256) fail('DISPATCH_PIN_MISMATCH');
}
export function checkAssets(c,local) {
  if(local.candidateSha!==c.candidate.sha || local.candidateTree!==c.candidate.tree || local.candidateClean!==true) fail('CANDIDATE_TREE_MISMATCH');
  if(typeof local.migration!=='string' || Buffer.byteLength(local.migration)>300_000 || digest(local.migration)!==c.reviewedManifest.migrationSha256
    || typeof local.capacity!=='string' || Buffer.byteLength(local.capacity)>100_000 || digest(local.capacity)!==c.reviewedManifest.capacitySha256
    || typeof local.admission!=='string' || Buffer.byteLength(local.admission)>200_000 || digest(local.admission)!==c.reviewedManifest.admissionSha256) fail('ASSET_DIGEST_MISMATCH');
  if(!Array.isArray(local.migrationVersions) || !local.migrationVersions.length || local.migrationVersions.some(v=>!/^\d{14}$/.test(v))
    || new Set(local.migrationVersions).size!==local.migrationVersions.length || !local.migrationVersions.includes('20261001201055')) fail('MIGRATION_FILES_INVALID');
}
export function checkSnapshot(value,c,phase,baseline) {
  if(!Array.isArray(value) || value.length!==1 || !exact(value[0],['catalogue','registry','versions','rows','quiescent','gate_closed','capacity_closed'])) fail('CATALOGUE_SHAPE');
  const s=value[0], expected=phase==='before'?c.expectedBefore:c.expectedAfter;
  if(s.catalogue!==expected.catalogue || s.registry!==expected.registry || !sha(s.rows,32) || s.quiescent!==true
    || s.gate_closed!==true || s.capacity_closed!==true || !Array.isArray(s.versions)
    || s.versions.some(v=>typeof v!=='string'||!/^\d{14}$/.test(v)) || new Set(s.versions).size!==s.versions.length) fail('CATALOGUE_DRIFT');
  if(baseline && s.rows!==baseline.rows) fail('BUSINESS_ROWS_CHANGED');
  return s;
}
export function checkPending(local,snapshot,phase) {
  const expected=local.migrationVersions.filter(v=>phase==='after'||v!=='20261001201055').sort();
  if(JSON.stringify(snapshot.versions.slice().sort())!==JSON.stringify(expected)) fail('MIGRATION_HISTORY_MISMATCH');
}

export async function executeClosed({env,local,contract,fetchImpl=fetch,checkpoint=()=>{}}) {
  const report={schemaVersion:1,status:'failed',phase:'context',code:null,projectRef:PROJECT,
    sourceSha:null,candidateSha:null,manifestSha256:null,dryRunVerified:false,commitAttempted:false,commitConfirmed:false,
    closedStateVerified:false,businessRowsUnchanged:false,providerInvoked:false,authCreated:false,edgeDeployed:false};
  const save=()=>{try{checkpoint(structuredClone(report));}catch{fail('CHECKPOINT_FAILED');}};
  async function request(url,method='GET',body,management=false) {
    try {
      const response=await fetchImpl(url,{method,redirect:'error',signal:AbortSignal.timeout(110_000),
        headers:management?{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'}:
          {Authorization:`Bearer ${env.GITHUB_TOKEN}`,Accept:'application/vnd.github+json','User-Agent':'Jolene-staging-closed'},
        ...(body===undefined?{}:{body:JSON.stringify(body)})});
      if(!response.ok) fail('HTTP_REFUSED');
      const text=await response.text(); if(Buffer.byteLength(text)>1_000_000) fail('RESPONSE_TOO_LARGE');
      return JSON.parse(text);
    } catch(error){if(error instanceof Refusal)throw error;fail('TRANSPORT_OR_JSON_UNCERTAIN');}
  }
  const query=(sql,readOnly)=>request(`${API}/database/query`,'POST',{query:sql,read_only:readOnly},true);
  const main=async()=>{const x=await request(`${GH}/git/ref/heads/main`);if(x?.ref!=='refs/heads/main'||x.object?.sha!==env.GITHUB_SHA||x.object?.type!=='commit')fail('MAIN_MOVED');};
  let before,commitRequestStarted=false;
  try {
    checkContext(env,local,contract);checkAssets(contract,local);
    if(!env.STAGING_SUPABASE_ACCESS_TOKEN?.trim() || !env.GITHUB_TOKEN?.trim()) fail('TOKENS_REQUIRED');
    report.sourceSha=env.GITHUB_SHA;report.candidateSha=contract.candidate.sha;report.manifestSha256=contract.reviewedManifest.manifestSha256;save();
    report.phase='trusted_revision';await main();
    const git=await request(`${GH}/git/commits/${contract.candidate.sha}`);
    if(git?.sha!==contract.candidate.sha||git.tree?.sha!==contract.candidate.tree)fail('REMOTE_TREE_MISMATCH');
    for(const run of contract.requiredCiRuns){const x=await request(`${GH}/actions/runs/${run}`);
      if(String(x?.id)!==run||x.status!=='completed'||x.conclusion!=='success'||x.head_sha!==contract.candidate.sha
        ||x.repository?.full_name!==REPOSITORY||x.head_repository?.full_name!==REPOSITORY||!['pull_request','push','workflow_dispatch'].includes(x.event))fail('REVIEWED_CI_NOT_SUCCESSFUL');}
    report.phase='project_identity';const project=await request(API,'GET',undefined,true);
    if(project?.id!==PROJECT||project.region!=='eu-west-1'||project.status!=='ACTIVE_HEALTHY'||project.database?.host!==`db.${PROJECT}.supabase.co`)fail('PROJECT_IDENTITY_REFUSED');
    report.phase='catalogue_before';before=checkSnapshot(await query(catalogueSql(false),true),contract,'before');checkPending(local,before,'before');
    report.phase='transaction_rollback';save();
    // Le même SQL complet est appliqué puis annulé. Un échec n'autorise pas le COMMIT.
    await query(transactionSql(local,contract,before,false),false);
    const restored=checkSnapshot(await query(catalogueSql(false),true),contract,'before',before);checkPending(local,restored,'before');
    report.dryRunVerified=true;save();await main();
    report.phase='commit_once';report.commitAttempted=true;save();
    // Une seule tentative. Aucun retry de transport, reprise automatique ou rollback compensatoire.
    const applySql=transactionSql(local,contract,before,true);
    commitRequestStarted=true;await query(applySql,false);
    report.phase='catalogue_after';const after=checkSnapshot(await query(catalogueSql(true),true),contract,'after',before);checkPending(local,after,'after');
    report.commitConfirmed=true;report.closedStateVerified=true;report.businessRowsUnchanged=true;report.status='success';report.phase='complete';save();
  }catch(error){report.code=error instanceof Refusal?error.code:'UNEXPECTED_FAILURE';
    if(report.commitAttempted&&!commitRequestStarted)report.commitAttempted=false;
    if(commitRequestStarted){report.status='uncertain';report.phase='reconcile_after_uncertain';
      try{const after=checkSnapshot(await query(catalogueSql(true),true),contract,'after',before);checkPending(local,after,'after');
        report.closedStateVerified=true;report.businessRowsUnchanged=true;}catch{/* Constat seulement ; ne jamais renvoyer la transaction. */}}
    try{save();}catch{report.code='CHECKPOINT_FAILED';}}
  return report;
}

// Aucune clé du job ni variable de substitution Git n'est transmise au sous-processus.
export const git=(cwd,args,environment=process.env)=>execFileSync('git',['-C',cwd,...args],{
  env:{PATH:environment.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'},
  encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:15_000,maxBuffer:2_000_000,
}).trim();
const file=(root,path)=>{const p=resolve(root,path);if(lstatSync(p).isSymbolicLink()||!lstatSync(p).isFile())fail('ASSET_NOT_REGULAR');return readFileSync(p,'utf8');};
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  let report;
  try{
    const mode=process.argv[2];if(!['resolve','apply'].includes(mode)||process.argv.length!==3)fail('MODE_REFUSED');
    const root=process.cwd(),contract=JSON.parse(file(root,'scripts/ci/connect-staging-closed.contract.json'));
    const local={mainSha:git(root,['rev-parse','HEAD']),mainClean:git(root,['status','--porcelain','--untracked-files=no'])===''};
    checkContext(process.env,local,contract);
    if(mode==='resolve'){
      if(!process.env.GITHUB_OUTPUT||!isAbsolute(process.env.GITHUB_OUTPUT))fail('OUTPUT_PATH_REQUIRED');
      writeFileSync(process.env.GITHUB_OUTPUT,`candidate=${contract.candidate.sha}\n`,{flag:'a'});
      console.log('CANDIDATE_PIN_CONFIRMED');
    }else{
      const candidate=resolve(root,'candidate');Object.assign(local,{candidateSha:git(candidate,['rev-parse','HEAD']),candidateTree:git(candidate,['rev-parse','HEAD^{tree}']),candidateClean:git(candidate,['status','--porcelain','--untracked-files=all'])==='',
        migration:file(candidate,MIGRATION),capacity:file(candidate,CAPACITY),admission:renderStagingAdmission(file(candidate,MIGRATION),file(candidate,ADMISSION)),migrationVersions:git(candidate,['ls-tree','-r','--name-only','HEAD','supabase/migrations']).split('\n').map(x=>/^supabase\/migrations\/(\d{14})_[^/]+\.sql$/.exec(x)?.[1]).filter(Boolean)});
      if(!process.env.RUNNER_TEMP||!isAbsolute(process.env.RUNNER_TEMP))fail('REPORT_PATH_REQUIRED');
      const out=resolve(process.env.RUNNER_TEMP,'connect-staging-closed');mkdirSync(out,{recursive:true,mode:0o700});
      report=await executeClosed({env:process.env,local,contract,checkpoint:r=>writeFileSync(resolve(out,'result.json'),JSON.stringify(r,null,2)+'\n',{mode:0o600})});
      console.log(JSON.stringify(report));if(report.status!=='success')process.exitCode=1;
    }
  }catch(error){console.log(JSON.stringify({status:'failed',code:error instanceof Refusal?error.code:'LOCAL_REFUSAL'}));process.exitCode=1;}
}
