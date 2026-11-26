-- ═══════════════════════════════════════════════════════════════════════════
-- Missions de revue App Store et cloisonnement des envois par cohorte de test
-- (migrations 20261126100000 et 20261126100100).
--
-- ⚠️  JAMAIS EN PROD. Staging CI : job « sql-transaction » de validate-pr.yml,
--     après les migrations candidates, sous SAVEPOINT puis ROLLBACK global ;
--     PostgreSQL 17 éphémère et PGlite : tests/postgres/revue-store-missions.pg17.mjs.
--     Le préflight refuse toute base où un cron est actif. Vraies routines et
--     vrais déclencheurs ; profils fictifs ; appels HTTP seulement mis en file
--     (pg_net n'envoie rien d'une transaction annulée) ; zéro persistance.
--
-- Ce qu'il prouve :
--   A. test-garde : toute fonction qui émet MISSION_A_POURVOIR ou un type
--      équivalent passe par le prédicat canonique de cohorte
--      (private.fn_comptes_meme_cohorte_test, celui de la RLS missions), seule
--      exception documentée ; les portes le lisent ; l'éligibilité n'a plus de
--      règle locale ;
--   B. un établissement réel est refusé (désignation, puis revérification par
--      private.fn_garantir_missions_revue_store) ;
--   C. la fonction crée exactement 3 missions OUVERTE (IDE, TOUS, CANDIDATURE,
--      J+7 à J+21, jour, taux >= plancher, REVUE_STORE), est idempotente,
--      retire puis remplace une mission qui approche, rétablit le contexte ;
--   D. les missions de revue survivent au nettoyage horaire des missions de
--      test, qui purge toujours une mission de test ordinaire ;
--   E. pour chaque chemin d'envoi (création, vagues, relance, boost, matching
--      inverse, missions sauvegardées, pool d'urgence, alerte pool, digest) :
--      le soignant de test T est notifié ou listé, le soignant réel R jamais,
--      et aucun appel HTTP en file ne le désigne.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

DO $revue_store_suite$
DECLARE
  v_e constant uuid := 'a5f0e001-0000-4000-8000-000000000001';      -- établissement de test (revue)
  v_e_reel constant uuid := 'a5f0e001-0000-4000-8000-000000000002'; -- établissement réel
  v_t constant uuid := 'a5f0e002-0000-4000-8000-000000000001';      -- soignant de test
  v_r constant uuid := 'a5f0e002-0000-4000-8000-000000000002';      -- soignant réel
  v_sentinelle constant text := 'RS999';
  v_types constant text := '''(MISSION_A_POURVOIR|MISSION_URGENTE|MISSION_URGENTE_POOL|POOL_URGENCE|FAVORI_NOUVELLE_MISSION|FAVORI_MISSION_EXPIRE|CANDIDATURE_PROPOSEE|MISSION_PROPOSEE_SOIGNANT|NOUVELLES_MISSIONS_FILTRE)''';
  v_portes constant text := '(fn_comptes_meme_cohorte_test|fn_soignant_eligible_mission|fn_resoudre_contrat_mission|fn_resultats_filtre_missions|fn_compter_nouveaux_pour_filtre|fn_pool_urgence_etablissement)';
  v_exceptions constant text[] := ARRAY['public.fn_declarer_empechement_imperieux'];
  v_emetteurs_connus constant text[] := ARRAY['public.fn_vagues_notification_urgentes', 'public.fn_evaluer_alertes_filtres',
    'public.fn_relancer_missions_sans_candidat', 'public.fn_matching_inverse_dispos', 'public.fn_booster_mission',
    'public.fn_trg_favori_nouvelle_mission', 'public.fn_trg_auto_notify_mission_urgente', 'public.fn_notifier_favoris_expirants',
    'private.fn_diffuser_pool_urgence_interne', 'public.fn_detecter_noshow_et_remplacer',
    'public.fn_escalade_remplacement_non_pourvu', 'public.fn_proposer_mission_soignant', 'public.fn_rebooker_soignant'];
  v_aujourdhui date := (now() AT TIME ZONE 'Europe/Paris')::date;
  v_jeton boolean;
  v_rec record;
  v_doc record;
  v_res jsonb;
  v_ids uuid[];
  v_m1 uuid;
  v_n integer;
  v_t_avant integer;
  v_r_avant integer;
  v_t_apres integer;
  v_r_apres integer;
  v_http_r integer;
  v_http_t integer;
  v_http_r0 integer;
  v_http_t0 integer;
  v_msg text;
  v_reglages text;
  v_noms text[];
