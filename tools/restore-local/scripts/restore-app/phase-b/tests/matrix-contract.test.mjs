import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { CASE_IDS, PROJECT_IDS, assertRestoreMatrix } from '../matrix-contract.mjs';
import { browserArguments } from '../browser-entry.mjs';

function fixture(side = 'target') {
  const cases = side === 'source' ? CASE_IDS.slice(0, 2) : CASE_IDS;
  const projects = side === 'source' ? ['ordinateur'] : PROJECT_IDS;
  const specs = cases.map(title => ({ title, tests: projects.map(projectName => ({ projectName })) }));
  return { raw: { suites: [{ specs }] }, projected: specs.flatMap(spec => spec.tests.map(result => ({
    file: 'e2e/restore-app.spec.ts', line: 86, column: 1, project: result.projectName,
    expectedStatus: 'passed', outcome: 'expected', attempts: [{ retry: 0, status: 'passed' }],
  }))) };
}
const refused = action => assert.throws(action, error => error.message === 'RESTORE_REPORT_MATRIX');

test('target requires and identifies all 25 distinct case/format pairs even with shared source lines', () => {
  const { raw, projected } = fixture();
  const identified = assertRestoreMatrix(raw, projected, 'target');
  assert.equal(identified.length, 25);
  assert.equal(new Set(identified.map(result => result.caseId + ':' + result.project)).size, 25);
  assert.deepEqual([...new Set(identified.map(result => result.caseId))], CASE_IDS);
});

test('duplicate replacing a missing pair is refused despite 25 passed records', () => {
  const { raw, projected } = fixture();
  raw.suites[0].specs[4].tests[4].projectName = 'iphone';
  projected[24].project = 'iphone';
  assert.equal(projected.length, 25);
  refused(() => assertRestoreMatrix(raw, projected, 'target'));
});

test('repeated actor with another actor missing is refused despite 25 records and shared lines', () => {
  const { raw, projected } = fixture();
  raw.suites[0].specs[1].title = CASE_IDS[0];
  refused(() => assertRestoreMatrix(raw, projected, 'target'));
});

test('unknown case and format refuse with constant error and no private canary', () => {
  const canary = randomBytes(24).toString('hex');
  for (const kind of ['title', 'project']) {
    const { raw, projected } = fixture();
    if (kind === 'title') raw.suites[0].specs[0].title = canary;
    else { raw.suites[0].specs[0].tests[0].projectName = canary; projected[0].project = canary; }
    let error;
    try { assertRestoreMatrix(raw, projected, 'target'); } catch (caught) { error = caught; }
    assert.equal(error?.message, 'RESTORE_REPORT_MATRIX');
    assert.equal(String(error).includes(canary), false);
    assert.equal(JSON.stringify(error).includes(canary), false);
  }
});

test('missing pair and raw/projected project disagreement each refuse', () => {
  const missing = fixture(); missing.raw.suites[0].specs[0].tests.pop(); missing.projected.splice(4, 1);
  refused(() => assertRestoreMatrix(missing.raw, missing.projected, 'target'));
  const mismatch = fixture(); mismatch.projected[0].project = 'ordinateur';
  refused(() => assertRestoreMatrix(mismatch.raw, mismatch.projected, 'target'));
});

test('source accepts exactly the two owners on desktop, never a duplicate or target pair', () => {
  const { raw, projected } = fixture('source');
  assert.deepEqual(assertRestoreMatrix(raw, projected, 'source').map(result => result.caseId), CASE_IDS.slice(0, 2));
  raw.suites[0].specs[1].title = CASE_IDS[0];
  refused(() => assertRestoreMatrix(raw, projected, 'source'));
  const wrong = fixture('source'); wrong.raw.suites[0].specs[1].tests[0].projectName = 'iphone'; wrong.projected[1].project = 'iphone';
  refused(() => assertRestoreMatrix(wrong.raw, wrong.projected, 'source'));
});

// Actual Playwright 1.58.2 _grepTitleWithTags shape for the pinned source project.
const fullSourceTitle = caseId => `ordinateur restore-app.spec.ts ${caseId}`;
function selectedBySource(titles) {
  const args = browserArguments('source');
  const selectors = args.filter(value => value.startsWith('--grep='));
  assert.equal(selectors.length, 1);
  const expression = new RegExp(selectors[0].slice('--grep='.length), 'gi');
  return titles.filter(title => { expression.lastIndex = 0; return expression.test(title); });
}

