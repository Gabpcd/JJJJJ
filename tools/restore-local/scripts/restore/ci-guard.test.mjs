import {test} from 'node:test';
import assert from 'node:assert/strict';
import {ciIdentity,requireExistingRefusal} from './ci-guard.mjs';
const head='a'.repeat(40);
const env={GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_RUN_ID:'1234567890',GITHUB_RUN_ATTEMPT:'1',GITHUB_SHA:head};
test('manual and PR identities are exact, monotonic attempts remain distinct, secrets excluded',()=>{
 const a=ciIdentity({...env,SECRET_CANARY:'SENSITIVE_VALUE'},head),b=ciIdentity({...env,GITHUB_EVENT_NAME:'pull_request',GITHUB_RUN_ATTEMPT:'2'},head);
 assert.equal(a.run,'jolene-restore-drill-1234567890-1');assert.notEqual(a.run,b.run);assert.ok(!JSON.stringify(a).includes('SENSITIVE'));
});
for(const [label,patch]of [['push',{GITHUB_EVENT_NAME:'push'}],['schedule',{GITHUB_EVENT_NAME:'schedule'}],['target',{GITHUB_EVENT_NAME:'pull_request_target'}],['repository',{GITHUB_REPOSITORY:'else/else'}],['head',{GITHUB_SHA:'b'.repeat(40)}],['run',{GITHUB_RUN_ID:'123; env'}],['attempt',{GITHUB_RUN_ATTEMPT:'0'}]])test('identity rejects '+label,()=>assert.throws(()=>ciIdentity({...env,...patch},head)));
test('negative start accepts only exact existing-resource refusal',()=>{
 const calls=[];const result=requireExistingRefusal('/tmp/unit',args=>{calls.push(args);throw Error('RESOURCES_ALREADY_EXIST')});assert.equal(result.result,'EXISTING_START_REFUSED');assert.deepEqual(calls,[['up','/tmp/unit']]);
 for(const error of ['DOCKER_COMMAND_FAILED','DOCKER_UNAVAILABLE','RESOURCES_ALREADY_EXIST secret_canary'])assert.throws(()=>requireExistingRefusal('/tmp/unit',()=>{throw Error(error)}),/UNEXPECTED_NEGATIVE_RESULT/);
 assert.throws(()=>requireExistingRefusal('/tmp/unit',()=>({result:'EMPTY_CORE_ONLY'})),/SECOND_START_WAS_NOT_REFUSED/);
});
