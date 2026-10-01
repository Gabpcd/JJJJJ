-- Lecture indépendante seulement ; aucun contenu utilisateur ni secret retourné.
-- Les compteurs globaux refusent aussi une mutation staging concurrente.
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
SELECT
  (SELECT md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||p.proowner::text||':'||p.prosecdef::text||':'||coalesce(p.proacl::text,'NULL')||':'||coalesce(p.proconfig::text,'NULL'),E'\n' ORDER BY p.oid::regprocedure::text))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','private') AND p.prokind='f') AS routines_md5,
  (SELECT md5(string_agg(t.tgrelid::regclass::text||':'||t.tgname||':'||t.tgenabled::text||':'||pg_get_triggerdef(t.oid),E'\n' ORDER BY t.tgrelid::regclass::text,t.tgname))
   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth')) AS triggers_md5,
  (SELECT md5(string_agg(signature||':'||categorie||':'||definition_md5,E'\n' ORDER BY signature))
   FROM private.security_definer_inventory) AS inventaire_md5,
  md5(coalesce((SELECT jsonb_build_object(
    'owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
    'colonnes',(SELECT jsonb_agg(jsonb_build_array(a.attname,a.atttypid,a.atttypmod,a.attnotnull,pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)
      FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
    'contraintes',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),
    'index',(SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY i.indexrelid::regclass::text) FROM pg_index i WHERE i.indrelid=c.oid),
    'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid))::text
    FROM pg_class c WHERE c.oid=to_regclass('private.generations_factures_honoraires')),'ABSENTE')) AS baux_schema_md5,
  jsonb_build_object(
    'auth_users',(SELECT count(*) FROM auth.users),'soignants',(SELECT count(*) FROM public.soignants),
    'etablissements',(SELECT count(*) FROM public.etablissements),'missions',(SELECT count(*) FROM public.missions),
    'presences',(SELECT count(*) FROM public.presences),
    'creneaux',(SELECT count(*) FROM public.mission_creneaux),'equipes',(SELECT count(*) FROM public.equipe_admin),
    'litiges',(SELECT count(*) FROM public.litiges),'honoraires',(SELECT count(*) FROM public.factures_honoraires),
    'commissions',(SELECT count(*) FROM public.factures),'audit_factures',(SELECT count(*) FROM public.invoice_audit_log),
    'audits',(SELECT count(*) FROM public.journaux_audit),'notifications',(SELECT count(*) FROM public.notifications),
    'preferences',(SELECT count(*) FROM public.preferences_notifications),'conformite',(SELECT count(*) FROM public.conformite_travail),
    'suivi',(SELECT count(*) FROM public.suivi_conversion_3200h),'emails',(SELECT count(*) FROM public.email_queue),
    'externalisations',(SELECT count(*) FROM public.externalisation_actions),'escrow',(SELECT count(*) FROM public.paiements_escrow),
    'refunds',(SELECT count(*) FROM public.stripe_refunds_queue),'cessions',(SELECT count(*) FROM public.cessions_creance),
    'scoring',(SELECT count(*) FROM public.scoring_breakdown),
    'escrow_release',(SELECT count(*) FROM public.escrow_release_queue),
    'stripe_transfers',(SELECT count(*) FROM public.stripe_transfers),
    'paiements_soignant',(SELECT count(*) FROM public.paiements_soignant),
    'claims',(SELECT count(*) FROM public.stripe_payment_flow_claims),
    'archives',(SELECT count(*) FROM public.factures_honoraires_documents),
    'net_requests',(SELECT count(*) FROM net.http_request_queue),
    -- Requête constante, évaluée seulement si la table existe déjà sur main.
    -- Compatible avant installation et après annulation de la migration candidate.
    'baux',CASE WHEN to_regclass('private.generations_factures_honoraires') IS NULL THEN 0
      ELSE ((xpath('/table/row/compteur/text()',query_to_xml(
        'SELECT count(*) AS compteur FROM private.generations_factures_honoraires',false,false,'')))[1]::text)::bigint END
  ) AS compteurs,
  (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.soignants WHERE id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.etablissements WHERE id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.missions WHERE id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.mission_creneaux WHERE mission_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.conformite_travail WHERE mission_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.suivi_conversion_3200h WHERE soignant_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.factures_honoraires WHERE id::text LIKE 'f172000%' OR mission_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.factures WHERE mission_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.paiements_soignant WHERE mission_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.stripe_transfers WHERE mission_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.notifications WHERE destinataire_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.email_queue WHERE destinataire_id::text LIKE 'f172000%')
    +(SELECT count(*) FROM public.stripe_payment_flow_claims WHERE resource_key LIKE 'MISSION:f172000%') AS residus;
ROLLBACK;
