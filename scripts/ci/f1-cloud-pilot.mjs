import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { mkdir, writeFile, lstat } from 'node:fs/promises';
import { join } from 'node:path';
import { FORMATS } from './f1-cloud-ui.mjs';
import { contextF1, generateOnce, ledgerF1, requireReady, refuse, sha256 } from './f1-cloud-core.mjs';

/** SQL/Auth/Storage implementation is provided by f1-cloud-adapter.mjs.
 * The adapter must persist all planned identities before creating the first user,
 * and reload that manifest for finalization even if prepare throws halfway. */
export async function pilotF1({ ctx, adapter, ui, fetcher, makeLedger = ledgerF1, observe = async () => {} }) {
  let phase='preflight';
  const mark=async value=>{phase=value;await observe({phase,state:'running'});};
  await mark('preflight');
  const preflight = await adapter.preflight(ctx);
  requireReady(preflight, ctx);
  const ledger = await makeLedger(ctx);
  let failed = false, report, documentReport, uiEvidence, finalization;
  const closureFailure=async (value,error)=>{failed=true;try{await observe({phase:value,state:'failed',code:value==='finalize_auth'?'F1_AUTH_FINALIZATION_FAILED':'F1_FINALIZATION_VERIFICATION_FAILED',exception_sha256:sha256(String(error?.message??''))});}catch{}};
  try {
    await mark('prepare');
    const manifest = await ledger.once('prepare_fixture', () => adapter.prepare(ctx, ledger.directory));
    await mark('generator_login');
    const token = await adapter.authenticateGenerator(ctx, manifest);
    await mark('generate_original');
    const original = await generateOnce({ ctx, ledger, manifest, token, preflight, kind: 'original', fetcher });
    await mark('reconcile_original');await adapter.reconcileOriginal(ctx, manifest, original);
    await mark('prepare_correction');
    const correction = await ledger.once('prepare_correction', () => adapter.prepareCorrection(ctx, manifest, original));
    // Current approved design requires URL absent + no request scheduled. A future
    // pg_net initiator needs a separate contract; never submit a second Edge call.
    if (correction?.initiation?.type !== 'runner') refuse('F1_CORRECTION_INITIATOR_REFUSED');
    await mark('generate_replacement');
    const replacement = await generateOnce({ ctx, ledger, manifest, token, preflight, kind: 'replacement', correction, fetcher });
    await mark('reconcile_documents');
    const documents = await adapter.reconcileDocuments(ctx, manifest, { original, replacement });
    await mark('frontend');report = await ui({ ctx, manifest, documents });
    if (report?.contextsClosed !== true) refuse('F1_CONTEXT_CLOSE_FAILED');
    await mark('document_analysis');documentReport = await adapter.verifyDownloads(ctx, manifest, documents);
    await mark('reconcile_effects');
    await adapter.reconcileEffects(ctx, manifest);
    uiEvidence=projectUiEvidenceF1(report,projectDocumentEvidenceF1(documentReport));
  } catch(error) { failed = true;try{await observe({phase,state:'failed',exception_sha256:sha256(String(error?.message??''))});}catch{ /* Evidence IO must never skip Auth finalization. */ } }
  finally {
    try{await mark('finalize_auth');}catch{failed=true;}
    try {
      // Retain financial rows, immutable versions and audit trail. The adapter's
      // reviewed finalize closes only owned Auth and explicitly allowed resources.
      await ledger.once('finalize_auth', () => adapter.finalize(ctx, ledger.directory));
      await observe({phase:'finalize_auth',state:'succeeded'});
    } catch(error) { await closureFailure('finalize_auth',error); }
    // Always obtain a fresh read, even when closure failed or its response was lost.
    try{await mark('verify_finalization');}catch{failed=true;}
    try {
      finalization=projectFinalizationF1(await adapter.verifyFinalization(ctx, ledger.directory),!failed);
      await observe({phase:'verify_finalization',state:'succeeded',finalization});
    } catch(error) { await closureFailure('verify_finalization',error); }
  }
  if (failed) refuse('F1_PILOT_FAILED_RECONCILE_REQUIRED');
  // Do not forward arbitrary adapter/UI return values into a public report.
  return { success: true, effects: ledger.projection(), uiContextsClosed: report.contextsClosed === true,
    ui:uiEvidence, finalization, documents: projectDocumentEvidenceF1(documentReport) };
}

