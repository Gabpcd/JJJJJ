-- Lecture indépendante staging avant/après la transaction, sous le même verrou.
-- Uniquement empreintes, compteurs et absence de fixtures ; aucun payload/token.
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
SET LOCAL timezone='UTC';
SELECT
  (SELECT md5(COALESCE(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
    'definition',md5(pg_get_functiondef(p.oid)),'owner',p.proowner,'definer',p.prosecdef,
    'acl',p.proacl::text,'config',p.proconfig) ORDER BY p.oid::regprocedure::text)::text,'[]'))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','private') AND p.prokind='f') AS routines_md5,
  (SELECT md5(COALESCE(jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,
    'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) ORDER BY t.tgrelid::regclass::text,t.tgname)::text,'[]'))
   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth')) AS triggers_md5,
  (SELECT md5(COALESCE(jsonb_agg(jsonb_build_object('signature',signature,'categorie',categorie,
    'definition_md5',definition_md5) ORDER BY signature)::text,'[]')) FROM private.security_definer_inventory) AS inventaire_md5,
  (SELECT md5(COALESCE(jsonb_agg(jsonb_build_object('table',c.conrelid::regclass::text,'name',c.conname,
    'validated',c.convalidated,'definition',pg_get_constraintdef(c.oid)) ORDER BY c.conrelid::regclass::text,c.conname)::text,'[]'))
   FROM pg_constraint c WHERE c.conrelid IN ('public.externalisation_actions'::regclass,
    'public.candidatures'::regclass,'public.notifications'::regclass)) AS contraintes_md5,
  (SELECT md5(COALESCE(jsonb_agg(jsonb_build_object('table',i.indrelid::regclass::text,
    'name',i.indexrelid::regclass::text,'valid',i.indisvalid,'definition',pg_get_indexdef(i.indexrelid))
    ORDER BY i.indexrelid::regclass::text)::text,'[]'))
   FROM pg_index i WHERE i.indrelid IN ('public.externalisation_actions'::regclass,
    'public.candidatures'::regclass,'public.notifications'::regclass)) AS indexes_md5,
  (SELECT md5(COALESCE(jsonb_agg(jsonb_build_object('cle',cle,'valeur',valeur) ORDER BY cle)::text,'[]'))
   FROM public.parametres_systeme WHERE cle='inscriptions_publiques_actives') AS parametre_md5,
  (SELECT md5(COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.id)::text,'[]'))
   FROM public.externalisation_actions a) AS externalisations_md5,
  jsonb_build_object(
    'auth_users',(SELECT count(*) FROM auth.users),
    'soignants',(SELECT count(*) FROM public.soignants),
    'etablissements',(SELECT count(*) FROM public.etablissements),
    'membres',(SELECT count(*) FROM public.membres_etablissement),
    'types_comptes',(SELECT count(*) FROM public.types_comptes_auth),
    'missions',(SELECT count(*) FROM public.missions),
    'creneaux',(SELECT count(*) FROM public.mission_creneaux),
    'candidatures',(SELECT count(*) FROM public.candidatures),
    'notifications',(SELECT count(*) FROM public.notifications),
    'preferences',(SELECT count(*) FROM public.preferences_notifications),
    'preferences_evenements',(SELECT count(*) FROM public.preferences_notifications_par_evenement),
    'swipes',(SELECT count(*) FROM public.swipes),
    'sauvegardes',(SELECT count(*) FROM public.missions_sauvegardees),
    'badges',(SELECT count(*) FROM public.badges_soignant),
    'streaks',(SELECT count(*) FROM public.streaks_soignant),
    'audits',(SELECT count(*) FROM public.journaux_audit),
    'conformite',(SELECT count(*) FROM public.conformite_travail),
    'suivi',(SELECT count(*) FROM public.suivi_conversion_3200h),
    'scoring',(SELECT count(*) FROM public.scoring_breakdown),
    'emails',(SELECT count(*) FROM public.email_queue),
    'externalisations',(SELECT count(*) FROM public.externalisation_actions),
    'push_tokens',(SELECT count(*) FROM public.tokens_push),
    'net_requests',(SELECT count(*) FROM net.http_request_queue),
    'cron_actifs',(SELECT count(*) FROM cron.job WHERE active)
  ) AS compteurs,
  (SELECT count(*) FROM auth.users WHERE id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.soignants WHERE id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.etablissements WHERE id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.membres_etablissement WHERE user_id::text LIKE '71140000-%' OR etablissement_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.types_comptes_auth WHERE user_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.missions WHERE id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.mission_creneaux WHERE mission_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.candidatures WHERE mission_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.notifications WHERE destinataire_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.preferences_notifications_par_evenement WHERE utilisateur_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.swipes WHERE soignant_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.missions_sauvegardees WHERE soignant_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.badges_soignant WHERE soignant_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.streaks_soignant WHERE soignant_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.journaux_audit WHERE acteur_id::text LIKE '71140000-%' OR id_ressource::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.conformite_travail WHERE soignant_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.suivi_conversion_3200h WHERE soignant_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.scoring_breakdown WHERE soignant_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.email_queue WHERE destinataire_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.tokens_push WHERE utilisateur_id::text LIKE '71140000-%')
    +(SELECT count(*) FROM public.externalisation_actions WHERE id::text LIKE '71140000-%' OR payload->>'mission_id' LIKE '71140000-%') AS residus;
ROLLBACK;
