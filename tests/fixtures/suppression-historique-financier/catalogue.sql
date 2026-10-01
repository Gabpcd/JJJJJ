-- SELECT indépendant avant/après la transaction de recette, même verrou staging.
-- Aucune ligne utilisateur ni valeur personnelle n’est retournée.
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
SELECT
  (SELECT md5(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
    'definition_md5',md5(pg_get_functiondef(p.oid)),'owner',pg_get_userbyid(p.proowner),
    'acl',p.proacl::text,'config',p.proconfig) ORDER BY p.oid::regprocedure::text)::text)
   FROM pg_proc p WHERE p.oid IN ('public.fn_supprimer_mon_compte()'::regprocedure,
    'public.fn_supprimer_compte_rate_limited()'::regprocedure)) AS routines_md5,
  (SELECT md5(jsonb_agg(to_jsonb(i) ORDER BY signature)::text) FROM private.security_definer_inventory i
   WHERE signature IN ('fn_supprimer_mon_compte()','fn_supprimer_compte_rate_limited()')) AS inventaire_md5,
  (SELECT md5(string_agg(t.tgrelid::regclass::text||':'||t.tgname||':'||t.tgenabled::text||':'||pg_get_triggerdef(t.oid),E'\n'
    ORDER BY t.tgrelid::regclass::text,t.tgname))
   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth')) AS triggers_md5,
  jsonb_build_object(
    'auth_users',(SELECT count(*) FROM auth.users),'soignants',(SELECT count(*) FROM public.soignants),
    'etablissements',(SELECT count(*) FROM public.etablissements),'missions',(SELECT count(*) FROM public.missions),
    'creneaux',(SELECT count(*) FROM public.mission_creneaux),'presences',(SELECT count(*) FROM public.presences),
    'paiements',(SELECT count(*) FROM public.paiements_soignant),'transferts',(SELECT count(*) FROM public.stripe_transfers),
    'honoraires',(SELECT count(*) FROM public.factures_honoraires),'commissions',(SELECT count(*) FROM public.factures),
    'audits_pieces',(SELECT count(*) FROM public.invoice_audit_log),'audits',(SELECT count(*) FROM public.journaux_audit),
    'recus',(SELECT count(*) FROM private.suppressions_compte_confirmees),
    'preferences',(SELECT count(*) FROM public.preferences_notifications),'notifications',(SELECT count(*) FROM public.notifications),
    'emails',(SELECT count(*) FROM public.email_queue),'externalisations',(SELECT count(*) FROM public.externalisation_actions),
    'refunds',(SELECT count(*) FROM public.stripe_refunds_queue),'cessions',(SELECT count(*) FROM public.cessions_creance),
    'escrow',(SELECT count(*) FROM public.paiements_escrow),'escrow_release',(SELECT count(*) FROM public.escrow_release_queue),
    'scoring',(SELECT count(*) FROM public.scoring_breakdown),'rate_limits',(SELECT count(*) FROM public.rate_limits),
    'net_requests',(SELECT count(*) FROM net.http_request_queue)
  ) AS compteurs,
  (SELECT count(*) FROM auth.users WHERE id::text LIKE ANY(ARRAY['f1610000-%','f1610007-%']))
    +(SELECT count(*) FROM public.soignants WHERE id::text LIKE ANY(ARRAY['f1610000-%','f1610007-%']))
    +(SELECT count(*) FROM public.etablissements WHERE id::text LIKE ANY(ARRAY['f1610000-%','f1610007-%']))
    +(SELECT count(*) FROM public.missions WHERE id::text LIKE 'f1610001-%')
    +(SELECT count(*) FROM public.mission_creneaux WHERE mission_id::text LIKE 'f1610001-%')
    +(SELECT count(*) FROM public.factures_honoraires WHERE id::text LIKE 'f1610002-%')
    +(SELECT count(*) FROM public.paiements_soignant WHERE mission_id::text LIKE 'f1610001-%')
    +(SELECT count(*) FROM public.stripe_transfers WHERE mission_id::text LIKE 'f1610001-%')
    +(SELECT count(*) FROM private.suppressions_compte_confirmees WHERE utilisateur_id::text LIKE ANY(ARRAY['f1610000-%','f1610007-%']))
    +(SELECT count(*) FROM public.rate_limits WHERE cle LIKE ANY(ARRAY['f1610000-%','f1610007-%']))
    +(SELECT count(*) FROM public.notifications WHERE destinataire_id::text LIKE ANY(ARRAY['f1610000-%','f1610007-%']))
    +(SELECT count(*) FROM public.email_queue WHERE destinataire_id::text LIKE ANY(ARRAY['f1610000-%','f1610007-%']))
    +(SELECT count(*) FROM public.invoice_audit_log WHERE invoice_id::text LIKE 'f1610002-%') AS residus;
ROLLBACK;
