// Pure SQL construction. The caller pins the complete render before transport.
// No function definition, row, secret or provider argument leaves these queries.
import {structuralJsonSql} from './connect-staging-closed-sql.mjs';

const TABLE='private.signature_sms_test_capacities';
const SENDER='public.fn_envoyer_otp_signature(uuid)';
const PRIVATE_LEDGER=['private.fn_reserver_envoi_sms_idempotent(text,text)',
 'private.fn_finaliser_envoi_sms_idempotent(text,text,text,text,text)'];
const WRAPPERS=['public.fn_reserver_envoi_sms_idempotent(text,text)',
 'public.fn_finaliser_envoi_sms_idempotent(text,text,text,text,text)'];
const NEW_ROUTINES=['private.fn_signature_sms_test_immutable()',
 'private.fn_signature_sms_test_telephone(text)','private.fn_signature_sms_test_scope(uuid,uuid)',
 'public.fn_admission_otp_signature_recette(uuid)',
 'public.fn_reserver_sms_signature_recette(text,text,text,uuid,uuid,uuid,text,text,text,text,text,text)'];
const TARGET_ROUTINES=[SENDER,...NEW_ROUTINES];
const INVENTORY=[SENDER,...NEW_ROUTINES.filter(s=>s.startsWith('public.'))].map(s=>s.replace(/^public\./,''));
const BUSINESS_TABLES=['auth.users','auth.sessions','auth.refresh_tokens','public.soignants','public.etablissements',
 'public.missions','public.mission_creneaux','public.candidatures','public.contrats_mission','public.signatures_contrats',
 'public.factures_honoraires','public.factures','public.litiges','public.paiements_soignant','public.paiements_mission',
 'public.paiements_escrow','public.stripe_transfers','public.stripe_payment_flow_claims','public.stripe_webhook_events',
 'public.stripe_refunds_queue','public.escrow_release_queue','public.externalisation_actions','public.invoice_audit_log',
 'public.notifications','public.email_queue','private.stripe_connect_release_gate','private.stripe_connect_test_capacities',
 'public.preferences_notifications','private.sms_dispatch_idempotency','public.sms_envoyes','public.journaux_audit',
 'public.signature_rate_limit_ip','cron.job','cron.job_run_details','net.http_request_queue'];
const INVARIANT_KEYS=['structure','routines','inventory','registry','rows'];
const META_KEYS=['signature','body_md5','owner','security_definer','config','acl','language','volatility','returns_set','strict'];
const literal=value=>"'"+String(value).replaceAll("'","''")+"'";
const jsonLiteral=value=>literal(JSON.stringify(value))+'::jsonb';
const sqlArray=values=>'ARRAY['+values.map(literal).join(',')+']::text[]';
const same=(a,b)=>JSON.stringify([...a].sort())===JSON.stringify([...b].sort());
const fail=()=>{throw Error('SMS_INSTALL_SQL_CONTRACT_REFUSED');};
const hex=value=>typeof value==='string'&&/^[a-f0-9]{32}$/.test(value);

