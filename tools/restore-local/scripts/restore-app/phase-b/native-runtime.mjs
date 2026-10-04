import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { localRuntime } from '../local-runtime.mjs';
import { fileTree, assertEmptyFileTree } from '../snapshot-restore.mjs';
import { projectSqlDiagnostic } from '../../restore/bootstrap.mjs';
import { DB, digest, requireValue } from './contract.mjs';

// Names instead of cluster-local OIDs; values remain in the private snapshot.
export const SETTINGS_SQL = `BEGIN READ ONLY; SET LOCAL statement_timeout='15s';
SELECT coalesce(jsonb_agg(jsonb_build_array(
 CASE WHEN s.setdatabase=0 THEN '*' ELSE d.datname END,
 CASE WHEN s.setrole=0 THEN '*' ELSE r.rolname END,
 ARRAY(SELECT unnest(s.setconfig) ORDER BY 1)) ORDER BY
 CASE WHEN s.setdatabase=0 THEN '*' ELSE d.datname END,
 CASE WHEN s.setrole=0 THEN '*' ELSE r.rolname END),'[]'::jsonb)
FROM pg_db_role_setting s LEFT JOIN pg_database d ON d.oid=s.setdatabase
LEFT JOIN pg_roles r ON r.oid=s.setrole;
ROLLBACK;`;
export const ROLE_SETTINGS_SQL = "ALTER ROLE authenticator SET pgrst.db_pre_request='public.fn_pre_request_compte_actif';\nALTER ROLE authenticator SET statement_timeout='120s';";
const RESTORE_ARGS = ['--exit-on-error','--single-transaction','--no-password','-U','supabase_admin','-h','/var/run/postgresql','-d',DB];

// A negative proof is accepted only for the exact expected missing PDF while
// its companion XML and the post-backup exclusion remain intact.
export function assertObjectWitness(result) {
  const keys=['verified','pdfExact','xmlExact','pdfMissing','xmlMissing','sentinelAbsent'];
  requireValue(result&&typeof result==='object'&&Object.keys(result).length===keys.length
    &&keys.every(key=>Object.hasOwn(result,key))&&Number.isSafeInteger(result.verified)&&result.verified>=0&&result.verified<=2
    &&keys.slice(1).every(key=>typeof result[key]==='boolean'),'B_FILES');
  const witness=Object.fromEntries(keys.map(key=>[key,result[key]]));
  if(!(witness.verified===2&&witness.pdfExact&&witness.xmlExact&&!witness.pdfMissing&&!witness.xmlMissing&&witness.sentinelAbsent)){
    throw Object.assign(Error('B_FILES'),{code:'B_FILES',witness});
  }
  return witness;
}
export async function proveControlledMissingPdf(runtime,fixture) {
  const removed=await runtime.removeKnownTargetPdf(fixture);
  requireValue(removed?.deleted===true&&removed?.status===200,'B_FILES');
  let failure;
  try { await runtime.assertRestoredObjects(fixture); } catch(error) { failure=error; }
  requireValue(failure?.code==='B_FILES'&&failure.witness?.verified===1&&failure.witness.pdfExact===false
    &&failure.witness.xmlExact===true&&failure.witness.pdfMissing===true&&failure.witness.xmlMissing===false
    &&failure.witness.sentinelAbsent===true,'B_FILES');
  await runtime.verifyState({source:'off',target:'running',browser:'absent'});
  return {result:'CONTROLLED_TARGET_PDF_MISSING_REJECTED',expectedCode:'B_FILES',ownedSyntheticPdfRemoved:true,
    sameVerifierRejected:true,xmlStillExact:true,postBackupSentinelAbsent:true,sourceOff:true,providerContacted:false};
}

