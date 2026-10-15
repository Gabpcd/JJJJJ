/** LOCAL AUTHOR DRAFT ONLY. No automatic execution, dependency install or historical fixture import.
 * Future runner-only operator: exactly one new TEST Customer + one new TEST Express.
 * No Auth/profile creation, application login, DB DML, onboarding link, KYC, payment or refund.
 * Callers must supply transport + encrypted checkpoint writer explicitly. Versioned contract stays closed.
 */
import {createHash,createPublicKey,publicEncrypt,randomBytes,createCipheriv,constants} from 'node:crypto';
import {open,rename,lstat,realpath} from 'node:fs/promises';
import {resolve,dirname,basename} from 'node:path';

export const PURPOSE='STRIPE_PROVIDER_ACTORS_TEST_V1',PROJECT='mejpriaetwgtcstbgfid',PLATFORM='acct_1T9pt0EVhQ7cb53W';
export const API_VERSION='2026-02-25.clover'; // Existing integration, deliberately pinned; no migration.
export const WORKFLOW='.github/workflows/stripe-test-provider-actors.yml';
export const SOURCE_FILES=['scripts/ci/stripe-test-provider-actors.mjs','scripts/ci/stripe-test-provider-actors-ci.mjs',WORKFLOW,'tests/node/stripe-test-provider-actors.node.mjs'];
const REPO='Gabpcd/JJJJJ',MGMT=`https://api.supabase.com/v1/projects/${PROJECT}`,STRIPE='https://api.stripe.com/v1';
const SHA=/^[a-f0-9]{40}$/,HEX=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const FLAGS=['hook_custom_access_token_enabled','hook_mfa_verification_attempt_enabled','hook_password_verification_attempt_enabled','hook_send_sms_enabled','hook_send_email_enabled','hook_before_user_created_enabled','hook_after_user_created_enabled'];
const canonical=x=>Array.isArray(x)?x.map(canonical):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])])):x;
const equal=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const plain=x=>x!==null&&typeof x==='object'&&!Array.isArray(x)&&Object.getPrototypeOf(x)===Object.prototype;
export const hash=x=>createHash('sha256').update(x).digest('hex');
export class Refusal extends Error {constructor(code){super(code);this.code=code;}}
const need=(ok,code)=>{if(!ok)throw new Refusal(code);};

// Narrow copies of reviewed recipientKey/sealJournal/privateWrite mechanisms.
// No import can reach executePreparation, transactionSql, a seed or invoice generation.
export function recipientKey(pem,fp) {
  need(typeof pem==='string'&&pem.startsWith('-----BEGIN PUBLIC KEY-----')&&!pem.includes('PRIVATE')&&HEX.test(fp??''),'RECIPIENT');
  let key;try{key=createPublicKey(pem);}catch{throw new Refusal('RECIPIENT');}
  need(key.asymmetricKeyType==='rsa'&&key.asymmetricKeyDetails.modulusLength===4096&&hash(key.export({type:'spki',format:'der'}))===fp,'RECIPIENT');return key;
}
export function sealJournal(payload,key) {
  const plaintext=Buffer.from(JSON.stringify(payload));need(plaintext.length<=1024*1024,'CHECKPOINT_SIZE');
  const secret=randomBytes(32),iv=randomBytes(12);
  try{const cipher=createCipheriv('aes-256-gcm',secret,iv),ciphertext=Buffer.concat([cipher.update(plaintext),cipher.final()]);
    return {format:'JOLENE_STRIPE_PROVIDER_ACTORS_ENCRYPTED_V1',cipher:'AES-256-GCM',keyWrap:'RSA-OAEP-SHA256',
      wrappedKey:publicEncrypt({key,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},secret).toString('base64'),
      iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),ciphertext:ciphertext.toString('base64')};
  }finally{secret.fill(0);plaintext.fill(0);}
}
export async function writeEncryptedCheckpoint(path,envelope,replace=false) {
  // Caller owns a 0700 RUNNER_TEMP directory; path is never a workflow input.
  need(typeof path==='string'&&resolve(path)===path&&basename(path)==='stripe-provider.encrypted.json','PRIVATE_OUTPUT_PATH');
  const directory=dirname(path),stat=await lstat(directory);
  need(stat.isDirectory()&&!stat.isSymbolicLink()&&(stat.mode&0o077)===0&&stat.uid===process.getuid()&&await realpath(directory)===directory,'PRIVATE_OUTPUT_DIRECTORY');
  need(envelope?.format==='JOLENE_STRIPE_PROVIDER_ACTORS_ENCRYPTED_V1'
    &&Object.keys(envelope).sort().join()==='cipher,ciphertext,format,iv,keyWrap,tag,wrappedKey','ENCRYPTED_OUTPUT_REQUIRED');
  const target=replace?`${path}.next`:path,fd=await open(target,'wx',0o600);
  try{await fd.writeFile(JSON.stringify(envelope));await fd.sync();}finally{await fd.close();}
  if(replace)await rename(target,path);
}

