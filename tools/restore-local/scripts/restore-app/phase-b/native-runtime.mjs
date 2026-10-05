import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { localRuntime } from '../local-runtime.mjs';
import { catalogueDiagnosticSql, catalogueFactsDiagnostic, CATALOGUE_PRIVATE_KEY } from './catalogue-facts-diagnostic.mjs';
import { buildB21ProbeSql, decodeB21Probe } from './catalogue-semantics-probe.mjs';
import { catalogueSemanticsDiagnostic, validateB21Probe } from './catalogue-semantics-diagnostic.mjs';
import { catalogueParityV2 } from './catalogue-parity-v2.mjs';
import { fileTree, assertEmptyFileTree } from '../snapshot-restore.mjs';
import { projectSqlDiagnostic } from '../../restore/bootstrap.mjs';
import { DB, digest, requireValue, requireRestoreInvariant, catalogueRestoreDiagnostic, projectRestoreCall, projectPgRestoreDiagnostic } from './contract.mjs';
import { assertGraphqlWitness,assertGraphqlNativeBaseline, assertGraphqlRestored, graphqlComparableWitness, partitionGraphqlRestore, prepareGraphqlRestore } from './graphql-restore-plan.mjs';

// PG17 pg_backup_db.c emits the first error and then "Command was:" even
// without --verbose. TOC INFO lines are suppressed, so do not depend on them.
// Advisory classification only: raw messages, identifiers and SQL stay private.
export function classifyPgRestoreStderr(value) {
  const limit=64*1024,isBuffer=Buffer.isBuffer(value),isString=typeof value==='string';
  if(!isBuffer&&!isString)return projectPgRestoreDiagnostic({parser:'INVALID_INPUT'});
  const inputTruncated=value.length>limit;
  const text=isBuffer?value.subarray(0,limit).toString('utf8'):value.slice(0,limit);
  const lines=text.split(/\r?\n/),first=lines.findIndex(line=>line.startsWith('pg_restore: error: '));
  const result={parser:!text?'EMPTY':first<0?'NO_PRIMARY_ERROR':'FIRST_ERROR',inputTruncated};
  if(first<0)return projectPgRestoreDiagnostic(result);
  // Stop before any subsequent primary error; a later error cannot replace it.
  const later=lines.findIndex((line,index)=>index>first&&line.startsWith('pg_restore: error: '));
  const section=lines.slice(first+1,later<0?undefined:later);
  const primary=lines[first].slice('pg_restore: error: '.length,4096);
  const sql=primary.match(/^(?:could not execute query|could not start database transaction|could not commit database transaction|query failed|COPY failed for table "[^"\r\n]*"): (?:ERROR|FATAL|PANIC):\s+(.*)$/);
  const message=sql?sql[1]:primary;
  const rules=[
    ['OBJECT_EXISTS',/^(?:schema|relation|type|function|extension|constraint|trigger|policy|publication|event trigger|operator|collation) .+ already exists$/],
    ['OBJECT_MISSING',/^(?:schema|relation|type|function|role|extension|operator|collation) .+ does not exist(?:$|[ (])/],
    ['OWNER_REQUIRED',/^must be owner of /],
    ['ROLE_REQUIRED',/^(?:must be member of role|must be able to SET ROLE|permission denied to set role) /],
    ['PERMISSION_DENIED',/^permission denied (?:for|to) /],
    ['SUPERUSER_REQUIRED',/^(?:must be superuser|only superusers can|superuser privilege is required)/],
    ['EXTENSION_UNAVAILABLE',/^(?:extension .+ is not available|could not open extension control file )/],
    ['EXTENSION_LIBRARY',/^(?:could not (?:access|load) (?:file|library)|incompatible library|undefined symbol)/],
    ['EXTENSION_PREREQUISITE',/^(?:required extension .+ is not installed|can only create extension in database |unrecognized configuration parameter "cron\.|pg_cron can only be loaded via shared_preload_libraries)/],
    ['TRANSACTION_RESTRICTION',/^(?:.+ cannot (?:run|be executed) inside a transaction block|cannot (?:run|execute) .+ (?:inside|within) a transaction)/],
    ['CONFIGURATION',/^(?:unrecognized configuration parameter|invalid value for parameter|parameter .+ cannot be changed)/],
    ['CONSTRAINT',/^(?:duplicate key value violates|insert or update on table .+ violates|new row for relation .+ violates|null value in column .+ violates)/],
    ['DATA',/^(?:invalid input syntax|value too long|invalid byte sequence|missing data for column|extra data after last expected column|invalid command)/],
    ['DEPENDENCY',/^(?:cannot drop .+ because other objects depend on it|cannot alter .+ because it is being used|cannot change .+ because extension .+ requires it)/],
    ['RESOURCE',/^(?:out of memory|out of shared memory|could not (?:extend|write|resize)|disk full|remaining connection slots)/],
    ['CONNECTION',/^(?:connection to (?:server|database)|reconnection failed|server closed the connection|could not connect|no connection to the server)/],
    ['ARCHIVE_FORMAT',/^(?:unsupported version|did not find magic string|input file (?:does not appear|appears)|unrecognized (?:archive|data block)|invalid archive|cannot restore from compressed archive)/],
    ['ARCHIVE_READ',/^(?:could not read from input file|could not read from input stream|could not uncompress data|unexpected end of file|could not find block ID|could not seek)/],
  ];
  result.category=rules.find(([,pattern])=>pattern.test(message))?.[0]??(sql?'SQL_OTHER':'UNKNOWN');
  // Only the first primary message supplies missing-object hints. Never infer a
  // role from GRANT recipients, DETAIL/HINT, TOC entries or a later error.
  if(result.category==='OBJECT_MISSING'){
    result.missingObjectType=message.match(/^(schema|relation|type|function|role|extension|operator|collation) /)?.[1].toUpperCase();
    result.missingRole=message.match(/^role (?:"([a-z_][a-z_0-9]*)"|([a-z_][a-z_0-9]*)) does not exist$/)?.slice(1).find(Boolean);
  }
  // Hints are projected through finite enums a second time at publication.
  // Never publish the rest of this line, even when it contains a known prefix.
  const commandLines=section.filter(line=>line.startsWith('Command was: '));
  const command=commandLines.length===1?commandLines[0].slice('Command was: '.length,4096).trimStart():'';
  const create=command.match(/^CREATE\s+(?:OR REPLACE\s+)?(EVENT TRIGGER|SCHEMA|EXTENSION|TABLE|SEQUENCE|FUNCTION|TYPE|(?:UNIQUE\s+)?INDEX|(?:MATERIALIZED\s+)?VIEW|TRIGGER|POLICY|PUBLICATION)\b/);
  result.command=create?'CREATE_'+create[1].replace(/^(?:UNIQUE|MATERIALIZED)\s+/,'').replace(/ /g,'_')
    :command.match(/^(SET|SELECT|BEGIN|COMMIT|COPY|INSERT|ALTER|GRANT|REVOKE|COMMENT|DO)\b/)?.[1]
      ??(/^SECURITY LABEL\b/.test(command)?'SECURITY_LABEL':sql&&primary.startsWith('COPY failed')?'COPY':'UNKNOWN');
  const identifier='(?:"([a-z_][a-z_0-9-]*)"|([a-z_][a-z_0-9-]*))';
  const schema=command.match(new RegExp('^CREATE SCHEMA '+identifier+'(?:[ ;]|$)'))
    ??message.match(new RegExp('^(?:schema |permission denied for schema |must be owner of schema )'+identifier+'(?:[ ;]|$)'));
  const extension=command.match(new RegExp('^CREATE EXTENSION (?:IF NOT EXISTS )?'+identifier+'(?:[ ;]|$)'))
    ??message.match(new RegExp('^(?:extension |required extension |must be owner of extension )'+identifier+'(?:[ ;]|$)'));
  // A qualified missing relation/function can name its schema, but never publish
  // the free object name or signature. The existing finite projector runs next.
  const missingSchema=result.category==='OBJECT_MISSING'?message.match(/^(?:relation|function) (?:"([a-z_][a-z_0-9]*)\.[^"\r\n]+"|"?([a-z_][a-z_0-9]*)"?\.(?:"[^"\r\n]+"|[a-z_][a-z_0-9]*))(?=\s|\()/):null;
  result.schema=schema?.[1]??schema?.[2]??missingSchema?.[1]??missingSchema?.[2];result.extension=extension?.[1]??extension?.[2];
  return projectPgRestoreDiagnostic(result);
}

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
const CATALOGUE_DIAGNOSTIC_SQL = catalogueDiagnosticSql(readFileSync(new URL('../sql/catalogue.sql',import.meta.url),'utf8'));
const B21_PROBE_SQL = buildB21ProbeSql(readFileSync(new URL('../sql/catalogue.sql',import.meta.url),'utf8'));
const GRAPHQL_WITNESS_SQL = readFileSync(new URL('./graphql-native-witness.sql',import.meta.url),'utf8');

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
  const preparedRestores = new WeakMap();
  // Run-local memory only: never enumerable on a catalogue or serialized snapshot.
  const catalogueFacts = new WeakMap();
  const catalogueProbes = new WeakMap();
  let sourceCaptured=false,sourceDumpStarted=false,sourceStopped=false;
  let preparedToken=null,targetRecreated=false;
  const callId=randomUUID();let command = 0, check = 0;
  const call = (args, input, restoreOperation = null) => {
    const result = spawnSync('docker', args, { input, encoding:null, maxBuffer:64*1024*1024, timeout:240_000,
      env:{PATH:process.env.PATH,HOME:process.env.HOME} });
    writeFileSync(join(privateDir,`phase-b-command-${callId}-${++command}.stderr.private`),result.stderr??Buffer.alloc(0),{mode:0o600,flag:'wx'});
    if(result.error||result.status!==0||result.signal!==null) {
      const error=Object.assign(Error('B_CALL'),{code:'B_CALL',diagnostic:projectSqlDiagnostic(result.stderr?.toString()??'')});
      if(restoreOperation!==null)error.restoreCall=projectRestoreCall({operation:restoreOperation,exitCode:result.status,
        signal:result.signal,systemError:result.error?.code??null,
        ...(['TARGET_ARCHIVE_RESTORE','TARGET_ARCHIVE_TOC_READ','TARGET_ARCHIVE_SQL_EXPORT'].includes(restoreOperation)?{pgRestore:classifyPgRestoreStderr(result.stderr)}:{})});
      throw error;
    }
    return result.stdout;
  };
  const targetState=()=>base.verifyState({source:'off',target:'db-only',browser:'absent'});
  const targetSql=async(body,database=DB,restoreOperation=null)=>{
    requireValue([DB,'postgres'].includes(database)); await targetState();
    return call(['exec','-i',`${run}-target-db`,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose',
      '-U','supabase_admin','-h','/var/run/postgresql','-d',database,'-f','-'],Buffer.from(body),restoreOperation);
  };
  const runtime={...base,
    databaseTool:async(...args)=>{sourceDumpStarted=true;return base.databaseTool(...args);},
    stopSource:async()=>{sourceStopped=true;return base.stopSource();},
    catalogue:async side=>{
      requireValue(['source','target'].includes(side),'B_CONTEXT');
      if(side==='source')requireValue(!sourceCaptured&&!sourceDumpStarted&&!sourceStopped,'B_CONTEXT');
      const state={source:side==='source'?'db-only':'off',target:'db-only',browser:'absent'};
      await base.verifyState(state);
      if(side==='source')sourceCaptured=true;
      const {[CATALOGUE_PRIVATE_KEY]:facts,...original}=await base.sqlJson(side,CATALOGUE_DIAGNOSTIC_SQL);
      let probe;
      try {
        // stdout/stderr stay memory-only, including on SQL/decoding failure.
        // A new session is intentional; its original catalogue result anchors
        // both repeatable-read views to the preceding B20 capture.
        await base.verifyState(state);
        const result=spawnSync('docker',['exec','-i',`${run}-${side}-db`,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1',
          '-U','postgres','-h','/var/run/postgresql','-d',DB,'-f','-'],{input:Buffer.from(B21_PROBE_SQL),encoding:null,maxBuffer:40*1024*1024,
          timeout:150_000,env:{PATH:process.env.PATH,HOME:process.env.HOME}});
        if(result.error||result.status!==0||result.signal!==null)probe={schemaVersion:1,status:'CAPTURE_FAILED'};
        else {probe=decodeB21Probe(result.stdout);const status=validateB21Probe(probe,original);if(status!=='COMPLETE')probe={schemaVersion:1,status};}
      }catch{probe={schemaVersion:1,status:'CAPTURE_FAILED'};}
      await base.verifyState(state);
      const catalogue={...original,databaseRoleSettings:await base.sqlJson(side,SETTINGS_SQL),
        nativeGraphql:(side==='source'?assertGraphqlNativeBaseline:assertGraphqlWitness)(await base.sqlJson(side,GRAPHQL_WITNESS_SQL),side==='source'?'SOURCE_CAPTURE':'TARGET_RESTORED')};
      catalogueFacts.set(catalogue,facts);catalogueProbes.set(catalogue,probe);return catalogue;
    },
    assertTargetFilesEmpty:async()=>{
      await targetState();const path=join(privateDir,`target-empty-b-${++check}`);
      await base.copyFilesOut('target',path);assertEmptyFileTree(path);
    },
    recreateOwnedEmptyTargetDatabase:async database=>{
      requireRestoreInvariant(database===DB&&preparedToken&&preparedRestores.has(preparedToken)&&!targetRecreated,'DATABASE_RECREATE_TOKEN');await targetState();await base.assertTargetNativeEmpty();await runtime.assertTargetFilesEmpty();
      await targetSql(`DROP DATABASE ${DB};\nCREATE DATABASE ${DB} OWNER postgres TEMPLATE template0;`,'postgres','TARGET_DATABASE_RECREATE');
      targetRecreated=true;
      // PG17 pg_dump does not recreate public: its SCHEMA TOC entry replays
      // ownership/ACLs onto the initdb schema inherited from template0. Keep it.
    },
    // Complete SQL preparation precedes DROP. Both exports use the very same
    // archive; only the exact native prerequisite partition runs first.
    prepareTargetArchiveRestore:async input=>{
      requireRestoreInvariant(!preparedToken&&!targetRecreated,'PREPARE_SINGLE_USE');
      await targetState();await base.assertTargetNativeEmpty();
      partitionGraphqlRestore(input); // Validate bytes/review before any native tool.
      await targetState();
      const actualToc=call(['exec','-i',`${run}-target-db`,'pg_restore','--list'],input.archive,'TARGET_ARCHIVE_TOC_READ');
      // The reviewed normalized hash excludes run-local OIDs/IDs. Bind the list
      // IDs to these actual archive bytes too, not merely to normalized tags.
      requireValue(actualToc.equals(input.toc),'B_SNAPSHOT');
      const prepared=await prepareGraphqlRestore({...input,toc:actualToc},async({partition,archive,list,args})=>{
        const listPath='/tmp/jolene-graphql-'+partition+'.list';
        requireRestoreInvariant(['prerequisites','remainder'].includes(partition),'EXPORT_PARTITION');
        await targetState();
        // Fixed script; noclobber refuses existing paths, including symlinks.
        call(['exec','-i',`${run}-target-db`,'sh','-c','umask 077; set -C; cat > '+listPath],list,'TARGET_TOC_WRITE');
        await targetState();
        requireRestoreInvariant(call(['exec',`${run}-target-db`,'cat',listPath],undefined,'TARGET_TOC_READBACK').equals(list),'TOC_READBACK_BEFORE_EXPORT');
        await targetState();
        const sql=call(['exec','-i',`${run}-target-db`,'pg_restore',...args],archive,'TARGET_ARCHIVE_SQL_EXPORT');
        await targetState();
        requireRestoreInvariant(call(['exec',`${run}-target-db`,'cat',listPath],undefined,'TARGET_TOC_READBACK').equals(list),'TOC_READBACK_AFTER_EXPORT');
        await targetState();
        call(['exec',`${run}-target-db`,'rm','--',listPath],undefined,'TARGET_TOC_REMOVE');
        return sql;
      });
      const token=Object.freeze({nativeGraphqlPrerequisiteVerified:true});
      preparedRestores.set(token,{...prepared,sqlSha256:digest(prepared.sql)});
      // SQL never leaves this private runtime and is never a public receipt.
      writeFileSync(join(privateDir,'graphql-restore.sql.private'),prepared.sql,{mode:0o600,flag:'wx'});
      preparedToken=token;
      return token;
    },
    executePreparedTargetRestore:async token=>{
      const prepared=preparedRestores.get(token);requireRestoreInvariant(token===preparedToken&&targetRecreated&&prepared&&digest(prepared.sql)===prepared.sqlSha256,'RESTORE_PREPARED_TOKEN');
      await targetState();preparedRestores.delete(token); // Single use, also on failure.
      call(['exec','-i',`${run}-target-db`,'psql',...prepared.transactionArgs],prepared.sql,'TARGET_SQL_RESTORE');
    },
    applyReviewedRoleSettings:async()=>targetSql(ROLE_SETTINGS_SQL,DB,'TARGET_ROLE_SETTINGS'),
    copyFilesIn:async(side,source)=>{
      requireValue(side==='target'&&realpathSync(source)===resolve(source)
        &&resolve(source)===join(realpathSync(privateDir),'snapshot','files'),'B_FILES');
      const expected=fileTree(source);await targetState();await runtime.assertTargetFilesEmpty();
      call(['cp','-a',source+'/.',`${run}-target-storage:/var/lib/storage/`],undefined,'TARGET_FILES_COPY_IN');
      const after=join(privateDir,'target-files-restored');await base.copyFilesOut('target',after);
      requireValue(JSON.stringify(fileTree(after))===JSON.stringify(expected),'B_FILES');
    },
    assertSourceOffAndTargetCatalogExact:async snapshot=>{
      await targetState();const target=await runtime.catalogue('target');
      const parity=assertGraphqlRestored(snapshot.catalogue.nativeGraphql,target.nativeGraphql);
      const comparable=value=>({...value,nativeGraphql:graphqlComparableWitness(value.nativeGraphql)});
      const catalogueComparison=catalogueParityV2(comparable(snapshot.catalogue),comparable(target),
        catalogueFacts.get(snapshot.catalogue),catalogueFacts.get(target),catalogueProbes.get(snapshot.catalogue),catalogueProbes.get(target));
      requireRestoreInvariant(catalogueComparison.v2Equal,'CATALOGUE_PARITY',
        ()=>catalogueRestoreDiagnostic(comparable(snapshot.catalogue),comparable(target),
          catalogueFactsDiagnostic(catalogueFacts.get(snapshot.catalogue),catalogueFacts.get(target)),
          catalogueSemanticsDiagnostic(snapshot.catalogue,target,catalogueFacts.get(snapshot.catalogue),catalogueFacts.get(target),
            catalogueProbes.get(snapshot.catalogue),catalogueProbes.get(target)),catalogueComparison));
      return {...parity,catalogueComparison};
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
