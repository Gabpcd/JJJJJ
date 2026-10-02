/** CI-only SQL witness: exact seed bytes, SQL Auth actors, SAVEPOINT rollback.
 * No Auth HTTP, Edge/Stripe call, migration, feature activation or persistent seed. */
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { newManifest, validateManifest, validateSnapshot, PROJECT } from './connect-test-fixture.mjs';
import { catalogueSqlFixture, snapshotSql, literal } from './connect-test-fixture-sql.mjs';

export const SEED_SHA256='57dd7f97e8cc7c0996a108abe51c62cbdf5a0218e775ddb14558c9badc4020ab';
// Fresh read-only staging observation reviewed on 2026-10-02. No automatic repin.
export const REVIEWED_CATALOGUE=Object.freeze({routines:'2d70a3530ef3547c9cb85d2775b66649',triggers:'9f6a900536c273864ff418df569511c1',columns:'a5b1a6c4464a545cc9256faba9e9596c'});
const ROOT=fileURLToPath(new URL('../../',import.meta.url));
const ENDPOINT=`https://api.supabase.com/v1/projects/${PROJECT}/database/query`;
const sha=value=>createHash('sha256').update(value).digest('hex');
class Refusal extends Error {constructor(code){super(code);this.code=code;}}
const check=(condition,code)=>{if(!condition)throw new Refusal(code);};
const selectBody=sql=>sql.replace(/;\s*$/,'');
export function loadSeed() {const seed=readFileSync(new URL('./connect-test-fixture-prepare.sql',import.meta.url),'utf8');check(sha(seed)===SEED_SHA256,'SEED_SOURCE_DRIFT');return seed;}
export function context(env,localSha) {
  check(env.GITHUB_ACTIONS==='true'&&env.GITHUB_EVENT_NAME==='pull_request'&&env.GITHUB_REPOSITORY==='Gabpcd/JJJJJ'
    &&env.PR_HEAD_REPOSITORY==='Gabpcd/JJJJJ'&&env.STAGING_SUPABASE_PROJECT_REF===PROJECT
    &&/^[a-f0-9]{40}$/.test(env.SOURCE_SHA??'')&&env.SOURCE_SHA===localSha
    &&/^[1-9][0-9]{0,19}$/.test(env.GITHUB_RUN_ID??'')&&/^[1-9][0-9]{0,3}$/.test(env.GITHUB_RUN_ATTEMPT??'')
    &&typeof env.STAGING_SUPABASE_ACCESS_TOKEN==='string'&&env.STAGING_SUPABASE_ACCESS_TOKEN.length>10,'CI_CONTEXT_REFUSED');
  return newManifest(`connect-test-ci-${env.GITHUB_RUN_ID}-${env.GITHUB_RUN_ATTEMPT}`,localSha);
}
export function observationSql(m) {
  validateManifest(m);const actors=m.members.map(x=>`${literal(x.id)}::uuid`).join(','),mission=`${literal(m.sql.ids.mission)}::uuid`;
  return `SELECT jsonb_build_object('catalogue',c.catalogue,'snapshot',s.receipt,
    'authInsertTriggers',(SELECT count(*) FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal AND tgenabled<>'D' AND (tgtype::int & 20)<>0),
    'externalNotifications',(SELECT md5(coalesce(string_agg(to_jsonb(n)::text,E'\\n' ORDER BY id),'')) FROM public.notifications n WHERE destinataire_id NOT IN(${actors})),
    'emailQueue',(SELECT md5(coalesce(string_agg(to_jsonb(q)::text,E'\\n' ORDER BY id),'')) FROM public.email_queue q),
    'externalQueues',md5(jsonb_build_array(
      (SELECT md5(coalesce(string_agg(to_jsonb(q)::text,E'\\n' ORDER BY to_jsonb(q)::text),'')) FROM public.externalisation_actions q),
      (SELECT md5(coalesce(string_agg(to_jsonb(q)::text,E'\\n' ORDER BY to_jsonb(q)::text),'')) FROM public.stripe_refunds_queue q),
      (SELECT md5(coalesce(string_agg(to_jsonb(q)::text,E'\\n' ORDER BY to_jsonb(q)::text),'')) FROM public.escrow_release_queue q))::text),
    'cohort',jsonb_build_object(
      'mandats',(SELECT count(*) FROM public.mandats_facturation_signatures WHERE soignant_id IN(${actors})),
      'creneaux',(SELECT count(*) FROM public.mission_creneaux WHERE mission_id=${mission}),
      'notifications',(SELECT count(*) FROM public.notifications WHERE destinataire_id IN(${actors}) OR id_ressource=${mission}),
      'audit',(SELECT count(*) FROM public.journaux_audit WHERE acteur_id IN(${actors}) OR id_ressource IN(${actors},${mission})),
      'preferences',(SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(${actors})),
      'sessions',(SELECT count(*) FROM auth.sessions WHERE user_id IN(${actors})),
      'identities',(SELECT count(*) FROM auth.identities WHERE user_id IN(${actors})))
  ) AS observation FROM (${selectBody(catalogueSqlFixture())}) c CROSS JOIN (${selectBody(snapshotSql(m.sql))}) s;`;
}
export function validateObservation(rows,m) {
  check(Array.isArray(rows)&&rows.length===1&&Object.keys(rows[0]).join()==='observation','OBSERVATION_SHAPE');const value=rows[0].observation,c=value?.catalogue;
  check(c&&Object.entries(REVIEWED_CATALOGUE).every(([k,v])=>c[k]===v)&&value.authInsertTriggers===0
    &&['queuedRequests','activeCrons','runningCrons'].every(k=>c[k]===0)&&c.generationUrlAbsent===true&&c.supportStagingExact===true
    &&/^[a-f0-9]{32}$/.test(value.externalNotifications??'')&&/^[a-f0-9]{32}$/.test(value.emailQueue??'')&&/^[a-f0-9]{32}$/.test(value.externalQueues??'')
    &&isDeepStrictEqual(value.cohort,{mandats:0,creneaux:0,notifications:0,audit:0,preferences:0,sessions:0,identities:0}),'STAGING_PREFLIGHT_REFUSED');
  validateSnapshot(value.snapshot,m,'empty');check(value.snapshot.auth.length===0,'AUTH_COLLISION');return value;
}
export function renderRollback(seed,m,before) {
  validateManifest(m);check(sha(seed)===SEED_SHA256,'SEED_SOURCE_DRIFT');
  check(!/^[ \t]*(?:BEGIN|COMMIT|ROLLBACK)[ \t]*;|^[ \t]*\\/im.test(seed),'SEED_TRANSACTION_COMMAND');validateObservation([{observation:before}],m);
  const observe=selectBody(observationSql(m)),snapshot=selectBody(snapshotSql(m.sql));
  const guard=`DO $seed_observation$ DECLARE actual jsonb; BEGIN
    SELECT observation.observation INTO actual FROM (${observe}) observation;
    IF actual IS DISTINCT FROM ${literal(JSON.stringify(before))}::jsonb THEN RAISE EXCEPTION 'CONNECT_SEED_OBSERVATION_CHANGED'; END IF;
  END $seed_observation$;`;
  const authValues=m.members.map((a,i)=>`(${literal(a.id)}::uuid,'00000000-0000-0000-0000-000000000000'::uuid,${literal(a.email)},'authenticated','authenticated',
    ${literal(JSON.stringify({role:a.role,est_compte_test:true,is_test_playwright:true,jolene_connect_fixture_owner:m.sql.ownerMarker,...(i===1?{etablissement_id:a.id}:{})}))}::jsonb,now())`).join(',\n');
  return `BEGIN;
SET LOCAL statement_timeout='90s'; SET LOCAL lock_timeout='3s'; SET LOCAL TIME ZONE 'UTC';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $seed_context$ DECLARE name text; BEGIN
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL OR public.est_admin()
    OR current_setting('session_replication_role')<>'origin' THEN RAISE EXCEPTION 'CONNECT_SEED_CONTEXT'; END IF;
  FOREACH name IN ARRAY ARRAY['app.test_mode','app.test_bypass_protections','jolene.sync_in_progress','jolene.system_update','jolene.planning_exact_managed'] LOOP
    IF coalesce(current_setting(name,true),'') NOT IN ('','false') THEN RAISE EXCEPTION 'CONNECT_SEED_BYPASS'; END IF;
  END LOOP;
END $seed_context$;
${guard}
SAVEPOINT connect_fixture_exact_seed;
SELECT set_config('jolene.connect_test_fixture_manifest',${literal(JSON.stringify(m.sql))},true);
-- SQL Auth only. No password, identity, session, GoTrue hook or invitation.
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at) VALUES
${authValues};
-- BEGIN EXACT SEED SHA256 ${SEED_SHA256}
${seed}
-- END EXACT SEED
DO $seed_assertions$ DECLARE r jsonb; receipt jsonb; checks jsonb; current_observation jsonb; BEGIN
  receipt:=current_setting('jolene.connect_test_fixture_receipt')::jsonb;
  IF receipt->>'runId' IS DISTINCT FROM ${literal(m.sql.runId)} OR receipt->>'missionId' IS DISTINCT FROM ${literal(m.sql.ids.mission)}
    OR receipt->'qualificationVerifiee' IS DISTINCT FROM 'false'::jsonb OR receipt->'signatureSynthetique' IS DISTINCT FROM 'true'::jsonb
    OR receipt->'mfaProuve' IS DISTINCT FROM 'false'::jsonb OR receipt->'montantOriginal' IS DISTINCT FROM '80'::jsonb
    THEN RAISE EXCEPTION 'CONNECT_SEED_RECEIPT'; END IF;
  SELECT snapshot.receipt INTO r FROM (${snapshot}) snapshot;
  IF jsonb_array_length(r->'auth')<>3 OR jsonb_array_length(r->'soignants')<>1 OR jsonb_array_length(r->'etablissements')<>1
    OR r->'preferencesClosed' IS DISTINCT FROM 'true'::jsonb OR r->'activeAdmin' IS DISTINCT FROM '0'::jsonb
    OR r->'payments' IS DISTINCT FROM '0'::jsonb OR r->'paymentClaims' IS DISTINCT FROM '0'::jsonb
    OR r->'emailQueue' IS DISTINCT FROM '0'::jsonb OR r->'emailRetries' IS DISTINCT FROM '0'::jsonb
    OR r->'onboarding' IS DISTINCT FROM '[]'::jsonb OR r->'invoices' IS DISTINCT FROM '[]'::jsonb OR r->'commissions' IS DISTINCT FROM '[]'::jsonb
    OR r#>>'{mission,status}' IS DISTINCT FROM 'EN_COURS' OR r#>'{mission,net}' IS DISTINCT FROM '160'::jsonb
    OR r#>'{mission,effective}' IS DISTINCT FROM '4'::jsonb
    OR r#>>'{mission,startsOn}'>receipt->>'periodeDebut' OR r#>>'{mission,endsOn}'<receipt->>'periodeFin'
    THEN RAISE EXCEPTION 'CONNECT_SEED_BUSINESS_ASSERTIONS'; END IF;
  checks:=public.fn_verifier_pre_facturation(${literal(m.sql.ids.mission)}::uuid,(receipt->>'periodeDebut')::date,(receipt->>'periodeFin')::date);
  IF checks->'ok' IS DISTINCT FROM 'true'::jsonb OR checks->'mode_periode' IS DISTINCT FROM 'true'::jsonb
    OR checks->'duree_previsionnelle' IS DISTINCT FROM '4'::jsonb OR checks->'duree_effective' IS DISTINCT FROM '4'::jsonb
    OR checks->'duree_facturee' IS DISTINCT FROM '4'::jsonb OR checks->>'source_facturation' IS DISTINCT FROM 'EFFECTIF'
    THEN RAISE EXCEPTION 'CONNECT_SEED_PREFACTURATION'; END IF;
  SELECT observation.observation INTO current_observation FROM (${observe}) observation;
  IF current_observation->'catalogue' IS DISTINCT FROM ${literal(JSON.stringify(before.catalogue))}::jsonb
    OR current_observation->>'externalNotifications' IS DISTINCT FROM ${literal(before.externalNotifications)}
    OR current_observation->>'emailQueue' IS DISTINCT FROM ${literal(before.emailQueue)}
    OR current_observation->>'externalQueues' IS DISTINCT FROM ${literal(before.externalQueues)}
    OR current_observation#>'{cohort,mandats}' IS DISTINCT FROM '1'::jsonb
    OR current_observation#>'{cohort,creneaux}' IS DISTINCT FROM '3'::jsonb
    OR current_observation#>'{cohort,preferences}' IS DISTINCT FROM '2'::jsonb
    OR current_observation#>'{cohort,sessions}' IS DISTINCT FROM '0'::jsonb
    OR current_observation#>'{cohort,identities}' IS DISTINCT FROM '0'::jsonb
    THEN RAISE EXCEPTION 'CONNECT_SEED_CHANNEL_OR_CATALOGUE_CHANGED'; END IF;
END $seed_assertions$;
ROLLBACK TO SAVEPOINT connect_fixture_exact_seed;
${guard}
RELEASE SAVEPOINT connect_fixture_exact_seed;
SELECT 'CONNECT_TEST_FIXTURE_SEED_ROLLBACK' AS proof,true AS rolled_back,${literal(SEED_SHA256)} AS seed_sha256;
ROLLBACK;
`;
}
export async function executeWitness({env,localSha,seed=loadSeed(),fetcher=fetch,record=()=>{}}) {
  const m=context(env,localSha),report={schemaVersion:1,projectRef:PROJECT,sourceSha:localSha,seedSha256:SEED_SHA256,
    success:false,attempted:false,rollbackSentinel:false,independentRead:false,authHttp:false,edgeCalled:false,stripeCalled:false,phase:'preflight',code:null};
  check(sha(seed)===SEED_SHA256,'SEED_SOURCE_DRIFT');
  const request=async(query,readOnly)=>{
    try {const response=await fetcher(ENDPOINT,{method:'POST',redirect:'error',signal:AbortSignal.timeout(readOnly?30000:110000),headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({query,read_only:readOnly})});
      check(response.ok&&!response.redirected,'SQL_HTTP_REFUSED');return await response.json();
    }catch(error){if(error instanceof Refusal)throw error;throw new Refusal('SQL_TRANSPORT_OR_JSON');}
  };
  let before;
  try {
    before=validateObservation(await request(observationSql(m),true),m);
    const sql=renderRollback(seed,m,before);report.phase='transaction';report.attempted=true;record(report);
    try {
      const rows=await request(sql,false);
      check(isDeepStrictEqual(rows,[{proof:'CONNECT_TEST_FIXTURE_SEED_ROLLBACK',rolled_back:true,seed_sha256:SEED_SHA256}]),'ROLLBACK_SENTINEL_MISSING');report.rollbackSentinel=true;
    }finally {
      report.phase='independent_read';const after=validateObservation(await request(observationSql(m),true),m);
      check(isDeepStrictEqual(after,before),'ROLLBACK_NOT_RECONCILED');report.independentRead=true;
    }
    report.success=true;report.phase='complete';
  }catch(error){report.code=error instanceof Refusal?error.code:'UNEXPECTED_FAILURE';}
  record(report);return report;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    check(process.argv.length===2,'NO_ARGUMENTS_ALLOWED');
    const localSha=execFileSync('git',['-C',ROOT,'rev-parse','HEAD'],{encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:15000,
      env:{PATH:process.env.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'}}).trim();
    const record=report=>{check(typeof process.env.RUNNER_TEMP==='string'&&process.env.RUNNER_TEMP.length>0,'PRIVATE_REPORT_PATH_REQUIRED');writeFileSync(resolve(process.env.RUNNER_TEMP,'connect-test-fixture-rollback.json'),JSON.stringify(report)+'\n',{mode:0o600});};
    const report=await executeWitness({env:process.env,localSha,record});console.log(JSON.stringify(report));if(!report.success)process.exitCode=1;
  }catch(error){console.error(JSON.stringify({success:false,code:error instanceof Refusal?error.code:'LOCAL_FAILURE'}));process.exitCode=1;}
}