test('source CLI selects the two owners from complete Playwright titles', () => {
  const args = browserArguments('source');
  assert.deepEqual(args.filter(value => value.startsWith('--project=')), ['--project=ordinateur']);
  assert.deepEqual(selectedBySource(CASE_IDS.map(fullSourceTitle)), CASE_IDS.slice(0, 2).map(fullSourceTitle));
  const { raw, projected } = fixture('source');
  assert.equal(assertRestoreMatrix(raw, projected, 'source').length, 2);
});

test('source CLI rejects extra owner-like titles and target retains all 25 cases', () => {
  const extra = ['RESTORE_OWNER_ADMIN', 'RESTORE_OWNER_SS', 'NOT_RESTORE_OWNER_S',
    'RESTORE_OWNER_S_EXTRA', 'RESTORE_OWNER_S extra', ...CASE_IDS.slice(2)];
  assert.deepEqual(selectedBySource(extra.map(fullSourceTitle)), []);
  const args = browserArguments('target');
  assert.equal(args.some(value => value.startsWith('--grep=') || value.startsWith('--project=')), false);
  const { raw, projected } = fixture('target');
  assert.equal(assertRestoreMatrix(raw, projected, 'target').length, 25);
  assert.throws(() => browserArguments('other'), error => error.code === 'B_BROWSER');
});

test('source matrix still refuses an empty or surplus selection', () => {
  refused(() => assertRestoreMatrix({ suites: [{ specs: [] }] }, [], 'source'));
  const { raw, projected } = fixture('source');
  raw.suites[0].specs.push({ title: 'RESTORE_OTHER_S', tests: [{ projectName: 'ordinateur' }] });
  projected.push({ ...projected[0] });
  refused(() => assertRestoreMatrix(raw, projected, 'source'));
});

import { PRODUCT_SHA, UI_STAGES, projectBrowserDiagnostic, projectBrowserDiagnostics,
  validateBrowserDiagnostic, validateBrowserReceipt } from '../contract.mjs';
import { browserAttempt } from '../browser-entry.mjs';
const rawAttempt=(status='failed',steps=[])=>({status,retry:0,duration:90_000,errors:[],steps});
const step=(title,error)=>({title,duration:12,...(error?{error:{message:error}}:{})});

test('closed UI stages preserve the first failed action before later cleanup failure',()=>{
 const raw=rawAttempt('timedOut',[step('BEFORE_EACH'),step('LOGIN_NAVIGATE'),step('LOGIN_EMAIL','PRIVATE_A'),step('AFTER_EACH','PRIVATE_B')]);
 const value=projectBrowserDiagnostic(raw);
 assert.deepEqual(value,{schemaVersion:1,stage:'LOGIN_EMAIL',stageSource:'STEP',code:'TIMEOUT',
  lastCompletedStage:'LOGIN_NAVIGATE',completedStages:['BEFORE_EACH','LOGIN_NAVIGATE'],durationMs:90_000});
 assert.equal(JSON.stringify(value).includes('PRIVATE_'),false);
});

test('closed UI stages choose a failing nested stage before its failed wrapper',()=>{
 const raw=rawAttempt('failed',[{...step('BEFORE_EACH','OUTER'),steps:[step('LOGIN_NAVIGATE','INNER')]},step('AFTER_EACH','LATER')]);
 assert.equal(projectBrowserDiagnostic(raw).stage,'LOGIN_NAVIGATE');
});

test('all five statuses keep their original code and never make a failed or skipped UI pass',()=>{
 for(const [status,code] of [['passed','PASSED'],['failed','TEST_FAILED'],['timedOut','TIMEOUT'],['skipped','SKIPPED'],['interrupted','INTERRUPTED']]) {
  const value=projectBrowserDiagnostic(rawAttempt(status,status==='passed'?[step('BEFORE_EACH'),step('LOGIN_NAVIGATE')]:[]));
  assert.equal(value.code,code);
  assert.equal(value.stage,['failed','timedOut','interrupted'].includes(status)?'UNKNOWN':null);
  assert.equal(value.stageSource,status==='skipped'?'NOT_EXECUTED':status==='passed'?'NO_FAILURE':'UNLOCATED');
  assert.deepEqual(validateBrowserDiagnostic(value,status),value);
 }
});

test('exact pinned Playwright fixture timeout messages reveal only a fixed setup stage',()=>{
 for(const fixture of ['browser','context','page'])for(const message of [
  `Test timeout of 90000ms exceeded while setting up "${fixture}".`,
  `Fixture "${fixture}" timeout of 90000ms exceeded during setup.`]) {
  const value=projectBrowserDiagnostic({...rawAttempt('timedOut'),error:{message:'\x1b[31m'+message+'\x1b[39m',stack:'PRIVATE_STACK'}});
  assert.equal(value.stage,'FIXTURE_'+fixture.toUpperCase());assert.equal(value.stageSource,'FIXTURE_TIMEOUT');
  assert.equal(JSON.stringify(value).includes('PRIVATE_STACK'),false);
 }
});

