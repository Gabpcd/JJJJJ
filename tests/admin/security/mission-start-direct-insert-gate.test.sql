-- La voie INSERT directe (PostgREST/admin établissement) ne doit pas pouvoir
-- fabriquer une mission déjà en cours ou historique sans contrat/documents.
-- Toutes les écritures sont annulées par le ROLLBACK final.

\set ON_ERROR_STOP on
BEGIN;

DO $mission_insert_gate$
DECLARE
  v_etablissement_id constant uuid := 'a11c0000-0000-4000-8000-000000000001';
  v_soignant_id constant uuid := 'a11c0000-0000-4000-8000-000000000002';
  v_acteur_id constant uuid := 'a11c0000-0000-4000-8000-000000000003';
  v_statut public.statut_mission;
  v_message text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Fixtures transactionnelles mission-start direct insert gate',
    true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_soignant_id, '00000000-0000-0000-0000-000000000000',
      'mission-start-soignant@test.local', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}', now()
    ),
    (
      v_acteur_id, '00000000-0000-0000-0000-000000000000',
      'mission-start-acteur@test.local', 'authenticated', 'authenticated',
      '{"role":"ADMIN_ETABLISSEMENT"}', now()
    );

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_compte_test
  ) VALUES (
    v_etablissement_id, 'Fixture mission-start', '99140000000401',
    'CLINIQUE_PRIVEE', '4 rue du Test', 'Paris', '75004',
    'mission-start-etablissement@test.local', true
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test
  ) VALUES (
    v_soignant_id, 'Fixture', 'MissionStart',
    'mission-start-soignant@test.local', 'IDE', true
  );

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, actif
  ) VALUES (
    v_etablissement_id, v_acteur_id, 'PROPRIETAIRE', true
  );

  PERFORM set_config('app.internal_operation', '', true);
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config('request.jwt.claim.sub', v_acteur_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_acteur_id,
      'role', 'authenticated',
      'aal', 'aal2'
    )::text,
    true
  );

  -- Isole le verrou d'état initial des gardes documentaires d'affectation :
  -- chaque statut historique est tenté sans soignant, puis la préaffectation
  -- d'une mission OUVERTE est vérifiée séparément ci-dessous.
  FOREACH v_statut IN ARRAY ARRAY[
    'ASSIGNEE',
    'EN_COURS',
    'TERMINEE',
    'ANNULEE_PAR_ETABLISSEMENT',
    'ANNULEE_PAR_SOIGNANT',
    'ABSENCE',
    'LITIGE',
    'EXPIREE'
  ]::public.statut_mission[]
  LOOP
    BEGIN
      INSERT INTO public.missions (
        etablissement_id, intitule, profession_requise,
        debut_le, fin_le, duree_heures, taux_horaire_base, statut,
        soignant_assigne_id, type_contrat_recherche, mode_attribution
      ) VALUES (
        v_etablissement_id,
        'Tentative INSERT direct ' || v_statut::text,
        'IDE',
        now() + interval '20 years',
        now() + interval '20 years 8 hours',
        8,
        20,
        v_statut,
        NULL,
        'SALARIE',
        'CANDIDATURE'
      );
      RAISE EXCEPTION 'INSERT direct non bloqué pour le statut %', v_statut;
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message IS DISTINCT FROM
             'Une mission doit être créée OUVERTE et sans soignant affecté.' THEN
          RAISE;
        END IF;
    END;
  END LOOP;

  -- Même une ligne OUVERTE ne peut pas pré-affecter discrètement un soignant.
  BEGIN
    INSERT INTO public.missions (
      etablissement_id, intitule, profession_requise,
      debut_le, fin_le, duree_heures, taux_horaire_base, statut,
      soignant_assigne_id, type_contrat_recherche, mode_attribution
    ) VALUES (
      v_etablissement_id,
      'Tentative pré-affectation directe',
      'IDE',
      now() + interval '20 years',
      now() + interval '20 years 8 hours',
      8,
      20,
      'OUVERTE',
      v_soignant_id,
      'SALARIE',
      'CANDIDATURE'
    );
    RAISE EXCEPTION 'INSERT direct OUVERTE pré-affectée non bloqué';
  EXCEPTION
    WHEN check_violation THEN
      GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
      IF v_message IS DISTINCT FROM
           'Une mission doit être créée OUVERTE et sans soignant affecté.' THEN
        RAISE;
      END IF;
  END;
END;
$mission_insert_gate$;

ROLLBACK;
