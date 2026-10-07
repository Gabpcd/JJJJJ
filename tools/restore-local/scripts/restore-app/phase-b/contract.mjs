import { projectCatalogueAnchors } from './catalogue-anchor-diagnostic.mjs';
import { projectCatalogueFactsDiagnostic } from './catalogue-facts-diagnostic.mjs';
import { projectCatalogueSemanticsDiagnostic } from './catalogue-semantics-diagnostic.mjs';
import { projectCatalogueParityV2,projectCatalogueBindingDiagnostic } from './catalogue-parity-v2.mjs';
import { projectB21WitnessFailure } from './catalogue-semantics-witness.mjs';
import { projectGraphqlSchemaDelta } from './graphql-schema-diagnostic.mjs';
import { createHash } from 'node:crypto';
// Kept self-contained because only phase-b is mounted into the browser.
const A_STAGES = ['identity','units','plan','preload','preflight','up','inspect','extensions','import',
 'current_product_witness','source_api_restart','source_seed','object_readback','capture',
 'capture_checkpoint_before','capture_catalogue','capture_dump','capture_toc','capture_files','capture_checkpoint_after',
 'project_toc','source_off','complete','cleanup','absence'];
export const BRANCH = 'ci/restore-app-phase-b-20261004';
export const PRODUCT_SHA = '58968a0e42d65b90d0c8916479149326635a390e';
export const IMAGE = 'mcr.microsoft.com/playwright@sha256:65cefd09a5e943921ecd3a6e5414c603db2eb161e9eb48f2e2ccc63486dc7dc0';
export const LABEL = 'org.jolene.restore-drill';
export const DB = 'jolene_candidatures_pg17_test';
export const CODES = new Set(['B_IDENTITY','B_REVIEW','B_PIN','B_CONTEXT','B_CALL','B_BUILD','B_DISK','B_DATABASE_READINESS','B_DATABASE_READINESS_TIMEOUT','B_BROWSER','B_REPORT','B_RESTORE','B_GRAPHQL_RESTORE_REFUSED','B_SEMANTICS_WITNESS','B_SNAPSHOT','B_FILES','B_SENTINEL','B_CLEANUP','B_FAILED']);
export const STAGES = new Set([...A_STAGES,'dependencies','semantics_witnesses','build','browser_source','sentinel','restore','browser_target','files_target','controlled_negative','complete']);
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export function requireValue(ok, code = 'B_CONTEXT') { if (!ok) { const error = new Error(CODES.has(code) ? code : 'B_FAILED'); error.code = error.message; throw error; } }
// Keep the existing refusal and boolean intact; diagnostics never decide a pass.
export function requireRestoreInvariant(ok, reason, diagnostic) {
 if(ok)return;
 try { requireValue(false,'B_RESTORE'); } catch(error) {
  let catalogue;try { catalogue=diagnostic?.(); } catch { catalogue={status:'INVALID_SHAPE'}; }
  error.restoreInvariant=projectRestoreInvariant({reason,catalogue});throw error;
 }
}
export const RESTORE_CALL_OPERATIONS = Object.freeze(['TARGET_ARCHIVE_TOC_READ','TARGET_TOC_WRITE','TARGET_TOC_READBACK','TARGET_ARCHIVE_SQL_EXPORT','TARGET_TOC_REMOVE',
 'TARGET_DATABASE_RECREATE','TARGET_SQL_RESTORE','TARGET_ROLE_SETTINGS','TARGET_FILES_COPY_IN','TARGET_ARCHIVE_RESTORE']);
const RESTORE_SIGNALS = new Set(['SIGTERM','SIGKILL','SIGINT','SIGABRT','SIGSEGV','SIGBUS','SIGPIPE']);
const RESTORE_SYSTEM_ERRORS = new Set(['ETIMEDOUT','ENOENT','EACCES','EPERM','ENOMEM','ENOBUFS','E2BIG','EAGAIN','ENOEXEC']);
export const PG_RESTORE_CATEGORIES = Object.freeze(['UNKNOWN','SQL_OTHER','OBJECT_EXISTS','OBJECT_MISSING',
 'PERMISSION_DENIED','OWNER_REQUIRED','ROLE_REQUIRED','SUPERUSER_REQUIRED','EXTENSION_UNAVAILABLE',
 'EXTENSION_LIBRARY','EXTENSION_PREREQUISITE','TRANSACTION_RESTRICTION','CONFIGURATION',
 'CONSTRAINT','DATA','DEPENDENCY','RESOURCE','CONNECTION','ARCHIVE_FORMAT','ARCHIVE_READ']);
