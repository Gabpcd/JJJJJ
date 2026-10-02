import { refuse, STAGING } from './f1-cloud-core.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export const literalF1 = value => `'${String(value).replaceAll("'", "''")}'`;
export function sqlManifestF1(m) {
  const v = m?.sql;
  const ids = [v?.actors?.soignant?.id, v?.actors?.etablissement?.id, v?.sqlActors?.admin?.id,
    v?.ids?.mission, v?.ids?.equipeAdmin, v?.ids?.litige, v?.ids?.presence];
  if (v?.schemaVersion !== 1 || v.projectRef !== STAGING || !/^f1-ci-[1-9][0-9]*-[1-9][0-9]*$/.test(v.runId ?? '')
    || !/^[a-f0-9]{40}$/.test(v.sourceSha ?? '') || v.ownerMarker !== `${v.runId}:${v.sourceSha}`
    || ids.some(id => !UUID.test(id ?? '')) || new Set(ids).size !== 7
    || !/^\d{14}$/.test(v.identifiants?.siretSoignant ?? '') || !/^\d{14}$/.test(v.identifiants?.siretEtablissement ?? '')
    || v.identifiants.siretSoignant === v.identifiants.siretEtablissement) refuse('F1_SQL_MANIFEST');
  for (const actor of [v.actors.soignant, v.actors.etablissement, v.sqlActors.admin]) {
    if (!/^f1-[a-f0-9-]+@example\.invalid$/.test(actor.email ?? '')) refuse('F1_SQL_MANIFEST');
  }
  if (v.documents?.original?.id != null && !UUID.test(v.documents.original.id)) refuse('F1_SQL_MANIFEST');
  // Do not serialize passwords/session fields, even if the private object has any.
  return { schemaVersion: 1, projectRef: STAGING, runId: v.runId, sourceSha: v.sourceSha, ownerMarker: v.ownerMarker,
    actors: { soignant: { id: ids[0], email: v.actors.soignant.email }, etablissement: { id: ids[1], email: v.actors.etablissement.email } },
    sqlActors: { admin: { id: ids[2], email: v.sqlActors.admin.email } }, ids: { mission: ids[3], equipeAdmin: ids[4], litige: ids[5], presence: ids[6] },
    identifiants: { siretSoignant: v.identifiants.siretSoignant, siretEtablissement: v.identifiants.siretEtablissement },
    documents: v.documents?.original?.id ? { original: { id: v.documents.original.id } } : {} };
}

/** Each transaction repeats the frozen catalogue check, including new triggers.
 * expected.catalogueDigest covers the structural SELECT returned by the reviewed
 * preflight; it is never learned automatically from the current remote state. */
