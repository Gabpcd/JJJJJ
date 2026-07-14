-- File RIB établissement : idempotence, snapshot borné et résolution.
-- Toutes les mutations sont annulées.

\set ON_ERROR_STOP on
BEGIN;

DO $rib_review_queue$
DECLARE
  v_etab_id constant uuid := 'a11c0000-0000-4000-8000-000000000011';
  v_etab public.etablissements%ROWTYPE;
  v_premiere jsonb;
  v_seconde jsonb;
  v_revue public.file_revue_manuelle%ROWTYPE;
  v_resolues integer;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Fixture transactionnelle file RIB établissement',
    true
  );

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_compte_test,
    verification_source_version, rib_s3_key
  ) VALUES (
    v_etab_id, 'Fixture file RIB établissement', '99140000000311',
    'CLINIQUE_PRIVEE', '5 rue du Test', 'Paris', '75005',
    'rib-review-etablissement@test.local', true, 7,
    v_etab_id::text || '/rib/fixture-file-revue.pdf'
  );

  PERFORM set_config('jolene.admin_seed_override_reason', '', true);

  SELECT * INTO v_etab
  FROM public.etablissements
  WHERE id = v_etab_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fixture dédiée de file RIB établissement absente';
  END IF;

  v_premiere := public.fn_ouvrir_revue_verification_etablissement(
    v_etab.id,
    'VERIFY_RIB_ETABLISSEMENT',
    'Le contrôle automatique du RIB est non concluant.',
    jsonb_build_object(
      'cause', 'AI_TIMEOUT',
      'verification_source_version', v_etab.verification_source_version,
      'rib_s3_key', v_etab.rib_s3_key,
      'rib_source_sha256_v1', repeat('a', 64),
      'iban_last4', '1234',
      'iban_fingerprint_sha256_v1', repeat('b', 64)
    ),
    4
  );
  v_seconde := public.fn_ouvrir_revue_verification_etablissement(
    v_etab.id,
    'VERIFY_RIB_ETABLISSEMENT',
    'Le contrôle automatique du RIB reste non concluant.',
    jsonb_build_object(
      'cause', 'AI_PARSE_ERROR',
      'verification_source_version', v_etab.verification_source_version,
      'rib_s3_key', v_etab.rib_s3_key,
      'rib_source_sha256_v1', repeat('a', 64),
      'iban_last4', '1234',
      'iban_fingerprint_sha256_v1', repeat('b', 64)
    ),
    4
  );

  IF v_premiere->>'success' IS DISTINCT FROM 'true'
     OR v_seconde->>'success' IS DISTINCT FROM 'true'
     OR v_premiere->>'revue_id' IS NULL
     OR v_premiere->>'revue_id' IS DISTINCT FROM v_seconde->>'revue_id' THEN
    RAISE EXCEPTION 'La revue RIB n’est pas idempotente: % / %', v_premiere, v_seconde;
  END IF;

  SELECT * INTO v_revue
  FROM public.file_revue_manuelle
  WHERE id = (v_premiere->>'revue_id')::uuid;
  IF NOT FOUND
     OR v_revue.type_entite IS DISTINCT FROM 'ETABLISSEMENT'
     OR v_revue.id_entite IS DISTINCT FROM v_etab.id
     OR v_revue.service_en_echec IS DISTINCT FROM 'VERIFY_RIB_ETABLISSEMENT'
     OR v_revue.statut IS DISTINCT FROM 'EN_ATTENTE'
     OR (v_revue.donnees_originales->>'verification_source_version')::bigint
          IS DISTINCT FROM v_etab.verification_source_version
     OR v_revue.donnees_originales->>'rib_s3_key'
          IS DISTINCT FROM v_etab.rib_s3_key
     OR v_revue.donnees_originales ? 'iban'
     OR v_revue.donnees_originales ? 'iban_extrait' THEN
    RAISE EXCEPTION 'Snapshot de revue RIB invalide ou sensible: %', v_revue.donnees_originales;
  END IF;

  v_resolues := public.fn_resoudre_revue_verification_etablissement(
    v_etab.id,
    'VERIFY_RIB_ETABLISSEMENT'
  );
  IF v_resolues IS DISTINCT FROM 1 OR NOT EXISTS (
    SELECT 1 FROM public.file_revue_manuelle
    WHERE id = v_revue.id AND statut = 'RESOLU_AUTO' AND resolu_le IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Résolution automatique de la revue RIB invalide';
  END IF;
END;
$rib_review_queue$;

ROLLBACK;