export const PG_RESTORE_COMMANDS = Object.freeze(['UNKNOWN','SET','SELECT','BEGIN','COMMIT','COPY','INSERT',
 'CREATE_SCHEMA','CREATE_EXTENSION','CREATE_TABLE','CREATE_SEQUENCE','CREATE_FUNCTION','CREATE_TYPE',
 'CREATE_INDEX','CREATE_VIEW','CREATE_TRIGGER','CREATE_EVENT_TRIGGER','CREATE_POLICY','CREATE_PUBLICATION',
 'ALTER','GRANT','REVOKE','COMMENT','SECURITY_LABEL','DO']);
export const PG_RESTORE_SCHEMAS = Object.freeze(['auth','storage','public','extensions','pg_catalog','cron',
 'graphql','graphql_public','pgbouncer','private','supabase_functions','vault','realtime','net']);
export const PG_RESTORE_EXTENSIONS = Object.freeze(['pg_cron','pg_graphql','pg_net','pg_stat_statements','pg_trgm',
 'pgcrypto','pgjwt','plpgsql','supabase_vault','uuid-ossp']);
export const PG_RESTORE_MISSING_OBJECTS = Object.freeze(['SCHEMA','RELATION','TYPE','FUNCTION','ROLE','EXTENSION','OPERATOR','COLLATION']);
// Fixed roles referenced by the reviewed bootstrap/product; unknown names stay private.
export const PG_RESTORE_ROLES = Object.freeze(['postgres','supabase_admin','anon','authenticated','service_role',
 'authenticator','pgbouncer','supabase_auth_admin','supabase_functions_admin','supabase_storage_admin']);
export function projectPgRestoreDiagnostic(value) {
 const missing=value?.parser==='FIRST_ERROR'&&value?.category==='OBJECT_MISSING';
 const missingObjectType=missing&&PG_RESTORE_MISSING_OBJECTS.includes(value?.missingObjectType)?value.missingObjectType:null;
 return {schemaVersion:1,parser:['FIRST_ERROR','NO_PRIMARY_ERROR','EMPTY','INVALID_INPUT'].includes(value?.parser)?value.parser:'INVALID_INPUT',
  inputTruncated:value?.inputTruncated===true,
  category:PG_RESTORE_CATEGORIES.includes(value?.category)?value.category:'UNKNOWN',
  command:PG_RESTORE_COMMANDS.includes(value?.command)?value.command:'UNKNOWN',
  schema:PG_RESTORE_SCHEMAS.includes(value?.schema)?value.schema:null,
  extension:PG_RESTORE_EXTENSIONS.includes(value?.extension)?value.extension:null,
  missingObjectType,missingRole:missingObjectType==='ROLE'&&PG_RESTORE_ROLES.includes(value?.missingRole)?value.missingRole:null};
}
// Diagnostic only: no arguments, SQL, paths, stderr, stdout or dump bytes.
export function projectRestoreCall(value) {
 const systemError=value?.systemError===null?null:RESTORE_SYSTEM_ERRORS.has(value?.systemError)?value.systemError:'OTHER';
 return {schemaVersion:1,operation:RESTORE_CALL_OPERATIONS.includes(value?.operation)?value.operation:'UNKNOWN',
  exitCode:Number.isInteger(value?.exitCode)&&value.exitCode>=0&&value.exitCode<=255?value.exitCode:null,
  signal:value?.signal===null?null:RESTORE_SIGNALS.has(value?.signal)?value.signal:'OTHER',
  systemError,timedOut:systemError==='ETIMEDOUT',
  ...(['TARGET_ARCHIVE_RESTORE','TARGET_ARCHIVE_TOC_READ','TARGET_ARCHIVE_SQL_EXPORT'].includes(value?.operation)&&value?.pgRestore?{pgRestore:projectPgRestoreDiagnostic(value.pgRestore)}:{})};
}
// GraphQL refusal diagnostics contain constants only; all catalogue/TOC values stay private.
export const GRAPHQL_WITNESS_FLAGS = Object.freeze([
 'context','nativeExtensionExact','wrapperSignatureExact','wrapperBodyExact','wrapperMembershipExact',
 'wrapperOwnerExact','hookSignatureExact','hookBodyExact','hookOwnerExact','hookNotExtensionMember',
 'triggerExact','schemaOwnersExact','defaultFunctionAclExact','noGlobalFunctionDefaultAcl',
]);
export const GRAPHQL_COMPONENTS = Object.freeze(['wrapper','hook','extension','trigger','initial_privileges',
 'default_acl','schema_extensions','schema_graphql_public','schema_graphql']);
