import { createHash } from 'node:crypto';
// Kept self-contained because only phase-b is mounted into the browser.
const A_STAGES = ['identity','units','plan','preload','preflight','up','inspect','extensions','import',
 'current_product_witness','source_api_restart','source_seed','object_readback','capture',
 'capture_checkpoint_before','capture_catalogue','capture_dump','capture_toc','capture_files','capture_checkpoint_after',
 'project_toc','source_off','complete','cleanup','absence'];
export const BRANCH = 'ci/restore-app-phase-b-20261004';
export const PRODUCT_SHA = '7dfdeb42f724a1d80f78318ecf468d248b321a68';
export const IMAGE = 'mcr.microsoft.com/playwright@sha256:65cefd09a5e943921ecd3a6e5414c603db2eb161e9eb48f2e2ccc63486dc7dc0';
export const LABEL = 'org.jolene.restore-drill';
export const DB = 'jolene_candidatures_pg17_test';
export const CODES = new Set(['B_IDENTITY','B_REVIEW','B_PIN','B_CONTEXT','B_CALL','B_BUILD','B_DISK','B_DATABASE_READINESS','B_DATABASE_READINESS_TIMEOUT','B_BROWSER','B_REPORT','B_RESTORE','B_SNAPSHOT','B_FILES','B_SENTINEL','B_CLEANUP','B_FAILED']);
export const STAGES = new Set([...A_STAGES,'dependencies','build','browser_source','sentinel','restore','browser_target','files_target','controlled_negative','complete']);
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export function requireValue(ok, code = 'B_CONTEXT') { if (!ok) { const error = new Error(CODES.has(code) ? code : 'B_FAILED'); error.code = error.message; throw error; } }
export function closedFailure(error, stage) { return { result:'PHASE_B_REFUSED',stage:STAGES.has(stage)?stage:'identity',
 code:CODES.has(error?.code)?error.code:'B_FAILED',sqlstate:/^[A-Z0-9]{5}$/.test(error?.diagnostic?.sqlstate??'')?error.diagnostic.sqlstate:null,
 sqlLine:Number.isSafeInteger(error?.diagnostic?.line)&&error.diagnostic.line>0&&error.diagnostic.line<1_000_000?error.diagnostic.line:null,
 restored:false,appVerified:false,readyForNationalLaunch:false }; }
export function assertReview(review) {
 requireValue(review?.productSha===PRODUCT_SHA && review?.approved===true && /^[a-f0-9]{40}$/.test(review.phaseAHarnessSha??'')
  && /^[1-9][0-9]{5,14}$/.test(review.phaseARunId??'') && /^[a-f0-9]{64}$/.test(review.nativeRestoreTocSha256??'')
  && review.nativeRoleSettingsReviewed===true && Number.isSafeInteger(review.native?.postgresVersionNum)
  && review.native.postgresVersionNum>=170000 && review.native.postgresVersionNum<180000
  && ['auth','storage'].every(key=>Number.isSafeInteger(review.native[key]?.count)&&review.native[key].count>0&&/^[a-f0-9]{64}$/.test(review.native[key].sha256)), 'B_REVIEW');
 return review;
}
export function assertNativeReview(result,review) {
 assertReview(review);
 requireValue(result?.result==='PHASE_A_NATIVE_CAPTURE_PASSED' && result.productSha===PRODUCT_SHA
  && result.toc?.normalizedSha256===review.nativeRestoreTocSha256 && result.native?.postgresVersionNum===review.native.postgresVersionNum
  && ['auth','storage'].every(key=>result.native[key]?.count===review.native[key].count&&result.native[key]?.sha256===review.native[key].sha256)
  && result.sourceStopped===true && result.targetNativeEmpty===true && result.targetFilesEmpty===true,'B_REVIEW');
}
const CASES=['RESTORE_OWNER_S','RESTORE_OWNER_E','RESTORE_OTHER_S','RESTORE_OTHER_E','RESTORE_ANONYMOUS'];
const PROJECTS=['ipad-portrait','ipad-paysage','iphone','android','ordinateur'];
const OUTCOMES=['expected','unexpected','flaky','skipped'];
const STATUSES=['passed','failed','timedOut','skipped','interrupted'];
const RESULT_CODES=['PASSED','TEST_FAILED','TIMEOUT','SKIPPED','INTERRUPTED'];
export function validateBrowserReceipt(value,side) {
 requireValue(['source','target'].includes(side)&&value?.schemaVersion===1&&value.productSha===PRODUCT_SHA,'B_REPORT');
 if(value.complete!==true)return {schemaVersion:1,productSha:PRODUCT_SHA,side,complete:false,passed:false,code:'B_REPORT'};
 const expected=new Set((side==='source'?CASES.slice(0,2):CASES).flatMap(id=>(side==='source'?['ordinateur']:PROJECTS).map(p=>id+':'+p)));
 requireValue(value.side===side&&value.expectedCount===expected.size&&typeof value.passed==='boolean'
  &&Number.isSafeInteger(value.globalErrorCount)&&value.globalErrorCount>=0&&value.globalErrorCount<=1000
  &&Array.isArray(value.tests)&&value.tests.length===expected.size,'B_REPORT');
 const counts=Object.fromEntries(OUTCOMES.map(key=>[key,0]));
 const tests=value.tests.map(item=>{
  const pair=item.caseId+':'+item.project;
  requireValue(expected.delete(pair)&&OUTCOMES.includes(item.outcome)&&Array.isArray(item.attempts)&&item.attempts.length===1,'B_REPORT');
  const result=item.attempts[0];requireValue(STATUSES.includes(result.status)&&RESULT_CODES.includes(result.code)&&result.retry===0,'B_REPORT');
  requireValue((item.outcome==='expected')===(result.status==='passed'),'B_REPORT');counts[item.outcome]++;
  return {caseId:item.caseId,project:item.project,outcome:item.outcome,attempts:[{status:result.status,code:result.code,retry:0}]};
 });
 requireValue(expected.size===0&&OUTCOMES.every(key=>value.counts?.[key]===counts[key]),'B_REPORT');
 const passed=value.globalErrorCount===0&&counts.expected===tests.length&&OUTCOMES.slice(1).every(k=>counts[k]===0);
 requireValue(value.passed===passed,'B_REPORT');
 return {schemaVersion:1,productSha:PRODUCT_SHA,side,complete:true,passed,expectedCount:tests.length,counts,globalErrorCount:value.globalErrorCount,tests};
}
