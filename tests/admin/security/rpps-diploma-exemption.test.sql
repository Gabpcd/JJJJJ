-- Règle métier documentaire : un RPPS validé par l'API dispense du diplôme
-- uniquement pour les professions à RPPS. Toutes les écritures sont annulées.

\set ON_ERROR_STOP on
BEGIN;

DO $rpps_diploma$
DECLARE
  v_ide uuid := gen_random_uuid();
  v_as uuid := gen_random_uuid();
  v_rpps text := '1' || right(
    lpad(regexp_replace(gen_random_uuid()::text, '[^0-9]', '', 'g'), 10, '0'),
    10
  );
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  INSERT INTO public.soignants(
    id, prenom, nom, email, date_naissance, profession, type_exercice,
    rpps_verifie, adeli_verifie, est_compte_test
  ) VALUES (
    v_ide, 'Camille', 'RppsTest',
    'rpps-diploma-' || v_ide::text || '@test.local', DATE '1990-01-01',
    'IDE', 'SALARIE', false, false, true
  );

  -- Installe toutes les preuves critiques salariées sauf celles que le RPPS
  -- peut remplacer. Le diplôme reste volontairement absent.
  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier,
    statut_verification, valide_depuis, valide_jusqua, verifie_le,
    resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom
  )
  SELECT
    v_ide,
    drp.type_document,
    v_ide::text || '/documents/' || lower(drp.type_document::text) || '.pdf',
    lower(drp.type_document::text) || '.pdf',
    'VERIFIE',
    current_date,
    CASE WHEN drp.a_expiration THEN current_date + 365 ELSE NULL END,
    now(),
    CASE
      WHEN drp.type_document = 'CARTE_IDENTITE'
        THEN jsonb_build_object('date_naissance_extraite', '1990-01-01')
      ELSE '{}'::jsonb
    END,
    'RPPSTEST',
    'Camille',
    true
  FROM public.documents_requis_par_profession drp
  WHERE drp.profession = 'IDE'
    AND drp.est_critique IS TRUE
    AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
    AND drp.type_document NOT IN ('DIPLOME', 'RPPS_ADELI');

  IF EXISTS (
    SELECT 1
    FROM public.documents_soignants
    WHERE soignant_id = v_ide AND type_document = 'DIPLOME'
  ) THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T0: le fixture contient un diplôme';
  END IF;

  UPDATE public.soignants
  SET numero_rpps = v_rpps,
      rpps_verifie = true,
      rpps_verifie_le = now(),
      rpps_nom_api = 'RPPSTEST',
      rpps_prenom_api = 'Camille',
      rpps_profession_api = 'IDE'
  WHERE id = v_ide;

  IF public.fn_documents_ok_pour_mission(v_ide, 'SALARIE') IS NOT TRUE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T1: le RPPS validé ne dispense pas du diplôme';
  END IF;
  IF (SELECT tous_documents_valides FROM public.soignants WHERE id = v_ide) IS NOT TRUE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T2: le cache n''a pas été recalculé après validation RPPS';
  END IF;

  -- ADELI seul dispense de la ligne RPPS_ADELI, mais pas du diplôme.
  UPDATE public.soignants
  SET rpps_verifie = false,
      rpps_verifie_le = NULL,
      adeli_verifie = true,
      adeli_verifie_le = now()
  WHERE id = v_ide;

  IF public.fn_documents_ok_pour_mission(v_ide, 'SALARIE') IS NOT FALSE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T3: ADELI seul a dispensé du diplôme';
  END IF;
  IF (SELECT tous_documents_valides FROM public.soignants WHERE id = v_ide) IS NOT FALSE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T4: le cache n''a pas été invalidé à la révocation RPPS';
  END IF;

  -- Défense en profondeur : une profession sans RPPS ne bénéficie jamais de
  -- la dispense, même si une donnée incohérente positionne rpps_verifie=true.
  INSERT INTO public.soignants(
    id, prenom, nom, email, date_naissance, profession, type_exercice,
    rpps_verifie, est_compte_test
  ) VALUES (
    v_as, 'Alex', 'SansRpps',
    'sans-rpps-diploma-' || v_as::text || '@test.local', DATE '1991-02-02',
    'AS', 'SALARIE', false, true
  );

  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier,
    statut_verification, valide_depuis, valide_jusqua, verifie_le,
    resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom
  )
  SELECT
    v_as,
    drp.type_document,
    v_as::text || '/documents/' || lower(drp.type_document::text) || '.pdf',
    lower(drp.type_document::text) || '.pdf',
    'VERIFIE',
    current_date,
    CASE WHEN drp.a_expiration THEN current_date + 365 ELSE NULL END,
    now(),
    CASE
      WHEN drp.type_document = 'CARTE_IDENTITE'
        THEN jsonb_build_object('date_naissance_extraite', '1991-02-02')
      ELSE '{}'::jsonb
    END,
    'SANSRPPS',
    'Alex',
    true
  FROM public.documents_requis_par_profession drp
  WHERE drp.profession = 'AS'
    AND drp.est_critique IS TRUE
    AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
    AND drp.type_document <> 'DIPLOME';

  UPDATE public.soignants
  SET rpps_verifie = true,
      rpps_verifie_le = now()
  WHERE id = v_as;

  IF public.fn_documents_ok_pour_mission(v_as, 'SALARIE') IS NOT FALSE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T5: une profession sans RPPS a été dispensée du diplôme';
  END IF;
END;
$rpps_diploma$;

ROLLBACK;
