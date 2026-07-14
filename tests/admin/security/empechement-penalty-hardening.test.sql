-- Empêchement impérieux : sérialisation, audit obligatoire, compteur, score
-- et garantie de remplacement durables. Toutes les fixtures sont annulées
-- par le ROLLBACK du harness CI ; app.test_mode interdit tout envoi externe.
\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE pg_temp.empechement_rpc_results (
  branche text PRIMARY KEY,
  resultat jsonb NOT NULL
) ON COMMIT DROP;
GRANT SELECT, INSERT ON TABLE pg_temp.empechement_rpc_results TO authenticated;

DO $empechement_penalty_setup$
DECLARE
  v_admin constant uuid := 'ec710000-0000-4000-8000-000000000001';
  -- Source test : ce profil reproduit volontairement un ancien compte ayant
  -- aussi une appartenance établissement LECTURE_SEULE.
  v_soignant constant uuid := 'ec710000-0000-4000-8000-000000000002';
  v_etablissement constant uuid := 'ec710000-0000-4000-8000-000000000003';
  v_mission_annulee constant uuid := 'ec710000-0000-4000-8000-000000000004';
  v_mission_audit constant uuid := 'ec710000-0000-4000-8000-000000000005';
  v_mission_terminee constant uuid := 'ec710000-0000-4000-8000-000000000006';
  v_mission_rpc constant uuid := 'ec710000-0000-4000-8000-000000000007';
  -- Source réelle + mission future ASSIGNEE garantie.
  v_soignant_reel constant uuid := 'ec710000-0000-4000-8000-000000000008';
  v_etablissement_reel constant uuid := 'ec710000-0000-4000-8000-000000000009';
  v_mission_assignee_reelle constant uuid := 'ec710000-0000-4000-8000-000000000010';
  -- Deux IADE de pool, identiques hors classe réel/démonstration.
  v_pool_iade_reel constant uuid := 'ec710000-0000-4000-8000-000000000011';
  v_pool_iade_test constant uuid := 'ec710000-0000-4000-8000-000000000012';
  v_soignant_escrow constant uuid := 'ec710000-0000-4000-8000-000000000013';
  v_mission_escrow constant uuid := 'ec710000-0000-4000-8000-000000000014';
  v_escrow constant uuid := 'ec710000-0000-4000-8000-000000000015';
  -- Mission déjà démarrée mais restée ASSIGNEE : elle emprunte la
  -- branche interruption en cours et ne doit plus jamais devenir TERMINEE.
  v_mission_assignee_demarree constant uuid := 'ec710000-0000-4000-8000-000000000016';
  -- Couple original/enfant no-show historique, sans aucun audit EPI.
  v_mission_noshow_originale constant uuid := 'ec710000-0000-4000-8000-000000000017';
  v_mission_noshow_enfant constant uuid := 'ec710000-0000-4000-8000-000000000018';
  v_etablissement_bloque constant uuid := 'ec710000-0000-4000-8000-000000000019';
  v_mission_noshow_bloquee constant uuid := 'ec710000-0000-4000-8000-000000000020';
  v_mission_noshow_initie constant uuid := 'ec710000-0000-4000-8000-000000000021';
  v_escrow_noshow_initie constant uuid := 'ec710000-0000-4000-8000-000000000022';
  v_mission_noshow_debite constant uuid := 'ec710000-0000-4000-8000-000000000023';
  v_escrow_noshow_debite constant uuid := 'ec710000-0000-4000-8000-000000000024';
  v_soignant_noshow constant uuid := 'ec710000-0000-4000-8000-000000000025';
  v_mission_noshow_finance_ambigue constant uuid := 'ec710000-0000-4000-8000-000000000026';
  v_escrow_noshow_finance_ambigue constant uuid := 'ec710000-0000-4000-8000-000000000027';
  v_mission_chaine_epi_a constant uuid := 'ec710000-0000-4000-8000-000000000028';
  v_mission_chaine_noshow_b constant uuid := 'ec710000-0000-4000-8000-000000000029';
  v_mission_chaine_enfant_c constant uuid := 'ec710000-0000-4000-8000-000000000030';
  v_rpc_definition text;
  v_resync_definition text;
  v_score_definition text;
  v_helper_definition text;
  v_desistement_definition text;
  v_guard_definition text;
  v_auto_urgent_definition text;
  v_first_before_trigger text;
  v_helper_security_definer boolean;
  v_result jsonb;
  v_score_base numeric;
  v_total_annulees integer;
  v_doc record;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('app.test_mode', 'true', true);
  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Fixture transactionnelle empêchement impérieux',
    true
  );

  SELECT lower(pg_get_functiondef(
    'public.fn_declarer_empechement_imperieux(uuid,date,date)'::regprocedure
  )) INTO STRICT v_rpc_definition;
  SELECT lower(pg_get_functiondef(
    'private.fn_resynchroniser_compteurs_soignant(uuid)'::regprocedure
  )) INTO STRICT v_resync_definition;
  SELECT lower(pg_get_functiondef(
    'public.fn_calculer_score_fiabilite_v2(uuid,text)'::regprocedure
  )) INTO STRICT v_score_definition;
  SELECT lower(pg_get_functiondef(
    'private.fn_diffuser_pool_urgence_interne(uuid)'::regprocedure
  )) INTO STRICT v_helper_definition;
  SELECT lower(pg_get_functiondef(
    'public.fn_trg_desistement_garanti()'::regprocedure
  )) INTO STRICT v_desistement_definition;
  SELECT lower(pg_get_functiondef(
    'private.fn_guard_contexte_empechement_mission()'::regprocedure
  )) INTO STRICT v_guard_definition;
  SELECT lower(pg_get_functiondef(
    'public.fn_trg_auto_notify_mission_urgente()'::regprocedure
  )) INTO STRICT v_auto_urgent_definition;

  IF position('pg_advisory_xact_lock' IN v_rpc_definition) = 0
     OR position('hashtextextended' IN v_rpc_definition) = 0
     OR position('jolene.empechement.' IN v_rpc_definition) = 0
     OR position('for update' IN v_rpc_definition) = 0
     OR position('select count(*) into v_n12' IN v_rpc_definition) = 0
     OR position('pg_advisory_xact_lock' IN v_rpc_definition)
          >= position('for update' IN v_rpc_definition)
     OR position('for update' IN v_rpc_definition)
          >= position('select count(*) into v_n12' IN v_rpc_definition) THEN
    RAISE EXCEPTION 'EPI-T1 : verrou soignant/mission absent ou placé après le quota';
  END IF;

  IF position('v_audit_result := fn_ecrire_audit_safe' IN v_rpc_definition) = 0
     OR position('la déclaration ne peut pas être journalisée' IN v_rpc_definition) = 0
     OR position('v_previous_system_update' IN v_rpc_definition) = 0
     OR position('v_notifications_avant' IN v_rpc_definition) = 0
     OR position('mission_urgente' IN v_rpc_definition) = 0
     OR position('insert into public.missions' IN v_rpc_definition) = 0
     OR position('remplacement_de_mission_id' IN v_rpc_definition) = 0
     OR position('exception when others' IN v_rpc_definition) = 0
     OR position('raise;' IN v_rpc_definition) = 0
     OR position(
       'set_config(''jolene.system_update'', '''', true)'
       IN v_rpc_definition
     ) > 0 THEN
    RAISE EXCEPTION 'EPI-T2 : audit fail-closed, remplacement ou restauration GUC incomplet';
  END IF;

  -- Le garde doit être le tout premier BEFORE trigger de missions. Il valide
  -- les trois phases et compare strictement les lignes OLD/NEW pour FLAG et
  -- CLOSE avant que les protections historiques puissent réécrire NEW.
  SELECT t.tgname
  INTO v_first_before_trigger
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.missions'::regclass
    AND NOT t.tgisinternal
    AND (t.tgtype::integer & 2) = 2
    AND (t.tgtype::integer & (4 | 16)) <> 0
  ORDER BY t.tgname
  LIMIT 1;
  IF v_first_before_trigger IS DISTINCT FROM 'dec_00_guard_empechement'
     OR NOT EXISTS (
       SELECT 1
       FROM pg_trigger t
       WHERE t.tgrelid = 'public.missions'::regclass
         AND t.tgname = 'dec_00_guard_empechement'
         AND NOT t.tgisinternal
         AND (t.tgtype::integer & 2) = 2
         AND (t.tgtype::integer & 4) = 4
         AND (t.tgtype::integer & 16) = 16
     ) THEN
    RAISE EXCEPTION 'EPI-T2A : le garde empêchement n''est pas le premier BEFORE INSERT/UPDATE';
  END IF;

  IF position('flag:' IN v_guard_definition) = 0
     OR position('close:' IN v_guard_definition) = 0
     OR position('replacement:' IN v_guard_definition) = 0
     OR position('flag:' IN v_rpc_definition) = 0
     OR position('close:' IN v_rpc_definition) = 0
     OR position('replacement:' IN v_rpc_definition) = 0
     OR (
       length(v_guard_definition)
       - length(replace(v_guard_definition, 'to_jsonb(new)', ''))
     ) / length('to_jsonb(new)') < 2
     OR (
       length(v_guard_definition)
       - length(replace(v_guard_definition, 'to_jsonb(old)', ''))
     ) / length('to_jsonb(old)') < 2
     OR position('v_previous_empechement_context' IN v_rpc_definition) = 0
     OR position('v_previous_empechement_validated' IN v_rpc_definition) = 0
     OR (
       length(v_rpc_definition)
       - length(replace(
         v_rpc_definition, 'jolene.empechement_mission_context', ''
       ))
     ) / length('jolene.empechement_mission_context') < 6
     OR (
       length(v_rpc_definition)
       - length(replace(
         v_rpc_definition, 'jolene.empechement_mission_validated', ''
       ))
     ) / length('jolene.empechement_mission_validated') < 6 THEN
    RAISE EXCEPTION 'EPI-T2B : phases, comparaison OLD/NEW ou restauration du contexte incomplètes';
  END IF;

  -- La RPC ne refait jamais le fan-out : l'AFTER trigger urgent en est
  -- l'unique propriétaire et utilise le filtre canonique. Cela évite les
  -- doublons tout en rendant pool_alerte mesurable.
  IF position('private.fn_diffuser_pool_urgence_interne' IN v_rpc_definition) > 0
     OR position('fn_soignant_eligible_mission' IN v_auto_urgent_definition) = 0
     OR position('app.test_mode' IN v_auto_urgent_definition) = 0
     OR position('mission_urgente' IN v_auto_urgent_definition) = 0 THEN
    RAISE EXCEPTION 'EPI-T2C : le fan-out urgent n''a plus une source unique et testable';
  END IF;

  IF position('annulee_par_soignant' IN v_resync_definition) = 0
     OR position('annulation_empechement_imperieux' IN v_resync_definition) = 0
     OR position('union' IN v_resync_definition) = 0
     OR position('ja.id_ressource is not null' IN v_resync_definition) = 0
     OR position('not exists' IN v_resync_definition) = 0
     OR position('ja_epi.action = ''annulation_empechement_imperieux''' IN v_resync_definition) = 0
     OR position('details @> ''{"depassement": true}''::jsonb' IN v_resync_definition) = 0
     OR position('for update' IN v_resync_definition) = 0 THEN
    RAISE EXCEPTION 'EPI-T3 : compteur canonique sans union mission/audit';
  END IF;

  IF position('v_empechement_malus' IN v_score_definition) = 0
     OR position('details @> ''{"depassement": true}''::jsonb' IN v_score_definition) = 0
     OR position('count(distinct ja.id_ressource)' IN v_score_definition) = 0
     OR position('m_engagement.statut = ''annulee_par_soignant''' IN v_score_definition) = 0
     OR position('ja_epi.action = ''annulation_empechement_imperieux''' IN v_score_definition) = 0
     OR position('v_previous_system_update' IN v_score_definition) = 0
     OR position('for update' IN v_score_definition) = 0 THEN
    RAISE EXCEPTION 'EPI-T4 : malus durable absent du score v2';
  END IF;

  SELECT p.prosecdef
  INTO STRICT v_helper_security_definer
  FROM pg_proc p
  WHERE p.oid = 'private.fn_diffuser_pool_urgence_interne(uuid)'::regprocedure;
  IF v_helper_security_definer
     OR has_function_privilege(
       'anon', 'private.fn_diffuser_pool_urgence_interne(uuid)', 'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'private.fn_diffuser_pool_urgence_interne(uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'private.fn_diffuser_pool_urgence_interne(uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'EPI-T5 : helper pool privé exposé à un rôle API';
  END IF;
  IF position('s.est_compte_test' IN v_helper_definition) = 0
     OR position('v_mission.etab_est_compte_test' IN v_helper_definition) = 0
     OR position('order by coalesce(s.score_fiabilite' IN v_helper_definition) = 0 THEN
    RAISE EXCEPTION 'EPI-T5B : fan-out pool non cloisonné ou non déterministe';
  END IF;
  IF position('private.fn_diffuser_pool_urgence_interne' IN v_desistement_definition) = 0
     OR position('new.est_urgente' IN v_desistement_definition) = 0
     OR position('is not true' IN v_desistement_definition) = 0 THEN
    RAISE EXCEPTION 'EPI-T5C : désistement garanti non urgent sans fan-out';
  END IF;
  IF NOT has_function_privilege(
    'authenticated',
    'public.fn_declarer_empechement_imperieux(uuid,date,date)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'EPI-T5D : la RPC n''est pas appelable par authenticated';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_admin,
      '00000000-0000-0000-0000-000000000000',
      'admin-empechement-hardening@test.local',
      'authenticated',
      'authenticated',
      '{"role":"ADMIN_PLATEFORME"}',
      now()
    ),
    (
      v_soignant,
      '00000000-0000-0000-0000-000000000000',
      'playwright-test-caregiver-empechement-hardening@jolene.app',
      'authenticated',
      'authenticated',
      -- Temporairement établissement pour créer la coexistence historique ;
      -- la source serveur redevient SOIGNANT avant l'appel de la RPC.
      '{"role":"ETABLISSEMENT"}',
      now()
    ),
    (
      v_soignant_reel,
      '00000000-0000-0000-0000-000000000000',
      'caregiver-real-empechement-hardening@test.local',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    ),
    (
      v_pool_iade_reel,
      '00000000-0000-0000-0000-000000000000',
      'pool-iade-real-empechement-hardening@test.local',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    ),
    (
      v_pool_iade_test,
      '00000000-0000-0000-0000-000000000000',
      'playwright-test-pool-iade-empechement-hardening@jolene.app',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    ),
    (
      v_soignant_escrow,
      '00000000-0000-0000-0000-000000000000',
      'caregiver-escrow-empechement-hardening@test.local',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    ),
    (
      v_soignant_noshow,
      '00000000-0000-0000-0000-000000000000',
      'caregiver-noshow-empechement-hardening@test.local',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    );

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin,
    'Empêchement',
    'Admin',
    'admin-empechement-hardening@test.local',
    true,
    ARRAY[
      'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
      'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur'
    ]::text[]
  );

  INSERT INTO public.etablissements (
    id, nom, siret, finess, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_compte_test,
    statut_verification, peut_publier_missions,
    siret_verifie, finess_verifie, representant_identite_verifiee,
    rattachement_verifie, contrat_service_signe
  ) VALUES
    (
      v_etablissement,
      'Fixture empêchement hardening test',
      '99140000000500',
      '991400500',
      'CLINIQUE_PRIVEE',
      '6 rue du Test',
      'Paris',
      '75006',
      'etablissement-empechement-hardening@test.local',
      true,
      'VERIFIE', true, true, true, true, true, true
    ),
    (
      v_etablissement_reel,
      'Fixture empêchement hardening réelle',
      '99140000000501',
      '991400501',
      'CLINIQUE_PRIVEE',
      '7 rue du Test',
      'Paris',
      '75007',
      'etablissement-real-empechement-hardening@test.local',
      false,
      'VERIFIE', true, true, true, true, true, true
    ),
    (
      v_etablissement_bloque,
      'Fixture no-show publication bloquée',
      '99140000000502',
      '991400502',
      'CLINIQUE_PRIVEE',
      '8 rue du Test',
      'Paris',
      '75008',
      'etablissement-bloque-noshow-hardening@test.local',
      false,
      'EN_COURS', false, true, true, true, true, true
    );

  -- Le garde famille interdit à juste titre de créer aujourd'hui un nouveau
  -- dual-role. La fixture reconstruit donc, dans le ROLLBACK, un cas historique
  -- explicitement supporté par le garde empêchement : membre d'abord, profil
  -- soignant ensuite, puis source de vérité Auth remise à SOIGNANT.
  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, actif
  ) VALUES (
    v_etablissement, v_soignant, 'LECTURE_SEULE', true
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test, type_exercice,
    score_fiabilite, rpps_verifie, disponible_urgence, statut_compte
  ) VALUES
    (
      v_soignant,
      'Fixture',
      'Empêchement',
      'playwright-test-caregiver-empechement-hardening@jolene.app',
      'IDE',
      true,
      'SALARIE',
      50,
      true,
      false,
      'ACTIF'
    ),
    (
      v_soignant_reel,
      'Fixture',
      'Empêchement réel',
      'caregiver-real-empechement-hardening@test.local',
      'IDE',
      false,
      'SALARIE',
      50,
      true,
      false,
      'ACTIF'
    ),
    (
      v_pool_iade_reel,
      'Pool',
      'IADE réel',
      'pool-iade-real-empechement-hardening@test.local',
      'IADE',
      false,
      'SALARIE',
      90,
      true,
      true,
      'ACTIF'
    ),
    (
      v_pool_iade_test,
      'Pool',
      'IADE test',
      'playwright-test-pool-iade-empechement-hardening@jolene.app',
      'IADE',
      true,
      'SALARIE',
      89,
      true,
      true,
      'ACTIF'
    ),
    (
      v_soignant_escrow,
      'Fixture',
      'Empêchement escrow',
      'caregiver-escrow-empechement-hardening@test.local',
      'IDE',
      false,
      'SALARIE',
      50,
      true,
      false,
      'ACTIF'
    ),
    (
      v_soignant_noshow,
      'Fixture',
      'No-show bloqué',
      'caregiver-noshow-empechement-hardening@test.local',
      'IDE',
      false,
      'SALARIE',
      50,
      true,
      false,
      'ACTIF'
    );

  UPDATE auth.users
  SET raw_app_meta_data = '{"role":"SOIGNANT"}'::jsonb
  WHERE id = v_soignant;
  INSERT INTO public.types_comptes_auth (
    user_id, type_compte, finalise_le
  ) VALUES (
    v_soignant, 'SOIGNANT', now()
  ) ON CONFLICT (user_id) DO UPDATE
  SET type_compte = EXCLUDED.type_compte,
      finalise_le = EXCLUDED.finalise_le;

  -- Chaque IADE reçoit toutes les preuves salariées critiques courantes. Le
  -- diplôme certifie explicitement IADE ; RPPS_ADELI est satisfait par le
  -- drapeau registre vérifié du profil.
  FOR v_doc IN
    SELECT drp.type_document, drp.a_expiration
    FROM public.documents_requis_par_profession drp
    WHERE drp.profession = 'IADE'
      AND drp.est_critique IS TRUE
      AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
      AND drp.type_document <> 'RPPS_ADELI'
  LOOP
    INSERT INTO public.documents_soignants (
      soignant_id, type_document, s3_cle, nom_fichier,
      statut_verification, est_critique, valide_jusqua, resultat_ia
    ) VALUES
      (
        v_pool_iade_reel,
        v_doc.type_document,
        'tests/empechement/pool-reel/' || lower(v_doc.type_document::text),
        'pool-reel-' || lower(v_doc.type_document::text) || '.pdf',
        'VERIFIE',
        true,
        CASE WHEN v_doc.a_expiration THEN current_date + 365 ELSE NULL END,
        CASE WHEN v_doc.type_document = 'DIPLOME'
          THEN '{"profession_certifiee":"IADE"}'::jsonb
          ELSE '{}'::jsonb
        END
      ),
      (
        v_pool_iade_test,
        v_doc.type_document,
        'tests/empechement/pool-test/' || lower(v_doc.type_document::text),
        'pool-test-' || lower(v_doc.type_document::text) || '.pdf',
        'VERIFIE',
        true,
        CASE WHEN v_doc.a_expiration THEN current_date + 365 ELSE NULL END,
        CASE WHEN v_doc.type_document = 'DIPLOME'
          THEN '{"profession_certifiee":"IADE"}'::jsonb
          ELSE '{}'::jsonb
        END
      );
  END LOOP;

  -- Les trois IDE présents sur des missions ASSIGNEE doivent franchir le
  -- même gate documentaire que les vrais utilisateurs. La fixture suit la
  -- matrice active (TOUS + SALARIE_ONLY) afin de rester exhaustive si la
  -- liste des preuves critiques évolue ; RPPS_ADELI est satisfait par le
  -- drapeau registre vérifié du profil.
  FOR v_doc IN
    SELECT drp.type_document, drp.a_expiration
    FROM public.documents_requis_par_profession drp
    WHERE drp.profession = 'IDE'
      AND drp.est_critique IS TRUE
      AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
      AND drp.type_document <> 'RPPS_ADELI'
  LOOP
    INSERT INTO public.documents_soignants (
      soignant_id, type_document, s3_cle, nom_fichier,
      statut_verification, est_critique, valide_jusqua, resultat_ia
    )
    SELECT
      fixture.soignant_id,
      v_doc.type_document,
      'tests/empechement/' || fixture.cle || '/'
        || lower(v_doc.type_document::text),
      fixture.cle || '-' || lower(v_doc.type_document::text) || '.pdf',
      'VERIFIE',
      true,
      CASE WHEN v_doc.a_expiration THEN current_date + 365 ELSE NULL END,
      CASE WHEN v_doc.type_document = 'DIPLOME'
        THEN '{"profession_certifiee":"IDE"}'::jsonb
        ELSE '{}'::jsonb
      END
    FROM (VALUES
      (v_soignant_reel, 'ide-reel'),
      (v_soignant_escrow, 'ide-escrow'),
      (v_soignant_noshow, 'ide-noshow')
    ) AS fixture(soignant_id, cle);
  END LOOP;

  -- Le setup reconstruit plus bas quatre no-shows concurrents du même profil,
  -- état volontairement impossible à créer via l'application. Seul le garde
  -- de chevauchement est suspendu pendant la construction des missions ; les
  -- documents, contrats, dates et contrôles de temps de travail restent actifs.
  EXECUTE 'ALTER TABLE public.missions DISABLE TRIGGER dec_chevauchement';

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    soignant_assigne_id, type_contrat_recherche, type_contrat_applique,
    mode_attribution,
    est_urgente, garantie_remplacement, mode_remuneration,
    retrocession_pct, mission_source
  ) VALUES
    (
      v_mission_annulee, v_etablissement, 'Fixture annulation canonique',
      'IDE', now() + interval '18 years', now() + interval '18 years 8 hours',
      8, 20, 'ANNULEE_PAR_SOIGNANT', v_soignant, 'SALARIE', 'SALARIE', 'CANDIDATURE',
      false, false, 'TAUX_HORAIRE', NULL, 'CANDIDATURE'
    ),
    (
      v_mission_audit, v_etablissement, 'Fixture audit seul',
      'IDE', now() + interval '19 years', now() + interval '19 years 8 hours',
      8, 20, 'OUVERTE', NULL, 'SALARIE', NULL, 'CANDIDATURE', false, false,
      'TAUX_HORAIRE', NULL, 'CANDIDATURE'
    ),
    (
      v_mission_terminee, v_etablissement, 'Fixture score de base',
      'IDE', now() + interval '20 years', now() + interval '20 years 8 hours',
      8, 20, 'LITIGE', v_soignant, 'SALARIE', 'SALARIE', 'CANDIDATURE', false, false,
      'TAUX_HORAIRE', NULL, 'CANDIDATURE'
    ),
    (
      -- Mission réellement commencée : l'originale reste la preuve de
      -- l'exécution et une nouvelle mission couvre seulement le temps restant.
      v_mission_rpc, v_etablissement, 'Fixture RPC empêchement en cours',
      'IDE', now() - interval '30 minutes', now() + interval '7 hours 30 minutes',
      8, 20, 'EN_COURS', v_soignant, 'SALARIE', 'SALARIE', 'CANDIDATURE', false, true,
      'TAUX_HORAIRE', NULL, 'CANDIDATURE'
    ),
    (
      -- Mission réelle future : l'originale sera clôturée et une nouvelle
      -- mission urgente conservera exactement son mode financier.
      v_mission_assignee_reelle, v_etablissement_reel,
      'Fixture RPC empêchement assignée réelle',
      'IDE', now() + interval '20 hours', now() + interval '28 hours',
      8, 20, 'ASSIGNEE', v_soignant_reel, 'SALARIE', 'SALARIE', 'CANDIDATURE', false, true,
      'RETROCESSION', 45, 'CANDIDATURE'
    ),
    (
      -- Même branche avec un débit escrow actif : la RPC doit utiliser le
      -- circuit de remboursement transactionnel avant tout remplacement.
      v_mission_escrow, v_etablissement_reel,
      'Fixture RPC empêchement escrow',
      'IDE', now() + interval '44 hours', now() + interval '52 hours',
      8, 20, 'ASSIGNEE', v_soignant_escrow, 'SALARIE', 'SALARIE', 'CANDIDATURE', false, true,
      'TAUX_HORAIRE', NULL, 'CANDIDATURE'
    ),
    (
      -- Un retard du cron ASSIGNEE -> EN_COURS ne doit pas transformer une
      -- interruption réelle en mission terminable sur les heures planifiées.
      v_mission_assignee_demarree, v_etablissement_reel,
      'Fixture EPI assignée déjà démarrée',
      'IDE', now() - interval '45 minutes', now() + interval '7 hours 15 minutes',
      8, 20, 'ASSIGNEE', v_soignant_escrow, 'SALARIE', 'SALARIE', 'CANDIDATURE', false, true,
      'TAUX_HORAIRE', NULL, 'CANDIDATURE'
    );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    soignant_assigne_id, type_contrat_recherche, type_contrat_applique,
    mode_attribution,
    est_urgente, garantie_remplacement, mode_remuneration,
    retrocession_pct, mission_source, absence_sans_prevenir
  ) VALUES (
    v_mission_noshow_originale, v_etablissement_reel,
    'Fixture originale no-show sans audit EPI',
    'IDE', now() - interval '50 minutes', now() + interval '6 hours',
    8, 20, 'ABSENCE', v_soignant_reel, 'SALARIE', 'SALARIE', 'CANDIDATURE',
    false, true, 'TAUX_HORAIRE', NULL, 'CANDIDATURE', true
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, description, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    type_contrat_recherche, mode_attribution, est_urgente, niveau_urgence,
    garantie_remplacement, mode_remuneration, retrocession_pct,
    mission_source, remplacement_de_mission_id
  ) VALUES (
    v_mission_noshow_enfant, v_etablissement_reel,
    'REMPLACEMENT URGENT — Fixture originale no-show sans audit EPI',
    E'Fixture no-show\n\n[Mission de remplacement générée automatiquement — garantie Jolene]',
    'IDE', now() + interval '15 minutes', now() + interval '6 hours',
    5.75, 20, 'OUVERTE', 'SALARIE', 'PREMIER_ARRIVE', true, 3,
    true, 'TAUX_HORAIRE', NULL, 'REMPLACEMENT',
    v_mission_noshow_originale
  );

  -- Chaîne de remplacement : A est interrompue par EPI, B devient un
  -- no-show, C est son enfant. L'ascendance complète doit exclure à la fois
  -- l'auteur/assigné de A et l'assigné de B de la candidature à C.
  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    soignant_assigne_id, type_contrat_recherche, mode_attribution,
    garantie_remplacement, mode_remuneration, mission_source,
    est_arret_maladie, arret_maladie_declare_le
  ) VALUES (
    v_mission_chaine_epi_a, v_etablissement_reel,
    'Fixture chaîne A — EPI', 'IDE',
    now() - interval '55 minutes', now() + interval '5 hours',
    8, 20, 'ANNULEE_PAR_SOIGNANT', v_soignant_reel,
    'SALARIE', 'CANDIDATURE', true, 'TAUX_HORAIRE', 'CANDIDATURE',
    true, now()
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    soignant_assigne_id, type_contrat_recherche, mode_attribution,
    garantie_remplacement, mode_remuneration, mission_source,
    remplacement_de_mission_id, absence_sans_prevenir
  ) VALUES (
    v_mission_chaine_noshow_b, v_etablissement_reel,
    'Fixture chaîne B — no-show', 'IDE',
    now() - interval '50 minutes', now() + interval '5 hours',
    6.5, 20, 'ABSENCE', v_soignant_noshow,
    'SALARIE', 'PREMIER_ARRIVE', true, 'TAUX_HORAIRE', 'REMPLACEMENT',
    v_mission_chaine_epi_a, true
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    type_contrat_recherche, mode_attribution, est_urgente, niveau_urgence,
    garantie_remplacement, mode_remuneration, mission_source,
    remplacement_de_mission_id
  ) VALUES (
    v_mission_chaine_enfant_c, v_etablissement_reel,
    'Fixture chaîne C — remplacement', 'IDE',
    now() + interval '15 minutes', now() + interval '5 hours',
    4.75, 20, 'OUVERTE', 'SALARIE', 'PREMIER_ARRIVE', true, 3,
    true, 'TAUX_HORAIRE', 'REMPLACEMENT', v_mission_chaine_noshow_b
  );

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_soignant_reel, 'SOIGNANT', 'ANNULATION_EMPECHEMENT_IMPERIEUX',
    'mission', v_mission_chaine_epi_a,
    '{"fixture":"chaine-epi-noshow","depassement":false}'::jsonb
  );

  -- Trois no-shows garantis sur un établissement non publiable. Les rails
  -- sans paiement, INITIE propre et DEBITE doivent tous classer l'originale
  -- ABSENCE sans publier d'enfant ; les deux derniers couvrent en plus la
  -- neutralisation financière sûre avant la revue admin. Ces quatre lignes
  -- simulent un lot concurrent impossible à créer via l'application pour un
  -- même soignant. La conformité documentaire est vérifiée explicitement
  -- avant de construire cet état historique ; le garde de chevauchement est
  -- réactivé avant les appels métier testés ensuite.
  IF NOT public.fn_documents_ok_pour_mission(v_soignant_noshow, 'SALARIE') THEN
    RAISE EXCEPTION 'Fixture no-show : justificatifs IDE salariés incomplets';
  END IF;

  INSERT INTO public.missions (
      id, etablissement_id, intitule, profession_requise,
      debut_le, fin_le, duree_heures, taux_horaire_base, statut,
      soignant_assigne_id, type_contrat_recherche, type_contrat_applique,
      mode_attribution,
      est_urgente, garantie_remplacement, mode_remuneration,
      retrocession_pct, mission_source
    ) VALUES
      (
        v_mission_noshow_bloquee, v_etablissement_bloque,
        'Fixture no-show gate sans escrow',
        'IDE', now() - interval '45 minutes', now() + interval '6 hours',
        7, 20, 'ASSIGNEE', v_soignant_noshow, 'SALARIE', 'SALARIE', 'CANDIDATURE',
        false, true, 'TAUX_HORAIRE', NULL, 'CANDIDATURE'
      ),
      (
        v_mission_noshow_initie, v_etablissement_bloque,
        'Fixture no-show gate escrow INITIE',
        'IDE', now() - interval '46 minutes', now() + interval '6 hours',
        7.17, 20, 'ASSIGNEE', v_soignant_noshow, 'SALARIE', 'SALARIE', 'CANDIDATURE',
        false, true, 'TAUX_HORAIRE', NULL, 'CANDIDATURE'
      ),
      (
        v_mission_noshow_debite, v_etablissement_bloque,
        'Fixture no-show gate escrow DEBITE',
        'IDE', now() - interval '47 minutes', now() + interval '6 hours',
        7.33, 20, 'ASSIGNEE', v_soignant_noshow, 'SALARIE', 'SALARIE', 'CANDIDATURE',
        false, true, 'TAUX_HORAIRE', NULL, 'CANDIDATURE'
      ),
      (
        -- Établissement publiable mais rail déjà ambigu : la seule cause
        -- de revue doit être financière, sans aucun enfant publié.
        v_mission_noshow_finance_ambigue, v_etablissement_reel,
        'Fixture no-show escrow RELEASE_PLANIFIE',
        'IDE', now() - interval '48 minutes', now() + interval '6 hours',
        7.5, 20, 'ASSIGNEE', v_soignant_noshow, 'SALARIE', 'SALARIE', 'CANDIDATURE',
        false, true, 'TAUX_HORAIRE', NULL, 'CANDIDATURE'
      );

  EXECUTE 'ALTER TABLE public.missions ENABLE TRIGGER dec_chevauchement';

  IF (
    SELECT count(*)
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.id IN (
      v_mission_noshow_bloquee,
      v_mission_noshow_initie,
      v_mission_noshow_debite,
      v_mission_noshow_finance_ambigue
    )
      AND m.statut = 'ASSIGNEE'
      AND m.soignant_assigne_id = v_soignant_noshow
      AND m.type_contrat_applique = 'SALARIE'
      AND m.debut_le < now() - interval '30 minutes'
      AND m.debut_le > now() - interval '1 hour'
      AND m.fin_le > now() + interval '1 hour'
  ) <> 4 THEN
    RAISE EXCEPTION 'Fixture no-show : état concurrent incomplet après restauration des triggers';
  END IF;

  INSERT INTO public.paiements_escrow (
    id, mission_id, etablissement_id, soignant_id,
    montant_total_cents, commission_cents, honoraires_cents,
    methode_debit, stripe_payment_intent_id, stripe_charge_id,
    statut, debite_le
  ) VALUES (
    v_escrow, v_mission_escrow, v_etablissement_reel, v_soignant_escrow,
    10000, 1000, 9000, 'CARTE', 'pi_epiEscrowFixture',
    'ch_epiEscrowFixture', 'DEBITE', now()
  );

  INSERT INTO public.paiements_escrow (
    id, mission_id, etablissement_id, soignant_id,
    montant_total_cents, commission_cents, honoraires_cents,
    methode_debit, stripe_payment_intent_id, stripe_charge_id,
    statut, debite_le
  ) VALUES
    (
      v_escrow_noshow_initie, v_mission_noshow_initie,
      v_etablissement_bloque, v_soignant_noshow,
      12000, 1200, 10800, 'CARTE', NULL, NULL, 'INITIE', NULL
    ),
    (
      v_escrow_noshow_debite, v_mission_noshow_debite,
      v_etablissement_bloque, v_soignant_noshow,
      20000, 2000, 18000, 'CARTE',
      'pi_noShowDebiteFixture', 'ch_noShowDebiteFixture', 'DEBITE', now()
    ),
    (
      v_escrow_noshow_finance_ambigue, v_mission_noshow_finance_ambigue,
      v_etablissement_reel, v_soignant_noshow,
      30000, 3000, 27000, 'CARTE',
      'pi_noShowAmbiguFixture', 'ch_noShowAmbiguFixture',
      'RELEASE_PLANIFIE', now()
    );

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    -- Une attestation non pénalisée et sans statut annulé ne doit jamais
    -- gonfler le compteur. La mission annulée voisine reste, elle, ordinaire.
    v_soignant, 'SOIGNANT', 'ANNULATION_EMPECHEMENT_IMPERIEUX',
    'mission', v_mission_audit, '{"fixture":"audit-seul"}'::jsonb
  );

  PERFORM set_config('jolene.system_update', 'sentinelle-epi', true);
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant);
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant);
  SELECT total_missions_annulees
  INTO STRICT v_total_annulees
  FROM public.soignants
  WHERE id = v_soignant;
  IF v_total_annulees IS DISTINCT FROM 1
     OR current_setting('jolene.system_update', true)
          IS DISTINCT FROM 'sentinelle-epi' THEN
    RAISE EXCEPTION 'EPI-T6 : compteur non durable/idempotent ou GUC perdue : %',
      v_total_annulees;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  UPDATE public.missions
  SET statut = 'TERMINEE'
  WHERE id = v_mission_terminee;

  PERFORM set_config('request.jwt.claim.sub', v_soignant::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  PERFORM set_config('jolene.system_update', 'sentinelle-epi', true);
  v_result := public.fn_calculer_score_fiabilite_v2(
    v_soignant, 'fixture_avant_empechement'
  );
  v_score_base := (v_result->>'score')::numeric;
  IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE
     OR v_score_base IS NULL
     OR (v_result->>'empechement_malus')::numeric IS DISTINCT FROM 0::numeric
     OR current_setting('jolene.system_update', true)
          IS DISTINCT FROM 'sentinelle-epi' THEN
    RAISE EXCEPTION 'EPI-T7 : score de base/GUC incohérent : %', v_result;
  END IF;
  INSERT INTO pg_temp.empechement_rpc_results (branche, resultat)
  VALUES ('score_base', v_result);

  INSERT INTO pg_temp.empechement_rpc_results (branche, resultat)
  SELECT 'source_reelle_avant', jsonb_build_object(
    'score', s.score_fiabilite,
    'total_missions_annulees', s.total_missions_annulees
  )
  FROM public.soignants s
  WHERE s.id = v_soignant_reel;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  UPDATE public.parametres_systeme
  SET valeur = 2
  WHERE cle = 'annulations_justifiees_max_12m';

  -- Les trois sentinelles doivent survivre aux deux appels et à leurs
  -- sous-blocs EXCEPTION. app.test_mode neutralise push/email/SMS.
  PERFORM set_config('jolene.system_update', 'sentinelle-epi', true);
  PERFORM set_config(
    'jolene.empechement_mission_context', 'sentinelle-contexte-epi', true
  );
  PERFORM set_config(
    'jolene.empechement_mission_validated', 'sentinelle-validation-epi', true
  );
END;
$empechement_penalty_setup$;

-- Premier appel PostgREST simulé sous le vrai rôle SQL authenticated : la
-- source et l'établissement sont réels et le quota autorise cette attestation.
SELECT set_config(
  'request.jwt.claim.sub',
  'ec710000-0000-4000-8000-000000000008',
  true
);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"ec710000-0000-4000-8000-000000000008","role":"authenticated","aal":"aal1"}',
  true
);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.empechement_rpc_results (branche, resultat)
SELECT
  'assignee_dates_hors_mission',
  public.fn_declarer_empechement_imperieux(
    'ec710000-0000-4000-8000-000000000010'::uuid,
    current_date + 30,
    current_date + 30
  );