function checkBaseContext(c,env,local,now,credentials) {
  need(c?.ready===true&&c.canExecute===true,'READINESS_CLOSED');
  need(c.schemaVersion===1&&c.purpose===PURPOSE&&c.projectRef===PROJECT&&c.platformId===PLATFORM&&c.apiVersion===API_VERSION
    &&c.frontendCompletedReviewed===true&&c.authJournalReviewed===true&&c.stripeWebhookSafetyReviewed===true
    &&/^auth-test-ci-[1-9][0-9]{0,19}-1:[a-f0-9]{40}$/.test(c.authOwner??'')&&SHA.test(c.authSourceSha??'')&&c.authOwner.endsWith(':'+c.authSourceSha)
    &&HEX.test(c.authJournalSha256??'')&&HEX.test(c.uiEvidenceSha256??'')
    &&SHA.test(c.reviewedSourceSha??'')&&SHA.test(c.reviewedSourceTree??'')&&typeof c.reviewedBy==='string'&&c.reviewedBy.trim().length>=3
    &&Date.parse(c.expiresAt)>now&&Date.parse(c.expiresAt)-now<=4*3600000,'CONTRACT');
  need(env.GITHUB_ACTIONS==='true'&&env.GITHUB_EVENT_NAME==='workflow_dispatch'&&env.GITHUB_REPOSITORY===REPO
    &&env.GITHUB_REF==='refs/heads/main'&&SHA.test(env.EXPECTED_MAIN_SHA??'')&&env.GITHUB_SHA===env.EXPECTED_MAIN_SHA
    &&local?.sha===env.GITHUB_SHA&&local.clean===true&&/^[1-9][0-9]{0,19}$/.test(env.GITHUB_RUN_ID??'')&&env.GITHUB_RUN_ATTEMPT==='1','TRUSTED_MAIN');
  need(equal(Object.keys(c.sourcePins??{}).sort(),[...SOURCE_FILES].sort())
    &&SOURCE_FILES.every(p=>HEX.test(c.sourcePins[p]??'')&&typeof local.sources?.[p]==='string'&&hash(local.sources[p])===c.sourcePins[p]),'SOURCE_PINS');
  if(credentials)need(/^(?:sk|rk)_test_[A-Za-z0-9]+$/.test(env.STRIPE_TEST_SECRET_KEY??'')
    &&['GITHUB_TOKEN','STAGING_SUPABASE_ACCESS_TOKEN'].every(k=>typeof env[k]==='string'&&env[k].length>10)
    &&!env.STAGING_SUPABASE_SERVICE_ROLE_KEY&&!env.STAGING_SUPABASE_ANON_KEY,'RUNNER_TEST_CREDENTIALS');
  else need(!env.STRIPE_TEST_SECRET_KEY&&!env.GITHUB_TOKEN&&!env.STAGING_SUPABASE_ACCESS_TOKEN,'CHECK_MUST_HAVE_NO_CREDENTIALS');
}
export function checkVersionedContext(c,env,local,now=Date.now(),credentials=true) {
  checkBaseContext(c,env,local,now,credentials);need(c.actors===null,'VERSIONED_UIDS_FORBIDDEN');
}
export function checkContext(m,c,env,local,now=Date.now(),credentials=true) {
  need(c?.ready===true&&c.canExecute===true,'READINESS_CLOSED');
  need(m?.schemaVersion===1&&m.purpose===PURPOSE&&m.projectRef===PROJECT&&m.platformId===PLATFORM
    &&m.authPurpose==='AUTH_ONLY_FRONTEND_V1'&&/^auth-test-ci-[1-9][0-9]{0,19}-1:[a-f0-9]{40}$/.test(m.authOwner??'')
    &&equal(Object.keys(m.actors??{}).sort(),['etablissement','soignant'])
    &&UUID.test(m.actors?.soignant??'')&&UUID.test(m.actors?.etablissement??'')&&m.actors.soignant!==m.actors.etablissement
    &&HEX.test(m.authJournalSha256??'')&&HEX.test(m.uiEvidenceSha256??'')&&plain(m.steps)&&Object.keys(m.steps).length===0,'ACTORS_OR_NO_RETRY');
  checkBaseContext(c,env,local,now,credentials);
  need(equal(c.actors,m.actors)&&c.authOwner===m.authOwner&&c.authJournalSha256===m.authJournalSha256&&c.uiEvidenceSha256===m.uiEvidenceSha256,'CONTRACT');
}

