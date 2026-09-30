import {test} from 'node:test';
import assert from 'node:assert/strict';
import{readFileSync}from'node:fs';
import{parse}from'yaml';
import{spawnSync}from'node:child_process';
const w=parse(readFileSync('.github/workflows/deploy-supabase-staging.yml','utf8'));
test('ancien input F true échoue avant toute étape bootstrap/DB, aucune exécution possible par le seed',()=>{
 const steps=w.jobs['bootstrap-staging'].steps;const guard=steps[0];assert.equal(guard.if,'inputs.seed_load_test_data');
 const run=spawnSync('bash',['-c',guard.run],{encoding:'utf8',env:{PATH:process.env.PATH}});assert.equal(run.status,1);assert.match(run.stdout,/Seed F historique interdit/);
 assert.equal(steps.some(s=>s.run?.includes('-f tests/load/seed/seed-staging.sql')),false);
 for(const file of ['seed-staging.sql','cleanup-staging.sql']){const sql=readFileSync('tests/load/seed/'+file,'utf8');assert.match(sql,/RAISE EXCEPTION/);assert.doesNotMatch(sql,/\b(?:INSERT|UPDATE|DELETE|TRUNCATE|DROP)\b/);}
});
test('D absent du raccord fixtures automatique et F conserve refus sans appel cron',()=>{
 const load=readFileSync('.github/workflows/load-tests.yml','utf8');assert.doesNotMatch(load,/prepare-candidatures-fixture/);
 const f=readFileSync('tests/load/scenarios/06-cron-weekly-invoicing.js','utf8');assert.match(f,/refuserScenarioNonIsole\('F'\)/);assert.doesNotMatch(f,/http\.post|functions\/v1/);
});
