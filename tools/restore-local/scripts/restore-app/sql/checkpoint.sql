-- Run with all source APIs stopped before backup, and all target APIs stopped
-- after pg_restore, before ANY target login. Results remain private.
BEGIN READ ONLY;
SET LOCAL row_security=off;
SET LOCAL statement_timeout='45s';
DO $restore_checkpoint$
DECLARE item record; rows_digest jsonb:='{}'::jsonb; row_count bigint; row_hash text;
BEGIN
  IF current_database()<>'jolene_candidatures_pg17_test' OR inet_server_addr() IS NOT NULL
    OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
    OR current_setting('cron.launch_active_jobs')<>'off' OR current_setting('max_worker_processes')<>'0'
    OR EXISTS(SELECT 1 FROM pg_stat_activity WHERE backend_type IN ('pg_cron launcher','pg_cron worker','pg_net worker'))
    OR EXISTS(SELECT 1 FROM cron.job WHERE active) OR EXISTS(SELECT 1 FROM net.http_request_queue)
    OR EXISTS(SELECT 1 FROM net._http_response) OR EXISTS(SELECT 1 FROM vault.secrets)
    OR EXISTS(SELECT 1 FROM auth.sessions) OR EXISTS(SELECT 1 FROM auth.refresh_tokens)
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE actif)
    OR EXISTS(SELECT 1 FROM public.email_queue) OR EXISTS(SELECT 1 FROM public.paiements_escrow)
    OR EXISTS(SELECT 1 FROM public.stripe_transfers)
    OR (SELECT count(*) FROM auth.users)<>5 OR (SELECT count(*) FROM auth.identities)<>5
    OR (SELECT count(*) FROM public.soignants)<>2 OR (SELECT count(*) FROM public.etablissements)<>2
    OR (SELECT count(*) FROM public.missions)<>1 OR (SELECT count(*) FROM public.factures_honoraires)<>1
    OR (SELECT count(*) FROM public.factures_honoraires_documents)<>1
    OR (SELECT count(*) FROM storage.objects)<>2
    OR EXISTS(SELECT 1 FROM auth.users WHERE email NOT LIKE 'restore-%@example.invalid'
      OR raw_app_meta_data->'est_compte_test' IS DISTINCT FROM 'true'::jsonb
      OR deleted_at IS NOT NULL OR email_confirmed_at IS NULL OR encrypted_password IS NULL OR encrypted_password='')
    OR EXISTS(SELECT 1 FROM auth.identities WHERE provider<>'email')
    OR EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id<>'jolene-documents' OR name NOT LIKE 'invoices/restore/%')
  THEN RAISE EXCEPTION 'RESTORE_CHECKPOINT_CONTEXT'; END IF;
  -- Includes Auth password hashes and identities WITHOUT exporting their values.
  -- No exclusion for data modified by triggers: snapshots must match before login.
  FOR item IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN('auth','storage','public','private') AND c.relkind IN('r','p')
    AND NOT c.relispartition ORDER BY n.nspname,c.relname LOOP
    EXECUTE format('SELECT count(*),encode(extensions.digest(convert_to(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb)::text,''UTF8''),''sha256''),''hex'') FROM %I.%I t',item.nspname,item.relname)
      INTO row_count,row_hash;
    rows_digest:=rows_digest||jsonb_build_object(item.nspname||'.'||item.relname,jsonb_build_object('count',row_count,'sha256',row_hash));
  END LOOP;
  PERFORM set_config('jolene.restore_checkpoint',rows_digest::text,true);
END $restore_checkpoint$;
SELECT current_setting('jolene.restore_checkpoint')::jsonb;
ROLLBACK;