export function manifestFromContract(c,actors) {
  need(plain(actors)&&equal(Object.keys(actors).sort(),['etablissement','soignant'])&&Object.values(actors).every(x=>UUID.test(x??''))&&actors.soignant!==actors.etablissement,'DISCOVERY_ACTORS');
  return {schemaVersion:1,purpose:PURPOSE,projectRef:PROJECT,platformId:PLATFORM,authPurpose:'AUTH_ONLY_FRONTEND_V1',
    authOwner:c.authOwner,actors:structuredClone(actors),authJournalSha256:c.authJournalSha256,uiEvidenceSha256:c.uiEvidenceSha256,steps:{}};
}
export function discoverySql(c) {
  need(/^auth-test-ci-[1-9][0-9]{0,19}-1:[a-f0-9]{40}$/.test(c.authOwner??'')&&SHA.test(c.authSourceSha??'')&&c.authOwner.endsWith(':'+c.authSourceSha),'DISCOVERY_OWNER');
  const owner=c.authOwner;
  return `BEGIN READ ONLY; SET LOCAL statement_timeout='20s';
DO $readonly$ BEGIN IF current_setting('transaction_read_only')<>'on' OR current_user<>'postgres' OR session_user NOT IN('postgres','supabase_admin') THEN RAISE EXCEPTION 'STRIPE_PROVIDER_READ_CONTEXT'; END IF; END $readonly$;
WITH cohort AS (SELECT id,email,raw_app_meta_data,email_confirmed_at,deleted_at,banned_until FROM auth.users WHERE raw_app_meta_data->>'jolene_auth_fixture_owner'='${owner}')
SELECT jsonb_build_object('ownerCount',(SELECT count(*) FROM cohort),
 'auth',(SELECT jsonb_agg(jsonb_build_object('id',id,'email',email,'metadata',raw_app_meta_data,'confirmed',email_confirmed_at IS NOT NULL,'deleted',deleted_at IS NOT NULL,'banned',banned_until>now()) ORDER BY id) FROM cohort),
 'soignants',(SELECT jsonb_agg(jsonb_build_object('id',s.id,'prenom',s.prenom,'nom',s.nom,'email',s.email,'est_compte_test',s.est_compte_test,'supprime_le',s.supprime_le,'stripe_account_id',s.stripe_account_id) ORDER BY s.id) FROM public.soignants s JOIN cohort u ON u.id=s.id),
 'etablissements',(SELECT jsonb_agg(jsonb_build_object('id',e.id,'nom',e.nom,'email_contact',e.email_contact,'est_compte_test',e.est_compte_test,'supprime_le',e.supprime_le,'stripe_customer_id',e.stripe_customer_id,'stripe_account_id',e.stripe_account_id) ORDER BY e.id) FROM public.etablissements e JOIN cohort u ON u.id=e.id)) AS receipt; ROLLBACK;`;
}
export function deriveActors(discovery,c) {
  need(discovery?.ownerCount===2&&Array.isArray(discovery.auth)&&discovery.auth.length===2&&new Set(discovery.auth.map(x=>x.id)).size===2,'DISCOVERY_COHORT');
  const roles=[['soignant','SOIGNANT'],['etablissement','ADMIN_ETABLISSEMENT']],actors={};
  for(const [kind,role]of roles){const rows=discovery.auth.filter(x=>x.metadata?.role===role);need(rows.length===1&&UUID.test(rows[0].id??''),'DISCOVERY_ROLES');actors[kind]=rows[0].id;}
  const manifest=manifestFromContract(c,actors);validateProfiles(discovery,manifest);
  need(projectionDigest(transmissionProjection(discovery,manifest))===c.uiEvidenceSha256,'UI_TRANSMISSION_PROJECTION');
  return {manifest,contract:{...c,actors}};
}
export function requireComplete(payload) {
  const m=payload?.manifest,requests=payload?.requests,projection=payload?.projection;
  need(payload?.format==='JOLENE_STRIPE_PROVIDER_ACTORS_PRIVATE_V1'&&payload.purpose===PURPOSE&&payload.projectRef===PROJECT&&payload.platformId===PLATFORM
    &&payload.prepared===true&&SHA.test(payload.mainSha??'')&&/^[1-9][0-9]{0,19}$/.test(payload.runId??'')&&payload.runAttempt===1
    &&payload.qualificationVerified===false&&payload.onboardingVerified===false&&payload.paymentCreated===false&&payload.refundCreated===false
    &&m?.schemaVersion===1&&m.purpose===PURPOSE&&m.projectRef===PROJECT&&m.platformId===PLATFORM&&m.authPurpose==='AUTH_ONLY_FRONTEND_V1'
    &&/^auth-test-ci-[1-9][0-9]{0,19}-1:[a-f0-9]{40}$/.test(m.authOwner??'')&&HEX.test(m.authJournalSha256??'')&&HEX.test(m.uiEvidenceSha256??'')
    &&plain(m.actors)&&equal(Object.keys(m.actors).sort(),['etablissement','soignant'])&&UUID.test(m.actors.soignant??'')&&UUID.test(m.actors.etablissement??'')&&m.actors.soignant!==m.actors.etablissement
    &&plain(m.steps)&&Object.keys(m.steps).sort().join()==='account,customer'&&plain(requests)&&Object.keys(requests).sort().join()==='account,customer','INCOMPLETE_HANDOFF');
  const customer=requests.customer,account=requests.account;
  need(plain(customer)&&plain(account)&&Object.values(customer).every(x=>typeof x==='string')&&Object.values(account).every(x=>typeof x==='string')
    &&equal(requests,providerRequests(m,{prenom:account['individual[first_name]'],nom:account['individual[last_name]'],email:account.email},{nom:customer.name,email_contact:customer.email})),'INCOMPLETE_HANDOFF');
  const actors=Object.fromEntries(['soignant','etablissement'].map(kind=>[kind,{id:m.actors[kind],profileTest:true,authTest:true,authOwner:m.authOwner}]));
  need(equal(projection,{schemaVersion:1,purpose:PURPOSE,projectRef:PROJECT,platformId:PLATFORM,authOwner:m.authOwner,actors,requests})
    &&projectionDigest(projection)===m.uiEvidenceSha256,'INCOMPLETE_HANDOFF');
  for(const kind of ['customer','account']) {
    const step=m.steps[kind],actor=m.actors[kind==='customer'?'etablissement':'soignant'];
    need(plain(step)&&Object.keys(step).sort().join()==='idempotencyKey,requestSha256,result,state'&&step.state==='done'
      &&step.requestSha256===projectionDigest(requests[kind])&&step.idempotencyKey===`jolene-stripe-provider-test-v1:${kind}:${hash(m.authOwner+':'+actor)}`
      &&plain(step.result)&&Object.keys(step.result).join()==='id'&&(kind==='customer'?/^cus_[A-Za-z0-9]+$/:/^acct_[A-Za-z0-9]+$/).test(step.result.id??'')
      &&!['acct_1UKlZCEVhQI2aaZg',PLATFORM].includes(step.result.id),'INCOMPLETE_HANDOFF');
  }
  need(equal(payload.result,{prepared:true,stripeObjectsCreated:2,dbLinked:false,onboardingVerified:false,qualificationVerified:false,paymentCreated:false,refundCreated:false}),'INCOMPLETE_HANDOFF');
  return payload;
}

