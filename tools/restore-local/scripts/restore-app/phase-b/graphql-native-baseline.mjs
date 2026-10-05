// Exact prerequisite from Supabase postgres a431c10, migration 20220317095840.
// Reproduces its initial schema USAGE before the unchanged extension/hook export.
// This module has no I/O or SQL executor. The source evidence is mandatory first.
import { validGraphqlSchemaDetails } from './graphql-schema-diagnostic.mjs';
export const GRAPHQL_BASELINE_SOURCE = Object.freeze({
  commit: 'a431c10a356be4c700d2e3f2af8551e2fec5e250',
  migration: '20220317095840_pg_graphql.sql',
  sha256: '31f5b997cba8d74936203a78613b5bda9b51e339c6c14f80c203440f82e95cf9',
  bytes: 5613,
});
export const GRAPHQL_VENDOR_SCHEMA_GRANT = 'grant usage on schema graphql_public to postgres, anon, authenticated, service_role;\n';
const expected = [
  ['ROLE','supabase_admin','supabase_admin','CREATE',false],
  ['ROLE','supabase_admin','supabase_admin','USAGE',false],
  ['ROLE','postgres','supabase_admin','USAGE',true],
  ['ROLE','anon','supabase_admin','USAGE',false],
  ['ROLE','authenticated','supabase_admin','USAGE',false],
  ['ROLE','service_role','supabase_admin','USAGE',false],
];
const exactKeys = (v, keys) => v !== null && typeof v === 'object' && !Array.isArray(v)
  && Object.keys(v).length === keys.length && keys.every(k => Object.hasOwn(v,k));
const ordered = rows => rows.map(row => JSON.stringify(row)).sort();
export function validGraphqlSchemaInitialPrivileges(value) {
  return Array.isArray(value) && value.length <= 1 && value.every(item =>
    exactKeys(item,['privtype','isNull','grants']) && ['e','i'].includes(item.privtype)
    && validGraphqlSchemaDetails({owner:'supabase_admin',isNull:item.isNull,grants:item.grants}));
}
export function freezeGraphqlSchemaInitialPrivileges(value) {
  return Object.freeze(value.map(item => Object.freeze({privtype:item.privtype,isNull:item.isNull,
    grants:Object.freeze(item.grants.map(row=>Object.freeze([...row])))})));
}
export function nativeGraphqlSchemaBaselineExact(witness) {
  const current = witness?.wrapperSchemaDetails, initial = witness?.wrapperSchemaInitialPrivileges;
  const equal = rows => JSON.stringify(ordered(rows)) === JSON.stringify(ordered(expected));
  return validGraphqlSchemaDetails(current) && current.owner === 'supabase_admin' && current.isNull === false
    && equal(current.grants) && validGraphqlSchemaInitialPrivileges(initial) && initial.length === 1
    && initial[0].privtype === 'e' && initial[0].isNull === false && equal(initial[0].grants);
}
// The disposable target is already guarded by the native adapter. Recheck the
// exact SQL identity and empty native schema before applying this prerequisite.
const before = `DO $jolene_graphql_baseline$
BEGIN
 IF (
  current_database()='jolene_candidatures_pg17_test' AND inet_server_addr() IS NULL
  AND session_user='supabase_admin' AND current_user=session_user
  AND current_setting('server_version_num')::integer=170006
  AND current_setting('cron.launch_active_jobs',true)='off' AND current_setting('max_worker_processes')='0'
  AND (SELECT count(*)=1 AND bool_and(pg_catalog.pg_get_userbyid(n.nspowner)='supabase_admin' AND n.nspacl IS NULL)
       FROM pg_catalog.pg_namespace n WHERE n.nspname='graphql_public')
  AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_extension WHERE extname='pg_graphql')
  AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='graphql_public')
  AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_init_privs i JOIN pg_catalog.pg_namespace n ON n.oid=i.objoid
       WHERE i.classoid='pg_catalog.pg_namespace'::regclass AND n.nspname='graphql_public')
 ) IS NOT TRUE THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='B_GRAPHQL_NATIVE_BASELINE_REFUSED'; END IF;
END;
$jolene_graphql_baseline$;
`;
const after = `DO $jolene_graphql_baseline$
BEGIN
 IF (
  (SELECT count(*)=6 AND count(DISTINCT (x.grantee,x.grantor,x.privilege_type,x.is_grantable))=6
   AND bool_and(pg_catalog.pg_get_userbyid(x.grantor)='supabase_admin' AND NOT x.is_grantable
     AND ((pg_catalog.pg_get_userbyid(x.grantee)='supabase_admin' AND x.privilege_type IN('CREATE','USAGE'))
       OR (pg_catalog.pg_get_userbyid(x.grantee) IN('postgres','anon','authenticated','service_role') AND x.privilege_type='USAGE')))
   FROM pg_catalog.pg_namespace n CROSS JOIN LATERAL pg_catalog.aclexplode(n.nspacl) x WHERE n.nspname='graphql_public')
 ) IS NOT TRUE THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='B_GRAPHQL_NATIVE_BASELINE_REFUSED'; END IF;
END;
$jolene_graphql_baseline$;
`;
// Fixed vendor bytes only: no role, privilege, owner or SQL is derived from a
// diagnostic or interpolated from the source catalogue.
export const GRAPHQL_NATIVE_BASELINE_SQL = before + GRAPHQL_VENDOR_SCHEMA_GRANT + after;