export function catalogueSqlF1() {
  return `SELECT jsonb_build_object(
    'routines', (SELECT md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,''),E'\n' ORDER BY p.oid::regprocedure::text))
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')),
    'triggers', (SELECT md5(string_agg(t.tgrelid::regclass::text||':'||pg_get_triggerdef(t.oid)||':'||t.tgenabled::text,E'\n' ORDER BY t.tgrelid::regclass::text,t.tgname))
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth','storage')),
    'columns', (SELECT md5(string_agg(n.nspname||'.'||c.relname||'.'||a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),''),E'\n' ORDER BY n.nspname,c.relname,a.attnum))
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attnum>0 AND NOT a.attisdropped AND n.nspname IN ('public','private','auth','storage')),
    'commissionHelper',md5(pg_get_functiondef('public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure)),
    'queuedRequests',(SELECT count(*)::int FROM net.http_request_queue),
    'activeCrons',(SELECT count(*)::int FROM cron.job WHERE active),
    'runningCrons',(SELECT count(*)::int FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending')),
    'generationUrlAbsent',NOT EXISTS(SELECT 1 FROM public.parametres_litiges WHERE cle='generate_invoice_url' AND coalesce(length(valeur),0)>0),
    'supportStagingExact',coalesce((SELECT nullif(btrim(decrypted_secret),'')='https://mejpriaetwgtcstbgfid.supabase.co' FROM vault.decrypted_secrets WHERE name='supabase_url' LIMIT 1),false)
  ) AS catalogue;`;
}
export function transactionF1(kind, manifest, template, expected) {
  if (!['prepare', 'correction'].includes(kind) || !expected || !['routines', 'triggers', 'columns'].every(k => /^[a-f0-9]{32}$/.test(expected[k] ?? ''))) refuse('F1_SQL_CONTRACT');
  const v = sqlManifestF1(manifest);
  if (kind === 'correction' && !v.documents.original) refuse('F1_SQL_ORIGINAL_REQUIRED');
  // template bytes are checked against fixed SHA256 by the loader, not caller SQL.
  const catalogue = catalogueSqlF1().replace(/;\s*$/, '');
  const supportReceipt = kind === 'correction' ? `
DO $f1_support$ DECLARE request_ids bigint[]; BEGIN
  SELECT array_agg(id ORDER BY id) INTO request_ids FROM net.http_request_queue
  WHERE url='https://mejpriaetwgtcstbgfid.supabase.co/functions/v1/notify-support'
    AND convert_from(body,'UTF8')::jsonb=${literalF1(JSON.stringify({
      sujet: 'Nouveau litige ouvert (DESACCORD_MONTANT_FACTURE)',
      corps: `RECETTE SYNTHETIQUE ${v.ownerMarker} : correction du taux de premiere periode`,
      source: 'Litige', lien: '/admin/litiges', mission_id: v.ids.mission,
    }))}::jsonb;
  IF (SELECT count(*) FROM net.http_request_queue)<>1 OR cardinality(request_ids) IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'F1_SUPPORT_REQUEST_NOT_PROVEN'; END IF;
  PERFORM set_config('jolene.recette_f1_receipt',
    (current_setting('jolene.recette_f1_receipt')::jsonb || jsonb_build_object('supportRequestId',request_ids[1]))::text,true);
END $f1_support$;
SELECT current_setting('jolene.recette_f1_receipt')::jsonb AS receipt;` : `DO $f1_no_queue$ BEGIN IF EXISTS(SELECT 1 FROM net.http_request_queue) THEN RAISE EXCEPTION 'F1_UNEXPECTED_HTTP_QUEUE'; END IF; END $f1_no_queue$;`;
  return `BEGIN; SET LOCAL statement_timeout='45s'; SET LOCAL lock_timeout='3s';
SET LOCAL TIME ZONE 'UTC';
SELECT set_config('jolene.recette_f1_manifest',${literalF1(JSON.stringify(v))},true);
DO $f1_guard$ DECLARE c jsonb; BEGIN
  SELECT catalogue INTO c FROM (${catalogue}) AS inventory;
  IF c->>'routines' IS DISTINCT FROM ${literalF1(expected.routines)} OR c->>'triggers' IS DISTINCT FROM ${literalF1(expected.triggers)}
    OR c->>'columns' IS DISTINCT FROM ${literalF1(expected.columns)} OR c->'activeCrons' IS DISTINCT FROM '0'::jsonb
    OR c->>'commissionHelper' IS DISTINCT FROM 'c793ac81eaef0fe18fb5920c9264c675'
    OR c->'queuedRequests' IS DISTINCT FROM '0'::jsonb
    OR c->'runningCrons' IS DISTINCT FROM '0'::jsonb OR c->'generationUrlAbsent' IS DISTINCT FROM 'true'::jsonb
    OR c->'supportStagingExact' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'F1_CATALOGUE_DRIFT'; END IF;
END $f1_guard$;
${template}
${supportReceipt}
COMMIT;`;
}

export function supportResponseSqlF1(requestId) {
  if (!Number.isSafeInteger(requestId) || requestId < 1) refuse('F1_SUPPORT_REQUEST_ID');
  return `SELECT jsonb_build_object('count',count(*)::int,'finished',coalesce(bool_and(status_code=200 AND timed_out IS FALSE AND error_msg IS NULL),false),
    'testSkip',coalesce(bool_and(content::jsonb @> '{"success":true,"skipped":true,"reason":"test_account"}'::jsonb),false)) AS receipt
    FROM net._http_response WHERE id=${requestId};`;
}

