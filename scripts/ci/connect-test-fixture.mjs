/** Operator-only preparation. No Checkout, PaymentIntent, Refund, transfer, capability allocation or F1 run. */
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { open, readFile, lstat, mkdir, rename, unlink, realpath } from 'node:fs/promises';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { preflightSql, transactionSql, snapshotSql, linkSql } from './connect-test-fixture-sql.mjs';

export const PROJECT='mejpriaetwgtcstbgfid';
export const PLATFORM='acct_1T9pt0EVhQ7cb53W';
export const EXCLUDED_ACCOUNT='acct_1UKlZCEVhQI2aaZg';
const ORIGIN=`https://${PROJECT}.supabase.co`, MANAGEMENT=`https://api.supabase.com/v1/projects/${PROJECT}`;
const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const UUID=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const SHA=/^[a-f0-9]{40}$/;
const ROLES=['SOIGNANT','ADMIN_ETABLISSEMENT','ADMIN_PLATEFORME'];
export const CLOSED_CONTRACT=Object.freeze({schemaVersion:1,ready:false,projectRef:PROJECT,stripePlatformId:PLATFORM,
  sourceSha:null,seedSha256:null,expiresAt:null,reviewedBy:null,notificationsTestSkipReviewed:false,catalogue:null,edges:null,
  protocolEnabled:false,capabilityEnabled:false,reason:'Préparation non exécutée ; provenance, catalogue et canaux à relire avant tout acteur TEST.'});
export class Refusal extends Error { constructor(code){super(code);this.code=code;} }
const requireThat=(ok,code)=>{if(!ok)throw new Refusal(code);};
const digest=value=>createHash('sha256').update(value).digest('hex');
const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
const equal=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const only=rows=>{requireThat(Array.isArray(rows)&&rows.length===1&&Object.keys(rows[0]).join()==='receipt','SQL_SHAPE');return rows[0].receipt;};