export const GRAPHQL_COMPONENT_LABELS = Object.freeze({wrapper:'WRAPPER_DEFINITION_AND_ACL',hook:'HOOK_DEFINITION_AND_ACL',
 extension:'EXTENSION_METADATA',trigger:'TRIGGER_METADATA',initial_privileges:'INITIAL_PRIVILEGES',
 default_acl:'DEFAULT_PRIVILEGES',schema_extensions:'HOOK_SCHEMA_RIGHTS',schema_graphql_public:'WRAPPER_SCHEMA_RIGHTS',
 schema_graphql:'EXTENSION_SCHEMA_RIGHTS'});
export const RESTORE_INVARIANT_REASONS=Object.freeze(['PREPARE_SINGLE_USE','EXPORT_PARTITION',
 'TOC_READBACK_BEFORE_EXPORT','TOC_READBACK_AFTER_EXPORT','DATABASE_RECREATE_TOKEN','RESTORE_PREPARED_TOKEN',
 'CHECKPOINT_BEFORE_API','CATALOGUE_PARITY','CATALOGUE_V2_RESULT','GRAPHQL_RESULT','CHECKPOINT_AFTER_API','RESTORE_RESULT']);
export const RESTORE_CATALOGUE_FIELDS=Object.freeze(['catalogue_sha256','database','roles','memberships','databaseRoleSettings','nativeGraphql']);
export const RESTORE_CATALOGUE_SECTIONS=Object.freeze([...RESTORE_CATALOGUE_FIELDS,'OTHER_FIELDS','FIELD_ORDER']);
export const RESTORE_NATIVE_GRAPHQL_FIELDS=Object.freeze(['schemaVersion',...GRAPHQL_WITNESS_FLAGS,
 'initialPrivilegesCount','fingerprint','components','wrapperSchemaInitialPrivileges']);