INSERT INTO pg_temp.empechement_rpc_results (branche, resultat)
SELECT
  'assignee_reelle',
  public.fn_declarer_empechement_imperieux(
    'ec710000-0000-4000-8000-000000000010'::uuid,
    current_date,
    current_date + 3
  );
RESET ROLE;

-- Un débit escrow existant doit être gelé et placé dans la queue de
-- remboursement avant que l'originale ne soit clôturée et remplacée.
SELECT set_config(
  'request.jwt.claim.sub',
  'ec710000-0000-4000-8000-000000000013',
  true
);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"ec710000-0000-4000-8000-000000000013","role":"authenticated","aal":"aal1"}',
  true
);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.empechement_rpc_results (branche, resultat)
SELECT
  'assignee_demarree',
  public.fn_declarer_empechement_imperieux(
    'ec710000-0000-4000-8000-000000000016'::uuid,
    current_date,
    current_date + 1
  );
INSERT INTO pg_temp.empechement_rpc_results (branche, resultat)
SELECT
  'assignee_escrow',
  public.fn_declarer_empechement_imperieux(
    'ec710000-0000-4000-8000-000000000014'::uuid,
    current_date,
    current_date + 3
  );
RESET ROLE;

-- Même service_role, cron ou admin : une mission interrompue ne peut pas
-- déclencher la cascade financière TERMINEE tant que les heures effectives
-- n'ont pas été réconciliées par un futur flux dédié.
DO $assert_hard_stop_assignee_demarree$
DECLARE
  v_refus_terminee boolean := false;
