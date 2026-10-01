-- Lecture indépendante seulement ; aucun contenu utilisateur ni secret retourné.
-- Les compteurs globaux refusent aussi une mutation staging concurrente.
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
SELECT
  (SELECT md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid)),E'\n' ORDER BY p.oid::regprocedure::text))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','private') AND p.prokind='f') AS routines_md5,
  (SELECT md5(string_agg(t.tgrelid::regclass::text||':'||t.tgname||':'||t.tgenabled::text||':'||pg_get_triggerdef(t.oid),E'\n' ORDER BY t.tgrelid::regclass::text,t.tgname))
   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth')) AS triggers_md5,
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
    'net_requests',(SELECT count(*) FROM net.http_request_queue)
  ) AS compteurs,
  (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f131000%')
    +(SELECT count(*) FROM public.missions WHERE id='f1310003-3000-4000-8000-000000000003')
    +(SELECT count(*) FROM public.equipe_admin WHERE id='f1310007-7000-4000-8000-000000000007')
    +(SELECT count(*) FROM public.presences WHERE id='f1310009-9000-4000-8000-000000000009' OR mission_id='f1310003-3000-4000-8000-000000000003')
    +(SELECT count(*) FROM public.litiges WHERE id='f1310008-8000-4000-8000-000000000008')
    +(SELECT count(*) FROM public.factures_honoraires WHERE mission_id='f1310003-3000-4000-8000-000000000003')
    +(SELECT count(*) FROM public.factures WHERE mission_id='f1310003-3000-4000-8000-000000000003') AS residus;
ROLLBACK;
