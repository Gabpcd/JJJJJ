import {readFileSync,statSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
export const NAMES=['pg_cron','pg_net','pg_stat_statements','pg_trgm','pgcrypto','pgjwt','plpgsql','supabase_vault','uuid-ossp'];
const ident=x=>typeof x==='string'&&/^[a-z_][a-z0-9_-]{0,62}$/.test(x);
const version=x=>typeof x==='string'&&/^[0-9][a-zA-Z0-9_.-]{0,30}$/.test(x);
const reject=()=>{throw Error('EXTENSION_CATALOGUE_REFUSED')};
export function projectExtensions(value){
 if(value?.postgres_major!==17||!Array.isArray(value.extensions)||value.extensions.length!==NAMES.length)reject();
 const seen=new Set();const extensions=value.extensions.map(e=>{
  if(!NAMES.includes(e.name)||seen.has(e.name)||!Number.isInteger(e.available_count)||e.available_count<0||e.available_count>1000||typeof e.available_truncated!=='boolean'||!Array.isArray(e.available_versions)||e.available_versions.length!==Math.min(50,e.available_count)||e.available_truncated!==(e.available_count>50))reject();seen.add(e.name);
  if(e.installed!==null&&(!version(e.installed?.version)||!ident(e.installed?.schema)))reject();
  const versions=new Set();const available_versions=e.available_versions.map(v=>{
   if(!version(v.version)||versions.has(v.version)||typeof v.superuser!=='boolean'||typeof v.trusted!=='boolean'||typeof v.relocatable!=='boolean'||(v.schema!==null&&!ident(v.schema))||(v.requires!==null&&(!Array.isArray(v.requires)||v.requires.length>20||v.requires.some(x=>!ident(x)))))reject();versions.add(v.version);
   return {version:v.version,superuser:v.superuser,trusted:v.trusted,relocatable:v.relocatable,schema:v.schema,requires:v.requires};
  });
  return {name:e.name,installed:e.installed?{version:e.installed.version,schema:e.installed.schema}:null,available_count:e.available_count,available_truncated:e.available_truncated,available_versions};
 });
 return {postgres_major:17,extensions:extensions.sort((a,b)=>a.name.localeCompare(b.name))};
}
export function compareRequired(source,runtime){
 const r=projectExtensions(runtime);if(!Array.isArray(source)||source.length!==NAMES.length||new Set(source.map(e=>e.name)).size!==NAMES.length||source.some(e=>!NAMES.includes(e.name)||!version(e.version)||!ident(e.schema)))reject();
 const checks=source.map(s=>{const t=r.extensions.find(e=>e.name===s.name);return {name:s.name,required_version:s.version,required_schema:s.schema,
  exact_version_available:t.available_versions.some(v=>v.version===s.version),available_catalogue_complete:!t.available_truncated,
  installed_version_matches:t.installed===null?null:t.installed.version===s.version,installed_schema_matches:t.installed===null?null:t.installed.schema===s.schema};});
 return {result:'EXTENSION_COMPATIBILITY_ONLY',checks,declarations_compatible:checks.every(c=>c.exact_version_available&&c.available_catalogue_complete&&c.installed_version_matches!==false&&c.installed_schema_matches!==false),import_ready:false};
}

// Both observations must belong to the same new run. Absence is permitted only
// for the two extensions not installed by this empty-stack initialization.
export function compareInventories(source,report,expectedRun){
 if(typeof expectedRun!=='string'||!/^jolene-restore-drill-[a-z0-9][a-z0-9-]{0,25}$/.test(expectedRun)||report?.run!==expectedRun||report.result!=='EXTENSION_CATALOGUE_ONLY'||report.extensions_changed!==false||report.schema_imported!==false||!Array.isArray(report.inventories)||report.inventories.length!==2)reject();
 const sides=['source','target'];
 if(report.inventories.some(x=>!x||!sides.includes(x.side))||new Set(report.inventories.map(x=>x.side)).size!==2)reject();
 const inventories=sides.map(side=>{
  const runtime=projectExtensions(report.inventories.find(x=>x.side===side));
  const comparison=compareRequired(source,runtime);
  const checks=comparison.checks.map(check=>({...check,
   bootstrap_installation_present:['pgjwt','pg_trgm'].includes(check.name)?null:runtime.extensions.find(x=>x.name===check.name).installed!==null
  }));
  return {side,checks,declarations_compatible:comparison.declarations_compatible&&checks.every(x=>x.bootstrap_installation_present!==false)};
 });
 return {result:'EXTENSION_COMPATIBILITY_ONLY',run:expectedRun,inventories,declarations_compatible:inventories.every(x=>x.declarations_compatible),extensions_changed:false,schema_imported:false,import_ready:false};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const [command,path,expectedRun,...extra]=process.argv.slice(2);
  if(command!=='compare'||!path||extra.length||statSync(path).size>1048576)reject();
  // Fixed versioned requirements: no CLI/env override of versions or schemas.
  const source=JSON.parse(readFileSync(new URL('../export/scope.json',import.meta.url),'utf8')).extensions;
  const result=compareInventories(source,JSON.parse(readFileSync(path,'utf8')),expectedRun);
  console.log(JSON.stringify(result));
  if(!result.declarations_compatible)process.exitCode=1;
 }catch{console.error(JSON.stringify({error:'EXTENSION_COMPARISON_REFUSED',import_ready:false}));process.exitCode=1;}
}