export function snapshotSql(m) {
  need(UUID.test(m?.actors?.soignant??'')&&UUID.test(m?.actors?.etablissement??'')&&m.actors.soignant!==m.actors.etablissement
    &&/^auth-test-ci-[1-9][0-9]{0,19}-1:[a-f0-9]{40}$/.test(m.authOwner??''),'ACTORS');
  const s=`'${m.actors.soignant}'::uuid`,e=`'${m.actors.etablissement}'::uuid`,ids=`${s},${e}`;
  return `BEGIN READ ONLY; SET LOCAL statement_timeout='20s';
DO $readonly$ BEGIN IF current_setting('transaction_read_only')<>'on' OR current_user<>'postgres' OR session_user NOT IN('postgres','supabase_admin') THEN RAISE EXCEPTION 'STRIPE_PROVIDER_READ_CONTEXT'; END IF; END $readonly$;
SELECT jsonb_build_object(
 'auth',(SELECT jsonb_agg(jsonb_build_object('id',id,'email',email,'metadata',raw_app_meta_data,'confirmed',email_confirmed_at IS NOT NULL,'deleted',deleted_at IS NOT NULL,'banned',banned_until>now()) ORDER BY id) FROM auth.users WHERE id IN(${ids})),
 'soignants',(SELECT jsonb_agg(to_jsonb(x)) FROM public.soignants x WHERE id=${s}),
 'etablissements',(SELECT jsonb_agg(to_jsonb(x)) FROM public.etablissements x WHERE id=${e}),
 'ownerCount',(SELECT count(*) FROM auth.users WHERE raw_app_meta_data->>'jolene_auth_fixture_owner'='${m.authOwner}'),
 'business',(SELECT jsonb_build_object(
  'missions',(SELECT count(*) FROM public.missions WHERE etablissement_id IN(${ids}) OR soignant_assigne_id IN(${ids})),
  'candidatures',(SELECT count(*) FROM public.candidatures WHERE soignant_id IN(${ids})),
  'contracts',(SELECT count(*) FROM public.contrats_mission WHERE soignant_id IN(${ids}) OR etablissement_id IN(${ids})),
  'invoices',(SELECT count(*) FROM public.factures_honoraires WHERE soignant_id IN(${ids}) OR etablissement_id IN(${ids}))+(SELECT count(*) FROM public.factures WHERE etablissement_id IN(${ids})),
  'mandates',(SELECT count(*) FROM public.mandats_facturation_signatures WHERE soignant_id IN(${ids})),
  'onboarding',(SELECT count(*) FROM public.stripe_connect_onboarding WHERE soignant_id IN(${ids})),
  'payments',(SELECT count(*) FROM public.paiements_mission WHERE etablissement_id IN(${ids}))+(SELECT count(*) FROM public.stripe_transfers WHERE soignant_id IN(${ids}) OR etablissement_id IN(${ids})))),
 'quiet',jsonb_build_object('queuedRequests',(SELECT count(*) FROM net.http_request_queue),'activeCrons',(SELECT count(*) FROM cron.job WHERE active),'runningCrons',(SELECT count(*) FROM cron.job_run_details WHERE end_time IS NULL AND status IN('starting','running','connecting','sending'))),
 'catalogue',jsonb_build_object(
  'routinesMd5',(SELECT md5(string_agg(p.oid::regprocedure::text||':'||pg_get_functiondef(p.oid),E'\n' ORDER BY p.oid::regprocedure::text)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private') AND p.prokind IN('f','p')),
  'triggersMd5',(SELECT md5(string_agg(t.tgrelid::regclass::text||':'||pg_get_triggerdef(t.oid)||':'||t.tgenabled::text,E'\n' ORDER BY t.tgrelid::regclass::text,t.tgname)) FROM pg_trigger t JOIN pg_class x ON x.oid=t.tgrelid JOIN pg_namespace n ON n.oid=x.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN('public','private','auth','storage'))
 )) AS receipt; ROLLBACK;`;
}
export function validateProfiles(x,m) {
  need(x?.ownerCount===2&&Array.isArray(x.auth)&&x.auth.length===2&&x.soignants?.length===1&&x.etablissements?.length===1,'UI_PROFILES_REQUIRED');
  for(const [kind,role]of [['soignant','SOIGNANT'],['etablissement','ADMIN_ETABLISSEMENT']]) {
    const a=x.auth.filter(a=>a.id===m.actors[kind]);need(a.length===1,'AUTH_OWNERSHIP');const u=a[0],meta=u.metadata;
    need(u.email===`auth-test-${u.id}@example.invalid`&&u.confirmed===true&&u.deleted===false&&(u.banned===false||u.banned===null)
      &&meta?.role===role&&meta.est_compte_test===true&&meta.is_test_playwright===true
      &&meta.jolene_auth_fixture_owner===m.authOwner&&meta.jolene_recette_purpose==='AUTH_ONLY_FRONTEND_V1'
      &&(kind==='etablissement'?meta.etablissement_id===m.actors.etablissement:!Object.hasOwn(meta,'etablissement_id')),'AUTH_OWNERSHIP');
  }
  const s=x.soignants[0],e=x.etablissements[0];
  need(s.id===m.actors.soignant&&e.id===m.actors.etablissement&&s.est_compte_test===true&&e.est_compte_test===true
    &&s.supprime_le===null&&e.supprime_le===null&&s.stripe_account_id===null&&e.stripe_customer_id===null&&e.stripe_account_id===null
    &&[s.prenom,s.nom,s.email,e.nom,e.email_contact].every(v=>typeof v==='string'&&v.trim().length>0),'TEST_PROFILE_OR_EXISTING_LINK');
  return {s,e};
}
export function validateSnapshot(x,m,c) {
  const {s,e}=validateProfiles(x,m);
  need(equal(Object.keys(x.business??{}).sort(),['candidatures','contracts','invoices','mandates','missions','onboarding','payments'])
    &&Object.values(x.business).every(v=>v===0)&&equal(x.quiet,{queuedRequests:0,activeCrons:0,runningCrons:0}),'BUSINESS_OR_QUIESCENCE');
  need(equal(x.catalogue,c.catalogue)&&Object.keys(c.catalogue??{}).sort().join()==='routinesMd5,triggersMd5'
    &&Object.values(c.catalogue).every(v=>/^[a-f0-9]{32}$/.test(v)),'CATALOGUE_DRIFT');
  return {s,e};
}
export function providerRequests(m,s,e) {
  const metadata=kind=>({[`metadata[${kind==='customer'?'etablissement_id':'soignant_id'}]`]:m.actors[kind==='customer'?'etablissement':'soignant'],
    'metadata[jolene_auth_fixture_owner]':m.authOwner,'metadata[jolene_recette_purpose]':PURPOSE});
  return {customer:{name:e.nom,email:e.email_contact,...metadata('customer')},account:{type:'express',country:'FR',business_type:'individual',email:s.email,
    'individual[first_name]':s.prenom,'individual[last_name]':s.nom,'individual[email]':s.email,
    'capabilities[card_payments][requested]':'true','capabilities[transfers][requested]':'true','settings[payouts][schedule][interval]':'manual',...metadata('account')}};
}
export function transmissionProjection(snapshot,m) {
  need(snapshot?.soignants?.length===1&&snapshot.etablissements?.length===1&&snapshot.auth?.length===2,'UI_PROJECTION_SHAPE');
  const actors=Object.fromEntries(['soignant','etablissement'].map(kind=>{
    const profile=snapshot[kind==='soignant'?'soignants':'etablissements'][0],auth=snapshot.auth.find(u=>u.id===m.actors[kind]);
    need(auth&&profile.id===m.actors[kind],'UI_PROJECTION_SHAPE');
    return [kind,{id:profile.id,profileTest:profile.est_compte_test,authTest:auth.metadata?.est_compte_test,authOwner:auth.metadata?.jolene_auth_fixture_owner}];
  }));
  return {schemaVersion:1,purpose:PURPOSE,projectRef:PROJECT,platformId:PLATFORM,authOwner:m.authOwner,actors,
    requests:providerRequests(m,snapshot.soignants[0],snapshot.etablissements[0])};
}
export const projectionDigest=x=>hash(JSON.stringify(canonical(x)));
export function validateWebhookDestinations(endpoints,pins) {
  const historical={id:'we_1TIkpVEVhQ7cb53WwyRXSQwO',url:'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/stripe-webhook',api_version:'2026-03-25.dahlia'};
  const activeIds=['we_1UKmjkEVhQ7cb53W3YeRcmyP','we_1UKmSiEVhQ7cb53WAuAljU47'];
  const normalize=rows=>rows.map(x=>({id:x.id,url:x.url,livemode:x.livemode,api_version:x.api_version,enabled_events:Array.isArray(x.enabled_events)?x.enabled_events.slice().sort():null,status:x.status})).sort((a,b)=>a.id.localeCompare(b.id));
  need(Array.isArray(endpoints)&&endpoints.length===3&&new Set(endpoints.map(x=>x.id)).size===3&&Array.isArray(pins)&&pins.length===3
    &&equal(normalize(endpoints),normalize(pins)),'WEBHOOK_DESTINATIONS');
  const active=endpoints.filter(x=>x.status==='enabled'),old=endpoints.filter(x=>x.status==='disabled');
  need(active.length===2&&old.length===1&&equal(active.map(x=>x.id).sort(),activeIds.slice().sort())
    &&equal(active.map(x=>x.url).sort(),['stripe-connect-webhook','stripe-webhook'].map(slug=>`https://${PROJECT}.supabase.co/functions/v1/${slug}`))
    &&active.every(x=>x.livemode===false&&x.api_version===API_VERSION&&Array.isArray(x.enabled_events))
    &&active.find(x=>x.id===activeIds[0]).url.endsWith('/stripe-connect-webhook')
    &&active.find(x=>x.id===activeIds[0]).enabled_events.includes('account.updated')
    &&old[0].id===historical.id&&old[0].url===historical.url&&old[0].api_version===historical.api_version&&old[0].livemode===false,'WEBHOOK_DESTINATIONS');
}
export function validateCustomer(x,m,body) {
  need(/^cus_[A-Za-z0-9]+$/.test(x?.id??'')&&x.object==='customer'&&x.livemode===false&&!x.deleted
    &&x.name===body.name&&x.email===body.email&&x.metadata?.etablissement_id===m.actors.etablissement
    &&x.metadata.jolene_auth_fixture_owner===m.authOwner&&x.metadata.jolene_recette_purpose===PURPOSE,'CUSTOMER_RECEIPT');
}
export function validateExpress(x,m,body) {
  need(/^acct_[A-Za-z0-9]+$/.test(x?.id??'')&&![PLATFORM,'acct_1UKlZCEVhQI2aaZg'].includes(x.id)
    &&x.object==='account'&&x.type==='express'&&x.country==='FR'&&x.business_type==='individual'&&x.email===body.email
    &&x.individual?.first_name===body['individual[first_name]']&&x.individual.last_name===body['individual[last_name]']&&x.individual.email===body.email
    &&x.metadata?.soignant_id===m.actors.soignant&&x.metadata.jolene_auth_fixture_owner===m.authOwner&&x.metadata.jolene_recette_purpose===PURPOSE
    &&x.settings?.payouts?.schedule?.interval==='manual'&&x.details_submitted===false&&x.charges_enabled===false&&x.payouts_enabled===false
    &&Array.isArray(x.external_accounts?.data)&&x.external_accounts.data.length===0&&!x.tos_acceptance?.date,'EXPRESS_RECEIPT');
}