BEGIN
  BEGIN
    UPDATE public.missions
       SET statut = 'TERMINEE', modifie_le = now()
     WHERE id = 'ec710000-0000-4000-8000-000000000016'::uuid;
  EXCEPTION WHEN check_violation THEN
    v_refus_terminee := true;
  END;

  IF v_refus_terminee IS NOT TRUE THEN
    RAISE EXCEPTION
      'EPI-T10D : une mission ASSIGNEE démarrée et interrompue a pu devenir TERMINEE';
  END IF;
END;
$assert_hard_stop_assignee_demarree$;

-- La seconde branche doit dépasser le quota pour conserver la non-régression
-- compteur/score historique. La mutation du paramètre reste service-role.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- fn_detecter_noshow_et_remplacer est un worker global. Dans une base liée,
-- neutraliser transactionnellement toutes les missions préexistantes éligibles
-- garantit que le test ne touche que ses quatre fixtures et ne déclenche aucun
-- fan-out externe. Le ROLLBACK retire aussi ces marqueurs.
INSERT INTO public.notifications (
  destinataire_id, type, titre, corps, lien, type_destinataire
)
SELECT
  m.etablissement_id,
  'SYSTEM',
  'Aucun pointage — isolation test transactionnelle',
  'Marqueur temporaire du test de non-régression no-show.',
  '/etablissement/missions/' || m.id,
  'ETABLISSEMENT'
