-- Current main7df/219 catalogue witness, executed only after the integral import.
-- Read-only: does not create Auth users, request OTP or alter permissions.
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
WITH routines AS (
 SELECT p.*, e.expected_md5 FROM (VALUES
 ('public.fn_envoyer_otp_signature(uuid)'::regprocedure, '24271f58b25ddaaf943c33041f31192a'),
 ('public.fn_signer_contrat_otp(uuid,text,text,text)'::regprocedure, '9d56c7dca13f13fd3d75f601b8b3ac73')
 ) AS e(oid,expected_md5) JOIN pg_proc p ON p.oid=e.oid
), columns AS (
 SELECT attname,has_column_privilege('authenticated','public.signatures_contrats',attname,'SELECT') AS readable,
   has_column_privilege('anon','public.signatures_contrats',attname,'SELECT') AS anonymous
 FROM pg_attribute WHERE attrelid='public.signatures_contrats'::regclass AND attnum>0 AND NOT attisdropped
)
SELECT jsonb_build_object(
 'localContext',current_database()='jolene_candidatures_pg17_test' AND inet_server_addr() IS NULL
   AND session_user='postgres' AND current_user=session_user
   AND current_setting('server_version_num')::integer BETWEEN 170000 AND 179999
   AND current_setting('cron.launch_active_jobs')='off' AND current_setting('max_worker_processes')='0',
 'functionsExact',(SELECT count(*)=2 AND bool_and(md5(prosrc)=expected_md5 AND proowner='postgres'::regrole
   AND prosecdef IS TRUE AND proconfig=ARRAY['search_path=public, extensions']::text[]
   AND proacl::text='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
   AND NOT has_function_privilege('anon',oid,'EXECUTE')
   AND has_function_privilege('authenticated',oid,'EXECUTE') AND has_function_privilege('service_role',oid,'EXECUTE')) FROM routines),
 'certificateExact',NOT has_table_privilege('authenticated','public.signatures_contrats','SELECT')
   AND NOT has_table_privilege('anon','public.signatures_contrats','SELECT')
   AND (SELECT array_agg(attname::text ORDER BY attname) FILTER(WHERE readable) =
   ARRAY['contrat_id','cree_le','hash_document','id','ip_signature','otp_valide_a','psc_session_active','rpps_verifie',
     'signataire_role','signataire_user_id','signe_a','statut_signature','traits_identite_verifies','user_agent']::text[]
   AND NOT bool_or(anonymous) FROM columns)
   AND NOT has_column_privilege('authenticated','public.signatures_contrats','otp_code_hash','SELECT'));
ROLLBACK;
