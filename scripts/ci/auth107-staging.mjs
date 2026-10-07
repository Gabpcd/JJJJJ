// Comptes Auth synthétiques de ce run uniquement. Aucun email ni fournisseur.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
const ref='mejpriaetwgtcstbgfid', base=`https://${ref}.supabase.co`;
assert.equal(process.env.CI,'true');
assert.equal(process.env.STAGING_SUPABASE_PROJECT_REF,ref);
assert.equal(process.env.STAGING_SUPABASE_URL,base);
const run=`${process.env.GITHUB_RUN_ID}-${process.env.GITHUB_RUN_ATTEMPT}`;
assert.match(run,/^\d+-\d+$/);
const privatePath=`${process.env.RUNNER_TEMP}/auth107.private.json`;
const phase=process.argv[2];
async function request(path,{method='GET',body,admin=false}={}) {
 const url=admin ? base+path : `https://api.supabase.com/v1/projects/${ref}${path}`;
 const token=admin ? process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY : process.env.STAGING_SUPABASE_ACCESS_TOKEN;
 assert(token);
 const response=await fetch(url,{method,headers:{Authorization:`Bearer ${token}`,
  'Content-Type':'application/json',...(admin?{apikey:token}:{})},redirect:'error',
  ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
 if(!response.ok)throw Error(`AUTH107_HTTP_${response.status}`);
 return response.status===204?null:await response.json();
}
const query=async sql=>request('/database/query',{method:'POST',body:{query:sql}});
const persist=s=>writeFileSync(privatePath,JSON.stringify(s),{mode:0o600});
async function main(){
 if(phase==='prepare'){
  assert(!existsSync(privatePath));
  const settings=await request('/config/auth');
  assert.equal(typeof settings.mailer_autoconfirm,'boolean');
  assert(!settings.security_captcha_enabled,'AUTH107_CAPTCHA_CONFIG_REQUIRES_SEPARATE_TEST');
  const state={run,originalAutoconfirm:settings.mailer_autoconfirm,changed:false,
   emails:['iphone','ipad'].flatMap(device=>['soignant','etab'].map(role=>`auth107-${run}-${device}-${role}@example.invalid`)),
   password:'JoleneTest!'+randomBytes(24).toString('hex')};
  const existing=await query(`SELECT count(*)::int AS n FROM auth.users WHERE email IN (${state.emails.map(x=>`'${x}'`).join(',')})`);
  assert.equal(existing[0].n,0);
  persist(state);
  console.log(`::add-mask::${state.password}`);
  const source=readFileSync(process.argv[3],'utf8');
  assert(source.includes('__RUN__')&&source.includes('__PASSWORD__'));
  writeFileSync(process.argv[3],source.replaceAll('__RUN__',run).replaceAll('__PASSWORD__',state.password));
  console.log('AUTH107_PREPARED_NO_AUTH_CONFIG_CHANGED');
 } else if(phase==='begin'){
  const state=JSON.parse(readFileSync(privatePath));assert.equal(state.run,run);
  const settings=await request('/config/auth');
  assert.equal(settings.mailer_autoconfirm,state.originalAutoconfirm);
  // Même comportement immédiat que la production. Verrou staging tenu par le job.
  state.changed=true;persist(state); // écrire avant la mutation pour permettre sa reprise
  await request('/config/auth',{method:'PATCH',body:{mailer_autoconfirm:true}});
  assert.equal((await request('/config/auth')).mailer_autoconfirm,true);
  console.log('AUTH107_TEST_MODE_READY');
 } else if(phase==='cleanup'){
  if(!existsSync(privatePath)){console.log('AUTH107_NOT_PREPARED');return;}
  const state=JSON.parse(readFileSync(privatePath));assert.equal(state.run,run);
  let restored=false,retired=false,count=0,drafts=0;
  try {
   const actors=await query(`SELECT u.id,(p.user_id IS NOT NULL) AS draft FROM auth.users u LEFT JOIN public.parcours_inscription p ON p.user_id=u.id WHERE u.email IN (${state.emails.map(x=>`'${x}'`).join(',')})`);
   for(const actor of actors){
    assert.match(actor.id,/^[0-9a-f-]{36}$/);
    await request(`/auth/v1/admin/users/${actor.id}`,{method:'PUT',admin:true,body:{ban_duration:'876000h'}});
   }
   count=actors.length;drafts=actors.filter(a=>a.draft).length;
   retired=true;
  } finally {
   if(state.changed)await request('/config/auth',{method:'PATCH',body:{mailer_autoconfirm:state.originalAutoconfirm}});
   restored=(await request('/config/auth')).mailer_autoconfirm===state.originalAutoconfirm;
   const report={mode:'REAL_AUTH_AND_DATABASE_STAGING',run,accountsCreated:count,draftsCreated:drafts,
    testAccountsBanned:retired,authConfigurationRestored:restored,noProductionMutation:true,
    noProviderPayment:true,storeBinaryExecuted:false};
   writeFileSync('test-results/ios-native/auth-cleanup.json',JSON.stringify(report,null,2));
   assert(restored&&retired,'AUTH107_CLEANUP_INCOMPLETE');
  }
 } else throw Error('AUTH107_PHASE');
}
main().catch(error=>{console.error(/^AUTH107_[A-Z_0-9]+$/.test(error.message)?error.message:'AUTH107_FAILED');process.exitCode=1;});