export async function prepareStripeTestActors({manifest:m,contract:c,env,local,fetcher,save,now=Date.now()}) {
  checkContext(m,c,env,local,now);
  need(typeof fetcher==='function'&&typeof save==='function','TRANSPORT_AND_CHECKPOINT_REQUIRED');
  const key=recipientKey(env.RECIPIENT_PUBLIC_KEY,env.RECIPIENT_SHA256);
  let stripePosts=0,baseline,requests,projection,result=null;
  const checkpoint=async()=>save(sealJournal({format:'JOLENE_STRIPE_PROVIDER_ACTORS_PRIVATE_V1',purpose:PURPOSE,
    projectRef:PROJECT,platformId:PLATFORM,mainSha:local.sha,runId:env.GITHUB_RUN_ID,runAttempt:1,
    manifest:m,requests,projection,result,prepared:result?.prepared===true,
    qualificationVerified:false,onboardingVerified:false,paymentCreated:false,refundCreated:false},key));
  const request=async(scope,path,{body,account,idempotencyKey}={})=>{
    const base=scope==='github'?`https://api.github.com/repos/${REPO}`:scope==='management'?MGMT:STRIPE;
    const token=scope==='github'?env.GITHUB_TOKEN:scope==='management'?env.STAGING_SUPABASE_ACCESS_TOKEN:env.STRIPE_TEST_SECRET_KEY;
    need(scope==='github'?path.startsWith('/'):scope==='management'?['','/config/auth','/functions','/database/query'].includes(path)
      :['/account','/balance','/customers','/accounts','/webhook_endpoints'].includes(path.split('?')[0])||/^\/(customers|accounts)\/[A-Za-z0-9_]+$/.test(path),'ENDPOINT');
    if(scope==='stripe'&&body){need(Date.parse(c.expiresAt)>Date.now(),'CONTRACT_EXPIRED');need(['/customers','/accounts'].includes(path)&&++stripePosts<=2&&typeof idempotencyKey==='string','POST_LIMIT');}
    try{const r=await fetcher(base+path,{method:body?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(25000),
      headers:{Authorization:`Bearer ${token}`,Accept:'application/json',...(scope==='stripe'?{'Stripe-Version':API_VERSION,'Content-Type':'application/x-www-form-urlencoded',...(account?{'Stripe-Account':account}:{}),...(idempotencyKey?{'Idempotency-Key':idempotencyKey}:{})}:{'Content-Type':'application/json'})},
      ...(body?{body:scope==='stripe'?new URLSearchParams(body).toString():JSON.stringify(body)}:{})});
      need(r.ok&&!r.redirected,'HTTP_UNCERTAIN');const text=await r.text();need(Buffer.byteLength(text)<2_000_000,'RESPONSE_LIMIT');return JSON.parse(text);
    }catch(error){if(error instanceof Refusal)throw error;throw new Refusal('TRANSPORT_UNCERTAIN');}
  };
  const list=async path=>{const rows=[];let after;for(let page=0;page<10;page++){
    const r=await request('stripe',`${path}?limit=100${after?`&starting_after=${encodeURIComponent(after)}`:''}`);
    need(r.object==='list'&&Array.isArray(r.data)&&typeof r.has_more==='boolean'&&r.data.every(x=>typeof x.id==='string'),'LIST_SHAPE');
    rows.push(...r.data);if(!r.has_more)return rows;need(r.data.length>0,'LIST_SHAPE');after=r.data.at(-1).id;
  }throw new Refusal('LIST_LIMIT');};
  const preflight=async()=>{
    need(Date.parse(c.expiresAt)>Date.now(),'CONTRACT_EXPIRED');
    const main=await request('github','/git/ref/heads/main');need(main.ref==='refs/heads/main'&&main.object?.sha===local.sha&&main.object.type==='commit','MAIN_MOVED');
    const project=await request('management','');need(project.id===PROJECT&&project.status==='ACTIVE_HEALTHY'&&project.database?.host===`db.${PROJECT}.supabase.co`,'PROJECT_IDENTITY');
    const config=await request('management','/config/auth'),enabled=Object.keys(config).filter(k=>k.startsWith('hook_')&&k.endsWith('_enabled')).sort();
    need(equal(enabled,[...FLAGS].sort())&&FLAGS.every(k=>config[k]===false)&&Object.keys(config).filter(k=>k.startsWith('hook_')).every(k=>FLAGS.includes(k)||FLAGS.some(f=>k.startsWith(f.slice(0,-8)+'_'))),'AUTH_HOOKS');
    const functions=await request('management','/functions');need(Array.isArray(functions)
      &&equal(Object.keys(c.edges??{}).sort(),['stripe-connect-webhook','stripe-webhook'])
      &&Object.entries(c.edges).every(([slug,pin])=>{const r=functions.filter(f=>f.slug===slug);return r.length===1&&r[0].status==='ACTIVE'
        &&Number.isInteger(pin.version)&&pin.version>0&&HEX.test(pin.ezbr_sha256??'')&&typeof pin.verify_jwt==='boolean'
        &&['version','ezbr_sha256','verify_jwt'].every(k=>r[0][k]===pin[k]);}),'WEBHOOK_EDGE_DRIFT');
    const account=await request('stripe','/account'),balance=await request('stripe','/balance');need(account.id===PLATFORM&&balance.object==='balance'&&balance.livemode===false,'PLATFORM_OR_MODE');
    validateWebhookDestinations(await list('/webhook_endpoints'),c.webhookEndpoints);
    const rows=await request('management','/database/query',{body:{query:snapshotSql(m),read_only:false}});need(Array.isArray(rows)&&rows.length===1&&Object.keys(rows[0]).join()==='receipt','SQL_SHAPE');
    const snapshot=rows[0].receipt,profiles=validateSnapshot(snapshot,m,c);if(baseline)need(equal(snapshot,baseline),'BACKEND_CHANGED');
    need(projectionDigest(transmissionProjection(snapshot,m))===c.uiEvidenceSha256,'UI_TRANSMISSION_PROJECTION');
    if(!baseline)baseline=snapshot;
    for(const [kind,path,field]of [['customer','/customers','etablissement_id'],['account','/accounts','soignant_id']]) {
      const existing=await list(path),actor=kind==='customer'?m.actors.etablissement:m.actors.soignant;
      const matches=existing.filter(x=>x.metadata?.[field]===actor||x.metadata?.jolene_auth_fixture_owner===m.authOwner
        ||x.email===(kind==='customer'?profiles.e.email_contact:profiles.s.email));
      const done=m.steps[kind];need(done?done.state==='done'&&matches.length===1&&matches[0].id===done.result.id:matches.length===0,'PROVIDER_COLLISION');
      if(done)(kind==='customer'?validateCustomer:validateExpress)(matches[0],m,requests[kind]);
    }
    return profiles;
  };
  await checkpoint();
  // Source provenance is distinct from the current main commit that only opens its contract.
  const commit=await request('github',`/git/commits/${c.reviewedSourceSha}`);need(commit.sha===c.reviewedSourceSha&&commit.tree?.sha===c.reviewedSourceTree,'REVIEWED_SOURCE');
  for(const path of SOURCE_FILES){const x=await request('github',`/contents/${path}?ref=${c.reviewedSourceSha}`);need(x.type==='file'&&x.encoding==='base64'&&hash(Buffer.from(x.content,'base64'))===c.sourcePins[path],'REVIEWED_BYTES');}
  const runs=await request('github',`/actions/workflows/stripe-test-provider-actors.yml/runs?event=workflow_dispatch&head_sha=${local.sha}&per_page=100`);
  need(runs.total_count===1&&runs.workflow_runs?.length===1&&String(runs.workflow_runs[0].id)===env.GITHUB_RUN_ID&&runs.workflow_runs[0].path===WORKFLOW,'SINGLE_DISPATCH');
  const ownerMatch=/^auth-test-ci-([1-9][0-9]{0,19})-1:([a-f0-9]{40})$/.exec(m.authOwner);
  const authRun=await request('github',`/actions/runs/${ownerMatch[1]}`);
  need(String(authRun.id)===ownerMatch[1]&&authRun.run_attempt===1&&authRun.head_sha===ownerMatch[2]
    &&authRun.path==='.github/workflows/connect-test-fixture.yml'&&authRun.status==='completed'&&authRun.conclusion==='success'
    &&authRun.repository?.full_name===REPO&&authRun.head_repository?.full_name===REPO,'AUTH_PROVENANCE');
  await preflight();projection=transmissionProjection(baseline,m);requests=projection.requests;
  for(const [kind,path,validate]of [['customer','/customers',validateCustomer],['account','/accounts',validateExpress]]) {
    await preflight();const body=requests[kind],actor=m.actors[kind==='customer'?'etablissement':'soignant'];
    const idempotencyKey=`jolene-stripe-provider-test-v1:${kind}:${hash(m.authOwner+':'+actor)}`;
    m.steps[kind]={state:'intent',requestSha256:hash(JSON.stringify(canonical(body))),idempotencyKey};await checkpoint();
    const x=await request('stripe',path,{body,idempotencyKey});validate(x,m,body);
    const reread=await request('stripe',`${path}/${x.id}`);validate(reread,m,body);
    if(kind==='account'){const b=await request('stripe','/balance',{account:x.id});need(b.object==='balance'&&b.livemode===false,'CONNECTED_TEST_MODE');}
    m.steps[kind]={...m.steps[kind],state:'done',result:{id:x.id}};await checkpoint();
    await preflight();
  }
  need(Object.keys(m.steps).sort().join()==='account,customer'&&Object.values(m.steps).every(x=>x.state==='done')&&stripePosts===2,'INCOMPLETE_RECEIPT');
  need(Date.parse(c.expiresAt)>Date.now(),'CONTRACT_EXPIRED');
  result={prepared:true,stripeObjectsCreated:2,dbLinked:false,onboardingVerified:false,qualificationVerified:false,paymentCreated:false,refundCreated:false};
  await checkpoint();return result;
}