const restorePlain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const restoreKeys=(v,keys)=>restorePlain(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
export function catalogueRestoreDiagnostic(source,target,facts,semantics,comparison,anchors,bindings) {
 if(!restorePlain(source)||!restorePlain(target))return {status:'INVALID_SHAPE'};
 const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
 const sections=RESTORE_CATALOGUE_FIELDS.filter(k=>!equal(source[k],target[k]));
 const other=v=>Object.entries(v).filter(([k])=>!RESTORE_CATALOGUE_FIELDS.includes(k));
 if(!equal(other(source),other(target)))sections.push('OTHER_FIELDS');
 if(!equal(Object.keys(source),Object.keys(target)))sections.push('FIELD_ORDER');
 const nativeGraphqlFields=Object.fromEntries(RESTORE_NATIVE_GRAPHQL_FIELDS.map(k=>[k,equal(source.nativeGraphql?.[k],target.nativeGraphql?.[k])]));
 return {status:'COMPLETE',sections,...(sections.includes('nativeGraphql')?{nativeGraphqlFields}:{}),
  ...(facts===undefined?{}:{facts:projectCatalogueFactsDiagnostic(facts)}),
  ...(semantics===undefined?{}:{semantics:projectCatalogueSemanticsDiagnostic(semantics)}),
  ...(comparison===undefined?{}:{comparison:projectCatalogueParityV2(comparison)}),
  ...(anchors===undefined?{}:{anchors:projectCatalogueAnchors(anchors)}),
  ...(bindings===undefined?{}:{bindings:projectCatalogueBindingDiagnostic(bindings)})};
}
export function projectRestoreInvariant(value) {
 const reason=RESTORE_INVARIANT_REASONS.includes(value?.reason)?value.reason:'UNKNOWN';
 const result={schemaVersion:1,reason};
 if(reason!=='CATALOGUE_PARITY')return result;
 const c=value?.catalogue,hasNative=Array.isArray(c?.sections)&&c.sections.includes('nativeGraphql'),hasFacts=restorePlain(c)&&Object.hasOwn(c,'facts'),hasSemantics=restorePlain(c)&&Object.hasOwn(c,'semantics');
 const hasComparison=restorePlain(c)&&Object.hasOwn(c,'comparison'),hasAnchors=restorePlain(c)&&Object.hasOwn(c,'anchors');
 const hasBindings=restorePlain(c)&&Object.hasOwn(c,'bindings');
 const keys=['status','sections',...(hasNative?['nativeGraphqlFields']:[]),...(hasFacts?['facts']:[]),...(hasSemantics?['semantics']:[]),...(hasComparison?['comparison']:[]),...(hasAnchors?['anchors']:[]),...(hasBindings?['bindings']:[])];
 if(!restoreKeys(c,keys)||c.status!=='COMPLETE'||!Array.isArray(c.sections)
  ||c.sections.length>RESTORE_CATALOGUE_SECTIONS.length||new Set(c.sections).size!==c.sections.length
  ||!c.sections.every(k=>RESTORE_CATALOGUE_SECTIONS.includes(k))
  ||(hasNative&&(!restoreKeys(c.nativeGraphqlFields,RESTORE_NATIVE_GRAPHQL_FIELDS)
    ||!RESTORE_NATIVE_GRAPHQL_FIELDS.every(k=>typeof c.nativeGraphqlFields[k]==='boolean'))))
  return {...result,catalogue:{status:'INVALID_SHAPE'}};
 return {...result,catalogue:{status:'COMPLETE',sections:RESTORE_CATALOGUE_SECTIONS.filter(k=>c.sections.includes(k)),
  ...(hasNative?{nativeGraphqlFields:Object.fromEntries(RESTORE_NATIVE_GRAPHQL_FIELDS.map(k=>[k,c.nativeGraphqlFields[k]]))}:{}),
  ...(hasFacts?{facts:projectCatalogueFactsDiagnostic(c.facts)}:{}),
  ...(hasSemantics?{semantics:projectCatalogueSemanticsDiagnostic(c.semantics)}:{}),
  ...(hasComparison?{comparison:projectCatalogueParityV2(c.comparison)}:{}),
  ...(hasAnchors?{anchors:projectCatalogueAnchors(c.anchors)}:{}),
  ...(hasBindings?{bindings:projectCatalogueBindingDiagnostic(c.bindings)}:{})}};
}
export const GRAPHQL_DIAGNOSTIC_CONTEXTS = Object.freeze(['SOURCE_CAPTURE','SOURCE_SNAPSHOT','TARGET_RESTORED',
 'TARGET_COMPARE','PARTITION','NORMALIZE','EXPORT_PREREQUISITES','EXPORT_REMAINDER','EXPORT_ASSEMBLY']);
export const GRAPHQL_DIAGNOSTIC_REASONS = Object.freeze([
 'WITNESS_SHAPE','WITNESS_FLAGS','WITNESS_INITIAL_PRIVILEGES','WITNESS_FINGERPRINT','WITNESS_COMPONENTS','WITNESS_RAW_SCHEMA_FINGERPRINT','WITNESS_SCHEMA_DETAILS','WITNESS_SCHEMA_INITIAL_PRIVILEGES','WITNESS_NATIVE_SCHEMA_BASELINE',
 'PARITY_INITIAL_PRIVILEGES','PARITY_FINGERPRINT','REVIEW','ARCHIVE_BUFFER','ARCHIVE_MAGIC','ARCHIVE_HASH',
 'TOC_BUFFER','TOC_UTF8','TOC_CONTROL','TOC_FORMAT','TOC_DUPLICATE_ID','TOC_SCOPE','TOC_COUNT','TOC_REVIEW_HASH',
 'REQUIRED_EXTENSION_SCHEMA','REQUIRED_WRAPPER_SCHEMA','REQUIRED_HOOK','REQUIRED_DEFAULT_ACL','REQUIRED_TRIGGER',
 'HOOK_COUNT','TRIGGER_COUNT','DEFAULT_ACL_COUNT','WRAPPER_DEFINITION','EXTENSION_COUNT','WRAPPER_ACL',
 'PARTITION_EXHAUSTIVE','EXPORT_CALLBACK','EXPORT_PARTITION','EXPORT_ARCHIVE_MUTATED','EXPORT_LIST_MUTATED',
 'EXPORT_SQL_BUFFER','EXPORT_SQL_NUL','EXPORT_TOTAL_BOUND',
]);
export function projectGraphqlDiagnostic(value) {
 const reason=GRAPHQL_DIAGNOSTIC_REASONS.includes(value?.reason)?value.reason:'UNKNOWN';
 return {schemaVersion:1,context:GRAPHQL_DIAGNOSTIC_CONTEXTS.includes(value?.context)?value.context:'UNKNOWN',reason,
  failedFlags:reason==='WITNESS_FLAGS'&&Array.isArray(value?.failedFlags)
   ?GRAPHQL_WITNESS_FLAGS.filter(flag=>value.failedFlags.includes(flag)):[],
  mismatchedComponents:reason==='PARITY_FINGERPRINT'&&Array.isArray(value?.mismatchedComponents)
   ?Object.values(GRAPHQL_COMPONENT_LABELS).filter(component=>value.mismatchedComponents.includes(component)):[],
  ...(reason==='PARITY_FINGERPRINT'&&typeof value?.wrapperSchemaComparison?.rawEqual==='boolean'
    &&typeof value?.wrapperSchemaComparison?.semanticEqual==='boolean'
   ?{wrapperSchemaComparison:{rawEqual:value.wrapperSchemaComparison.rawEqual,semanticEqual:value.wrapperSchemaComparison.semanticEqual}}:{}),
  ...(reason==='PARITY_FINGERPRINT'&&value?.context==='TARGET_COMPARE'&&Object.hasOwn(value,'wrapperSchemaDelta')
   ?{wrapperSchemaDelta:projectGraphqlSchemaDelta(value.wrapperSchemaDelta,PG_RESTORE_ROLES)}:{})};
}
export function closedFailure(error, stage) { return { result:'PHASE_B_REFUSED',stage:STAGES.has(stage)?stage:'identity',
 code:CODES.has(error?.code)?error.code:'B_FAILED',sqlstate:typeof error?.diagnostic?.sqlstate==='string'&&/^[A-Z0-9]{5}$/.test(error.diagnostic.sqlstate)?error.diagnostic.sqlstate:null,
 sqlLine:Number.isSafeInteger(error?.diagnostic?.line)&&error.diagnostic.line>0&&error.diagnostic.line<1_000_000?error.diagnostic.line:null,
 ...(stage==='restore'&&error?.code==='B_CALL'&&error?.restoreCall?{restoreCall:projectRestoreCall(error.restoreCall)}:{}),
 ...(stage==='restore'&&error?.code==='B_RESTORE'&&error?.restoreInvariant?{restoreInvariant:projectRestoreInvariant(error.restoreInvariant)}:{}),
 ...(error?.code==='B_GRAPHQL_RESTORE_REFUSED'?{graphql:projectGraphqlDiagnostic(error?.graphql)}:{}),
 ...(error?.code==='B_SEMANTICS_WITNESS'?{semanticsWitness:projectB21WitnessFailure(error?.b21WitnessReason,error?.b21Sql)}:{}),
 restored:false,appVerified:false,readyForNationalLaunch:false }; }
export function assertReview(review) {
 requireValue(review?.productSha===PRODUCT_SHA && review?.approved===true && /^[a-f0-9]{40}$/.test(review.phaseAHarnessSha??'')
  && /^[1-9][0-9]{5,14}$/.test(review.phaseARunId??'') && /^[a-f0-9]{64}$/.test(review.nativeRestoreTocSha256??'')
  && review.nativeRoleSettingsReviewed===true && review.nativeGraphqlRepairReviewed===true && Number.isSafeInteger(review.native?.postgresVersionNum)
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
  return {caseId:item.caseId,project:item.project,outcome:item.outcome,attempts:[{status:result.status,code:result.code,retry:0,
   ...(Object.hasOwn(result,'diagnostic')?{diagnostic:validateBrowserDiagnostic(result.diagnostic,result.status)}:{})}]};
 });
 requireValue(expected.size===0&&OUTCOMES.every(key=>value.counts?.[key]===counts[key]),'B_REPORT');
 const passed=value.globalErrorCount===0&&counts.expected===tests.length&&OUTCOMES.slice(1).every(k=>counts[k]===0);
 requireValue(value.passed===passed,'B_REPORT');
 return {schemaVersion:1,productSha:PRODUCT_SHA,side,complete:true,passed,expectedCount:tests.length,counts,globalErrorCount:value.globalErrorCount,tests};
}