FROM public.missions m
WHERE m.id NOT IN (
    'ec710000-0000-4000-8000-000000000020'::uuid,
    'ec710000-0000-4000-8000-000000000021'::uuid,
    'ec710000-0000-4000-8000-000000000023'::uuid,
    'ec710000-0000-4000-8000-000000000026'::uuid
  )
  AND m.statut IN ('ASSIGNEE', 'EN_COURS')
  AND m.soignant_assigne_id IS NOT NULL
  AND COALESCE(m.est_arret_maladie, false) = false
  AND m.debut_le < now() - interval '30 minutes'
  AND m.debut_le > now() - interval '4 hours'
  AND m.fin_le > now() + interval '1 hour'
  AND NOT EXISTS (
    SELECT 1 FROM public.presences p
    WHERE p.mission_id = m.id AND p.soignant_id = m.soignant_assigne_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.missions r
    WHERE r.remplacement_de_mission_id = m.id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.destinataire_id = m.etablissement_id
      AND n.type = 'SYSTEM'
      AND n.lien = '/etablissement/missions/' || m.id
      AND n.titre LIKE 'Aucun pointage%'
      AND n.cree_le > now() - interval '6 hours'
  );

INSERT INTO pg_temp.empechement_rpc_results (branche, resultat)
SELECT 'noshow_bloque', public.fn_detecter_noshow_et_remplacer();

