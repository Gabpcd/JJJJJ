BEGIN READ ONLY;
SET LOCAL statement_timeout = '10s';
DO $check$
BEGIN
  IF current_setting('server_version_num')::integer / 10000 <> 17 THEN
    RAISE EXCEPTION 'POSTGRES_17_REQUIRED';
  END IF;
  IF NOT (inet_server_addr() IS NULL OR inet_server_addr() <<= '10.0.0.0/8'::inet
    OR inet_server_addr() <<= '172.16.0.0/12'::inet OR inet_server_addr() <<= '192.168.0.0/16'::inet) THEN
    RAISE EXCEPTION 'LOCAL_ADDRESS_REQUIRED';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users) OR EXISTS (SELECT 1 FROM auth.sessions)
    OR EXISTS (SELECT 1 FROM storage.objects) OR EXISTS (SELECT 1 FROM storage.buckets)
    OR EXISTS (SELECT 1 FROM cron.job) OR EXISTS (SELECT 1 FROM vault.secrets)
    OR EXISTS (SELECT 1 FROM net.http_request_queue) OR EXISTS (SELECT 1 FROM supabase_functions.hooks)
    OR EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal AND tgfoid = 'supabase_functions.http_request()'::regprocedure)
    OR EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')) THEN
    RAISE EXCEPTION 'EMPTY_CORE_REQUIRED';
  END IF;
END
$check$;
SELECT 'EMPTY_LOCAL_CORE' AS result;
ROLLBACK;
