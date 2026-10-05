-- PREPARATION ONLY. Read before the source dump and after the target restore.
-- Keep the entire result private; publish only a verified boolean after checking.
-- Exact public-source bodies: supabase/postgres a431c10, migration 20231017062225.
BEGIN READ ONLY;
SET LOCAL search_path=pg_catalog;
SET LOCAL row_security=off;
SET LOCAL statement_timeout='15s';
WITH wrapper AS (
 SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='graphql_public' AND p.proname='graphql'
), hook AS (
 SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='extensions' AND p.proname='grant_pg_graphql_access'
), extension AS (
 SELECT e.* FROM pg_extension e WHERE e.extname='pg_graphql'
), trigger AS (
 SELECT e.* FROM pg_event_trigger e WHERE e.evtname='issue_pg_graphql_access'
), defaults AS (
 SELECT d.* FROM pg_default_acl d JOIN pg_namespace n ON n.oid=d.defaclnamespace
 WHERE n.nspname='graphql_public' AND d.defaclobjtype='f'
), initial_privileges AS (
 SELECT i.* FROM pg_init_privs i JOIN wrapper p ON p.oid=i.objoid
 WHERE i.classoid='pg_proc'::regclass AND i.objsubid=0
), wrapper_schema AS (
 SELECT n.* FROM pg_namespace n WHERE n.nspname='graphql_public'
), wrapper_schema_acl AS (
 -- aclexplode preserves every grantor, grantee, privilege and grant option.
 -- PUBLIC is tagged separately from a named role, even a role named PUBLIC.
 SELECT jsonb_build_array(CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE 'ROLE' END,
   CASE WHEN x.grantee=0 THEN NULL ELSE pg_get_userbyid(x.grantee) END,
   pg_get_userbyid(x.grantor),x.privilege_type,x.is_grantable) AS grant_tuple
 FROM wrapper_schema n CROSS JOIN LATERAL aclexplode(n.nspacl) x
), facts AS (
 SELECT 'wrapper' AS kind,jsonb_build_array(pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl) AS fact FROM wrapper p
 UNION ALL SELECT 'hook',jsonb_build_array(pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl) FROM hook p
 UNION ALL SELECT 'extension',jsonb_build_array(e.extversion,n.nspname,pg_get_userbyid(e.extowner)) FROM extension e JOIN pg_namespace n ON n.oid=e.extnamespace
 UNION ALL SELECT 'trigger',jsonb_build_array(e.evtevent,e.evtenabled,e.evttags,pg_get_userbyid(e.evtowner)) FROM trigger e
 UNION ALL SELECT 'initial_privileges',jsonb_build_array(i.privtype,i.initprivs) FROM initial_privileges i
 UNION ALL SELECT 'default_acl',jsonb_build_array(pg_get_userbyid(d.defaclrole),d.defaclacl) FROM defaults d
 UNION ALL SELECT 'schemas',jsonb_build_array(n.nspname,pg_get_userbyid(n.nspowner),
   CASE WHEN n.nspname='graphql_public' THEN jsonb_build_object('isNull',n.nspacl IS NULL,
     'grants',COALESCE((SELECT jsonb_agg(grant_tuple ORDER BY grant_tuple::text COLLATE "C") FROM wrapper_schema_acl),'[]'::jsonb))
   ELSE to_jsonb(n.nspacl) END)
 FROM pg_namespace n WHERE n.nspname IN('graphql','graphql_public','extensions')
)
SELECT jsonb_build_object(
 'schemaVersion',3,
 'context',current_database()='jolene_candidatures_pg17_test' AND inet_server_addr() IS NULL
   AND session_user='postgres' AND current_user=session_user
   AND current_setting('server_version_num')::integer BETWEEN 170000 AND 179999
   AND current_setting('cron.launch_active_jobs',true)='off' AND current_setting('max_worker_processes')='0',
 'nativeExtensionExact',(SELECT count(*)=1 AND bool_and(n.nspname='graphql' AND pg_get_userbyid(e.extowner)='supabase_admin'
   AND e.extversion=a.default_version) FROM extension e JOIN pg_namespace n ON n.oid=e.extnamespace
   JOIN pg_available_extensions a ON a.name=e.extname),
 'wrapperSignatureExact',(SELECT count(*)=1 AND bool_and(p.proargtypes='25 25 3802 3802'::oidvector
   AND p.proargnames=ARRAY['operationName','query','variables','extensions']::text[] AND p.proargmodes IS NULL
   AND p.proallargtypes IS NULL AND p.pronargs=4 AND p.pronargdefaults=4 AND p.prokind='f'
   AND p.prorettype='jsonb'::regtype AND l.lanname='sql' AND NOT p.prosecdef AND NOT p.proretset
   AND p.proconfig IS NULL AND p.provolatile='v' AND p.proparallel='u'
   AND pg_get_expr(p.proargdefaults,0)='NULL::text, NULL::text, NULL::jsonb, NULL::jsonb')
   FROM wrapper p JOIN pg_language l ON l.oid=p.prolang),
 'wrapperBodyExact',(SELECT count(*)=1 AND bool_and(encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='03b36c9655c8688b452fba90346ce43dafa2ded68bffb9250da6c236133d467e') FROM wrapper p),
 'wrapperMembershipExact',(SELECT count(*)=1 AND bool_and(d.refobjid=e.oid AND d.deptype='e')
   FROM wrapper p JOIN pg_depend d ON d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.refclassid='pg_extension'::regclass
   CROSS JOIN extension e),
 'wrapperOwnerExact',(SELECT count(*)=1 AND bool_and(pg_get_userbyid(p.proowner)='supabase_admin') FROM wrapper p),
 'hookSignatureExact',(SELECT count(*)=1 AND bool_and(p.pronargs=0 AND p.prorettype='event_trigger'::regtype
   AND l.lanname='plpgsql' AND NOT p.prosecdef AND NOT p.proretset AND p.prokind='f' AND p.proconfig IS NULL
   AND p.provolatile='v' AND p.proparallel='u') FROM hook p JOIN pg_language l ON l.oid=p.prolang),
 'hookBodyExact',(SELECT count(*)=1 AND bool_and(encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='ad8bfb866513170056bbc1f817103be550cd62efcb589fa2a3807718efb3eb6a') FROM hook p),
 'hookOwnerExact',(SELECT count(*)=1 AND bool_and(pg_get_userbyid(p.proowner)='supabase_admin') FROM hook p),
 'hookNotExtensionMember',NOT EXISTS(SELECT 1 FROM hook p JOIN pg_depend d ON d.classid='pg_proc'::regclass
   AND d.objid=p.oid AND d.refclassid='pg_extension'::regclass AND d.deptype='e'),
 'triggerExact',(SELECT count(*)=1 AND bool_and(e.evtevent='ddl_command_end' AND e.evtenabled='O'
   AND e.evttags=ARRAY['CREATE FUNCTION']::text[] AND e.evtfoid=p.oid AND pg_get_userbyid(e.evtowner)='supabase_admin')
   FROM trigger e CROSS JOIN hook p),
 'schemaOwnersExact',(SELECT count(*)=2 AND bool_and(pg_get_userbyid(n.nspowner)=CASE n.nspname WHEN 'extensions' THEN 'postgres' ELSE 'supabase_admin' END)
   FROM pg_namespace n WHERE n.nspname IN('extensions','graphql_public')),
 'defaultFunctionAclExact',(SELECT count(*)=1 AND bool_and(pg_get_userbyid(d.defaclrole)='supabase_admin'
   AND (SELECT count(*)=4 AND count(DISTINCT x.grantee)=4 AND bool_and(x.privilege_type='EXECUTE' AND NOT x.is_grantable
     AND pg_get_userbyid(x.grantee) IN('postgres','anon','authenticated','service_role')
     AND pg_get_userbyid(x.grantor)='supabase_admin') FROM aclexplode(d.defaclacl) x)) FROM defaults d),
 'noGlobalFunctionDefaultAcl',NOT EXISTS(SELECT 1 FROM pg_default_acl d WHERE d.defaclnamespace=0 AND d.defaclobjtype='f'
   AND pg_get_userbyid(d.defaclrole)='supabase_admin'),
 'initialPrivilegesCount',(SELECT count(*) FROM initial_privileges),
 -- Diagnostic only; never substitutes for the complete semantic fingerprint.
 'wrapperSchemaRawFingerprint',(SELECT encode(sha256(convert_to(jsonb_build_array(
   n.nspname,pg_get_userbyid(n.nspowner),n.nspacl)::text,'UTF8')),'hex') FROM wrapper_schema n),
 'fingerprint',encode(sha256(convert_to((SELECT jsonb_agg(jsonb_build_array(kind,fact) ORDER BY kind,fact::text)::text FROM facts),'UTF8')),'hex'),
 -- Private component hashes. Both aggregate and component equality remain mandatory.
 'components',(SELECT jsonb_object_agg(k,encode(sha256(convert_to(
   COALESCE((SELECT jsonb_agg(f.fact ORDER BY f.fact::text)::text FROM facts f
     WHERE CASE WHEN f.kind='schemas' THEN 'schema_'||(f.fact->>0) ELSE f.kind END=k),'[]'),'UTF8')),'hex'))
   FROM unnest(ARRAY['wrapper','hook','extension','trigger','initial_privileges','default_acl',
     'schema_extensions','schema_graphql_public','schema_graphql']) k)
);
ROLLBACK;
