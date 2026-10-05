import { readFileSync, writeFileSync, lstatSync, realpathSync, renameSync } from 'node:fs';
import { join } from 'node:path';
import { runPhaseA } from '../phase-a-core.mjs';
import { newSourceFixture } from '../source-fixture.mjs';
import { captureSource } from '../snapshot-restore.mjs';
import { nativeRuntime, proveControlledMissingPdf } from './native-runtime.mjs';
import { restoreTarget } from './restore-target.mjs';
import { writeBrowserInput } from './browser-input.mjs';
import { browserDriver } from './browser-driver.mjs';
import { verifyBuild } from './build-app.mjs';
import { PRODUCT_SHA, assertReview, assertNativeReview, requireValue, requireRestoreInvariant, validateBrowserReceipt } from './contract.mjs';
import { projectCatalogueParityV2 } from './catalogue-parity-v2.mjs';

// qualify() saves its progress repeatedly, including before it rethrows an
// import failure. Replace only this private progress report atomically; command
// diagnostics remain exclusive, immutable files owned by their runtimes.
function saveImportProgress(directory, report) {
 const dir=lstatSync(directory);
 requireValue(dir.isDirectory()&&!dir.isSymbolicLink()&&realpathSync(directory)===directory
  &&(dir.mode&0o077)===0,'B_CONTEXT');
 const target=join(directory,'import-qualification.private.json');
 let previous;
 try { previous=lstatSync(target); } catch(error) { if(error.code!=='ENOENT')throw error; }
 if(previous)requireValue(previous.isFile()&&!previous.isSymbolicLink()&&previous.nlink===1
  &&(previous.mode&0o777)===0o600,'B_CONTEXT');
 const temporary=target+'.writing';
 writeFileSync(temporary,JSON.stringify(report)+'\n',{mode:0o600,flag:'wx'});
 renameSync(temporary,target);
}

// Dependencies are pure-test seams, never environment/CLI overrides.
export async function runPhaseB(evidence,paths,review,save,dependencies={}) {
 assertReview(review);
 const enter=stage=>save('phase-b.json',{result:'PHASE_B_IN_PROGRESS',stage,restored:false,appVerified:false});
 let runtime,fixture,snapshot;
 const native=await (dependencies.runPhaseA??runPhaseA)(evidence,paths,value=>{
  save('phase-a-capture.json',value);enter(value.stage);
 },{
  makeRuntime:directory=>(runtime=(dependencies.makeRuntime??nativeRuntime)(directory)),
  makeFixture:()=>(fixture=(dependencies.makeFixture??newSourceFixture)(PRODUCT_SHA,evidence.run)),
  capture:async(...args)=>(snapshot=await(dependencies.capture??captureSource)(...args)),
  saveImport:report=>saveImportProgress(paths.stack,report),
 });
 assertNativeReview(native,review);requireValue(runtime&&fixture&&snapshot&&snapshot.run===evidence.run,'B_CONTEXT');
 const browser=(dependencies.browserDriver??browserDriver)(paths.stack,evidence.productDirectory,runtime);
 const runUi=async side=>{
  enter('browser_'+side);(dependencies.verifyBuild??verifyBuild)(paths.stack,side,evidence.run);
  const result=await browser.run(side,path=>(dependencies.writeBrowserInput??writeBrowserInput)(runtime,fixture,side,path));
  const receipt=validateBrowserReceipt(result.report,side);save('browser-'+side+'.json',receipt);
  requireValue(result.exitCode===0&&receipt.passed===true,'B_REPORT');return receipt;
 };
 await runtime.startSourceForUi();const source=await runUi('source');
 enter('sentinel');await runtime.createPostBackupSentinel(fixture);await runtime.stopSource();
 await runtime.verifyState({source:'off',target:'db-only',browser:'absent'});
 enter('restore');
 const checkpoint=dependencies.checkpointSql??readFileSync(new URL('../sql/checkpoint.sql',import.meta.url),'utf8');
 const restored=await(dependencies.restoreTarget??restoreTarget)(runtime,join(paths.stack,'snapshot'),snapshot,review,checkpoint);
 const catalogueComparison=projectCatalogueParityV2(restored.catalogueComparison);
 requireRestoreInvariant(catalogueComparison.v2Equal&&restored.restored===true&&restored.sourceOff===true&&restored.targetSeeded===false
  &&restored.nativeGraphqlPrerequisiteVerified===true&&restored.nativeGraphqlRestoredExact===true
  &&restored.nativeGraphqlWrapperSchemaSemanticEqual===true&&typeof restored.nativeGraphqlWrapperSchemaRawEqual==='boolean','RESTORE_RESULT');
 save('catalogue-comparison.json',catalogueComparison);
 save('graphql-comparison.json',{schemaVersion:1,result:'GRAPHQL_WRAPPER_SCHEMA_COMPARISON_PASSED',
  rawEqual:restored.nativeGraphqlWrapperSchemaRawEqual,semanticEqual:true});
 enter('files_target');await runtime.assertRestoredObjects(fixture);
 const target=await runUi('target');
 enter('files_target');const objects=await runtime.assertRestoredObjects(fixture);
 await runtime.verifyState({source:'off',target:'running',browser:'absent'});
 save('target-objects.json',{result:'TARGET_OBJECTS_EXACT_AFTER_POSITIVE_UI',verified:objects.verified,
   sentinelAbsent:objects.sentinelAbsent,sourceOff:true,beforeControlledNegative:true});
 enter('controlled_negative');
 const negative=await(dependencies.proveControlledMissingPdf??proveControlledMissingPdf)(runtime,fixture);
 requireValue(negative?.result==='CONTROLLED_TARGET_PDF_MISSING_REJECTED'&&negative.expectedCode==='B_FILES'
   &&negative.sameVerifierRejected===true&&negative.xmlStillExact===true&&negative.sourceOff===true,'B_FILES');
 save('controlled-negative.json',negative);
 const result={result:'ISOLATED_SYNTHETIC_APP_RESTORATION_PASSED',stage:'complete',productSha:PRODUCT_SHA,
  sourceCases:source.expectedCount,targetCases:target.expectedCount,restored:true,appVerified:true,sourceOff:true,controlledNegativePassed:true,targetIntentionallyChangedAfterPositiveProof:true,targetFinalObjectsIntact:false,
  sameRunSnapshot:true,sameDumpAndObjectBytes:true,restoredObjects:objects.verified,postBackupSentinelAbsent:objects.sentinelAbsent,
  targetSeeded:false,providerContacted:false,liveSessionsRestored:false,physicalDeviceVerified:false,readyForNationalLaunch:false,
  nativeGraphqlPrerequisiteVerified:true,nativeGraphqlRestoredExact:true,
  nativeGraphqlWrapperSchemaRawEqual:restored.nativeGraphqlWrapperSchemaRawEqual,nativeGraphqlWrapperSchemaSemanticEqual:true};
 save('phase-b.json',result);return result;
}
