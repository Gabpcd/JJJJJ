-- Suspension admin réellement opposable aux JWT déjà émis.
-- Transactionnel : toutes les fixtures sont annulées en fin de suite.
BEGIN;

DO $fixtures$
DECLARE
  v_admin uuid := '68000000-0000-4000-8000-000000000001';
  v_soignant uuid := '68000000-0000-4000-8000-000000000002';
  v_etab uuid := '68000000-0000-4000-8000-000000000003';
  v_membre uuid := '68000000-0000-4000-8000-000000000004';
  v_mission uuid := '68000000-0000-4000-8000-000000000005';
  v_rgpd uuid := '68000000-0000-4000-8000-000000000006';
  v_mission_finance uuid := '68000000-0000-4000-8000-000000000007';
  v_mission_invalide uuid := '68000000-0000-4000-8000-000000000008';
  v_finance record;
  v_erreur text;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_admin, '00000000-0000-0000-0000-000000000000',
      'suspension-admin@test.local', 'authenticated', 'authenticated',
      '{"role":"ADMIN_PLATEFORME"}', now()
    ),
    (
      v_soignant, '00000000-0000-0000-0000-000000000000',
      'suspension-soignant@test.local', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}', now()
    ),
    (
      v_etab, '00000000-0000-0000-0000-000000000000',
      'suspension-etab@test.local', 'authenticated', 'authenticated',
      '{"role":"ADMIN_ETABLISSEMENT"}', now()
    ),
    (
      v_membre, '00000000-0000-0000-0000-000000000000',
      'suspension-membre@test.local', 'authenticated', 'authenticated',
      '{"role":"ETABLISSEMENT"}', now()
    ),
    (
      v_rgpd, '00000000-0000-0000-0000-000000000000',
      'rgpd-supprime@test.local', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}', now()
    );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test
  ) VALUES (
    v_soignant, 'Test', 'Suspension', 'suspension-soignant@test.local', 'IDE', true
  ), (
    v_rgpd, 'Soignant', 'Supprimé',
    'fixture-rgpd@supprime.jolene.app', 'IDE', true
  );

  UPDATE public.soignants
  SET supprime_le = now()
  WHERE id = v_rgpd;

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin, 'Suspension', 'Admin', 'suspension-admin@test.local', true,
    ARRAY[
      'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
      'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur'
    ]::text[]
  );

  INSERT INTO public.etablissements (
    id, nom, siret, finess, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, statut_verification,
    peut_publier_missions, siret_verifie, finess_verifie,
    representant_identite_verifiee, rattachement_verifie,
    contrat_service_signe, est_compte_test,
    taux_majoration_nuit_pourcent,
    taux_majoration_dimanche_pourcent,
    taux_majoration_ferie_pourcent
  ) VALUES (
    v_etab, 'Établissement suspension', '68000000000003', '680000003',
    'CLINIQUE_PRIVEE', '1 rue du Test', 'Paris', '75001',
    'suspension-etab@test.local', 'VERIFIE', true, true, true,
    true, true, true, true, 25, 25, 50
  );

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, actif
  ) VALUES (v_etab, v_membre, 'RH', true);

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, type_contrat_recherche, mode_attribution,
    soignant_assigne_id, type_contrat_applique, taux_commission_fige,
    total_brut, net_a_payer
  ) VALUES
    (
      v_mission, v_etab, 'Mission test suspension', 'IDE',
      now() + interval '2 days', now() + interval '2 days 8 hours',
      8, 20, 'OUVERTE', 'SALARIE', 'CANDIDATURE',
      NULL, NULL, NULL, NULL, NULL
    ),
    (
      v_mission_finance, v_etab, 'Mission test finance canonique', 'IDE',
      '2035-06-18 09:00:00+02'::timestamptz,
      '2035-06-18 17:00:00+02'::timestamptz,
      8, 20, 'TERMINEE', 'SALARIE', 'CANDIDATURE',
      v_soignant, 'SALARIE', 15, 160.00, 193.60
    );

  SELECT
    m.total_brut,
    m.montant_ifm,
    m.montant_icp,
    m.net_a_payer,
    m.taux_commission,
    m.montant_commission_ht,
    m.montant_commission_tva,
    m.montant_commission_ttc
  INTO v_finance
  FROM public.missions m
  WHERE m.id = v_mission_finance;

  IF v_finance.total_brut IS DISTINCT FROM 160.00::numeric
     OR v_finance.montant_ifm IS DISTINCT FROM 16.00::numeric
     OR v_finance.montant_icp IS DISTINCT FROM 17.60::numeric
     OR v_finance.net_a_payer IS DISTINCT FROM 193.60::numeric
     OR v_finance.taux_commission IS DISTINCT FROM 15.00::numeric
     OR v_finance.montant_commission_ht IS DISTINCT FROM 29.04::numeric
     OR v_finance.montant_commission_tva IS DISTINCT FROM 5.81::numeric
     OR v_finance.montant_commission_ttc IS DISTINCT FROM 34.85::numeric
     OR v_finance.net_a_payer + v_finance.montant_commission_ttc
          IS DISTINCT FROM 228.45::numeric THEN
    RAISE EXCEPTION 'Chaîne finance/commission non canonique : %',
      row_to_json(v_finance);
  END IF;

  -- L'ancienne formule retranchait 15 % du dû soignant (193,60 - 29,04).
  -- Ce snapshot doit être refusé avant que le moteur ne puisse le réécrire.
  BEGIN
    INSERT INTO public.missions (
      id, etablissement_id, intitule, profession_requise,
      debut_le, fin_le, duree_heures, taux_horaire_base,
      statut, type_contrat_recherche, mode_attribution,
      taux_commission_fige, total_brut, net_a_payer
    ) VALUES (
      v_mission_invalide, v_etab, 'Mission commission déduite interdite', 'IDE',
      '2035-06-19 09:00:00+02'::timestamptz,
      '2035-06-19 17:00:00+02'::timestamptz,
      8, 20, 'TERMINEE', 'SALARIE', 'CANDIDATURE',
      15, 160.00, 164.56
    );
    RAISE EXCEPTION 'Le snapshot avec commission déduite a été accepté';
  EXCEPTION WHEN SQLSTATE '23514' THEN
    GET STACKED DIAGNOSTICS v_erreur = MESSAGE_TEXT;
    IF v_erreur NOT LIKE 'anti-seed mission: net_a_payer %' THEN
      RAISE;
    END IF;
  END;
