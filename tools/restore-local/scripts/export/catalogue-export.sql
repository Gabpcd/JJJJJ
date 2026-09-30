-- Une seule lecture des catalogues. Aucun mot de passe, corps SQL libre ou ligne applicative.
WITH ns AS (SELECT oid,nspname,nspowner,nspacl FROM pg_catalog.pg_namespace WHERE nspname IN ('public','private','auth','storage')),
objects AS (
 SELECT 'schema' AS kind,n.nspname AS identity,md5(concat_ws('|',n.nspowner::text,n.nspacl::text)) AS fingerprint FROM ns n
 UNION ALL
 SELECT 'routine',p.oid::regprocedure::text,md5(concat_ws('|',pg_catalog.pg_get_functiondef(p.oid),p.proowner::text,p.proacl::text)) FROM pg_catalog.pg_proc p JOIN ns n ON n.oid=p.pronamespace WHERE p.prokind IN ('f','p')
 UNION ALL
 SELECT 'relation',c.oid::regclass::text,md5(concat_ws('|',c.relkind::text,c.relowner::text,c.relacl::text,c.relrowsecurity::text,c.relforcerowsecurity::text,c.reloptions::text)) FROM pg_catalog.pg_class c JOIN ns n ON n.oid=c.relnamespace WHERE c.relkind IN ('r','p','v','m','S','f')
 UNION ALL
 SELECT 'column',c.oid::regclass::text||'.'||a.attname,md5(concat_ws('|',pg_catalog.format_type(a.atttypid,a.atttypmod),a.attnum::text,a.attnotnull::text,a.attidentity::text,a.attgenerated::text,pg_catalog.pg_get_expr(d.adbin,d.adrelid),a.attacl::text)) FROM pg_catalog.pg_class c JOIN ns n ON n.oid=c.relnamespace JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum WHERE a.attnum>0 AND NOT a.attisdropped
 UNION ALL
 SELECT 'constraint',c.conrelid::regclass::text||'.'||c.conname,md5(pg_catalog.pg_get_constraintdef(c.oid,true)) FROM pg_catalog.pg_constraint c JOIN ns n ON n.oid=c.connamespace
 UNION ALL
 SELECT 'index',i.indexrelid::regclass::text,md5(pg_catalog.pg_get_indexdef(i.indexrelid)) FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid JOIN ns n ON n.oid=c.relnamespace
 UNION ALL
 SELECT 'trigger',t.tgrelid::regclass::text||'.'||t.tgname,md5(concat_ws('|',pg_catalog.pg_get_triggerdef(t.oid,true),t.tgenabled::text)) FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN ns n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal
 UNION ALL
 SELECT 'policy',p.polrelid::regclass::text||'.'||p.polname,md5(concat_ws('|',p.polcmd::text,p.polpermissive::text,p.polroles::text,pg_catalog.pg_get_expr(p.polqual,p.polrelid),pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid))) FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid JOIN ns n ON n.oid=c.relnamespace
 UNION ALL
 SELECT 'view',c.oid::regclass::text,md5(pg_catalog.pg_get_viewdef(c.oid,true)) FROM pg_catalog.pg_class c JOIN ns n ON n.oid=c.relnamespace WHERE c.relkind IN ('v','m')
 UNION ALL
 SELECT 'enum',t.oid::regtype::text,md5(string_agg(e.enumlabel,'|' ORDER BY e.enumsortorder)) FROM pg_catalog.pg_type t JOIN ns n ON n.oid=t.typnamespace JOIN pg_catalog.pg_enum e ON e.enumtypid=t.oid GROUP BY t.oid
 UNION ALL
 SELECT 'default_acl',n.nspname||'.'||a.defaclrole::text||'.'||a.defaclobjtype::text,md5(a.defaclacl::text) FROM pg_catalog.pg_default_acl a JOIN ns n ON n.oid=a.defaclnamespace
), extensions AS (
 SELECT e.extname AS name,e.extversion AS version,n.nspname AS schema FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
)
SELECT jsonb_build_object(
 'version',1,'database',current_database(),'read_only',current_setting('transaction_read_only')='on',
 'postgres_major',current_setting('server_version_num')::integer/10000,
 'catalogue_md5',(SELECT md5(string_agg(kind||'|'||identity||'|'||fingerprint,E'\n' ORDER BY kind,identity,fingerprint)) FROM objects),
 'object_count',(SELECT count(*) FROM objects),
 'application_schemas',(SELECT jsonb_agg(nspname ORDER BY nspname) FROM ns WHERE nspname IN ('public','private')),
 'extensions',(SELECT jsonb_agg(to_jsonb(e) ORDER BY name) FROM extensions e),
 'foreign_tables',(SELECT count(*) FROM pg_catalog.pg_class c JOIN ns n ON n.oid=c.relnamespace WHERE c.relkind='f'),
 'managed_policies',(SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',p.polname) ORDER BY n.nspname,c.relname,p.polname),'[]'::jsonb) FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid JOIN ns n ON n.oid=c.relnamespace WHERE n.nspname IN ('auth','storage')),
 'auth_triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object('schema','auth','table',c.relname,'name',t.tgname) ORDER BY c.relname,t.tgname),'[]'::jsonb) FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN ns n ON n.oid=c.relnamespace WHERE n.nspname='auth' AND NOT t.tgisinternal),
 'direct_secret_pattern_routines',(SELECT count(*) FROM pg_catalog.pg_proc p JOIN ns n ON n.oid=p.pronamespace WHERE p.prokind IN ('f','p') AND (p.prosrc ~ '(sk_live_|sk_test_|sb_secret_|sbp_|-----BEGIN [A-Z ]*PRIVATE KEY-----)' OR p.prosrc ~ 'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'))
) AS catalogue;
