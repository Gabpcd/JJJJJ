import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),YAML=require('yaml');
const workflow=YAML.parse(await readFile(new URL('../../.github/workflows/f1-cloud-staging.yml',import.meta.url),'utf8'));
test('manual main-only job retains staging lock, read-only repository token and bounded always-finalization',()=>{
  assert.deepEqual(Object.keys(workflow.on),['workflow_dispatch']);assert.deepEqual(workflow.permissions,{contents:'read'});
  assert.deepEqual(workflow.concurrency,{group:'jolene-supabase-staging-writes',queue:'max','cancel-in-progress':false});
  const job=workflow.jobs.documents;assert.equal(job['timeout-minutes'],35);
  for(const clause of ["github.repository == 'Gabpcd/JJJJJ'","github.ref == 'refs/heads/main'","github.event_name == 'workflow_dispatch'"])assert(job.if.includes(clause));
  const steps=job.steps,pilot=steps.findIndex(x=>x.id==='pilot'),cleanup=steps.findIndex(x=>x.run==='node scripts/ci/f1-cloud-pilot.mjs finalize');
  assert(cleanup>pilot);assert(steps[cleanup].if.startsWith('always()'));assert.equal(steps[pilot]['timeout-minutes'],14);
  assert.equal(steps[0].run,'echo "F1_JOB_STARTED_UNIX=$(date +%s)" >> "$GITHUB_ENV"');
  const gate=steps.findIndex(x=>x.run==='node scripts/ci/f1-cloud-pilot.mjs check');assert(gate>0&&gate<pilot);assert.equal(steps[gate].env,undefined);
  assert.equal(steps[cleanup]['timeout-minutes'],4);
  for(const command of ['npm ci','npx --no-install playwright install --with-deps chromium webkit','npm run build']){const i=steps.findIndex(x=>x.run===command);assert(i>gate&&i<pilot);assert(Number.isInteger(steps[i]['timeout-minutes']));}
  assert.deepEqual(steps.find(x=>x.uses?.startsWith('actions/checkout@')).with,{ref:'${{ github.sha }}','persist-credentials':false});
});
test('artifact paths expose only closed JSON and synthetic invoice-card PNG, never private directory or credential',()=>{
  const step=workflow.jobs.documents.steps.find(x=>x.uses?.startsWith('actions/upload-artifact@'));
  assert.deepEqual(step.with.path.trim().split('\n'),['${{ runner.temp }}/f1-cloud-proof/result.json','${{ runner.temp }}/f1-cloud-proof/finalization.json','${{ runner.temp }}/f1-cloud-proof/*.png']);
  assert(!step.with.path.includes('private'));assert.equal(step.with['if-no-files-found'],'error');
  assert(!JSON.stringify(workflow).match(/pull_request_target|db reset|secrets set|stripe-webhooks|deploy-supabase/));
});

test('Validate PR runs all offline pilot contracts without manual readiness or credential environment',async()=>{
  const pr=YAML.parse(await readFile(new URL('../../.github/workflows/validate-pr.yml',import.meta.url),'utf8'));
  const step=Object.values(pr.jobs).flatMap(job=>job.steps??[]).find(x=>x.name==='Contrats du pilote documentaire F1 sans réseau ni credentials');
  assert(step);assert.equal(step.if,undefined);assert.equal(step.env,undefined);
  assert.equal(step.run,'node --test tests/node/f1-cloud-pilot.node.mjs tests/node/f1-cloud-adapter.node.mjs tests/node/f1-cloud-documents.node.mjs tests/node/f1-cloud-network.node.mjs tests/node/f1-cloud-workflow.node.mjs');
});