END;
$fixtures$;

DO $pre_request_configure$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles r,
         unnest(COALESCE(r.rolconfig, ARRAY[]::text[])) AS c(config)
    WHERE r.rolname = 'authenticator'
      AND c.config = 'pgrst.db_pre_request=public.fn_pre_request_compte_actif'
  ) THEN
    RAISE EXCEPTION 'P0: le hook global PostgREST n’est pas configuré';
  END IF;
END;
$pre_request_configure$;

SET LOCAL ROLE authenticated;

-- AAL1 ne peut jamais suspendre.
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"68000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);
DO $aal1$
DECLARE v_resultat jsonb;
BEGIN
  SELECT public.fn_admin_suspendre_utilisateur(
    'soignants', '68000000-0000-4000-8000-000000000002', true, 'Contrôle sécurité'
  ) INTO v_resultat;
  IF (v_resultat->>'success' = 'true') IS TRUE
     OR NULLIF(v_resultat->>'error', '') IS NULL THEN
    RAISE EXCEPTION 'P0: une session admin AAL1 peut suspendre un compte';
  END IF;
END;
$aal1$;

-- AAL2 suspend le profil et le compte Auth dans la même transaction.
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"68000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);
DO $suspendre_soignant$
DECLARE v_resultat jsonb;
BEGIN
  SELECT public.fn_admin_suspendre_utilisateur(
    'soignants', '68000000-0000-4000-8000-000000000002', true, 'Contrôle sécurité'
  ) INTO v_resultat;
  IF v_resultat->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Suspension soignant échouée: %', v_resultat;
  END IF;
