-- Diagnostic uniquement, à envoyer au staging mejpriaetwgtcstbgfid avec
-- l'option Management API read_only:true. Une seule instruction SELECT.
-- Aucun corps de fonction, défaut, prédicat, commande cron, secret ou donnée
-- métier ne sort : uniquement identités de catalogue, nombres et empreintes.
-- Ce reçu ne remplace pas les constantes de candidatures-fixture-contract.mjs.
WITH
relations AS (
  SELECT unnest(ARRAY[
    'auth.users'::regclass, 'public.soignants'::regclass,
    'public.etablissements'::regclass, 'public.missions'::regclass,
    'public.mission_creneaux'::regclass, 'public.candidatures'::regclass,
    'public.notifications'::regclass, 'public.preferences_notifications'::regclass,
    'public.rate_limits'::regclass, 'public.journaux_audit'::regclass
  ]) AS oid
),
colonnes AS (
  SELECT a.attrelid::regclass::text AS relation, a.attnum, a.attname,
    format_type(a.atttypid,a.atttypmod) AS type_name, a.attnotnull,
    md5(pg_get_expr(d.adbin,d.adrelid)) AS default_md5,
    jsonb_build_array(a.attrelid::regclass::text,a.attname,
      format_type(a.atttypid,a.atttypmod),a.attnotnull,
      pg_get_expr(d.adbin,d.adrelid)) AS original_row
  FROM pg_attribute a
  LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attnum>0 AND NOT a.attisdropped
    AND a.attrelid IN (SELECT oid FROM relations)
),
contraintes AS (
  SELECT c.conrelid::regclass::text AS relation,c.conname,c.contype,
    CASE WHEN c.confrelid=0 THEN NULL ELSE c.confrelid::regclass::text END AS referenced_relation,
    md5(pg_get_constraintdef(c.oid)) AS definition_md5,
    jsonb_build_array(c.conrelid::regclass::text,c.conname,
      pg_get_constraintdef(c.oid)) AS original_row
  FROM pg_constraint c
  WHERE c.conrelid IN (SELECT oid FROM relations)
     OR c.confrelid IN (SELECT oid FROM relations)
),
fonctions AS (
  SELECT n.nspname AS schema_name,p.oid::regprocedure::text AS signature,
    md5(p.prosrc) AS body_md5,md5(pg_get_functiondef(p.oid)) AS definition_md5,
    md5(coalesce(p.proacl::text,'')) AS acl_md5,
    n.nspname||'.'||p.oid::regprocedure::text||':'||pg_get_functiondef(p.oid)
      ||':'||coalesce(p.proacl::text,'') AS original_row
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')
),
declencheurs AS (
  SELECT t.tgrelid::regclass::text AS relation,t.tgname,t.tgenabled::text AS enabled,
    t.tgfoid::regprocedure::text AS function_signature,
    md5(pg_get_triggerdef(t.oid)) AS definition_md5,
    md5(pg_get_functiondef(t.tgfoid)) AS function_definition_md5,
    t.tgrelid::regclass::text||':'||pg_get_triggerdef(t.oid)||':'||t.tgenabled::text
      ||':'||pg_get_functiondef(t.tgfoid) AS original_row
  FROM pg_trigger t
  WHERE NOT t.tgisinternal AND t.tgrelid IN (SELECT oid FROM relations)
)
SELECT jsonb_build_object(
  'observed_at',current_timestamp,
  'transaction_read_only',current_setting('transaction_read_only'),
  'server_version_num',current_setting('server_version_num'),
  'search_path_md5',md5(current_setting('search_path')),
  'scope','D2_CATALOGUE_METADATA_AND_HASHES_ONLY',
  'aggregate',jsonb_build_object(
    'schema',md5(jsonb_build_object(
      'colonnes',(SELECT jsonb_agg(original_row ORDER BY relation,attnum) FROM colonnes),
      'contraintes',(SELECT jsonb_agg(original_row ORDER BY relation,conname) FROM contraintes)
    )::text),
    'fonctions',(SELECT md5(string_agg(original_row,'|' ORDER BY schema_name,signature)) FROM fonctions),
    'triggers',(SELECT md5(string_agg(original_row,'|' ORDER BY relation,tgname)) FROM declencheurs),
    'crons_actifs',(SELECT count(*)::integer FROM cron.job WHERE active),
    'audit_fk',(SELECT count(*)::integer FROM pg_constraint WHERE contype='f'
      AND conrelid='public.journaux_audit'::regclass
      AND confrelid IN (SELECT oid FROM relations WHERE oid<>'public.journaux_audit'::regclass))
  ),
  'columns',(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relation',relation,'position',attnum,'name',attname,'type',type_name,
    'not_null',attnotnull,'default_md5',default_md5,
    'row_md5',md5(original_row::text)
  ) ORDER BY relation,attnum),'[]'::jsonb) FROM colonnes),
  'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relation',relation,'name',conname,'type',contype,
    'referenced_relation',referenced_relation,'definition_md5',definition_md5,
    'row_md5',md5(original_row::text)
  ) ORDER BY relation,conname),'[]'::jsonb) FROM contraintes),
  'functions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'schema',schema_name,'signature',signature,'body_md5',body_md5,
    'definition_md5',definition_md5,'acl_md5',acl_md5,'row_md5',md5(original_row)
  ) ORDER BY schema_name,signature),'[]'::jsonb) FROM fonctions),
  'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relation',relation,'name',tgname,'enabled',enabled,'function',function_signature,
    'definition_md5',definition_md5,'function_definition_md5',function_definition_md5,
    'row_md5',md5(original_row)
  ) ORDER BY relation,tgname),'[]'::jsonb) FROM declencheurs)
) AS d2_catalogue;