function validateMetadata(row,definitionRequired){
 if(!row||typeof row!=='object'||Array.isArray(row))fail();
 const keys=[...META_KEYS,...('definition_md5' in row?['definition_md5']:[])];
 if(!same(Object.keys(row),keys)||!hex(row.body_md5)
   ||(definitionRequired&&!hex(row.definition_md5))
   ||('definition_md5' in row&&!hex(row.definition_md5))
   ||typeof row.signature!=='string'||row.owner!=='postgres'
   ||typeof row.security_definer!=='boolean'||typeof row.returns_set!=='boolean'||typeof row.strict!=='boolean'
   ||!['plpgsql','sql'].includes(row.language)||!['i','s','v'].includes(row.volatility)
   ||![row.config,row.acl].every(v=>v===null||(Array.isArray(v)&&v.every(x=>typeof x==='string'))))fail();
}
function validateContract(contract){
 if(!contract||!Array.isArray(contract.beforeRoutines)||!Array.isArray(contract.afterRoutines)
   ||!same(contract.beforeRoutines.map(r=>r.signature),[SENDER,...PRIVATE_LEDGER,...WRAPPERS])
   ||!same(contract.afterRoutines.map(r=>r.signature),[...TARGET_ROUTINES,...WRAPPERS]))fail();
 for(const row of contract.beforeRoutines)validateMetadata(row,true);
 for(const row of contract.afterRoutines)validateMetadata(row,WRAPPERS.includes(row.signature));
 for(const signature of WRAPPERS){
  const before=contract.beforeRoutines.find(r=>r.signature===signature);
  const after=contract.afterRoutines.find(r=>r.signature===signature);
  if(Object.keys(before).some(k=>JSON.stringify(before[k])!==JSON.stringify(after[k])))fail();
 }
}

// A qualified identity without argument names is stable at search_path=pg_catalog.
// Filtering text avoids NOT IN(NULL) when the five new routines do not exist yet.
const identity="n.nspname||'.'||p.proname||'('||replace(oidvectortypes(p.proargtypes),', ',',')||')'";
const metadata=`jsonb_build_object('signature',${identity},'body_md5',md5(p.prosrc),
 'definition_md5',md5(pg_get_functiondef(p.oid)),'owner',pg_get_userbyid(p.proowner),
 'security_definer',p.prosecdef,'config',p.proconfig,
 'acl',(SELECT jsonb_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x),
 'language',l.lanname,'volatility',p.provolatile,'returns_set',p.proretset,'strict',p.proisstrict)`;
const procFrom='FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang';
const routinesJson=signatures=>`(SELECT COALESCE(jsonb_agg(${metadata} ORDER BY ${identity}),'[]'::jsonb)
 ${procFrom} WHERE p.prokind IN ('f','p') AND ${identity}=ANY(${sqlArray(signatures)}))`;
const routineInvariant=`(SELECT md5(COALESCE(jsonb_agg(jsonb_build_array(${metadata},pg_get_functiondef(p.oid))
 ORDER BY ${identity})::text,'[]')) ${procFrom}
 WHERE n.nspname IN ('public','private','auth') AND p.prokind IN ('f','p')
 AND NOT (${identity}=ANY(${sqlArray(TARGET_ROUTINES)})))`;
const inventoryInvariant=`(SELECT md5(COALESCE(jsonb_agg(to_jsonb(i) ORDER BY signature)::text,'[]'))
 FROM private.security_definer_inventory i WHERE NOT (signature=ANY(${sqlArray(INVENTORY)})))`;
const registry=`(SELECT md5(COALESCE(jsonb_agg(to_jsonb(m) ORDER BY version)::text,'[]'))
 FROM supabase_migrations.schema_migrations m)`;
const rows=`md5(concat_ws('|',${BUSINESS_TABLES.map(t=>`(SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,'[]')) FROM ${t} t)`).join(',')}))`;
const quiet=`(NOT EXISTS(SELECT 1 FROM cron.job WHERE active)
 AND NOT EXISTS(SELECT 1 FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending'))
 AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)
 AND NOT EXISTS(SELECT 1 FROM public.escrow_release_queue WHERE statut IN ('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE statut IN ('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.externalisation_actions WHERE statut='PROCESSING')
 AND NOT EXISTS(SELECT 1 FROM public.stripe_transfers WHERE statut IN ('EN_ATTENTE','CHARGE_REUSSI'))
 AND NOT EXISTS(SELECT 1 FROM private.sms_dispatch_idempotency WHERE statut IN ('EN_COURS','INDETERMINE'))
 AND NOT EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities WHERE enabled)
 AND NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE enabled)
 AND NOT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()
   AND backend_type='client backend' AND state IS DISTINCT FROM 'idle'))`;