test('unknown fixture names, timeout values, appended private messages and stacks remain unlocated',()=>{
 for(const message of [
  'Test timeout of 90000ms exceeded while setting up "PRIVATE_EMAIL".',
  'Test timeout of 12345ms exceeded while setting up "page".',
  'Fixture "page" timeout of 90000ms exceeded during teardown.',
  'Test timeout of 90000ms exceeded while setting up "page". PRIVATE_TOKEN',
  'Test timeout of 90000ms exceeded while setting up "page".\nPRIVATE_TOKEN']) {
  const value=projectBrowserDiagnostic({...rawAttempt('timedOut'),error:{message,stack:'Test timeout of 90000ms exceeded while setting up "browser".'}});
  assert.equal(value.stage,'UNKNOWN');assert.equal(value.stageSource,'UNLOCATED');assert.equal(JSON.stringify(value).includes('PRIVATE_'),false);
 }
});

test('arbitrary step titles and payloads never escape while an unknown first error stays first',()=>{
 const canary=randomBytes(24).toString('hex');
 const raw={...rawAttempt('failed',[{...step(canary,canary),url:'https://'+canary,body:canary,location:{file:canary,line:5}},step('AFTER_EACH',canary)]),
  stdout:[{text:canary}],stderr:[{text:canary}],attachments:[{body:canary}],error:{message:canary,stack:canary}};
 const value=projectBrowserDiagnostic(raw);
 assert.equal(value.stage,'UNKNOWN');assert.equal(value.stageSource,'STEP');assert.equal(JSON.stringify(value).includes(canary),false);
 const closed=validateBrowserDiagnostic({...value,message:canary,stack:canary,url:canary},'failed');
 assert.deepEqual(closed,value);assert.equal(JSON.stringify(closed).includes(canary),false);
});

test('bounded UI projection refuses oversized or malformed trees and invalid statuses with a fixed code',()=>{
 const tooDeep=step('BEFORE_EACH');let cursor=tooDeep;for(let i=0;i<18;i++){cursor.steps=[step('BEFORE_EACH')];cursor=cursor.steps[0];}
 for(const raw of [{...rawAttempt(),status:'PRIVATE'}, {...rawAttempt(),duration:Infinity}, {...rawAttempt(),duration:-1},
  rawAttempt('failed',Array.from({length:2049},()=>step('BEFORE_EACH'))),rawAttempt('failed',[tooDeep]),rawAttempt('failed',[null]),
  rawAttempt('failed',[{...step('BEFORE_EACH'),steps:{private:'CANARY'}}])]) {
  assert.throws(()=>projectBrowserDiagnostic(raw),e=>e.code==='B_REPORT'&&e.message==='B_REPORT');
 }
 const value=projectBrowserDiagnostic(rawAttempt());
 for(const edit of [{stage:'PRIVATE'},{completedStages:['PRIVATE']},{code:'PASSED'},{durationMs:NaN},{lastCompletedStage:'LOGIN_EMAIL'},
  {stage:'LOGIN_EMAIL',stageSource:'FIXTURE_TIMEOUT'},{stage:null,stageSource:'UNLOCATED'}]) {
  assert.throws(()=>validateBrowserDiagnostic({...value,...edit},'failed'),e=>e.code==='B_REPORT');
 }
});

function diagnosticMatrix(status='timedOut') {
 const rawCases=CASE_IDS.slice(0,2).map((title,index)=>({title,tests:[{projectName:'ordinateur',results:[rawAttempt(index?'skipped':status,
  index?[]:[step('BEFORE_EACH'),step('LOGIN_NAVIGATE',status==='passed'?undefined:'PRIVATE')])]}]}));
 const identified=rawCases.map(spec=>({caseId:spec.title,project:'ordinateur',attempts:[{status:spec.tests[0].results[0].status,retry:0,code:spec.tests[0].results[0].status==='skipped'?'SKIPPED':status==='passed'?'PASSED':'TIMEOUT'}]}));
 return {raw:{suites:[{specs:rawCases}]},identified};
}