export function projectFinalizationF1(row, complete = false) {
  if(!Number.isInteger(row?.owned_auth_banned)||row.owned_auth_banned<0||row.owned_auth_banned>3
    ||row.sessions!==0||row.active_admin!==0||typeof row.financial_retention!=='boolean'
    ||(complete&&(row.owned_auth_banned!==3||row.financial_retention!==true)))refuse('F1_FINALIZATION_EVIDENCE_INVALID');
  return {owned_auth_banned:row.owned_auth_banned,sessions:0,active_admin:0,financial_retention:row.financial_retention};
}

export function projectUiEvidenceF1(report,documents) {
  const fail=()=>refuse('F1_UI_EVIDENCE_INCOMPLETE'),seen=new Set();
  if(report?.contextsClosed!==true||report.observations?.length!==10)fail();
  const observations=report.observations.map(row=>{
    if(!FORMATS.some(f=>f.name===row.format)||!['SOIGNANT','ETABLISSEMENT'].includes(row.role)||row.downloads?.length!==4)fail();
    const key=`${row.format}/${row.role}`;if(seen.has(key))fail();seen.add(key);
    const slots=new Set();
    const downloads=row.downloads.map(d=>{
      if(!['original','replacement'].includes(d.slot)||typeof d.reload!=='boolean'||!Number.isSafeInteger(d.duration_ms)||d.duration_ms<0||d.duration_ms>1200000)fail();
      const key=`${d.slot}/${d.reload}`;if(slots.has(key))fail();slots.add(key);
      const expected=documents.downloads.find(e=>e.role===row.role&&e.slot===d.slot&&e.format==='pdf');
      if(!expected||d.sha256!==expected.sha256||d.size!==expected.size)fail();
      return {slot:d.slot,reload:d.reload,sha256:d.sha256,size:d.size,duration_ms:d.duration_ms};
    });
    return {format:row.format,role:row.role,downloads};
  });
  return {contextsClosed:true,observations};
}

export function projectDocumentEvidenceF1(report) {
  if (!Array.isArray(report?.downloads) || report.downloads.length !== 8
    || !Array.isArray(report?.semantic) || report.semantic.length !== 8) refuse('F1_DOCUMENT_EVIDENCE_INCOMPLETE');
  const seen = new Set();
  const downloads = report.downloads.map(row => {
    if (!['SOIGNANT','ETABLISSEMENT'].includes(row.role) || !['original','replacement'].includes(row.slot)
      || !['pdf','xml'].includes(row.format) || !/^[a-f0-9]{64}$/.test(row.sha256 ?? '')
      || !Number.isSafeInteger(row.size) || row.size < 1 || row.size > 25*1024*1024
      || !Number.isSafeInteger(row.duration_ms) || row.duration_ms < 0) refuse('F1_DOCUMENT_EVIDENCE_INCOMPLETE');
    const key = `${row.role}/${row.slot}/${row.format}`;
    if (seen.has(key)) refuse('F1_DOCUMENT_EVIDENCE_INCOMPLETE'); seen.add(key);
    return { role: row.role, slot: row.slot, format: row.format, sha256: row.sha256, size: row.size, duration_ms: row.duration_ms };
  });
  const semantic = report.semantic.map(row => {
    if (!['SOIGNANT','ETABLISSEMENT'].includes(row.role) || !['original','replacement'].includes(row.slot)
      || row.previous_number_and_date !== (row.slot === 'replacement')) refuse('F1_DOCUMENT_EVIDENCE_INCOMPLETE');
    if (row.pdf_sha256) {
      if (!/^[a-f0-9]{64}$/.test(row.pdf_sha256) || !Number.isSafeInteger(row.pages) || row.pages < 1 || row.pages > 8 || row.overflow_count !== 0) refuse('F1_DOCUMENT_EVIDENCE_INCOMPLETE');
      return { role: row.role, slot: row.slot, format: 'pdf', sha256: row.pdf_sha256, pages: row.pages, overflow_count: 0, previous_number_and_date: row.previous_number_and_date };
    }
    if (row.type !== '380' || row.quantity !== 4 || row.rate !== (row.slot === 'replacement' ? 18 : 20)
      || row.net !== (row.slot === 'replacement' ? 72 : 80) || row.vat !== 0 || row.total !== row.net
      || !/^[a-f0-9]{64}$/.test(row.xml_sha256 ?? '')) refuse('F1_DOCUMENT_EVIDENCE_INCOMPLETE');
    return { role: row.role, slot: row.slot, format: 'xml', sha256: row.xml_sha256, type: '380', quantity: 4,
      rate: row.rate, net: row.net, vat: 0, total: row.total, previous_number_and_date: row.previous_number_and_date };
  });
  if (new Set(semantic.map(x => `${x.role}/${x.slot}/${x.format}`)).size !== 8
    || semantic.some(x => !downloads.some(d => d.role === x.role && d.slot === x.slot && d.format === x.format && d.sha256 === x.sha256))) refuse('F1_DOCUMENT_EVIDENCE_INCOMPLETE');
  return { downloads, semantic };
}

