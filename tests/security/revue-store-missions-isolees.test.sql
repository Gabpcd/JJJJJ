-- ═══════════════════════════════════════════════════════════════════════════
-- Missions de revue des stores et cloisonnement des missions par cohorte de
-- test (migrations 20261126100000 et 20261126100100).
--
-- ⚠️  JAMAIS EN PROD. Staging CI : job « sql-transaction » de validate-pr.yml,
--     après les migrations candidates, sous SAVEPOINT puis ROLLBACK global ;
--     PostgreSQL 17 éphémère et PGlite : tests/postgres/revue-store-missions.pg17.mjs.
--     Le préflight refuse toute base où un cron est actif. Vraies routines et
--     vrais déclencheurs ; profils fictifs ; appels HTTP seulement mis en file
--     (pg_net n'envoie rien d'une transaction annulée) ; zéro persistance.
--
-- Fixtures : E (établissement de test désigné pour la revue), E2 (établissement
-- de test ordinaire), ER (établissement réel), T (soignant de test désigné pour
-- la revue), T2 (soignant de test ordinaire : la cohorte de test ne contient
-- pas que des comptes internes), R (soignant réel), ADM (administrateur).
--
-- Ce qu'il prouve :
--   A. test-gardes : toute fonction qui émet MISSION_A_POURVOIR ou un type
--      équivalent passe par une porte qui lit le prédicat de cohorte ; les portes
--      écartent REVUE_STORE ; tout lecteur SECURITY DEFINER de missions ouvertes
--      exposé à un compte applique un filtre de visibilité (ou est classé) ;
--   B. un établissement ou un soignant réel est refusé à la désignation ; une
--      désignation forcée d'un établissement réel : le retrait (job distinct)
--      retire ses missions, la garantie lève ;
--   C. exactement 3 missions OUVERTE conformes (créneau de 6 h), idempotence,
--      contexte rétabli, audit ; retrait et remplacement d'une mission qui
--      approche, avec refus de sa candidature en attente ;
--   D. nettoyage horaire : le stock de E survit ; une mission de test ordinaire
--      et une mission REVUE_STORE d'un établissement non désigné sont purgées ;
--      aucun compte ne pose ni ne retire REVUE_STORE ;
--   E. diffusion : aucun envoi (notification, push, e-mail, SMS en file) ne
--      désigne une mission de revue, pour personne, T compris ; les mêmes chemins
--      notifient T et T2 pour une mission de test ordinaire, jamais R ; pool
--      d'urgence de E vide ; le stock ne compte dans le digest pour personne ;
--   F. visibilité : T seul lit les missions de revue (RLS) ; T2 et R non ; E
--      les lit ; favoris comptés de même ; T2 et R ne peuvent pas y candidater,
--      T oui ; textes de posts publics sans mission de test ;
--   G. suppression du compte de E : non bloquée, missions retirées, désignation
--      levée, garantie sans échec ; établissement désigné supprimé : ignoré,
--      sans échec ; suppression du compte de T : sans effet sur la garantie.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout = '150s';
SET LOCAL lock_timeout = '5s';
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

DO $revue_store_suite$
DECLARE
  v_e constant uuid := 'a5f0e001-0000-4000-8000-000000000001';
  v_e2 constant uuid := 'a5f0e001-0000-4000-8000-000000000003';
  v_er constant uuid := 'a5f0e001-0000-4000-8000-000000000002';
  v_t constant uuid := 'a5f0e002-0000-4000-8000-000000000001';
  v_t2 constant uuid := 'a5f0e002-0000-4000-8000-000000000003';
  v_t3 constant uuid := 'a5f0e002-0000-4000-8000-000000000004';  -- soignant de revue sans pièce (G4)
  v_r constant uuid := 'a5f0e002-0000-4000-8000-000000000002';
  v_adm constant uuid := 'a5f0e003-0000-4000-8000-000000000001';
  v_m2 constant uuid := 'a5f0e004-0000-4000-8000-000000000001';      -- mission de test ordinaire de E2
  v_mx constant uuid := 'a5f0e004-0000-4000-8000-000000000002';      -- mission REVUE_STORE hors désignation
  v_sentinelle constant text := 'RS999';
  v_types constant text := '''(MISSION_A_POURVOIR|MISSION_URGENTE|MISSION_URGENTE_POOL|POOL_URGENCE|FAVORI_NOUVELLE_MISSION|FAVORI_MISSION_EXPIRE|CANDIDATURE_PROPOSEE|MISSION_PROPOSEE_SOIGNANT|NOUVELLES_MISSIONS_FILTRE)''';
  v_portes constant text := '(fn_comptes_meme_cohorte_test|fn_soignant_eligible_mission|fn_resoudre_contrat_mission|fn_resultats_filtre_missions|fn_compter_nouveaux_pour_filtre|fn_soignant_contactable_par_etablissement)';
  v_diffusions constant text[] := ARRAY['MISSION_A_POURVOIR', 'MISSION_URGENTE', 'MISSION_URGENTE_POOL', 'POOL_URGENCE',
    'FAVORI_NOUVELLE_MISSION', 'FAVORI_MISSION_EXPIRE', 'CANDIDATURE_PROPOSEE', 'MISSION_NON_POURVUE', 'NOUVELLES_MISSIONS_FILTRE'];
  v_exceptions constant text[] := ARRAY['public.fn_declarer_empechement_imperieux'];
  v_emetteurs_connus constant text[] := ARRAY['public.fn_vagues_notification_urgentes', 'public.fn_evaluer_alertes_filtres',
    'public.fn_relancer_missions_sans_candidat', 'public.fn_matching_inverse_dispos', 'public.fn_booster_mission',
    'public.fn_trg_favori_nouvelle_mission', 'public.fn_trg_auto_notify_mission_urgente', 'public.fn_notifier_favoris_expirants',
    'private.fn_diffuser_pool_urgence_interne', 'public.fn_detecter_noshow_et_remplacer',
    'public.fn_escalade_remplacement_non_pourvu', 'public.fn_proposer_mission_soignant', 'public.fn_rebooker_soignant'];
  -- Lecteurs SECURITY DEFINER de missions ouvertes exposés à un compte, sans filtre
  -- de visibilité des soignants, et pourquoi (classement revu le 26/11/2026).
  v_lecteurs_classes constant text[] := ARRAY[
    'public.fn_admin_health_check',                -- compteurs techniques, admin seulement
    'public.fn_admin_reset_test_account',          -- action admin sur un compte de test
    'public.fn_alertes_dashboard_etab',            -- missions de l'établissement appelant
    'public.fn_stats_dashboard_etablissement',     -- idem
    'public.fn_stats_rh_etablissement',            -- idem
    'public.fn_supprimer_mon_compte_etablissement',-- idem (suppression de son compte)
    'public.fn_annuler_mission_etab',              -- action sur sa mission
    'public.fn_annuler_mission_soignant',          -- action sur sa mission attribuée
    'public.fn_annuler_candidature_soignant',      -- action sur sa candidature
    'public.fn_declarer_empechement_imperieux',    -- action sur sa mission attribuée
    'public.fn_etablissement_pour_mission',        -- fiche établissement, aucune mission rendue
    'public.fn_etablissements_safe',               -- fiche établissement (cohorte), aucune mission rendue
    'public.fn_compteur_soignants_disponibles'];   -- côté établissement (cohorte), compte de soignants
  v_aujourdhui date := (now() AT TIME ZONE 'Europe/Paris')::date;
  v_jeton boolean;
  v_rec record;
  v_doc record;
  v_res jsonb;
  v_res2 jsonb;
  v_ids uuid[];
  v_m1 uuid;
  v_n integer;
  v_t_avant integer;
  v_t2_avant integer;
  v_r_avant integer;
  v_t_apres integer;
  v_t2_apres integer;
  v_http_t2 integer;
  v_vus_revue integer;
  v_vus_ordinaire integer;
  v_r_apres integer;
  v_msg text;
  v_noms text[];
  v_reglages text;