const absent=`(to_regclass('${TABLE}') IS NULL AND to_regtype('${TABLE}') IS NULL
 AND NOT EXISTS(SELECT 1 ${procFrom} WHERE ${identity}=ANY(${sqlArray(NEW_ROUTINES)})))`;

// Reuse the existing structural catalogue, removing only this exact relation in
// each category. Overloads, other private relations and all policies stay covered.
function structureProjection(target){
 const targetRelation=`CASE WHEN e.key='policies' THEN
  a.item->>'schemaname'='private' AND a.item->>'tablename'='signature_sms_test_capacities'
  ELSE a.item->>0='private' AND a.item->>1='signature_sms_test_capacities' END`;
 return `(SELECT COALESCE(jsonb_object_agg(e.key,(
  SELECT COALESCE(jsonb_agg(a.item ORDER BY a.ordinal),'[]'::jsonb)
  FROM jsonb_array_elements(COALESCE(NULLIF(e.value,'null'::jsonb),'[]'::jsonb)) WITH ORDINALITY a(item,ordinal)
  WHERE ${target?'':'NOT '}(${targetRelation})
 ) ORDER BY e.key),'{}'::jsonb) FROM jsonb_each(s.value-'routines'-'inventory') e)`;
}

const columns=[['id','uuid',true],['project_ref','text',true],['run_id','text',true],['source_sha','text',true],
 ['manifest_sha256','text',true],['enabled','boolean',true],['installed_at','timestamp with time zone',true],
 ['expires_at','timestamp with time zone',true],['revoked_at','timestamp with time zone',false],['mission_id','uuid',true],
 ['contrat_id','uuid',true],['document_sha256','text',true],['soignant_id','uuid',true],['etablissement_id','uuid',true],
 ['soignant_phone','text',true],['etablissement_phone','text',true],['twilio_account_sid','text',true],['sender_phone','text',true],
 ['max_attempts_per_actor','smallint',true],['soignant_attempts','smallint',true],['etablissement_attempts','smallint',true]];
const indexes=['signature_sms_test_capacities_pkey','signature_sms_test_capacities_run_id_key',
 'signature_sms_test_capacities_mission_id_key','signature_sms_test_capacities_contrat_id_key','signature_sms_test_one_active_run'].sort();
const closed=`(NOT EXISTS(SELECT 1 FROM ${TABLE})
 AND EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='private' AND c.relname='signature_sms_test_capacities'
   AND c.relkind='r' AND c.relpersistence='p' AND c.relowner='postgres'::regrole
   AND c.relrowsecurity AND NOT c.relforcerowsecurity
   AND NOT EXISTS(SELECT 1 FROM aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
     WHERE a.grantee<>c.relowner OR a.grantor<>c.relowner))
 AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='${TABLE}'::regclass)
 AND NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='${TABLE}'::regclass AND attnum>0 AND (attisdropped OR attacl IS NOT NULL))
 AND NOT EXISTS(SELECT 1 FROM (VALUES ('anon'),('authenticated'),('service_role')) r(name)
   WHERE has_table_privilege(r.name,'${TABLE}','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))
 AND (SELECT jsonb_agg(jsonb_build_array(attname,format_type(atttypid,atttypmod),attnotnull) ORDER BY attnum)
   FROM pg_attribute WHERE attrelid='${TABLE}'::regclass AND attnum>0 AND NOT attisdropped)=${jsonLiteral(columns)}
 AND (SELECT jsonb_agg(i.relname ORDER BY i.relname) FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
   WHERE x.indrelid='${TABLE}'::regclass)=${jsonLiteral(indexes)}
 AND NOT EXISTS(SELECT 1 FROM pg_index WHERE indrelid='${TABLE}'::regclass AND (NOT indisvalid OR NOT indisready))
 AND (SELECT count(*) FROM pg_trigger WHERE tgrelid='${TABLE}'::regclass AND NOT tgisinternal)=1
 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='${TABLE}'::regclass AND NOT tgisinternal
   AND tgname='signature_sms_test_immutable' AND tgenabled='O' AND tgtype=19
   AND tgfoid='private.fn_signature_sms_test_immutable()'::regprocedure)
 AND (SELECT jsonb_object_agg(kind,total) FROM (SELECT contype::text kind,count(*) total FROM pg_constraint
   WHERE conrelid='${TABLE}'::regclass GROUP BY contype) counts)='{"c":15,"f":4,"p":1,"u":3}'::jsonb
 AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='${TABLE}'::regclass AND NOT convalidated)
 AND (SELECT count(*) FROM private.security_definer_inventory WHERE signature=ANY(${sqlArray(INVENTORY)}))=3
 AND NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p
   ON p.oid=to_regprocedure('public.'||i.signature)
   WHERE i.signature=ANY(${sqlArray(INVENTORY)}) AND (
     i.definition_md5 IS DISTINCT FROM md5(p.prosrc)
     OR i.justification IS DISTINCT FROM 'Admission signature OTP staging bornee ; compte TEST preserve, allocation fermee.'
     OR i.categorie IS DISTINCT FROM CASE WHEN i.signature LIKE 'fn_reserver_sms_signature_recette(%'
       THEN 'SERVICE_ONLY_REVOQUE' ELSE 'RPC_UTILISATEUR_AUTH_INTERNE' END)))`;

