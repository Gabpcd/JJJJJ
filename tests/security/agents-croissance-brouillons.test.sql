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
  v_places integer;
  v_rec record;
  v_id_pub uuid;
  v_contact_pub uuid;
  v_mention_pa text;
  v_mention_hist text;
  v_prov jsonb := jsonb_build_object(
    'source_code', 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV',
    'source_url', 'https://www.data.gouv.fr/datasets/etablissements-ehpad-esld-residences-autonomie-accueils-de-jour',
    'source_publie_le', '2020-11-11', 'source_maj_le', '2020-10-04', 'releve_le', '2026-11-24', 'classe', 'FONCTION');
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
  -- distinct de ZZ : chaque décompte porte sur des témoins créés ici (FINESS
  -- ZYTEL…) et comptés, sans dépendre de ce que le staging contient déjà.
  -- Un seul univers ciblé (private.fn_growth_prospects_cibles) pour l'agent
  -- email, l'agent d'appels et le décompte ; les interdits du prédicat unique
  -- valent pour l'appel, sauf le motif MSSANTE.
  UPDATE public.growth_config SET valeur = 'ZY' WHERE cle = 'agents_departements_cibles';
  -- Volumes neutralisés : le quota de la semaine se lit ensuite en relatif.
  INSERT INTO public.growth_config (cle, valeur, maj_le)
  VALUES ('agents_appels_quota_semaine', '200', now()), ('agents_appels_file_max', '500', now())
  ON CONFLICT (cle) DO UPDATE SET valeur = EXCLUDED.valeur, maj_le = now();

  -- 11.a Droits : les six fonctions neuves restent fermées à anon et authenticated.
  IF EXISTS (SELECT 1 FROM unnest(ARRAY[
               'private.fn_growth_telephone_national(text)',
               'private.fn_growth_prospects_cibles()', 'private.fn_growth_cibles_prospection()',
               'private.fn_growth_appel_bloque(text,text,text)', 'private.fn_growth_script_appel(text)',
               'private.fn_growth_agent_appels()']) AS f(sig)
             WHERE has_function_privilege('anon', f.sig, 'EXECUTE')
                OR has_function_privilege('authenticated', f.sig, 'EXECUTE')) THEN
    RAISE EXCEPTION 'Appels : une fonction private du lot est exécutable par anon ou authenticated';
  END IF;
  -- Forme nationale : trois écritures d'un même numéro, rien pour un champ incomplet ou double.
  SELECT count(*) INTO v_n
  FROM (VALUES
    ('01 00 00 10 01', '0100001001'), ('01.00.00.10.01', '0100001001'), ('+33 1 00 00 10 01', '0100001001'),
    ('0033 1 00 00 10 01', '0100001001'), ('33100001001', '0100001001'),
    ('+33 (0)1 00 00 10 01', '0100001001'), ('0033 (0) 1 00 00 10 01', '0100001001'),
    ('100001001', NULL), ('12345', NULL), ('01 00 00 10 01 / 01 00 00 10 02', NULL),
    ('+262 262 00 10 01', NULL), ('', NULL), (NULL, NULL)
  ) AS t(saisi, attendu)
  WHERE private.fn_growth_telephone_national(t.saisi) IS NOT DISTINCT FROM t.attendu;
  IF v_n IS DISTINCT FROM 13 THEN
    RAISE EXCEPTION 'Appels : fn_growth_telephone_national juste sur % cas sur 13', v_n;
  END IF;

  -- 11.b Décompte : quatorze établissements ciblés (la pharmacie est hors
  -- cible), six adresses en messagerie fermée, aucune adresse utilisable, douze
  -- téléphones utilisables (un numéro trop court, un champ à deux numéros),
  -- neuf encore disponibles (une opposition, un prospect daté au CRM, un
  -- contact CRM au même FINESS).
  INSERT INTO public.prospects_etablissements
    (finess, nom, type_jolene, email, telephone, ville, departement, statut_sourcing, ajoute_crm_le)
  VALUES
    ('ZYTEL001', 'EHPAD Appel Un', 'EHPAD', 'contact@ehpad-appel-un.mssante.fr', '01 00 00 10 01', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL002', 'Hôpital Appel Deux', 'HOPITAL', NULL, '0100001002', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL003', 'EHPAD Appel Opposition', 'EHPAD', 'direction@interop-mssante.apicrypt.org', '0100001003', 'Appelville', 'ZY', 'OPPOSITION', NULL),
    ('ZYTEL004', 'EHPAD Appel A1 Stop numéro', 'EHPAD', NULL, '0100001004', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL005', 'Foyer Appel Standard partagé', 'HANDICAP', NULL, '+33 1 00 00 10 02', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL006', 'EHPAD Appel Numéro court', 'EHPAD', NULL, '12345', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL007', 'Centre Appel Adresse', 'CENTRE_SANTE', 'accueil@centre-appel.mssante.fr', '0100001007', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL008', 'Pharmacie Appel', 'PHARMACIE', 'contact@pharmacie-appel.test', '0100001008', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL009', 'Institut Appel École', 'ECOLE_SANTE', NULL, '0100001009', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL010', 'EHPAD Appel Déjà au CRM', 'EHPAD', 'rh@ehpad-appel-crm.mssante.fr', '0100001010', 'Appelville', 'ZY', 'QUALIFIE', now()),
    ('ZYTEL011', 'SSIAD Appel Stop adresse', 'DOMICILE', 'stop@ssiad-appel.mssante.fr', '0100001011', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL014', 'EHPAD Appel Contact CRM existant', 'EHPAD', NULL, '0100001014', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL015', 'EHPAD Appel A2 Stop numéro international', 'EHPAD', NULL, '0100001015', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL017', 'EHPAD Appel A3 Stop adresse', 'EHPAD', 'stop-a3@ehpad-appel.mssante.fr', '0100001017', 'Appelville', 'ZY', 'A_QUALIFIER', NULL),
    ('ZYTEL018', 'EHPAD Appel Deux numéros', 'EHPAD', NULL, '01 00 00 10 18 / 01 00 00 10 19', 'Appelville', 'ZY', 'A_QUALIFIER', NULL);
  INSERT INTO public.sales_contacts (type, nom, email, telephone, finess, statut, ne_plus_contacter)
  VALUES
    ('ETABLISSEMENT', 'STOP par numéro recette', NULL, '01 00 00 10 04', NULL, 'PERDU', true),
    ('ETABLISSEMENT', 'STOP par numéro international recette', NULL, '+33 (0)1 00 00 10 15', NULL, 'PERDU', true),
    ('ETABLISSEMENT', 'STOP par adresse recette', 'stop@ssiad-appel.mssante.fr', NULL, NULL, 'PERDU', true),
    ('ETABLISSEMENT', 'STOP par adresse A3 recette', 'stop-a3@ehpad-appel.mssante.fr', NULL, NULL, 'PERDU', true),
    ('ETABLISSEMENT', 'Contact CRM existant recette', NULL, NULL, 'ZYTEL014', 'PROSPECT', false);

  v_cibles := private.fn_growth_cibles_prospection();
  IF v_cibles - 'departements' IS DISTINCT FROM jsonb_build_object(
       'etablissements_cibles', 14, 'adresses_fermees', 6, 'adresses_utilisables', 0, 'adresses_restantes', 0,
       'adresses_annuaire_public', 0,
       'telephones_utilisables', 12, 'telephones_restants', 9)
     OR v_cibles->'departements' IS DISTINCT FROM '["ZY"]'::jsonb THEN
    RAISE EXCEPTION 'Appels : décompte des cibles inexact — %', v_cibles;
  END IF;

  -- 11.c Zéro visible : sans adresse utilisable, l'agent email ne prépare rien
  -- et le dit dans son résultat ; dès qu'une adresse ouverte existe, il la
  -- prend et il n'en reste plus.
  v_res := private.fn_growth_agent_prospection();
  IF (v_res->>'premiers_contacts')::integer IS DISTINCT FROM 0
     OR COALESCE((v_res->>'places_du_jour')::integer, 0) < 1
     OR (v_res->>'places_non_pourvues')::integer IS DISTINCT FROM (v_res->>'places_du_jour')::integer
     OR v_res->'cibles' IS DISTINCT FROM v_cibles THEN
    RAISE EXCEPTION 'Zéro visible : aucun premier contact, toutes les places non pourvues et décompte dans le résultat attendus — %', v_res;
  END IF;
  UPDATE public.prospects_etablissements SET email = 'accueil@centre-appel.test' WHERE finess = 'ZYTEL007';
  v_res := private.fn_growth_agent_prospection();
  IF (v_res->>'premiers_contacts')::integer IS DISTINCT FROM 1
     OR (v_res->'cibles'->>'adresses_utilisables')::integer IS DISTINCT FROM 1
     OR (v_res->'cibles'->>'adresses_restantes')::integer IS DISTINCT FROM 0
     OR (v_res->'cibles'->>'adresses_fermees')::integer IS DISTINCT FROM 5
     OR (v_res->'cibles'->>'telephones_restants')::integer IS DISTINCT FROM 8
     OR NOT EXISTS (SELECT 1 FROM public.growth_brouillons
                    WHERE agent = 'PROSPECTION_ETABLISSEMENT' AND canal = 'EMAIL' AND cible_id = 'ZYTEL007'
                      AND statut = 'BROUILLON' AND (contexte->'score'->>'type')::integer = 20) THEN
    RAISE EXCEPTION 'Zéro visible : l''adresse ouverte doit être prise par l''agent email et décomptée — %', v_res;
  END IF;

  -- 11.d Liste d'appels : trois fiches (EHPAD, hôpital, école) sur huit cibles
  -- examinées. Écartés dans la boucle : STOP par le numéro (004), STOP noté
  -- « +33 (0) » au CRM (015), STOP par l'adresse bien que MSSanté (017 et 011),
  -- standard partagé avec 002 écrit « +33 » (005). Hors sélection : numéro
  -- court (006), deux numéros (018), opposition (003), déjà au CRM (010, 014),
  -- cible prise par l'email (007), type hors cible (008).
  v_res := private.fn_growth_agent_appels();
  v_places := (v_res->>'places_de_la_semaine')::integer;
  IF (v_res->>'fiches_appel')::integer IS DISTINCT FROM 3 OR (v_res->>'brouillons_crees')::integer IS DISTINCT FROM 3
     OR (v_res->>'exclus_stop')::integer IS DISTINCT FROM 4 OR (v_res->>'numeros_deja_en_file')::integer IS DISTINCT FROM 1
     OR (v_res->>'candidats_examines')::integer IS DISTINCT FROM 8
     OR COALESCE(v_places, 0) < 3
     OR (v_res->>'places_non_pourvues')::integer IS DISTINCT FROM v_places - 3
     -- Ce qui borne la liste est dit : fiches de la semaine sur le quota, fiches en file sur le plafond.
     OR (v_res->>'fiches_de_la_semaine')::integer IS DISTINCT FROM (v_res->>'quota_semaine')::integer - v_places + 3
     OR (v_res->>'file_max')::integer IS DISTINCT FROM 500
     OR COALESCE((v_res->>'fiches_en_file')::integer, 0) < 3 THEN
    RAISE EXCEPTION 'Appels : 3 fiches, 4 STOP, 1 numéro déjà en file sur 8 cibles examinées attendus — %', v_res;
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons
      WHERE agent = 'APPEL_ETABLISSEMENT' AND canal = 'TELEPHONE' AND cible_type = 'PROSPECT_ETABLISSEMENT'
        AND cible_id IN ('ZYTEL001', 'ZYTEL002', 'ZYTEL009') AND statut = 'BROUILLON'
        AND destinataire_email IS NULL AND sujet IS NULL AND departement = 'ZY'
        AND expire_le > now() + interval '13 days') IS DISTINCT FROM 3
     OR EXISTS (SELECT 1 FROM public.growth_brouillons
                WHERE canal = 'TELEPHONE' AND cible_id LIKE 'ZYTEL%'
                  AND cible_id NOT IN ('ZYTEL001', 'ZYTEL002', 'ZYTEL009')) THEN
    RAISE EXCEPTION 'Appels : fiches attendues pour 001, 002 et 009 seulement';
  END IF;
  SELECT id, corps INTO v_id_tel, v_corps FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL001';
  IF (SELECT score FROM public.growth_brouillons WHERE id = v_id_tel) IS DISTINCT FROM 40
     OR (SELECT contexte->>'telephone' FROM public.growth_brouillons WHERE id = v_id_tel) IS DISTINCT FROM '01 00 00 10 01'
     OR (SELECT (contexte->'score'->>'type')::integer FROM public.growth_brouillons WHERE id = v_id_tel) IS DISTINCT FROM 40
     OR (SELECT contexte->>'source' FROM public.growth_brouillons WHERE id = v_id_tel) IS NULL
     OR (SELECT contexte->'score' ? 'email' FROM public.growth_brouillons WHERE id = v_id_tel) IS NOT FALSE THEN
    RAISE EXCEPTION 'Appels : score (type 40, sans part email), numéro ou source absents de la fiche 001';
  END IF;
  -- Script : la phrase de commission de la FAQ de l'accueil, la possibilité de
  -- ne plus être rappelé, aucune comparaison avec un autre prestataire.
  IF COALESCE(position('Jolene facture à l''établissement une commission de 15 % HT sur la base financière validée : honoraires HT pour une mission libérale ou rémunération brute contractuelle pour une mission salariée' IN v_corps), 0) = 0
     OR COALESCE(position('publié dans les annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé)' IN v_corps), 0) = 0
     OR COALESCE(position('Jolene ne vous rappellera plus' IN v_corps), 0) = 0
     OR v_corps ~* '(intérim|agence)' THEN
    RAISE EXCEPTION 'Appels : script établissement inattendu — %', v_corps;
  END IF;
  SELECT corps INTO v_corps FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL009';
  IF COALESCE(position('jeunes diplômés' IN v_corps), 0) = 0 OR COALESCE(position('gratuite pour les soignants' IN v_corps), 0) = 0
     OR COALESCE(position('publié dans les annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé)' IN v_corps), 0) = 0
     OR COALESCE(position('Jolene ne vous rappellera plus' IN v_corps), 0) = 0
     OR position('commission' IN v_corps) > 0 OR v_corps ~ '[0-9]' THEN
    RAISE EXCEPTION 'Appels : script école inattendu — %', v_corps;
  END IF;

  -- Idempotence : rien de plus, trois places de moins.
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'fiches_appel')::integer IS DISTINCT FROM 0
     OR (v_res->>'places_de_la_semaine')::integer IS DISTINCT FROM v_places - 3 THEN
    RAISE EXCEPTION 'Appels : second passage non idempotent ou quota de la semaine mal décompté — %', v_res;
  END IF;
  -- Une seule place, et une tête de classement entièrement écartée (004, 015 et
  -- 017, trois STOP) : la fiche va à la quatrième cible. Une sélection bornée à
  -- trois fois les places ne l'aurait jamais atteinte.
  SELECT count(*) INTO v_n FROM public.growth_brouillons
  WHERE agent = 'APPEL_ETABLISSEMENT'
    AND cree_le >= date_trunc('week', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris';
  UPDATE public.growth_config SET valeur = (v_n + 1)::text WHERE cle = 'agents_appels_quota_semaine';
  INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, telephone, ville, departement, statut_sourcing)
  VALUES
    ('ZYTEL012', 'EHPAD Appel Quota A', 'EHPAD', '0100001012', 'Appelville', 'ZY', 'A_QUALIFIER'),
    ('ZYTEL013', 'EHPAD Appel Quota B', 'EHPAD', '0100001013', 'Appelville', 'ZY', 'A_QUALIFIER');
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'fiches_appel')::integer IS DISTINCT FROM 1 OR (v_res->>'places_de_la_semaine')::integer IS DISTINCT FROM 1
     OR (v_res->>'exclus_stop')::integer IS DISTINCT FROM 3 OR (v_res->>'candidats_examines')::integer IS DISTINCT FROM 4
     OR (v_res->>'places_non_pourvues')::integer IS DISTINCT FROM 0
     OR NOT EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL012')
     OR EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL013') THEN
    RAISE EXCEPTION 'Appels : une place, trois cibles écartées en tête, la fiche attendue pour 012 — %', v_res;
  END IF;
  -- Quota de la semaine atteint : plus de fiche, même s'il reste une cible.
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'fiches_appel')::integer IS DISTINCT FROM 0 OR (v_res->>'places_de_la_semaine')::integer IS DISTINCT FROM 0
     OR (v_res->>'candidats_examines')::integer IS DISTINCT FROM 0
     OR EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL013') THEN
    RAISE EXCEPTION 'Appels : quota de la semaine atteint, aucune fiche attendue — %', v_res;
  END IF;

  -- 11.e Contraintes : une fiche d'appel exige un prospect établissement et un numéro complet.
  FOR v_rec IN
    SELECT * FROM (VALUES
      ('sans numéro', 'PROSPECT_ETABLISSEMENT', 'ZYTEL098', '{}'::jsonb),
      ('numéro à neuf chiffres', 'PROSPECT_ETABLISSEMENT', 'ZYTEL098', '{"telephone":"123456789"}'::jsonb),
      ('sans prospect établissement', 'PUBLIC', NULL, '{"telephone":"0100001098"}'::jsonb)
    ) AS t(cas, cible_type, cible_id, contexte)
  LOOP
    v_refus := false;
    BEGIN
      INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, corps, contexte, idempotence_key)
      VALUES ('APPEL_ETABLISSEMENT', 'TELEPHONE', v_rec.cible_type, v_rec.cible_id, 'Recette', v_rec.contexte,
              'recette-appel:contrainte:' || v_rec.cas);
    EXCEPTION WHEN check_violation THEN v_refus := true;
    END;
    IF NOT v_refus THEN RAISE EXCEPTION 'Appels : une fiche % a été acceptée', v_rec.cas; END IF;
  END LOOP;

  -- 11.f Décision admin : valider, appeler soi-même, noter le résultat.
  -- Témoins des cas de décision, préparés comme le ferait l'agent.
  INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, telephone, ville, departement, statut_sourcing)
  SELECT 'ZYTEL0' || n, 'EHPAD Appel Décision ' || n, 'EHPAD', '01000010' || n, 'Appelville', 'ZY', 'A_QUALIFIER'
  FROM generate_series(20, 28) AS n;
  INSERT INTO public.growth_brouillons (agent, canal, cible_type, cible_id, destinataire_nom, departement, corps, contexte, score, idempotence_key, expire_le)
  SELECT 'APPEL_ETABLISSEMENT', 'TELEPHONE', 'PROSPECT_ETABLISSEMENT', 'ZYTEL0' || n, 'EHPAD Appel Décision ' || n, 'ZY',
         private.fn_growth_script_appel('EHPAD'), jsonb_build_object('telephone', '01000010' || n, 'type_etablissement', 'EHPAD'),
         40, 'appel:ZYTEL0' || n, CASE WHEN n = 28 THEN now() - interval '1 minute' ELSE now() + interval '14 days' END
  FROM generate_series(20, 28) AS n;
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
                       ->'prospection'->>'fiches_appel_notees_periode')::integer;
  IF v_appels_avant IS NULL THEN
    RAISE EXCEPTION 'Appels : l''entonnoir ne compte pas les fiches d''appel notées';
  END IF;

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
  -- Rejouable : l'écran revalide à chaque demande d'appel.
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel, 'VALIDER');
  IF v_res->>'statut' IS DISTINCT FROM 'VALIDE' OR (v_res->>'success')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'Appels : la revérification d''une fiche validée doit réussir — %', v_res;
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
  -- Les quatre autres résultats, chacun sur sa fiche.
  FOR v_rec IN
    SELECT b.id, t.resultat FROM (VALUES ('ZYTEL024', 'INTERESSE'), ('ZYTEL025', 'A_RAPPELER'),
                                         ('ZYTEL026', 'APPEL_REPONDU'), ('ZYTEL027', 'PAS_INTERESSE')) AS t(finess, resultat)
    JOIN public.growth_brouillons b ON b.canal = 'TELEPHONE' AND b.cible_id = t.finess
  LOOP
    v_res := public.fn_admin_growth_brouillon_decider(v_rec.id, 'VALIDER');
    v_res := public.fn_admin_growth_brouillon_decider(v_rec.id, 'MARQUER_ENVOYE', NULL, NULL, v_rec.resultat);
    IF v_res->>'statut' IS DISTINCT FROM 'ENVOYE' THEN
      RAISE EXCEPTION 'Appels : constat « % » échoué — %', v_rec.resultat, v_res;
    END IF;
  END LOOP;
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
     OR private.fn_growth_appel_bloque('ZYTEL005', NULL, '+33 1 00 00 10 02') IS DISTINCT FROM 'STOP'
     OR private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'ZYTEL002', 'nouvelle-adresse@appel-recette.test', NULL, NULL) IS DISTINCT FROM 'STOP' THEN
    RAISE EXCEPTION 'Appels : un STOP noté au téléphone doit bloquer l''appel (FINESS et numéro partagé) et l''email';
  END IF;
  -- Un refus est aussi porté par le prospect : il ne dépend pas du seul contact CRM.
  IF (SELECT count(*) FROM public.prospects_etablissements pe
      WHERE (pe.finess IN ('ZYTEL002', 'ZYTEL027') AND pe.statut_sourcing = 'OPPOSITION')
         OR (pe.finess IN ('ZYTEL001', 'ZYTEL024', 'ZYTEL025', 'ZYTEL026') AND pe.statut_sourcing = 'QUALIFIE')
     ) IS DISTINCT FROM 6 THEN
    RAISE EXCEPTION 'Appels : après « STOP » ou « pas intéressé » le prospect doit être en opposition, après un autre résultat seulement rattaché au CRM';
  END IF;
  IF (SELECT count(*) FROM public.sales_contacts sc
      WHERE (sc.finess = 'ZYTEL024' AND sc.statut = 'CONTACTE' AND sc.reponse = 'POSITIVE' AND sc.a_rappeler IS TRUE AND sc.sequence_active IS TRUE)
         OR (sc.finess = 'ZYTEL025' AND sc.statut = 'PROSPECT' AND sc.a_rappeler IS TRUE AND sc.sequence_active IS TRUE AND sc.prochaine_action_le > now())
         OR (sc.finess = 'ZYTEL026' AND sc.statut = 'CONTACTE' AND sc.reponse = 'EN_ATTENTE' AND sc.a_rappeler IS TRUE)
         OR (sc.finess = 'ZYTEL027' AND sc.statut = 'PERDU' AND sc.reponse = 'NEGATIVE' AND sc.ne_plus_contacter IS TRUE AND sc.sequence_active IS FALSE)
     ) IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'Appels : états CRM inattendus après « intéressé », « à rappeler », « a répondu » ou « pas intéressé » — %',
      (SELECT jsonb_agg(jsonb_build_object('finess', sc.finess, 'statut', sc.statut, 'reponse', sc.reponse, 'a_rappeler', sc.a_rappeler))
       FROM public.sales_contacts sc WHERE sc.finess IN ('ZYTEL024', 'ZYTEL025', 'ZYTEL026', 'ZYTEL027'));
  END IF;

  -- Oppositions et changements arrivés après la préparation des fiches.
  INSERT INTO public.sales_contacts (type, nom, telephone, statut, ne_plus_contacter)
  VALUES ('ETABLISSEMENT', 'Opposition tardive par numéro recette', '+33 1 00 00 10 09', 'PERDU', true);
  INSERT INTO public.sales_contacts (type, nom, finess, statut)
  VALUES ('ETABLISSEMENT', 'Contact créé après la fiche recette', 'ZYTEL022', 'PROSPECT');
  UPDATE public.prospects_etablissements SET telephone = '01 00 00 10 93' WHERE finess = 'ZYTEL023';
  EXECUTE 'SET LOCAL ROLE authenticated';
  -- Avant la première validation : la fiche est rejetée, le rejet persiste.
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_tardif, 'VALIDER');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE OR v_res->>'statut' IS DISTINCT FROM 'REJETE'
     OR v_res->>'raison' IS DISTINCT FROM 'Contact en opposition (STOP) ou perdu : ne pas appeler' THEN
    RAISE EXCEPTION 'Appels : une opposition tardive doit rejeter la fiche — %', v_res;
  END IF;
  -- Établissement entré au CRM entre-temps : il se traite depuis le CRM.
  v_res := public.fn_admin_growth_brouillon_decider(
    (SELECT id FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL022'), 'VALIDER');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE
     OR v_res->>'raison' IS DISTINCT FROM 'Établissement déjà suivi au CRM, déjà inscrit ou écarté : ne pas appeler' THEN
    RAISE EXCEPTION 'Appels : une cible entrée au CRM après la préparation doit être refusée — %', v_res;
  END IF;
  -- Numéro modifié dans l'annuaire : la fiche le suit.
  v_res := public.fn_admin_growth_brouillon_decider(
    (SELECT id FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL023'), 'VALIDER');
  IF v_res->>'statut' IS DISTINCT FROM 'VALIDE' OR v_res->>'telephone' IS DISTINCT FROM '01 00 00 10 93' THEN
    RAISE EXCEPTION 'Appels : une fiche dont le numéro a changé doit rester validable et rendre le nouveau numéro — %', v_res;
  END IF;
  -- Opposition entre la validation et l'appel : la demande d'appel la voit AVANT l'appel.
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_constat, 'VALIDER');
  IF v_res->>'statut' IS DISTINCT FROM 'VALIDE' THEN
    RAISE EXCEPTION 'Appels : validation de la fiche 012 refusée — %', v_res;
  END IF;
  v_res := public.fn_admin_growth_brouillon_decider(
    (SELECT id FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL020'), 'VALIDER');
  v_res := public.fn_admin_growth_brouillon_decider(
    (SELECT id FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL021'), 'VALIDER');
  EXECUTE 'RESET ROLE';
  UPDATE public.prospects_etablissements SET statut_sourcing = 'OPPOSITION' WHERE finess IN ('ZYTEL012', 'ZYTEL020', 'ZYTEL021');
  INSERT INTO public.sales_contacts (type, nom, finess, statut)
  VALUES ('ETABLISSEMENT', 'Inscrit entre l''appel et la note recette', 'ZYTEL023', 'INSCRIT');
  EXECUTE 'SET LOCAL ROLE authenticated';
  -- Établissement entré au CRM (ici déjà inscrit) entre l'appel et la note : un résultat ordinaire
  -- ne réécrit pas son suivi.
  v_res := public.fn_admin_growth_brouillon_decider(
    (SELECT id FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL023'),
    'MARQUER_ENVOYE', NULL, NULL, 'SANS_REPONSE');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE OR v_res->>'statut' IS DISTINCT FROM 'REJETE'
     OR v_res->>'raison' IS DISTINCT FROM 'Établissement déjà suivi au CRM, déjà inscrit ou écarté : appel non enregistré au CRM' THEN
    RAISE EXCEPTION 'Appels : un résultat ordinaire sur une cible entrée au CRM depuis l''appel doit être refusé — %', v_res;
  END IF;
  v_res := public.fn_admin_growth_brouillon_decider(v_id_tel_constat, 'VALIDER');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE OR v_res->>'statut' IS DISTINCT FROM 'REJETE'
     OR v_res->>'raison' IS DISTINCT FROM 'Contact en opposition (STOP) ou perdu : ne pas appeler' THEN
    RAISE EXCEPTION 'Appels : une opposition arrivée après la validation doit être vue à la demande d''appel — %', v_res;
  END IF;
  -- Opposition arrivée pendant l'appel : un résultat ordinaire n'entre pas au
  -- CRM mais reste lisible sur la fiche ; un refus entendu est enregistré.
  v_res := public.fn_admin_growth_brouillon_decider(
    (SELECT id FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL020'),
    'MARQUER_ENVOYE', NULL, NULL, 'APPEL_REPONDU');
  IF COALESCE((v_res->>'success')::boolean, true) IS NOT FALSE OR v_res->>'statut' IS DISTINCT FROM 'REJETE'
     OR v_res->>'raison' IS DISTINCT FROM 'Contact en opposition (STOP) ou perdu : appel non enregistré au CRM' THEN
    RAISE EXCEPTION 'Appels : un résultat ordinaire sur une cible passée en opposition doit être refusé au CRM — %', v_res;
  END IF;
  v_res := public.fn_admin_growth_brouillon_decider(
    (SELECT id FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL021'),
    'MARQUER_ENVOYE', NULL, NULL, 'STOP');
  IF v_res->>'statut' IS DISTINCT FROM 'ENVOYE' OR (v_res->>'contact_crm_id') IS NULL THEN
    RAISE EXCEPTION 'Appels : un refus entendu au téléphone doit toujours être enregistré — %', v_res;
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
        AND motif_rejet = 'Opposition (STOP) ou contact perdu' AND envoye_le IS NULL) IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM public.sales_contacts WHERE finess IN ('ZYTEL009', 'ZYTEL012', 'ZYTEL020'))
     OR EXISTS (SELECT 1 FROM public.sales_taches WHERE idempotence_key = 'growth:appel:' || (
                  SELECT id FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL023'))
     OR EXISTS (SELECT 1 FROM public.sales_taches
                WHERE idempotence_key IN ('growth:appel:' || v_id_tel_tardif, 'growth:appel:' || v_id_tel_constat)) THEN
    RAISE EXCEPTION 'Appels : rejet non persisté, ou fiche CRM créée malgré l''opposition';
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons b
      WHERE b.canal = 'TELEPHONE'
        AND ((b.cible_id = 'ZYTEL020' AND b.statut = 'REJETE' AND b.contexte->>'resultat_appel' = 'APPEL_REPONDU')
          OR (b.cible_id = 'ZYTEL021' AND b.statut = 'ENVOYE' AND b.contexte->>'resultat_appel' = 'STOP')
          OR (b.cible_id = 'ZYTEL022' AND b.statut = 'REJETE' AND b.motif_rejet = 'Établissement déjà suivi au CRM, déjà inscrit ou écarté')
          OR (b.cible_id = 'ZYTEL023' AND b.statut = 'REJETE' AND b.contexte->>'telephone' = '01 00 00 10 93'
              AND b.contexte->>'resultat_appel' = 'SANS_REPONSE'))
     ) IS DISTINCT FROM 4
     OR NOT EXISTS (SELECT 1 FROM public.sales_contacts
                    WHERE finess = 'ZYTEL021' AND statut = 'PERDU' AND ne_plus_contacter IS TRUE)
     OR (SELECT statut_sourcing FROM public.prospects_etablissements WHERE finess = 'ZYTEL021') IS DISTINCT FROM 'OPPOSITION'
     OR (SELECT statut FROM public.sales_contacts WHERE finess = 'ZYTEL023') IS DISTINCT FROM 'INSCRIT'
     OR private.fn_growth_appel_bloque('ZYTEL021', NULL, NULL) IS DISTINCT FROM 'STOP' THEN
    RAISE EXCEPTION 'Appels : résultat perdu au constat refusé, refus entendu non enregistré, cible déjà suivie acceptée ou numéro non suivi';
  END IF;

  -- Une fiche rejetée ferme aussi son numéro : un autre établissement au même
  -- standard n'est pas proposé (030 partage le numéro de 012, fiche rejetée),
  -- pendant qu'une cible libre reçoit sa fiche (013).
  UPDATE public.growth_config SET valeur = '200' WHERE cle = 'agents_appels_quota_semaine';
  INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, telephone, ville, departement, statut_sourcing)
  VALUES ('ZYTEL030', 'EHPAD Appel Standard de 012', 'EHPAD', '01 00 00 10 12', 'Appelville', 'ZY', 'A_QUALIFIER');
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'fiches_appel')::integer IS DISTINCT FROM 1
     -- 030 seul : 005 partage le numéro de 002, désormais en STOP, et compte parmi les cinq oppositions.
     OR (v_res->>'numeros_deja_en_file')::integer IS DISTINCT FROM 1
     OR (v_res->>'exclus_stop')::integer IS DISTINCT FROM 5
     OR NOT EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL013' AND statut = 'BROUILLON')
     OR EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL030') THEN
    RAISE EXCEPTION 'Appels : le numéro d''une fiche rejetée ne doit pas être reproposé par un autre établissement — %', v_res;
  END IF;
  -- Plus aucune place pour la suite : l'orchestrateur ne doit rien ajouter.
  UPDATE public.growth_config SET valeur = '0' WHERE cle = 'agents_appels_quota_semaine';

  -- 11.g Orchestrateur, exécutions et rapport : l'agent d'appels est tracé, le
  -- décompte figure dans les détails de l'agent email et dans l'entonnoir figé ;
  -- une fiche jamais validée qui expire libère sa cible.
  v_res := private.fn_growth_agents_executer('ADMIN');
  IF (SELECT count(*) FROM jsonb_object_keys(v_res->'agents')) IS DISTINCT FROM 5
     OR v_res->'agents'->'APPEL_ETABLISSEMENT'->>'places_de_la_semaine' IS DISTINCT FROM '0'
     OR v_res->'agents'->'PROSPECTION_ETABLISSEMENT'->'cibles'->>'etablissements_cibles' IS DISTINCT FROM '26'
     OR NOT EXISTS (SELECT 1 FROM public.growth_agent_executions
                    WHERE agent = 'APPEL_ETABLISSEMENT' AND declencheur = 'ADMIN' AND erreur IS NULL
                      AND details ? 'fiches_appel' AND details ? 'places_non_pourvues')
     OR NOT EXISTS (SELECT 1 FROM public.growth_agent_executions
                    WHERE agent = 'PROSPECTION_ETABLISSEMENT' AND declencheur = 'ADMIN' AND erreur IS NULL
                      AND details->'cibles' ? 'adresses_utilisables' AND details ? 'places_non_pourvues') THEN
    RAISE EXCEPTION 'Appels : orchestrateur à 5 agents, exécution tracée et décompte dans les détails attendus — %', v_res;
  END IF;
  IF (SELECT statut FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZYTEL028') IS DISTINCT FROM 'EXPIRE'
     OR (SELECT c.disponible FROM private.fn_growth_prospects_cibles() c WHERE c.finess = 'ZYTEL028') IS NOT TRUE
     OR (SELECT c.disponible FROM private.fn_growth_prospects_cibles() c WHERE c.finess = 'ZYTEL012') IS NOT FALSE THEN
    RAISE EXCEPTION 'Appels : une fiche jamais validée puis expirée doit libérer sa cible, une fiche rejetée non';
  END IF;
  v_res := private.fn_growth_entonnoir(now() - interval '1 day', now() + interval '1 minute');
  IF (v_res->'prospection'->>'fiches_appel_notees_periode')::integer IS DISTINCT FROM v_appels_avant + 7
     OR v_res->'prospection'->'cibles_agent' IS DISTINCT FROM private.fn_growth_cibles_prospection() THEN
    RAISE EXCEPTION 'Appels : entonnoir sans les sept fiches d''appel notées ou sans le décompte des cibles — %', v_res->'prospection';
  END IF;
  v_res := private.fn_growth_snapshot_hebdo();
  IF (SELECT donnees->'prospection'->'cibles_agent'->>'etablissements_cibles' FROM public.growth_rapports_hebdo
      WHERE semaine_debut = (v_res->>'semaine_debut')::date) IS NULL THEN
    RAISE EXCEPTION 'Appels : le rapport hebdomadaire figé ne porte pas le décompte des cibles';
  END IF;

  -- 12. Adresses publiques de l'annuaire des établissements pour personnes
  -- âgées (20261124170000). Marché fictif ZX : sept témoins créés ici. La
  -- provenance ne vaut que pour l'adresse qu'elle décrit ; la mention
  -- d'opposition suit l'origine de l'adresse, au premier contact comme à la
  -- relance ; une origine sans mention ne reçoit aucun brouillon ; les fiches
  -- d'appel vont d'abord aux établissements qu'aucun email ne peut joindre.
  UPDATE public.growth_config SET valeur = 'ZX' WHERE cle = 'agents_departements_cibles';
  UPDATE public.growth_config SET valeur = '100' WHERE cle = 'agents_prospection_quota_jour';
  UPDATE public.growth_config SET valeur = '500' WHERE cle = 'agents_prospection_file_max';
  v_mention_hist := private.fn_growth_config('prospection_mention_opposition', NULL);

  -- 12.a Droits : les deux fonctions neuves restent fermées à anon et authenticated.
  IF EXISTS (SELECT 1 FROM unnest(ARRAY[
               'private.fn_growth_email_source(text,text)',
               'private.fn_growth_mention_opposition(text,text)']) AS f(sig)
             WHERE has_function_privilege('anon', f.sig, 'EXECUTE')
                OR has_function_privilege('authenticated', f.sig, 'EXECUTE')) THEN
    RAISE EXCEPTION 'Adresses publiques : une fonction private du lot est exécutable par anon ou authenticated';
  END IF;

  -- 12.b Forme de la provenance : sans page source ni date de relevé, ou pour une
  -- adresse en messagerie fermée, la ligne est refusée.
  v_refus := false;
  BEGIN
    INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, email, departement, email_provenance)
    VALUES ('ZXPUB098', 'EHPAD Provenance incomplète', 'EHPAD', 'contact@ehpad-incomplet.test', 'ZX',
            jsonb_build_object('email', 'contact@ehpad-incomplet.test', 'source_code', 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV'));
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Adresses publiques : une provenance sans page source ni date de relevé a été acceptée'; END IF;
  v_refus := false;
  BEGIN
    INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, email, departement, email_provenance)
    VALUES ('ZXPUB099', 'EHPAD Provenance fermée', 'EHPAD', 'contact@ehpad-ferme.mssante.fr', 'ZX',
            v_prov || jsonb_build_object('email', 'contact@ehpad-ferme.mssante.fr'));
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Adresses publiques : une provenance en messagerie fermée a été acceptée'; END IF;
  -- Seule une saisie manuelle se passe de page source.
  v_refus := false;
  BEGIN
    INSERT INTO public.prospects_etablissements (finess, nom, type_jolene, email, departement, email_provenance)
    VALUES ('ZXPUB097', 'EHPAD Provenance sans page', 'EHPAD', 'contact@ehpad-sans-page.test', 'ZX',
            jsonb_build_object('email', 'contact@ehpad-sans-page.test', 'source_code', 'AUTRE_SOURCE', 'releve_le', '2026-11-24'));
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Adresses publiques : une provenance sans page source, hors saisie manuelle, a été acceptée'; END IF;

  -- 12.c Témoins : 001 adresse de l'annuaire (elle remplace une adresse fermée),
  -- 002 adresse sans provenance, 003 adresse changée depuis l'import (la
  -- provenance décrit une autre adresse), 004 origine que le code ne connaît
  -- pas, 005 même adresse de groupe que 001, 006 hôpital sans adresse (moins
  -- de points qu'un EHPAD, mais joignable par téléphone seulement), 007 adresse
  -- saisie à la main dans l'écran Sales (provenance SAISIE_MANUELLE, sans page).
  INSERT INTO public.prospects_etablissements
    (finess, nom, type_jolene, email, telephone, ville, departement, email_provenance)
  VALUES
    ('ZXPUB001', 'EHPAD Public Un', 'EHPAD', 'contact@ehpad-public-un.test', '01 00 00 20 01', 'Publicville', 'ZX',
     v_prov || jsonb_build_object('email', 'contact@ehpad-public-un.test', 'remplace', 'contact@ehpad-public-un.mssante.fr')),
    ('ZXPUB002', 'EHPAD Public Deux sans provenance', 'EHPAD', 'accueil@ehpad-public-deux.test', NULL, 'Publicville', 'ZX', NULL),
    ('ZXPUB003', 'EHPAD Public Trois adresse changée', 'EHPAD', 'direction@ehpad-public-trois.test', NULL, 'Publicville', 'ZX',
     v_prov || jsonb_build_object('email', 'contact@ehpad-public-trois.test')),
    ('ZXPUB004', 'EHPAD Public Quatre origine inconnue', 'EHPAD', 'contact@ehpad-public-quatre.test', NULL, 'Publicville', 'ZX',
     v_prov || jsonb_build_object('email', 'contact@ehpad-public-quatre.test', 'source_code', 'SOURCE_SANS_MENTION')),
    ('ZXPUB005', 'EHPAD Public Cinq adresse de groupe', 'EHPAD', 'contact@ehpad-public-un.test', NULL, 'Publicville', 'ZX',
     v_prov || jsonb_build_object('email', 'contact@ehpad-public-un.test')),
    ('ZXPUB006', 'Hôpital Public Six sans adresse', 'HOPITAL', NULL, '01 00 00 20 06', 'Publicville', 'ZX', NULL),
    ('ZXPUB007', 'EHPAD Public Sept adresse saisie', 'EHPAD', 'accueil@ehpad-public-sept.test', NULL, 'Publicville', 'ZX',
     jsonb_build_object('email', 'accueil@ehpad-public-sept.test', 'source_code', 'SAISIE_MANUELLE', 'releve_le', '2026-11-24'));

  v_cibles := private.fn_growth_cibles_prospection();
  IF (v_cibles->>'etablissements_cibles')::integer IS DISTINCT FROM 7
     OR (v_cibles->>'adresses_utilisables')::integer IS DISTINCT FROM 6
     OR (v_cibles->>'adresses_restantes')::integer IS DISTINCT FROM 6
     OR (v_cibles->>'adresses_fermees')::integer IS DISTINCT FROM 0
     -- 001, 004 et 005 : la provenance décrit l'adresse du prospect ; pas 003,
     -- et 007 est une saisie manuelle, pas un annuaire.
     OR (v_cibles->>'adresses_annuaire_public')::integer IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'Adresses publiques : décompte inexact — %', v_cibles;
  END IF;

  -- 12.c bis Liste d'appels : une seule place. Elle va à l'hôpital sans adresse
  -- (35 points), pas à l'EHPAD 001 (40 points, téléphone) que l'agent email
  -- peut joindre ; 001 reste libre pour l'email.
  UPDATE public.growth_config
     SET valeur = ((SELECT count(*) FROM public.growth_brouillons b
                    WHERE b.agent = 'APPEL_ETABLISSEMENT'
                      AND b.cree_le >= date_trunc('week', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris') + 1)::text
   WHERE cle = 'agents_appels_quota_semaine';
  v_res := private.fn_growth_agent_appels();
  IF (v_res->>'places_de_la_semaine')::integer IS DISTINCT FROM 1
     OR (v_res->>'fiches_appel')::integer IS DISTINCT FROM 1
     OR NOT EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZXPUB006' AND statut = 'BROUILLON')
     OR EXISTS (SELECT 1 FROM public.growth_brouillons WHERE canal = 'TELEPHONE' AND cible_id = 'ZXPUB001')
     OR (SELECT c.disponible FROM private.fn_growth_prospects_cibles() c WHERE c.finess = 'ZXPUB001') IS NOT TRUE THEN
    RAISE EXCEPTION 'Adresses publiques : la fiche d''appel doit aller à l''établissement sans adresse utilisable, pas à l''EHPAD joignable par email — %', v_res;
  END IF;
  UPDATE public.growth_config SET valeur = '0' WHERE cle = 'agents_appels_quota_semaine';

  -- 12.d Origine et mention : la provenance se lit sans égard à la casse ni aux
  -- blancs ; elle ne vaut pas pour une autre adresse, ni sans FINESS. La mention
  -- historique reste celle des établissements sans aucune provenance. Dès que
  -- le prospect en porte une, une adresse qu'elle ne décrit pas (changée depuis
  -- l'import : 003) n'a pas de mention ; une adresse saisie à la main (007) non plus.
  v_mention_pa := private.fn_growth_mention_opposition('ZXPUB001', 'contact@ehpad-public-un.test');
  IF v_mention_hist IS NULL OR v_mention_pa IS NULL
     OR v_mention_pa IS NOT DISTINCT FROM v_mention_hist
     OR position('pour-les-personnes-agees.gouv.fr' IN v_mention_pa) = 0
     OR position('Annuaire Santé' IN v_mention_pa) > 0
     OR position('« STOP »' IN v_mention_pa) = 0
     -- La phrase d'opposition est la même, mot pour mot ; seule l'origine déclarée change.
     OR split_part(v_mention_pa, '). ', 2) IS DISTINCT FROM split_part(v_mention_hist, '). ', 2)
     OR split_part(v_mention_hist, '). ', 2) NOT LIKE 'Si vous ne souhaitez plus%'
     OR private.fn_growth_email_source('ZXPUB001', '  Contact@EHPAD-Public-Un.test ')->>'source_code'
        IS DISTINCT FROM 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV'
     OR private.fn_growth_email_source('ZXPUB001', 'autre@ehpad-public-un.test') IS NOT NULL
     OR private.fn_growth_email_source(NULL, 'contact@ehpad-public-un.test') IS NOT NULL
     OR private.fn_growth_email_source('ZXPUB003', 'direction@ehpad-public-trois.test') IS NOT NULL
     OR private.fn_growth_mention_opposition('ZXPUB002', 'accueil@ehpad-public-deux.test') IS DISTINCT FROM v_mention_hist
     OR private.fn_growth_mention_opposition('ZXPUB002', '  Accueil@EHPAD-Public-Deux.test ') IS DISTINCT FROM v_mention_hist
     -- Limite antérieure au lot : sans provenance sur le prospect, toute adresse garde la mention historique.
     OR private.fn_growth_mention_opposition('ZXPUB002', 'corrigee@ehpad-public-deux.test') IS DISTINCT FROM v_mention_hist
     OR private.fn_growth_mention_opposition(NULL, 'contact@ehpad-public-un.test') IS DISTINCT FROM v_mention_hist
     OR private.fn_growth_mention_opposition('ZXABSENT', 'accueil@ehpad-public-deux.test') IS DISTINCT FROM v_mention_hist
     -- Provenance qui décrit une autre adresse : aucune mention, ni pour l'adresse du prospect ni pour une autre.
     OR private.fn_growth_mention_opposition('ZXPUB003', 'direction@ehpad-public-trois.test') IS NOT NULL
     OR private.fn_growth_mention_opposition('ZXPUB001', 'autre@ehpad-public-un.test') IS NOT NULL
     OR private.fn_growth_email_source('ZXPUB007', 'accueil@ehpad-public-sept.test')->>'source_code' IS DISTINCT FROM 'SAISIE_MANUELLE'
     OR private.fn_growth_mention_opposition('ZXPUB007', 'accueil@ehpad-public-sept.test') IS NOT NULL
     OR private.fn_growth_mention_opposition('ZXPUB004', 'contact@ehpad-public-quatre.test') IS NOT NULL THEN
    RAISE EXCEPTION 'Adresses publiques : origine ou mention inexacte — annuaire « % », historique « % »', v_mention_pa, v_mention_hist;
  END IF;

  -- 12.e Agent : deux brouillons (001 avec la mention de l'annuaire, 002 avec la
  -- mention historique) ; 003, 004 et 007 comptés sans mention ; 005 écarté, son
  -- adresse a déjà une séquence.
  v_res := private.fn_growth_agent_prospection();
  IF (v_res->>'premiers_contacts')::integer IS DISTINCT FROM 2
     OR (v_res->>'exclus_sans_mention')::integer IS DISTINCT FROM 3
     OR (v_res->'cibles'->>'adresses_annuaire_public')::integer IS DISTINCT FROM 3
     OR (SELECT count(*) FROM public.growth_brouillons
         WHERE agent = 'PROSPECTION_ETABLISSEMENT'
           AND cible_id IN ('ZXPUB003', 'ZXPUB004', 'ZXPUB005', 'ZXPUB007')) <> 0 THEN
    RAISE EXCEPTION 'Adresses publiques : deux premiers contacts, trois origines sans mention et aucune seconde séquence sur l''adresse de groupe attendus — %', v_res;
  END IF;
  SELECT id, corps INTO v_id_pub, v_corps
  FROM public.growth_brouillons WHERE canal = 'EMAIL' AND cible_id = 'ZXPUB001';
  IF v_id_pub IS NULL
     OR right(v_corps, char_length(v_mention_pa)) IS DISTINCT FROM v_mention_pa
     OR position('Annuaire Santé' IN v_corps) > 0
     OR (SELECT b.destinataire_email IS DISTINCT FROM 'contact@ehpad-public-un.test'
                OR b.contexte->'email_source'->>'source_code' IS DISTINCT FROM 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV'
                OR b.contexte->'email_source'->>'source_url' IS DISTINCT FROM v_prov->>'source_url'
                OR b.contexte->'email_source'->>'source_maj_le' IS DISTINCT FROM '2020-10-04'
                OR b.contexte->'email_source'->>'releve_le' IS DISTINCT FROM '2026-11-24'
                -- L'ancienne adresse en messagerie fermée ne suit pas le brouillon.
                OR b.contexte->'email_source' ? 'remplace'
                OR position('mssante' IN b.contexte::text) > 0
                OR position('pour-les-personnes-agees.gouv.fr' IN b.contexte->>'source') = 0
         FROM public.growth_brouillons b WHERE b.id = v_id_pub) THEN
    RAISE EXCEPTION 'Adresses publiques : le brouillon de l''adresse de l''annuaire doit porter sa mention et son origine — %',
      (SELECT contexte FROM public.growth_brouillons WHERE id = v_id_pub);
  END IF;
  IF (SELECT count(*) FROM public.growth_brouillons b
      WHERE b.canal = 'EMAIL' AND b.cible_id = 'ZXPUB002'
        AND right(b.corps, char_length(v_mention_hist)) = v_mention_hist
        AND position('pour-les-personnes-agees' IN b.corps) = 0
        AND jsonb_typeof(b.contexte->'email_source') = 'null'
        AND b.contexte->>'source' = 'FINESS (établissement) + Annuaire Santé (email)') <> 1 THEN
    RAISE EXCEPTION 'Adresses publiques : sans provenance, le brouillon garde la mention et la source historiques';
  END IF;

  -- 12.f Relance : le constat d'envoi copie l'adresse de l'annuaire sur la fiche
  -- CRM ; la relance porte la mention de CETTE adresse, même si l'adresse du
  -- prospect a changé depuis. Une adresse nouvelle n'hérite pas de la source.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM public.fn_admin_growth_brouillon_decider(v_id_pub, 'VALIDER');
  v_res := public.fn_admin_growth_brouillon_decider(v_id_pub, 'MARQUER_ENVOYE');
  EXECUTE 'RESET ROLE';
  v_contact_pub := (v_res->>'contact_crm_id')::uuid;
  IF v_res->>'statut' IS DISTINCT FROM 'ENVOYE'
     OR (SELECT email FROM public.sales_contacts WHERE id = v_contact_pub) IS DISTINCT FROM 'contact@ehpad-public-un.test' THEN
    RAISE EXCEPTION 'Adresses publiques : le constat d''envoi doit copier l''adresse de l''annuaire sur la fiche CRM — %', v_res;
  END IF;
  UPDATE public.prospects_etablissements SET email = 'nouvelle@ehpad-public-un.test' WHERE finess = 'ZXPUB001';
  IF private.fn_growth_mention_opposition('ZXPUB001', 'nouvelle@ehpad-public-un.test') IS NOT NULL THEN
    RAISE EXCEPTION 'Adresses publiques : une adresse écrite après l''import, sans provenance à elle, ne doit recevoir aucune mention (ni celle de l''annuaire, ni l''historique)';
  END IF;
  -- Fiche CRM corrigée à la main : la relance partirait à une adresse dont
  -- l'origine est inconnue. Aucun brouillon, et l'agent le compte.
  UPDATE public.sales_contacts
     SET email = 'corrigee@ehpad-public-un.test', prochaine_action_le = now() - interval '1 minute'
   WHERE id = v_contact_pub;
  v_res := private.fn_growth_agent_prospection();
  IF (v_res->>'relances')::integer IS DISTINCT FROM 0
     OR (v_res->>'exclus_sans_mention')::integer < 1
     OR EXISTS (SELECT 1 FROM public.growth_brouillons b
                WHERE b.destinataire_email = 'corrigee@ehpad-public-un.test') THEN
    RAISE EXCEPTION 'Adresses publiques : une fiche CRM dont l''adresse a été corrigée à la main ne doit recevoir aucune relance tant que son origine est inconnue — %', v_res;
  END IF;
  -- L'adresse de l'annuaire revient sur la fiche : la relance est préparée.
  UPDATE public.sales_contacts
     SET email = 'contact@ehpad-public-un.test', prochaine_action_le = now() - interval '1 minute'
   WHERE id = v_contact_pub;
  v_res := private.fn_growth_agent_prospection();
  IF (v_res->>'relances')::integer IS DISTINCT FROM 1
     OR (SELECT right(b.corps, char_length(v_mention_pa)) IS DISTINCT FROM v_mention_pa
                OR b.destinataire_email IS DISTINCT FROM 'contact@ehpad-public-un.test' OR b.sequence_etape <> 2
                -- La relance dit elle aussi d'où vient son adresse, sans l'ancienne adresse fermée.
                OR b.contexte->'email_source'->>'source_code' IS DISTINCT FROM 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV'
                OR b.contexte->'email_source' ? 'remplace'
                OR position('mssante' IN b.contexte::text) > 0
         FROM public.growth_brouillons b
         WHERE b.cible_type = 'CONTACT_CRM' AND b.cible_id = v_contact_pub::text) IS NOT FALSE THEN
    RAISE EXCEPTION 'Adresses publiques : la relance doit porter la mention et l''origine de l''annuaire — %', v_res;
  END IF;

END;
$test$;
ROLLBACK;
