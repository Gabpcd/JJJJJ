/** Two new Auth TEST actors only; no business or provider writes. */
import { randomUUID, randomBytes } from 'node:crypto';
import { PROJECT, Refusal } from './connect-test-fixture.mjs';
const ORIGIN=`https://${PROJECT}.supabase.co`, MANAGEMENT=`https://api.supabase.com/v1/projects/${PROJECT}`;
const SHA=/^[a-f0-9]{40}$/, UUID=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const requireThat=(ok,code)=>{if(!ok)throw new Refusal(code);};
const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
const equal=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const only=rows=>{requireThat(Array.isArray(rows)&&rows.length===1&&Object.keys(rows[0]).join()==='receipt','AUTH_ONLY_SQL_SHAPE');return rows[0].receipt;};

// Separate bootstrap purpose. The historical Connect executor above is unchanged.
export const AUTH_ONLY_PURPOSE='AUTH_ONLY_FRONTEND_V1';
export const AUTH_HOOK_FLAGS=Object.freeze(['hook_custom_access_token_enabled','hook_mfa_verification_attempt_enabled',
  'hook_password_verification_attempt_enabled','hook_send_sms_enabled','hook_send_email_enabled',
  'hook_before_user_created_enabled','hook_after_user_created_enabled']);
export function projectAuthHooks(config) {
  requireThat(config&&typeof config==='object'&&!Array.isArray(config),'AUTH_ONLY_CONFIG');
  const flags=Object.keys(config).filter(k=>/^hook_.*_enabled$/.test(k)).sort();
  requireThat(equal(flags,[...AUTH_HOOK_FLAGS].sort()),'AUTH_ONLY_HOOK_INVENTORY');
  for(const name of Object.keys(config).filter(k=>k.startsWith('hook_'))) {
    requireThat(AUTH_HOOK_FLAGS.some(flag=>name.startsWith(flag.slice(0,-'enabled'.length))),'AUTH_ONLY_HOOK_INVENTORY');
  }
  return Object.fromEntries(AUTH_HOOK_FLAGS.map(k=>{requireThat(typeof config[k]==='boolean','AUTH_ONLY_HOOK_VALUE');return[k,config[k]];}));
}
export function newAuthOnlyManifest(runId,sourceSha) {
  requireThat(/^auth-test-ci-[0-9]{1,20}-1$/.test(runId??'')&&SHA.test(sourceSha??''),'AUTH_ONLY_PLAN');
  return {schemaVersion:1,purpose:AUTH_ONLY_PURPOSE,projectRef:PROJECT,sourceSha,ownerMarker:`${runId}:${sourceSha}`,runId,
    members:['SOIGNANT','ETABLISSEMENT'].map(intention=>{const id=randomUUID();return{id,intention,email:`auth-test-${id}@example.invalid`,password:`At!${randomBytes(36).toString('base64url')}`};}),steps:{}};
}
export function validateAuthOnlyManifest(m) {
  requireThat(m?.schemaVersion===1&&m.purpose===AUTH_ONLY_PURPOSE&&m.projectRef===PROJECT&&SHA.test(m.sourceSha??'')
    &&/^auth-test-ci-[0-9]{1,20}-1$/.test(m.runId??'')&&m.ownerMarker===`${m.runId}:${m.sourceSha}`
    &&Array.isArray(m.members)&&m.members.length===2&&m.steps&&typeof m.steps==='object'&&!Array.isArray(m.steps)
    &&Object.keys(m).sort().join()==='members,ownerMarker,projectRef,purpose,runId,schemaVersion,sourceSha,steps','AUTH_ONLY_MANIFEST');
  m.members.forEach((member,i)=>requireThat(Object.keys(member).sort().join()==='email,id,intention,password'
    &&UUID.test(member.id??'')&&member.intention===['SOIGNANT','ETABLISSEMENT'][i]
    &&member.email===`auth-test-${member.id}@example.invalid`&&typeof member.password==='string'&&/^At![A-Za-z0-9_-]{48}$/.test(member.password),'AUTH_ONLY_MEMBER'));
  requireThat(new Set(m.members.map(x=>x.id)).size===2&&new Set(m.members.map(x=>x.password)).size===2
    &&Object.keys(m.steps).every(k=>['auth0','auth1'].includes(k)),'AUTH_ONLY_MANIFEST');
}
export function validateAuthOnlyUser(user,member,m) {
  const meta=user?.app_metadata;
  requireThat(user?.id===member.id&&user.email===member.email&&!!user.email_confirmed_at&&!user.deleted_at
    &&(!user.banned_until||Date.parse(user.banned_until)<=Date.now())&&meta?.est_compte_test===true&&meta?.is_test_playwright===true
    &&meta.jolene_auth_fixture_owner===m.ownerMarker&&meta.jolene_recette_purpose===AUTH_ONLY_PURPOSE
    &&!Object.hasOwn(meta,'role')&&!Object.hasOwn(meta,'etablissement_id'),'AUTH_ONLY_OWNERSHIP');
}
export function authOnlyCatalogueSql() {
  return `SELECT jsonb_build_object(
    'authTriggersMd5',(SELECT md5(coalesce(string_agg(pg_get_triggerdef(t.oid)||':'||t.tgenabled::text||':'||md5(pg_get_functiondef(p.oid))||':'||p.proowner::regrole::text||':'||coalesce(p.proacl::text,''),E'\\n' ORDER BY t.tgname),'')) FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE t.tgrelid='auth.users'::regclass AND NOT t.tgisinternal),
    'authInsertOrUpdateTriggers',(SELECT count(*)::int FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal AND (tgtype::int & 20)<>0),
    'profileTriggersMd5',(SELECT md5(coalesce(string_agg(pg_get_triggerdef(t.oid)||':'||t.tgenabled::text||':'||md5(pg_get_functiondef(p.oid))||':'||p.proowner::regrole::text,E'\\n' ORDER BY t.tgrelid::regclass::text),'')) FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE t.tgrelid IN('public.soignants'::regclass,'public.etablissements'::regclass) AND t.tgname='trg_forcer_compte_test_prelaunch' AND NOT t.tgisinternal),
    'profileTriggersValid',(SELECT count(*)=2 AND bool_and(t.tgenabled='O' AND n.nspname='private' AND p.proname='fn_forcer_compte_test_prelaunch' AND p.prosecdef AND p.proowner='postgres'::regrole) FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace n ON n.oid=p.pronamespace WHERE t.tgrelid IN('public.soignants'::regclass,'public.etablissements'::regclass) AND t.tgname='trg_forcer_compte_test_prelaunch' AND NOT t.tgisinternal),
    'queuedRequests',(SELECT count(*)::int FROM net.http_request_queue),
    'activeCrons',(SELECT count(*)::int FROM cron.job WHERE active),
    'runningCrons',(SELECT count(*)::int FROM cron.job_run_details WHERE end_time IS NULL AND status IN('starting','running','connecting','sending'))
  ) AS receipt;`;
}
export function authOnlyReadOnlySql(sql) {
  requireThat(/^SELECT\b/.test(sql.trim())&&!/\b(?:BEGIN|COMMIT|ROLLBACK|END)\s*;|^[ \t]*\\/im.test(sql),'AUTH_ONLY_READ_REQUIRED');
  return `BEGIN READ ONLY; SET LOCAL statement_timeout='20s'; SET LOCAL row_security=off;
DO $auth_only_read$ BEGIN IF current_setting('transaction_read_only')<>'on' OR current_user<>'postgres' OR session_user NOT IN('postgres','supabase_admin') THEN RAISE EXCEPTION 'AUTH_ONLY_READ_CONTEXT'; END IF; END $auth_only_read$;
${sql}\nROLLBACK;`;
}
export function authOnlySnapshotSql(m) {
  validateAuthOnlyManifest(m);
  const ids=m.members.map(x=>`'${x.id}'::uuid`).join(','),emails=m.members.map(x=>`'${x.email}'`).join(',');
  return `SELECT jsonb_build_object(
    'authCount',(SELECT count(*)::int FROM auth.users WHERE id IN(${ids}) OR email IN(${emails})),
    'profiles',(SELECT count(*)::int FROM public.soignants WHERE id IN(${ids}) OR email IN(${emails}))+(SELECT count(*)::int FROM public.etablissements WHERE id IN(${ids}) OR email_contact IN(${emails})),
    'parcours',(SELECT count(*)::int FROM public.parcours_inscription WHERE user_id IN(${ids})),
    'types',(SELECT count(*)::int FROM public.types_comptes_auth WHERE user_id IN(${ids})),
    'admin',(SELECT count(*)::int FROM public.equipe_admin WHERE user_id IN(${ids})),
    'members',(SELECT count(*)::int FROM public.membres_etablissement WHERE user_id IN(${ids}) OR etablissement_id IN(${ids})),
    'missions',(SELECT count(*)::int FROM public.missions WHERE etablissement_id IN(${ids}) OR soignant_assigne_id IN(${ids})),
    'documents',(SELECT count(*)::int FROM public.documents_soignants WHERE soignant_id IN(${ids})),
    'contracts',(SELECT count(*)::int FROM public.contrats_mission WHERE soignant_id IN(${ids}) OR etablissement_id IN(${ids})),
    'invoices',(SELECT count(*)::int FROM public.factures_honoraires WHERE soignant_id IN(${ids}) OR etablissement_id IN(${ids}))+(SELECT count(*)::int FROM public.factures WHERE etablissement_id IN(${ids})),
    'onboarding',(SELECT count(*)::int FROM public.stripe_connect_onboarding WHERE soignant_id IN(${ids})),
    'emailQueue',(SELECT count(*)::int FROM public.email_queue WHERE destinataire_id IN(${ids})),
    'notifications',(SELECT count(*)::int FROM public.notifications WHERE destinataire_id IN(${ids})),
    'sessions',(SELECT count(*)::int FROM auth.sessions WHERE user_id IN(${ids})),
    'identities',(SELECT count(*)::int FROM auth.identities WHERE user_id IN(${ids}))
  ) AS receipt;`;
}
export function validateAuthOnlySnapshot(snapshot,count) {
  const fields=['authCount','profiles','parcours','types','admin','members','missions','documents','contracts','invoices','onboarding','emailQueue','notifications','sessions','identities'];
  requireThat(snapshot&&Object.keys(snapshot).sort().join()===fields.sort().join()
    &&fields.every(k=>Number.isSafeInteger(snapshot[k])&&snapshot[k]>=0)
    &&snapshot.authCount===count&&snapshot.identities===count
    &&fields.filter(k=>!['authCount','identities'].includes(k)).every(k=>snapshot[k]===0),'AUTH_ONLY_COLLISION_OR_EFFECT');
}
export function checkAuthOnlyContract(c,m,now=Date.now()) {
  requireThat(c?.ready===true,'AUTH_ONLY_READINESS_CLOSED');validateAuthOnlyManifest(m);
  requireThat(c.schemaVersion===1&&c.purpose===AUTH_ONLY_PURPOSE&&c.projectRef===PROJECT&&c.sourceSha===m.sourceSha
    &&c.authEffectsReviewed===true&&typeof c.reviewedBy==='string'&&c.reviewedBy.trim().length>=3
    &&Date.parse(c.expiresAt)>now&&Date.parse(c.expiresAt)-now<=4*3600000,'AUTH_ONLY_CONTRACT');
  const cat=c.catalogue;
  requireThat(cat&&Object.keys(cat).sort().join()==='activeCrons,authInsertOrUpdateTriggers,authTriggersMd5,profileTriggersMd5,profileTriggersValid,queuedRequests,runningCrons'
    &&['authTriggersMd5','profileTriggersMd5'].every(k=>/^[a-f0-9]{32}$/.test(cat[k]??''))
    &&['authInsertOrUpdateTriggers','queuedRequests','activeCrons','runningCrons'].every(k=>cat[k]===0)&&cat.profileTriggersValid===true,'AUTH_ONLY_CATALOGUE_PIN');
  requireThat(equal(projectAuthHooks(c.authHooks),Object.fromEntries(AUTH_HOOK_FLAGS.map(k=>[k,false]))),'AUTH_ONLY_HOOK_ACTIVE');
}
export function requireAuthOnlyComplete(m,result) {
  validateAuthOnlyManifest(m);
  requireThat(equal(Object.keys(m.steps).sort(),['auth0','auth1'])
    &&Object.values(m.steps).every(step=>equal(step,{state:'done',result:{created:true}}))
    &&equal(result,{prepared:true,authCreated:2,profilesCreated:0,missionsCreated:0,qualificationVerified:false,frontendCompletionRequired:true,
      stripeObjectsCreated:0,paymentCreated:false,smsSent:false,mailSent:false}),'AUTH_ONLY_INCOMPLETE_HANDOFF');
}
export async function executeAuthOnlyPreparation({manifest:m,contract:c,env,local,fetcher=fetch,save}) {
  checkAuthOnlyContract(c,m);
  requireThat(local?.sha===m.sourceSha&&local.clean===true,'AUTH_ONLY_SOURCE');
  requireThat(Object.keys(m.steps).length===0,'AUTH_ONLY_NO_RETRY');
  requireThat(typeof save==='function','AUTH_ONLY_CHECKPOINT_REQUIRED');
  requireThat(typeof env.STAGING_SUPABASE_ACCESS_TOKEN==='string'&&env.STAGING_SUPABASE_ACCESS_TOKEN.length>10
    &&typeof env.STAGING_SUPABASE_SERVICE_ROLE_KEY==='string'&&env.STAGING_SUPABASE_SERVICE_ROLE_KEY.length>10
    &&typeof env.GITHUB_TOKEN==='string'&&env.GITHUB_TOKEN.length>10&&!env.STRIPE_TEST_SECRET_KEY,'AUTH_ONLY_CREDENTIALS');
  const request=async(kind,path,body)=>{
    const management=kind==='management',github=kind==='github';
    requireThat(management?['','/config/auth','/database/query'].includes(path):github?path==='/git/ref/heads/main':path==='/auth/v1/admin/users'||m.members.some(x=>path===`/auth/v1/admin/users/${x.id}`),'AUTH_ONLY_ENDPOINT');
    const method=body===undefined?'GET':'POST';
    requireThat(method!=='POST'||management&&path==='/database/query'||!management&&!github&&path==='/auth/v1/admin/users','AUTH_ONLY_ENDPOINT');
    try {
      const token=management?env.STAGING_SUPABASE_ACCESS_TOKEN:github?env.GITHUB_TOKEN:env.STAGING_SUPABASE_SERVICE_ROLE_KEY;
      const base=management?MANAGEMENT:github?'https://api.github.com/repos/Gabpcd/JJJJJ':ORIGIN;
      const response=await fetcher(base+path,{method,redirect:'error',signal:AbortSignal.timeout(30000),headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',...(management||github?{}:{apikey:token})},...(body===undefined?{}:{body:JSON.stringify(body)})});
      requireThat(response.ok&&!response.redirected,'AUTH_ONLY_HTTP_UNCERTAIN');
      const value=await response.text();requireThat(Buffer.byteLength(value)<2_000_000,'AUTH_ONLY_RESPONSE_SIZE');return JSON.parse(value);
    }catch(error){if(error instanceof Refusal)throw error;throw new Refusal('AUTH_ONLY_TRANSPORT_UNCERTAIN');}
  };
  const query=async sql=>only(await request('management','/database/query',{query:authOnlyReadOnlySql(sql),read_only:false}));
  const preflight=async()=>{
    checkAuthOnlyContract(c,m);
    const main=await request('github','/git/ref/heads/main');requireThat(main?.ref==='refs/heads/main'&&main.object?.sha===m.sourceSha&&main.object?.type==='commit','AUTH_ONLY_MAIN_MOVED');
    const project=await request('management','');requireThat(project?.id===PROJECT&&project.status==='ACTIVE_HEALTHY'&&project.database?.host===`db.${PROJECT}.supabase.co`,'AUTH_ONLY_PROJECT');
    requireThat(equal(projectAuthHooks(await request('management','/config/auth')),c.authHooks),'AUTH_ONLY_HOOK_DRIFT');
    requireThat(equal(await query(authOnlyCatalogueSql()),c.catalogue),'AUTH_ONLY_CATALOGUE_DRIFT');
  };
  await preflight();validateAuthOnlySnapshot(await query(authOnlySnapshotSql(m)),0);
  for(const [i,member]of m.members.entries()) {
    await preflight();validateAuthOnlySnapshot(await query(authOnlySnapshotSql(m)),i);
    // Both identities and passwords already exist in the encrypted checkpoint.
    // An intent has no retry path, including a response lost after POST.
    m.steps[`auth${i}`]={state:'intent'};await save(m);
    const result=await request('auth','/auth/v1/admin/users',{id:member.id,email:member.email,password:member.password,email_confirm:true,
      app_metadata:{est_compte_test:true,is_test_playwright:true,jolene_auth_fixture_owner:m.ownerMarker,jolene_recette_purpose:AUTH_ONLY_PURPOSE}});
    validateAuthOnlyUser(result?.user??result,member,m);
    const reread=await request('auth',`/auth/v1/admin/users/${member.id}`);validateAuthOnlyUser(reread?.user??reread,member,m);
    await preflight();validateAuthOnlySnapshot(await query(authOnlySnapshotSql(m)),i+1);
    m.steps[`auth${i}`]={state:'done',result:{created:true}};await save(m);
  }
  return {prepared:true,authCreated:2,profilesCreated:0,missionsCreated:0,qualificationVerified:false,frontendCompletionRequired:true,
    stripeObjectsCreated:0,paymentCreated:false,smsSent:false,mailSent:false};
}