BEGIN
  -- ── 1. Contexte isolé ──────────────────────────────────────────────────────
  IF session_user NOT IN ('postgres', 'supabase_admin') OR auth.uid() IS NOT NULL
     OR EXISTS (SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'REVUE_STORE : maintenance isolée requise (postgres, sans identité, aucun cron actif)'; END IF;
  IF to_regclass('net.http_request_queue') IS NULL
  THEN RAISE EXCEPTION 'REVUE_STORE : file pg_net absente, les appels push ne seraient pas observables'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id::text LIKE 'a5f0e00%')
     OR EXISTS (SELECT 1 FROM public.etablissements WHERE id::text LIKE 'a5f0e00%'
                  OR siret IN ('99178000000101', '99178000000102', '99178000000103'))
     OR EXISTS (SELECT 1 FROM public.soignants WHERE id::text LIKE 'a5f0e00%')
     OR EXISTS (SELECT 1 FROM public.missions WHERE id::text LIKE 'a5f0e00%')
  THEN RAISE EXCEPTION 'REVUE_STORE : identifiants de fixture déjà présents'; END IF;
  v_jeton := EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'service_role_key');

  -- ── 2. Catalogue candidat ──────────────────────────────────────────────────
  FOR v_rec IN SELECT * FROM (VALUES
      ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)', '6db2aebbc7342bb721108b66688b62bc'),
      ('public.fn_resoudre_contrat_mission(uuid,uuid,text)', '91bf0908b53aaca7b5b4ea2cefaf4110'),
      ('public.fn_pool_urgence_etablissement(uuid)', 'a4308cb167e6c0d895efda615c5da297'),
      ('private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)', 'e2d9b4f46afb52b8278c0f71018b2539'),
      ('public.fn_notifier_favoris_expirants()', '8d3fa4597fb5835e8658bc4f31a3730c'),
      ('public.fn_relancer_missions_sans_candidat()', '6d9af12f3446ccdabe4f840d93debfc7'),
      ('private.fn_resultats_filtre_missions(uuid,timestamp with time zone)', 'bf44aa1996cebc52ea272622000876c5'),
      ('public.fn_mes_favoris_etablissements()', '100f3988e20a0446673267ce804bb3b0'),
      ('public.fn_admin_generer_posts()', 'f822983bb47bd93f1d984cdcb41a4b15'),
      ('public.fn_cleanup_missions_test()', 'ee0c90c2fa777643b8261956ef7e3d6f'),
      ('public.fn_supprimer_mon_compte_etablissement()', 'a5dd6e6858e7ad641f4bd353753f3223')
    ) AS t(signature, empreinte)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(v_rec.signature)) IS DISTINCT FROM v_rec.empreinte
    THEN RAISE EXCEPTION 'REVUE_STORE : corps candidat inattendu pour %', v_rec.signature; END IF;
  END LOOP;
  FOR v_rec IN SELECT unnest(ARRAY['private.fn_garantir_missions_revue_store()', 'private.fn_retirer_missions_revue_store(uuid[],text)',
      'private.fn_retirer_missions_revue_store_non_conformes()', 'private.fn_liberer_revue_store_etablissement(uuid)',
      'private.fn_est_etablissement_revue_store(uuid)', 'private.fn_soignant_voit_mission(uuid,uuid,text)',
      'private.fn_soignant_contactable_par_etablissement(uuid,uuid)']) AS signature
  LOOP
    IF (SELECT prosecdef FROM pg_proc WHERE oid = to_regprocedure(v_rec.signature)) IS NOT TRUE
       OR (SELECT proconfig FROM pg_proc WHERE oid = to_regprocedure(v_rec.signature)) IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR has_function_privilege('anon', v_rec.signature, 'EXECUTE')
       OR has_function_privilege('authenticated', v_rec.signature, 'EXECUTE')
       OR has_function_privilege('service_role', v_rec.signature, 'EXECUTE')
    THEN RAISE EXCEPTION 'REVUE_STORE : % exposée ou mal configurée', v_rec.signature; END IF;
  END LOOP;
  IF has_function_privilege('anon', 'private.fn_est_soignant_revue_store(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'private.fn_est_soignant_revue_store(uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'private.etablissements_revue_store', 'SELECT')
     OR has_table_privilege('service_role', 'private.etablissements_revue_store', 'INSERT')
     OR has_table_privilege('authenticated', 'private.soignants_revue_store', 'SELECT')
     OR has_table_privilege('service_role', 'private.soignants_revue_store', 'INSERT')
  THEN RAISE EXCEPTION 'REVUE_STORE : désignation ou prédicat exposés'; END IF;
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory i
              JOIN pg_proc p ON p.oid = to_regprocedure(CASE WHEN i.signature LIKE 'private.%' THEN i.signature ELSE 'public.' || i.signature END)
             WHERE (i.signature LIKE 'private.fn_%revue_store%' OR i.signature IN ('fn_pool_urgence_etablissement(uuid)',
                      'fn_mes_favoris_etablissements()', 'fn_admin_generer_posts()', 'fn_supprimer_mon_compte_etablissement()',
                      'private.fn_soignant_voit_mission(uuid,uuid,text)', 'private.fn_soignant_contactable_par_etablissement(uuid,uuid)'))
               AND i.definition_md5 IS DISTINCT FROM md5(p.prosrc))
     OR (SELECT count(*) FROM private.security_definer_inventory
          WHERE signature IN ('private.fn_garantir_missions_revue_store()', 'private.fn_est_soignant_revue_store(uuid)',
                              'private.fn_soignant_voit_mission(uuid,uuid,text)', 'private.fn_liberer_revue_store_etablissement(uuid)')) <> 4
  THEN RAISE EXCEPTION 'REVUE_STORE : inventaire SECURITY DEFINER désaligné'; END IF;
  IF strpos((SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
              WHERE c.conrelid = 'public.missions'::regclass AND c.conname = 'missions_mission_source_check'), '''REVUE_STORE''') = 0
     OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.missions'::regclass
                      AND polname = 'missions_revue_store_soignant_designe' AND NOT polpermissive AND polcmd = 'r')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.missions'::regclass
                      AND tgname = 'trg_00_proteger_mission_source_revue_store' AND tgenabled = 'O')
  THEN RAISE EXCEPTION 'REVUE_STORE : contrainte, politique ou déclencheur absents'; END IF;
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND ((SELECT count(*) FROM cron.job WHERE jobname = 'jolene_missions_revue_store_quotidien'
            AND schedule = '40 4 * * *' AND command = 'SELECT private.fn_garantir_missions_revue_store()' AND active IS FALSE) <> 1
       OR (SELECT count(*) FROM cron.job WHERE jobname = 'jolene_missions_revue_store_retrait'
            AND schedule = '35 4 * * *' AND command = 'SELECT private.fn_retirer_missions_revue_store_non_conformes()' AND active IS FALSE) <> 1)
  THEN RAISE EXCEPTION 'REVUE_STORE : crons absents, ou actifs sur une base sans cron actif'; END IF;

  -- ── A. Test-gardes ─────────────────────────────────────────────────────────
  -- A1. Émetteurs de diffusion de mission : tous derrière une porte.
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
  -- appartient au déclencheur urgent), liée au corps relu le 26/11/2026.
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_declarer_empechement_imperieux(uuid,date,date)'::regprocedure)
       IS DISTINCT FROM 'b258bf027eff809cf3ac4b005ddde3dc'
  THEN RAISE EXCEPTION 'REVUE_STORE test-garde : fn_declarer_empechement_imperieux a changé depuis la revue de son exception (26/11/2026), la revoir'; END IF;
  -- A2. Portes : chacune lit le prédicat de cohorte ; celles de la diffusion écartent REVUE_STORE.
  FOR v_rec IN
    SELECT t.signature, t.motif, p.prosrc
      FROM (VALUES
        ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'private.fn_comptes_meme_cohorte_test('),
        ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'IF v_mission.mission_source IS NOT DISTINCT FROM ''REVUE_STORE'' THEN'),
        ('public.fn_resoudre_contrat_mission(uuid,uuid,text)', 'private.fn_comptes_meme_cohorte_test('),
        ('public.fn_resoudre_contrat_mission(uuid,uuid,text)', 'private.fn_est_soignant_revue_store(p_soignant_id)'),
        ('private.fn_resultats_filtre_missions(uuid,timestamp with time zone)', 'private.fn_comptes_meme_cohorte_test('),
        ('private.fn_resultats_filtre_missions(uuid,timestamp with time zone)', 'AND m.mission_source IS DISTINCT FROM ''REVUE_STORE'''),
        ('public.fn_relancer_missions_sans_candidat()', 'AND m.mission_source IS DISTINCT FROM ''REVUE_STORE'''),
        ('public.fn_notifier_favoris_expirants()', 'AND m.mission_source IS DISTINCT FROM ''REVUE_STORE'''),
        ('private.fn_soignant_contactable_par_etablissement(uuid,uuid)', 'private.fn_comptes_meme_cohorte_test('),
        ('private.fn_soignant_contactable_par_etablissement(uuid,uuid)', 'NOT private.fn_est_etablissement_revue_store('),
        ('public.fn_pool_urgence_etablissement(uuid)', 'private.fn_soignant_contactable_par_etablissement(s.id, p_etablissement_id)'),
        ('private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)', 'private.fn_soignant_contactable_par_etablissement(s.id, e.id)'),
        ('private.fn_soignant_voit_mission(uuid,uuid,text)', 'private.fn_comptes_meme_cohorte_test('),
        ('private.fn_soignant_voit_mission(uuid,uuid,text)', 'private.fn_est_soignant_revue_store('),
        ('public.fn_compter_nouveaux_pour_filtre(uuid,timestamp with time zone)', 'private.fn_resultats_filtre_missions('),
        ('public.fn_obtenir_apercu_filtre(uuid,timestamp with time zone,integer)', 'private.fn_resultats_filtre_missions('),
        ('public.fn_soignants_urgence(uuid)', 'fn_soignant_eligible_mission('),
        ('public.fn_recommander_soignants(uuid,integer)', 'fn_soignant_eligible_mission('),
        ('public.fn_vivier_disponibilites(date,text)', 'private.fn_comptes_meme_cohorte_test('),
        ('private.fn_resultats_recherche_soignants_etab(uuid,text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text)', 'private.fn_comptes_meme_cohorte_test(')
      ) AS t(signature, motif)
      LEFT JOIN pg_proc p ON p.oid = to_regprocedure(t.signature)
  LOOP
    IF v_rec.prosrc IS NULL OR strpos(v_rec.prosrc, v_rec.motif) = 0 THEN
      RAISE EXCEPTION 'REVUE_STORE test-garde : la porte % ne contient plus « % »', v_rec.signature, v_rec.motif;
    END IF;
  END LOOP;
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)'::regprocedure), 'est_compte_test') > 0
  THEN RAISE EXCEPTION 'REVUE_STORE test-garde : l''éligibilité redécide encore la cohorte localement'; END IF;
  -- A3. Lecteurs SECURITY DEFINER de missions ouvertes exposés à un compte (RPC du
  -- schéma public : elles contournent la RLS ; private n'est pas exposé à PostgREST).
  FOR v_rec IN
    SELECT n.nspname || '.' || p.proname AS nom, p.prosrc
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosecdef
       AND (has_function_privilege('authenticated', p.oid, 'EXECUTE') OR has_function_privilege('anon', p.oid, 'EXECUTE'))
       AND p.prosrc ~* '(from|join)\s+(public\.)?missions\M'
       AND p.prosrc ~* 'statut\s*(=\s*''OUVERTE''|IN\s*\([^)]*''OUVERTE'')'
     ORDER BY 1
  LOOP
    CONTINUE WHEN v_rec.nom = ANY (v_lecteurs_classes);
    IF v_rec.prosrc !~ '(fn_soignant_eligible_mission|fn_mission_lie_compte_test|est_compte_test|fn_soignant_voit_mission|fn_resultats_filtre_missions|fn_soignant_contactable_par_etablissement)' THEN
      RAISE EXCEPTION 'REVUE_STORE test-garde : % lit des missions ouvertes sans filtre de visibilité (cohorte, REVUE_STORE) ; l''aligner ou le classer', v_rec.nom;
    END IF;
  END LOOP;
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.fn_admin_generer_posts()'::regprocedure), 'NOT private.fn_mission_lie_compte_test(m.id)') = 0
     OR strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.fn_admin_generer_posts()'::regprocedure), 'NOT private.fn_mission_lie_compte_test(m3.id)') = 0
  THEN RAISE EXCEPTION 'REVUE_STORE test-garde : fn_admin_generer_posts compte des missions de test'; END IF;

  -- ── 3. Fixtures (SQL Auth direct : ni session, ni e-mail, ni hook) ─────────
  INSERT INTO public.parametres_systeme (cle, valeur, label, description, unite, val_min, val_max, categorie, avertissement, cablee)
  VALUES ('inscriptions_publiques_actives', 1, 'Inscriptions publiques actives', 'Fixture REVUE_STORE (transaction annulée).',
          'booléen', 0, 1, 'GENERAL', 'Fixture.', true)
  ON CONFLICT (cle) DO UPDATE SET valeur = 1;
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
  SELECT u.id, '00000000-0000-0000-0000-000000000000', u.email, 'authenticated', 'authenticated', u.meta::jsonb, now()
    FROM (VALUES
      (v_e, 'revue-store-e@example.invalid', '{"role":"ADMIN_ETABLISSEMENT","est_compte_test":true}'),
      (v_e2, 'revue-store-e2@example.invalid', '{"role":"ADMIN_ETABLISSEMENT","est_compte_test":true}'),
      (v_er, 'revue-store-er@example.invalid', '{"role":"ADMIN_ETABLISSEMENT"}'),
      (v_t, 'revue-store-t@example.invalid', '{"role":"SOIGNANT","est_compte_test":true}'),
      (v_t2, 'revue-store-t2@example.invalid', '{"role":"SOIGNANT","est_compte_test":true}'),
      (v_r, 'revue-store-r@example.invalid', '{"role":"SOIGNANT"}'),
      (v_adm, 'revue-store-adm@example.invalid', '{"role":"ADMIN_PLATEFORME"}')
    ) AS u(id, email, meta);
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal,
    adresse_lat, adresse_lng, email_contact, est_compte_test)
  VALUES
    (v_e, 'Fixture revue store', '99178000000101', 'CLINIQUE_PRIVEE', '1 rue du Test', 'Paris', '75002',
     48.8686, 2.3417, 'revue-store-e@example.invalid', true),
    (v_er, 'Fixture établissement réel', '99178000000102', 'CLINIQUE_PRIVEE', '2 rue du Test', 'Paris', '75002',
     48.8686, 2.3417, 'revue-store-er@example.invalid', false),
    (v_e2, 'Fixture établissement de test', '99178000000103', 'CLINIQUE_PRIVEE', '3 rue du Test', 'Paris', '75003',
     48.8640, 2.3600, 'revue-store-e2@example.invalid', true);
  INSERT INTO public.soignants (id, prenom, nom, email, profession, est_compte_test, rpps_verifie,
    disponible_urgence, tous_documents_valides, telephone, adresse_lat, adresse_lng, rayon_deplacement_km, urgence_rayon_km)
  VALUES
    (v_t, 'Fixture', 'Revue', 'revue-store-t@example.invalid', 'IDE', true, true, true, true, NULL, 48.8575, 2.3800, 50, 30),
    (v_t2, 'Fixture', 'Test', 'revue-store-t2@example.invalid', 'IDE', true, true, true, true, NULL, 48.8575, 2.3800, 50, 30),
    (v_r, 'Fixture', 'Reel', 'revue-store-r@example.invalid', 'IDE', false, true, true, true, NULL, 48.8575, 2.3800, 50, 30);
  IF (SELECT array_agg(est_compte_test ORDER BY id) FROM public.etablissements WHERE id IN (v_e, v_er, v_e2)) IS DISTINCT FROM ARRAY[true, false, true]
     OR (SELECT array_agg(est_compte_test ORDER BY id) FROM public.soignants WHERE id IN (v_t, v_r, v_t2)) IS DISTINCT FROM ARRAY[true, false, true]
  THEN RAISE EXCEPTION 'REVUE_STORE : cohortes de fixture inattendues'; END IF;
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
      FROM unnest(ARRAY[v_t, v_t2, v_r]) s;
  END LOOP;
  INSERT INTO public.membres_etablissement (etablissement_id, user_id, role, actif)
  SELECT x, x, 'PROPRIETAIRE', true FROM unnest(ARRAY[v_e, v_e2]) x
   WHERE NOT EXISTS (SELECT 1 FROM public.membres_etablissement WHERE etablissement_id = x AND user_id = x);
  INSERT INTO public.equipe_admin (user_id, nom, prenom, email, actif, acces_groupes)
  VALUES (v_adm, 'Revue store', 'Admin', 'revue-store-adm@example.invalid', true,
    ARRAY['Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats', 'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur']::text[]);
  -- Favoris de E et E2 (pour R, ligne orpheline : la RLS ne lui aurait rien montré).
  INSERT INTO public.favoris_soignant_etab (soignant_id, etablissement_id)
  SELECT s, x FROM unnest(ARRAY[v_t, v_t2, v_r]) s, unnest(ARRAY[v_e, v_e2]) x;
  -- Mission de test ordinaire de E2 (J+5, 6 h, moteur financier des déclencheurs ;
  -- rôle de service comme l'API établissement) : témoin positif des diffusions.
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le,
    taux_horaire_base, statut, type_contrat_recherche, mode_attribution)
  VALUES (v_m2, v_e2, 'Fixture mission de test ordinaire', 'IDE',
    ((v_aujourdhui + 5) + time '08:00') AT TIME ZONE 'Europe/Paris', ((v_aujourdhui + 5) + time '14:00') AT TIME ZONE 'Europe/Paris',
    30, 'OUVERTE', 'TOUS', 'CANDIDATURE');
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF (SELECT count(*) FROM public.notifications WHERE id_ressource = v_m2 AND type = 'FAVORI_NOUVELLE_MISSION'
        AND destinataire_id IN (v_t, v_t2)) <> 2
     OR EXISTS (SELECT 1 FROM public.notifications WHERE destinataire_id = v_r)
  THEN RAISE EXCEPTION 'REVUE_STORE : favoris à la création de la mission ordinaire (T et T2 attendus, jamais R)'; END IF;

  -- ── B. Refus des comptes réels ─────────────────────────────────────────────
  BEGIN
    INSERT INTO private.etablissements_revue_store (etablissement_id, motif) VALUES (v_er, 'Fixture : établissement réel');
    RAISE EXCEPTION 'REVUE_STORE B1 : un établissement réel a été désigné';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_msg = PG_EXCEPTION_HINT;
    IF v_msg IS DISTINCT FROM 'REVUE_STORE_ETABLISSEMENT_REEL' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO private.soignants_revue_store (soignant_id, motif) VALUES (v_r, 'Fixture : soignant réel');
    RAISE EXCEPTION 'REVUE_STORE B2 : un soignant réel a été désigné';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_msg = PG_EXCEPTION_HINT;
    IF v_msg IS DISTINCT FROM 'REVUE_STORE_SOIGNANT_REEL' THEN RAISE; END IF;
  END;
  -- Désignation forcée d'un établissement réel portant une mission REVUE_STORE :
  -- le job de retrait (distinct, validé seul) la retire ; la garantie lève.
  BEGIN
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le,
      taux_horaire_base, statut, type_contrat_recherche, mode_attribution, mission_source)
    VALUES (v_mx, v_er, 'Fixture REVUE_STORE forcée', 'IDE',
      ((v_aujourdhui + 9) + time '08:00') AT TIME ZONE 'Europe/Paris', ((v_aujourdhui + 9) + time '14:00') AT TIME ZONE 'Europe/Paris',
      30, 'OUVERTE', 'TOUS', 'CANDIDATURE', 'REVUE_STORE');
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    ALTER TABLE private.etablissements_revue_store DISABLE TRIGGER trg_verifier_designation_revue_store;
    INSERT INTO private.etablissements_revue_store (etablissement_id, motif) VALUES (v_er, 'Fixture : établissement réel');
    ALTER TABLE private.etablissements_revue_store ENABLE TRIGGER trg_verifier_designation_revue_store;
    v_n := private.fn_retirer_missions_revue_store_non_conformes();
    IF v_n < 1 OR (SELECT statut::text FROM public.missions WHERE id = v_mx) IS DISTINCT FROM 'EXPIREE'
    THEN RAISE EXCEPTION 'REVUE_STORE B3 : le retrait n''a pas retiré la mission REVUE_STORE d''un établissement réel (% retirée(s), %)',
           v_n, (SELECT to_jsonb(m) - 'description' FROM public.missions m WHERE m.id = v_mx); END IF;
    BEGIN
      PERFORM private.fn_garantir_missions_revue_store();
      RAISE EXCEPTION 'REVUE_STORE B4 : la garantie a accepté un établissement réel';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      GET STACKED DIAGNOSTICS v_msg = PG_EXCEPTION_HINT;
      IF v_msg IS DISTINCT FROM 'REVUE_STORE_ETABLISSEMENT_REEL' THEN RAISE; END IF;
    END;
    IF EXISTS (SELECT 1 FROM public.missions WHERE etablissement_id = v_er AND statut = 'OUVERTE')
    THEN RAISE EXCEPTION 'REVUE_STORE B5 : mission ouverte créée pour un établissement réel'; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;

  -- ── C. Stock ───────────────────────────────────────────────────────────────
  INSERT INTO private.etablissements_revue_store (etablissement_id, motif) VALUES (v_e, 'Fixture : établissement de revue');
  INSERT INTO private.soignants_revue_store (soignant_id, motif) VALUES (v_t, 'Fixture : soignant de revue');
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
     AND (m.fin_le AT TIME ZONE 'Europe/Paris')::time <= time '19:00'
     AND (m.fin_le AT TIME ZONE 'Europe/Paris')::date = (m.debut_le AT TIME ZONE 'Europe/Paris')::date
     AND m.duree_heures = 6 AND m.nb_creneaux = 1
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
  SELECT string_agg(n || '=' || COALESCE(current_setting(n, true), ''), ' ') INTO v_reglages
    FROM unnest(ARRAY['request.jwt.claims', 'request.jwt.claim.role', 'request.jwt.claim.sub',
      'jolene.creer_mission_context', 'jolene.planning_exact_managed', 'jolene.sync_in_progress',
      'jolene.tva_mission_managed']) AS n
   WHERE COALESCE(current_setting(n, true), '') NOT IN ('', 'false');
  IF v_reglages IS NOT NULL THEN
    RAISE EXCEPTION 'REVUE_STORE C4 : réglages de transaction non rétablis (%)', v_reglages;
  END IF;
  v_res := private.fn_garantir_missions_revue_store();
  IF (v_res->>'missions_creees')::integer <> 0 OR (v_res->>'missions_retirees')::integer <> 0
     OR (SELECT count(*) FROM public.missions WHERE etablissement_id = v_e AND statut = 'OUVERTE') <> 3
  THEN RAISE EXCEPTION 'REVUE_STORE C5 : second passage non idempotent (%)', v_res; END IF;
  -- À la création : aucun envoi pour les missions de revue (T a E en favori).
  IF EXISTS (SELECT 1 FROM public.notifications n, unnest(v_ids) i WHERE n.id_ressource = i OR n.lien LIKE '%' || i::text || '%')
     OR EXISTS (SELECT 1 FROM net.http_request_queue q, unnest(v_ids) i WHERE convert_from(q.body, 'UTF8') LIKE '%' || i::text || '%')
  THEN RAISE EXCEPTION 'REVUE_STORE E1 : un envoi désigne une mission de revue dès sa création'; END IF;

  -- Ancienneté de plus de 24 h pour les chemins qui attendent (vagues, relance, nettoyage).
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  FOR v_rec IN SELECT unnest(v_ids || v_m2) AS id LOOP
    PERFORM public.fn_test_update_mission(v_rec.id, jsonb_build_object('cree_le', now() - interval '25 hours'));
  END LOOP;
  PERFORM set_config('app.internal_operation', '', true);
  PERFORM set_config('jolene.creer_mission_context', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF (SELECT count(*) FROM public.missions WHERE id = ANY (v_ids || v_m2) AND cree_le < now() - interval '24 hours') <> 4
  THEN RAISE EXCEPTION 'REVUE_STORE : ancienneté de fixture non posée'; END IF;

  -- ── D. Nettoyage et protection de la source ────────────────────────────────
  BEGIN
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le,
      taux_horaire_base, statut, type_contrat_recherche, mode_attribution, mission_source)
    VALUES (v_mx, v_e2, 'Fixture REVUE_STORE hors désignation', 'IDE',
      ((v_aujourdhui + 9) + time '08:00') AT TIME ZONE 'Europe/Paris', ((v_aujourdhui + 9) + time '14:00') AT TIME ZONE 'Europe/Paris',
      30, 'OUVERTE', 'TOUS', 'CANDIDATURE', 'REVUE_STORE');
    PERFORM public.fn_test_update_mission(v_mx, jsonb_build_object('cree_le', now() - interval '25 hours'));
    PERFORM set_config('app.internal_operation', '', true);
    PERFORM set_config('jolene.creer_mission_context', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM public.fn_cleanup_missions_test();
    IF (SELECT count(*) FROM public.missions WHERE id = ANY (v_ids) AND statut = 'OUVERTE') <> 3
    THEN RAISE EXCEPTION 'REVUE_STORE D1 : une mission de revue de l''établissement désigné a été purgée'; END IF;
    IF EXISTS (SELECT 1 FROM public.missions WHERE id IN (v_m2, v_mx))
    THEN RAISE EXCEPTION 'REVUE_STORE D2 : le nettoyage épargne une mission de test ordinaire ou une REVUE_STORE hors désignation'; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;
  -- Aucun compte ne pose ni ne retire REVUE_STORE.
  FOR v_rec IN SELECT * FROM (VALUES (v_e, v_m1, NULL::text), (v_e2, v_m2, 'REVUE_STORE')) AS t(compte, mission, source) LOOP
    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_rec.compte::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_rec.compte, 'role', 'authenticated')::text, true);
      UPDATE public.missions SET mission_source = v_rec.source WHERE id = v_rec.mission;
      RAISE EXCEPTION 'REVUE_STORE D3 : un compte a modifié la source REVUE_STORE';
    EXCEPTION WHEN SQLSTATE '42501' THEN
      GET STACKED DIAGNOSTICS v_msg = PG_EXCEPTION_HINT;
      IF v_msg IS DISTINCT FROM 'REVUE_STORE_SOURCE_PROTEGEE' THEN RAISE; END IF;
    END;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);

  -- ── E. Diffusion : personne pour le stock, T et T2 pour la mission ordinaire ─
  IF public.fn_soignant_eligible_mission(v_t, v_m1, false) OR public.fn_soignant_eligible_mission(v_t2, v_m1, false)
     OR public.fn_soignant_eligible_mission(v_r, v_m1, false)
     OR NOT public.fn_soignant_eligible_mission(v_t, v_m2, true) OR NOT public.fn_soignant_eligible_mission(v_t2, v_m2, true)
     OR public.fn_soignant_eligible_mission(v_r, v_m2, false)
  THEN RAISE EXCEPTION 'REVUE_STORE E2 : éligibilité inattendue (stock jamais, mission ordinaire pour T et T2 seulement)'; END IF;
  -- Fan-outs bornés aux fixtures : les autres soignants éligibles à la mission
  -- ordinaire sont exclus par E2 le temps de la transaction.
  INSERT INTO public.exclusions (exclu_par, exclu_id, type_exclu_par, motif)
  SELECT v_e2, s.id, 'ETABLISSEMENT', 'Fixture REVUE_STORE'
    FROM public.soignants s
   WHERE s.id NOT IN (v_t, v_t2, v_r) AND public.fn_soignant_eligible_mission(s.id, v_m2, false)
  ON CONFLICT (exclu_par, exclu_id) DO NOTHING;

  -- Témoin positif : notification de T et T2 au sujet de la mission ordinaire
  -- (lien vers elle) ; vagues et matching inverse : par type, la file d'autres
  -- missions de test de la base pouvant passer avant (plafonds par soignant).
  FOR v_rec IN SELECT * FROM (VALUES
      ('vagues', 'MISSION_A_POURVOIR', false), ('relance', 'MISSION_A_POURVOIR', true),
      ('boost', 'MISSION_A_POURVOIR', true), ('matching_inverse', 'MISSION_A_POURVOIR', false),
      ('sauvegardees', 'FAVORI_MISSION_EXPIRE', true)
    ) AS t(chemin, type_notif, cible_m2)
  LOOP
    BEGIN
      SELECT count(*) FILTER (WHERE n.destinataire_id = v_t), count(*) FILTER (WHERE n.destinataire_id = v_t2)
        INTO v_t_avant, v_t2_avant
        FROM public.notifications n
       WHERE n.destinataire_id IN (v_t, v_t2) AND n.type = v_rec.type_notif
         AND (NOT v_rec.cible_m2 OR n.lien = '/soignant/missions/' || v_m2);
      SELECT count(*) INTO v_r_avant FROM public.notifications WHERE destinataire_id = v_r;
      SELECT count(*) INTO v_http_t2 FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_t2::text || '%';
      CASE v_rec.chemin
        WHEN 'vagues' THEN
          PERFORM public.fn_vagues_notification_urgentes();
        WHEN 'relance' THEN
          PERFORM public.fn_relancer_missions_sans_candidat();
        WHEN 'boost' THEN
          FOR v_n IN 1..2 LOOP
            PERFORM set_config('request.jwt.claim.sub', (CASE v_n WHEN 1 THEN v_e ELSE v_e2 END)::text, true);
            PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
            PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', CASE v_n WHEN 1 THEN v_e ELSE v_e2 END,
              'role', 'authenticated')::text, true);
            v_res := public.fn_booster_mission(CASE v_n WHEN 1 THEN v_m1 ELSE v_m2 END);
            IF (v_res->>'success')::boolean IS NOT TRUE OR (v_n = 1 AND (v_res->>'soignants_notifies')::integer <> 0)
            THEN RAISE EXCEPTION 'REVUE_STORE E boost % : %', v_n, v_res; END IF;
          END LOOP;
          PERFORM set_config('request.jwt.claim.sub', '', true);
          PERFORM set_config('request.jwt.claim.role', '', true);
          PERFORM set_config('request.jwt.claims', '', true);
        WHEN 'matching_inverse' THEN
          -- T n'est disponible que le jour d'une mission de revue : aucune ne lui est
          -- comptée (contrôle global ci-dessous) ; T2 et R le jour de la mission ordinaire.
          INSERT INTO public.disponibilites_soignant (soignant_id, jour, creneau)
          SELECT v_t, (debut_le AT TIME ZONE 'Europe/Paris')::date, 'JOURNEE' FROM public.missions WHERE id = v_m1
          UNION ALL
          SELECT s, (debut_le AT TIME ZONE 'Europe/Paris')::date, 'JOURNEE' FROM public.missions, unnest(ARRAY[v_t2, v_r]) s
           WHERE id = v_m2;
          PERFORM public.fn_matching_inverse_dispos();
        WHEN 'sauvegardees' THEN
          PERFORM set_config('request.jwt.claim.role', 'service_role', true);
          PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
          FOR v_n IN 1..2 LOOP
            PERFORM public.fn_test_update_mission(CASE v_n WHEN 1 THEN v_m1 ELSE v_m2 END,
              jsonb_build_object('debut_le', now() + interval '30 hours', 'fin_le', now() + interval '36 hours'));
          END LOOP;
          PERFORM set_config('app.internal_operation', '', true);
          PERFORM set_config('jolene.creer_mission_context', '', true);
          PERFORM set_config('request.jwt.claim.role', '', true);
          PERFORM set_config('request.jwt.claims', '', true);
          INSERT INTO public.missions_sauvegardees (soignant_id, mission_id)
          SELECT s, x FROM unnest(ARRAY[v_t, v_t2, v_r]) s, unnest(ARRAY[v_m1, v_m2]) x;
          PERFORM public.fn_notifier_favoris_expirants();
      END CASE;
      SELECT count(*) FILTER (WHERE n.destinataire_id = v_t), count(*) FILTER (WHERE n.destinataire_id = v_t2)
        INTO v_t_apres, v_t2_apres
        FROM public.notifications n
       WHERE n.destinataire_id IN (v_t, v_t2) AND n.type = v_rec.type_notif
         AND (NOT v_rec.cible_m2 OR n.lien = '/soignant/missions/' || v_m2);
      SELECT count(*) INTO v_r_apres FROM public.notifications WHERE destinataire_id = v_r;
      -- Personne, pas même T ni l'établissement de revue, n'est contacté au sujet du stock.
      IF EXISTS (SELECT 1 FROM public.notifications n, unnest(v_ids) i WHERE n.id_ressource = i OR n.lien LIKE '%' || i::text || '%')
         OR EXISTS (SELECT 1 FROM net.http_request_queue q, unnest(v_ids) i WHERE convert_from(q.body, 'UTF8') LIKE '%' || i::text || '%')
         OR EXISTS (SELECT 1 FROM public.notifications WHERE destinataire_id = v_e AND type = ANY (v_diffusions))
      THEN RAISE EXCEPTION 'REVUE_STORE E % : un envoi désigne une mission de revue', v_rec.chemin; END IF;
      IF v_r_apres <> v_r_avant
         OR EXISTS (SELECT 1 FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_r::text || '%')
      THEN RAISE EXCEPTION 'REVUE_STORE E % : le soignant réel a été contacté', v_rec.chemin; END IF;
      IF v_t2_apres <= v_t2_avant OR (v_rec.chemin <> 'matching_inverse' AND v_t_apres <= v_t_avant) THEN
        RAISE EXCEPTION 'REVUE_STORE E % : la mission de test ordinaire n''a pas été diffusée à la cohorte (T % → %, T2 % → %)',
          v_rec.chemin, v_t_avant, v_t_apres, v_t2_avant, v_t2_apres;
      END IF;
      IF v_jeton AND v_rec.chemin IN ('vagues', 'matching_inverse')
         AND (SELECT count(*) FROM net.http_request_queue q WHERE convert_from(q.body, 'UTF8') LIKE '%' || v_t2::text || '%') <= v_http_t2
      THEN RAISE EXCEPTION 'REVUE_STORE E % : aucun push en file pour T2 alors qu''un jeton de service existe', v_rec.chemin; END IF;
      RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
    EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
    END;
  END LOOP;

  -- Pool d'urgence (autorisation de send-push et send-sms) et alerte pool d'une mission.
  BEGIN
    FOR v_n IN 1..2 LOOP
      PERFORM set_config('request.jwt.claim.sub', (CASE v_n WHEN 1 THEN v_e ELSE v_e2 END)::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', CASE v_n WHEN 1 THEN v_e ELSE v_e2 END,
        'role', 'authenticated')::text, true);
      IF v_n = 1 AND (EXISTS (SELECT 1 FROM public.fn_pool_urgence_etablissement(v_e))
                      OR EXISTS (SELECT 1 FROM public.fn_soignants_urgence(v_m1)))
      THEN RAISE EXCEPTION 'REVUE_STORE E pool : le pool de l''établissement de revue n''est pas vide'; END IF;
      IF v_n = 2 AND (NOT EXISTS (SELECT 1 FROM public.fn_pool_urgence_etablissement(v_e2) p WHERE p.soignant_id = v_t2)
                      OR EXISTS (SELECT 1 FROM public.fn_pool_urgence_etablissement(v_e2) p WHERE p.soignant_id = v_r)
                      OR NOT EXISTS (SELECT 1 FROM public.fn_soignants_urgence(v_m2) p WHERE p.soignant_id = v_t2)
                      OR EXISTS (SELECT 1 FROM public.fn_soignants_urgence(v_m2) p WHERE p.soignant_id = v_r))
      THEN RAISE EXCEPTION 'REVUE_STORE E pool : T2 absent ou R présent dans le pool d''un établissement de test'; END IF;
    END LOOP;
    IF private.fn_soignant_visible_pool_etablissement(v_e, v_t, v_e) OR private.fn_soignant_visible_pool_etablissement(v_e2, v_r, v_e2)
       OR NOT private.fn_soignant_visible_pool_etablissement(v_e2, v_t2, v_e2)
    THEN RAISE EXCEPTION 'REVUE_STORE E pool : le jumeau conversation pool diverge du pool'; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;
  -- Digest hebdomadaire (fn_digest_hebdo_cibles compte par l'éligibilité, porte A2) :
  -- le stock ne compte pour personne, la mission ordinaire pour T et T2.
  IF (SELECT count(*) FROM public.missions m, unnest(ARRAY[v_t, v_t2, v_r]) s
       WHERE m.id = ANY (v_ids) AND m.statut = 'OUVERTE' AND public.fn_soignant_eligible_mission(s, m.id, false)) <> 0
     OR NOT public.fn_soignant_eligible_mission(v_t2, v_m2, false)
     OR strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.fn_digest_hebdo_cibles(integer)'::regprocedure),
               'public.fn_soignant_eligible_mission(s.id, m.id, false)') = 0
  THEN RAISE EXCEPTION 'REVUE_STORE E digest : le stock compte dans le digest, ou le digest ne passe plus par l''éligibilité'; END IF;

  -- ── F. Visibilité, réponse et textes publics ───────────────────────────────
  -- Lecture PostgREST (rôle authenticated, RLS) : NULL = non attendu (lecture
  -- inter-établissements hors sujet).
  FOR v_rec IN SELECT * FROM (VALUES (v_t, 3, 1), (v_t2, 0, 1), (v_r, 0, 0), (v_e, 3, NULL::integer))
                 AS t(compte, revue, ordinaire) LOOP
    PERFORM set_config('request.jwt.claim.sub', v_rec.compte::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_rec.compte, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL row_security = on';
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) FILTER (WHERE m.id = ANY (v_ids)), count(*) FILTER (WHERE m.id = v_m2)
      INTO v_vus_revue, v_vus_ordinaire
      FROM public.missions m WHERE m.id = ANY (v_ids || v_m2);
    EXECUTE 'RESET ROLE';
    IF v_vus_revue <> v_rec.revue OR (v_rec.ordinaire IS NOT NULL AND v_vus_ordinaire <> v_rec.ordinaire) THEN
      RAISE EXCEPTION 'REVUE_STORE F1 : % lit % mission(s) de revue et % ordinaire(s), attendu % et %',
        v_rec.compte, v_vus_revue, v_vus_ordinaire, v_rec.revue, v_rec.ordinaire;
    END IF;
    IF v_rec.compte <> v_e THEN
      v_res := public.fn_mes_favoris_etablissements();
      IF (SELECT (x->>'nb_missions_ouvertes')::integer FROM jsonb_array_elements(v_res) x
           WHERE (x->>'etablissement_id')::uuid = v_e) IS DISTINCT FROM v_rec.revue
      THEN RAISE EXCEPTION 'REVUE_STORE F2 : favoris de % : % mission(s) de E, attendu %', v_rec.compte, v_res, v_rec.revue; END IF;
    END IF;
  END LOOP;
  -- Textes de posts publics : aucune mission de test.
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'REVUE_STORE F3 : fixture administrateur refusée'; END IF;
  v_res := public.fn_admin_generer_posts();
  IF COALESCE((SELECT (x->>'nb')::integer FROM jsonb_array_elements(v_res) x WHERE x->>'profession' = 'IDE'), 0)
     IS DISTINCT FROM (SELECT count(*)::integer FROM public.missions m
                        WHERE m.statut = 'OUVERTE' AND m.profession_requise = 'IDE' AND NOT private.fn_mission_lie_compte_test(m.id))
  THEN RAISE EXCEPTION 'REVUE_STORE F3 : posts publics comptant des missions de test (%)', v_res; END IF;
  -- Réponse : T2 et R refusés, T accepté (candidature EN_ATTENTE).
  FOR v_rec IN SELECT * FROM (VALUES (v_t2, false), (v_r, false), (v_t, true)) AS t(compte, accepte) LOOP
    PERFORM set_config('request.jwt.claim.sub', v_rec.compte::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_rec.compte, 'role', 'authenticated')::text, true);
    v_res := public.fn_postuler_mission(v_m1, 'Fixture REVUE_STORE', 'SALARIE');
    IF EXISTS (SELECT 1 FROM public.candidatures WHERE mission_id = v_m1 AND soignant_id = v_rec.compte AND statut = 'EN_ATTENTE')
       IS DISTINCT FROM v_rec.accepte
    THEN RAISE EXCEPTION 'REVUE_STORE F4 : candidature de % (%)', v_rec.compte, v_res; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  -- Seuls les deux comptes de revue sont contactés au sujet du stock (réponse de T à E).
  IF EXISTS (SELECT 1 FROM public.notifications n, unnest(v_ids) i
              WHERE (n.id_ressource = i OR n.lien LIKE '%' || i::text || '%')
                AND (n.destinataire_id NOT IN (v_e, v_t) OR n.type = ANY (v_diffusions)))
  THEN RAISE EXCEPTION 'REVUE_STORE F5 : une notification du stock vise un autre compte que la paire de revue'; END IF;

  -- Retrait puis remplacement d'une mission qui approche : sa candidature est refusée.
  BEGIN
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    PERFORM public.fn_test_update_mission(v_m1, jsonb_build_object('debut_le', now() + interval '2 days',
      'fin_le', now() + interval '2 days 6 hours'));
    PERFORM set_config('app.internal_operation', '', true);
    PERFORM set_config('jolene.creer_mission_context', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    v_res := private.fn_garantir_missions_revue_store();
    IF (v_res->>'missions_retirees')::integer <> 1 OR (v_res->>'missions_creees')::integer <> 1
       OR (SELECT statut::text FROM public.missions WHERE id = v_m1) <> 'EXPIREE'
       OR (SELECT statut::text FROM public.candidatures WHERE mission_id = v_m1 AND soignant_id = v_t) <> 'REFUSEE'
       OR (SELECT count(*) FROM public.missions WHERE etablissement_id = v_e AND statut = 'OUVERTE'
             AND mission_source = 'REVUE_STORE' AND debut_le > now() + interval '3 days') <> 3
    THEN RAISE EXCEPTION 'REVUE_STORE C6 : retrait et remplacement inattendus (%)', v_res; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;

  -- ── G. Suppressions de comptes ─────────────────────────────────────────────
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_e::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_e, 'role', 'authenticated')::text, true);
    v_res := public.fn_supprimer_mon_compte_etablissement();
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    IF (v_res->>'success')::boolean IS NOT TRUE
       OR EXISTS (SELECT 1 FROM public.missions WHERE etablissement_id = v_e AND statut = 'OUVERTE')
       OR (SELECT count(*) FROM public.missions WHERE id = ANY (v_ids) AND statut = 'EXPIREE') <> 3
       OR (SELECT statut::text FROM public.candidatures WHERE mission_id = v_m1 AND soignant_id = v_t) <> 'REFUSEE'
       OR EXISTS (SELECT 1 FROM private.etablissements_revue_store WHERE etablissement_id = v_e)
       OR (SELECT supprime_le FROM public.etablissements WHERE id = v_e) IS NULL
    THEN RAISE EXCEPTION 'REVUE_STORE G1 : suppression du compte de revue (%)', v_res; END IF;
    v_res := private.fn_garantir_missions_revue_store();
    IF (v_res->>'success')::boolean IS NOT TRUE OR EXISTS (SELECT 1 FROM public.missions WHERE etablissement_id = v_e AND statut = 'OUVERTE')
    THEN RAISE EXCEPTION 'REVUE_STORE G2 : garantie après suppression (%)', v_res; END IF;
    -- Désignation restée sur un établissement supprimé : ignoré, sans échec.
    ALTER TABLE private.etablissements_revue_store DISABLE TRIGGER trg_verifier_designation_revue_store;
    INSERT INTO private.etablissements_revue_store (etablissement_id, motif) VALUES (v_e, 'Fixture : établissement supprimé');
    ALTER TABLE private.etablissements_revue_store ENABLE TRIGGER trg_verifier_designation_revue_store;
    v_res := private.fn_garantir_missions_revue_store();
    IF (v_res->>'success')::boolean IS NOT TRUE OR (v_res->>'etablissements_ignores')::integer < 1
       OR EXISTS (SELECT 1 FROM public.missions WHERE etablissement_id = v_e AND statut = 'OUVERTE')
    THEN RAISE EXCEPTION 'REVUE_STORE G3 : établissement désigné supprimé non ignoré (%)', v_res; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;
  -- Suppression du compte du soignant de revue. Soignant désigné sans pièce
  -- justificative : l'anonymisation d'un profil aux pièces vérifiées passe par
  -- l'invalidation des preuves, que la protection des documents refuse en session
  -- utilisateur ; ce chemin ne dépend pas des missions de revue et reste intact.
  BEGIN
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
    VALUES (v_t3, '00000000-0000-0000-0000-000000000000', 'revue-store-t3@example.invalid', 'authenticated', 'authenticated',
            '{"role":"SOIGNANT","est_compte_test":true}'::jsonb, now());
    INSERT INTO public.soignants (id, prenom, nom, email, profession, est_compte_test)
    VALUES (v_t3, 'Fixture', 'Revue sans piece', 'revue-store-t3@example.invalid', 'IDE', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    DELETE FROM private.soignants_revue_store WHERE soignant_id = v_t;
    INSERT INTO private.soignants_revue_store (soignant_id, motif) VALUES (v_t3, 'Fixture : soignant de revue sans pièce');
    IF NOT private.fn_est_soignant_revue_store(v_t3) OR private.fn_est_soignant_revue_store(v_t)
    THEN RAISE EXCEPTION 'REVUE_STORE G4 : désignation du soignant de revue de remplacement inattendue'; END IF;
    PERFORM set_config('request.jwt.claim.sub', v_t3::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_t3, 'role', 'authenticated')::text, true);
    v_res := public.fn_supprimer_mon_compte();
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    v_res2 := private.fn_garantir_missions_revue_store();
    IF (v_res->>'success')::boolean IS NOT TRUE OR private.fn_est_soignant_revue_store(v_t3)
       OR (v_res2->>'success')::boolean IS NOT TRUE
       OR (SELECT count(*) FROM public.missions WHERE etablissement_id = v_e AND statut = 'OUVERTE' AND mission_source = 'REVUE_STORE') <> 3
    THEN RAISE EXCEPTION 'REVUE_STORE G4 : suppression du soignant de revue (% / %)', v_res, v_res2; END IF;
    RAISE EXCEPTION USING ERRCODE = v_sentinelle, MESSAGE = 'sentinelle';
  EXCEPTION WHEN SQLSTATE 'RS999' THEN NULL;
  END;

  RAISE NOTICE 'REVUE_STORE : test-gardes (% émetteurs), refus réels, stock 3, idempotence, retrait, nettoyage, diffusion nulle, visibilité, suppressions vérifiés (jeton de service : %).',
    cardinality(v_noms), v_jeton;
END
$revue_store_suite$;
ROLLBACK;