// Diagnostics are descriptive only. The case matrix and pass/fail gates above
// remain authoritative; no free Playwright string is copied into this schema.
export const UI_STAGES = Object.freeze(['BEFORE_EACH','AFTER_EACH','LOGIN_NAVIGATE','LOGIN_EMAIL','LOGIN_PASSWORD',
 'LOGIN_SUBMIT','LOGIN_AUTH_RESPONSE','LOGIN_ROUTE','LOGIN_DASHBOARD','LOGIN_IDENTITY','MISSION_NAVIGATE',
 'DOCUMENT_VISIBLE','DOCUMENT_ACCESS','PDF_DOWNLOAD','RELOAD','RELOADED_DOCUMENT_VISIBLE',
 'RELOADED_DOCUMENT_ACCESS','RELOADED_PDF_DOWNLOAD','DENIED_ROUTE','DOCUMENT_ABSENT',
 'ANONYMOUS_REDIRECT','ANONYMOUS_LOGIN_VISIBLE']);
const DIAGNOSTIC_STAGES = new Set([...UI_STAGES,'FIXTURE_BROWSER','FIXTURE_CONTEXT','FIXTURE_PAGE','FIXTURE_OTHER','FIXTURE_TEARDOWN','BEFORE_HOOKS','AFTER_HOOKS','WORKER_CLEANUP','UNKNOWN']);
const DIAGNOSTIC_SOURCES = new Set(['STEP','INCOMPLETE_STEP','FIXTURE_TIMEOUT','UNLOCATED','NO_FAILURE','NOT_EXECUTED']);
const STATUS_CODES = Object.freeze({passed:'PASSED',failed:'TEST_FAILED',timedOut:'TIMEOUT',skipped:'SKIPPED',interrupted:'INTERRUPTED'});
const durationOk = value => typeof value==='number'&&Number.isFinite(value)&&value>=0&&value<=7*24*3600_000;
const plainObject = value => value!==null&&typeof value==='object'&&!Array.isArray(value);
function fixtureTimeoutStage(attempt) {
 // These exact messages are emitted by pinned Playwright 1.58.2 timeoutManager.
 // A changed/unknown message remains unlocated. No substring or stack export.
 const errors=[attempt.error,...(Array.isArray(attempt.errors)?attempt.errors.slice(0,10):[])];
 for(const error of errors) {
  if(!plainObject(error)||typeof error.message!=='string'||error.message.length>1024)continue;
  const message=error.message.replace(/\u001b\[[0-9;]*m/g,'');
  const match=/^Test timeout of 90000ms exceeded while setting up "(browser|context|page)"\.$/.exec(message)
   ?? /^Fixture "(browser|context|page)" timeout of 90000ms exceeded during setup\.$/.exec(message);
  if(match)return {browser:'FIXTURE_BROWSER',context:'FIXTURE_CONTEXT',page:'FIXTURE_PAGE'}[match[1]];
 }
 return null;
}
function diagnosticStage(step,parentStage) {
 if(step.category==='fixture') {
  const match=/^Fixture "(browser|context|page)"$/.exec(step.title);
  if(['AFTER_HOOKS','AFTER_EACH','WORKER_CLEANUP','FIXTURE_TEARDOWN'].includes(parentStage))return 'FIXTURE_TEARDOWN';
  return match?{browser:'FIXTURE_BROWSER',context:'FIXTURE_CONTEXT',page:'FIXTURE_PAGE'}[match[1]]:'FIXTURE_OTHER';
 }
 if(step.category==='hook')return {'Before Hooks':'BEFORE_HOOKS',beforeEach:'BEFORE_EACH',
  'After Hooks':'AFTER_HOOKS',afterEach:'AFTER_EACH','Worker Cleanup':'WORKER_CLEANUP'}[step.title]??null;
 if(step.category===undefined||step.category==='test.step')return UI_STAGES.includes(step.title)?step.title:'UNKNOWN';
 return null;
}
export function projectBrowserDiagnostic(attempt) {
 requireValue(plainObject(attempt)&&Object.hasOwn(STATUS_CODES,attempt.status)&&durationOk(attempt.duration),'B_REPORT');
 const completedStages=[];let stage=null,stageSource='NO_FAILURE',count=0;
 const visit=(steps,depth,parentStage=null)=>{
  requireValue(Array.isArray(steps)&&depth<=16,'B_REPORT');
  for(const step of steps) {
   requireValue(plainObject(step)&&++count<=2048&&(step.duration===-1||durationOk(step.duration)),'B_REPORT');
   const ownStage=diagnosticStage(step,parentStage),currentStage=ownStage??parentStage;
   if(step.steps!==undefined)visit(step.steps,depth+1,currentStage);
   if(stage!==null)continue; // Preserve the first action failure across afterEach/teardown.
   if(step.error!==undefined&&step.error!==null) {stage=currentStage??'UNKNOWN';stageSource='STEP';}
   else if(step.duration===-1) {stage=currentStage??'UNKNOWN';stageSource='INCOMPLETE_STEP';}
   else if(ownStage!==null&&ownStage!=='UNKNOWN'&&completedStages.at(-1)!==ownStage)completedStages.push(ownStage);
  }
 };
 if(attempt.steps!==undefined)visit(attempt.steps,0);
 if(!['passed','skipped'].includes(attempt.status)&&stage===null) {
  stage=fixtureTimeoutStage(attempt);
  stageSource=stage===null?'UNLOCATED':'FIXTURE_TIMEOUT';
  stage??='UNKNOWN';
 }
 if(attempt.status==='skipped'&&count===0)stageSource='NOT_EXECUTED';
 return validateBrowserDiagnostic({schemaVersion:1,stage,stageSource,code:STATUS_CODES[attempt.status],
  lastCompletedStage:completedStages.at(-1)??null,completedStages,durationMs:attempt.duration},attempt.status);
}
export function validateBrowserDiagnostic(value,status) {
 requireValue(plainObject(value)&&value.schemaVersion===1&&Object.hasOwn(STATUS_CODES,status)
  &&value.code===STATUS_CODES[status]&&DIAGNOSTIC_SOURCES.has(value.stageSource)
  &&(value.stage===null||DIAGNOSTIC_STAGES.has(value.stage))
  &&Array.isArray(value.completedStages)&&value.completedStages.length<=64
  &&value.completedStages.every(stage=>DIAGNOSTIC_STAGES.has(stage)&&stage!=='UNKNOWN')&&durationOk(value.durationMs)
  &&value.lastCompletedStage===(value.completedStages.at(-1)??null),'B_REPORT');
 requireValue((['STEP','INCOMPLETE_STEP','FIXTURE_TIMEOUT','UNLOCATED'].includes(value.stageSource))===(value.stage!==null)
  &&(value.stageSource!=='UNLOCATED'||value.stage==='UNKNOWN')
  &&(value.stageSource!=='FIXTURE_TIMEOUT'||['FIXTURE_BROWSER','FIXTURE_CONTEXT','FIXTURE_PAGE'].includes(value.stage))
  &&(value.stageSource!=='NOT_EXECUTED'||(status==='skipped'&&value.completedStages.length===0)),'B_REPORT');
 return {schemaVersion:1,stage:value.stage,stageSource:value.stageSource,code:value.code,
  lastCompletedStage:value.lastCompletedStage,completedStages:[...value.completedStages],durationMs:value.durationMs};
}
export function projectBrowserDiagnostics(raw,identified) {
 const records=[];
 const visit=(suites,depth)=>{
  requireValue(Array.isArray(suites)&&depth<=30,'B_REPORT');
  for(const suite of suites) {
   requireValue(plainObject(suite)&&Array.isArray(suite.specs),'B_REPORT');
   for(const spec of suite.specs) {
    requireValue(plainObject(spec)&&Array.isArray(spec.tests),'B_REPORT');
    for(const result of spec.tests) { requireValue(records.length<25,'B_REPORT');records.push({caseId:spec.title,result}); }
   }
   if(suite.suites!==undefined)visit(suite.suites,depth+1);
  }
 };
 visit(raw?.suites,0);
 requireValue(Array.isArray(identified)&&records.length===identified.length,'B_REPORT');
 return records.map(({caseId,result},index)=>{
  const test=identified[index];
  requireValue(plainObject(result)&&plainObject(test)&&caseId===test.caseId&&result.projectName===test.project&&Array.isArray(result.results)
   &&result.results.length===1&&result.results[0].retry===0&&test.attempts.length===1
   &&result.results[0].status===test.attempts[0].status,'B_REPORT');
  return Object.hasOwn(result.results[0],'closedDiagnostic')
   ?validateBrowserDiagnostic(result.results[0].closedDiagnostic,result.results[0].status)
   :projectBrowserDiagnostic(result.results[0]);
 });
}