END;
$suspendre_soignant$;

RESET ROLE;
DO $etat_suspendu$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = '68000000-0000-4000-8000-000000000002'
      AND banned_until > now()
  ) THEN
    RAISE EXCEPTION 'P0: le bannissement Auth n’a pas été posé';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = '68000000-0000-4000-8000-000000000002'
      AND supprime_le IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'P0: le profil soignant n’a pas été suspendu';
  END IF;
END;
$etat_suspendu$;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"68000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}',
  true
);
DO $jwt_suspendu$
BEGIN
  IF public.fn_compte_auth_actif() IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'P0: le JWT déjà émis reste actif après suspension';
  END IF;
  BEGIN
    PERFORM public.fn_pre_request_compte_actif();
    RAISE EXCEPTION 'P0: le hook Data API accepte un JWT suspendu';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
  IF public.fn_peut_deposer_justificatif(
       '68000000-0000-4000-8000-000000000002/preuve.pdf'
     ) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'P0: Storage accepte encore un dépôt du compte suspendu';
  END IF;
  IF public.fn_peut_lire_justificatif(
       '68000000-0000-4000-8000-000000000002/preuve.pdf'
     ) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'P0: Storage accepte encore une lecture du compte suspendu';
  END IF;
  BEGIN
    INSERT INTO public.candidatures (mission_id, soignant_id, statut)
    VALUES (
      '68000000-0000-4000-8000-000000000005',
      '68000000-0000-4000-8000-000000000002',
      'EN_ATTENTE'
    );
    RAISE EXCEPTION 'P0: le compte suspendu peut encore candidater';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$jwt_suspendu$;

-- Une suspension répétée doit faire suivre la valeur CAS réellement posée,
-- tout en conservant l'état Auth d'origine.
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"68000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);
DO $suspension_repetee$
DECLARE
  v_resultat jsonb;
BEGIN
  SELECT public.fn_admin_suspendre_utilisateur(
    'soignants', '68000000-0000-4000-8000-000000000002', true,
    'Contrôle sécurité répété'
  ) INTO v_resultat;
  IF v_resultat->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Suspension répétée échouée: %', v_resultat;
  END IF;
END;
$suspension_repetee$;

RESET ROLE;
DO $cas_repetition$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.suspensions_auth_admin sa
    JOIN auth.users u ON u.id = sa.user_id
    WHERE sa.type_ressource = 'soignants'
      AND sa.id_ressource = '68000000-0000-4000-8000-000000000002'
      AND u.banned_until IS NOT DISTINCT FROM sa.banned_until_pose
  ) THEN
    RAISE EXCEPTION 'P0: provenance CAS désynchronisée après suspension répétée';
  END IF;
END;
$cas_repetition$;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"68000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);

-- Réactivation : enlève uniquement le ban créé par Jolene.
DO $reactiver_soignant$
DECLARE v_resultat jsonb;
BEGIN
  SELECT public.fn_admin_suspendre_utilisateur(
    'soignants', '68000000-0000-4000-8000-000000000002', false, NULL
  ) INTO v_resultat;
  IF v_resultat->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Réactivation soignant échouée: %', v_resultat;
  END IF;
END;
$reactiver_soignant$;

RESET ROLE;
DO $etat_reactive$
BEGIN
  IF EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = '68000000-0000-4000-8000-000000000002'
      AND banned_until > now()
  ) OR EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = '68000000-0000-4000-8000-000000000002'
      AND supprime_le IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'P0: état soignant non restauré';
  END IF;
END;
$etat_reactive$;