/** Read only: exact cohort, no free SQL, no business content outside the fixture. */
export function reconcileSqlF1(manifest) {
  const v = sqlManifestF1(manifest), s = literalF1(v.actors.soignant.id), e = literalF1(v.actors.etablissement.id),
    a = literalF1(v.sqlActors.admin.id), m = literalF1(v.ids.mission), team = literalF1(v.ids.equipeAdmin), marker = literalF1(v.ownerMarker);
  return `WITH f AS (SELECT * FROM public.factures_honoraires WHERE mission_id=${m}::uuid),
  commissions AS (SELECT * FROM public.factures WHERE mission_id=${m}::uuid OR facture_honoraire_id IN(SELECT id FROM f)),
  versions AS (SELECT d.* FROM public.factures_honoraires_documents d JOIN f ON f.id=d.facture_honoraire_id)
SELECT jsonb_build_object(
  'actors',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'owned',raw_app_meta_data->>'jolene_f1_owner'=${marker}
    AND raw_app_meta_data->'est_compte_test'='true'::jsonb AND deleted_at IS NULL,'banned',banned_until>now(),'confirmed',email_confirmed_at IS NOT NULL) ORDER BY id),'[]'::jsonb)
    FROM auth.users WHERE id IN(${s}::uuid,${e}::uuid,${a}::uuid)),
  'sessions',(SELECT count(*)::int FROM auth.sessions WHERE user_id IN(${s}::uuid,${e}::uuid,${a}::uuid)),
  'adminActive',(SELECT count(*)::int FROM public.equipe_admin WHERE id=${team}::uuid AND user_id=${a}::uuid AND actif),
  'mission',(SELECT jsonb_build_object('id',id,'soignant',soignant_assigne_id,'etablissement',etablissement_id,'status',statut,
    'hours',duree_heures,'effectiveHours',duree_heures_effective,'rate',taux_horaire_base,'net',net_a_payer,'commission',montant_commission_ht)
    FROM public.missions WHERE id=${m}::uuid),
  'documents',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'number',f.numero_facture,'status',f.statut,'kind',f.type_document,
    'nature',f.nature_correction,'predecessor',f.facture_precedente_id,'soignant',f.soignant_id,'etablissement',f.etablissement_id,
    'emittedOn',f.date_emission,'dueOn',f.date_echeance,'quantity',f.quantite_heures_snapshot,'rate',f.taux_horaire_snapshot,
    'net',f.montant_ht,'vat',f.montant_tva,'total',f.montant_ttc,'paid',f.date_paiement IS NOT NULL OR f.stripe_payment_intent_id IS NOT NULL,
    'final',f.est_facture_finale_mission,'periodStart',f.periode_debut,'periodEnd',f.periode_fin,
    'versionCount',(SELECT count(*) FROM versions d WHERE d.facture_honoraire_id=f.id),
    'versions',(SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY d.id),'[]'::jsonb) FROM versions d WHERE d.facture_honoraire_id=f.id),
    'pdf',jsonb_build_object('key',f.pdf_s3_key,'sha256',(SELECT d.pdf_sha256 FROM versions d WHERE d.facture_honoraire_id=f.id LIMIT 1),
      'size',(SELECT (o.metadata->>'size')::bigint FROM storage.objects o WHERE bucket_id='jolene-documents' AND name=f.pdf_s3_key)),
    'xml',jsonb_build_object('key',f.facturx_xml_url,'sha256',(SELECT d.xml_sha256 FROM versions d WHERE d.facture_honoraire_id=f.id LIMIT 1),
      'size',(SELECT (o.metadata->>'size')::bigint FROM storage.objects o WHERE bucket_id='jolene-documents' AND name=f.facturx_xml_url))
    ) ORDER BY f.facture_precedente_id NULLS FIRST,f.id),'[]'::jsonb) FROM f),
  'syntheticPresence',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'mission',mission_id,'soignant',soignant_id,
    'hours',heures_reelles,'adjusted',heures_ajustees_litige,'litige',ajustement_litige_id,'arrival',pointage_arrivee_le IS NOT NULL,
    'departure',pointage_depart_le IS NOT NULL,'validated',coalesce(valide_par_etablissement,false)) ORDER BY id),'[]'::jsonb)
    FROM public.presences WHERE mission_id=${m}::uuid OR id=${literalF1(v.ids.presence)}::uuid),
  'commissions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'honoraire',c.facture_honoraire_id,'predecessor',c.facture_precedente_id,
    'mission',c.mission_id,'etablissement',c.etablissement_id,'kind',c.type_document,'status',c.statut,
    'net',c.montant_ht,'vat',c.montant_tva,'total',c.montant_ttc,'periodStart',c.periode_debut,'periodEnd',c.periode_fin,
    'providerLinked',c.stripe_invoice_id IS NOT NULL OR c.stripe_payment_intent_id IS NOT NULL OR c.stripe_hosted_url IS NOT NULL
      OR c.chorus_pro_id IS NOT NULL OR c.date_paiement IS NOT NULL OR c.virement_confirme_le IS NOT NULL,
    'immutable',to_jsonb(c)-'statut'-'modifie_le') ORDER BY c.facture_precedente_id NULLS FIRST,c.id),'[]'::jsonb) FROM commissions c),
  'paymentsSoignant',(SELECT count(*)::int FROM public.paiements_soignant WHERE mission_id=${m}::uuid),
  'paymentsMission',(SELECT count(*)::int FROM public.paiements_mission WHERE mission_id=${m}::uuid),
  'payments',(SELECT count(*)::int FROM public.paiements_escrow WHERE mission_id=${m}::uuid),
  'transfers',(SELECT count(*)::int FROM public.stripe_transfers WHERE mission_id=${m}::uuid),
  'emailsQueued',(SELECT count(*)::int FROM public.email_queue WHERE destinataire_id IN(${s}::uuid,${e}::uuid)),
  'emailTestSkips',(SELECT count(*)::int FROM public.journaux_audit WHERE id_ressource IN(${s}::uuid,${e}::uuid)
    AND action='NOTIFICATION_SKIPPED' AND details->>'raison'='test_account' AND details->>'fonction' IS NULL),
  'supportTestSkips',(SELECT count(*)::int FROM public.journaux_audit WHERE id_ressource IN(${s}::uuid,${e}::uuid)
    AND action='NOTIFICATION_SKIPPED' AND details->>'raison'='test_account' AND details->>'fonction'='notify-support'),
  'emailRetries',(SELECT count(*)::int FROM public.invoice_audit_log WHERE invoice_id IN(SELECT id FROM f) AND action='EMAIL_EMISSION_A_REESSAYER'),
  'conversations',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'mission',mission_id,'soignant',soignant_id,'etablissement',etablissement_id,
    'first',participant_1_id,'second',participant_2_id) ORDER BY id),'[]'::jsonb) FROM public.conversations WHERE mission_id=${m}::uuid),
  'messages',(SELECT count(*)::int FROM public.messages_chat WHERE conversation_id IN(SELECT id FROM public.conversations WHERE mission_id=${m}::uuid)),
  'presences',(SELECT count(*)::int FROM public.presence_status WHERE user_id IN(${s}::uuid,${e}::uuid)),
  'typing',(SELECT count(*)::int FROM public.typing_status WHERE user_id IN(${s}::uuid,${e}::uuid)),
  'uiAudit',(SELECT jsonb_agg(jsonb_build_object('id',id,
    'connexions',(SELECT count(*)::int FROM public.journaux_audit WHERE acteur_id=acteurs.id AND action='CONNEXION'),
    'consultations',(SELECT count(*)::int FROM public.journaux_audit WHERE acteur_id=acteurs.id AND action='DONNEES_PERSO_CONSULTATION'
      AND details='{"page":"dashboard_etablissement"}'::jsonb),
    'other',(SELECT count(*)::int FROM public.journaux_audit WHERE acteur_id=acteurs.id AND action NOT IN('CONNEXION','DONNEES_PERSO_CONSULTATION'))
    ) ORDER BY id) FROM (VALUES(${s}::uuid),(${e}::uuid)) acteurs(id)),
  'financeDigest',(SELECT md5(coalesce(string_agg(to_jsonb(f)::text,E'\n' ORDER BY id),'')) FROM f),
  'commissionsDigest',(SELECT md5(coalesce(string_agg(to_jsonb(c)::text,E'\n' ORDER BY id),'')) FROM commissions c),
  'invoiceAuditDigest',(SELECT md5(coalesce(string_agg(to_jsonb(a)::text,E'\n' ORDER BY id),'')) FROM public.invoice_audit_log a WHERE invoice_id IN(SELECT id FROM f)),
  'versionsDigest',(SELECT md5(coalesce(string_agg(to_jsonb(d)::text,E'\n' ORDER BY id),'')) FROM versions d)
) AS receipt;`;
}