function siret(id) {
  const stem=`99${BigInt(`0x${id.replaceAll('-','').slice(0,10)}`).toString().padStart(11,'0').slice(-11)}`;
  for(let n=0;n<10;n++) {const v=stem+n;
    if([...v].reverse().reduce((a,c,i)=>{const x=Number(c)*(i%2?2:1);return a+(x>9?x-9:x);},0)%10===0)return v;}
  throw new Refusal('SIRET');
}
export function newManifest(runId,sourceSha) {
  requireThat(/^connect-test-[a-z0-9-]{8,64}$/.test(runId??'')&&SHA.test(sourceSha??''),'PLAN_CONTEXT');
  const ids=Array.from({length:6},()=>randomUUID());
  const members=ids.slice(0,3).map((id,i)=>({id,email:`connect-test-${id}@example.invalid`,role:ROLES[i],password:`Ct!${randomBytes(36).toString('base64url')}`}));
  const actor=i=>({id:members[i].id,email:members[i].email});
  return {schemaVersion:1,synthetic:true,publicationProven:false,assignmentProven:false,
    sql:{schemaVersion:1,projectRef:PROJECT,runId,sourceSha,ownerMarker:`${runId}:${sourceSha}`,
      actors:{soignant:actor(0),etablissement:actor(1)},sqlActors:{admin:actor(2)},
      ids:{mission:ids[3],equipeAdmin:ids[4],presence:ids[5]},identifiants:{siretSoignant:siret(ids[0]),siretEtablissement:siret(ids[1])}},
    members,steps:{}};
}
export function validateManifest(m) {
  const v=m?.sql;
  requireThat(m?.schemaVersion===1&&m.synthetic===true&&m.publicationProven===false&&m.assignmentProven===false
    &&v?.schemaVersion===1&&v.projectRef===PROJECT&&/^connect-test-[a-z0-9-]{8,64}$/.test(v.runId??'')&&SHA.test(v.sourceSha??'')
    &&v.ownerMarker===`${v.runId}:${v.sourceSha}`&&Array.isArray(m.members)&&m.members.length===3,'MANIFEST');
  const actors=[v.actors?.soignant,v.actors?.etablissement,v.sqlActors?.admin],ids=[...actors.map(x=>x?.id),...Object.values(v.ids??{})];
  requireThat(ids.length===6&&ids.every(x=>UUID.test(x??''))&&new Set(ids).size===6
    &&['mission','equipeAdmin','presence'].every(k=>UUID.test(v.ids?.[k]??'')),'MANIFEST_IDS');
  m.members.forEach((x,i)=>requireThat(x.id===actors[i]?.id&&x.email===`connect-test-${x.id}@example.invalid`&&x.email===actors[i]?.email
    &&x.role===ROLES[i]&&typeof x.password==='string'&&x.password.length>=40,'MANIFEST_ACTORS'));
  requireThat(v.identifiants?.siretSoignant===siret(ids[0])&&v.identifiants?.siretEtablissement===siret(ids[1])
    &&v.identifiants.siretSoignant!==v.identifiants.siretEtablissement&&m.steps&&typeof m.steps==='object','MANIFEST_IDENTIFIERS');
}
export function checkContract(c,m,seed,now=Date.now()) {
  requireThat(c?.ready===true,'READINESS_CLOSED');validateManifest(m);
  requireThat(c.schemaVersion===1&&c.projectRef===PROJECT&&c.stripePlatformId===PLATFORM&&c.sourceSha===m.sql.sourceSha
    &&c.seedSha256===digest(seed)&&c.protocolEnabled===false&&c.capabilityEnabled===false
    &&typeof c.reviewedBy==='string'&&c.reviewedBy.trim().length>=3&&c.notificationsTestSkipReviewed===true
    &&Date.parse(c.expiresAt)>now&&Date.parse(c.expiresAt)-now<=4*3600000,'CONTRACT');
  requireThat(['routines','triggers','columns','commissionHelper'].every(k=>/^[a-f0-9]{32}$/.test(c.catalogue?.[k]??''))
    &&['queuedRequests','activeCrons','runningCrons'].every(k=>c.catalogue?.[k]===0)
    &&['generationUrlAbsent','supportStagingExact','gateClosed','capacitiesEmpty','operationsEmpty'].every(k=>c.catalogue?.[k]===true),'CATALOGUE_PIN');
  for(const slug of ['generate-invoice','send-email','notify-support']) {
    const p=c.edges?.[slug];requireThat(Number.isInteger(p?.version)&&p.version>0&&typeof p.verify_jwt==='boolean'&&/^[a-f0-9]{64}$/.test(p.ezbr_sha256??''),'EDGE_PIN');
  }
}
export function validateAuth(user,member,m) {
  requireThat(user?.id===member.id&&user.email===member.email&&!!user.email_confirmed_at&&!user.deleted_at
    &&(!user.banned_until||Date.parse(user.banned_until)<=Date.now())&&user.app_metadata?.role===member.role
    &&user.app_metadata?.est_compte_test===true&&user.app_metadata?.jolene_connect_fixture_owner===m.sql.ownerMarker
    &&(member.role!=='ADMIN_ETABLISSEMENT'||user.app_metadata?.etablissement_id===member.id),'AUTH_OWNERSHIP');
}
export function validateCustomer(x,m) {
  requireThat(/^cus_[A-Za-z0-9]+$/.test(x?.id??'')&&x.object==='customer'&&x.livemode===false&&!x.deleted
    &&x.metadata?.etablissement_id===m.members[1].id&&x.metadata?.jolene_connect_fixture_owner===m.sql.ownerMarker
    &&x.email===m.members[1].email&&x.name==='TEST Clinique Connect Synthétique','CUSTOMER_OWNERSHIP');
}
export function validateAccount(x,m) {
  requireThat(/^acct_[A-Za-z0-9]+$/.test(x?.id??'')&&x.id!==EXCLUDED_ACCOUNT&&x.id!==PLATFORM&&x.object==='account'
    &&x.type==='express'&&x.country==='FR'&&x.email===m.members[0].email&&x.metadata?.soignant_id===m.members[0].id
    &&x.metadata?.jolene_connect_fixture_owner===m.sql.ownerMarker&&x.settings?.payouts?.schedule?.interval==='manual'
    &&x.details_submitted===false&&x.charges_enabled===false&&x.payouts_enabled===false,'ACCOUNT_OWNERSHIP_OR_ONBOARDING_CHANGED');
}
export function validateSnapshot(r,m,phase) {
  requireThat(r&&Array.isArray(r.auth)&&Array.isArray(r.soignants)&&Array.isArray(r.etablissements)
    &&Array.isArray(r.onboarding)&&Array.isArray(r.invoices)&&Array.isArray(r.commissions),'SNAPSHOT_SHAPE');
  requireThat(r.payments===0&&r.paymentClaims===0&&r.emailQueue===0&&r.emailRetries===0&&r.activeAdmin===0,'UNEXPECTED_EFFECTS');
  for(const user of r.auth) {const member=m.members.find(x=>x.id===user.id);requireThat(member,'HISTORICAL_AUTH');validateAuth(user,member,m);}
  requireThat(new Set(r.auth.map(x=>x.id)).size===r.auth.length,'AUTH_DUPLICATES');
  if(phase==='empty') {
    requireThat(!r.mission&&r.soignants.length===0&&r.etablissements.length===0&&r.onboarding.length===0&&r.invoices.length===0&&r.commissions.length===0,'HISTORICAL_COLLISION');
    return;
  }
  requireThat(r.auth.length===3&&r.soignants.length===1&&r.etablissements.length===1&&r.preferencesClosed===true,'ACTORS_OR_CHANNELS');
  const s=r.soignants[0],e=r.etablissements[0],mission=r.mission;
  requireThat(s.id===m.members[0].id&&s.email===m.members[0].email&&s.test===true&&s.source==='RECETTE_CONNECT_TEST_SYNTHETIQUE'
    &&s.sms===false&&s.smsAlerts===false&&s.defacto===false&&e.id===m.members[1].id&&e.email===m.members[1].email
    &&e.test===true&&e.source==='RECETTE_CONNECT_TEST_SYNTHETIQUE'&&e.sms===false&&e.chorus===false,'PROFILE_OWNERSHIP');
  requireThat(mission?.id===m.sql.ids.mission&&mission.soignant===s.id&&mission.etablissement===e.id&&mission.status==='EN_COURS'
    &&mission.label===`RECETTE CONNECT TEST SYNTHETIQUE ${m.sql.runId}`&&mission.hours===8&&mission.effective===4&&mission.net===160&&mission.commission===24,'SYNTHETIC_MISSION');
  const period=m.steps.seed?.result;
  requireThat(/^\d{4}-\d{2}-\d{2}$/.test(mission.startsOn??'')&&/^\d{4}-\d{2}-\d{2}$/.test(mission.endsOn??'')
    &&period?.periodeDebut>=mission.startsOn&&period?.periodeFin<=mission.endsOn,'PERIOD_OUTSIDE_MISSION');
  if(m.steps.link?.state==='done') {
    requireThat(s.account===m.steps.account.result.id&&e.customer===m.steps.customer.result.id&&r.onboarding.length===1,'STRIPE_LINK');
    const o=r.onboarding[0];requireThat(o.account===s.account&&o.soignant===s.id&&o.status==='EN_COURS'&&[o.complete,o.charges,o.payouts,o.details].every(x=>x===false),'ONBOARDING_CHANGED');
  } else requireThat(!s.account&&!e.customer&&r.onboarding.length===0,'UNEXPECTED_STRIPE_LINK');
  if(phase==='generated') {
    requireThat(r.invoices.length===1&&r.commissions.length===1,'DOCUMENT_COUNT');const f=r.invoices[0],c=r.commissions[0];
    requireThat(UUID.test(f.id)&&f.soignant===s.id&&f.etablissement===e.id&&f.status==='EMISE'&&f.kind==='FACTURE'&&f.nature==='ORIGINALE'
      &&f.total===80&&f.paid===false&&f.versions===1&&typeof f.pdf==='string'&&f.pdf.length>0&&typeof f.xml==='string'&&f.xml.length>0
      &&UUID.test(c.id)&&c.honoraire===f.id&&c.kind==='FACTURE'&&c.status==='EMISE'&&c.total===14.4&&c.linked===false&&r.emailSkips===2,'DOCUMENT_RECONCILIATION');
  } else requireThat(r.invoices.length===0&&r.commissions.length===0,'UNEXPECTED_INVOICE');
}

