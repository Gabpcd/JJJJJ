-- Catalogue runtime local uniquement ; aucune extension créée/modifiée.
WITH wanted(name) AS (VALUES ('pg_cron'),('pg_net'),('pg_stat_statements'),('pg_trgm'),('pgcrypto'),('pgjwt'),('plpgsql'),('supabase_vault'),('uuid-ossp'))
SELECT jsonb_build_object('postgres_major',current_setting('server_version_num')::integer/10000,
 'extensions',jsonb_agg(jsonb_build_object('name',w.name,
  'installed',(SELECT jsonb_build_object('version',e.extversion,'schema',n.nspname) FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace WHERE e.extname=w.name),
  'available_count',(SELECT count(*) FROM pg_catalog.pg_available_extension_versions v WHERE v.name=w.name),
  'available_truncated',(SELECT count(*)>50 FROM pg_catalog.pg_available_extension_versions v WHERE v.name=w.name),
  'available_versions',coalesce((SELECT jsonb_agg(jsonb_build_object('version',v.version,'superuser',v.superuser,'trusted',v.trusted,'relocatable',v.relocatable,'schema',v.schema,'requires',v.requires) ORDER BY v.version) FROM (SELECT * FROM pg_catalog.pg_available_extension_versions a WHERE a.name=w.name ORDER BY a.version LIMIT 50) v),'[]'::jsonb)
 ) ORDER BY w.name)) FROM wanted w;
