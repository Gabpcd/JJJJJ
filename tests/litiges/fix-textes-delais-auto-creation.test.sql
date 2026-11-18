-- ============================================================
-- Litiges auto-créés — textes de délai dérivés du paramètre
-- (migration 20261118152150_litiges_auto_textes_delais.sql, suite D12)
-- ============================================================
-- Prérequis : migration 20261118152150 appliquée. Fonctionne quelle que soit
-- la valeur de parametres_litiges.delai_contestation_pointage_h (48 avant
-- #1140, 72 après) : le banc lit le paramètre, rien n'est figé.
-- Usage : psql "$DB_URL" -f tests/litiges/fix-textes-delais-auto-creation.test.sql
-- Base locale ou staging uniquement. Le banc REFUSE (message [CONTEXTE]
-- REFUSÉ, aucune fixture) si pg_cron est absent (cron.job introuvable :
-- contexte non vérifiable) ou si un cron est actif (production).
--
-- Scénarios (fixture de cp8a-t1/t2, horodatages dérivés du paramètre) :
--   A. présence absente validée il y a (délai + 1) h → litige ABSENCE_SOIGNANT,
--      motif « … dans les <délai>h », notification sans « Répondez sous »,
--      SMS LITIGE_OUVERTURE sans « Répondez sous 72h », raison d'audit dérivée ;
--   B. départ anticipé (4 h sur 8) validé il y a (délai + 1) h → notification
--      sans promesse, raison d'audit dérivée ;
--   C. présence absente validée il y a (délai - 1) h → aucun litige (fenêtre
--      encore ouverte : même source que le texte).
--
-- Volets cron : probants sur une mission réelle seulement
-- (private.fn_mission_est_reelle). trg_forcer_compte_test_prelaunch pose
-- est_compte_test tant que parametres_systeme.inscriptions_publiques_actives
-- <> 1 (0 sur une branche Supabase ou en staging, 1 en prod depuis le
-- 27/09/2026) : le banc pose ce paramètre à 1 dans la transaction, après la
-- garde de contexte. Si la mission reste « test » (session non backend), le
-- volet affiche NON PROBANT, jamais PASS ni FAIL (même garde que les bancs
-- cp8a-t1, cp8a-t2 et fix-bonus révisés dans #1140).
-- Tout est annulé (ROLLBACK) : aucune pollution de la base.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Litiges auto-créés — textes de délai dérivés du paramètre =='

BEGIN;

DO $textes_delais$
DECLARE
  v_delai        integer;
  v_cron_actif   boolean;
  v_etab_id      uuid := gen_random_uuid();
  v_soignant_id  uuid := gen_random_uuid();
  v_mission_a    uuid := gen_random_uuid();
  v_mission_b    uuid := gen_random_uuid();
  v_mission_c    uuid := gen_random_uuid();
  v_reelle_a     boolean;
  v_reelle_b     boolean;
  v_reelle_c     boolean;
  v_litige_a     public.litiges%ROWTYPE;
  v_litige_b     public.litiges%ROWTYPE;
  v_corps        text;
  v_sms          text;
  v_raison       text;
  v_result       jsonb;
  c_non_probant  constant text := 'NON PROBANT — mission dérivée test (est_compte_test posé par trg_forcer_compte_test_prelaunch : inscriptions_publiques_actives <> 1 ou session non backend) : fn_auto_creation_litiges_presence l''ignore (private.fn_mission_est_reelle)';
BEGIN
  -- Garde de contexte, avant toute écriture : refus explicite, pas de FAIL.
  IF pg_catalog.to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE '[CONTEXTE] REFUSÉ — cron.job introuvable (pg_cron absent) : contexte isolé non vérifiable, banc non exécuté';
    RETURN;
  END IF;
  EXECUTE 'SELECT EXISTS (SELECT 1 FROM cron.job WHERE active)' INTO v_cron_actif;
  IF v_cron_actif THEN
    RAISE NOTICE '[CONTEXTE] REFUSÉ — cron actif (base de production ?) : banc non exécuté';
    RETURN;
  END IF;

  -- Missions réelles pour le cron : posé dans la transaction, annulé par le ROLLBACK.
  UPDATE public.parametres_systeme SET valeur = 1 WHERE cle = 'inscriptions_publiques_actives';

  SELECT valeur::integer INTO v_delai
    FROM public.parametres_litiges
   WHERE cle = 'delai_contestation_pointage_h';
  IF v_delai IS NULL OR v_delai < 2 THEN
    RAISE NOTICE '[PARAM] FAIL — delai_contestation_pointage_h absent ou invalide (%)', v_delai;
    RETURN;
  END IF;
  RAISE NOTICE '[PARAM] delai_contestation_pointage_h = %', v_delai;

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact
  ) VALUES (
    v_etab_id, 'TEXTES_DELAIS_Etab', '12345678900188', 'HOPITAL_PUBLIC',
    '1 rue test', 'Paris', '75001', 'textes-delais@test.local'
  );

  INSERT INTO public.soignants (
    id, nom, prenom, email, profession, telephone
  ) VALUES (
    v_soignant_id, 'TEXTES_DELAIS_Nom', 'Alice',
    'textes-delais-' || v_soignant_id || '@test.local', 'IDE', '0600000000'
  );

  -- Mission de 8 h terminée 15 h avant la validation (comme cp8a-t1).
  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id
  )
  SELECT m.id, v_etab_id, m.intitule, 'IDE',
         now() - make_interval(hours => m.decalage + 23),
         now() - make_interval(hours => m.decalage + 15),
         8, 25, 'TERMINEE', v_soignant_id
    FROM (VALUES
      (v_mission_a, 'TEXTES_DELAIS_A', v_delai + 1),
      (v_mission_b, 'TEXTES_DELAIS_B', v_delai + 1),
      (v_mission_c, 'TEXTES_DELAIS_C', v_delai - 1)
    ) AS m(id, intitule, decalage);

  INSERT INTO public.presences (
    id, mission_id, soignant_id,
    valide_par_etablissement, valide_le,
    heures_reelles, motif_litige
  ) VALUES
    (gen_random_uuid(), v_mission_a, v_soignant_id,
     TRUE, now() - make_interval(hours => v_delai + 1),
     0, 'Soignant absent, pas de justificatif reçu'),
    (gen_random_uuid(), v_mission_b, v_soignant_id,
     TRUE, now() - make_interval(hours => v_delai + 1),
     4, 'Départ anticipé constaté'),
    (gen_random_uuid(), v_mission_c, v_soignant_id,
     TRUE, now() - make_interval(hours => v_delai - 1),
     0, 'Soignant absent, fenêtre encore ouverte');

  v_reelle_a := private.fn_mission_est_reelle(v_mission_a);
  v_reelle_b := private.fn_mission_est_reelle(v_mission_b);
  v_reelle_c := private.fn_mission_est_reelle(v_mission_c);
  v_result := public.fn_auto_creation_litiges_presence();

  -- A. Absence : motif, notification, SMS et audit.
  SELECT * INTO v_litige_a
    FROM public.litiges
   WHERE mission_id = v_mission_a AND type_litige = 'ABSENCE_SOIGNANT';
  IF NOT FOUND AND v_reelle_a IS NOT TRUE THEN
    RAISE NOTICE '[A] %', c_non_probant;
  ELSIF NOT FOUND THEN
    RAISE NOTICE '[A] FAIL — aucun litige ABSENCE_SOIGNANT (result=%)', v_result;
  ELSE
    IF v_litige_a.motif IS DISTINCT FROM
       format('Auto-création : soignant marqué absent sans contestation dans les %sh', v_delai) THEN
      RAISE NOTICE '[A] FAIL — motif=%', v_litige_a.motif;
    ELSE
      RAISE NOTICE '[A] PASS — motif dérivé : %', v_litige_a.motif;
    END IF;

    SELECT n.corps INTO v_corps
      FROM public.notifications n
     WHERE n.id_ressource = v_litige_a.id AND n.type = 'LITIGE_OUVERTURE';
    IF v_corps IS DISTINCT FROM 'Votre établissement a signalé une absence.' THEN
      RAISE NOTICE '[A-notif] FAIL — corps=%', v_corps;
    ELSE
      RAISE NOTICE '[A-notif] PASS — %', v_corps;
    END IF;

    SELECT q.data ->> 'contenu' INTO v_sms
      FROM public.email_queue q
     WHERE q.type = 'SMS_LITIGE_OUVERTURE'
       AND q.data ->> 'litige_id' = v_litige_a.id::text;
    IF v_sms IS DISTINCT FROM 'un litige ABSENCE_SOIGNANT a été ouvert sur votre mission.' THEN
      RAISE NOTICE '[A-sms] FAIL — contenu=%', v_sms;
    ELSE
      RAISE NOTICE '[A-sms] PASS — %', v_sms;
    END IF;

    SELECT j.details ->> 'raison' INTO v_raison
      FROM public.journaux_audit j
     WHERE j.action = 'LITIGE_AUTO_CREATION' AND j.id_ressource = v_litige_a.id;
    IF v_raison IS DISTINCT FROM
       format('Absence non contestée dans les %sh post-validation présence', v_delai) THEN
      RAISE NOTICE '[A-audit] FAIL — raison=%', v_raison;
    ELSE
      RAISE NOTICE '[A-audit] PASS — %', v_raison;
    END IF;
  END IF;

  -- B. Départ anticipé : notification et audit.
  SELECT * INTO v_litige_b
    FROM public.litiges
   WHERE mission_id = v_mission_b AND type_litige = 'DEPART_ANTICIPE';
  IF NOT FOUND AND v_reelle_b IS NOT TRUE THEN
    RAISE NOTICE '[B] %', c_non_probant;
  ELSIF NOT FOUND THEN
    RAISE NOTICE '[B] FAIL — aucun litige DEPART_ANTICIPE (result=%)', v_result;
  ELSE
    SELECT n.corps INTO v_corps
      FROM public.notifications n
     WHERE n.id_ressource = v_litige_b.id AND n.type = 'LITIGE_OUVERTURE';
    SELECT j.details ->> 'raison' INTO v_raison
      FROM public.journaux_audit j
     WHERE j.action = 'LITIGE_AUTO_CREATION' AND j.id_ressource = v_litige_b.id;
    IF v_corps IS DISTINCT FROM 'Votre établissement a signalé un départ anticipé.' THEN
      RAISE NOTICE '[B-notif] FAIL — corps=%', v_corps;
    ELSIF v_raison IS DISTINCT FROM
          format('Départ anticipé (< 80 %% heures prévues) non contesté dans les %sh', v_delai) THEN
      RAISE NOTICE '[B-audit] FAIL — raison=%', v_raison;
    ELSE
      RAISE NOTICE '[B] PASS — % / %', v_corps, v_raison;
    END IF;
  END IF;

  -- C. Fenêtre encore ouverte : aucun litige. Probant seulement si la mission
  -- est réelle (sinon « aucun litige » serait vrai pour une autre raison).
  IF v_reelle_c IS NOT TRUE THEN
    RAISE NOTICE '[C] %', c_non_probant;
  ELSIF EXISTS (SELECT 1 FROM public.litiges WHERE mission_id = v_mission_c) THEN
    RAISE NOTICE '[C] FAIL — litige créé avant la fin de la fenêtre de % h', v_delai;
  ELSE
    RAISE NOTICE '[C] PASS — aucun litige avant % h', v_delai;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[TEXTES_DELAIS] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $textes_delais$;

ROLLBACK;

\echo ''
\echo '== Fin litiges auto-créés — textes de délai =='