export async function privateRead(path) {
  const s=await lstat(path);requireThat(s.isFile()&&!s.isSymbolicLink()&&(s.mode&0o077)===0&&s.uid===process.getuid(),'PRIVATE_FILE');
  return JSON.parse(await readFile(path,'utf8'));
}
export async function privateWrite(path,value,replace=false) {
  const target=replace?`${path}.next`:path,fd=await open(target,'wx',0o600);
  try{await fd.writeFile(JSON.stringify(value,null,2));await fd.sync();}finally{await fd.close();}
  if(replace)await rename(target,path);
}
async function privateDirectory(path) {
  const full=resolve(path),s=await lstat(full);
  requireThat(s.isDirectory()&&!s.isSymbolicLink()&&(s.mode&0o077)===0&&s.uid===process.getuid()&&await realpath(full)===full,'PRIVATE_DIRECTORY');return full;
}
export async function executePreparation({manifest:m,contract:c,env,seed,local,fetcher=fetch,save=async()=>{}}) {
  checkContract(c,m,seed);
  requireThat(local?.sha===c.sourceSha&&local.clean===true,'TRUSTED_SOURCE_REQUIRED');
  requireThat(['STAGING_SUPABASE_ACCESS_TOKEN','STAGING_SUPABASE_SERVICE_ROLE_KEY','STAGING_SUPABASE_ANON_KEY'].every(k=>typeof env[k]==='string'&&env[k].length>10)
    &&/^(?:sk|rk)_test_[A-Za-z0-9]+$/.test(env.STRIPE_TEST_SECRET_KEY??''),'TEST_CREDENTIALS_REQUIRED');
  const request=async(scope,path,{method='GET',body,idempotencyKey,account,token}={})=>{
    let base,headers;
    if(scope==='management'){base=MANAGEMENT;headers={Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`};}
    else if(scope==='github'){base='https://api.github.com/repos/Gabpcd/JJJJJ';headers={Accept:'application/vnd.github+json','User-Agent':'Jolene-connect-test-fixture'};}
    else if(scope==='stripe'){base='https://api.stripe.com/v1';headers={Authorization:`Bearer ${env.STRIPE_TEST_SECRET_KEY}`,'Stripe-Version':'2026-02-25.clover',...(idempotencyKey?{'Idempotency-Key':idempotencyKey}:{}),...(account?{'Stripe-Account':account}:{})};}
    else {base=ORIGIN;headers={apikey:env.STAGING_SUPABASE_ANON_KEY,Authorization:`Bearer ${token??env.STAGING_SUPABASE_SERVICE_ROLE_KEY}`};}
    try {
      const response=await fetcher(base+path,{method,redirect:'error',signal:AbortSignal.timeout(55000),headers:{...headers,'Content-Type':scope==='stripe'?'application/x-www-form-urlencoded':'application/json'},
        ...(body===undefined?{}:{body:scope==='stripe'?new URLSearchParams(body).toString():JSON.stringify(body)})});
      requireThat(response.ok&&!response.redirected,'HTTP_REFUSED');const text=await response.text();requireThat(Buffer.byteLength(text)<2_000_000,'RESPONSE_TOO_LARGE');return JSON.parse(text);
    }catch(error){if(error instanceof Refusal)throw error;throw new Refusal('TRANSPORT_OR_JSON_UNCERTAIN');}
  };
  const query=async(sql,readOnly=true)=>only(await request('management','/database/query',{method:'POST',body:{query:sql,read_only:readOnly}}));
  const snapshot=async phase=>{const r=await query(snapshotSql(m.sql));validateSnapshot(r,m,phase);return r;};
  const preflight=async()=>{
    checkContract(c,m,seed);
    const main=await request('github','/git/ref/heads/main');requireThat(main?.ref==='refs/heads/main'&&main.object?.sha===c.sourceSha&&main.object?.type==='commit','MAIN_MOVED');
    const project=await request('management','');requireThat(project?.id===PROJECT&&project.status==='ACTIVE_HEALTHY'&&project.database?.host===`db.${PROJECT}.supabase.co`,'PROJECT_IDENTITY');
    const edges=await request('management','/functions');requireThat(Array.isArray(edges),'EDGE_CATALOGUE');
    for(const [slug,pin] of Object.entries(c.edges)) {const x=edges.filter(x=>x.slug===slug);requireThat(x.length===1&&x[0].status==='ACTIVE'&&['version','verify_jwt','ezbr_sha256'].every(k=>x[0][k]===pin[k]),'EDGE_DRIFT');}
    requireThat(equal(await query(preflightSql()),c.catalogue),'CATALOGUE_DRIFT');
    const platform=await request('stripe','/account'),balance=await request('stripe','/balance');
    requireThat(platform?.id===PLATFORM&&balance?.livemode===false,'STRIPE_PLATFORM_OR_MODE');
  };
  const step=async(name,action)=>{
    if(m.steps[name]) {requireThat(m.steps[name].state==='done','AMBIGUOUS_PREVIOUS_ATTEMPT');return m.steps[name].result;}
    await preflight();m.steps[name]={state:'intent'};await save(m);
    const result=await action();m.steps[name]={state:'done',result};await save(m);return result;
  };
  // An intent without receipt never retries, including after network timeout/crash.
  requireThat(Object.values(m.steps).every(x=>x.state==='done'),'AMBIGUOUS_PREVIOUS_ATTEMPT');
  await preflight();await snapshot(m.steps.generate?'generated':m.steps.seed?'seeded':'empty');
  for(const [i,member] of m.members.entries()) {
    await step(`auth${i}`,async()=>{const u=await request('auth','/auth/v1/admin/users',{method:'POST',body:{id:member.id,email:member.email,password:member.password,email_confirm:true,
      app_metadata:{role:member.role,est_compte_test:true,is_test_playwright:true,jolene_connect_fixture_owner:m.sql.ownerMarker,...(i===1?{etablissement_id:member.id}:{})}}});validateAuth(u?.user??u,member,m);return {id:member.id};});
    const reread=await request('auth',`/auth/v1/admin/users/${member.id}`);validateAuth(reread?.user??reread,member,m);
  }
  await step('seed',async()=>{
    await snapshot('empty');const r=await query(transactionSql(m,c.catalogue,seed),false);
    requireThat(r?.runId===m.sql.runId&&r.missionId===m.sql.ids.mission&&r.montantOriginal===80&&r.commissionTtc===14.4
      &&r.signatureSynthetique===true&&r.qualificationVerifiee===false&&r.mfaProuve===false,'SEED_RECEIPT');return r;
  });
  await snapshot(m.steps.generate?'generated':'seeded');
  const customer=await step('customer',async()=>{
    const x=await request('stripe','/customers',{method:'POST',idempotencyKey:`customer_etablissement_${m.members[1].id}`,body:{
      name:'TEST Clinique Connect Synthétique',email:m.members[1].email,'metadata[etablissement_id]':m.members[1].id,'metadata[jolene_connect_fixture_owner]':m.sql.ownerMarker}});
    validateCustomer(x,m);return {id:x.id};
  });
  validateCustomer(await request('stripe',`/customers/${customer.id}`),m);
  const account=await step('account',async()=>{
    const x=await request('stripe','/accounts',{method:'POST',idempotencyKey:`connect_account_${m.members[0].id}`,body:{type:'express',country:'FR',email:m.members[0].email,business_type:'individual',
      'individual[first_name]':'Connect','individual[last_name]':'TEST Synthétique','individual[email]':m.members[0].email,
      'capabilities[card_payments][requested]':'true','capabilities[transfers][requested]':'true','settings[payouts][schedule][interval]':'manual',
      'metadata[soignant_id]':m.members[0].id,'metadata[jolene_connect_fixture_owner]':m.sql.ownerMarker}});
    validateAccount(x,m);return {id:x.id};
  });
  validateAccount(await request('stripe',`/accounts/${account.id}`),m);
  const connectedBalance=await request('stripe','/balance',{account:account.id});requireThat(connectedBalance?.livemode===false,'CONNECTED_MODE');
  await step('link',async()=>{await snapshot('seeded');const r=await query(transactionSql(m,c.catalogue,linkSql(m.sql,customer,account)),false);requireThat(r?.linked===true,'LINK_RECEIPT');return r;});
  await snapshot(m.steps.generate?'generated':'seeded');
  await step('generate',async()=>{
    const auth=await request('auth','/auth/v1/token?grant_type=password',{method:'POST',token:env.STAGING_SUPABASE_ANON_KEY,body:{email:m.members[0].email,password:m.members[0].password}});
    validateAuth(auth.user,m.members[0],m);requireThat(typeof auth.access_token==='string'&&auth.access_token.length>20,'GENERATOR_AUTH');
    const r=m.steps.seed.result,start=new Date(`${r.periodeDebut}T00:00:00Z`),end=new Date(`${r.periodeFin}T00:00:00Z`);
    requireThat(start.getUTCDay()===1&&end.getUTCDay()===0&&+end-+start===6*86400000&&+end<Date.now(),'SEED_PERIOD');
    const thursday=new Date(+start+3*86400000),year=thursday.getUTCFullYear(),jan4=new Date(Date.UTC(year,0,4)),monday=new Date(+jan4-((jan4.getUTCDay()+6)%7)*86400000);
    const response=await request('auth','/functions/v1/generate-invoice',{method:'POST',token:auth.access_token,body:{mission_id:m.sql.ids.mission,periode_debut:r.periodeDebut,periode_fin:r.periodeFin,
      numero_semaine_iso:1+Math.round((+start-+monday)/(7*86400000)),annee_iso:year,est_facture_finale_mission:false}});
    requireThat(UUID.test(response?.facture_id??'')&&typeof response.pdf_path==='string'&&typeof response.xml_path==='string','GENERATOR_RECEIPT');
    const after=await snapshot('generated');requireThat(after.invoices[0].id===response.facture_id&&after.invoices[0].pdf===response.pdf_path&&after.invoices[0].xml===response.xml_path,'GENERATOR_BINDING');
    // Store only non-secret identifiers; login tokens never enter the journal.
    return {invoiceId:response.facture_id,commissionId:after.commissions[0].id};
  });
  await preflight();const result=await snapshot('generated');
  return {prepared:true,synthetic:true,publicationProven:false,assignmentProven:false,onboardingComplete:false,uiPaymentVerified:false,
    paymentCreated:false,capabilityAllocated:false,invoiceId:result.invoices[0].id,commissionId:result.commissions[0].id};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  let lockPath,ownsLock=false;
  try {
    const [mode,path,run,sha]=process.argv.slice(2);
    if(mode==='plan'&&process.argv.length===6) {
      const m=newManifest(run,sha),directory=resolve(path);await mkdir(directory,{mode:0o700});await privateDirectory(directory);
      await privateWrite(join(directory,'manifest.private.json'),m);await privateWrite(join(directory,'contract.private.json'),CLOSED_CONTRACT);
      console.log(JSON.stringify({planned:true,ready:false,directory,remoteCalls:0}));
    } else if(mode==='prepare'&&process.argv.length===4) {
      const directory=await privateDirectory(path),c=await privateRead(join(directory,'contract.private.json')),m=await privateRead(join(directory,'manifest.private.json'));
      const seed=await readFile(new URL('./connect-test-fixture-prepare.sql',import.meta.url),'utf8');checkContract(c,m,seed);
      lockPath=join(directory,'execution.lock');const fd=await open(lockPath,'wx',0o600);ownsLock=true;await fd.close();
      const git=args=>execFileSync('git',['-C',ROOT,...args],{env:{PATH:process.env.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'},encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:15000}).trim();
      const result=await executePreparation({manifest:m,contract:c,env:process.env,seed,local:{sha:git(['rev-parse','HEAD']),clean:git(['status','--porcelain'])===''},save:value=>privateWrite(join(directory,'manifest.private.json'),value,true)});
      await privateWrite(join(directory,'result.private.json'),result,true);console.log(JSON.stringify({prepared:true,uiPaymentVerified:false,onboardingComplete:false}));
    } else throw new Refusal('USAGE_PLAN_DIRECTORY_RUN_SHA_OR_PREPARE_DIRECTORY');
  }catch(error){console.error(JSON.stringify({prepared:false,code:error instanceof Refusal?error.code:'LOCAL_OR_UNEXPECTED_FAILURE'}));process.exitCode=1;}
  finally{if(ownsLock)await unlink(lockPath).catch(()=>{});}
}
