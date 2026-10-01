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