BEGIN
  -- ── 1. Contexte isolé ──────────────────────────────────────────────────────
  IF session_user NOT IN ('postgres', 'supabase_admin') OR auth.uid() IS NOT NULL
     OR EXISTS (SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'REVUE_STORE : maintenance isolée requise (postgres, sans identité, aucun cron actif)'; END IF;
  IF to_regclass('net.http_request_queue') IS NULL
  THEN RAISE EXCEPTION 'REVUE_STORE : file pg_net absente, les appels push ne seraient pas observables'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id::text LIKE 'a5f0e00%')
     OR EXISTS (SELECT 1 FROM public.etablissements WHERE id::text LIKE 'a5f0e00%' OR siret IN ('99178000000101', '99178000000102'))
     OR EXISTS (SELECT 1 FROM public.soignants WHERE id::text LIKE 'a5f0e00%')
  THEN RAISE EXCEPTION 'REVUE_STORE : identifiants de fixture déjà présents'; END IF;
  v_jeton := EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'service_role_key');

  -- ── 2. Catalogue candidat ──────────────────────────────────────────────────
  FOR v_rec IN SELECT * FROM (VALUES
      ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'f15ef90fcd8a867ecfb375bb37c8d739'),
      ('public.fn_pool_urgence_etablissement(uuid)', '057e327862ee12a7c7cbaacaff8b3ab8'),
      ('public.fn_notifier_favoris_expirants()', 'ad2f2d6c4887de12458807a1b4213bfb'),
      ('public.fn_cleanup_missions_test()', '65b1b5874bd9eb6ce2a6715554cf51ab')
    ) AS t(signature, empreinte)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(v_rec.signature)) IS DISTINCT FROM v_rec.empreinte
    THEN RAISE EXCEPTION 'REVUE_STORE : corps candidat inattendu pour %', v_rec.signature; END IF;
  END LOOP;
  IF (SELECT prosecdef FROM pg_proc WHERE oid = 'private.fn_garantir_missions_revue_store()'::regprocedure) IS NOT TRUE
     OR (SELECT proconfig FROM pg_proc WHERE oid = 'private.fn_garantir_missions_revue_store()'::regprocedure)
        IS DISTINCT FROM ARRAY['search_path=""']::text[]
     OR has_function_privilege('anon', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
     OR has_table_privilege('authenticated', 'private.etablissements_revue_store', 'INSERT')
     OR has_table_privilege('service_role', 'private.etablissements_revue_store', 'INSERT')
  THEN RAISE EXCEPTION 'REVUE_STORE : fonction de garantie ou désignation exposées'; END IF;
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory i
              JOIN pg_proc p ON p.oid = to_regprocedure(CASE WHEN i.signature LIKE 'private.%' THEN i.signature ELSE 'public.' || i.signature END)
             WHERE i.signature IN ('private.fn_garantir_missions_revue_store()', 'fn_pool_urgence_etablissement(uuid)')
               AND i.definition_md5 IS DISTINCT FROM md5(p.prosrc))
  THEN RAISE EXCEPTION 'REVUE_STORE : inventaire SECURITY DEFINER désaligné'; END IF;
  IF strpos((SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
              WHERE c.conrelid = 'public.missions'::regclass AND c.conname = 'missions_mission_source_check'), '''REVUE_STORE''') = 0
  THEN RAISE EXCEPTION 'REVUE_STORE : mission_source n''accepte pas REVUE_STORE'; END IF;
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND (SELECT count(*) FROM cron.job WHERE jobname = 'jolene_missions_revue_store_quotidien'
            AND schedule = '40 4 * * *' AND command = 'SELECT private.fn_garantir_missions_revue_store()'
            AND active IS FALSE) <> 1
  THEN RAISE EXCEPTION 'REVUE_STORE : cron quotidien absent, ou actif sur une base sans cron actif'; END IF;

  -- ── A. Test-garde des émetteurs ────────────────────────────────────────────
  v_noms := ARRAY[]::text[];
  FOR v_rec IN
    SELECT n.nspname || '.' || p.proname AS nom, p.prosrc
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'private')
       AND p.prosrc ~ v_types
       AND p.prosrc ~* '(insert\s+into\s+(public\.)?(notifications|email_queue)|net\.http_post|fn_creer_notification)'
     ORDER BY 1
  LOOP
    v_noms := v_noms || v_rec.nom;
    CONTINUE WHEN v_rec.nom = ANY (v_exceptions);
    IF v_rec.prosrc !~ v_portes THEN
      RAISE EXCEPTION 'REVUE_STORE test-garde : % émet une diffusion de mission sans le prédicat de cohorte (private.fn_comptes_meme_cohorte_test, directement ou par une porte)', v_rec.nom;
    END IF;
  END LOOP;
  IF NOT (v_noms @> v_emetteurs_connus) THEN
    RAISE EXCEPTION 'REVUE_STORE test-garde : énumération incomplète (%), motif des émetteurs à revoir', v_noms;
  END IF;
  -- L'exception documentée ne fait que compter ces notifications (la diffusion
  -- appartient au déclencheur urgent) : elle est liée au corps relu le
  -- 26/11/2026 ; tout changement de corps impose une nouvelle revue.
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_declarer_empechement_imperieux(uuid,date,date)'::regprocedure)
       IS DISTINCT FROM 'b258bf027eff809cf3ac4b005ddde3dc'
  THEN RAISE EXCEPTION 'REVUE_STORE test-garde : fn_declarer_empechement_imperieux a changé depuis la revue de son exception (26/11/2026), la revoir'; END IF;
  -- Portes de premier rang : lisent le prédicat ; de second rang : lisent une porte.
  FOR v_rec IN
    SELECT t.signature, t.motif, p.prosrc
      FROM (VALUES
        ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'private.fn_comptes_meme_cohorte_test('),
        ('public.fn_resoudre_contrat_mission(uuid,uuid,text)', 'private.fn_comptes_meme_cohorte_test('),
        ('private.fn_resultats_filtre_missions(uuid,timestamp with time zone)', 'private.fn_comptes_meme_cohorte_test('),
        ('public.fn_pool_urgence_etablissement(uuid)', 'private.fn_comptes_meme_cohorte_test('),
        ('public.fn_compter_nouveaux_pour_filtre(uuid,timestamp with time zone)', 'private.fn_resultats_filtre_missions('),
        ('public.fn_obtenir_apercu_filtre(uuid,timestamp with time zone,integer)', 'private.fn_resultats_filtre_missions('),
        -- Listes de soignants à contacter vues par un établissement.
        ('public.fn_soignants_urgence(uuid)', 'fn_soignant_eligible_mission('),
        ('public.fn_recommander_soignants(uuid,integer)', 'fn_soignant_eligible_mission('),
        ('public.fn_vivier_disponibilites(date,text)', 'private.fn_comptes_meme_cohorte_test('),
        ('private.fn_resultats_recherche_soignants_etab(uuid,text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text)', 'private.fn_comptes_meme_cohorte_test(')
      ) AS t(signature, motif)
      LEFT JOIN pg_proc p ON p.oid = to_regprocedure(t.signature)
  LOOP
    IF v_rec.prosrc IS NULL OR strpos(v_rec.prosrc, v_rec.motif) = 0 THEN
      RAISE EXCEPTION 'REVUE_STORE test-garde : la porte % ne lit plus %', v_rec.signature, v_rec.motif;
    END IF;
  END LOOP;
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)'::regprocedure), 'est_compte_test') > 0
  THEN RAISE EXCEPTION 'REVUE_STORE test-garde : l''éligibilité redécide encore la cohorte localement'; END IF;

  -- ── 3. Fixtures (SQL Auth direct : ni session, ni e-mail, ni hook) ─────────
  -- Comptes réels possibles : comme en production (inscriptions publiques actives).
  INSERT INTO public.parametres_systeme (cle, valeur, label, description, unite, val_min, val_max, categorie, avertissement, cablee)
  VALUES ('inscriptions_publiques_actives', 1, 'Inscriptions publiques actives', 'Fixture REVUE_STORE (transaction annulée).',
          'booléen', 0, 1, 'GENERAL', 'Fixture.', true)
  ON CONFLICT (cle) DO UPDATE SET valeur = 1;
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
  VALUES
    (v_e, '00000000-0000-0000-0000-000000000000', 'revue-store-e@example.invalid', 'authenticated', 'authenticated',
     '{"role":"ADMIN_ETABLISSEMENT","est_compte_test":true}', now()),
    (v_e_reel, '00000000-0000-0000-0000-000000000000', 'revue-store-e-reel@example.invalid', 'authenticated', 'authenticated',
     '{"role":"ADMIN_ETABLISSEMENT"}', now()),
    (v_t, '00000000-0000-0000-0000-000000000000', 'revue-store-t@example.invalid', 'authenticated', 'authenticated',
     '{"role":"SOIGNANT","est_compte_test":true}', now()),
    (v_r, '00000000-0000-0000-0000-000000000000', 'revue-store-r@example.invalid', 'authenticated', 'authenticated',
     '{"role":"SOIGNANT"}', now());
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal,
    adresse_lat, adresse_lng, email_contact, est_compte_test)
  VALUES
    (v_e, 'Fixture revue store', '99178000000101', 'CLINIQUE_PRIVEE', '1 rue du Test', 'Paris', '75002',
     48.8686, 2.3417, 'revue-store-e@example.invalid', true),
    (v_e_reel, 'Fixture établissement réel', '99178000000102', 'CLINIQUE_PRIVEE', '2 rue du Test', 'Paris', '75002',
     48.8686, 2.3417, 'revue-store-e-reel@example.invalid', false);
  INSERT INTO public.soignants (id, prenom, nom, email, profession, est_compte_test, rpps_verifie,
    disponible_urgence, tous_documents_valides, telephone, adresse_lat, adresse_lng, rayon_deplacement_km, urgence_rayon_km)
  VALUES
    (v_t, 'Fixture', 'Test', 'revue-store-t@example.invalid', 'IDE', true, true, true, true, NULL, 48.8575, 2.3800, 50, 30),
    (v_r, 'Fixture', 'Reel', 'revue-store-r@example.invalid', 'IDE', false, true, true, true, NULL, 48.8575, 2.3800, 50, 30);
  IF (SELECT est_compte_test FROM public.etablissements WHERE id = v_e) IS NOT TRUE
     OR (SELECT est_compte_test FROM public.etablissements WHERE id = v_e_reel) IS NOT FALSE
     OR (SELECT est_compte_test FROM public.soignants WHERE id = v_t) IS NOT TRUE
     OR (SELECT est_compte_test FROM public.soignants WHERE id = v_r) IS NOT FALSE
  THEN RAISE EXCEPTION 'REVUE_STORE : cohortes de fixture inattendues'; END IF;
  -- Preuves salariées critiques vérifiées pour T et R (même filtre documentaire).
  FOR v_doc IN
    SELECT drp.type_document, drp.a_expiration
      FROM public.documents_requis_par_profession drp
     WHERE drp.profession = 'IDE' AND drp.est_critique IS TRUE
       AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY') AND drp.type_document <> 'RPPS_ADELI'
  LOOP
    INSERT INTO public.documents_soignants (soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
      est_critique, valide_jusqua, resultat_ia)
    SELECT s, v_doc.type_document, 'tests/revue-store/' || s || '/' || lower(v_doc.type_document::text),
           lower(v_doc.type_document::text) || '.pdf', 'VERIFIE', true,
           CASE WHEN v_doc.a_expiration THEN current_date + 365 END,
           CASE WHEN v_doc.type_document = 'DIPLOME' THEN '{"profession_certifiee":"IDE"}'::jsonb ELSE '{}'::jsonb END
      FROM unnest(ARRAY[v_t, v_r]) s;
  END LOOP;
  INSERT INTO public.membres_etablissement (etablissement_id, user_id, role, actif)
  SELECT v_e, v_e, 'PROPRIETAIRE', true
   WHERE NOT EXISTS (SELECT 1 FROM public.membres_etablissement WHERE etablissement_id = v_e AND user_id = v_e);
  -- R a mis l'établissement de test en favori (ligne orpheline : la RLS ne le lui
  -- aurait jamais montré) ; T aussi.
  INSERT INTO public.favoris_soignant_etab (soignant_id, etablissement_id) VALUES (v_t, v_e), (v_r, v_e);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  -- Appels HTTP déjà en file qui désignent T ou R (aucun attendu) : référence des contrôles.
  SELECT count(*) INTO v_http_r0 FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_r::text || '%';
  SELECT count(*) INTO v_http_t0 FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_t::text || '%';

  -- ── B. Un établissement réel est refusé ────────────────────────────────────
  BEGIN
    INSERT INTO private.etablissements_revue_store (etablissement_id, motif) VALUES (v_e_reel, 'Fixture : établissement réel');
    RAISE EXCEPTION 'REVUE_STORE B1 : un établissement réel a été désigné';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_msg = PG_EXCEPTION_HINT;
    IF v_msg IS DISTINCT FROM 'REVUE_STORE_ETABLISSEMENT_REEL' THEN RAISE; END IF;
  END;
  -- Désignation forcée (déclencheur désactivé, comme une écriture qui l'aurait
  -- contourné) : la fonction refuse quand même et ne crée rien.
  BEGIN
    ALTER TABLE private.etablissements_revue_store DISABLE TRIGGER trg_verifier_designation_revue_store;
    INSERT INTO private.etablissements_revue_store (etablissement_id, motif) VALUES (v_e_reel, 'Fixture : établissement réel');
    ALTER TABLE private.etablissements_revue_store ENABLE TRIGGER trg_verifier_designation_revue_store;
    PERFORM private.fn_garantir_missions_revue_store();
    RAISE EXCEPTION 'REVUE_STORE B2 : la fonction a accepté un établissement réel';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_msg = PG_EXCEPTION_HINT;
    IF v_msg IS DISTINCT FROM 'REVUE_STORE_ETABLISSEMENT_REEL' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.missions WHERE etablissement_id = v_e_reel)
     OR EXISTS (SELECT 1 FROM private.etablissements_revue_store WHERE etablissement_id = v_e_reel)
  THEN RAISE EXCEPTION 'REVUE_STORE B3 : refus avec effet de bord'; END IF;

  -- ── C. Création du stock ───────────────────────────────────────────────────
  INSERT INTO private.etablissements_revue_store (etablissement_id, motif) VALUES (v_e, 'Fixture : établissement de revue');
  SELECT count(*) INTO v_t_avant FROM public.notifications WHERE destinataire_id = v_t;
  SELECT count(*) INTO v_r_avant FROM public.notifications WHERE destinataire_id = v_r;
  v_res := private.fn_garantir_missions_revue_store();
  IF (v_res->>'success')::boolean IS NOT TRUE OR (v_res->>'missions_creees')::integer < 3 THEN
    RAISE EXCEPTION 'REVUE_STORE C1 : stock non créé (%)', v_res;
  END IF;
  SELECT array_agg(m.id ORDER BY m.debut_le) INTO v_ids
    FROM public.missions m
   WHERE m.etablissement_id = v_e AND m.statut = 'OUVERTE' AND m.mission_source = 'REVUE_STORE'
     AND m.profession_requise = 'IDE' AND m.type_contrat_recherche = 'TOUS' AND m.mode_attribution = 'CANDIDATURE'
     AND m.est_urgente IS FALSE AND m.soignant_assigne_id IS NULL
     AND (m.debut_le AT TIME ZONE 'Europe/Paris')::date BETWEEN v_aujourdhui + 7 AND v_aujourdhui + 21
     AND extract(isodow FROM (m.debut_le AT TIME ZONE 'Europe/Paris')) <> 7
     AND (m.debut_le AT TIME ZONE 'Europe/Paris')::time >= time '07:00'
     AND (m.fin_le AT TIME ZONE 'Europe/Paris')::time <= time '20:00'
     AND (m.fin_le AT TIME ZONE 'Europe/Paris')::date = (m.debut_le AT TIME ZONE 'Europe/Paris')::date
     AND m.duree_heures = 7 AND m.nb_creneaux = 1
     AND m.taux_horaire_base >= (SELECT valeur FROM public.parametres_systeme WHERE cle = 'taux_horaire_minimum_salarie')
     AND m.total_brut > 0 AND m.net_a_payer > 0
     AND m.statut_validation_tva = 'A_CONFIRMER' AND m.nature_tva_prestation = 'SOIN_THERAPEUTIQUE_EXONERE'
     AND m.intitule NOT LIKE '[%'
     AND (SELECT count(*) FROM public.mission_creneaux c WHERE c.mission_id = m.id AND c.type_creneau = 'PREVISIONNEL'
            AND c.debut = m.debut_le AND c.fin = m.fin_le AND c.est_pause IS FALSE) = 1;
  IF cardinality(v_ids) IS DISTINCT FROM 3
     OR (SELECT count(*) FROM public.missions WHERE etablissement_id = v_e) <> 3
     OR (SELECT count(DISTINCT (debut_le AT TIME ZONE 'Europe/Paris')::date) FROM public.missions WHERE id = ANY (v_ids)) <> 3
  THEN RAISE EXCEPTION 'REVUE_STORE C2 : stock attendu de 3 missions conformes, relu % (%)', cardinality(v_ids),
         (SELECT jsonb_agg(jsonb_build_object('debut', debut_le, 'type', type_contrat_recherche, 'source', mission_source,
            'duree', duree_heures, 'taux', taux_horaire_base, 'tva', statut_validation_tva)) FROM public.missions WHERE etablissement_id = v_e);
  END IF;
  v_m1 := v_ids[1];
  IF (SELECT count(*) FROM public.journaux_audit WHERE action = 'MISSION_CREATION' AND id_ressource = ANY (v_ids)
        AND details->>'source' = 'REVUE_STORE') <> 3
  THEN RAISE EXCEPTION 'REVUE_STORE C3 : audit de création absent'; END IF;
  -- Contexte rétabli : aucune identité ni drapeau de création ne survit à l'appel.
  SELECT string_agg(n || '=' || COALESCE(current_setting(n, true), ''), ' ') INTO v_reglages
    FROM unnest(ARRAY['request.jwt.claims', 'request.jwt.claim.role', 'request.jwt.claim.sub',
      'jolene.creer_mission_context', 'jolene.planning_exact_managed', 'jolene.sync_in_progress',
      'jolene.tva_mission_managed']) AS n
   WHERE COALESCE(current_setting(n, true), '') NOT IN ('', 'false');
  IF v_reglages IS NOT NULL THEN
    RAISE EXCEPTION 'REVUE_STORE C4 : réglages de transaction non rétablis (%)', v_reglages;
  END IF;
  -- Idempotence.
  v_res := private.fn_garantir_missions_revue_store();
  IF (v_res->>'missions_creees')::integer <> 0 OR (v_res->>'missions_retirees')::integer <> 0
     OR (SELECT count(*) FROM public.missions WHERE etablissement_id = v_e AND statut = 'OUVERTE') <> 3
  THEN RAISE EXCEPTION 'REVUE_STORE C5 : second passage non idempotent (%)', v_res; END IF;
  -- E1 : la création a déclenché trg_favori_nouvelle_mission : T notifié, R jamais.
  SELECT count(*) INTO v_t_apres FROM public.notifications WHERE destinataire_id = v_t AND type = 'FAVORI_NOUVELLE_MISSION';
  SELECT count(*) INTO v_r_apres FROM public.notifications WHERE destinataire_id = v_r;
  SELECT count(*) INTO v_http_r FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_r::text || '%';
  IF v_t_apres < 3 OR v_r_apres <> v_r_avant OR v_http_r <> v_http_r0 THEN
    RAISE EXCEPTION 'REVUE_STORE E1 : favoris à la création (T % notification(s), R % → %, HTTP R %)', v_t_apres, v_r_avant, v_r_apres, v_http_r;
  END IF;
  IF v_jeton AND (SELECT count(*) FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_t::text || '%') <= v_http_t0
  THEN RAISE EXCEPTION 'REVUE_STORE E1 : aucun e-mail en file pour T alors qu''un jeton de service existe'; END IF;

  -- Retrait puis remplacement d'une mission qui approche (sentinelle annulée).
  BEGIN
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    PERFORM public.fn_test_update_mission(v_m1, jsonb_build_object('debut_le', now() + interval '2 days',
      'fin_le', now() + interval '2 days 7 hours'));
    PERFORM set_config('app.internal_operation', '', true);
    PERFORM set_config('jolene.creer_mission_context', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    v_res := private.fn_garantir_missions_revue_store();
    IF (v_res->>'missions_retirees')::integer <> 1 OR (v_res->>'missions_creees')::integer <> 1
       OR (SELECT statut::text FROM public.missions WHERE id = v_m1) <> 'EXPIREE'
       OR (SELECT count(*) FROM public.missions WHERE etablissement_id = v_e AND statut = 'OUVERTE'
             AND mission_source = 'REVUE_STORE' AND debut_le > now() + interval '3 days') <> 3
    THEN RAISE EXCEPTION 'REVUE_STORE C6 : retrait et remplacement inattendus (%)', v_res; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;

  -- Ancienneté de plus de 24 h pour les chemins qui attendent (vagues, relance, nettoyage).
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  FOR v_n IN 1..3 LOOP
    PERFORM public.fn_test_update_mission(v_ids[v_n], jsonb_build_object('cree_le', now() - interval '25 hours'));
  END LOOP;
  PERFORM set_config('app.internal_operation', '', true);
  PERFORM set_config('jolene.creer_mission_context', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF (SELECT count(*) FROM public.missions WHERE id = ANY (v_ids) AND cree_le < now() - interval '24 hours') <> 3
  THEN RAISE EXCEPTION 'REVUE_STORE : ancienneté de fixture non posée'; END IF;

  -- ── D. Nettoyage horaire : le stock survit, une mission de test ordinaire non ─
  BEGIN
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    PERFORM public.fn_test_update_mission(v_ids[3], '{"mission_source": null}'::jsonb);
    PERFORM set_config('app.internal_operation', '', true);
    PERFORM set_config('jolene.creer_mission_context', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM public.fn_cleanup_missions_test();
    IF (SELECT count(*) FROM public.missions WHERE id IN (v_ids[1], v_ids[2]) AND statut = 'OUVERTE') <> 2
    THEN RAISE EXCEPTION 'REVUE_STORE D1 : une mission de revue a été purgée par fn_cleanup_missions_test'; END IF;
    IF EXISTS (SELECT 1 FROM public.missions WHERE id = v_ids[3])
    THEN RAISE EXCEPTION 'REVUE_STORE D2 : le nettoyage ne purge plus une mission de test ordinaire'; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;
  IF (SELECT count(*) FROM public.missions WHERE id = ANY (v_ids) AND statut = 'OUVERTE' AND mission_source = 'REVUE_STORE') <> 3
  THEN RAISE EXCEPTION 'REVUE_STORE D3 : stock altéré après la sentinelle'; END IF;

  -- ── E. Chemins d'envoi : T oui, R jamais ───────────────────────────────────
  -- Éligibilité (porte commune).
  IF NOT public.fn_soignant_eligible_mission(v_t, v_m1, true) OR public.fn_soignant_eligible_mission(v_r, v_m1, false)
  THEN RAISE EXCEPTION 'REVUE_STORE E2 : éligibilité (T %, R %)', public.fn_soignant_eligible_mission(v_t, v_m1, true),
         public.fn_soignant_eligible_mission(v_r, v_m1, false); END IF;
  -- Les fan-outs sont bornés aux deux fixtures : les autres soignants éligibles
  -- sont exclus par l'établissement de test le temps de la transaction.
  INSERT INTO public.exclusions (exclu_par, exclu_id, type_exclu_par, motif)
  SELECT v_e, s.id, 'ETABLISSEMENT', 'Fixture REVUE_STORE'
    FROM public.soignants s
   WHERE s.id NOT IN (v_t, v_r) AND public.fn_soignant_eligible_mission(s.id, v_m1, false)
  ON CONFLICT (exclu_par, exclu_id) DO NOTHING;

  FOR v_rec IN SELECT * FROM (VALUES
      ('vagues', 'MISSION_A_POURVOIR'), ('relance', 'MISSION_A_POURVOIR'), ('boost', 'MISSION_A_POURVOIR'),
      ('matching_inverse', 'MISSION_A_POURVOIR'), ('sauvegardees', 'FAVORI_MISSION_EXPIRE')
    ) AS t(chemin, type_notif)
  LOOP
    BEGIN
      SELECT count(*) INTO v_t_avant FROM public.notifications WHERE destinataire_id = v_t AND type = v_rec.type_notif;
      SELECT count(*) INTO v_r_avant FROM public.notifications WHERE destinataire_id = v_r;
      SELECT count(*) INTO v_http_t0 FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_t::text || '%';
      CASE v_rec.chemin
        WHEN 'vagues' THEN
          PERFORM public.fn_vagues_notification_urgentes();
        WHEN 'relance' THEN
          PERFORM public.fn_relancer_missions_sans_candidat();
        WHEN 'boost' THEN
          PERFORM set_config('request.jwt.claim.sub', v_e::text, true);
          PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
          PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_e, 'role', 'authenticated')::text, true);
          v_res := public.fn_booster_mission(v_m1);
          PERFORM set_config('request.jwt.claim.sub', '', true);
          PERFORM set_config('request.jwt.claim.role', '', true);
          PERFORM set_config('request.jwt.claims', '', true);
          IF (v_res->>'success')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'REVUE_STORE E boost refusé : %', v_res; END IF;
        WHEN 'matching_inverse' THEN
          INSERT INTO public.disponibilites_soignant (soignant_id, jour, creneau)
          SELECT s, (debut_le AT TIME ZONE 'Europe/Paris')::date, 'JOURNEE'
            FROM public.missions, unnest(ARRAY[v_t, v_r]) s
           WHERE id = v_m1 AND (debut_le AT TIME ZONE 'Europe/Paris')::date <= current_date + 14;
          IF NOT FOUND THEN
            -- Première mission au-delà de J+14 (dimanche ou férié) : rapprochée pour ce seul chemin.
            PERFORM set_config('request.jwt.claim.role', 'service_role', true);
            PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
            PERFORM public.fn_test_update_mission(v_m1, jsonb_build_object('debut_le', date_trunc('day', now()) + interval '10 days 8 hours',
              'fin_le', date_trunc('day', now()) + interval '10 days 15 hours'));
            PERFORM set_config('app.internal_operation', '', true);
            PERFORM set_config('jolene.creer_mission_context', '', true);
            PERFORM set_config('request.jwt.claim.role', '', true);
            PERFORM set_config('request.jwt.claims', '', true);
            INSERT INTO public.disponibilites_soignant (soignant_id, jour, creneau)
            SELECT s, (debut_le AT TIME ZONE 'Europe/Paris')::date, 'JOURNEE'
              FROM public.missions, unnest(ARRAY[v_t, v_r]) s WHERE id = v_m1;
          END IF;
          PERFORM public.fn_matching_inverse_dispos();
        WHEN 'sauvegardees' THEN
          PERFORM set_config('request.jwt.claim.role', 'service_role', true);
          PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
          PERFORM public.fn_test_update_mission(v_m1, jsonb_build_object('debut_le', now() + interval '30 hours',
            'fin_le', now() + interval '37 hours'));
          PERFORM set_config('app.internal_operation', '', true);
          PERFORM set_config('jolene.creer_mission_context', '', true);
          PERFORM set_config('request.jwt.claim.role', '', true);
          PERFORM set_config('request.jwt.claims', '', true);
          INSERT INTO public.missions_sauvegardees (soignant_id, mission_id) VALUES (v_t, v_m1), (v_r, v_m1);
          PERFORM public.fn_notifier_favoris_expirants();
      END CASE;
      SELECT count(*) INTO v_t_apres FROM public.notifications WHERE destinataire_id = v_t AND type = v_rec.type_notif;
      SELECT count(*) INTO v_r_apres FROM public.notifications WHERE destinataire_id = v_r;
      SELECT count(*) INTO v_http_r FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_r::text || '%';
      SELECT count(*) INTO v_http_t FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_t::text || '%';
      IF v_t_apres <= v_t_avant THEN
        RAISE EXCEPTION 'REVUE_STORE E % : le soignant de test n''a pas été notifié (%)', v_rec.chemin, v_rec.type_notif;
      END IF;
      IF v_r_apres <> v_r_avant OR v_http_r <> v_http_r0 THEN
        RAISE EXCEPTION 'REVUE_STORE E % : le soignant réel a été notifié (% → %) ou désigné par % appel(s) HTTP',
          v_rec.chemin, v_r_avant, v_r_apres, v_http_r - v_http_r0;
      END IF;
      IF v_jeton AND v_rec.chemin IN ('vagues', 'matching_inverse') AND v_http_t <= v_http_t0 THEN
        RAISE EXCEPTION 'REVUE_STORE E % : aucun push en file pour T alors qu''un jeton de service existe', v_rec.chemin;
      END IF;
      RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
    EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
    END;
  END LOOP;

  -- Pool d'urgence (autorisation de send-push et send-sms) et alerte pool d'une mission.
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_e::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_e, 'role', 'authenticated')::text, true);
    IF NOT EXISTS (SELECT 1 FROM public.fn_pool_urgence_etablissement(v_e) p WHERE p.soignant_id = v_t)
       OR EXISTS (SELECT 1 FROM public.fn_pool_urgence_etablissement(v_e) p WHERE p.soignant_id = v_r)
    THEN RAISE EXCEPTION 'REVUE_STORE E pool : T absent ou R présent dans le pool d''un établissement de test'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fn_soignants_urgence(v_m1) p WHERE p.soignant_id = v_t)
       OR EXISTS (SELECT 1 FROM public.fn_soignants_urgence(v_m1) p WHERE p.soignant_id = v_r)
    THEN RAISE EXCEPTION 'REVUE_STORE E alerte pool : T absent ou R présent'; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;
  -- Digest hebdomadaire (comptes par l'éligibilité, sans documents).
  IF (SELECT count(*) FROM public.missions m WHERE m.statut = 'OUVERTE' AND public.fn_soignant_eligible_mission(v_r, m.id, false)
        AND m.etablissement_id = v_e) <> 0
     OR (SELECT count(*) FROM public.missions m WHERE m.statut = 'OUVERTE' AND public.fn_soignant_eligible_mission(v_t, m.id, false)
        AND m.etablissement_id = v_e) <> 3
  THEN RAISE EXCEPTION 'REVUE_STORE E digest : comptes inattendus'; END IF;

  RAISE NOTICE 'REVUE_STORE : test-garde (% émetteurs), refus réel, stock 3, idempotence, retrait, nettoyage, 8 chemins d''envoi vérifiés (jeton de service : %).',
    cardinality(v_noms), v_jeton;
END
$revue_store_suite$;
ROLLBACK;
