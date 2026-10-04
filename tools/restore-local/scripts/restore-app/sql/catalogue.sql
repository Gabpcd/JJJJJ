BEGIN READ ONLY;
SET LOCAL row_security=off;
SET LOCAL statement_timeout='45s';
-- Native PG17 regression: the old expression must be ambiguous, the cast must
-- resolve to text. All values below are constants; no catalogue row is exported.
DO $catalogue_type_guard$
DECLARE old_expression_ambiguous boolean := false; corrected text;
BEGIN
  IF current_database()<>'jolene_candidatures_pg17_test' OR inet_server_addr() IS NOT NULL
    OR session_user<>'postgres' OR current_user<>session_user
    OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
    OR current_setting('cron.launch_active_jobs')<>'off' OR current_setting('max_worker_processes')<>'0'
    OR NOT EXISTS (SELECT 1 FROM pg_attribute
      WHERE attrelid='pg_catalog.pg_default_acl'::regclass AND attname='defaclobjtype'
        AND atttypid='"char"'::regtype AND NOT attisdropped)
  THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='RESTORE_CATALOGUE_TYPE_CONTEXT'; END IF;
  BEGIN
    EXECUTE $old_expression$SELECT 'prefix.'::text || 'r'::"char"$old_expression$;
  EXCEPTION WHEN SQLSTATE '42725' THEN old_expression_ambiguous := true;
  END;
  IF old_expression_ambiguous IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='RESTORE_CATALOGUE_AMBIGUITY_EXPECTED';
  END IF;
  SELECT 'prefix.'::text || ('r'::"char")::text INTO corrected;
  IF corrected IS DISTINCT FROM 'prefix.r' THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='RESTORE_CATALOGUE_CAST_REQUIRED';
  END IF;
END $catalogue_type_guard$;
WITH facts AS (
 SELECT 'relation' AS kind,n.nspname||'.'||c.relname AS name,
   jsonb_build_array(c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner),c.relacl) AS value
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','auth','storage')
 UNION ALL SELECT 'column',n.nspname||'.'||c.relname||'.'||a.attname,
   jsonb_build_array(format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attidentity,a.attgenerated,a.attacl,pg_get_expr(d.adbin,d.adrelid))
 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
 WHERE n.nspname IN('public','private','auth','storage') AND a.attnum>0 AND NOT a.attisdropped
 UNION ALL SELECT 'function',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
   jsonb_build_array(pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl)
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN('public','private','auth','storage') AND p.prokind IN('f','p')
 UNION ALL SELECT 'policy',schemaname||'.'||tablename||'.'||policyname,to_jsonb(p)
 FROM pg_policies p WHERE schemaname IN('public','private','auth','storage')
 UNION ALL SELECT 'trigger',n.nspname||'.'||c.relname||'.'||t.tgname,jsonb_build_array(pg_get_triggerdef(t.oid),t.tgenabled)
 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private','auth','storage') AND NOT t.tgisinternal
 UNION ALL SELECT 'constraint',n.nspname||'.'||c.relname||'.'||con.conname,to_jsonb(pg_get_constraintdef(con.oid))
 FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private','auth','storage')
 UNION ALL SELECT 'index',schemaname||'.'||indexname,to_jsonb(indexdef)
 FROM pg_indexes WHERE schemaname IN('public','private','auth','storage')
 UNION ALL SELECT 'extension',e.extname,jsonb_build_array(e.extversion,n.nspname,pg_get_userbyid(e.extowner))
 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
 UNION ALL SELECT 'default_acl',pg_get_userbyid(d.defaclrole)||'.'||coalesce(n.nspname,'global')||'.'||d.defaclobjtype::text,
   to_jsonb(d.defaclacl) FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
)
SELECT jsonb_build_object(
 'catalogue_sha256',encode(extensions.digest(convert_to((SELECT jsonb_agg(jsonb_build_array(kind,name,value) ORDER BY kind,name,value::text)::text FROM facts),'UTF8'),'sha256'),'hex'),
 'database',(SELECT jsonb_build_array(pg_get_userbyid(datdba),datacl,pg_encoding_to_char(encoding),datcollate,datctype) FROM pg_database WHERE datname=current_database()),
 'roles',(SELECT jsonb_agg(jsonb_build_array(rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolconfig) ORDER BY rolname) FROM pg_roles),
 'memberships',(SELECT jsonb_agg(jsonb_build_array(pg_get_userbyid(roleid),pg_get_userbyid(member),admin_option,inherit_option,set_option) ORDER BY pg_get_userbyid(roleid),pg_get_userbyid(member)) FROM pg_auth_members));
ROLLBACK;