test('diagnostics bind to the exact same case project status and single attempt as the matrix',()=>{
 const {raw,identified}=diagnosticMatrix();
 assert.deepEqual(projectBrowserDiagnostics(raw,identified).map(v=>v.stage),['LOGIN_NAVIGATE',null]);
 for(const mutate of [h=>h.raw.suites[0].specs[0].title='RESTORE_OWNER_E',h=>h.identified[0].project='iphone',
  h=>h.identified[0].attempts[0].status='passed',h=>h.raw.suites[0].specs[0].tests[0].results.push(rawAttempt()),
  h=>h.raw.suites[0].specs[0].tests[0].results[0].retry=1,h=>h.identified.pop()]) {
  const h=diagnosticMatrix();mutate(h);assert.throws(()=>projectBrowserDiagnostics(h.raw,h.identified),e=>e.code==='B_REPORT');
 }
});

test('actual browser attempt seam and public receipt keep B8 diagnostics without changing B7 failure',()=>{
 const {raw,identified}=diagnosticMatrix();const diagnostics=projectBrowserDiagnostics(raw,identified);
 const tests=identified.map((item,index)=>({caseId:item.caseId,project:item.project,outcome:index?'skipped':'unexpected',
  attempts:item.attempts.map(attempt=>browserAttempt(attempt,diagnostics[index]))}));
 const value={schemaVersion:1,productSha:PRODUCT_SHA,side:'source',complete:true,passed:false,expectedCount:2,
  counts:{expected:0,unexpected:1,flaky:0,skipped:1},globalErrorCount:2,tests};
 assert.deepEqual(value.tests[0].attempts[0].diagnostic,diagnostics[0]);
 const publicValue=validateBrowserReceipt(value,'source');
 assert.deepEqual(publicValue,value);assert.equal(publicValue.passed,false);
 assert.equal(publicValue.tests[0].attempts[0].diagnostic.stage,'LOGIN_NAVIGATE');
 assert.equal(publicValue.tests[1].attempts[0].diagnostic.stageSource,'NOT_EXECUTED');
 assert.equal(JSON.stringify(publicValue).includes('PRIVATE'),false);
});