-- Un effacement RGPD ne devient jamais réversible via le bouton admin.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"68000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);
DO $refuser_reactivation_rgpd$
DECLARE v_resultat jsonb;
BEGIN
  SELECT public.fn_admin_suspendre_utilisateur(
    'soignants', '68000000-0000-4000-8000-000000000006', false, NULL
  ) INTO v_resultat;
  IF v_resultat->>'error' IS NULL THEN
    RAISE EXCEPTION 'P0: une suppression RGPD peut être réactivée';
  END IF;

  SELECT public.fn_admin_suspendre_utilisateur(
    'soignants', '68000000-0000-4000-8000-000000000006', true,
    'Tentative interdite'
  ) INTO v_resultat;
  IF v_resultat->>'error' IS NULL THEN
    RAISE EXCEPTION 'P0: une suppression RGPD peut être convertie en suspension';
  END IF;
END;
$refuser_reactivation_rgpd$;

RESET ROLE;
DO $rgpd_intact$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = '68000000-0000-4000-8000-000000000006'
      AND supprime_le IS NOT NULL
      AND email LIKE '%@supprime.jolene.app'
  ) OR EXISTS (
    SELECT 1 FROM public.suspensions_profils_admin
    WHERE type_ressource = 'soignants'
      AND id_ressource = '68000000-0000-4000-8000-000000000006'
  ) THEN
    RAISE EXCEPTION 'P0: la preuve RGPD a été altérée';
  END IF;
END;
$rgpd_intact$;

-- Un établissement suspend son compte principal et toutes ses appartenances,
-- puis restaure uniquement les états archivés si aucun autre gel n’existe.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"68000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);
DO $cycle_etablissement$
DECLARE v_resultat jsonb;
BEGIN
  SELECT public.fn_admin_suspendre_utilisateur(
    'etablissements', '68000000-0000-4000-8000-000000000003', true, 'Contrôle établissement'
  ) INTO v_resultat;
  IF v_resultat->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Suspension établissement échouée: %', v_resultat;
  END IF;
END;
$cycle_etablissement$;

RESET ROLE;
DO $etablissement_suspendu$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = '68000000-0000-4000-8000-000000000003'
      AND banned_until > now()
  ) OR EXISTS (
    SELECT 1 FROM public.membres_etablissement
    WHERE etablissement_id = '68000000-0000-4000-8000-000000000003'
      AND actif IS DISTINCT FROM FALSE
  ) OR EXISTS (
    SELECT 1 FROM public.etablissements
    WHERE id = '68000000-0000-4000-8000-000000000003'
      AND (
        supprime_le IS NULL
        OR peut_publier_missions IS DISTINCT FROM FALSE
      )
  ) THEN
    RAISE EXCEPTION 'P0: suspension établissement incomplète';
  END IF;
END;
$etablissement_suspendu$;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"68000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);
DO $reactiver_etablissement$
DECLARE v_resultat jsonb;
BEGIN
  SELECT public.fn_admin_suspendre_utilisateur(
    'etablissements', '68000000-0000-4000-8000-000000000003', false, NULL
  ) INTO v_resultat;
  IF v_resultat->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Réactivation établissement échouée: %', v_resultat;
  END IF;
END;
$reactiver_etablissement$;

RESET ROLE;
DO $etablissement_reactive$
BEGIN
  IF EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = '68000000-0000-4000-8000-000000000003'
      AND banned_until > now()
  ) OR NOT EXISTS (
    SELECT 1 FROM public.membres_etablissement
    WHERE etablissement_id = '68000000-0000-4000-8000-000000000003'
      AND user_id = '68000000-0000-4000-8000-000000000004'
      AND actif IS TRUE
  ) OR NOT EXISTS (
    SELECT 1 FROM public.etablissements
    WHERE id = '68000000-0000-4000-8000-000000000003'
      AND supprime_le IS NULL
      AND peut_publier_missions IS TRUE
  ) THEN
    RAISE EXCEPTION 'P0: réactivation établissement non fidèle';
  END IF;
END;
$etablissement_reactive$;

ROLLBACK;