// Fully wired, but deliberately non-activatable with the distributed false
// readiness contract. A following reviewed contract must supply actual hashes.
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let dependencies;
  try {
    if(process.argv.length>3||!['run','finalize','check'].includes(process.argv[2]??'run'))refuse('F1_ARGUMENTS');
    const ctx = contextF1(process.env);
    const {loadContractF1,connectedDependenciesF1}=await import('./f1-cloud-runtime.mjs');
    const contract=await loadContractF1(ctx),action=process.argv[2]??'run';
    if(action==='check')process.stdout.write(JSON.stringify({success:true,contract:true,source_sha:ctx.sha})+'\n');
    else if(action==='finalize') {
      const {createAdapterF1}=await import('./f1-cloud-adapter.mjs');
      const adapter=createAdapterF1({env:process.env,contract}),directory=join(ctx.privateRoot,ctx.run);
      try{await lstat(join(directory,'manifest.private.json'));}catch(error){if(error.code==='ENOENT'){process.stdout.write('{"no_fixture_manifest":true}\n');process.exit(0);}throw error;}
      let attempted=false;try{await lstat(join(directory,'finalize_auth.intent.json'));attempted=true;}catch(error){if(error.code!=='ENOENT')throw error;}
      const proof=join(ctx.privateRoot,'f1-cloud-proof');await mkdir(proof,{recursive:true,mode:0o700});
      const events=[];let finalizationFailed=false,result;
      if(!attempted){try{const ledger=await ledgerF1(ctx);await ledger.once('finalize_auth',()=>adapter.finalize(ctx,directory));events.push({phase:'finalize_auth',state:'succeeded'});}catch(error){finalizationFailed=true;events.push({phase:'finalize_auth',state:'failed',code:'F1_AUTH_FINALIZATION_FAILED',exception_sha256:sha256(String(error?.message??''))});}}
      else events.push({phase:'finalize_auth',state:'previously_attempted_no_replay'});
      // If primary finalization was ambiguous, do not replay: only inspect state.
      try{result=projectFinalizationF1(await adapter.verifyFinalization(ctx,directory));events.push({phase:'verify_finalization',state:'succeeded',finalization:result});}
      catch(error){finalizationFailed=true;events.push({phase:'verify_finalization',state:'failed',code:'F1_FINALIZATION_VERIFICATION_FAILED',exception_sha256:sha256(String(error?.message??''))});}
      const evidence={success:!finalizationFailed,source_sha:ctx.sha,run:ctx.run,events};
      await writeFile(join(proof,'finalization.json'),JSON.stringify(evidence,null,2)+'\n',{mode:0o600});
      process.stdout.write(JSON.stringify(evidence)+'\n');
      if(finalizationFailed)refuse('F1_PILOT_FAILED_RECONCILE_REQUIRED');
    } else {
      dependencies=await connectedDependenciesF1({ctx,env:process.env,contract});
      const diagnostic=[];
      const observe=async value=>{diagnostic.push(value);await dependencies.report({success:false,source_sha:ctx.sha,run:ctx.run,diagnostic});};
      const result=await pilotF1({ctx,adapter:dependencies.adapter,ui:dependencies.ui,observe});
      await dependencies.report({...result,source_sha:ctx.sha,run:ctx.run,diagnostic});process.stdout.write('{"success":true,"scope":"F1_STAGING_DOCUMENTS"}\n');
    }
  } catch (error) {
    const allowed = new Set(['F1_TRUSTED_MAIN_REQUIRED', 'F1_STAGING_REQUIRED', 'F1_RUN_REQUIRED',
      'F1_PRIVATE_DIRECTORY_REQUIRED', 'F1_CONTRACT_PENDING','F1_ARGUMENTS','F1_PILOT_FAILED_RECONCILE_REQUIRED']);
    process.stderr.write(JSON.stringify({ success: false, code: allowed.has(error.message) ? error.message : 'F1_PREFLIGHT_FAILED' }) + '\n');
    process.exitCode = 1;
  } finally {if(dependencies)try{await dependencies.close();}catch{process.stderr.write('{"success":false,"code":"F1_LOCAL_CLOSE_FAILED"}\n');process.exitCode=1;}}
}
