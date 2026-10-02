import { catalogueSqlF1 } from './f1-cloud-sql.mjs';

export const literal = value => `'${String(value).replaceAll("'", "''")}'`;
// Catalogue read only; neither the F1 executor nor its readiness is invoked.
export function preflightSql() {
  return `SELECT catalogue || jsonb_build_object(
    'gateClosed',(SELECT count(*)=1 AND bool_and(protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE) FROM private.stripe_connect_release_gate),
    'capacitiesEmpty',NOT EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities),
    'operationsEmpty',NOT EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert)
  ) AS receipt FROM (${catalogueSqlF1().replace(/;\s*$/, '')}) c;`;
}
export function guardSql(expected) {
  return `DO $fixture_guard$ DECLARE c jsonb; BEGIN
    SELECT receipt INTO c FROM (${preflightSql().replace(/;\s*$/, '')}) preflight;
    IF c IS DISTINCT FROM ${literal(JSON.stringify(expected))}::jsonb THEN RAISE EXCEPTION 'CONNECT_FIXTURE_PREFLIGHT_DRIFT'; END IF;
  END $fixture_guard$;`;
}
export function transactionSql(manifest, expected, body) {
  return `BEGIN; SET LOCAL statement_timeout='45s'; SET LOCAL lock_timeout='3s'; SET LOCAL TIME ZONE 'UTC';
  SELECT set_config('jolene.connect_test_fixture_manifest',${literal(JSON.stringify(manifest.sql))},true);
  ${guardSql(expected)}
  ${body}
  DO $fixture_queue$ BEGIN IF EXISTS(SELECT 1 FROM net.http_request_queue) THEN RAISE EXCEPTION 'CONNECT_FIXTURE_HTTP_QUEUE'; END IF; END $fixture_queue$;
  COMMIT;`;
}
export function snapshotSql(v) {
  const s=literal(v.actors.soignant.id),e=literal(v.actors.etablissement.id),a=literal(v.sqlActors.admin.id),m=literal(v.ids.mission);
  return `SELECT jsonb_build_object(
    'auth',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'email',email,'email_confirmed_at',email_confirmed_at,'deleted_at',deleted_at,'banned_until',banned_until,'app_metadata',raw_app_meta_data) ORDER BY id),'[]') FROM auth.users WHERE id IN(${s}::uuid,${e}::uuid,${a}::uuid) OR email IN(${literal(v.actors.soignant.email)},${literal(v.actors.etablissement.email)},${literal(v.sqlActors.admin.email)})),
    'soignants',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'email',email,'test',est_compte_test,'source',source_acquisition,'account',stripe_account_id,'sms',sms_actif,'smsAlerts',sms_alertes_actives,'defacto',defacto_opt_in)),'[]') FROM public.soignants WHERE id IN(${s}::uuid,${e}::uuid,${a}::uuid) OR email=${literal(v.actors.soignant.email)} OR siret_liberal=${literal(v.identifiants.siretSoignant)}),
    'etablissements',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'email',email_contact,'name',nom,'test',est_compte_test,'source',source_acquisition,'customer',stripe_customer_id,'sms',sms_actif,'chorus',chorus_pro_actif)),'[]') FROM public.etablissements WHERE id IN(${s}::uuid,${e}::uuid,${a}::uuid) OR email_contact=${literal(v.actors.etablissement.email)} OR siret=${literal(v.identifiants.siretEtablissement)}),
    'mission',(SELECT jsonb_build_object('id',id,'soignant',soignant_assigne_id,'etablissement',etablissement_id,'status',statut,'label',intitule,'hours',duree_heures,'effective',duree_heures_effective,'net',net_a_payer,'commission',montant_commission_ht,'startsOn',debut_le::date,'endsOn',fin_le::date) FROM public.missions WHERE id=${m}::uuid),
    'onboarding',(SELECT coalesce(jsonb_agg(jsonb_build_object('account',stripe_account_id,'soignant',soignant_id,'status',statut,'complete',onboarding_complete,'charges',charges_enabled,'payouts',payouts_enabled,'details',details_submitted)),'[]') FROM public.stripe_connect_onboarding WHERE soignant_id=${s}::uuid),
    'preferencesClosed',(SELECT count(*)=2 AND bool_and(NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app) FROM public.preferences_notifications WHERE utilisateur_id IN(${s}::uuid,${e}::uuid)),
    'activeAdmin',(SELECT count(*) FROM public.equipe_admin WHERE user_id=${a}::uuid AND actif),
    'invoices',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'soignant',f.soignant_id,'etablissement',f.etablissement_id,'status',f.statut,'kind',f.type_document,'nature',f.nature_correction,'total',f.montant_ttc,'paid',f.date_paiement IS NOT NULL OR f.stripe_payment_intent_id IS NOT NULL,'pdf',f.pdf_s3_key,'xml',f.facturx_xml_url,'versions',(SELECT count(*) FROM public.factures_honoraires_documents d WHERE d.facture_honoraire_id=f.id))),'[]') FROM public.factures_honoraires f WHERE f.mission_id=${m}::uuid),
    'commissions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'honoraire',facture_honoraire_id,'status',statut,'kind',type_document,'total',montant_ttc,'linked',stripe_invoice_id IS NOT NULL OR stripe_payment_intent_id IS NOT NULL OR stripe_hosted_url IS NOT NULL OR chorus_pro_id IS NOT NULL OR date_paiement IS NOT NULL OR virement_confirme_le IS NOT NULL)),'[]') FROM public.factures WHERE mission_id=${m}::uuid),
    'payments',(SELECT count(*) FROM public.paiements_soignant WHERE mission_id=${m}::uuid)+(SELECT count(*) FROM public.paiements_mission WHERE mission_id=${m}::uuid)+(SELECT count(*) FROM public.paiements_escrow WHERE mission_id=${m}::uuid)+(SELECT count(*) FROM public.stripe_transfers WHERE mission_id=${m}::uuid),
    'paymentClaims',(SELECT count(*) FROM public.stripe_payment_flow_claims WHERE resource_key='MISSION:'||${m} OR resource_key IN(SELECT 'FACTURE:'||id::text FROM public.factures WHERE mission_id=${m}::uuid)),
    'emailQueue',(SELECT count(*) FROM public.email_queue WHERE destinataire_id IN(${s}::uuid,${e}::uuid)),
    'emailRetries',(SELECT count(*) FROM public.invoice_audit_log WHERE invoice_id IN(SELECT id FROM public.factures_honoraires WHERE mission_id=${m}::uuid) AND action='EMAIL_EMISSION_A_REESSAYER'),
    'emailSkips',(SELECT count(*) FROM public.journaux_audit WHERE id_ressource IN(${s}::uuid,${e}::uuid) AND action='NOTIFICATION_SKIPPED' AND details->>'raison'='test_account' AND details->>'fonction' IS NULL)
  ) AS receipt;`;
}
export function linkSql(v, customer, account) {
  const s=literal(v.actors.soignant.id), e=literal(v.actors.etablissement.id);
  return `DO $fixture_link$ DECLARE n integer; BEGIN
    IF EXISTS(SELECT 1 FROM public.etablissements WHERE stripe_customer_id=${literal(customer.id)})
      OR EXISTS(SELECT 1 FROM public.soignants WHERE stripe_account_id=${literal(account.id)})
      OR EXISTS(SELECT 1 FROM public.stripe_connect_onboarding WHERE stripe_account_id=${literal(account.id)} OR soignant_id=${s}::uuid)
    THEN RAISE EXCEPTION 'CONNECT_FIXTURE_LINK_EXISTS'; END IF;
    UPDATE public.etablissements SET stripe_customer_id=${literal(customer.id)} WHERE id=${e}::uuid AND est_compte_test IS TRUE AND stripe_customer_id IS NULL AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE';
    GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'CONNECT_FIXTURE_CUSTOMER_CAS'; END IF;
    UPDATE public.soignants SET stripe_account_id=${literal(account.id)} WHERE id=${s}::uuid AND est_compte_test IS TRUE AND stripe_account_id IS NULL AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE';
    GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'CONNECT_FIXTURE_ACCOUNT_CAS'; END IF;
    INSERT INTO public.stripe_connect_onboarding(soignant_id,stripe_account_id,statut,onboarding_complete,charges_enabled,payouts_enabled,details_submitted)
      VALUES(${s}::uuid,${literal(account.id)},'EN_COURS',false,false,false,false);
  END $fixture_link$;
  SELECT jsonb_build_object('linked',true) AS receipt;`;
}
