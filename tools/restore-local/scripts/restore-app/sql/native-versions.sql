BEGIN READ ONLY;
SET LOCAL row_security=off;
SET LOCAL statement_timeout='15s';
SELECT jsonb_build_object(
 'postgresVersionNum',current_setting('server_version_num')::integer,
 'auth',(SELECT jsonb_build_object('count',count(*),'sha256',encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(m) ORDER BY to_jsonb(m)::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM auth.schema_migrations m),
 'storage',(SELECT jsonb_build_object('count',count(*),'sha256',encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(m) ORDER BY to_jsonb(m)::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM storage.migrations m));
ROLLBACK;
