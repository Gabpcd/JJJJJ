-- La voie INSERT directe (PostgREST/admin établissement) ne doit pas pouvoir
-- fabriquer une mission déjà en cours ou historique sans contrat/documents.
-- Toutes les écritures sont annulées par le ROLLBACK final.

\set ON_ERROR_STOP on
BEGIN;

DO $mission_insert_gate$
DECLARE
  v_etablissement_id uuid;
  v_soignant_id uuid;
  v_acteur_id uuid;
  v_statut public.statut_mission;
  v_message text;
BEGIN
  SELECT id INTO v_etablissement_id
  FROM public.etablissements
  WHERE supprime_le IS NULL
  ORDER BY id
  LIMIT 1;

  SELECT id INTO v_soignant_id
  FROM public.soignants
  WHERE supprime_le IS NULL
  ORDER BY id
  LIMIT 1;

  SELECT id INTO v_acteur_id
  FROM auth.users
  WHERE deleted_at IS NULL
  ORDER BY id
  LIMIT 1;

  IF v_etablissement_id IS NULL OR v_soignant_id IS NULL OR v_acteur_id IS NULL THEN
    RAISE EXCEPTION 'Fixtures mission-start insuffisantes';
  END IF;

  PERFORM set_config('app.internal_operation', '', true);
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_acteur_id,
      'role', 'authenticated',
      'aal', 'aal2'
    )::text,
    true
  );

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
        debut_le, fin_le, taux_horaire_base, statut,
        soignant_assigne_id
      ) VALUES (
        v_etablissement_id,
        'Tentative INSERT direct ' || v_statut::text,
        'IDE',
        now() + interval '20 years',
        now() + interval '20 years 8 hours',
        20,
        v_statut,
        v_soignant_id
      );
      RAISE EXCEPTION 'INSERT direct non bloqué pour le statut %', v_statut;
    EXCEPTION
      WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> 'Une mission doit être créée OUVERTE et sans soignant affecté.' THEN
          RAISE;
        END IF;
    END;
  END LOOP;

  -- Même une ligne OUVERTE ne peut pas pré-affecter discrètement un soignant.
  BEGIN
    INSERT INTO public.missions (
      etablissement_id, intitule, profession_requise,
      debut_le, fin_le, taux_horaire_base, statut,
      soignant_assigne_id
    ) VALUES (
      v_etablissement_id,
      'Tentative pré-affectation directe',
      'IDE',
      now() + interval '20 years',
      now() + interval '20 years 8 hours',
      20,
      'OUVERTE',
      v_soignant_id
    );
    RAISE EXCEPTION 'INSERT direct OUVERTE pré-affectée non bloqué';
  EXCEPTION
    WHEN check_violation THEN
      GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
      IF v_message <> 'Une mission doit être créée OUVERTE et sans soignant affecté.' THEN
        RAISE;
      END IF;
  END;
END;
$mission_insert_gate$;

ROLLBACK;