DO $preparer_depassement$
BEGIN
  UPDATE public.parametres_systeme
  SET valeur = 0
  WHERE cle = 'annulations_justifiees_max_12m';
  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET score_fiabilite = 62
  WHERE id = 'ec710000-0000-4000-8000-000000000002'::uuid;
  PERFORM set_config('jolene.system_update', 'sentinelle-epi', true);
END;
$preparer_depassement$;

-- Branche test EN_COURS et dual-role LECTURE_SEULE. Sans le contexte validé,
-- FLAG ou REPLACEMENT serait bloqué par le RBAC établissement.
SELECT set_config(
  'request.jwt.claim.sub',
  'ec710000-0000-4000-8000-000000000002',
  true
);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"ec710000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}',
  true
);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.empechement_rpc_results (branche, resultat)
SELECT
  'en_cours_test',
  public.fn_declarer_empechement_imperieux(
    'ec710000-0000-4000-8000-000000000007'::uuid,
    current_date,
    current_date + 1
  );
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $empechement_penalty_assertions$
DECLARE
  v_admin constant uuid := 'ec710000-0000-4000-8000-000000000001';
  v_soignant constant uuid := 'ec710000-0000-4000-8000-000000000002';
  v_mission_rpc constant uuid := 'ec710000-0000-4000-8000-000000000007';
  v_soignant_reel constant uuid := 'ec710000-0000-4000-8000-000000000008';
  v_mission_assignee_reelle constant uuid := 'ec710000-0000-4000-8000-000000000010';
  v_pool_iade_reel constant uuid := 'ec710000-0000-4000-8000-000000000011';
  v_pool_iade_test constant uuid := 'ec710000-0000-4000-8000-000000000012';
  v_soignant_escrow constant uuid := 'ec710000-0000-4000-8000-000000000013';
  v_mission_escrow constant uuid := 'ec710000-0000-4000-8000-000000000014';
  v_escrow constant uuid := 'ec710000-0000-4000-8000-000000000015';
  v_mission_assignee_demarree constant uuid := 'ec710000-0000-4000-8000-000000000016';
  v_mission_noshow_originale constant uuid := 'ec710000-0000-4000-8000-000000000017';
  v_mission_noshow_enfant constant uuid := 'ec710000-0000-4000-8000-000000000018';
  v_mission_noshow_bloquee constant uuid := 'ec710000-0000-4000-8000-000000000020';
  v_mission_noshow_initie constant uuid := 'ec710000-0000-4000-8000-000000000021';
  v_escrow_noshow_initie constant uuid := 'ec710000-0000-4000-8000-000000000022';
  v_mission_noshow_debite constant uuid := 'ec710000-0000-4000-8000-000000000023';
  v_escrow_noshow_debite constant uuid := 'ec710000-0000-4000-8000-000000000024';
  v_soignant_noshow constant uuid := 'ec710000-0000-4000-8000-000000000025';
  v_mission_noshow_finance_ambigue constant uuid := 'ec710000-0000-4000-8000-000000000026';
  v_escrow_noshow_finance_ambigue constant uuid := 'ec710000-0000-4000-8000-000000000027';
  v_mission_chaine_epi_a constant uuid := 'ec710000-0000-4000-8000-000000000028';
  v_mission_chaine_noshow_b constant uuid := 'ec710000-0000-4000-8000-000000000029';
  v_mission_chaine_enfant_c constant uuid := 'ec710000-0000-4000-8000-000000000030';
  v_result_test jsonb;
  v_result_reel jsonb;
  v_result_dates_invalides jsonb;
  v_result_escrow jsonb;
  v_result_assignee_demarree jsonb;
  v_result_noshow_bloque jsonb;
  v_score_base_result jsonb;
  v_source_reelle_avant jsonb;
  v_score_result jsonb;
  v_score_base numeric;
  v_score_apres numeric;
  v_score_reel_apres numeric;
  v_total_annulees integer;
  v_total_annulees_reel integer;
  v_remplacement_id uuid;
  v_remplacement_reel_id uuid;
  v_remplacement_escrow_id uuid;
  v_remplacement_assignee_demarree_id uuid;
  v_escrow_statut text;
  v_mission record;
  v_notification_reel_reel integer;
  v_notification_reel_test integer;
  v_notification_test_test integer;
  v_notification_test_reel integer;
  v_notifications_cross_class integer;
  v_notifications_declarants integer;
  v_nb_remplacements_reel integer;
  v_nb_remplacements_test integer;
  v_nb_remplacements_escrow integer;
  v_nb_remplacements_assignee_demarree integer;
