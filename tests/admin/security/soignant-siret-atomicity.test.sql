-- Vérification transactionnelle de la garde anti-TOCTOU du SIRET libéral.
-- Usage : psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--   -f tests/admin/security/soignant-siret-atomicity.test.sql

\set ON_ERROR_STOP on
BEGIN;

DO $test$
DECLARE
  v_soignant uuid := gen_random_uuid();
  v_applique boolean;
BEGIN
  INSERT INTO public.soignants(
    id, prenom, nom, email, date_naissance, profession,
    siret_liberal, statut_liberal, type_contrat
  ) VALUES (
    v_soignant, 'Marie', 'Lefèvre',
    'siret-atomic-' || v_soignant::text || '@test.local',
    DATE '1990-05-12', 'IDE', NULL, 'NON_LIBERAL', 'CDD'
  );

  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'role', 'service_role',
    'sub', '00000000-0000-0000-0000-000000000000'
  )::text, true);

  -- Un changement de nom intervenu pendant l'appel registre invalide le
  -- snapshot et ne doit activer aucune preuve.
  UPDATE public.soignants SET nom = 'Martin' WHERE id = v_soignant;
  v_applique := public.fn_appliquer_verification_siret_soignant(
    v_soignant, 'Marie', 'Lefèvre', DATE '1990-05-12', NULL,
    'NON_LIBERAL', 'CDD', '73282932000074', 'MARIE LEFEVRE'
  );
  IF v_applique IS TRUE THEN
    RAISE EXCEPTION 'SIRET-ATOMIC-T1: le snapshot identité périmé a été accepté';
  END IF;
  IF (SELECT siret_liberal_verifie FROM public.soignants WHERE id = v_soignant) IS TRUE THEN
    RAISE EXCEPTION 'SIRET-ATOMIC-T2: une preuve périmée a été activée';
  END IF;

  -- Avec le snapshot courant complet, preuve et SIRET sont appliqués dans la
  -- même transaction.
  v_applique := public.fn_appliquer_verification_siret_soignant(
    v_soignant, 'Marie', 'Martin', DATE '1990-05-12', NULL,
    'NON_LIBERAL', 'CDD', '73282932000074', 'MARIE MARTIN'
  );
  IF v_applique IS NOT TRUE THEN
    RAISE EXCEPTION 'SIRET-ATOMIC-T3: le snapshot courant a été refusé';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = v_soignant
      AND siret_liberal = '73282932000074'
      AND statut_liberal = 'EN_COURS'
      AND siret_liberal_verifie IS TRUE
      AND siret_liberal_verifie_le IS NOT NULL
      AND siret_liberal_coherence_identite IS TRUE
  ) THEN
    RAISE EXCEPTION 'SIRET-ATOMIC-T4: la preuve complète n''a pas été persistée';
  END IF;

  -- Une source SIRET modifiée après snapshot échoue également fermé.
  UPDATE public.soignants
  SET siret_liberal = '55210055400013',
      siret_liberal_verifie = false,
      siret_liberal_verifie_le = NULL,
      siret_liberal_coherence_identite = NULL,
      statut_liberal = 'EN_COURS'
  WHERE id = v_soignant;
  v_applique := public.fn_appliquer_verification_siret_soignant(
    v_soignant, 'Marie', 'Martin', DATE '1990-05-12', '73282932000074',
    'EN_COURS', 'CDD', '73282932000074', 'MARIE MARTIN'
  );
  IF v_applique IS TRUE THEN
    RAISE EXCEPTION 'SIRET-ATOMIC-T5: le snapshot SIRET périmé a été accepté';
  END IF;

  -- La RPC refuse aussi une date de naissance absente, même sous service_role.
  BEGIN
    PERFORM public.fn_appliquer_verification_siret_soignant(
      v_soignant, 'Marie', 'Martin', NULL, '55210055400013',
      'EN_COURS', 'CDD', '55210055400013', 'MARIE MARTIN'
    );
    RAISE EXCEPTION 'SIRET-ATOMIC-T6: une date absente a été acceptée';
  EXCEPTION
    WHEN SQLSTATE '22023' THEN NULL;
  END;
END;
$test$;

ROLLBACK;
