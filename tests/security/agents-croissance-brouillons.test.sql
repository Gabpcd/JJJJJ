-- Agents de croissance (20261109140000) : brouillons seulement, garde STOP,
-- opposition, idempotence, décisions admin et entonnoir de la cohorte réelle.
-- §9 : adresses MSSanté exclues et brouillons MSSanté expirés (20261116143942).
-- §11 : zéro visible (décompte des cibles) et liste d'appels hebdomadaire (20261124123500).
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
  v_contact_mss uuid;
  v_contact_cls uuid;
  v_id_mss uuid;
  v_id_mss_valide uuid;
  v_id_faux_ami uuid;
  v_file_n integer;
  v_places_avant integer;
  v_places_apres integer;
  v_refus boolean;
  v_cibles jsonb;
  v_id_tel uuid;
  v_id_tel_stop uuid;
  v_id_tel_tardif uuid;
  v_id_tel_constat uuid;
  v_id_tel_orphelin uuid;
  v_appels_avant integer;
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
  -- Donnée BMO du marché fictif : part exacte pour les aides-soignants, catégorie agrégée
  -- (commune avec les sages-femmes) pour les infirmiers.
  INSERT INTO public.acquisition_territoires
    (departement, profession, bmo_annee, bmo_projets_recrutement, bmo_difficulte_pct, bmo_precision)
  VALUES ('ZZ', 'AS', 2026, 120, 40, 'EXACT'), ('ZZ', 'IDE', 2026, 80, 50, 'AGREGAT')
  ON CONFLICT (departement, profession) DO UPDATE
    SET bmo_annee = EXCLUDED.bmo_annee, bmo_projets_recrutement = EXCLUDED.bmo_projets_recrutement,
        bmo_difficulte_pct = EXCLUDED.bmo_difficulte_pct, bmo_precision = EXCLUDED.bmo_precision;
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
  -- Phrase BMO : préposition élidée (20261120150000), et jamais de catégorie agrégée.
  SELECT corps INTO v_corps FROM public.growth_brouillons
   WHERE agent = 'POST_SOCIAL' AND departement = 'ZZ' AND profession = 'AS';
  IF COALESCE(position('France Travail recense 120 projets de recrutement d''aides-soignants dans le ZZ en 2026, dont 40 % jugés difficiles par les employeurs (enquête BMO).' IN v_corps), 0) = 0 THEN
    RAISE EXCEPTION 'Post aides-soignants : phrase BMO absente ou mal accordée — %', v_corps;
  END IF;
  IF EXISTS (SELECT 1 FROM public.growth_brouillons
             WHERE agent = 'POST_SOCIAL' AND departement = 'ZZ' AND profession = 'IDE'
               AND position('France Travail' IN corps) > 0) THEN
    RAISE EXCEPTION 'Post infirmiers : une catégorie BMO agrégée ne doit pas être citée';
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
  IF v_res->'agents' IS NULL OR (SELECT count(*) FROM jsonb_object_keys(v_res->'agents')) <> 5 THEN
    RAISE EXCEPTION 'Orchestrateur : 5 agents attendus — %', v_res;
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

  -- 9. MSSanté (20261116143942) : espace de confiance fermé, injoignable depuis
  -- Gmail. Une seule règle, private.fn_growth_email_mssante, appliquée par
  -- l'agent, par le prédicat unique fn_growth_destinataire_bloque et par
  -- private.fn_growth_expirer_brouillons_mssante, la fonction même qu'exécute
  -- la migration. Chaque preuve porte sur des témoins créés ici et comptés :
  -- aucune assertion ne peut passer à vide.

  -- 9.a Post-condition de la migration sur les données réelles du staging. Elle
  -- peut porter sur zéro ligne : la preuve de l'expiration est au 9.f.
  IF EXISTS (SELECT 1 FROM public.growth_brouillons b
             WHERE b.agent = 'PROSPECTION_ETABLISSEMENT' AND b.statut IN ('BROUILLON', 'VALIDE')
               AND private.fn_growth_email_mssante(b.destinataire_email)) THEN
    RAISE EXCEPTION 'MSSanté : un brouillon de prospection MSSanté est encore en file après la migration';
  END IF;

  -- 9.b Droits : les trois fonctions neuves restent fermées à anon et authenticated.
  IF has_function_privilege('anon', 'private.fn_growth_email_mssante(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.fn_growth_email_mssante(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.fn_growth_motif_expiration_mssante()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.fn_growth_motif_expiration_mssante()', 'EXECUTE')
     OR has_function_privilege('anon', 'private.fn_growth_expirer_brouillons_mssante()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.fn_growth_expirer_brouillons_mssante()', 'EXECUTE') THEN
    RAISE EXCEPTION 'MSSanté : une fonction private MSSanté est exécutable par anon ou authenticated';
  END IF;

  -- 9.c Règle : mssante.fr et ses sous-domaines, casse et blancs de bord
  -- ignorés ; les faux amis restent joignables ; NULL et vide valent false.
  SELECT count(*) INTO v_n
  FROM (VALUES
    ('contact@ehpad-recette.mssante.fr', true),
    (' Direction@MSSante.FR ', true),
    ('secretariat@a.b.mssante.fr', true),
    ('rh@ch_recette.mssante.fr', true),
    ('rh@hôpital-recette.mssante.fr', true),
    (E'rh@mssante.fr\t', true),
    ('contact@pasmssante.fr', false),
    ('contact@recette-pasmssante.fr', false),
    ('contact@mssante.fr.exemple.com', false),
    ('contact@mssante-fr.fr', false),
    ('contact@xmssante.fr', false),
    ('mssante.fr@gmail.com', false),
    ('', false),
    (NULL, false)
  ) AS t(email, attendu)
  WHERE private.fn_growth_email_mssante(t.email) IS NOT DISTINCT FROM t.attendu;
  IF v_n <> 14 THEN
    RAISE EXCEPTION 'MSSanté : fn_growth_email_mssante juste sur % cas sur 14', v_n;
  END IF;

  -- 9.d Prédicat unique : motif MSSANTE pour tout type de cible, après les
  -- motifs existants (compte supprimé et STOP gardent la priorité).
  INSERT INTO public.sales_contacts (type, nom, email, statut, ne_plus_contacter)
  VALUES ('ETABLISSEMENT', 'STOP MSSanté recette', 'stop@ehpad-recette.mssante.fr', 'PERDU', true);
  IF private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'ZZGROW040', 'contact@ehpad-recette.mssante.fr', NULL, NULL) IS DISTINCT FROM 'MSSANTE'
     OR private.fn_growth_destinataire_bloque('CONTACT_CRM', '73000000-0000-4000-8000-000000000040', ' Direction@MSSante.FR ', NULL, NULL) IS DISTINCT FROM 'MSSANTE'
     OR private.fn_growth_destinataire_bloque('PUBLIC', NULL, 'rh@mssante.fr', NULL, NULL) IS DISTINCT FROM 'MSSANTE'
     OR private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'ZZGROW040', 'stop@ehpad-recette.mssante.fr', NULL, NULL) IS DISTINCT FROM 'STOP'
     OR private.fn_growth_destinataire_bloque('SOIGNANT', '73000000-0000-4000-8000-000000000040', 'rh@mssante.fr', NULL, NULL) IS DISTINCT FROM 'COMPTE_SUPPRIME'
     OR private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'ZZGROW040', 'contact@mssante.fr.exemple.com', NULL, NULL) IS NOT NULL
     OR private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'ZZGROW040', 'contact@pasmssante.fr', NULL, NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'MSSanté : prédicat fn_growth_destinataire_bloque inexact (motif MSSANTE, priorité STOP et compte supprimé, faux amis)';
  END IF;

  -- 9.e Agent : aucun prospect ni relance MSSanté retenu ; l'adresse classique
  -- et les trois faux amis le sont. Quota relevé au maximum pour le 9.g.
  UPDATE public.growth_config SET valeur = '100' WHERE cle = 'agents_prospection_quota_jour';
  INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, email, ville, departement, statut_sourcing)
  VALUES
    ('ZZGROW010', 'EHPAD Recette MSSanté', 'EHPAD', 'contact@ehpad-recette.mssante.fr', 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW011', 'EHPAD Recette MSSanté racine', 'EHPAD', ' Direction@MSSante.FR ', 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW012', 'EHPAD Recette Classique', 'EHPAD', 'accueil@ehpad-recette-classique.test', 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW013', 'EHPAD Recette Faux ami tiret', 'EHPAD', 'contact@recette-pasmssante.fr', 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW014', 'EHPAD Recette Faux ami suffixe', 'EHPAD', 'contact@mssante.fr.exemple.com', 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW015', 'EHPAD Recette Faux ami préfixe', 'EHPAD', 'contact@pasmssante.fr', 'Recetteville', 'ZZ', 'A_QUALIFIER');

  -- Relances CRM : deux contacts ouverts par l'agent, échus, l'un MSSanté.
  INSERT INTO public.sales_contacts (type, nom, email, finess, departement, type_etab, statut,
    sequence_active, prochaine_action_le, derniere_action_type, sequence_etape, reponse)
  VALUES ('ETABLISSEMENT', 'Contact MSSanté recette', 'direction@ch-recette.mssante.fr', 'ZZGROW020', 'ZZ', 'EHPAD',
    'CONTACTE', true, '2000-01-01 00:00:00+00', 'EMAIL_ENVOYE', 1, 'EN_ATTENTE')
  RETURNING id INTO v_contact_mss;
  INSERT INTO public.sales_contacts (type, nom, email, finess, departement, type_etab, statut,
    sequence_active, prochaine_action_le, derniere_action_type, sequence_etape, reponse)
  VALUES ('ETABLISSEMENT', 'Contact classique recette', 'direction@ch-recette-classique.test', 'ZZGROW021', 'ZZ', 'EHPAD',
    'CONTACTE', true, '2000-01-01 00:00:00+00', 'EMAIL_ENVOYE', 1, 'EN_ATTENTE')
  RETURNING id INTO v_contact_cls;
  INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, destinataire_email,
    sequence_etape, corps, statut, valide_le, envoye_le, idempotence_key)
  VALUES
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW020', 'direction@ch-recette.mssante.fr',
     1, 'Recette', 'ENVOYE', now(), now(), 'recette-mssante:ZZGROW020:etape1'),
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW021', 'direction@ch-recette-classique.test',
     1, 'Recette', 'ENVOYE', now(), now(), 'recette-mssante:ZZGROW021:etape1');

  v_res := private.fn_growth_agent_prospection();
  IF EXISTS (SELECT 1 FROM public.growth_brouillons
             WHERE cible_id IN ('ZZGROW010', 'ZZGROW011', v_contact_mss::text)) THEN
    RAISE EXCEPTION 'MSSanté : une adresse MSSanté a été retenue par l''agent — %', v_res;
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE cible_type = 'PROSPECT_ETABLISSEMENT'
        AND cible_id IN ('ZZGROW012', 'ZZGROW013', 'ZZGROW014', 'ZZGROW015')
        AND statut = 'BROUILLON' AND sequence_etape = 1) <> 4 THEN
    RAISE EXCEPTION 'MSSanté : l''adresse classique et les faux amis (recette-pasmssante.fr, mssante.fr.exemple.com, pasmssante.fr) doivent être retenus — %', v_res;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.growth_brouillons
                 WHERE cible_type = 'CONTACT_CRM' AND cible_id = v_contact_cls::text
                   AND statut = 'BROUILLON' AND sequence_etape = 2) THEN
    RAISE EXCEPTION 'MSSanté : la relance CRM d''une adresse classique doit être préparée — %', v_res;
  END IF;

  -- 9.f Expiration : private.fn_growth_expirer_brouillons_mssante(), la
  -- fonction qu'appelle la migration, sur des brouillons témoins.
  INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, destinataire_email,
    sequence_etape, corps, statut, valide_le, motif_rejet, idempotence_key, maj_le)
  VALUES
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW030', 'accueil@ehpad-recette.mssante.fr',
     1, 'Recette', 'BROUILLON', NULL, NULL, 'recette-mssante:ZZGROW030', now() - interval '1 day'),
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'CONTACT_CRM', 'ZZGROW031', ' Contact@MSSANTE.FR ',
     2, 'Recette', 'BROUILLON', NULL, NULL, 'recette-mssante:ZZGROW031', now() - interval '1 day'),
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW032', 'rh@ehpad-recette-valide.mssante.fr',
     1, 'Recette', 'VALIDE', now(), NULL, 'recette-mssante:ZZGROW032', now() - interval '1 day'),
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW033', 'accueil@ehpad-recette-classique-2.test',
     1, 'Recette', 'BROUILLON', NULL, NULL, 'recette-mssante:ZZGROW033', now() - interval '1 day'),
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW034', 'rh@recette-pasmssante.fr',
     1, 'Recette', 'BROUILLON', NULL, NULL, 'recette-mssante:ZZGROW034', now() - interval '1 day'),
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW036', 'rh@mssante.fr.exemple.com',
     1, 'Recette', 'BROUILLON', NULL, NULL, 'recette-mssante:ZZGROW036', now() - interval '1 day'),
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW037', 'rh@pasmssante.fr',
     1, 'Recette', 'BROUILLON', NULL, NULL, 'recette-mssante:ZZGROW037', now() - interval '1 day'),
    ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW038', 'rh@ehpad-recette-rejete.mssante.fr',
     1, 'Recette', 'REJETE', NULL, 'Rejeté par l''admin', 'recette-mssante:ZZGROW038', now() - interval '1 day'),
    ('REACTIVATION', 'EMAIL', 'SOIGNANT', '73000000-0000-4000-8000-000000000035', 'soignant@cabinet-recette.mssante.fr',
     NULL, 'Recette', 'BROUILLON', NULL, NULL, 'recette-mssante:ZZGROW035', now() - interval '1 day');

  -- Places du jour avant l'expiration (9.g). Précondition : aucun premier
  -- contact créé par ce passage et quota du jour limitant (file non pleine).
  SELECT count(*) INTO v_file_n FROM public.growth_brouillons
  WHERE agent = 'PROSPECTION_ETABLISSEMENT' AND statut = 'BROUILLON';
  v_res := private.fn_growth_agent_prospection();
  v_places_avant := (v_res->>'places_du_jour')::integer;
  IF (v_res->>'premiers_contacts')::integer <> 0 OR v_places_avant < 1 OR v_places_avant >= 500 - v_file_n THEN
    RAISE EXCEPTION 'MSSanté : précondition du banc de quota non remplie (aucun premier contact, quota du jour limitant) — %', v_res;
  END IF;

  v_n := private.fn_growth_expirer_brouillons_mssante();
  IF v_n < 3 THEN
    RAISE EXCEPTION 'MSSanté : l''expiration doit toucher au moins les 3 témoins MSSanté en file, % ligne(s)', v_n;
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE cible_id IN ('ZZGROW030', 'ZZGROW031') AND statut = 'EXPIRE' AND maj_le = now()
        AND motif_rejet = private.fn_growth_motif_expiration_mssante()
        AND idempotence_key = 'recette-mssante:' || cible_id || ':expire:' || id) <> 2 THEN
    RAISE EXCEPTION 'MSSanté : les brouillons MSSanté jamais validés doivent expirer avec le motif et libérer leur clé';
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE cible_id = 'ZZGROW032' AND statut = 'EXPIRE' AND maj_le = now() AND valide_le IS NOT NULL
        AND motif_rejet = private.fn_growth_motif_expiration_mssante()
        AND idempotence_key = 'recette-mssante:ZZGROW032') <> 1 THEN
    RAISE EXCEPTION 'MSSanté : un brouillon MSSanté VALIDE doit expirer avec le motif en gardant sa clé (cible exclue)';
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE cible_id IN ('ZZGROW033', 'ZZGROW034', 'ZZGROW036', 'ZZGROW037', '73000000-0000-4000-8000-000000000035')
        AND statut = 'BROUILLON' AND maj_le < now() AND motif_rejet IS NULL
        AND idempotence_key NOT LIKE '%:expire:%') <> 5
     OR (SELECT count(*) FROM public.growth_brouillons
         WHERE cible_id = 'ZZGROW038' AND statut = 'REJETE' AND maj_le < now()
           AND motif_rejet = 'Rejeté par l''admin') <> 1
     OR (SELECT count(*) FROM public.growth_brouillons
         WHERE idempotence_key = 'recette-mssante:ZZGROW020:etape1' AND statut = 'ENVOYE') <> 1 THEN
    RAISE EXCEPTION 'MSSanté : l''expiration a touché un brouillon classique, faux ami, rejeté, envoyé ou d''un autre agent';
  END IF;

  -- 9.g Quota du jour : les deux brouillons d'étape 1 du jour expirés par la
  -- correction (030 et 032) rendent leur place ; une expiration ordinaire, sans
  -- ce motif, continue de consommer le quota.
  SELECT count(*) INTO v_file_n FROM public.growth_brouillons
  WHERE agent = 'PROSPECTION_ETABLISSEMENT' AND statut = 'BROUILLON';
  v_res := private.fn_growth_agent_prospection();
  v_places_apres := (v_res->>'places_du_jour')::integer;
  IF (v_res->>'premiers_contacts')::integer <> 0 OR v_places_apres >= 500 - v_file_n
     OR v_places_apres <> v_places_avant + 2 THEN
    RAISE EXCEPTION 'MSSanté : le quota du jour doit ignorer les 2 brouillons expirés par la correction (avant %, après %) — %',
      v_places_avant, v_places_apres, v_res;
  END IF;
  UPDATE public.growth_brouillons
     SET statut = 'EXPIRE', maj_le = now(), idempotence_key = idempotence_key || ':expire:' || id
   WHERE idempotence_key = 'recette-mssante:ZZGROW033';
  SELECT count(*) INTO v_file_n FROM public.growth_brouillons
  WHERE agent = 'PROSPECTION_ETABLISSEMENT' AND statut = 'BROUILLON';
  v_res := private.fn_growth_agent_prospection();
  IF (v_res->>'premiers_contacts')::integer <> 0 OR (v_res->>'places_du_jour')::integer >= 500 - v_file_n
     OR (v_res->>'places_du_jour')::integer <> v_places_apres THEN
    RAISE EXCEPTION 'MSSanté : une expiration ordinaire doit continuer de consommer le quota du jour (attendu %) — %',
      v_places_apres, v_res;
  END IF;

  -- 9.h Décision admin : la revalidation par le prédicat unique refuse une
  -- adresse MSSanté à la validation comme au constat d'envoi ; un faux ami
  -- reste validable.
  INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, destinataire_email,
    sequence_etape, corps, statut, valide_le, idempotence_key)
  VALUES ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW041',
    'direction@ehpad-recette-tardif.mssante.fr', 1, 'Recette', 'BROUILLON', NULL, 'recette-mssante:ZZGROW041')
  RETURNING id INTO v_id_mss;
  INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, destinataire_email,
    sequence_etape, corps, statut, valide_le, contexte, idempotence_key)
  VALUES ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'CONTACT_CRM', v_contact_mss::text,
    'direction@ch-recette.mssante.fr', 2, 'Recette', 'VALIDE', now(),
    jsonb_build_object('finess', 'ZZGROW020'), 'recette-mssante:ZZGROW042')
  RETURNING id INTO v_id_mss_valide;
  SELECT id INTO v_id_faux_ami FROM public.growth_brouillons WHERE idempotence_key = 'recette-mssante:ZZGROW034';

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_res := public.fn_admin_growth_brouillon_decider(v_id_mss, 'VALIDER');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE OR v_res->>'statut' IS DISTINCT FROM 'REJETE' THEN
    RAISE EXCEPTION 'MSSanté : la validation d''un brouillon MSSanté doit le rejeter — %', v_res;
  END IF;
  v_res := public.fn_admin_growth_brouillon_decider(v_id_mss_valide, 'MARQUER_ENVOYE');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE OR v_res->>'statut' IS DISTINCT FROM 'REJETE' THEN
    RAISE EXCEPTION 'MSSanté : le constat d''envoi d''un brouillon MSSanté validé doit le rejeter — %', v_res;
  END IF;
  v_res := public.fn_admin_growth_brouillon_decider(v_id_faux_ami, 'VALIDER');
  IF v_res->>'statut' IS DISTINCT FROM 'VALIDE' THEN
    RAISE EXCEPTION 'MSSanté : un faux ami (recette-pasmssante.fr) doit rester validable — %', v_res;
  END IF;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE id IN (v_id_mss, v_id_mss_valide) AND statut = 'REJETE'
        AND motif_rejet = 'Destinataire invalide' AND envoye_le IS NULL) <> 2
     OR (SELECT sequence_etape FROM public.sales_contacts WHERE id = v_contact_mss) <> 1 THEN
    RAISE EXCEPTION 'MSSanté : rejet non persisté ou séquence CRM avancée malgré le refus';
  END IF;

  -- 10. Apicrypt (20261117060000) : messagerie de santé sécurisée et fermée,
  -- dont les adresses MSSanté sont publiées en interop-mssante.apicrypt.org.
  -- Même règle unique (fn_growth_email_mssante), donc même prédicat, même
  -- agent et même expiration ; témoins créés ici et comptés.

  -- 10.a Règle : apicrypt.org et ses sous-domaines, casse et blancs de bord
  -- ignorés ; les faux amis restent joignables.
  SELECT count(*) INTO v_n
  FROM (VALUES
    ('prenom.nom@interop-mssante.apicrypt.org', true),
    (' Prenom.Nom@INTEROP-MSSANTE.APICRYPT.ORG ', true),
    ('dr.recette@medical64.apicrypt.org', true),
    (E'contact@apicrypt.org\n', true),
    ('contact@pasapicrypt.org', false),
    ('contact@recette-pasapicrypt.org', false),
    ('contact@apicrypt.org.exemple.com', false),
    ('contact@apicrypt-org.fr', false),
    ('apicrypt.org@gmail.com', false)
  ) AS t(email, attendu)
  WHERE private.fn_growth_email_mssante(t.email) IS NOT DISTINCT FROM t.attendu;
  IF v_n <> 9 THEN
    RAISE EXCEPTION 'Apicrypt : fn_growth_email_mssante juste sur % cas sur 9', v_n;
  END IF;

  -- 10.b Prédicat unique : motif MSSANTE pour une adresse interop-mssante,
  -- aucun motif pour un faux ami.
  IF private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'ZZGROW050', 'direction@interop-mssante.apicrypt.org', NULL, NULL) IS DISTINCT FROM 'MSSANTE'
     OR private.fn_growth_destinataire_bloque('PUBLIC', NULL, ' Dr.Recette@Medical64.Apicrypt.Org ', NULL, NULL) IS DISTINCT FROM 'MSSANTE'
     OR private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'ZZGROW050', 'contact@pasapicrypt.org', NULL, NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'Apicrypt : prédicat fn_growth_destinataire_bloque inexact (motif MSSANTE, faux ami joignable)';
  END IF;

  -- 10.c Agent : le prospect interop-mssante n'est pas retenu, le faux ami l'est.
  INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, email, ville, departement, statut_sourcing)
  VALUES
    ('ZZGROW051', 'EHPAD Recette Apicrypt', 'EHPAD', 'direction@interop-mssante.apicrypt.org', 'Recetteville', 'ZZ', 'A_QUALIFIER'),
    ('ZZGROW052', 'EHPAD Recette Faux ami Apicrypt', 'EHPAD', 'contact@pasapicrypt.org', 'Recetteville', 'ZZ', 'A_QUALIFIER');
  v_res := private.fn_growth_agent_prospection();
  IF EXISTS (SELECT 1 FROM public.growth_brouillons WHERE cible_id = 'ZZGROW051') THEN
    RAISE EXCEPTION 'Apicrypt : une adresse interop-mssante.apicrypt.org a été retenue par l''agent — %', v_res;
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE cible_type = 'PROSPECT_ETABLISSEMENT' AND cible_id = 'ZZGROW052'
        AND statut = 'BROUILLON' AND sequence_etape = 1) <> 1 THEN
    RAISE EXCEPTION 'Apicrypt : le faux ami pasapicrypt.org doit être retenu — %', v_res;
  END IF;

  -- 10.d Expiration : la fonction de la migration expire un brouillon Apicrypt
  -- en file, avec le motif et la clé libérée, sans toucher au faux ami.
  INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, destinataire_email,
    sequence_etape, corps, statut, valide_le, motif_rejet, idempotence_key, maj_le)
  VALUES ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZZGROW053',
    'accueil@interop-mssante.apicrypt.org', 1, 'Recette', 'BROUILLON', NULL, NULL, 'recette-apicrypt:ZZGROW053',
    now() - interval '1 day');
  v_n := private.fn_growth_expirer_brouillons_mssante();
  IF v_n < 1
     OR (SELECT count(*) FROM public.growth_brouillons
         WHERE cible_id = 'ZZGROW053' AND statut = 'EXPIRE' AND maj_le = now()
           AND motif_rejet = private.fn_growth_motif_expiration_mssante()
           AND idempotence_key = 'recette-apicrypt:ZZGROW053:expire:' || id) <> 1
     OR (SELECT count(*) FROM public.growth_brouillons
         WHERE cible_id = 'ZZGROW052' AND statut = 'BROUILLON' AND motif_rejet IS NULL) <> 1 THEN
    RAISE EXCEPTION 'Apicrypt : le brouillon interop-mssante doit expirer avec le motif et libérer sa clé, le faux ami rester en file (% ligne(s))', v_n;
  END IF;

  -- 11. Zéro visible et liste d'appels (20261124123500). Marché fictif ZY,
  -- distinct de ZZ : chaque décompte porte sur des témoins créés ici et comptés.
  -- Un seul univers ciblé (private.fn_growth_prospects_cibles) pour l'agent
  -- email, l'agent d'appels et le décompte ; les interdits du prédicat unique
  -- valent pour l'appel, sauf le motif MSSANTE.
  UPDATE public.growth_config SET valeur = 'ZY' WHERE cle = 'agents_departements_cibles';

  -- 11.a Droits : les cinq fonctions neuves restent fermées à anon et authenticated.
  IF EXISTS (SELECT 1 FROM unnest(ARRAY[
               'private.fn_growth_prospects_cibles()', 'private.fn_growth_cibles_prospection()',
               'private.fn_growth_appel_bloque(text,text,text)', 'private.fn_growth_script_appel(text)',
               'private.fn_growth_agent_appels()']) AS f(sig)
             WHERE has_function_privilege('anon', f.sig, 'EXECUTE')
                OR has_function_privilege('authenticated', f.sig, 'EXECUTE')) THEN
    RAISE EXCEPTION 'Appels : une fonction private du lot est exécutable par anon ou authenticated';
  END IF;

  -- 11.b Décompte : dix établissements ciblés (la pharmacie est hors cible),
  -- cinq adresses en messagerie fermée, aucune adresse utilisable, neuf
  -- téléphones utilisables (un numéro trop court), sept encore disponibles
  -- (une opposition, un prospect déjà au CRM).
  INSERT INTO public.prospects_etablissements
    (finess, nom, type_jolene, email, telephone, ville, departement, statut_sourcing, ajoute_crm_le)
  VALUES
    ('ZYTEL001', 'EHPAD Appel Un', 'EHPAD', 'contact@ehpad-appel-un.mssante.fr', '01 00 00 10 01', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL002', 'Hôpital Appel Deux', 'HOPITAL', NULL, '0100001002', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL003', 'EHPAD Appel Opposition', 'EHPAD', 'direction@interop-mssante.apicrypt.org', '0100001003', 'Appelville', 'ZY', 'OPPOSITION', NULL),
    ('ZYTEL004', 'EHPAD Appel Stop numéro', 'EHPAD', NULL, '0100001004', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL005', 'Foyer Appel Standard partagé', 'HANDICAP', NULL, '01.00.00.10.02', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL006', 'EHPAD Appel Numéro court', 'EHPAD', NULL, '12345', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL007', 'Centre Appel Adresse', 'CENTRE_SANTE', 'accueil@centre-appel.mssante.fr', '0100001007', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL008', 'Pharmacie Appel', 'PHARMACIE', 'contact@pharmacie-appel.test', '0100001008', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL009', 'Institut Appel École', 'ECOLE_SANTE', NULL, '0100001009', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL010', 'EHPAD Appel Déjà au CRM', 'EHPAD', 'rh@ehpad-appel-crm.mssante.fr', '0100001010', 'Appelville', 'ZY', 'QUALIFIE', now()),
    ('ZYTEL011', 'SSIAD Appel Stop adresse', 'DOMICILE', 'stop@ssiad-appel.mssante.fr', '0100001011', 'Appelville', 'ZY', 'A_QUALIFIER', NULL);
  INSERT INTO public.sales_contacts (type, nom, email, telephone, statut, ne_plus_contacter)
  VALUES
    ('ETABLISSEMENT', 'STOP par numéro recette', NULL, '01 00 00 10 04', 'PERDU', true),
    ('ETABLISSEMENT', 'STOP par adresse recette', 'stop@ssiad-appel.mssante.fr', NULL, 'PERDU', true);

  v_cibles := private.fn_growth_cibles_prospection();
  IF v_cibles - 'departements' IS DISTINCT FROM jsonb_build_object(
       'etablissements_cibles', 10, 'adresses_fermees', 5, 'adresses_utilisables', 0, 'adresses_restantes', 0,
       'telephones_utilisables', 9, 'telephones_restants', 7)
     OR v_cibles->'departements' IS DISTINCT FROM '["ZY"]'::jsonb THEN
    RAISE EXCEPTION 'Appels : décompte des cibles inexact — %', v_cibles;
  END IF;

  -- 11.c Zéro visible : sans adresse utilisable, l'agent email ne prépare rien
  -- et le dit dans son résultat ; dès qu'une adresse ouverte existe, il la
  -- prend et il n'en reste plus.
  v_res := private.fn_growth_agent_prospection();
  IF (v_res->>'premiers_contacts')::integer <> 0 OR (v_res->>'places_du_jour')::integer < 1
     OR v_res->'cibles' IS DISTINCT FROM v_cibles THEN
    RAISE EXCEPTION 'Zéro visible : aucun premier contact attendu, places disponibles et décompte dans le résultat — %', v_res;
  END IF;
  UPDATE public.prospects_etablissements SET email = 'accueil@centre-appel.test' WHERE finess = 'ZYTEL007';
  v_res := private.fn_growth_agent_prospection();
  IF (v_res->>'premiers_contacts')::integer <> 1
     OR (v_res->'cibles'->>'adresses_utilisables')::integer <> 1
     OR (v_res->'cibles'->>'adresses_restantes')::integer <> 0
     OR (v_res->'cibles'->>'adresses_fermees')::integer <> 4
     OR (v_res->'cibles'->>'telephones_restants')::integer <> 6
     OR NOT EXISTS (SELECT 1 FROM public.growth_brouillons
                    WHERE agent = 'PROSPECTION_ETABLISSEMENT' AND canal = 'EMAIL' AND cible_id = 'ZYTEL007'
                      AND statut = 'BROUILLON' AND (contexte->'score'->>'type')::integer = 20) THEN
    RAISE EXCEPTION 'Zéro visible : l''adresse ouverte doit être prise par l''agent email et décomptée — %', v_res;
  END IF;

  -- 11.d Liste d'appels : trois fiches (EHPAD, hôpital, école). Écartés : STOP
  -- par le numéro (004), STOP par l'adresse bien que MSSanté (011), standard
  -- partagé avec 002 (005), numéro trop court (006), opposition (003), déjà
  -- au CRM (010), cible prise par l'email (007), type hors cible (008).
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'fiches_appel')::integer <> 3 OR (v_res->>'brouillons_crees')::integer <> 3
     OR (v_res->>'exclus_stop')::integer <> 2 OR (v_res->>'numeros_deja_en_file')::integer <> 1
     OR (v_res->>'places_de_la_semaine')::integer <> 30 THEN
    RAISE EXCEPTION 'Appels : 3 fiches, 2 STOP, 1 numéro déjà en file et 30 places attendus — %', v_res;
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE agent = 'APPEL_ETABLISSEMENT' AND canal = 'TELEPHONE' AND cible_type = 'PROSPECT_ETABLISSEMENT'
        AND cible_id IN ('ZYTEL001', 'ZYTEL002', 'ZYTEL009') AND statut = 'BROUILLON'
        AND destinataire_email IS NULL AND sujet IS NULL AND departement = 'ZY'
        AND expire_le > now() + interval '13 days') <> 3
     OR EXISTS (SELECT 1 FROM public.growth_brouillons
                WHERE canal = 'TELEPHONE' AND cible_id NOT IN ('ZYTEL001', 'ZYTEL002', 'ZYTEL009')) THEN
    RAISE EXCEPTION 'Appels : fiches attendues pour 001, 002 et 009 seulement';
  END IF;
  SELECT id, corps INTO v_id_tel, v_corps FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL001';
  IF (SELECT score FROM public.growth_brouillons WHERE id = v_id_tel) <> 40
     OR (SELECT contexte->>'telephone' FROM public.growth_brouillons WHERE id = v_id_tel) <> '01 00 00 10 01'
     OR (SELECT (contexte->'score'->>'type')::integer FROM public.growth_brouillons WHERE id = v_id_tel) <> 40
     OR (SELECT contexte->'score' ? 'email' FROM public.growth_brouillons WHERE id = v_id_tel) THEN
    RAISE EXCEPTION 'Appels : score (type 40, sans part email) ou numéro absent de la fiche 001';
  END IF;
  -- Script : la phrase de commission de la FAQ de l'accueil, la possibilité de
  -- ne plus être rappelé, aucune comparaison avec un autre prestataire.
  IF position('Jolene facture à l''établissement une commission de 15 % HT sur la base financière validée : honoraires HT pour une mission libérale ou rémunération brute contractuelle pour une mission salariée' IN v_corps) = 0
     OR position('Jolene ne vous rappellera plus' IN v_corps) = 0
     OR v_corps ~* '(intérim|agence)' THEN
    RAISE EXCEPTION 'Appels : script établissement inattendu — %', v_corps;
  END IF;
  SELECT corps INTO v_corps FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL009';
  IF position('jeunes diplômés' IN v_corps) = 0 OR position('gratuite pour les soignants' IN v_corps) = 0
     OR position('Jolene ne vous rappellera plus' IN v_corps) = 0
     OR position('commission' IN v_corps) > 0 OR v_corps ~ '[0-9]' THEN
    RAISE EXCEPTION 'Appels : script école inattendu — %', v_corps;
  END IF;

  -- Idempotence, puis quota de la semaine : une place, une fiche ; plus de
  -- place, plus de fiche, même s'il reste une cible.
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'fiches_appel')::integer <> 0 OR (v_res->>'places_de_la_semaine')::integer <> 27 THEN
    RAISE EXCEPTION 'Appels : second passage non idempotent ou quota de la semaine mal décompté — %', v_res;
  END IF;
  INSERT INTO public.growth_config (cle, valeur, maj_le) VALUES ('agents_appels_quota_semaine', '4', now())
  ON CONFLICT (cle) DO UPDATE SET valeur = EXCLUDED.valeur, maj_le = now();
  INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, telephone, ville, departement, statut_sourcing)
  VALUES
    ('ZYTEL012', 'EHPAD Appel Quota A', 'EHPAD', '0100001012', 'Appelville', 'ZY', 'A_QUALIFIER'),
    ('ZYTEL013', 'EHPAD Appel Quota B', 'EHPAD', '0100001013', 'Appelville', 'ZY', 'A_QUALIFIER');
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'fiches_appel')::integer <> 1 OR (v_res->>'places_de_la_semaine')::integer <> 1
     OR NOT EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL012')
     OR EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL013') THEN
    RAISE EXCEPTION 'Appels : quota de la semaine (4) : une seule fiche de plus attendue, pour 012 — %', v_res;
  END IF;
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'fiches_appel')::integer <> 0 OR (v_res->>'places_de_la_semaine')::integer <> 0
     OR EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL013') THEN
    RAISE EXCEPTION 'Appels : quota de la semaine atteint, aucune fiche attendue — %', v_res;
  END IF;

  -- 11.e Contraintes : une fiche d'appel exige un prospect établissement et un numéro.
  v_refus := false;
  BEGIN
    INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, corps, idempotence_key)
    VALUES ('APPEL_ETABLISSEMENT', 'TELEPHONE', 'PROSPECT_ETABLISSEMENT', 'ZYTEL098', 'Recette', 'recette-appel:sans-numero');
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Appels : une fiche sans numéro a été acceptée'; END IF;
  v_refus := false;
  BEGIN
    INSERT INTO public.growth_brouillons (agent, canal, cible_type, corps, contexte, idempotence_key)
    VALUES ('APPEL_ETABLISSEMENT', 'TELEPHONE', 'PUBLIC', 'Recette', '{"telephone":"0100001098"}', 'recette-appel:sans-prospect');
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Appels : une fiche sans prospect établissement a été acceptée'; END IF;

  -- 11.f Décision admin : valider, appeler soi-même, noter le résultat.
  SELECT id INTO v_id_tel_stop FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL002';
  SELECT id INTO v_id_tel_tardif FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL009';
  SELECT id INTO v_id_tel_constat FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL012';
  INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, destinataire_nom, corps, contexte, idempotence_key)
  VALUES ('APPEL_ETABLISSEMENT', 'TELEPHONE', 'PROSPECT_ETABLISSEMENT', 'ZYTEL099', 'Prospect disparu recette', 'Recette',
    '{"telephone":"0100001099"}', 'recette-appel:prospect-disparu')
  RETURNING id INTO v_id_tel_orphelin;
  INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, destinataire_email, sequence_etape, corps, idempotence_key)
  VALUES ('PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', 'ZYTEL097', 'direction@ehpad-appel-email.mssante.fr',
    1, 'Recette', 'recette-appel:email-mssante')
  RETURNING id INTO v_id_mss;
  v_appels_avant := (private.fn_growth_entonnoir(now() - interval '1 day', now() + interval '1 minute')
                       ->'prospection'->>'appels_journalises_periode')::integer;

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_refus := false;
  BEGIN
    PERFORM public.fn_admin_growth_brouillon_decider(v_id_tel, 'VALIDER');
  EXCEPTION WHEN insufficient_privilege THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Appels : un non-admin a pu valider une fiche d''appel'; END IF;
  EXECUTE 'RESET ROLE';

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_refus := false;
  BEGIN
    PERFORM public.fn_admin_growth_brouillon_decider(v_id_tel, 'MARQUER_ENVOYE', NULL, NULL, 'SANS_REPONSE');
  EXCEPTION WHEN raise_exception THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Appels : un appel a pu être noté sur une fiche non validée'; END IF;
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel, 'VALIDER');
  IF v_res->>'statut' IS DISTINCT FROM 'VALIDE' THEN
    RAISE EXCEPTION 'Appels : validation d''une fiche refusée — %', v_res;
  END IF;
  v_refus := false;
  BEGIN
    PERFORM public.fn_admin_growth_brouillon_decider(v_id_tel, 'MARQUER_ENVOYE');
  EXCEPTION WHEN raise_exception THEN v_refus := position('Résultat d''appel requis' IN SQLERRM) > 0;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Appels : un appel a pu être noté sans résultat'; END IF;
  -- Sans réponse : fiche CRM, rappel programmé, rien d'envoyé.
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel, 'MARQUER_ENVOYE', NULL, NULL, ' sans_reponse ');
  v_contact := (v_res->>'contact_crm_id')::uuid;
  IF v_res->>'statut' IS DISTINCT FROM 'ENVOYE' OR v_contact IS NULL THEN
    RAISE EXCEPTION 'Appels : constat « sans réponse » échoué — %', v_res;
  END IF;
  -- STOP au téléphone : définitif, pour tous les canaux.
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_stop, 'VALIDER');
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_stop, 'MARQUER_ENVOYE', NULL, NULL, 'STOP');
  IF v_res->>'statut' IS DISTINCT FROM 'ENVOYE' THEN
    RAISE EXCEPTION 'Appels : constat « STOP » échoué — %', v_res;
  END IF;
  EXECUTE 'RESET ROLE';

  IF NOT EXISTS (SELECT 1 FROM public.sales_contacts
                 WHERE id = v_contact AND finess = 'ZYTEL001' AND statut = 'RELANCE' AND a_rappeler IS TRUE
                   AND sequence_active IS TRUE AND prochaine_action_le > now() AND ne_plus_contacter IS NOT TRUE)
     OR NOT EXISTS (SELECT 1 FROM public.sales_taches
                    WHERE idempotence_key = 'growth:appel:' || v_id_tel AND contact_id = v_contact
                      AND canal = 'TELEPHONE' AND statut = 'TERMINEE')
     OR NOT EXISTS (SELECT 1 FROM public.sales_taches
                    WHERE contact_id = v_contact AND canal = 'TELEPHONE' AND statut = 'A_FAIRE'
                      AND idempotence_key <> 'growth:appel:' || v_id_tel)
     OR NOT EXISTS (SELECT 1 FROM public.sales_activites
                    WHERE contact_id = v_contact AND action_type = 'TACHE_TRAITEE' AND canal = 'TELEPHONE'
                      AND resultat = 'SANS_REPONSE') THEN
    RAISE EXCEPTION 'Appels : le constat « sans réponse » doit créer la fiche CRM, clore la tâche d''appel et programmer le rappel';
  END IF;
  IF (SELECT contexte->>'resultat_appel' FROM public.growth_brouillons WHERE id = v_id_tel) IS DISTINCT FROM 'SANS_REPONSE'
     OR (SELECT envoye_le FROM public.growth_brouillons WHERE id = v_id_tel) IS NULL
     OR (SELECT ajoute_crm_le FROM public.prospects_etablissements WHERE finess = 'ZYTEL001') IS NULL
     OR (SELECT email_envoye_le FROM public.prospects_etablissements WHERE finess = 'ZYTEL001') IS NOT NULL THEN
    RAISE EXCEPTION 'Appels : résultat non conservé sur la fiche, prospect non rattaché au CRM, ou email marqué envoyé à tort';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.sales_contacts
                 WHERE finess = 'ZYTEL002' AND statut = 'PERDU' AND ne_plus_contacter IS TRUE AND sequence_active IS FALSE)
     OR private.fn_growth_appel_bloque('ZYTEL002', NULL, '0100001002') IS DISTINCT FROM 'STOP'
     OR private.fn_growth_appel_bloque('ZYTEL005', NULL, '01.00.00.10.02') IS DISTINCT FROM 'STOP'
     OR private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'ZYTEL002', 'nouvelle-adresse@appel-recette.test', NULL, NULL) IS DISTINCT FROM 'STOP' THEN
    RAISE EXCEPTION 'Appels : un STOP noté au téléphone doit bloquer l''appel (FINESS et numéro partagé) et l''email';
  END IF;

  -- Opposition arrivée après la préparation de la fiche : la validation rejette et persiste.
  INSERT INTO public.sales_contacts (type, nom, telephone, statut, ne_plus_contacter)
  VALUES ('ETABLISSEMENT', 'Opposition tardive par numéro recette', '01 00 00 10 09', 'PERDU', true);
  -- Opposition arrivée entre la validation et le constat : le constat rejette, rien n'entre au CRM.
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_tardif, 'VALIDER');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE OR v_res->>'statut' IS DISTINCT FROM 'REJETE'
     OR v_res->>'raison' IS DISTINCT FROM 'Contact en opposition (STOP) ou perdu : ne pas appeler' THEN
    RAISE EXCEPTION 'Appels : une opposition tardive doit rejeter la fiche — %', v_res;
  END IF;
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_constat, 'VALIDER');
  IF v_res->>'statut' IS DISTINCT FROM 'VALIDE' THEN
    RAISE EXCEPTION 'Appels : validation de la fiche 012 refusée — %', v_res;
  END IF;
  EXECUTE 'RESET ROLE';
  UPDATE public.prospects_etablissements SET statut_sourcing = 'OPPOSITION' WHERE finess = 'ZYTEL012';
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_constat, 'MARQUER_ENVOYE', NULL, NULL, 'APPEL_REPONDU');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE OR v_res->>'statut' IS DISTINCT FROM 'REJETE' THEN
    RAISE EXCEPTION 'Appels : une opposition arrivée avant le constat doit rejeter la fiche — %', v_res;
  END IF;
  -- Prospect disparu du répertoire : fiche rejetée, sans erreur brute.
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_orphelin, 'VALIDER');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE
     OR v_res->>'raison' IS DISTINCT FROM 'Destinataire invalide : ne pas appeler' THEN
    RAISE EXCEPTION 'Appels : une fiche dont le prospect a disparu doit être rejetée — %', v_res;
  END IF;
  -- Parcours email inchangé : même refus, même texte.
  v_res := public.fn_admin_growth_brouillon_decider(v_id_mss, 'VALIDER');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE
     OR v_res->>'raison' IS DISTINCT FROM 'Destinataire invalide : aucun envoi possible' THEN
    RAISE EXCEPTION 'Appels : le refus d''un email MSSanté a changé de texte — %', v_res;
  END IF;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE id IN (v_id_tel_tardif, v_id_tel_constat) AND statut = 'REJETE'
        AND motif_rejet = 'Opposition (STOP) ou contact perdu' AND envoye_le IS NULL) <> 2
     OR EXISTS (SELECT 1 FROM public.sales_contacts WHERE finess IN ('ZYTEL009', 'ZYTEL012'))
     OR EXISTS (SELECT 1 FROM public.sales_taches
                WHERE idempotence_key IN ('growth:appel:' || v_id_tel_tardif, 'growth:appel:' || v_id_tel_constat)) THEN
    RAISE EXCEPTION 'Appels : rejet non persisté, ou fiche CRM créée malgré l''opposition';
  END IF;

  -- 11.g Orchestrateur, exécutions et rapport : l'agent d'appels est tracé, le
  -- décompte figure dans les détails de l'agent email et dans l'entonnoir figé.
  v_res := private.fn_growth_agents_executer('ADMIN');
  IF (SELECT count(*) FROM jsonb_object_keys(v_res->'agents')) <> 5
     OR v_res->'agents'->'APPEL_ETABLISSEMENT'->>'places_de_la_semaine' IS DISTINCT FROM '0'
     OR v_res->'agents'->'PROSPECTION_ETABLISSEMENT'->'cibles'->>'etablissements_cibles' IS DISTINCT FROM '12'
     OR NOT EXISTS (SELECT 1 FROM public.growth_agent_executions
                    WHERE agent = 'APPEL_ETABLISSEMENT' AND declencheur = 'ADMIN' AND erreur IS NULL
                      AND details ? 'fiches_appel')
     OR NOT EXISTS (SELECT 1 FROM public.growth_agent_executions
                    WHERE agent = 'PROSPECTION_ETABLISSEMENT' AND declencheur = 'ADMIN' AND erreur IS NULL
                      AND details->'cibles' ? 'adresses_utilisables') THEN
    RAISE EXCEPTION 'Appels : orchestrateur à 5 agents, exécution tracée et décompte dans les détails attendus — %', v_res;
  END IF;
  v_res := private.fn_growth_entonnoir(now() - interval '1 day', now() + interval '1 minute');
  IF (v_res->'prospection'->>'appels_journalises_periode')::integer <> v_appels_avant + 2
     OR v_res->'prospection'->'cibles_agent' IS DISTINCT FROM private.fn_growth_cibles_prospection() THEN
    RAISE EXCEPTION 'Appels : entonnoir sans les deux appels notés ou sans le décompte des cibles — %', v_res->'prospection';
  END IF;
  v_res := private.fn_growth_snapshot_hebdo();
  IF (SELECT donnees->'prospection'->'cibles_agent'->>'etablissements_cibles' FROM public.growth_rapports_hebdo
      WHERE semaine_debut = (v_res->>'semaine_debut')::date) IS NULL THEN
    RAISE EXCEPTION 'Appels : le rapport hebdomadaire figé ne porte pas le décompte des cibles';
  END IF;
END;
$test$;
ROLLBACK;