test('fixed diagnostic stage inventory includes every literal test.step and no extra test case',async()=>{
 const {readFileSync}=await import('node:fs');const spec=readFileSync(new URL('../e2e/restore-app.spec.ts',import.meta.url),'utf8');
 const literals=[...spec.matchAll(/test\.step\('([A-Z_]+)'/g)].map(m=>m[1]);
 assert.ok(literals.length>=20);assert.ok(literals.every(stage=>UI_STAGES.includes(stage)));
 assert.deepEqual([...new Set(literals)].sort(),[...UI_STAGES].sort());
 assert.equal((spec.match(/test\.step\(/g)||[]).length,literals.length);
 assert.equal(/test\.(skip|fixme|only)|test\.setTimeout|timeout\s*:/.test(spec),false);
});

// Structured reporter fixtures are pure: CI units run before dependency installation.
const structuredStep=(category,title,steps=[],error,duration=12)=>({category,title,steps,duration,
 ...(error?{error:{message:error}}:{})});
const reporterResult=(status,steps)=>({...rawAttempt(status,steps),workerIndex:0,parallelIndex:0,
 stdout:[],stderr:[],attachments:[],annotations:[],startTime:new Date('2026-10-05T00:00:00.000Z')});
const closedResult=result=>({...result,closedDiagnostic:projectBrowserDiagnostic(result)});

test('structured fixture failure retains only a fixed preparation stage',()=>{
 const raw=reporterResult('timedOut',[structuredStep('hook','Before Hooks',[
  structuredStep('fixture','Fixture "browser"',[], 'PRIVATE_BROWSER')], 'PRIVATE_HOOK')]);
 const value=projectBrowserDiagnostic(raw);
 assert.equal(value.stage,'FIXTURE_BROWSER');assert.equal(value.stageSource,'STEP');
 assert.equal(JSON.stringify(value).includes('PRIVATE'),false);
});

test('structured projection preserves hook children and first body failure over teardown',()=>{
 const hook=structuredStep('hook','Before Hooks',[structuredStep('hook','beforeEach',[
  structuredStep('test.step','BEFORE_EACH',[], 'PRIVATE')],'PRIVATE')],'PRIVATE');
 const raw=reporterResult('failed',[hook]);
 assert.equal(closedResult(raw).closedDiagnostic.stage,'BEFORE_EACH');
 const sequence=reporterResult('failed',[
  structuredStep('hook','Before Hooks',[structuredStep('fixture','Fixture "page"')]),
  structuredStep('test.step','LOGIN_NAVIGATE'),
  structuredStep('test.step','LOGIN_EMAIL',[structuredStep('pw:api','PRIVATE_URL',[],'PRIVATE')],'PRIVATE'),
  structuredStep('hook','After Hooks',[structuredStep('test.step','AFTER_EACH',[],'PRIVATE')],'PRIVATE')]);
 const value=closedResult(sequence).closedDiagnostic;
 assert.equal(value.stage,'LOGIN_EMAIL');assert.equal(value.lastCompletedStage,'LOGIN_NAVIGATE');
 assert.equal(JSON.stringify(value).includes('PRIVATE'),false);
});

test('unfinished structured steps retain the first stage and do not become B_REPORT',()=>{
 const raw=reporterResult('timedOut',[
  structuredStep('test.step','LOGIN_NAVIGATE'),
  structuredStep('test.step','LOGIN_EMAIL',[structuredStep('pw:api','PRIVATE_URL',[],undefined,-1)],undefined,-1),
  structuredStep('hook','After Hooks',[], 'SECONDARY_PRIVATE')]);
 const value=closedResult(raw).closedDiagnostic;
 assert.equal(value.stage,'LOGIN_EMAIL');assert.equal(value.stageSource,'INCOMPLETE_STEP');
 assert.deepEqual(value.completedStages,['LOGIN_NAVIGATE']);assert.equal(value.code,'TIMEOUT');
});

test('fixture teardown and worker cleanup use closed stages while successful hooks stay descriptive',()=>{
 for(const hook of ['After Hooks','Worker Cleanup']) {
  const raw=reporterResult('failed',[structuredStep('hook',hook,[structuredStep('fixture','Fixture "page"',[],'PRIVATE')],'PRIVATE')]);
  assert.equal(closedResult(raw).closedDiagnostic.stage,'FIXTURE_TEARDOWN');
 }
 assert.equal(closedResult(reporterResult('failed',[structuredStep('hook','Worker Cleanup',[],'PRIVATE')])).closedDiagnostic.stage,'WORKER_CLEANUP');
 const complete=closedResult(reporterResult('passed',[
  structuredStep('hook','Before Hooks',[structuredStep('fixture','Fixture "browser"'),structuredStep('fixture','Fixture "context"'),structuredStep('fixture','Fixture "page"'),structuredStep('test.step','BEFORE_EACH')]),
  structuredStep('test.step','LOGIN_NAVIGATE'),structuredStep('hook','After Hooks',[structuredStep('test.step','AFTER_EACH')])])).closedDiagnostic;
 assert.equal(complete.code,'PASSED');assert.equal(complete.stage,null);assert.equal(complete.stageSource,'NO_FAILURE');
 assert.equal(complete.lastCompletedStage,'AFTER_HOOKS');
 assert.equal(closedResult(reporterResult('skipped',[])).closedDiagnostic.stageSource,'NOT_EXECUTED');
});

test('closed reporter output survives the exact bound receipt path and strips hostile extra fields',()=>{
 const canary=randomBytes(24).toString('hex');const {raw,identified}=diagnosticMatrix();
 const attempt=closedResult(reporterResult('timedOut',[structuredStep('hook','Before Hooks',[
  structuredStep('fixture','Fixture "context"',[],canary)],canary)]));
 raw.suites[0].specs[0].tests[0].results[0]=attempt;
 attempt.closedDiagnostic.message=canary;attempt.closedDiagnostic.url=canary;attempt.closedDiagnostic.stack=canary;
 const [value]=projectBrowserDiagnostics(raw,identified);
 assert.equal(value.stage,'FIXTURE_CONTEXT');assert.equal(JSON.stringify(value).includes(canary),false);
 assert.equal(JSON.stringify(browserAttempt(identified[0].attempts[0],value)).includes(canary),false);
 attempt.closedDiagnostic.stage=canary;
 assert.throws(()=>projectBrowserDiagnostics(raw,identified),e=>e.code==='B_REPORT');
});

test('unnamed fixture and empty hook failures retain distinct fixed preparation stages',()=>{
 for(const [raw,expected] of [
  [structuredStep('hook','Before Hooks',[],'PRIVATE'),'BEFORE_HOOKS'],
  [structuredStep('hook','After Hooks',[],'PRIVATE'),'AFTER_HOOKS'],
  [structuredStep('hook','Before Hooks',[structuredStep('fixture','PRIVATE_FIXTURE',[],'PRIVATE')],'PRIVATE'),'FIXTURE_OTHER']]) {
  const value=projectBrowserDiagnostic(reporterResult('failed',[raw]));
  assert.equal(value.stage,expected);assert.equal(JSON.stringify(value).includes('PRIVATE'),false);
 }
});
