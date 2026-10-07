// Manual TEST-only alignment with the two already-reviewed production migrations.
// No database reset, account creation, provider request or business-data rewrite.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {sqlCatalogueD,literal} from './candidatures-fixture-contract.mjs';
import {structuralJsonSql} from './connect-staging-closed-sql.mjs';
export const PROJECT='mejpriaetwgtcstbgfid';
const REPO='Gabpcd/JJJJJ';
const digest=b=>createHash('sha256').update(b).digest('hex');
const fail=code=>{throw Error(code);};
const exact=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const businessTables=['auth.users','auth.sessions','auth.refresh_tokens','public.soignants','public.etablissements',
 'public.missions','public.mission_creneaux','public.candidatures','public.contrats_mission','public.signatures_contrats',
 'public.factures_honoraires','public.factures','public.litiges','public.paiements_soignant','public.paiements_mission',
 'public.paiements_escrow','public.stripe_transfers','public.stripe_payment_flow_claims','public.stripe_webhook_events',
 'public.stripe_refunds_queue','public.escrow_release_queue','public.externalisation_actions','public.invoice_audit_log',
 'public.notifications','public.email_queue','private.stripe_connect_release_gate','private.stripe_connect_test_capacities'];
export function assets(root,contract){
 if(contract.schemaVersion!==1||contract.project!==PROJECT||contract.functions.length!==16
   ||contract.functions.filter(x=>x.revokePublic).length!==12||contract.migrations.length!==2)fail('ASSET_SCOPE');
 const versions=['20261006144554','20261006144619'];
 return contract.migrations.map((m,i)=>{
  if(m.version!==versions[i]||!/^supabase\/migrations\/\d{14}_[a-z0-9_]+\.sql$/.test(m.path)
   ||m.path!==`supabase/migrations/${m.version}_${m.name}.sql`)fail('MIGRATION_PATH');
  const body=readFileSync(resolve(root,m.path),'utf8');
  if(digest(body)!==m.sha256||/^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im.test(body))fail('MIGRATION_BYTES');
  return {...m,body};
 });
}
const metadata=`jsonb_build_object('schema',n.nspname,'signature',p.oid::regprocedure::text,'body',md5(p.prosrc),
 'definition',md5(pg_get_functiondef(p.oid)),'acl',p.proacl,'owner',pg_get_userbyid(p.proowner),'securitydefiner',p.prosecdef,'config',p.proconfig)`;
const quiet=`NOT EXISTS(SELECT 1 FROM cron.job WHERE active)
 AND NOT EXISTS(SELECT 1 FROM cron.job_run_details WHERE end_time IS NULL AND status IN('starting','running','connecting','sending'))
 AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)
 AND NOT EXISTS(SELECT 1 FROM public.escrow_release_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities WHERE enabled)
 AND NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE enabled)`;
