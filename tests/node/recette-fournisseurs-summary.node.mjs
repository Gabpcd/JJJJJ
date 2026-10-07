import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { summarizePreflight, readPreflightReport } from '../../scripts/recette-fournisseurs/summarize-preflight.mjs';
import { collectPreflight } from '../../scripts/recette-fournisseurs/collect-preflight.mjs';

const canary='PRIVATE_CANARY_token-reference-account-note';
const noSource = () => collectPreflight({source:null,fetchImpl:()=>assert.fail('no network')});
test('source failure renders refusal with zero observed groups and all nine permanent limits', async()=>{
  const report=await noSource(), summary=summarizePreflight(report);
  assert.match(summary,/NON PRÊT/);assert.match(summary,/0\/9 groupes/);assert.match(summary,/Référence source invalide/);
  assert.match(summary,/Contenu Edge/);assert.match(summary,/Définitions SQL/);assert.match(summary,/cohortes/);
  assert.match(summary,/Vault/);assert.match(summary,/SMS/);assert.match(summary,/utilisé par les Edge/);
  assert.match(summary,/Portée Connect/);assert.match(summary,/files étrangères/);assert.match(summary,/snapshot transactionnel/);
});
test('unknown fields, references, fingerprints and provider exception messages cannot reach summary',async()=>{
  const report=await noSource();
  report.note=canary;report.source={sha:canary};report.expectedStripeAccount=canary;report.projectRef=canary;
  report.checks.edgeSecretNames={status:'UNKNOWN',raw:canary};
  assert(!summarizePreflight(report).includes(canary));
});
test('unknown diagnostic codes and forged readiness are closed rather than echoed',async()=>{
  for(const edit of [r=>r.issues.push(canary),r=>r.readyForTransports=true,r=>r.status=canary,r=>r.integratedFlowReady=true]){
    const report=await noSource();edit(report);const summary=summarizePreflight(report);
    assert.match(summary,/rapport absent, invalide ou diagnostic non reconnu/);assert.match(summary,/NON PRÊT/);
    assert(!summary.includes(canary));assert(!summary.includes('Collecte : complète'));
  }
});
test('unrecognized checks, missing limits and unknown check statuses cannot claim completeness',async()=>{
  for(const edit of [r=>r.checks[canary]={status:'OBSERVED'},r=>r.unknowns=[],r=>r.checks.migrations={status:canary}]){
    const report=await noSource();edit(report);const summary=summarizePreflight(report);
    assert.match(summary,/incomplète ou non confirmée/);assert(!summary.includes(canary));
  }
});
test('outer collection failure stays NON PRET without assuming successful reads',()=>{
  const summary=summarizePreflight({status:'NON_PRET',readyForTransports:false,integratedFlowReady:false,issues:['COLLECTION_SOURCE_OR_RUNTIME_INVALID']});
  assert.match(summary,/Collecte impossible/);assert.match(summary,/0\/9/);assert.match(summary,/code de sortie 2/);
});
test('file reader refuses symlinks, invalid UTF8, invalid JSON and oversized input',()=>{
  const dir=mkdtempSync(join(tmpdir(),'jolene-inventory-summary-'));
  try{
    const target=join(dir,'target'),alias=join(dir,'alias');writeFileSync(target,'{}');symlinkSync(target,alias);
    assert.throws(()=>readPreflightReport(alias));
    for(const data of [Buffer.from([255]),Buffer.from('{bad'),Buffer.alloc(1024*1024+1,65)]){
      writeFileSync(target,data);assert.throws(()=>readPreflightReport(target));
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
});
test('CLI has no provider credentials and invalid report yields only closed summary',async()=>{
  const dir=mkdtempSync(join(tmpdir(),'jolene-inventory-summary-cli-'));
  const script=fileURLToPath(new URL('../../scripts/recette-fournisseurs/summarize-preflight.mjs',import.meta.url));
  try{
    const run=()=>spawnSync(process.execPath,[script],{cwd:dir,encoding:'utf8',env:{PATH:process.env.PATH}});
    let result=run();assert.equal(result.status,1);assert.equal(result.stderr,'');assert.match(result.stdout,/absent ou illisible/);
    writeFileSync(join(dir,'recette-fournisseurs-preflight.json'),JSON.stringify({...await noSource(),note:canary}));
    result=run();assert.equal(result.status,0);assert.match(result.stdout,/NON PRÊT/);assert(!result.stdout.includes(canary));assert.equal(result.stderr,'');
  }finally{rmSync(dir,{recursive:true,force:true});}
});
