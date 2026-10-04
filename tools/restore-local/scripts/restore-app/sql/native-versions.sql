-- Native-version identity excludes installation time, never migration contents.
-- Auth v2.196.0: migrations/00_init_auth_schema.up.sql (version only).
-- Storage v1.74.0 locks postgres-migrations 5.3.0: id/name/hash/executed_at.
-- Its INSERT omits executed_at, whose DEFAULT current_timestamp varies by install.
BEGIN READ ONLY;
SET LOCAL row_security=off;
SET LOCAL statement_timeout='15s';
DO $native_contract$
DECLARE actual jsonb; same_a text; same_b text; changed text;
BEGIN
  SELECT jsonb_agg(jsonb_build_array(n.nspname,c.relname,a.attname,
    pg_catalog.format_type(a.atttypid,a.atttypmod),a.attnotnull) ORDER BY n.nspname,c.relname,a.attname)
  INTO actual FROM pg_catalog.pg_attribute a
  JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE ((n.nspname='auth' AND c.relname='schema_migrations')
    OR (n.nspname='storage' AND c.relname='migrations'))
    AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped;
  IF actual IS DISTINCT FROM '[
    ["auth","schema_migrations","version","character varying(255)",true],
    ["storage","migrations","executed_at","timestamp without time zone",false],
    ["storage","migrations","hash","character varying(40)",true],
    ["storage","migrations","id","integer",true],
    ["storage","migrations","name","character varying(100)",true]
  ]'::jsonb THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PHASE_A_NATIVE_SCHEMA'; END IF;
  IF EXISTS (SELECT 1 FROM auth.schema_migrations GROUP BY version HAVING count(*)<>1)
    OR EXISTS (SELECT 1 FROM storage.migrations GROUP BY id HAVING count(*)<>1)
    OR EXISTS (SELECT 1 FROM storage.migrations GROUP BY name HAVING count(*)<>1)
    OR EXISTS (SELECT 1 FROM auth.schema_migrations WHERE version='')
    OR EXISTS (SELECT 1 FROM storage.migrations WHERE name='' OR hash!~'^[a-f0-9]{40}$')
    THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PHASE_A_NATIVE_ROWS'; END IF;
  -- Native SQL witness, executed on the isolated source before returning identity.
  -- Same stable fields/different installation dates must match; changed hash must not.
  WITH samples(sample,id,name,hash,executed_at) AS (VALUES
    (1,0::integer,'synthetic'::varchar(100),repeat('a',40)::varchar(40),timestamp '2000-01-01'),
    (2,0::integer,'synthetic'::varchar(100),repeat('a',40)::varchar(40),timestamp '2001-01-01'),
    (3,0::integer,'synthetic'::varchar(100),repeat('b',40)::varchar(40),timestamp '2000-01-01')),
  projected AS (SELECT s.sample,to_jsonb(m)-'executed_at' AS identity FROM samples s
    CROSS JOIN LATERAL (SELECT s.id,s.name,s.hash,s.executed_at) m),
  fingerprints AS (SELECT sample,encode(extensions.digest(convert_to(
    jsonb_agg(identity ORDER BY identity::text)::text,'UTF8'),'sha256'),'hex') AS sha256
    FROM projected GROUP BY sample)
  SELECT max(sha256) FILTER(WHERE sample=1),max(sha256) FILTER(WHERE sample=2),
    max(sha256) FILTER(WHERE sample=3) INTO same_a,same_b,changed FROM fingerprints;
  IF same_a IS NULL OR same_a IS DISTINCT FROM same_b OR same_a IS NOT DISTINCT FROM changed
    THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PHASE_A_NATIVE_IDENTITY_WITNESS'; END IF;
END
$native_contract$;
SELECT jsonb_build_object(
 'postgresVersionNum',current_setting('server_version_num')::integer,
 'auth',(SELECT jsonb_build_object('count',count(*),'sha256',encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(m) ORDER BY to_jsonb(m)::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM auth.schema_migrations m),
 'storage',(SELECT jsonb_build_object('count',count(*),'sha256',encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(m)-'executed_at' ORDER BY (to_jsonb(m)-'executed_at')::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM storage.migrations m));
ROLLBACK;
