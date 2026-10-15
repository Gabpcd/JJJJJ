// SQL-only recovery of the reviewed render. cron.job remains in every snapshot
// and quiet predicate. Its SELECT-only managed ACL permits ACCESS SHARE, which
// observes this relation but does not serialize concurrent cron.job writers.
import {transactionSql} from './install-sms-staging-closed-sql.mjs';

const TABLES=Object.freeze(['auth.users','auth.sessions','auth.refresh_tokens','public.soignants','public.etablissements',
 'public.missions','public.mission_creneaux','public.candidatures','public.contrats_mission','public.signatures_contrats',
 'public.factures_honoraires','public.factures','public.litiges','public.paiements_soignant','public.paiements_mission',
 'public.paiements_escrow','public.stripe_transfers','public.stripe_payment_flow_claims','public.stripe_webhook_events',
 'public.stripe_refunds_queue','public.escrow_release_queue','public.externalisation_actions','public.invoice_audit_log',
 'public.notifications','public.email_queue','private.stripe_connect_release_gate','private.stripe_connect_test_capacities',
 'public.preferences_notifications','private.sms_dispatch_idempotency','public.sms_envoyes','public.journaux_audit',
 'public.signature_rate_limit_ip','cron.job','cron.job_run_details','net.http_request_queue']);

export function transactionSqlOnly(contract,rendered,before,commit=false){
 const original=transactionSql(contract,rendered,before,commit);
 const line=` LOCK TABLE ${TABLES.join(',')} IN SHARE MODE NOWAIT;`;
 if(original.split(line).length!==2)throw Error('SMS_RESUME_LOCK_SOURCE_REFUSED');
 const replacement=` LOCK TABLE ${TABLES.filter(t=>t!=='cron.job').join(',')} IN SHARE MODE NOWAIT;
 -- cron.job is observed before/after; ACCESS SHARE does not block its writers.
 LOCK TABLE cron.job IN ACCESS SHARE MODE NOWAIT;`;
 return original.replace(line,replacement);
}
