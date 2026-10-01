import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {fileURLToPath} from 'node:url';import {spawnSync} from 'node:child_process';
import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {NAMES,projectExtensions,compareRequired,compareInventories} from './extensions.mjs';
const source=JSON.parse(readFileSync(new URL('../export/scope.json',import.meta.url))).extensions;
const runtime=()=>({postgres_major:17,extensions:source.map(e=>({name:e.name,installed:{version:e.version,schema:e.schema},available_count:1,available_truncated:false,available_versions:[{version:e.version,superuser:true,trusted:false,relocatable:false,schema:e.schema,requires:null}]}))});
test('available does not mean installed, and compatibility never claims an import',()=>{const r=runtime();r.extensions.find(e=>e.name==='pgjwt').installed=null;const d=compareRequired(source,r);assert.equal(d.declarations_compatible,true);assert.equal(d.import_ready,false);assert.equal(d.checks.find(e=>e.name==='pgjwt').installed_version_matches,null)});
test('missing pgjwt is preserved as a blocker, never silently omitted',()=>{const r=runtime(),j=r.extensions.find(e=>e.name==='pgjwt');j.installed=null;j.available_versions=[];j.available_count=0;const d=compareRequired(source,r);assert.equal(d.declarations_compatible,false);assert.equal(d.checks.length,9);assert.equal(d.checks.find(e=>e.name==='pgjwt').exact_version_available,false)});
test('installed mismatches or truncated catalogue are not treated as compatible',()=>{const r=runtime();r.extensions[0].installed.version='9.9';assert.equal(compareRequired(source,r).declarations_compatible,false);const x=runtime();x.extensions[0].installed.schema='public';assert.equal(compareRequired(source,x).declarations_compatible,false)});
test('unexpected names, duplicates, malformed versions or unsafe fields refuse',()=>{
 for(const mutate of [r=>r.postgres_major=16,r=>r.extensions.pop(),r=>r.extensions[0].name='CANARY_SECRET',r=>r.extensions[0].name=r.extensions[1].name,r=>r.extensions[0].installed.version='https://CANARY_SECRET',r=>r.extensions[0].available_count=2]){const r=runtime();mutate(r);assert.throws(()=>projectExtensions(r),/^Error: EXTENSION_CATALOGUE_REFUSED$/)}
 const r=runtime();r.secret='CANARY_SECRET';r.extensions[0].available_versions[0].comment='CANARY_SECRET';assert.ok(!JSON.stringify(projectExtensions(r)).includes('CANARY'));assert.equal(NAMES.length,9);
});

const run='jolene-restore-drill-unittest';
const report=()=>({result:'EXTENSION_CATALOGUE_ONLY',run,extensions_changed:false,schema_imported:false,inventories:['source','target'].map(side=>({side,...runtime()}))});
function cli(t,value,args=[]){
 const dir=mkdtempSync(join(tmpdir(),'restore-extension-unit-')),path=join(dir,'catalogue.json');t.after(()=>rmSync(dir,{recursive:true,force:true}));
 writeFileSync(path,typeof value==='string'?value:JSON.stringify(value));
 return spawnSync(process.execPath,[fileURLToPath(new URL('./extensions.mjs',import.meta.url)),'compare',path,run,...args],{encoding:'utf8'});
}
test('CLI succeeds only after both complete inventories and preserves uninstalled distinction',t=>{
 const r=report();for(const side of r.inventories)for(const e of side.extensions)if(['pgjwt','pg_trgm'].includes(e.name))e.installed=null;
 const child=cli(t,r);assert.equal(child.status,0);assert.equal(child.stderr,'');const d=JSON.parse(child.stdout);
 assert.equal(d.declarations_compatible,true);assert.equal(d.import_ready,false);assert.equal(d.extensions_changed,false);assert.equal(d.schema_imported,false);
 assert.deepEqual(d.inventories.map(x=>x.side),['source','target']);for(const side of d.inventories){assert.equal(side.checks.length,9);assert.equal(side.checks.find(x=>x.name==='pgjwt').installed_version_matches,null);}
});
test('CLI rejects the observed 136 pg_net 0.20.3 mismatch, even when all other requirements match',t=>{
 const r=report();for(const side of r.inventories){const e=side.extensions.find(x=>x.name==='pg_net');e.installed.version='0.20.3';e.available_versions[0].version='0.20.3';}
 const child=cli(t,r);assert.equal(child.status,1);assert.equal(child.stderr,'');const d=JSON.parse(child.stdout);assert.equal(d.declarations_compatible,false);
 for(const side of d.inventories){const failures=side.checks.filter(x=>!x.exact_version_available||x.installed_version_matches===false);assert.deepEqual(failures.map(x=>x.name),['pg_net']);}
});
test('every one of nine missing exact versions is blocking, independently on each side',()=>{
 for(const side of ['source','target'])for(const required of source){const r=report(),e=r.inventories.find(x=>x.side===side).extensions.find(x=>x.name===required.name);e.available_versions[0].version='99.99';const d=compareInventories(source,r,run);assert.equal(d.declarations_compatible,false,side+':'+required.name);assert.equal(d.inventories.find(x=>x.side!==side).declarations_compatible,true);}
});
test('installed version, schema, missing initialized extension and truncated inventory block either side',()=>{
 for(const side of ['source','target'])for(const mutate of [e=>e.installed.version='99.99',e=>e.installed.schema='public',e=>e.installed=null,e=>{e.available_count=51;e.available_truncated=true;e.available_versions=Array.from({length:50},(_,i)=>({...e.available_versions[0],version:i===0?e.installed.version:'90.'+i}));}]){
  const r=report(),e=r.inventories.find(x=>x.side===side).extensions.find(x=>x.name==='pg_net');mutate(e);assert.equal(compareInventories(source,r,run).declarations_compatible,false);
 }
});
test('partial, duplicate or unrelated runs and observations refuse, never count as compatibility',()=>{
 for(const mutate of [r=>r.inventories.pop(),r=>r.inventories.push(r.inventories[0]),r=>r.inventories[1].side='source',r=>r.inventories[1].side='CANARY_SECRET',r=>r.inventories[1]=null,r=>r.run+='-other',r=>r.extensions_changed=true,r=>r.schema_imported=true,r=>r.result='EMPTY_CORE_ONLY',r=>r.inventories[0].postgres_major=16]){
  const r=report();mutate(r);assert.throws(()=>compareInventories(source,r,run));
 }
 for(const requirements of [source.slice(1),[...source.slice(1),source[1]]])assert.throws(()=>compareInventories(requirements,report(),run));
 assert.throws(()=>compareInventories(source,report(),'https://CANARY_SECRET'));
});
test('CLI failures and extra inputs do not disclose paths, credentials or arbitrary payload',t=>{
 for(const value of ['{"password":"CANARY_SECRET"', {...report(),run:'CANARY_SECRET'}, {...report(),inventories:[null,null]}]){
  const child=cli(t,value);assert.equal(child.status,1);assert.equal(child.stdout,'');assert.deepEqual(JSON.parse(child.stderr),{error:'EXTENSION_COMPARISON_REFUSED',import_ready:false});assert.ok(!child.stderr.includes('CANARY'));
 }
 const r=report();r.secret='CANARY_SECRET';r.inventories[0].extensions[0].installed.extra='CANARY_SECRET';const child=cli(t,r);assert.equal(child.status,0);assert.ok(!child.stdout.includes('CANARY'));
 const extra=cli(t,r,['CANARY_SECRET']);assert.equal(extra.status,1);assert.ok(!extra.stderr.includes('CANARY'));
});
