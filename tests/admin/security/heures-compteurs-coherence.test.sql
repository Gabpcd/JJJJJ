-- Compteurs d'heures canoniques : précision décimale, idempotence des
-- transitions mission, synchronisation des caches et cloisonnement des helpers.
-- Toutes les fixtures sont annulées par le ROLLBACK final.
\set ON_ERROR_STOP on
BEGIN;

DO $heures_compteurs_coherence$
DECLARE
  v_admin constant uuid := 'cc420000-0000-4000-8000-000000000000';
  v_soignant constant uuid := 'cc420000-0000-4000-8000-000000000001';
  v_soignant_remplacement constant uuid := 'cc420000-0000-4000-8000-000000000005';
  v_etablissement constant uuid := 'cc420000-0000-4000-8000-000000000002';
  v_mission constant uuid := 'cc420000-0000-4000-8000-000000000003';
  v_presence constant uuid := 'cc420000-0000-4000-8000-000000000004';
  v_presence_remplacement constant uuid := 'cc420000-0000-4000-8000-000000000006';
  v_heures_externes uuid;
  v_compteur record;
  v_canonique record;
  v_canonique_remplacement record;
  v_cache record;
  v_cache_remplacement record;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Fixture transactionnelle coherence compteurs heures',
    true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_admin,
      '00000000-0000-0000-0000-000000000000',
      'admin-counter-coherence@test.local',
      'authenticated',
      'authenticated',
      '{"role":"ADMIN_PLATEFORME"}',
      now()
    ),
    (
      v_soignant,
      '00000000-0000-0000-0000-000000000000',
      'playwright-test-caregiver-counter-coherence@jolene.app',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    ),
    (
      v_soignant_remplacement,
      '00000000-0000-0000-0000-000000000000',
      'playwright-test-caregiver-counter-reassignment@jolene.app',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    );

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin,
    'Compteurs',
    'Admin',
    'admin-counter-coherence@test.local',
    true,
    ARRAY[
      'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
      'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur'
    ]::text[]
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test, type_exercice
  ) VALUES
    (
      v_soignant, 'Fixture', 'Compteurs',
      'playwright-test-caregiver-counter-coherence@jolene.app',
      'IDE', true, 'LIBERAL'
    ),
    (
      v_soignant_remplacement, 'Fixture', 'Remplacement',
      'playwright-test-caregiver-counter-reassignment@jolene.app',
      'IDE', true, 'SALARIE'
    );

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_compte_test
  ) VALUES (
    v_etablissement, 'Fixture compteurs heures', '99140000000500',
    'CLINIQUE_PRIVEE', '5 rue du Test', 'Paris', '75005',
    'heures-compteurs-etablissement@test.local', true
  );

  IF private.fn_seuil_heures_liberal(v_soignant, 'IDE')
       IS DISTINCT FROM 3200::numeric
     OR private.fn_seuil_heures_liberal(v_soignant, 'SAGE_FEMME')
       IS DISTINCT FROM 0::numeric
     OR private.fn_seuil_heures_liberal(v_soignant, 'KINE') IS NOT NULL THEN
    RAISE EXCEPTION 'HC-T0 : seuil non résolu depuis la profession de mission';
  END IF;

  -- Le helper de fixture crée une preuve externe portant toute la provenance
  -- serveur requise. Son INSERT doit immédiatement synchroniser le cache.
  v_heures_externes := public.fn_test_seed_heures_externes_validees(
    v_soignant, 3192
  );

  SELECT * INTO STRICT v_canonique
  FROM private.fn_heures_exercice_verifiees(v_soignant);
  IF v_canonique.heures_jolene IS DISTINCT FROM 0::numeric
     OR v_canonique.heures_externes_validees IS DISTINCT FROM 3192::numeric
     OR v_canonique.heures_totales IS DISTINCT FROM 3192::numeric THEN
    RAISE EXCEPTION 'HC-T1 : seed externe non canonique : %',
      row_to_json(v_canonique);
  END IF;

  SELECT heures_plateforme, heures_cumulees, eligible_conversion_3200h
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_cache.heures_plateforme IS DISTINCT FROM 0::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 3192::numeric
     OR v_cache.eligible_conversion_3200h IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'HC-T2 : cache externe non synchronisé : %',
      row_to_json(v_cache);
  END IF;

  -- Un cache forgé ne doit jamais devenir une preuve de seuil. Le calcul privé
  -- repart des missions/presences et des attestations externes vérifiables.
  UPDATE public.soignants
  SET heures_plateforme = 4000,
      heures_cumulees = 4000,
      eligible_conversion_3200h = true
  WHERE id = v_soignant;

  SELECT * INTO STRICT v_canonique
  FROM private.fn_heures_exercice_verifiees(v_soignant);
  IF v_canonique.heures_jolene IS DISTINCT FROM 0::numeric
     OR v_canonique.heures_totales IS DISTINCT FROM 3192::numeric THEN
    RAISE EXCEPTION 'HC-T3 : le calcul canonique a cru le cache forgé : %',
      row_to_json(v_canonique);
  END IF;
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant);

  -- La mission naît en LITIGE : elle ne compte pas. Une transition vers
  -- TERMINEE doit ajouter exactement 8 h et une seule mission terminée.
  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    soignant_assigne_id, type_contrat_recherche, mode_attribution
  ) VALUES (
    v_mission, v_etablissement, 'Fixture coherence compteurs', 'IDE',
    now() + interval '20 years', now() + interval '20 years 8 hours',
    8, 20, 'LITIGE', v_soignant, 'SALARIE', 'CANDIDATURE'
  );

  UPDATE public.missions SET statut = 'TERMINEE' WHERE id = v_mission;

  SELECT * INTO STRICT v_canonique
  FROM private.fn_heures_exercice_verifiees(v_soignant);
  SELECT heures_plateforme, heures_cumulees, eligible_conversion_3200h,
         total_missions_terminees
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_canonique.heures_jolene IS DISTINCT FROM 8::numeric
     OR v_canonique.heures_totales IS DISTINCT FROM 3200::numeric
     OR v_cache.heures_plateforme IS DISTINCT FROM 8::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 3200::numeric
     OR v_cache.eligible_conversion_3200h IS DISTINCT FROM true
     OR v_cache.total_missions_terminees IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'HC-T4 : mission 8 h mal comptée : canonique=%, cache=%',
      row_to_json(v_canonique), row_to_json(v_cache);
  END IF;

  -- Un UPDATE sans changement de cycle ne doit jamais ré-incrémenter.
  UPDATE public.missions
  SET intitule = intitule || ' — idempotence'
  WHERE id = v_mission;
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant);
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant);
  SELECT heures_plateforme, heures_cumulees, total_missions_terminees
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_cache.heures_plateforme IS DISTINCT FROM 8::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 3200::numeric
     OR v_cache.total_missions_terminees IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'HC-T5 : double comptage après UPDATE/resync : %',
      row_to_json(v_cache);
  END IF;

  -- Le détour TERMINEE -> LITIGE -> TERMINEE reste réversible et idempotent.
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  UPDATE public.missions SET statut = 'LITIGE' WHERE id = v_mission;
  SELECT heures_plateforme, heures_cumulees, total_missions_terminees
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_cache.heures_plateforme IS DISTINCT FROM 0::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 3192::numeric
     OR v_cache.total_missions_terminees IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'HC-T6 : sortie de TERMINEE non réversible : %',
      row_to_json(v_cache);
  END IF;

  UPDATE public.missions SET statut = 'TERMINEE' WHERE id = v_mission;
  SELECT heures_plateforme, heures_cumulees, total_missions_terminees
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_cache.heures_plateforme IS DISTINCT FROM 8::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 3200::numeric
     OR v_cache.total_missions_terminees IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'HC-T7 : LITIGE -> TERMINEE a doublé les heures : %',
      row_to_json(v_cache);
  END IF;

  -- Une présence réelle prime sur le planifié. 3192 + 7,99 = 3199,99 : la
  -- précision décimale ne doit jamais arrondir ce total à 3200 ni l'autoriser.
  INSERT INTO public.presences (
    id, mission_id, soignant_id, heures_reelles,
    valide_par_etablissement, valide_le
  ) VALUES (
    v_presence, v_mission, v_soignant, 7.99, true, now()
  );

  SELECT * INTO STRICT v_canonique
  FROM private.fn_heures_exercice_verifiees(v_soignant);
  SELECT heures_plateforme, heures_cumulees, eligible_conversion_3200h
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_canonique.heures_jolene IS DISTINCT FROM 7.99::numeric
     OR v_canonique.heures_totales IS DISTINCT FROM 3199.99::numeric
     OR v_cache.heures_plateforme IS DISTINCT FROM 7.99::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 3199.99::numeric
     OR v_cache.eligible_conversion_3200h IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'HC-T8 : frontière 3199,99 arrondie/acceptée : canonique=%, cache=%',
      row_to_json(v_canonique), row_to_json(v_cache);
  END IF;

  -- À 8,00 h réelles, le total exact atteint 3200 et devient éligible.
  UPDATE public.presences SET heures_reelles = 8 WHERE id = v_presence;
  PERFORM set_config('request.jwt.claim.sub', v_soignant::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  SELECT * INTO STRICT v_compteur
  FROM public.fn_compteur_heures_soignant(v_soignant);
  SELECT heures_plateforme, heures_cumulees, eligible_conversion_3200h
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_compteur.heures_jolene IS DISTINCT FROM 8::numeric
     OR v_compteur.heures_externes_validees IS DISTINCT FROM 3192::numeric
     OR v_compteur.heures_externes_en_attente IS DISTINCT FROM 0::numeric
     OR v_compteur.heures_totales IS DISTINCT FROM 3200::numeric
     -- Free Transition est un avantage Jolene : seules les heures faites sur
     -- la plateforme l'ouvrent, contrairement au seuil légal des 3 200 h.
     OR v_compteur.eligible_free_transition IS DISTINCT FROM false
     OR v_cache.heures_cumulees IS DISTINCT FROM 3200::numeric
     OR v_cache.eligible_conversion_3200h IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'HC-T9 : frontière 3200 non cohérente : compteur=%, cache=%',
      row_to_json(v_compteur), row_to_json(v_cache);
  END IF;

  -- La révocation puis la revalidation de la preuve externe doivent recalculer
  -- le cache dans la même transaction, sans appel manuel de resynchronisation.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('jolene.heures_externes_server_update', 'true', true);
  UPDATE public.heures_externes_soignants
  SET statut_validation = 'REJETE'
  WHERE id = v_heures_externes;
  SELECT heures_plateforme, heures_cumulees, eligible_conversion_3200h
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_cache.heures_plateforme IS DISTINCT FROM 8::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 8::numeric
     OR v_cache.eligible_conversion_3200h IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'HC-T10 : révocation externe non synchronisée : %',
      row_to_json(v_cache);
  END IF;

  UPDATE public.heures_externes_soignants
  SET statut_validation = 'VALIDE'
  WHERE id = v_heures_externes;
  PERFORM set_config('jolene.heures_externes_server_update', '', true);
  SELECT heures_plateforme, heures_cumulees, eligible_conversion_3200h
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  IF v_cache.heures_plateforme IS DISTINCT FROM 8::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 3200::numeric
     OR v_cache.eligible_conversion_3200h IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'HC-T11 : revalidation externe non synchronisée : %',
      row_to_json(v_cache);
  END IF;

  -- L'ancien trigger incrémental est incompatible avec un recalcul canonique.
  IF EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'missions'
      AND t.tgname = 'dec_heures_plateforme'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'HC-T12 : le trigger incrémental dec_heures_plateforme existe encore';
  END IF;

  -- Les helpers privés ne doivent pas être exposés aux JWT utilisateurs.
  IF has_function_privilege(
       'authenticated',
       'private.fn_heures_exercice_verifiees(uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'private.fn_resynchroniser_compteurs_soignant(uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'HC-T13 : helper privé exécutable par authenticated';
  END IF;

  -- Une mission peut conserver la présence de son premier soignant après une
  -- réaffectation. Seule la présence du soignant actuellement assigné doit
  -- alors alimenter ses heures : l'ancienne présence ne doit pas s'ajouter à
  -- celle du remplaçant.
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
  SET soignant_assigne_id = v_soignant_remplacement
  WHERE id = v_mission;

  INSERT INTO public.presences (
    id, mission_id, soignant_id, heures_reelles,
    valide_par_etablissement, valide_le
  ) VALUES (
    v_presence_remplacement, v_mission, v_soignant_remplacement,
    6, true, now()
  );

  IF (
    SELECT count(*)
    FROM public.presences
    WHERE mission_id = v_mission
  ) <> 2 THEN
    RAISE EXCEPTION 'HC-T14 : la réaffectation n''a pas conservé les deux présences';
  END IF;

  SELECT * INTO STRICT v_canonique
  FROM private.fn_heures_exercice_verifiees(v_soignant);
  SELECT heures_plateforme, heures_cumulees, total_missions_terminees
  INTO STRICT v_cache
  FROM public.soignants WHERE id = v_soignant;
  SELECT * INTO STRICT v_canonique_remplacement
  FROM private.fn_heures_exercice_verifiees(v_soignant_remplacement);
  SELECT heures_plateforme, heures_cumulees, total_missions_terminees
  INTO STRICT v_cache_remplacement
  FROM public.soignants WHERE id = v_soignant_remplacement;

  IF v_canonique.heures_jolene IS DISTINCT FROM 0::numeric
     OR v_canonique.heures_totales IS DISTINCT FROM 3192::numeric
     OR v_cache.heures_plateforme IS DISTINCT FROM 0::numeric
     OR v_cache.heures_cumulees IS DISTINCT FROM 3192::numeric
     OR v_cache.total_missions_terminees IS DISTINCT FROM 0
     OR v_canonique_remplacement.heures_jolene IS DISTINCT FROM 6::numeric
     OR v_canonique_remplacement.heures_totales IS DISTINCT FROM 6::numeric
     OR v_cache_remplacement.heures_plateforme IS DISTINCT FROM 6::numeric
     OR v_cache_remplacement.heures_cumulees IS DISTINCT FROM 6::numeric
     OR v_cache_remplacement.total_missions_terminees IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'HC-T15 : présence historique surcomptée après réaffectation : ancien canonique=%, ancien cache=%, remplaçant canonique=%, remplaçant cache=%',
      row_to_json(v_canonique), row_to_json(v_cache),
      row_to_json(v_canonique_remplacement), row_to_json(v_cache_remplacement);
  END IF;
END;
$heures_compteurs_coherence$;

ROLLBACK;
