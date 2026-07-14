-- La fenêtre de 12 semaines doit être réellement glissante et ne doit
-- compter que les missions salariées, ventilées dans leur semaine civile.
\set ON_ERROR_STOP on
BEGIN;

DO $fixtures$
DECLARE
  v_soignant uuid := '70000000-0000-4000-8000-000000000001';
  v_etab uuid := '70000000-0000-4000-8000-000000000002';
  v_medecin uuid := '70000000-0000-4000-8000-000000000007';
  v_mission uuid;
  v_base date := date_trunc('week', current_date + interval '20 years')::date;
  v_debut timestamptz;
  v_message text;
  i integer;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_soignant, '00000000-0000-0000-0000-000000000000',
      'moyenne44-soignant@test.local', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}', now()
    ),
    (
      v_etab, '00000000-0000-0000-0000-000000000000',
      'moyenne44-etab@test.local', 'authenticated', 'authenticated',
      '{"role":"ADMIN_ETABLISSEMENT"}', now()
    ),
    (
      v_medecin, '00000000-0000-0000-0000-000000000000',
      'moyenne44-medecin@test.local', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}', now()
    );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test
  ) VALUES (
    v_soignant, 'Moyenne', 'Test', 'moyenne44-soignant@test.local', 'IDE', true
  ), (
    v_medecin, 'Médecin', 'Test', 'moyenne44-medecin@test.local', 'MEDECIN', true
  );

  INSERT INTO public.etablissements (
    id, nom, siret, finess, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, statut_verification,
    peut_publier_missions, siret_verifie, finess_verifie,
    representant_identite_verifiee, rattachement_verifie,
    contrat_service_signe, est_compte_test
  ) VALUES (
    v_etab, 'Établissement moyenne 44 h', '70000000000002', '700000002',
    'CLINIQUE_PRIVEE', '1 rue du Test', 'Paris', '75001',
    'moyenne44-etab@test.local', 'VERIFIE', true, true, true,
    true, true, true, true
  );

  -- Onze semaines futures à 44 h chacune. Chacune est conforme seule et le
  -- total sur toute fenêtre existante reste sous 44 h de moyenne.
  FOR i IN 1..11 LOOP
    v_mission := gen_random_uuid();
    v_debut := ((v_base + (i * 7))::timestamp + interval '8 hours')
      AT TIME ZONE 'Europe/Paris';

    INSERT INTO public.missions (
      id, etablissement_id, intitule, profession_requise,
      debut_le, fin_le, duree_heures, taux_horaire_base,
      statut, soignant_assigne_id, type_contrat_recherche,
      type_contrat_applique, choix_contrat_soignant, mode_attribution
    ) VALUES (
      v_mission, v_etab, 'Semaine salariée ' || i, 'IDE',
      v_debut, v_debut + interval '44 hours', 44, 20,
      'ASSIGNEE', v_soignant, 'SALARIE', 'SALARIE', 'SALARIE', 'CANDIDATURE'
    );
  END LOOP;

  -- La mission de 45 h en semaine 0 respecte le plafond ponctuel de 48 h,
  -- mais la fenêtre qui se termine onze semaines plus tard atteint
  -- (45 + 11*44) / 12 = 44,08 h : elle doit être bloquée.
  v_debut := (v_base::timestamp + interval '8 hours') AT TIME ZONE 'Europe/Paris';
  BEGIN
    INSERT INTO public.missions (
      id, etablissement_id, intitule, profession_requise,
      debut_le, fin_le, duree_heures, taux_horaire_base,
      statut, soignant_assigne_id, type_contrat_recherche,
      type_contrat_applique, choix_contrat_soignant, mode_attribution
    ) VALUES (
      '70000000-0000-4000-8000-000000000004',
      v_etab, 'Mission révélant la fenêtre future', 'IDE',
      v_debut, v_debut + interval '45 hours', 45, 20,
      'ASSIGNEE', v_soignant, 'SALARIE', 'SALARIE', 'SALARIE', 'CANDIDATURE'
    );
    RAISE EXCEPTION 'P1: la fenêtre glissante future n’a pas été bloquée';
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
      IF position('[CODE DU TRAVAIL] Moyenne dépassée' IN v_message) = 0 THEN
        RAISE;
      END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM public.missions
    WHERE id = '70000000-0000-4000-8000-000000000004'
  ) THEN
    RAISE EXCEPTION 'P1: la mission bloquée a tout de même été persistée';
  END IF;

  -- Une déclaration honnête postérieure à l'affectation n'est jamais rejetée.
  -- Elle prend le même verrou et transforme le conflit en alerte durable.
  INSERT INTO public.attestations_heures_externes (
    id, soignant_id, semaine_du, heures_salarie,
    employeur_principal, attestation_honneur
  ) VALUES (
    '70000000-0000-4000-8000-000000000005',
    v_soignant,
    v_base + 7,
    10,
    'Employeur principal test',
    true
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.attestations_heures_externes
    WHERE id = '70000000-0000-4000-8000-000000000005'
  ) THEN
    RAISE EXCEPTION 'P1: la déclaration externe véridique a été rejetée';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.conformite_travail
    WHERE soignant_id = v_soignant
      AND type_controle = 'PLAFOND_48H_HEBDO'
      AND resultat = 'VIOLATION_ALERTEE'
      AND details_violation->>'attestation_id' =
        '70000000-0000-4000-8000-000000000005'
  ) THEN
    RAISE EXCEPTION 'P1: le conflit révélé par la déclaration n’a pas été alerté';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE destinataire_id = v_soignant
      AND type_ressource = 'attestations_heures_externes'
      AND id_ressource = '70000000-0000-4000-8000-000000000005'
  ) THEN
    RAISE EXCEPTION 'P1: le soignant n’a pas été informé de la revue humaine';
  END IF;

  -- Une correction administrative de propriétaire doit déclencher exactement
  -- les mêmes contrôles pour le nouveau soignant; soignant_id ne doit jamais
  -- permettre de contourner la sérialisation et le recalcul.
  INSERT INTO public.attestations_heures_externes (
    id, soignant_id, semaine_du, heures_salarie,
    employeur_principal, attestation_honneur
  ) VALUES (
    '70000000-0000-4000-8000-000000000006',
    v_medecin,
    v_base + 7,
    5,
    'Employeur correction attribution',
    true
  );
  UPDATE public.attestations_heures_externes
  SET soignant_id = v_soignant
  WHERE id = '70000000-0000-4000-8000-000000000006';

  IF NOT EXISTS (
    SELECT 1 FROM public.conformite_travail
    WHERE soignant_id = v_soignant
      AND type_controle = 'PLAFOND_48H_HEBDO'
      AND resultat = 'VIOLATION_ALERTEE'
      AND details_violation->>'attestation_id' =
        '70000000-0000-4000-8000-000000000006'
  ) THEN
    RAISE EXCEPTION 'P1: la réattribution d’attestation n’a pas recalculé les plafonds';
  END IF;

  -- Mission simple historique sans créneaux : au passage effectif, le helper
  -- doit privilégier duree_heures_effective et conserver le fait accompli tout
  -- en ouvrant une alerte (40 h prévues, 55 h réellement constatées).
  v_debut := ((v_base + (30 * 7))::timestamp + interval '8 hours')
    AT TIME ZONE 'Europe/Paris';
  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id, type_contrat_recherche,
    type_contrat_applique, choix_contrat_soignant, mode_attribution,
    debut_effectif, fin_effective, duree_heures_effective
  ) VALUES (
    '70000000-0000-4000-8000-000000000009',
    v_etab, 'Mission simple effective salariée', 'IDE',
    v_debut, v_debut + interval '40 hours', 40, 20,
    'TERMINEE', v_soignant, 'SALARIE', 'SALARIE', 'SALARIE', 'CANDIDATURE',
    v_debut, v_debut + interval '40 hours', 40
  );

  UPDATE public.missions
  SET duree_heures_effective = 55,
      fin_effective = v_debut + interval '55 hours'
  WHERE id = '70000000-0000-4000-8000-000000000009';

  IF NOT EXISTS (
    SELECT 1 FROM public.missions
    WHERE id = '70000000-0000-4000-8000-000000000009'
      AND duree_heures_effective = 55
  ) THEN
    RAISE EXCEPTION 'P1: les heures effectives constatées ont été rejetées';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.conformite_travail
    WHERE mission_id = '70000000-0000-4000-8000-000000000009'
      AND type_controle = 'PLAFOND_48H_HEBDO'
      AND resultat = 'VIOLATION_ALERTEE'
      AND details_violation->>'origine' = 'HEURES_EFFECTIVES_TERMINEES'
      AND (details_violation->>'heures_mission_effectives')::numeric = 55
  ) THEN
    RAISE EXCEPTION 'P1: les 55 h effectives sans créneaux n’ont pas été alertées';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE destinataire_id = v_soignant
      AND type_ressource = 'missions'
      AND id_ressource = '70000000-0000-4000-8000-000000000009'
  ) THEN
    RAISE EXCEPTION 'P1: aucune notification pour le dépassement effectif';
  END IF;

  -- Le même fait sur une mission réellement libérale ne relève pas des
  -- plafonds salariés, quelle que soit la profession portée par le profil.
  v_debut := ((v_base + (40 * 7))::timestamp + interval '8 hours')
    AT TIME ZONE 'Europe/Paris';
  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id, type_contrat_recherche,
    type_contrat_applique, choix_contrat_soignant, mode_attribution,
    debut_effectif, fin_effective, duree_heures_effective
  ) VALUES (
    '70000000-0000-4000-8000-000000000010',
    v_etab, 'Mission simple effective libérale', 'MEDECIN',
    v_debut, v_debut + interval '40 hours', 40, 50,
    'TERMINEE', v_medecin, 'LIBERAL', 'LIBERAL', 'LIBERAL', 'CANDIDATURE',
    v_debut, v_debut + interval '40 hours', 40
  );

  UPDATE public.missions
  SET duree_heures_effective = 80,
      fin_effective = v_debut + interval '80 hours'
  WHERE id = '70000000-0000-4000-8000-000000000010';

  IF EXISTS (
    SELECT 1 FROM public.conformite_travail
    WHERE mission_id = '70000000-0000-4000-8000-000000000010'
      AND details_violation->>'origine' = 'HEURES_EFFECTIVES_TERMINEES'
  ) THEN
    RAISE EXCEPTION 'P1: une mission réellement libérale est soumise au plafond salarié';
  END IF;
END;
$fixtures$;

ROLLBACK;
