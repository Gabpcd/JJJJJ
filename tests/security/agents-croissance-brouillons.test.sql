-- Agents de croissance (20261108120000) : brouillons seulement, garde STOP,
-- opposition, idempotence, décisions admin et entonnoir de la cohorte réelle.
-- Staging uniquement ; toutes les fixtures et mutations sont annulées.
BEGIN;
SET LOCAL statement_timeout = '60s';

DO $test$
DECLARE
  v_admin uuid := '73000000-0000-4000-8000-000000000001';
  v_user uuid := '73000000-0000-4000-8000-000000000002';
  v_res jsonb;
  v_n integer;
  v_id uuid;
  v_id_stop uuid;
  v_corps text;
  v_contact uuid;
  v_refus boolean;
BEGIN
  -- 1. Droits : RPC admin fermées à anon, primitives private fermées à tous.
  IF has_function_privilege('anon', 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.fn_admin_growth_entonnoir(integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.fn_admin_growth_executer_agents()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.fn_admin_growth_planification(boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'RPC croissance ouverte à anon';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.fn_admin_growth_entonnoir(integer)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.fn_admin_growth_executer_agents()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.fn_admin_growth_planification(boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'GRANT authenticated manquant sur une RPC croissance';
  END IF;
  IF has_function_privilege('authenticated', 'private.fn_growth_agents_executer(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.fn_growth_agent_prospection()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.fn_growth_entonnoir(timestamptz,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Primitive private croissance exécutable par authenticated';
  END IF;
  IF has_table_privilege('authenticated', 'public.growth_brouillons', 'INSERT')
     OR has_table_privilege('authenticated', 'public.growth_brouillons', 'UPDATE')
     OR has_table_privilege('anon', 'public.growth_brouillons', 'SELECT') THEN
    RAISE EXCEPTION 'Écriture directe ou lecture anonyme possible sur growth_brouillons';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p
                 ON p.oid = 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)'::regprocedure
                 WHERE i.signature = 'fn_admin_growth_brouillon_decider(uuid,text,text,text,text)'
                   AND i.definition_md5 = md5(p.prosrc)) THEN
    RAISE EXCEPTION 'Inventaire SECURITY DEFINER non synchronisé';
  END IF;

  -- 2. Fixtures : un marché fictif ZZ isolé des vraies données staging.
  UPDATE public.growth_config SET valeur = 'ZZ' WHERE cle = 'agents_departements_cibles';
  UPDATE public.growth_config SET valeur = '50' WHERE cle = 'agents_prospection_quota_jour';
  UPDATE public.growth_config SET valeur = '500' WHERE cle = 'agents_prospection_file_max';

  INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, email, telephone, ville, departement, statut_sourcing)
  VALUES
    ('ZZGROW001', 'EHPAD Recette Un', 'EHPAD', 'contact@ehpad-recette-un.test', '0100000001', 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW002', 'EHPAD Recette Stop', 'EHPAD', 'direction@ehpad-recette-stop.test', '0100000002', 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW003', 'EHPAD Recette Opposition', 'EHPAD', 'accueil@ehpad-recette-opp.test', NULL, 'Recetteville', 'ZZ', 'OPPOSITION'),
    ('ZZGROW004', 'EHPAD Recette Doublon', 'EHPAD', 'CONTACT@ehpad-recette-un.test', NULL, 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW005', 'Centre Recette Tardif', 'CENTRE_SANTE', 'rh@centre-recette-tardif.test', NULL, 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW006', 'Pharmacie Recette', 'PHARMACIE', 'contact@pharma-recette.test', NULL, 'Recetteville', 'ZZ', 'A_QUALIFIER');

  INSERT INTO public.sales_contacts (type, nom, email, statut, ne_plus_contacter)
  VALUES ('ETABLISSEMENT', 'Contact STOP recette', 'direction@ehpad-recette-stop.test', 'PERDU', true);

  -- 3. Agent prospection : uniquement les cibles contactables, une par adresse.
  v_res := private.fn_growth_agent_prospection();
  SELECT count(*) INTO v_n FROM public.growth_brouillons WHERE cible_id LIKE 'ZZGROW%';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'Prospection : 2 brouillons attendus (001, 005), % obtenus — %', v_n, v_res;
  END IF;
  IF EXISTS (SELECT 1 FROM public.growth_brouillons
             WHERE cible_id IN ('ZZGROW002', 'ZZGROW003', 'ZZGROW004', 'ZZGROW006')) THEN
    RAISE EXCEPTION 'Prospection : STOP, opposition, doublon d''adresse ou type hors cible non exclu';
  END IF;
  SELECT id, corps INTO v_id, v_corps FROM public.growth_brouillons WHERE cible_id = 'ZZGROW001';
  IF position('(répertoire FINESS et Annuaire Santé)' IN v_corps) = 0
     OR position('« STOP »' IN v_corps) = 0
     OR position('15 % HT' IN v_corps) = 0
     OR position('utm_campaign=agent-prospection' IN v_corps) = 0 THEN
    RAISE EXCEPTION 'Corps de prospection incomplet (mention d''opposition, tarif ou lien UTM)';
  END IF;
  IF (SELECT statut FROM public.growth_brouillons WHERE id = v_id) <> 'BROUILLON' THEN
    RAISE EXCEPTION 'Un brouillon neuf doit être au statut BROUILLON';
  END IF;

  -- Idempotence : un second passage ne recrée rien.
  v_res := private.fn_growth_agent_prospection();
  SELECT count(*) INTO v_n FROM public.growth_brouillons WHERE cible_id LIKE 'ZZGROW%';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'Prospection non idempotente : % brouillons', v_n;
  END IF;

  -- Verrou explicite : sans mention d'opposition, aucun brouillon.
  UPDATE public.growth_config SET valeur = '' WHERE cle = 'prospection_mention_opposition';
  v_refus := false;
  BEGIN
    PERFORM private.fn_growth_agent_prospection();
  EXCEPTION WHEN raise_exception THEN
    v_refus := position('prospection_mention_opposition' IN SQLERRM) > 0;
  END;
  IF NOT v_refus THEN
    RAISE EXCEPTION 'La prospection doit refuser de tourner sans mention d''opposition';
  END IF;
  UPDATE public.growth_config
     SET valeur = 'Vos coordonnées professionnelles proviennent des annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé). Si vous ne souhaitez plus être contacté par Jolene, répondez simplement « STOP » à cet email : nous ne vous écrirons plus.'
   WHERE cle = 'prospection_mention_opposition';

  -- 4. Posts : 2 professions × 1 département + 1 LinkedIn de la semaine, idempotents.
  v_res := private.fn_growth_agent_posts();
  v_res := private.fn_growth_agent_posts();
  SELECT count(*) INTO v_n FROM public.growth_brouillons WHERE agent = 'POST_SOCIAL' AND departement = 'ZZ';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'Posts : 2 brouillons Facebook ZZ attendus, % obtenus', v_n;
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE idempotence_key = 'posts:' || to_char(now() AT TIME ZONE 'Europe/Paris', 'IYYY-"S"IW') || ':linkedin') <> 1 THEN
    RAISE EXCEPTION 'Posts : un seul LinkedIn attendu pour la semaine courante';
  END IF;

  -- 4 bis. Un brouillon expiré libère la cible : elle est reproposée.
  INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, email, ville, departement, statut_sourcing)
  VALUES ('ZZGROW007', 'EHPAD Recette Expiré', 'EHPAD', 'accueil@ehpad-recette-expire.test', 'Recetteville', 'ZZ', 'A_QUALIFIER');
  v_res := private.fn_growth_agent_prospection();
  SELECT id INTO v_id_stop FROM public.growth_brouillons WHERE cible_id = 'ZZGROW007';
  UPDATE public.growth_brouillons SET expire_le = now() - interval '1 minute' WHERE id = v_id_stop;
  UPDATE public.growth_config SET valeur = 'true' WHERE cle = 'agents_croissance_actifs';
  v_res := private.fn_growth_agents_executer('CRON');
  IF (SELECT statut FROM public.growth_brouillons WHERE id = v_id_stop) <> 'EXPIRE'
     OR (SELECT count(*) FROM public.growth_brouillons WHERE cible_id = 'ZZGROW007' AND statut = 'BROUILLON') <> 1 THEN
    RAISE EXCEPTION 'Une cible expirée doit être reproposée — %', v_res;
  END IF;
  -- … mais un brouillon VALIDÉ puis expiré (envoi possible hors suivi) ne l'est pas.
  UPDATE public.growth_brouillons
     SET statut = 'VALIDE', valide_le = now(), expire_le = now() - interval '1 minute'
   WHERE cible_id = 'ZZGROW007' AND statut = 'BROUILLON';
  v_res := private.fn_growth_agents_executer('CRON');
  IF (SELECT count(*) FROM public.growth_brouillons WHERE cible_id = 'ZZGROW007') <> 2
     OR EXISTS (SELECT 1 FROM public.growth_brouillons WHERE cible_id = 'ZZGROW007' AND statut <> 'EXPIRE') THEN
    RAISE EXCEPTION 'Un brouillon validé puis expiré ne doit pas libérer sa cible — %', v_res;
  END IF;

  -- 5. Orchestrateur : le cron respecte l'interrupteur.
  UPDATE public.growth_config SET valeur = 'false' WHERE cle = 'agents_croissance_actifs';
  v_res := private.fn_growth_agents_executer('CRON');
  IF COALESCE((v_res->>'ignore')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Le cron doit être ignoré quand agents_croissance_actifs=false : %', v_res;
  END IF;
  UPDATE public.growth_config SET valeur = 'true' WHERE cle = 'agents_croissance_actifs';
  v_res := private.fn_growth_agents_executer('CRON');
  IF v_res->'agents' IS NULL OR (SELECT count(*) FROM jsonb_object_keys(v_res->'agents')) <> 4 THEN
    RAISE EXCEPTION 'Orchestrateur : 4 agents attendus — %', v_res;
  END IF;
  IF EXISTS (SELECT 1 FROM public.growth_agent_executions
             WHERE declencheur = 'CRON' AND erreur IS NOT NULL AND debut_le >= now()) THEN
    RAISE EXCEPTION 'Un agent a échoué : %',
      (SELECT string_agg(agent || ': ' || erreur, ' | ') FROM public.growth_agent_executions
       WHERE erreur IS NOT NULL AND debut_le >= now());
  END IF;

  -- 6. Entonnoir : cohorte réelle, clés attendues.
  v_res := private.fn_growth_entonnoir(now() - interval '7 days', now());
  IF v_res->>'cohorte' IS DISTINCT FROM 'REELLE'
     OR v_res->'soignants'->'inscrits_total' IS NULL
     OR v_res->'etablissements'->'ayant_publie' IS NULL
     OR v_res->'missions'->'ouvertes_sans_candidature' IS NULL
     OR v_res->'prospection'->'prospects_avec_email' IS NULL
     OR v_res->'agents'->'en_attente' IS NULL
     OR v_res->'exclus_cohorte_test'->'soignants_test' IS NULL THEN
    RAISE EXCEPTION 'Entonnoir incomplet : %', v_res;
  END IF;
  v_res := private.fn_growth_snapshot_hebdo();
  IF NOT EXISTS (SELECT 1 FROM public.growth_rapports_hebdo WHERE semaine_debut = (v_res->>'semaine_debut')::date) THEN
    RAISE EXCEPTION 'Rapport hebdomadaire non figé';
  END IF;

  -- 7. Décisions : non-admin refusé, admin valide puis constate l'envoi.
  INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
  VALUES
    (v_admin, '00000000-0000-0000-0000-000000000000', 'croissance-admin@test.local',
     'authenticated', 'authenticated', '{"role":"ADMIN_PLATEFORME"}', now()),
    (v_user, '00000000-0000-0000-0000-000000000000', 'croissance-user@test.local',
     'authenticated', 'authenticated', '{"role":"SOIGNANT"}', now());
  INSERT INTO public.equipe_admin (user_id, nom, prenom, email, actif, acces_groupes)
  VALUES (v_admin, 'Croissance', 'Admin', 'croissance-admin@test.local', true, ARRAY[
    'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
    'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur']::text[]);

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_refus := false;
  BEGIN
    PERFORM public.fn_admin_growth_brouillon_decider(v_id, 'VALIDER');
  EXCEPTION WHEN insufficient_privilege THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Un non-admin a pu décider d''un brouillon'; END IF;
  v_refus := false;
  BEGIN
    PERFORM public.fn_admin_growth_entonnoir(7);
  EXCEPTION WHEN insufficient_privilege THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Un non-admin a pu lire l''entonnoir'; END IF;
  v_refus := false;
  BEGIN
    PERFORM public.fn_admin_growth_planification(true);
  EXCEPTION WHEN insufficient_privilege THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Un non-admin a pu activer la planification'; END IF;
  IF EXISTS (SELECT 1 FROM public.growth_brouillons) THEN
    RAISE EXCEPTION 'RLS : un non-admin lit growth_brouillons';
  END IF;
  EXECUTE 'RESET ROLE';

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF NOT EXISTS (SELECT 1 FROM public.growth_brouillons WHERE id = v_id) THEN
    RAISE EXCEPTION 'RLS : l''admin ne lit pas growth_brouillons';
  END IF;
  v_refus := false;
  BEGIN
    PERFORM public.fn_admin_growth_brouillon_decider(v_id, 'MARQUER_ENVOYE');
  EXCEPTION WHEN raise_exception THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Un brouillon non validé a pu être marqué envoyé'; END IF;

  v_res := public.fn_admin_growth_brouillon_decider(v_id, 'VALIDER', 'Objet modifié', NULL);
  IF v_res->>'statut' IS DISTINCT FROM 'VALIDE' THEN
    RAISE EXCEPTION 'Validation admin échouée : %', v_res;
  END IF;
  v_res := public.fn_admin_growth_brouillon_decider(v_id, 'MARQUER_ENVOYE');
  v_contact := (v_res->>'contact_crm_id')::uuid;
  IF v_res->>'statut' IS DISTINCT FROM 'ENVOYE' OR v_contact IS NULL THEN
    RAISE EXCEPTION 'Constat d''envoi échoué : %', v_res;
  END IF;
  EXECUTE 'RESET ROLE';

  IF NOT EXISTS (SELECT 1 FROM public.sales_contacts
                 WHERE id = v_contact AND finess = 'ZZGROW001'
                   AND statut = 'CONTACTE' AND sequence_active IS TRUE
                   AND prochaine_action_le > now()) THEN
    RAISE EXCEPTION 'Le constat d''envoi n''a pas alimenté la séquence CRM';
  END IF;
  IF (SELECT email_envoye_le FROM public.prospects_etablissements WHERE finess = 'ZZGROW001') IS NULL THEN
    RAISE EXCEPTION 'email_envoye_le non posé sur le prospect';
  END IF;
  IF (SELECT sujet FROM public.growth_brouillons WHERE id = v_id) <> 'Objet modifié' THEN
    RAISE EXCEPTION 'La modification du sujet à la validation est perdue';
  END IF;

  -- Opposition arrivée après la rédaction : la validation rejette et persiste.
  SELECT id INTO v_id_stop FROM public.growth_brouillons WHERE cible_id = 'ZZGROW005';
  INSERT INTO public.sales_contacts (type, nom, email, statut, ne_plus_contacter)
  VALUES ('ETABLISSEMENT', 'Opposition tardive recette', 'rh@centre-recette-tardif.test', 'PERDU', true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_res := public.fn_admin_growth_brouillon_decider(v_id_stop, 'VALIDER');
  EXECUTE 'RESET ROLE';
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE
     OR (SELECT statut FROM public.growth_brouillons WHERE id = v_id_stop) <> 'REJETE' THEN
    RAISE EXCEPTION 'Une opposition tardive doit rejeter le brouillon : %', v_res;
  END IF;

  -- 8. Crons créés désactivés ; seul l'interrupteur admin les active.
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF (SELECT count(*) FROM cron.job WHERE jobname IN ('jolene_growth_agents_quotidien', 'jolene_growth_rapport_hebdo')) <> 2
       OR EXISTS (SELECT 1 FROM cron.job WHERE jobname LIKE 'jolene_growth_%' AND active)
       OR EXISTS (SELECT 1 FROM cron.job WHERE jobname LIKE 'jolene_growth_%' AND command ~* '(net\.http|send-email|resend)') THEN
      RAISE EXCEPTION 'Crons croissance absents, actifs à la migration ou contenant un appel d''envoi';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_res := public.fn_admin_growth_planification(NULL);
    IF (v_res->>'actif')::boolean IS NOT FALSE THEN
      RAISE EXCEPTION 'Lecture de planification : inactif attendu — %', v_res;
    END IF;
    v_res := public.fn_admin_growth_planification(true);
    EXECUTE 'RESET ROLE';
    IF (v_res->>'actif')::boolean IS NOT TRUE
       OR (SELECT count(*) FROM cron.job WHERE jobname LIKE 'jolene_growth_%' AND active) <> 2
       OR private.fn_growth_config('agents_croissance_actifs', 'false') <> 'true' THEN
      RAISE EXCEPTION 'Activation admin incomplète — %', v_res;
    END IF;
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_res := public.fn_admin_growth_planification(false);
    EXECUTE 'RESET ROLE';
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname LIKE 'jolene_growth_%' AND active)
       OR private.fn_growth_config('agents_croissance_actifs', 'true') <> 'false' THEN
      RAISE EXCEPTION 'Mise en pause admin incomplète — %', v_res;
    END IF;
  END IF;
END;
$test$;
ROLLBACK;
