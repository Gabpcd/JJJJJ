-- Seed des comptes de test Playwright (idempotent).
-- Date : 2026-05-03
--
-- Ces comptes permettent à la suite Playwright de se connecter sans
-- intervention manuelle de Gabrielle. Sans seed, les tests qui utilisent
-- TEST_ACCOUNTS.soignant / TEST_ACCOUNTS.etab skippent proprement.
--
-- Comptes créés / synchronisés :
--   - playwright-soignant@jolene.app (rôle SOIGNANT)
--   - playwright-etab@jolene.app     (rôle ADMIN_ETABLISSEMENT)
--
-- Password : "Playwright!Test2026" (hardcodé car compte de TEST uniquement,
-- pas de données réelles, accessible seulement via la suite E2E).
--
-- Idempotence :
--   - auth.users : UPDATE encrypted_password si compte existe, INSERT sinon
--   - soignants/etablissements : INSERT ON CONFLICT DO UPDATE pour synchro
--   - Re-exécution de la migration met à jour sans casser l'état

BEGIN;

-- ════════════════════════════════════════════════════════════════════
-- 1. Compte SOIGNANT test
-- ════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_soignant_id uuid;
  v_password_hash text := extensions.crypt('Playwright!Test2026', extensions.gen_salt('bf'));
BEGIN
  -- Récupérer ou créer le user auth
  SELECT id INTO v_soignant_id FROM auth.users WHERE email = 'playwright-soignant@jolene.app';

  IF v_soignant_id IS NULL THEN
    v_soignant_id := extensions.gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data
    ) VALUES (
      v_soignant_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'playwright-soignant@jolene.app',
      v_password_hash,
      now(), now(), now(),
      jsonb_build_object('provider', 'email', 'providers', ARRAY['email'], 'is_test_playwright', true),
      jsonb_build_object('role', 'SOIGNANT', 'prenom', 'Playwright', 'nom', 'TestSoignant')
    );

    -- Identité auth.identities (requise depuis Supabase 2024+)
    INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES (
      extensions.gen_random_uuid(),
      v_soignant_id,
      v_soignant_id::text,
      jsonb_build_object('sub', v_soignant_id::text, 'email', 'playwright-soignant@jolene.app', 'email_verified', true),
      'email',
      now(), now(), now()
    )
    ON CONFLICT DO NOTHING;
  ELSE
    -- Forcer le password connu + reset du flag is_test
    UPDATE auth.users
    SET encrypted_password = v_password_hash,
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        raw_app_meta_data = raw_app_meta_data || jsonb_build_object('is_test_playwright', true),
        updated_at = now()
    WHERE id = v_soignant_id;
  END IF;

  -- Profil soignant complet (idempotent via ON CONFLICT)
  INSERT INTO public.soignants (
    id, prenom, nom, email, telephone, profession,
    type_contrat, types_contrat_acceptes,
    adresse_rue, adresse_ville, adresse_code_postal, adresse_lat, adresse_lng,
    rayon_deplacement_km, annees_experience,
    tous_documents_valides, identite_verifiee, rpps_verifie, numero_rpps,
    score_fiabilite, total_missions_terminees, heures_cumulees,
    bio, date_naissance, est_compte_test,
    cree_le
  ) VALUES (
    v_soignant_id,
    'Playwright', 'TestSoignant', 'playwright-soignant@jolene.app', '+33600000001',
    'IDE', 'CDD', 'CDD,VACATION',
    '1 rue de Test', 'Paris', '75001', 48.8566, 2.3522,
    20, 5,
    true, true, true, '99999999999',
    50, 0, 0,
    'Compte test généré par migration Playwright (NE PAS UTILISER pour vraies missions).',
    '1990-01-01', true,
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    prenom = EXCLUDED.prenom,
    nom = EXCLUDED.nom,
    profession = EXCLUDED.profession,
    types_contrat_acceptes = EXCLUDED.types_contrat_acceptes,
    tous_documents_valides = true,
    identite_verifiee = true,
    rpps_verifie = true,
    est_compte_test = true,
    bio = EXCLUDED.bio;
END $$;

-- ════════════════════════════════════════════════════════════════════
-- 2. Compte ADMIN_ETABLISSEMENT test (avec onboarding complet)
-- ════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_etab_id uuid;
  v_password_hash text := extensions.crypt('Playwright!Test2026', extensions.gen_salt('bf'));
BEGIN
  SELECT id INTO v_etab_id FROM auth.users WHERE email = 'playwright-etab@jolene.app';

  IF v_etab_id IS NULL THEN
    v_etab_id := extensions.gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data
    ) VALUES (
      v_etab_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'playwright-etab@jolene.app',
      v_password_hash,
      now(), now(), now(),
      jsonb_build_object('provider', 'email', 'providers', ARRAY['email'], 'role', 'ADMIN_ETABLISSEMENT', 'is_test_playwright', true),
      jsonb_build_object('role', 'ADMIN_ETABLISSEMENT', 'nom', 'TestEtabPlaywright')
    );

    INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES (
      extensions.gen_random_uuid(),
      v_etab_id,
      v_etab_id::text,
      jsonb_build_object('sub', v_etab_id::text, 'email', 'playwright-etab@jolene.app', 'email_verified', true),
      'email',
      now(), now(), now()
    )
    ON CONFLICT DO NOTHING;
  ELSE
    UPDATE auth.users
    SET encrypted_password = v_password_hash,
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        raw_app_meta_data = raw_app_meta_data
          || jsonb_build_object('role', 'ADMIN_ETABLISSEMENT', 'is_test_playwright', true),
        updated_at = now()
    WHERE id = v_etab_id;
  END IF;

  -- Profil étab complet + onboarding marqué fait
  INSERT INTO public.etablissements (
    id, nom, siret, type,
    adresse_rue, adresse_ville, adresse_code_postal, adresse_lat, adresse_lng,
    email_contact, telephone_contact,
    contrat_service_signe, contrat_service_signe_le,
    rib_s3_key, est_compte_test,
    cree_le
  ) VALUES (
    v_etab_id,
    'Clinique Playwright Test',
    '99999999999999',
    'CLINIQUE_PRIVEE',
    '1 rue de Test', 'Paris', '75002', 48.8666, 2.3322,
    'playwright-etab@jolene.app', '+33100000001',
    true, now(),
    'playwright-test/seed/rib-fictif.pdf', true,
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    nom = EXCLUDED.nom,
    siret = EXCLUDED.siret,
    type = EXCLUDED.type,
    contrat_service_signe = true,
    contrat_service_signe_le = COALESCE(public.etablissements.contrat_service_signe_le, now()),
    est_compte_test = true,
    rib_s3_key = COALESCE(NULLIF(public.etablissements.rib_s3_key, 'legacy/auto-backfill'), 'playwright-test/seed/rib-fictif.pdf');
END $$;

COMMIT;