function unchangedSql(c){
 const sigs=c.functions.map(x=>literal(x.signature)+'::regprocedure').join(',');
 const inventory=c.functions.filter(x=>!x.revokePublic).map(x=>literal(x.before.signature)).join(',');
 return `SELECT jsonb_build_object(
 'structure',md5(((${structuralJsonSql})-'routines'-'inventory')::text),
 'routines',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(n.nspname,p.oid::regprocedure::text,pg_get_functiondef(p.oid),p.proacl,pg_get_userbyid(p.proowner)) ORDER BY n.nspname,p.oid::regprocedure::text)::text,'[]')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','auth') AND p.prokind IN('f','p') AND p.oid NOT IN(${sigs})),
 'inventory',(SELECT md5(coalesce(jsonb_agg(to_jsonb(i)-'recense_le' ORDER BY signature)::text,'[]')) FROM private.security_definer_inventory i WHERE signature NOT IN(${inventory})),
 'rows',md5(concat_ws('|',${businessTables.map(t=>`(SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,'[]')) FROM ${t} t)`).join(',')}))
 ) value`;
}
function assertFunctions(c,phase){return c.functions.map(x=>`IF (SELECT ${metadata} FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.oid=${literal(x.signature)}::regprocedure) IS DISTINCT FROM ${literal(JSON.stringify(x[phase]))}::jsonb THEN RAISE EXCEPTION 'ALIGN_FUNCTION_${phase.toUpperCase()}'; END IF;`).join('\n');}
export function transaction(c,migrations,commit){
 const versions=migrations.map(m=>literal(m.version)).join(',');
 const expected=c.catalogueBefore;
 return `BEGIN; SET LOCAL search_path=public,pg_catalog; SET LOCAL TIME ZONE 'UTC'; SET LOCAL statement_timeout='60s'; SET LOCAL lock_timeout='3s';
 SELECT pg_advisory_xact_lock(184731,107);
 LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE NOWAIT;
 DO $align_before$ DECLARE v_align_catalogue record; BEGIN
 IF NOT (${quiet}) THEN RAISE EXCEPTION 'ALIGN_NOT_QUIET'; END IF;
 SELECT * INTO v_align_catalogue FROM (${sqlCatalogueD}) q;
 IF v_align_catalogue.schema<>${literal(expected.schema)} OR v_align_catalogue.fonctions<>${literal(expected.fonctions)} OR v_align_catalogue.triggers<>${literal(expected.triggers)} OR v_align_catalogue.crons_actifs<>0 OR v_align_catalogue.audit_fk<>0 THEN RAISE EXCEPTION 'ALIGN_CATALOGUE_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN(${versions})) THEN RAISE EXCEPTION 'ALIGN_ALREADY_APPLIED'; END IF;
 ${assertFunctions(c,'before')}
 END $align_before$;
 CREATE TEMP TABLE align_107_unchanged ON COMMIT DROP AS ${unchangedSql(c)};
 CREATE TEMP TABLE align_107_registry ON COMMIT DROP AS SELECT md5(jsonb_agg(to_jsonb(m) ORDER BY version)::text) value FROM supabase_migrations.schema_migrations m;
 ${migrations.map(m=>m.body).join('\n')}
 ${c.functions.filter(x=>x.revokePublic).map(x=>`REVOKE EXECUTE ON FUNCTION ${x.signature} FROM PUBLIC;`).join('\n')}
 ${migrations.map(m=>`INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(${literal(m.version)},${literal(m.name)},ARRAY[${literal(m.body)}]);`).join('\n')}
 SET LOCAL search_path=public,pg_catalog;
 DO $align_after$ BEGIN
 ${assertFunctions(c,'after')}
 IF NOT (${quiet}) THEN RAISE EXCEPTION 'ALIGN_NOT_QUIET'; END IF;
 IF (SELECT value FROM align_107_unchanged) IS DISTINCT FROM (${unchangedSql(c)}) THEN RAISE EXCEPTION 'ALIGN_UNRELATED_CHANGE'; END IF;
 IF (SELECT value FROM align_107_registry) IS DISTINCT FROM (SELECT md5(jsonb_agg(to_jsonb(m) ORDER BY version)::text) FROM supabase_migrations.schema_migrations m WHERE version NOT IN(${versions})) THEN RAISE EXCEPTION 'ALIGN_REGISTRY_CHANGED'; END IF;
 END $align_after$;
 ${sqlCatalogueD};
 ${commit?'COMMIT':'ROLLBACK'};`;
}
export function context(env,head,clean){
 if(env.GITHUB_ACTIONS!=='true'||env.GITHUB_REPOSITORY!==REPO||env.GITHUB_EVENT_NAME!=='workflow_dispatch'
  ||env.GITHUB_REF!=='refs/heads/main'||!clean||!/^[a-f0-9]{40}$/.test(head)||head!==env.GITHUB_SHA||head!==env.INVOICE_EXPECTED_SHA)fail('TRUSTED_MAIN_REQUIRED');
}
export async function align({env,head,clean,contract,migrations,fetchImpl=fetch,save=()=>{}}){
 const r={schemaVersion:1,status:'failed',project:PROJECT,sourceSha:head,phase:'context',code:null,dryRunVerified:false,commitAttempted:false,commitConfirmed:false,after:null,providerContacted:false,authCreated:false};
 const request=async(url,body,management)=>{
  const res=await fetchImpl(url,{method:body?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(70000),headers:management?{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'}:{Accept:'application/vnd.github+json'},...(body?{body:JSON.stringify(body)}:{})});
  if(!res.ok)fail('HTTP_REFUSED');return res.json();
 };
 const query=(q,readOnly=false)=>request(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`,{query:q,read_only:readOnly},true);
 const main=async()=>{const ref=await request(`https://api.github.com/repos/${REPO}/git/ref/heads/main`);if(ref?.object?.sha!==head)fail('MAIN_MOVED');};
 try{
  context(env,head,clean);if(!env.STAGING_SUPABASE_ACCESS_TOKEN)fail('TOKEN_REQUIRED');await main();
  r.phase='rollback';save(r);const preview=await query(transaction(contract,migrations,false));
  if(!Array.isArray(preview)||preview.length!==1||preview[0].crons_actifs!==0||preview[0].audit_fk!==0)fail('PREVIEW_SHAPE');
  const before=await query('BEGIN READ ONLY; SET LOCAL search_path=public,pg_catalog; '+sqlCatalogueD+'; ROLLBACK;',true);
  if(!Array.isArray(before)||before.length!==1||Object.entries(contract.catalogueBefore).some(([k,v])=>before[0][k]!==v))fail('ROLLBACK_NOT_CONFIRMED');
  r.dryRunVerified=true;await main();r.phase='commit_once';r.commitAttempted=true;save(r);
  const after=await query(transaction(contract,migrations,true));
  if(!exact(preview,after))fail('COMMIT_RESPONSE_MISMATCH');
  r.phase='readback';const final=await query('BEGIN READ ONLY; SET LOCAL search_path=public,pg_catalog; '+sqlCatalogueD+'; ROLLBACK;',true);
  if(!exact(final,after))fail('READBACK_MISMATCH');r.after=after[0];r.commitConfirmed=true;r.status='success';r.phase='complete';
 }catch(e){r.code=/^[A-Z_]+$/.test(e.message)?e.message:'TRANSPORT_OR_SQL_REFUSED';if(r.commitAttempted&&!r.commitConfirmed)r.status='uncertain';}
 save(r);return r;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const root=process.cwd();const c=JSON.parse(readFileSync(resolve(root,'scripts/ci/align-staging-107.contract.json'),'utf8'));
 const git=args=>execFileSync('git',args,{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
 const dir=resolve(process.env.RUNNER_TEMP??'/tmp','align-staging-107-proof');mkdirSync(dir,{recursive:true,mode:0o700});
 align({env:process.env,head:git(['rev-parse','HEAD']),clean:git(['status','--porcelain','--untracked-files=all'])==='',contract:c,migrations:assets(root,c),save:r=>writeFileSync(resolve(dir,'result.json'),JSON.stringify(r,null,2)+'\n',{mode:0o600})}).then(r=>{console.log(JSON.stringify(r));if(r.status!=='success')process.exitCode=1;}).catch(()=>{console.error('ALIGN_LOCAL_REFUSED');process.exitCode=1;});
}