export function nativeRuntime(privateDir) {
  const base = localRuntime(privateDir), run = base.run;
  const callId=randomUUID();let command = 0, check = 0;
  const call = (args, input) => {
    const result = spawnSync('docker', args, { input, encoding:null, maxBuffer:64*1024*1024, timeout:240_000,
      env:{PATH:process.env.PATH,HOME:process.env.HOME} });
    writeFileSync(join(privateDir,`phase-b-command-${callId}-${++command}.stderr.private`),result.stderr??Buffer.alloc(0),{mode:0o600,flag:'wx'});
    if(result.error||result.status!==0||result.signal!==null) {
      const error=Object.assign(Error('B_CALL'),{code:'B_CALL',diagnostic:projectSqlDiagnostic(result.stderr?.toString()??'')});throw error;
    }
    return result.stdout;
  };
  const targetState=()=>base.verifyState({source:'off',target:'db-only',browser:'absent'});
  const targetSql=async(body,database=DB)=>{
    requireValue([DB,'postgres'].includes(database)); await targetState();
    return call(['exec','-i',`${run}-target-db`,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose',
      '-U','supabase_admin','-h','/var/run/postgresql','-d',database,'-f','-'],Buffer.from(body));
  };
  const runtime={...base,
    catalogue:async side=>({...await base.catalogue(side),databaseRoleSettings:await base.sqlJson(side,SETTINGS_SQL)}),
    assertTargetFilesEmpty:async()=>{
      await targetState();const path=join(privateDir,`target-empty-b-${++check}`);
      await base.copyFilesOut('target',path);assertEmptyFileTree(path);
    },
    recreateOwnedEmptyTargetDatabase:async database=>{
      requireValue(database===DB,'B_RESTORE');await targetState();await base.assertTargetNativeEmpty();await runtime.assertTargetFilesEmpty();
      await targetSql(`DROP DATABASE ${DB};\nCREATE DATABASE ${DB} OWNER postgres TEMPLATE template0;`,'postgres');
      await targetSql('DROP SCHEMA public;');
    },
    databaseTool:async(side,tool,args,bytes)=>{
      if(side==='source')return base.databaseTool(side,tool,args,bytes);
      requireValue(side==='target'&&tool==='pg_restore'&&JSON.stringify(args)===JSON.stringify(RESTORE_ARGS)
        &&Buffer.isBuffer(bytes)&&bytes.subarray(0,5).toString()==='PGDMP'&&bytes.length<64*1024*1024,'B_RESTORE');
      await targetState();return call(['exec','-i',`${run}-target-db`,tool,...args],bytes);
    },
    applyReviewedRoleSettings:async()=>targetSql(ROLE_SETTINGS_SQL),
    copyFilesIn:async(side,source)=>{
      requireValue(side==='target'&&realpathSync(source)===resolve(source)
        &&resolve(source)===join(realpathSync(privateDir),'snapshot','files'),'B_FILES');
      const expected=fileTree(source);await targetState();await runtime.assertTargetFilesEmpty();
      call(['cp','-a',source+'/.',`${run}-target-storage:/var/lib/storage/`]);
      const after=join(privateDir,'target-files-restored');await base.copyFilesOut('target',after);
      requireValue(JSON.stringify(fileTree(after))===JSON.stringify(expected),'B_FILES');
    },
    assertSourceOffAndTargetCatalogExact:async snapshot=>{
      await targetState();requireValue(JSON.stringify(await runtime.catalogue('target'))===JSON.stringify(snapshot.catalogue),'B_RESTORE');
    },
    startSourceForUi:async()=>{
      await base.verifyState({source:'off',target:'db-only',browser:'absent'});
      call(['start',`${run}-source-db`]);
      // docker start does not apply Compose depends_on. Keep every API stopped
      // until the restarted DB is healthy; revalidate the complete owned plan.
      let databaseReady=false;
      for(let attempt=0;attempt<60;attempt++){
        await base.verifyState({source:'db-only',target:'db-only',browser:'absent'});
        const inspected=JSON.parse(call(['inspect',`${run}-source-db`]));
        requireValue(Array.isArray(inspected)&&inspected.length===1
          &&inspected[0].Name===`/${run}-source-db`
          &&inspected[0].State?.Status==='running'&&inspected[0].State?.OOMKilled!==true,
          'B_DATABASE_READINESS');
        const health=inspected[0].State?.Health?.Status;
        requireValue(['starting','healthy'].includes(health),'B_DATABASE_READINESS');
        if(health==='healthy'){databaseReady=true;break;}
        if(attempt<59)await new Promise(done=>setTimeout(done,2000));
      }
      requireValue(databaseReady,'B_DATABASE_READINESS_TIMEOUT');
      // Existing API loop then verifies all five services and the owned plan.
      await base.startApis('source');await base.assertApiHealthy('source');
      await base.verifyState({source:'running',target:'db-only',browser:'absent'});
    },
    createPostBackupSentinel:async fixture=>{
      await base.verifyState({source:'running',target:'db-only',browser:'absent'});
      const id=fixture?.sql?.document?.id;requireValue(/^[a-f0-9-]{36}$/.test(id)&&fixture.run===run,'B_SENTINEL');
      const key=`invoices/restore/${id}/post-backup.xml`,bytes=Buffer.from('<synthetic-post-backup-marker/>\n');
      const code=`import {createHash} from 'node:crypto';let raw='';for await(const c of process.stdin)raw+=c;const p=JSON.parse(raw);try{const headers={apikey:process.env.SERVICE_KEY,Authorization:'Bearer '+process.env.SERVICE_KEY,'Content-Type':'application/xml','x-upsert':'false'};const added=await fetch(p.origin+'/storage/v1/object/jolene-documents/'+p.key,{method:'POST',headers,body:Buffer.from(p.bytes,'base64'),redirect:'error',signal:AbortSignal.timeout(15000)});await added.body?.cancel();if(![200,201].includes(added.status))throw Error();const read=await fetch(p.origin+'/storage/v1/object/authenticated/jolene-documents/'+p.key,{headers,redirect:'error',signal:AbortSignal.timeout(15000)});const bytes=Buffer.from(await read.arrayBuffer());process.stdout.write(JSON.stringify({ok:read.status===200&&createHash('sha256').update(bytes).digest('hex')===p.sha}));}catch{process.stdout.write('{"ok":false}');process.exitCode=1;}`;
      const result=JSON.parse(call(['exec','-i',`${run}-source-storage`,'node','--input-type=module','-e',code],
        Buffer.from(JSON.stringify({origin:`http://${run}-source-api:8000`,key,bytes:bytes.toString('base64'),sha:digest(bytes)}))));
      requireValue(result.ok===true,'B_SENTINEL');return {created:true,readback:true};
    },
    removeKnownTargetPdf:async fixture=>{
      await base.verifyState({source:'off',target:'running',browser:'absent'});
      // Refuse if the original target is no longer exact before this controlled mutation.
      await runtime.assertRestoredObjects(fixture);
      const id=fixture?.sql?.document?.id,key=fixture?.files?.[0]?.key;
      requireValue(fixture.run===run&&/^[a-f0-9-]{36}$/.test(id)
        &&fixture.files[0].kind==='pdf'&&key===`invoices/restore/${id}/invoice.pdf`,'B_FILES');
      const code=`let raw='';for await(const c of process.stdin)raw+=c;const p=JSON.parse(raw);try{const r=await fetch(p.origin+'/storage/v1/object/jolene-documents',{method:'DELETE',headers:{apikey:process.env.SERVICE_KEY,Authorization:'Bearer '+process.env.SERVICE_KEY,'Content-Type':'application/json'},body:JSON.stringify({prefixes:[p.key]}),redirect:'error',signal:AbortSignal.timeout(15000)});const body=await r.json();const count=Array.isArray(body)?body.length:0;process.stdout.write(JSON.stringify({deleted:r.status===200&&count===1,status:r.status}));}catch{process.exitCode=1;}`;
      const result=JSON.parse(call(['exec','-i',`${run}-target-storage`,'node','--input-type=module','-e',code],
        Buffer.from(JSON.stringify({origin:`http://${run}-target-api:8000`,key}))));
      requireValue(result.deleted===true&&result.status===200,'B_FILES');return {deleted:true,status:200};
    },
    assertRestoredObjects:async fixture=>{
      await base.verifyState({source:'off',target:'running',browser:'absent'});
      const expected=fixture.files.map(file=>({kind:file.kind,key:file.key,bytes:file.bytes.length,sha:digest(file.bytes)}));
      requireValue(fixture.run===run&&expected.length===2&&expected[0].kind==='pdf'&&expected[1].kind==='xml'&&expected.every(f=>/^invoices\/restore\/[a-f0-9-]{36}\/invoice\.(pdf|xml)$/.test(f.key)),'B_FILES');
      const absent=expected[0].key.replace('/invoice.pdf','/post-backup.xml');
      const code=`import{createHash}from'node:crypto';let raw='';for await(const c of process.stdin)raw+=c;const p=JSON.parse(raw);try{const headers={apikey:process.env.SERVICE_KEY,Authorization:'Bearer '+process.env.SERVICE_KEY};let verified=0;const witness={};for(const f of p.expected){const r=await fetch(p.origin+'/storage/v1/object/authenticated/jolene-documents/'+f.key,{headers,redirect:'error',signal:AbortSignal.timeout(15000)});const b=Buffer.from(await r.arrayBuffer());const exact=r.status===200&&b.length===f.bytes&&createHash('sha256').update(b).digest('hex')===f.sha;if(exact)verified++;witness[f.kind+'Exact']=exact;witness[f.kind+'Missing']=[400,404].includes(r.status);}const missing=await fetch(p.origin+'/storage/v1/object/authenticated/jolene-documents/'+p.absent,{headers,redirect:'error',signal:AbortSignal.timeout(15000)});await missing.body?.cancel();process.stdout.write(JSON.stringify({verified,...witness,sentinelAbsent:[400,404].includes(missing.status)}));}catch{process.exitCode=1;}`;
      const result=JSON.parse(call(['exec','-i',`${run}-target-storage`,'node','--input-type=module','-e',code],Buffer.from(JSON.stringify({origin:`http://${run}-target-api:8000`,expected,absent}))));
      return assertObjectWitness(result);
    },
  };
  return runtime;
}