function snapshotSelect(contract,after){
 const phase=after?contract.afterRoutines:contract.beforeRoutines;
 const targetInventory=`(SELECT COALESCE(jsonb_agg(${after?"to_jsonb(i)-'recense_le'":'to_jsonb(i)'} ORDER BY signature),'[]'::jsonb)
 FROM private.security_definer_inventory i WHERE signature=ANY(${sqlArray(INVENTORY)}))`;
 return `WITH sms_catalogue AS (SELECT ${structuralJsonSql} AS value)
 SELECT jsonb_build_object('quiet',${quiet},'absent',${absent},'closed',${after?closed:'false'},
 'routines',${routinesJson(phase.map(r=>r.signature))},
 'invariant',jsonb_build_object('structure',md5((${structureProjection(false)})::text),
   'routines',${routineInvariant},'inventory',${inventoryInvariant},'registry',${registry},'rows',${rows}),
 'targets',md5((jsonb_build_object('structure',${structureProjection(true)},
   'routines',${routinesJson(TARGET_ROUTINES)},'inventory',${targetInventory}))::text)) AS snapshot
 FROM sms_catalogue s`;
}

export function snapshotSql(contract,after=false){
 validateContract(contract);if(typeof after!=='boolean')fail();
 return `BEGIN READ ONLY; SET LOCAL search_path=pg_catalog; SET LOCAL row_security=off; SET LOCAL TIME ZONE 'UTC'; SET LOCAL standard_conforming_strings=on;
 SET LOCAL statement_timeout='30s'; SET LOCAL lock_timeout='3s';
 DO $sms_install_reader$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR current_setting('transaction_read_only')<>'on' OR current_setting('row_security')<>'off'
   THEN RAISE EXCEPTION 'SMS_INSTALL_READ_ONLY_CONTEXT'; END IF;
 END; $sms_install_reader$;
 ${snapshotSelect(contract,after)};
 ROLLBACK;`;
}
function routineAssertions(contract,after){
 const expected=after?contract.afterRoutines:contract.beforeRoutines;
 return `IF jsonb_array_length(v->'routines')<>${expected.length} THEN RAISE EXCEPTION 'SMS_INSTALL_ROUTINE_SCOPE'; END IF;
 ${expected.map(row=>`IF (SELECT ${'definition_md5' in row?'r':"r-'definition_md5'"} FROM jsonb_array_elements(v->'routines') r
   WHERE r->>'signature'=${literal(row.signature)}) IS DISTINCT FROM ${jsonLiteral(row)}
   THEN RAISE EXCEPTION 'SMS_INSTALL_ROUTINE_METADATA'; END IF;`).join('\n')}`;
}
function validateBefore(contract,before){
 if(!before||!same(Object.keys(before),['quiet','absent','closed','routines','invariant','targets'])
   ||before.quiet!==true||before.absent!==true||before.closed!==false||!hex(before.targets)
   ||!before.invariant||!same(Object.keys(before.invariant),INVARIANT_KEYS)
   ||!Object.values(before.invariant).every(hex)||!Array.isArray(before.routines)
   ||!same(before.routines.map(r=>r.signature),contract.beforeRoutines.map(r=>r.signature)))fail();
 for(const row of before.routines){
  validateMetadata(row,true);
  const expected=contract.beforeRoutines.find(r=>r.signature===row.signature);
  if(Object.keys(expected).some(k=>JSON.stringify(expected[k])!==JSON.stringify(row[k])))fail();
 }
}
export function transactionSql(contract,rendered,before,commit=false){
 validateContract(contract);validateBefore(contract,before);
 if(typeof commit!=='boolean'||typeof rendered!=='string'||!rendered.trim()
   ||/^\s*(?:BEGIN|COMMIT|ROLLBACK)\s*;/im.test(rendered)
   ||/\$sms_install_(?:before|after)\$/.test(rendered))throw Error('SMS_INSTALL_RENDER_FRAGMENT_REFUSED');
 return `BEGIN; SET LOCAL search_path=pg_catalog; SET LOCAL row_security=off; SET LOCAL TIME ZONE 'UTC'; SET LOCAL standard_conforming_strings=on;
 SET LOCAL statement_timeout='90s'; SET LOCAL lock_timeout='3s';
 DO $sms_install_operator$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR current_setting('transaction_read_only')<>'off' OR current_setting('row_security')<>'off'
   THEN RAISE EXCEPTION 'SMS_INSTALL_OPERATOR_CONTEXT'; END IF;
 END; $sms_install_operator$;
 SELECT pg_advisory_xact_lock(184731,1017);
 LOCK TABLE supabase_migrations.schema_migrations,private.security_definer_inventory IN SHARE ROW EXCLUSIVE MODE NOWAIT;
 LOCK TABLE ${BUSINESS_TABLES.join(',')} IN SHARE MODE NOWAIT;
 CREATE TEMP TABLE sms_install_before ON COMMIT DROP AS ${snapshotSelect(contract,false)};
 DO $sms_install_before$ DECLARE v jsonb; BEGIN
 SELECT snapshot INTO STRICT v FROM pg_temp.sms_install_before;
 IF v IS DISTINCT FROM ${jsonLiteral(before)} THEN RAISE EXCEPTION 'SMS_INSTALL_BEFORE_CHANGED'; END IF;
 ${routineAssertions(contract,false)}
 END; $sms_install_before$;
 ${rendered}
 SET LOCAL search_path=pg_catalog;
 DO $sms_install_after$ DECLARE v jsonb; BEGIN
 SELECT snapshot INTO STRICT v FROM (${snapshotSelect(contract,true)}) after_snapshot;
 IF v->'quiet' IS DISTINCT FROM 'true'::jsonb OR v->'absent' IS DISTINCT FROM 'false'::jsonb
   OR v->'closed' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'SMS_INSTALL_NOT_CLOSED'; END IF;
 IF v->'invariant' IS DISTINCT FROM (SELECT snapshot->'invariant' FROM pg_temp.sms_install_before)
   THEN RAISE EXCEPTION 'SMS_INSTALL_UNRELATED_CHANGE'; END IF;
 ${routineAssertions(contract,true)}
 END; $sms_install_after$;
 ${snapshotSelect(contract,true)};
 ${commit?'COMMIT':'ROLLBACK'};`;
}
