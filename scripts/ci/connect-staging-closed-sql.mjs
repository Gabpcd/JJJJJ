// SQL transporté uniquement vers le projet staging exact par l'exécuteur.
// Aucun corps de fonction ni ligne métier ne sort : empreintes et booléens seuls.
const TABLES = ['missions','factures_honoraires','factures','litiges','paiements_soignant','paiements_mission',
  'paiements_escrow','stripe_transfers','stripe_payment_flow_claims','stripe_webhook_events',
  'stripe_refunds_queue','escrow_release_queue','externalisation_actions','invoice_audit_log','notifications','email_queue'];
const rows = `md5(concat_ws('|',${TABLES.map(t=>`(SELECT md5(COALESCE(jsonb_agg(j ORDER BY j::text)::text,'[]')) FROM (SELECT to_jsonb(t) j FROM public.${t} t) q)`).join(',')}))`;
const quiet = `(NOT EXISTS(SELECT 1 FROM cron.job WHERE active)
 AND NOT EXISTS(SELECT 1 FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending'))
 AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)
 AND NOT EXISTS(SELECT 1 FROM public.escrow_release_queue WHERE statut IN ('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE statut IN ('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.externalisation_actions WHERE statut='PROCESSING')
 AND NOT EXISTS(SELECT 1 FROM public.stripe_transfers WHERE statut IN ('EN_ATTENTE','CHARGE_REUSSI'))
 AND NOT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()
   AND backend_type='client backend' AND state IS DISTINCT FROM 'idle'))`;
const structural = `md5(jsonb_build_object(
 'routines',(SELECT COALESCE(jsonb_agg(jsonb_build_array(n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),
   pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl) ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),'[]')
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private','auth') AND p.prokind IN ('f','p')),
 'relations',(SELECT COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,c.relkind,pg_get_userbyid(c.relowner),c.relacl,c.relrowsecurity,c.relforcerowsecurity)
   ORDER BY n.nspname,c.relname),'[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private','auth') AND c.relkind IN ('r','p','v','m','S')),
 'views',(SELECT COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,pg_get_viewdef(c.oid,true)) ORDER BY n.nspname,c.relname),'[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private','auth') AND c.relkind IN ('v','m')),
 'columns',(SELECT COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attacl,pg_get_expr(d.adbin,d.adrelid))
   ORDER BY n.nspname,c.relname,a.attnum),'[]') FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE n.nspname IN ('public','private','auth') AND c.relkind IN ('r','p') AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid,true)) ORDER BY n.nspname,c.relname,k.conname),'[]')
   FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private','auth')),
 'indexes',(SELECT COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,pg_get_indexdef(i.indexrelid)) ORDER BY n.nspname,c.relname,pg_get_indexdef(i.indexrelid)),'[]')
   FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private','auth')),
 'triggers',(SELECT COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid,true)) ORDER BY n.nspname,c.relname,t.tgname),'[]')
   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private','auth') AND NOT t.tgisinternal),
 'policies',(SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.schemaname,p.tablename,p.policyname),'[]') FROM pg_policies p WHERE p.schemaname IN ('public','private','auth')),
 'inventory',(SELECT COALESCE(jsonb_agg(to_jsonb(i)-'recense_le' ORDER BY signature),'[]') FROM private.security_definer_inventory i)
 )::text)`;
const registry = `(SELECT md5(COALESCE(jsonb_agg(to_jsonb(m) ORDER BY version)::text,'[]')) FROM supabase_migrations.schema_migrations m)`;
const version = `(SELECT COALESCE(jsonb_agg(version ORDER BY version),'[]') FROM supabase_migrations.schema_migrations)`;
function catalogueSelect(after) {
  const gate=after?`((SELECT count(*) FROM private.stripe_connect_release_gate)=1
    AND EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
    AND NOT EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert))`:
    `(to_regclass('private.stripe_connect_release_gate') IS NULL AND to_regclass('private.stripe_connect_avant_transfert') IS NULL)`;
  const capacity=after?`(NOT EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities))`:
    `(to_regclass('private.stripe_connect_test_capacities') IS NULL)`;
  return `SELECT ${structural} AS catalogue,${registry} AS registry,${version} AS versions,
 ${rows} AS rows,${quiet} AS quiescent,${gate} AS gate_closed,${capacity} AS capacity_closed`;
}
export function catalogueSql(after) {
  return `BEGIN READ ONLY; SET LOCAL search_path=pg_catalog; SET LOCAL statement_timeout='20s'; SET LOCAL lock_timeout='3s'; SET LOCAL TIME ZONE 'UTC';\n${catalogueSelect(after)};\nROLLBACK;`;
}
const hex = (s,n) => typeof s==='string' && new RegExp(`^[a-f0-9]{${n}}$`).test(s);
export function transactionSql(local,contract,before,commit) {
  if(![contract.expectedBefore.catalogue,contract.expectedBefore.registry,contract.expectedAfter.catalogue,contract.expectedAfter.registry,before.rows].every(s=>hex(s,32))) throw new Error('SQL_PIN_REFUSED');
  if(typeof local.migration!=='string'||!/^([\s\S]*?)\bBEGIN;[\s\S]*\nCOMMIT;\s*$/.test(local.migration)
    || (local.migration.match(/^BEGIN;\s*$/gm)||[]).length!==1 || (local.migration.match(/^COMMIT;\s*$/gm)||[]).length!==1) throw new Error('MIGRATION_TRANSACTION_REFUSED');
  if(typeof local.capacity!=='string'||/^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im.test(local.capacity)) throw new Error('CAPACITY_FRAGMENT_REFUSED');
  if(typeof local.admission!=='string'||/^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im.test(local.admission)) throw new Error('ADMISSION_FRAGMENT_REFUSED');
  // Les fichiers ont été pincés par SHA256 avant ce raccord. Aucun SQL fourni par input.
  const body=local.migration.replace(/^BEGIN;\s*$/m,'').replace(/^COMMIT;\s*$/m,'');
  const delimiter='$jolene_migration_source$';if(local.migration.includes(delimiter))throw new Error('SQL_DELIMITER_COLLISION');
  const assertion=(after,pins)=>`SET LOCAL search_path=pg_catalog;
 DO $closed_check$ DECLARE v record; BEGIN
 SELECT * INTO v FROM (${catalogueSelect(after)}) snapshot;
 IF v.catalogue IS DISTINCT FROM '${pins.catalogue}' OR v.registry IS DISTINCT FROM '${pins.registry}'
   OR v.rows IS DISTINCT FROM '${before.rows}' OR v.quiescent IS DISTINCT FROM TRUE
   OR v.gate_closed IS DISTINCT FROM TRUE OR v.capacity_closed IS DISTINCT FROM TRUE THEN
   RAISE EXCEPTION 'CONNECT_STAGING_CATALOGUE_REFUSED'; END IF;
 END $closed_check$;`;
  return `BEGIN; SET LOCAL statement_timeout='90s'; SET LOCAL lock_timeout='3s'; SET LOCAL TIME ZONE 'UTC';
 -- Verrou CI commun + verrou transactionnel ; tout écrivain concurrent fait refuser le constat.
 SELECT pg_advisory_xact_lock(184731,1017);
 LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE NOWAIT;
 ${assertion(false,contract.expectedBefore)}
 ${body}
 ${local.capacity}
 ${local.admission}
 INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
 VALUES('20261001201055','reserver_remboursement_connect_avant_transfert',ARRAY[${delimiter}${local.migration}${delimiter}]);
 ${assertion(true,contract.expectedAfter)}
 ${commit?'COMMIT':'ROLLBACK'};`;
}
