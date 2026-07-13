-- Revalidation historique : scénarios transactionnels des critères par type.
-- Usage : psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--   -f tests/admin/security/historical-proof-backfill.test.sql
-- Prérequis : migrations appliquées au moins jusqu'à 20260713224000.

\set ON_ERROR_STOP on
BEGIN;

DO $fixture$
DECLARE
  v_diplome uuid := gen_random_uuid();
  v_adeli uuid := gen_random_uuid();
  v_corporate uuid := gen_random_uuid();
  v_identite_incomplete uuid := gen_random_uuid();
  v_numero_rpps text;
  v_numero_adeli text;
BEGIN
  v_numero_rpps := left('8' || regexp_replace(v_adeli::text, '[^0-9]', '', 'g') || repeat('0', 11), 11);
  v_numero_adeli := left('7' || regexp_replace(v_adeli::text, '[^0-9]', '', 'g') || repeat('0', 9), 9);

  INSERT INTO public.soignants(
    id, prenom, nom, email, date_naissance, profession, est_compte_test,
    numero_rpps, numero_adeli
  ) VALUES
    (
      v_diplome, 'Alice', 'Martin', 'backfill-diplome-' || v_diplome::text || '@test.local',
      DATE '1990-01-01', 'IDE', false, NULL, NULL
    ),
    (
      v_adeli, 'Benoit', 'Durand', 'backfill-adeli-' || v_adeli::text || '@test.local',
      DATE '1989-02-02', 'IDE', false, v_numero_rpps, v_numero_adeli
    ),
    (
      v_corporate, 'Claire', 'Bernard', 'backfill-corporate-' || v_corporate::text || '@test.local',
      DATE '1988-03-03', 'IDE', false, NULL, NULL
    ),
    (
      v_identite_incomplete, 'David', 'Petit',
      'backfill-identite-' || v_identite_incomplete::text || '@test.local',
      DATE '1987-04-04', 'IDE', false, NULL, NULL
    );

  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
    valide_jusqua, resultat_ia, nom_extrait_ia, prenom_extrait_ia,
    coherence_nom, verifie_le
  ) VALUES
    (
      v_diplome, 'DIPLOME', v_diplome::text || '/documents/diplome.pdf',
      'diplome.pdf', 'VERIFIE', DATE '2099-12-31',
      '{"profession_certifiee":"IADE"}', 'MARTIN', 'Alice', true, now()
    ),
    (
      v_adeli, 'RPPS_ADELI', v_adeli::text || '/documents/adeli.pdf',
      'adeli.pdf', 'VERIFIE', DATE '2099-12-31',
      jsonb_build_object(
        'type_identifiant_professionnel', 'ADELI',
        'numero_professionnel_extrait', v_numero_adeli
      ),
      'DURAND', 'Benoit', true, now()
    ),
    (
      v_corporate, 'KBIS', v_corporate::text || '/documents/kbis.pdf',
      'kbis.pdf', 'VERIFIE', DATE '2099-12-31', '{}', NULL, NULL, NULL, now()
    ),
    (
      v_identite_incomplete, 'CARTE_IDENTITE',
      v_identite_incomplete::text || '/documents/cni.pdf', 'cni.pdf',
      'VERIFIE', DATE '2099-12-31',
      '{"date_naissance_extraite":"1987-04-04"}', NULL, NULL, NULL, now()
    );
END;
$fixture$;

-- Réapplique le backfill dans la transaction pour tester ses prédicats réels.
\ir ../../../supabase/migrations/20260713224000_revalider_preuves_historiques_reelles.sql

DO $assertions$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.documents_soignants ds
    JOIN public.soignants s ON s.id = ds.soignant_id
    WHERE s.email LIKE 'backfill-diplome-%@test.local'
      AND ds.type_document = 'DIPLOME'
      AND ds.statut_verification <> 'VERIFIE'
  ) THEN
    RAISE EXCEPTION 'BACKFILL-T1: un diplôme IADE/IBODE doit rester compatible avec un profil IDE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.documents_soignants ds
    JOIN public.soignants s ON s.id = ds.soignant_id
    WHERE s.email LIKE 'backfill-adeli-%@test.local'
      AND ds.type_document = 'RPPS_ADELI'
      AND ds.statut_verification <> 'VERIFIE'
  ) THEN
    RAISE EXCEPTION 'BACKFILL-T2: ADELI a été comparé au RPPS au lieu de numero_adeli';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.documents_soignants ds
    JOIN public.soignants s ON s.id = ds.soignant_id
    WHERE s.email LIKE 'backfill-corporate-%@test.local'
      AND ds.type_document = 'KBIS'
      AND ds.statut_verification <> 'VERIFIE'
  ) THEN
    RAISE EXCEPTION 'BACKFILL-T3: un KBIS corporate a exigé un prénom de personne physique';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.documents_soignants ds
    JOIN public.soignants s ON s.id = ds.soignant_id
    WHERE s.email LIKE 'backfill-identite-%@test.local'
      AND ds.type_document = 'CARTE_IDENTITE'
      AND ds.statut_verification <> 'EN_ATTENTE'
  ) THEN
    RAISE EXCEPTION 'BACKFILL-T4: une pièce d’identité sans nom/prénom est restée vérifiée';
  END IF;
END;
$assertions$;

ROLLBACK;