BEGIN
  SELECT resultat INTO STRICT v_result_test
  FROM pg_temp.empechement_rpc_results
  WHERE branche = 'en_cours_test';
  SELECT resultat INTO STRICT v_result_reel
  FROM pg_temp.empechement_rpc_results
  WHERE branche = 'assignee_reelle';
  SELECT resultat INTO STRICT v_result_dates_invalides
  FROM pg_temp.empechement_rpc_results
  WHERE branche = 'assignee_dates_hors_mission';
  SELECT resultat INTO STRICT v_result_escrow
  FROM pg_temp.empechement_rpc_results
  WHERE branche = 'assignee_escrow';
  SELECT resultat INTO STRICT v_result_assignee_demarree
  FROM pg_temp.empechement_rpc_results
  WHERE branche = 'assignee_demarree';
  SELECT resultat INTO STRICT v_result_noshow_bloque
  FROM pg_temp.empechement_rpc_results
  WHERE branche = 'noshow_bloque';
  SELECT resultat INTO STRICT v_score_base_result
  FROM pg_temp.empechement_rpc_results
  WHERE branche = 'score_base';
  SELECT resultat INTO STRICT v_source_reelle_avant
  FROM pg_temp.empechement_rpc_results
  WHERE branche = 'source_reelle_avant';
  v_score_base := (v_score_base_result->>'score')::numeric;
  v_remplacement_id := NULLIF(
    v_result_test->>'mission_remplacement_id', ''
  )::uuid;
  v_remplacement_reel_id := NULLIF(
    v_result_reel->>'mission_remplacement_id', ''
  )::uuid;
  v_remplacement_escrow_id := NULLIF(
    v_result_escrow->>'mission_remplacement_id', ''
  )::uuid;
  v_remplacement_assignee_demarree_id := NULLIF(
    v_result_assignee_demarree->>'mission_remplacement_id', ''
  )::uuid;

  SELECT score_fiabilite, total_missions_annulees
  INTO STRICT v_score_apres, v_total_annulees
  FROM public.soignants
  WHERE id = v_soignant;
  IF COALESCE((v_result_test->>'success')::boolean, false) IS NOT TRUE
     OR COALESCE((v_result_test->>'depassement')::boolean, false) IS NOT TRUE
     OR (v_result_test->>'pool_alerte')::integer < 1
     OR v_remplacement_id IS NULL
     OR (v_result_test->>'mission_diffusee_id')::uuid
          IS DISTINCT FROM v_remplacement_id
     OR COALESCE(
          (v_result_test->>'mission_originale_cloturee')::boolean, true
        ) IS DISTINCT FROM false
     OR COALESCE(
          (v_result_test->>'remplacement_en_revue')::boolean, true
        ) IS DISTINCT FROM false
     OR v_result_test->>'finance_resolution' IS DISTINCT FROM 'AUCUNE'
     OR v_score_apres IS DISTINCT FROM 54::numeric
     OR v_total_annulees IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'EPI-T8 : RPC EN_COURS/pénalité/compteur incohérent : %, %, %',
      v_result_test, v_score_apres, v_total_annulees;
  END IF;

  IF COALESCE((v_result_reel->>'success')::boolean, false) IS NOT TRUE
     OR COALESCE((v_result_reel->>'depassement')::boolean, false)
          IS DISTINCT FROM false
     OR (v_result_reel->>'pool_alerte')::integer < 1
     OR v_remplacement_reel_id IS NULL
     OR (v_result_reel->>'mission_diffusee_id')::uuid
          IS DISTINCT FROM v_remplacement_reel_id
     OR COALESCE(
          (v_result_reel->>'mission_originale_cloturee')::boolean, false
        ) IS DISTINCT FROM true
     OR COALESCE(
          (v_result_reel->>'remplacement_en_revue')::boolean, true
        ) IS DISTINCT FROM false
     OR v_result_reel->>'finance_resolution' IS DISTINCT FROM 'AUCUNE' THEN
    RAISE EXCEPTION 'EPI-T10 : RPC ASSIGNEE réelle incohérente : %', v_result_reel;
  END IF;
  IF COALESCE((v_result_dates_invalides->>'success')::boolean, false) IS TRUE
     OR NULLIF(v_result_dates_invalides->>'error', '') IS NULL THEN
    RAISE EXCEPTION
      'EPI-T10A : une indisponibilité hors mission a été acceptée : %',
      v_result_dates_invalides;
  END IF;

  IF COALESCE(
       (v_result_assignee_demarree->>'success')::boolean, false
     ) IS NOT TRUE
     OR COALESCE(
          (v_result_assignee_demarree->>'mission_originale_cloturee')::boolean,
          true
        ) IS DISTINCT FROM false
     OR COALESCE(
          (v_result_assignee_demarree->>'remplacement_en_revue')::boolean,
          true
        ) IS DISTINCT FROM false
     OR v_result_assignee_demarree->>'finance_resolution'
          IS DISTINCT FROM 'AUCUNE'
     OR v_remplacement_assignee_demarree_id IS NULL
     OR (v_result_assignee_demarree->>'mission_diffusee_id')::uuid
          IS DISTINCT FROM v_remplacement_assignee_demarree_id
     OR NOT EXISTS (
       SELECT 1
       FROM public.missions m
       WHERE m.id = v_mission_assignee_demarree
         AND m.statut = 'ASSIGNEE'
         AND m.soignant_assigne_id = v_soignant_escrow
         AND m.est_arret_maladie IS TRUE
         AND m.arret_maladie_declare_le IS NOT NULL
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.missions m
       WHERE m.id = v_remplacement_assignee_demarree_id
         AND m.remplacement_de_mission_id = v_mission_assignee_demarree
         AND m.statut = 'OUVERTE'
         AND m.soignant_assigne_id IS NULL
     ) THEN
    RAISE EXCEPTION
      'EPI-T10E : branche ASSIGNEE déjà démarrée incohérente : %',
      v_result_assignee_demarree;
  END IF;

  -- Le no-show est une exclusion propre, indépendante de l'attestation EPI :
  -- l'ancien assigné d'une originale ABSENCE ne peut candidater à l'enfant.
  IF EXISTS (
       SELECT 1
       FROM public.journaux_audit ja
       WHERE ja.acteur_id = v_soignant_reel
         AND ja.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
         AND ja.type_ressource = 'mission'
         AND ja.id_ressource = v_mission_noshow_originale
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.missions m
       WHERE m.id = v_mission_noshow_originale
         AND m.statut = 'ABSENCE'
         AND m.absence_sans_prevenir IS TRUE
         AND m.soignant_assigne_id = v_soignant_reel
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.missions m
       WHERE m.id = v_mission_noshow_enfant
         AND m.statut = 'OUVERTE'
         AND m.remplacement_de_mission_id = v_mission_noshow_originale
         AND m.garantie_remplacement IS TRUE
     )
     OR public.fn_soignant_eligible_mission(
          v_soignant_reel, v_mission_noshow_enfant, false
        ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION
      'EPI-T10F : ancien assigné no-show rééligible sans audit EPI';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM public.missions b
       JOIN public.missions c
         ON c.remplacement_de_mission_id = b.id
       WHERE b.id = v_mission_chaine_noshow_b
         AND b.remplacement_de_mission_id = v_mission_chaine_epi_a
         AND b.statut = 'ABSENCE'
         AND b.absence_sans_prevenir IS TRUE
         AND b.garantie_remplacement IS TRUE
         AND c.id = v_mission_chaine_enfant_c
         AND c.statut = 'OUVERTE'
         AND c.garantie_remplacement IS TRUE
     )
     OR public.fn_soignant_eligible_mission(
          v_soignant_reel, v_mission_chaine_enfant_c, false
        ) IS DISTINCT FROM false
     OR public.fn_soignant_eligible_mission(
          v_soignant_noshow, v_mission_chaine_enfant_c, false
        ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION
      'EPI-T10H : ascendance A(EPI)->B(no-show)->C ou garantie non conservée';
  END IF;

  -- Le gate de publication et un rail financier ambigu sont deux causes de
  -- revue fail-closed : ABSENCE reste la source de vérité, mais aucun enfant
  -- ne devient visible. Les rails sûrs sont neutralisés avant cette décision.
  IF COALESCE((v_result_noshow_bloque->>'success')::boolean, false) IS NOT TRUE
     OR (v_result_noshow_bloque->>'detectes')::integer IS DISTINCT FROM 4
     OR (v_result_noshow_bloque->>'remplacements')::integer IS DISTINCT FROM 0
     OR (
       SELECT count(*)::integer
       FROM public.missions m
       WHERE m.id = ANY (ARRAY[
         v_mission_noshow_bloquee,
         v_mission_noshow_initie,
         v_mission_noshow_debite,
         v_mission_noshow_finance_ambigue
       ]::uuid[])
         AND m.statut = 'ABSENCE'
         AND m.absence_sans_prevenir IS TRUE
         AND m.soignant_assigne_id = v_soignant_noshow
     ) IS DISTINCT FROM 4
     OR EXISTS (
       SELECT 1
       FROM public.missions enfant
       WHERE enfant.remplacement_de_mission_id = ANY (ARRAY[
         v_mission_noshow_bloquee,
         v_mission_noshow_initie,
         v_mission_noshow_debite,
         v_mission_noshow_finance_ambigue
       ]::uuid[])
     )
     OR (
       SELECT count(*)::integer
       FROM public.notifications n
       WHERE n.destinataire_id = v_admin
         AND n.type_destinataire = 'ADMIN'
         AND n.titre = 'No-show — remplacement à traiter manuellement ⚠️'
         AND n.type_ressource = 'mission'
         AND n.id_ressource = ANY (ARRAY[
           v_mission_noshow_bloquee,
           v_mission_noshow_initie,
           v_mission_noshow_debite
         ]::uuid[])
     ) IS DISTINCT FROM 3
     OR (
       SELECT count(*)::integer
       FROM public.notifications n
       WHERE n.destinataire_id = 'ec710000-0000-4000-8000-000000000019'::uuid
         AND n.type_destinataire = 'ETABLISSEMENT'
         AND n.titre = 'Aucun pointage — remplacement en revue ⚠️'
         AND n.lien IN (
           '/etablissement/missions/' || v_mission_noshow_bloquee::text,
           '/etablissement/missions/' || v_mission_noshow_initie::text,
           '/etablissement/missions/' || v_mission_noshow_debite::text
         )
     ) IS DISTINCT FROM 3
     OR (
       SELECT count(*)::integer
       FROM public.notifications n
       WHERE n.destinataire_id = v_admin
         AND n.type_destinataire = 'ADMIN'
         AND n.titre = 'No-show — rapprochement financier requis ⚠️'
         AND n.type_ressource = 'mission'
         AND n.id_ressource = v_mission_noshow_finance_ambigue
     ) IS DISTINCT FROM 1
     OR NOT EXISTS (
       SELECT 1
       FROM public.journaux_audit ja
       WHERE ja.action = 'ADMIN_ACTION'
         AND ja.type_ressource = 'mission'
         AND ja.id_ressource = v_mission_noshow_finance_ambigue
         AND ja.details @> jsonb_build_object(
           'evenement', 'NO_SHOW_RAPPROCHEMENT_FINANCIER_REQUIS',
           'paiement_escrow_id', v_escrow_noshow_finance_ambigue
         )
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.paiements_escrow pe
       WHERE pe.id = v_escrow_noshow_initie
         AND pe.statut = 'REMBOURSE'
         AND pe.erreur = 'No-show avant débit Stripe'
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.journaux_audit ja
       WHERE ja.action = 'ADMIN_ACTION'
         AND ja.type_ressource = 'paiement_escrow'
         AND ja.id_ressource = v_escrow_noshow_initie
         AND ja.details @> jsonb_build_object(
           'evenement', 'ESCROW_ANNULE_NO_SHOW_AVANT_DEBIT',
           'mission_id', v_mission_noshow_initie
         )
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.paiements_escrow pe
       WHERE pe.id = v_escrow_noshow_debite
         AND pe.statut = 'REMBOURSE_EN_COURS'
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.stripe_refunds_queue q
       WHERE q.paiement_escrow_id = v_escrow_noshow_debite
         AND q.statut IN ('EN_ATTENTE', 'EN_COURS')
         AND q.montant_cts = 20000
         AND q.reverse_transfer IS TRUE
         AND q.refund_application_fee_cts = 2000
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.paiements_escrow pe
       WHERE pe.id = v_escrow_noshow_finance_ambigue
         AND pe.statut = 'RELEASE_PLANIFIE'
     )
     OR EXISTS (
       SELECT 1
       FROM public.stripe_refunds_queue q
       WHERE q.paiement_escrow_id IN (
         v_escrow_noshow_initie, v_escrow_noshow_finance_ambigue
       )
     ) THEN
    RAISE EXCEPTION
      'EPI-T10G : no-show bloqué ou neutralisation finance incohérente : %',
      v_result_noshow_bloque;
  END IF;

  SELECT score_fiabilite, total_missions_annulees
  INTO STRICT v_score_reel_apres, v_total_annulees_reel
  FROM public.soignants
  WHERE id = v_soignant_reel;
  IF v_score_reel_apres IS DISTINCT FROM
       (v_source_reelle_avant->>'score')::numeric
     OR v_total_annulees_reel IS DISTINCT FROM
       (v_source_reelle_avant->>'total_missions_annulees')::integer THEN
    RAISE EXCEPTION
      'EPI-T10B : empêchement autorisé compté comme annulation/malus : avant %, après score %, annulations %',
      v_source_reelle_avant, v_score_reel_apres, v_total_annulees_reel;
  END IF;

  SELECT pe.statut INTO STRICT v_escrow_statut
  FROM public.paiements_escrow pe
  WHERE pe.id = v_escrow;
  IF COALESCE((v_result_escrow->>'success')::boolean, false) IS NOT TRUE
     OR v_remplacement_escrow_id IS NULL
     OR (v_result_escrow->>'mission_diffusee_id')::uuid
          IS DISTINCT FROM v_remplacement_escrow_id
     OR COALESCE(
          (v_result_escrow->>'mission_originale_cloturee')::boolean, false
        ) IS DISTINCT FROM true
     OR COALESCE(
          (v_result_escrow->>'remplacement_en_revue')::boolean, true
        ) IS DISTINCT FROM false
     OR v_result_escrow->>'finance_resolution'
          IS DISTINCT FROM 'ESCROW_REMBOURSEMENT_ENFILE'
     OR v_escrow_statut IS DISTINCT FROM 'REMBOURSE_EN_COURS'
     OR NOT EXISTS (
       SELECT 1
       FROM public.stripe_refunds_queue q
       WHERE q.paiement_escrow_id = v_escrow
         AND q.statut IN ('EN_ATTENTE', 'EN_COURS')
         AND q.montant_cts = 10000
         AND q.reverse_transfer IS TRUE
         AND q.refund_application_fee_cts = 1000
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.missions m
       WHERE m.id = v_mission_escrow
         AND m.statut = 'ANNULEE_PAR_SOIGNANT'
         AND m.soignant_assigne_id = v_soignant_escrow
         AND m.est_arret_maladie IS TRUE
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.missions m
       WHERE m.id = v_remplacement_escrow_id
         AND m.remplacement_de_mission_id = v_mission_escrow
         AND m.statut = 'OUVERTE'
         AND m.soignant_assigne_id IS NULL
         AND m.mode_remuneration = 'TAUX_HORAIRE'
         AND m.retrocession_pct IS NULL
         AND m.mission_source = 'REMPLACEMENT'
     ) THEN
    RAISE EXCEPTION
      'EPI-T10C : escrow non remboursé avant remplacement : résultat %, statut %',
      v_result_escrow, v_escrow_statut;
  END IF;

  IF current_setting('jolene.system_update', true)
       IS DISTINCT FROM 'sentinelle-epi'
     OR current_setting('jolene.empechement_mission_context', true)
       IS DISTINCT FROM 'sentinelle-contexte-epi'
     OR current_setting('jolene.empechement_mission_validated', true)
       IS DISTINCT FROM 'sentinelle-validation-epi'
     OR current_setting('app.test_mode', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EPI-T11 : un contexte transactionnel n''a pas été restauré';
  END IF;

  SELECT statut, soignant_assigne_id, est_arret_maladie,
         arret_maladie_declare_le
  INTO STRICT v_mission
  FROM public.missions
  WHERE id = v_mission_assignee_reelle;
  IF v_mission.statut::text IS DISTINCT FROM 'ANNULEE_PAR_SOIGNANT'
     OR v_mission.soignant_assigne_id IS DISTINCT FROM v_soignant_reel
     OR v_mission.est_arret_maladie IS DISTINCT FROM true
     OR v_mission.arret_maladie_declare_le IS NULL THEN
    RAISE EXCEPTION 'EPI-T12 : mission ASSIGNEE originale non clôturée exactement : %',
      to_jsonb(v_mission);
  END IF;

  SELECT statut, soignant_assigne_id, est_urgente, niveau_urgence,
         mode_attribution, debut_le, remplacement_de_mission_id,
         mode_remuneration, retrocession_pct, mission_source
  INTO STRICT v_mission
  FROM public.missions
  WHERE id = v_remplacement_reel_id;
  IF v_mission.statut::text IS DISTINCT FROM 'OUVERTE'
     OR v_mission.soignant_assigne_id IS NOT NULL
     OR v_mission.est_urgente IS DISTINCT FROM true
     OR v_mission.niveau_urgence IS DISTINCT FROM 3
     OR v_mission.mode_attribution::text IS DISTINCT FROM 'PREMIER_ARRIVE'
     OR v_mission.debut_le <= now()
     OR v_mission.remplacement_de_mission_id
          IS DISTINCT FROM v_mission_assignee_reelle
     OR v_mission.mode_remuneration IS DISTINCT FROM 'RETROCESSION'
     OR v_mission.retrocession_pct IS DISTINCT FROM 45::numeric
     OR v_mission.mission_source IS DISTINCT FROM 'REMPLACEMENT' THEN
    RAISE EXCEPTION 'EPI-T12B : remplacement ASSIGNEE invalide : %',
      to_jsonb(v_mission);
  END IF;

  SELECT statut, soignant_assigne_id, est_arret_maladie,
         arret_maladie_declare_le
  INTO STRICT v_mission
  FROM public.missions
  WHERE id = v_mission_rpc;
  IF v_mission.statut::text IS DISTINCT FROM 'EN_COURS'
     OR v_mission.soignant_assigne_id IS DISTINCT FROM v_soignant
     OR v_mission.est_arret_maladie IS DISTINCT FROM true
     OR v_mission.arret_maladie_declare_le IS NULL THEN
    RAISE EXCEPTION 'EPI-T13 : mission EN_COURS originale altérée : %',
      to_jsonb(v_mission);
  END IF;

  SELECT statut, soignant_assigne_id, est_urgente, niveau_urgence,
         mode_attribution, debut_le, remplacement_de_mission_id,
         mode_remuneration, retrocession_pct, mission_source
  INTO STRICT v_mission
  FROM public.missions
  WHERE id = v_remplacement_id;
  IF v_mission.statut::text IS DISTINCT FROM 'OUVERTE'
     OR v_mission.soignant_assigne_id IS NOT NULL
     OR v_mission.est_urgente IS DISTINCT FROM true
     OR v_mission.niveau_urgence IS DISTINCT FROM 3
     OR v_mission.mode_attribution::text IS DISTINCT FROM 'PREMIER_ARRIVE'
     OR v_mission.debut_le <= now()
     OR v_mission.remplacement_de_mission_id IS DISTINCT FROM v_mission_rpc
     OR v_mission.mode_remuneration IS DISTINCT FROM 'TAUX_HORAIRE'
     OR v_mission.retrocession_pct IS NOT NULL
     OR v_mission.mission_source IS DISTINCT FROM 'REMPLACEMENT' THEN
    RAISE EXCEPTION 'EPI-T14 : mission de remplacement invalide : %',
      to_jsonb(v_mission);
  END IF;

  SELECT count(*)::integer INTO v_notification_reel_reel
  FROM public.notifications n
  WHERE n.destinataire_id = v_pool_iade_reel
    AND n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')
    AND n.type_ressource = 'mission'
    AND n.id_ressource = v_remplacement_reel_id;
  SELECT count(*)::integer INTO v_notification_reel_test
  FROM public.notifications n
  WHERE n.destinataire_id = v_pool_iade_reel
    AND n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')
    AND n.type_ressource = 'mission'
    AND n.id_ressource = v_remplacement_id;
  SELECT count(*)::integer INTO v_notification_test_test
  FROM public.notifications n
  WHERE n.destinataire_id = v_pool_iade_test
    AND n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')
    AND n.type_ressource = 'mission'
    AND n.id_ressource = v_remplacement_id;
  SELECT count(*)::integer INTO v_notification_test_reel
  FROM public.notifications n
  WHERE n.destinataire_id = v_pool_iade_test
    AND n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')
    AND n.type_ressource = 'mission'
    AND n.id_ressource = v_remplacement_reel_id;

  SELECT count(*)::integer
  INTO v_notifications_cross_class
  FROM public.notifications n
  JOIN public.soignants s ON s.id = n.destinataire_id
  JOIN public.missions m ON m.id = n.id_ressource
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')
    AND n.type_ressource = 'mission'
    AND n.id_ressource IN (
      v_remplacement_reel_id, v_remplacement_id, v_remplacement_escrow_id
    )
    AND COALESCE(s.est_compte_test, false)
          IS DISTINCT FROM COALESCE(e.est_compte_test, false);

  IF v_notification_reel_reel IS DISTINCT FROM 1
     OR v_notification_reel_test IS DISTINCT FROM 0
     OR v_notification_test_test IS DISTINCT FROM 1
     OR v_notification_test_reel IS DISTINCT FROM 0
     OR v_notifications_cross_class IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'EPI-T15 : fan-out réel/test invalide (RR %, RT %, TT %, TR %, cross %)',
      v_notification_reel_reel, v_notification_reel_test,
      v_notification_test_test, v_notification_test_reel,
      v_notifications_cross_class;
  END IF;

  SELECT count(*)::integer INTO v_notifications_declarants
  FROM public.notifications n
  WHERE n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')
    AND n.type_ressource = 'mission'
    AND (
      (n.destinataire_id = v_soignant_reel
       AND n.id_ressource = v_remplacement_reel_id)
      OR
      (n.destinataire_id = v_soignant
       AND n.id_ressource = v_remplacement_id)
      OR
      (n.destinataire_id = v_soignant_escrow
       AND n.id_ressource = v_remplacement_escrow_id)
      OR
      (n.destinataire_id = v_soignant_escrow
       AND n.id_ressource = v_remplacement_assignee_demarree_id)
    );
  SELECT count(*)::integer INTO v_nb_remplacements_reel
  FROM public.missions m
  WHERE m.remplacement_de_mission_id = v_mission_assignee_reelle;
  SELECT count(*)::integer INTO v_nb_remplacements_test
  FROM public.missions m
  WHERE m.remplacement_de_mission_id = v_mission_rpc;
  SELECT count(*)::integer INTO v_nb_remplacements_escrow
  FROM public.missions m
  WHERE m.remplacement_de_mission_id = v_mission_escrow;
  SELECT count(*)::integer INTO v_nb_remplacements_assignee_demarree
  FROM public.missions m
  WHERE m.remplacement_de_mission_id = v_mission_assignee_demarree;
  IF v_notifications_declarants IS DISTINCT FROM 0
     OR v_nb_remplacements_reel IS DISTINCT FROM 1
     OR v_nb_remplacements_test IS DISTINCT FROM 1
     OR v_nb_remplacements_escrow IS DISTINCT FROM 1
     OR v_nb_remplacements_assignee_demarree IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'EPI-T15B : déclarant notifié ou remplacement dupliqué (notif %, réel %, test %, escrow %, assignée-démarrée %)',
      v_notifications_declarants, v_nb_remplacements_reel,
      v_nb_remplacements_test, v_nb_remplacements_escrow,
      v_nb_remplacements_assignee_demarree;
  END IF;

  -- La profession exigée par la mission gouverne : une IADE peut prendre une
  -- mission IDE de sa classe, jamais celle de la classe opposée.
  IF public.fn_soignant_eligible_mission(
       v_pool_iade_reel, v_remplacement_reel_id, true
     ) IS DISTINCT FROM true
     OR public.fn_soignant_eligible_mission(
       v_pool_iade_test, v_remplacement_reel_id, true
     ) IS DISTINCT FROM false
     OR public.fn_soignant_eligible_mission(
       v_pool_iade_test, v_remplacement_id, true
     ) IS DISTINCT FROM true
     OR public.fn_soignant_eligible_mission(
       v_pool_iade_reel, v_remplacement_id, true
     ) IS DISTINCT FROM false
     OR public.fn_soignant_eligible_mission(
       v_soignant_reel, v_remplacement_reel_id, false
     ) IS DISTINCT FROM false
     OR public.fn_soignant_eligible_mission(
       v_soignant, v_remplacement_id, false
     ) IS DISTINCT FROM false
     OR public.fn_soignant_eligible_mission(
       v_soignant_escrow, v_remplacement_escrow_id, false
     ) IS DISTINCT FROM false
     OR public.fn_soignant_eligible_mission(
       v_soignant_escrow, v_remplacement_assignee_demarree_id, false
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EPI-T16 : compatibilité IADE × mission IDE ou cloisonnement invalide';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.membres_etablissement m
    WHERE m.user_id = v_soignant
      AND m.role = 'LECTURE_SEULE'
      AND m.actif IS TRUE
  ) THEN
    RAISE EXCEPTION 'EPI-T17 : la branche EN_COURS n''a pas testé le dual-role LECTURE_SEULE';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_soignant::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_score_result := public.fn_calculer_score_fiabilite_v2(
    v_soignant, 'fixture_apres_empechement'
  );
  SELECT score_fiabilite
  INTO STRICT v_score_apres
  FROM public.soignants
  WHERE id = v_soignant;
  IF (v_score_result->>'empechement_malus')::numeric IS DISTINCT FROM -8::numeric
     OR v_score_apres IS DISTINCT FROM GREATEST(0::numeric, v_score_base - 8)
     OR (v_score_result->>'score')::numeric IS DISTINCT FROM v_score_apres
     OR current_setting('jolene.system_update', true)
          IS DISTINCT FROM 'sentinelle-epi'
     OR current_setting('jolene.empechement_mission_context', true)
          IS DISTINCT FROM 'sentinelle-contexte-epi'
     OR current_setting('jolene.empechement_mission_validated', true)
          IS DISTINCT FROM 'sentinelle-validation-epi' THEN
    RAISE EXCEPTION 'EPI-T9 : recalcul a effacé le malus : base %, résultat %, stocké %',
      v_score_base, v_score_result, v_score_apres;
  END IF;
END;
$empechement_penalty_assertions$;

ROLLBACK;
